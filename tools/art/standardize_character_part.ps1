param(
    [Parameter(Mandatory = $true)]
    [string]$Source,

    [Parameter(Mandatory = $true)]
    [string]$Output,

    [Parameter(Mandatory = $true)]
    [ValidateSet("body", "head", "hair", "outfit", "accessory", "held_item")]
    [string]$Part,

    [string]$AssetId = "",

    [string]$AdjustmentsPath = "",

    [string]$BatchId = "",

    [string]$BatchAdjustmentsPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Drawing

function New-TargetRegion {
    param([string]$Part)

    [void]$Part
    return [PSCustomObject]@{
        X = 0
        Y = 0
        Width = 256
        Height = 256
        Align = "center"
    }
}

function Get-AssetAdjustment {
    param(
        [string]$AdjustmentsPath,
        [string]$Id
    )

    if ([string]::IsNullOrWhiteSpace($AdjustmentsPath) -or [string]::IsNullOrWhiteSpace($Id)) {
        return $null
    }

    if (-not (Test-Path -LiteralPath $AdjustmentsPath)) {
        throw "Adjustment table not found: $AdjustmentsPath"
    }

    $extension = [System.IO.Path]::GetExtension($AdjustmentsPath).ToLowerInvariant()
    if ($extension -ne ".json") {
        throw "Adjustment table must be JSON to avoid Godot CSV translation imports: $AdjustmentsPath"
    }

    $rows = Get-Content -Encoding UTF8 -Raw -LiteralPath $AdjustmentsPath | ConvertFrom-Json
    if ($rows.PSObject.Properties["value"] -and $rows.PSObject.Properties["Count"]) {
        $rows = $rows.value
    }
    elseif ($rows.PSObject.Properties["SyncRoot"] -and $rows.PSObject.Properties["Count"]) {
        $rows = $rows.SyncRoot
    }
    $row = $rows | Where-Object { $_.asset_id -eq $Id } | Select-Object -First 1
    if ($null -eq $row) {
        return $null
    }

    return $row
}

function Get-BatchAdjustment {
    param(
        [string]$AdjustmentsPath,
        [string]$Id,
        [string]$Part
    )

    if ([string]::IsNullOrWhiteSpace($AdjustmentsPath) -or [string]::IsNullOrWhiteSpace($Id)) {
        return $null
    }

    if (-not (Test-Path -LiteralPath $AdjustmentsPath)) {
        throw "Batch adjustment table not found: $AdjustmentsPath"
    }

    $extension = [System.IO.Path]::GetExtension($AdjustmentsPath).ToLowerInvariant()
    if ($extension -ne ".json") {
        throw "Batch adjustment table must be JSON to avoid Godot CSV translation imports: $AdjustmentsPath"
    }

    $rows = Get-Content -Encoding UTF8 -Raw -LiteralPath $AdjustmentsPath | ConvertFrom-Json
    if ($rows.PSObject.Properties["value"] -and $rows.PSObject.Properties["Count"]) {
        $rows = $rows.value
    }
    elseif ($rows.PSObject.Properties["SyncRoot"] -and $rows.PSObject.Properties["Count"]) {
        $rows = $rows.SyncRoot
    }

    $row = $rows |
        Where-Object {
            $_.batch_id -eq $Id -and
            ([string]::IsNullOrWhiteSpace([string]$_.standard_part) -or $_.standard_part -eq $Part)
        } |
        Select-Object -First 1
    if ($null -eq $row) {
        return $null
    }

    return $row
}

function Get-AdjustmentNumber {
    param(
        [object]$Adjustment,
        [string]$Name,
        [double]$DefaultValue
    )

    if ($null -eq $Adjustment) {
        return $DefaultValue
    }

    $value = $Adjustment.$Name
    if ([string]::IsNullOrWhiteSpace([string]$value)) {
        return $DefaultValue
    }

    return [double]$value
}

function Get-AdjustmentString {
    param(
        [object]$Adjustment,
        [string]$Name,
        [string]$DefaultValue
    )

    if ($null -eq $Adjustment) {
        return $DefaultValue
    }

    $value = [string]$Adjustment.$Name
    if ([string]::IsNullOrWhiteSpace($value)) {
        return $DefaultValue
    }

    return $value
}

function Apply-AssetAdjustment {
    param(
        [object]$Region,
        [object]$Adjustment
    )

    if ($null -eq $Adjustment) {
        return $Region
    }

    $defaultOffsetX = if ($Region.PSObject.Properties["OffsetX"]) { [double]$Region.OffsetX } else { 0.0 }
    $defaultOffsetY = if ($Region.PSObject.Properties["OffsetY"]) { [double]$Region.OffsetY } else { 0.0 }
    $defaultScale = if ($Region.PSObject.Properties["Scale"]) { [double]$Region.Scale } else { 1.0 }

    $adjusted = [PSCustomObject]@{
        X = [int][Math]::Round((Get-AdjustmentNumber -Adjustment $Adjustment -Name "target_x" -DefaultValue $Region.X))
        Y = [int][Math]::Round((Get-AdjustmentNumber -Adjustment $Adjustment -Name "target_y" -DefaultValue $Region.Y))
        Width = [int][Math]::Round((Get-AdjustmentNumber -Adjustment $Adjustment -Name "target_width" -DefaultValue $Region.Width))
        Height = [int][Math]::Round((Get-AdjustmentNumber -Adjustment $Adjustment -Name "target_height" -DefaultValue $Region.Height))
        Align = Get-AdjustmentString -Adjustment $Adjustment -Name "align" -DefaultValue $Region.Align
        OffsetX = Get-AdjustmentNumber -Adjustment $Adjustment -Name "offset_x" -DefaultValue $defaultOffsetX
        OffsetY = Get-AdjustmentNumber -Adjustment $Adjustment -Name "offset_y" -DefaultValue $defaultOffsetY
        Scale = Get-AdjustmentNumber -Adjustment $Adjustment -Name "scale" -DefaultValue $defaultScale
    }

    if ($adjusted.Width -le 0 -or $adjusted.Height -le 0) {
        throw "Adjustment for '$AssetId' produced invalid target size."
    }

    if ($adjusted.Scale -le 0) {
        throw "Adjustment for '$AssetId' produced invalid scale."
    }

    return $adjusted
}

function Save-Png {
    param(
        [System.Drawing.Bitmap]$Image,
        [string]$Path
    )

    $directory = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($directory)) {
        New-Item -ItemType Directory -Force -Path $directory | Out-Null
    }

    $Image.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
}

$resolvedSource = (Resolve-Path -LiteralPath $Source).Path
$resolvedOutput = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Output)

$sourceImage = [System.Drawing.Bitmap]::FromFile($resolvedSource)
$targetImage = New-Object System.Drawing.Bitmap 256, 256, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)

try {
    $bounds = New-Object System.Drawing.Rectangle 0, 0, $sourceImage.Width, $sourceImage.Height
    $batchAdjustment = Get-BatchAdjustment -AdjustmentsPath $BatchAdjustmentsPath -Id $BatchId -Part $Part
    $assetAdjustment = Get-AssetAdjustment -AdjustmentsPath $AdjustmentsPath -Id $AssetId
    $region = New-TargetRegion -Part $Part
    $appliedAdjustments = @()
    if ($null -ne $batchAdjustment) {
        $region = Apply-AssetAdjustment -Region $region -Adjustment $batchAdjustment
        $appliedAdjustments += "batch=$BatchId offset=$($region.OffsetX),$($region.OffsetY) scale=$($region.Scale)"
    }
    if ($null -ne $assetAdjustment) {
        $region = Apply-AssetAdjustment -Region $region -Adjustment $assetAdjustment
        $appliedAdjustments += "asset=$AssetId offset=$($region.OffsetX),$($region.OffsetY) scale=$($region.Scale)"
    }
    $scale = [Math]::Min(
        [double]$region.Width / [double]$bounds.Width,
        [double]$region.Height / [double]$bounds.Height
    ) * [double]$region.Scale
    $destWidth = [Math]::Max(1, [int][Math]::Round($bounds.Width * $scale))
    $destHeight = [Math]::Max(1, [int][Math]::Round($bounds.Height * $scale))
    $destX = [int][Math]::Round($region.X + ($region.Width - $destWidth) * 0.5)
    $destY = [int][Math]::Round($region.Y + ($region.Height - $destHeight) * 0.5)

    if ($region.Align -eq "bottom") {
        $destY = [int][Math]::Round($region.Y + $region.Height - $destHeight)
    }

    $destX = [int][Math]::Round($destX + $region.OffsetX)
    $destY = [int][Math]::Round($destY + $region.OffsetY)

    $graphics = [System.Drawing.Graphics]::FromImage($targetImage)
    try {
        $graphics.Clear([System.Drawing.Color]::FromArgb(0, 0, 0, 0))
        $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceOver
        $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality

        $destRect = New-Object System.Drawing.Rectangle $destX, $destY, $destWidth, $destHeight
        $graphics.DrawImage($sourceImage, $destRect, $bounds, [System.Drawing.GraphicsUnit]::Pixel)
    }
    finally {
        $graphics.Dispose()
    }

    Save-Png -Image $targetImage -Path $resolvedOutput

    [PSCustomObject]@{
        Source = $resolvedSource
        Output = $resolvedOutput
        Part = $Part
        SourceBounds = "$($bounds.X),$($bounds.Y),$($bounds.Width),$($bounds.Height)"
        TargetRegion = "$($region.X),$($region.Y),$($region.Width),$($region.Height)"
        DestRect = "$destX,$destY,$destWidth,$destHeight"
        Adjustment = $appliedAdjustments -join "; "
        Canvas = "256x256"
        Anchor = "128,184"
    }
}
finally {
    $sourceImage.Dispose()
    $targetImage.Dispose()
}
