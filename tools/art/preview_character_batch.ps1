param(
    [Parameter(Mandatory = $true)]
    [string]$BatchId,

    [ValidateSet("", "body", "head", "hair", "outfit", "accessory", "held_item")]
    [string]$Part = "",

    [Nullable[double]]$OffsetX = $null,

    [Nullable[double]]$OffsetY = $null,

    [Nullable[double]]$Scale = $null,

    [switch]$Save,

    [int]$MaxItems = 60,

    [string]$CatalogPath = "tools/art/catalogs/character_source_catalog.json",

    [string]$BatchAdjustmentsPath = "tools/art/catalogs/character_batch_adjustments.json",

    [string]$AssetAdjustmentsPath = "tools/art/catalogs/character_asset_adjustments.json",

    [string]$Output = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Drawing

$ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$StandardizeScript = Join-Path $PSScriptRoot "standardize_character_part.ps1"
$PreviewRoot = Join-Path $ProjectRoot "tools/art/previews/batches"
$TempRoot = Join-Path $ProjectRoot "tools/art/previews/_batch_tmp"
$BaseBodyPath = Join-Path $ProjectRoot "assets/art/characters/body/body_axolotl_male_01_south_std256.png"
$BaseHeadPath = Join-Path $ProjectRoot "assets/art/characters/head/rk_test_head_01_south_std256.png"

function Resolve-ProjectPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return ""
    }
    if ($Path.StartsWith("res://")) {
        return Join-Path $ProjectRoot $Path.Substring(6)
    }
    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }
    return Join-Path $ProjectRoot $Path
}

function Convert-ToProjectPath {
    param([string]$Path)
    $full = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    if ($full.StartsWith($ProjectRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $full.Substring($ProjectRoot.Length).TrimStart("\", "/").Replace("\", "/")
    }
    return $full.Replace("\", "/")
}

function Convert-ToId {
    param([string]$Value)
    $text = $Value.ToLowerInvariant()
    $text = [Regex]::Replace($text, "[^a-z0-9]+", "_")
    $text = [Regex]::Replace($text, "_+", "_").Trim("_")
    if ([string]::IsNullOrWhiteSpace($text)) {
        return "batch"
    }
    return $text
}

function Read-JsonArray {
    param([string]$Path)
    $resolved = Resolve-ProjectPath $Path
    if (-not (Test-Path -LiteralPath $resolved)) {
        throw "JSON file not found: $resolved"
    }
    $value = Get-Content -Raw -Encoding UTF8 -LiteralPath $resolved | ConvertFrom-Json
    if ($value -is [System.Array]) {
        return @($value)
    }
    if ($value.PSObject.Properties["value"] -and $value.PSObject.Properties["Count"]) {
        return @($value.value)
    }
    if ($value.PSObject.Properties["SyncRoot"] -and $value.PSObject.Properties["Count"]) {
        return @($value.SyncRoot)
    }
    return @($value)
}

function Get-Prop {
    param(
        [object]$Object,
        [string]$Name,
        [object]$DefaultValue = ""
    )
    if ($null -eq $Object) {
        return $DefaultValue
    }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $DefaultValue
    }
    return $property.Value
}

function Limit-Text {
    param(
        [string]$Text,
        [int]$MaxLength = 24
    )
    if ([string]::IsNullOrWhiteSpace($Text) -or $Text.Length -le $MaxLength) {
        return $Text
    }
    return $Text.Substring(0, [Math]::Max(1, $MaxLength - 3)) + "..."
}

function Copy-BatchRowsWithOverride {
    param(
        [object[]]$Rows,
        [string]$Path
    )

    $updated = @()
    foreach ($row in $Rows) {
        $copy = [PSCustomObject]@{}
        foreach ($property in $row.PSObject.Properties) {
            $copy | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value
        }
        if ([string](Get-Prop $copy "batch_id" "") -eq $BatchId -and
            ([string]::IsNullOrWhiteSpace($Part) -or [string](Get-Prop $copy "standard_part" "") -eq $Part)) {
            if ($null -ne $OffsetX) { $copy.offset_x = [double]$OffsetX }
            if ($null -ne $OffsetY) { $copy.offset_y = [double]$OffsetY }
            if ($null -ne $Scale) { $copy.scale = [double]$Scale }
            if ([string]::IsNullOrWhiteSpace([string](Get-Prop $copy "review_status" "")) -or [string](Get-Prop $copy "review_status" "") -eq "pending") {
                $copy.review_status = "batch_adjusted"
            }
        }
        $updated += $copy
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    $updated | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 -LiteralPath $Path
    return $updated
}

function New-Canvas {
    param([int]$Width, [int]$Height)
    $bitmap = New-Object System.Drawing.Bitmap $Width, $Height, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    return $bitmap
}

function Draw-Checker {
    param(
        [System.Drawing.Graphics]$Graphics,
        [int]$X,
        [int]$Y,
        [int]$Size,
        [int]$Cell = 16
    )
    $light = [System.Drawing.Color]::FromArgb(255, 245, 241, 225)
    $dark = [System.Drawing.Color]::FromArgb(255, 224, 218, 198)
    $lightBrush = New-Object System.Drawing.SolidBrush $light
    $darkBrush = New-Object System.Drawing.SolidBrush $dark
    try {
        for ($yy = 0; $yy -lt $Size; $yy += $Cell) {
            for ($xx = 0; $xx -lt $Size; $xx += $Cell) {
                $brush = if (((($xx / $Cell) + ($yy / $Cell)) % 2) -eq 0) { $lightBrush } else { $darkBrush }
                $Graphics.FillRectangle($brush, $X + $xx, $Y + $yy, $Cell, $Cell)
            }
        }
    }
    finally {
        $lightBrush.Dispose()
        $darkBrush.Dispose()
    }
}

function Compose-Part {
    param(
        [System.Drawing.Bitmap]$PartImage,
        [string]$StandardPart
    )

    $composite = New-Canvas 256 256
    $graphics = [System.Drawing.Graphics]::FromImage($composite)
    $body = [System.Drawing.Bitmap]::FromFile($BaseBodyPath)
    $head = [System.Drawing.Bitmap]::FromFile($BaseHeadPath)
    try {
        $graphics.Clear([System.Drawing.Color]::FromArgb(0, 0, 0, 0))
        switch ($StandardPart) {
            "body" {
                $graphics.DrawImage($PartImage, 0, 0, 256, 256)
                $graphics.DrawImage($head, 0, 0, 256, 256)
            }
            "head" {
                $graphics.DrawImage($body, 0, 0, 256, 256)
                $graphics.DrawImage($PartImage, 0, 0, 256, 256)
            }
            "outfit" {
                $graphics.DrawImage($body, 0, 0, 256, 256)
                $graphics.DrawImage($PartImage, 0, 0, 256, 256)
                $graphics.DrawImage($head, 0, 0, 256, 256)
            }
            default {
                $graphics.DrawImage($body, 0, 0, 256, 256)
                $graphics.DrawImage($head, 0, 0, 256, 256)
                $graphics.DrawImage($PartImage, 0, 0, 256, 256)
            }
        }
    }
    finally {
        $graphics.Dispose()
        $body.Dispose()
        $head.Dispose()
    }
    return $composite
}

$catalog = Read-JsonArray $CatalogPath
$batchRows = Read-JsonArray $BatchAdjustmentsPath
$selectedRows = @(
    $catalog |
        Where-Object {
            [string](Get-Prop $_ "batch_id" "") -eq $BatchId -and
            ([string]::IsNullOrWhiteSpace($Part) -or [string](Get-Prop $_ "standard_part" "") -eq $Part)
        } |
        Select-Object -First $MaxItems
)

if ($selectedRows.Count -le 0) {
    throw "No source assets found for batch '$BatchId' and part '$Part'."
}

if ($Save -and ($null -ne $OffsetX -or $null -ne $OffsetY -or $null -ne $Scale)) {
    Copy-BatchRowsWithOverride $batchRows (Resolve-ProjectPath $BatchAdjustmentsPath) | Out-Null
    $batchRows = Read-JsonArray $BatchAdjustmentsPath
}

$tempBatchPath = Join-Path $TempRoot ("{0}_batch_adjustments.json" -f (Convert-ToId "$BatchId-$Part"))
Copy-BatchRowsWithOverride $batchRows $tempBatchPath | Out-Null

if ([string]::IsNullOrWhiteSpace($Output)) {
    $Output = Join-Path $PreviewRoot ("{0}.png" -f (Convert-ToId "$BatchId-$Part"))
}
$resolvedOutput = Resolve-ProjectPath $Output
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $resolvedOutput) | Out-Null
New-Item -ItemType Directory -Force -Path $TempRoot | Out-Null

$cellWidth = 180
$cellHeight = 188
$previewSize = 128
$columns = 5
$rowsCount = [int][Math]::Ceiling([double]$selectedRows.Count / [double]$columns)
$sheetWidth = $columns * $cellWidth
$sheetHeight = 76 + ($rowsCount * $cellHeight)
$sheet = New-Canvas $sheetWidth $sheetHeight
$graphics = [System.Drawing.Graphics]::FromImage($sheet)
$fontTitle = New-Object System.Drawing.Font "Consolas", 18, ([System.Drawing.FontStyle]::Bold)
$font = New-Object System.Drawing.Font "Consolas", 9
$black = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 42, 34, 24))
$muted = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 92, 78, 58))
$linePen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(180, 180, 52, 44), 1)

try {
    $graphics.Clear([System.Drawing.Color]::FromArgb(255, 246, 238, 216))
    $graphics.DrawString(("Batch Preview: {0}" -f $BatchId), $fontTitle, $black, 18, 14)
    $graphics.DrawString(("part={0}  items={1}/{2}  override offset=({3},{4}) scale={5}" -f $Part, $selectedRows.Count, ($catalog | Where-Object { [string](Get-Prop $_ "batch_id" "") -eq $BatchId }).Count, $OffsetX, $OffsetY, $Scale), $font, $muted, 20, 46)

    for ($index = 0; $index -lt $selectedRows.Count; $index++) {
        $row = $selectedRows[$index]
        $partName = [string](Get-Prop $row "standard_part" "")
        $assetId = [string](Get-Prop $row "asset_id" "")
        $source = Resolve-ProjectPath ([string](Get-Prop $row "source_path" ""))
        $tempOutput = Join-Path $TempRoot ("{0}_std256.png" -f $assetId)

        & powershell -NoProfile -ExecutionPolicy Bypass -File $StandardizeScript `
            -Source $source `
            -Output $tempOutput `
            -Part $partName `
            -AssetId $assetId `
            -AdjustmentsPath (Resolve-ProjectPath $AssetAdjustmentsPath) `
            -BatchId $BatchId `
            -BatchAdjustmentsPath $tempBatchPath | Out-Null

        $partImage = [System.Drawing.Bitmap]::FromFile($tempOutput)
        $composite = Compose-Part $partImage $partName
        try {
            $column = $index % $columns
            $rowIndex = [int][Math]::Floor([double]$index / [double]$columns)
            $x = $column * $cellWidth + 20
            $y = 76 + ($rowIndex * $cellHeight)
            Draw-Checker $graphics $x $y $previewSize 16
            $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $graphics.DrawImage($composite, $x, $y, $previewSize, $previewSize)
            $graphics.DrawLine($linePen, $x + 64, $y, $x + 64, $y + $previewSize)
            $graphics.DrawLine($linePen, $x, $y + 92, $x + $previewSize, $y + 92)
            $assetLabel = Limit-Text -Text $assetId -MaxLength 24
            $nameLabel = Limit-Text -Text ([string](Get-Prop $row "original_name" "")) -MaxLength 24
            $graphics.DrawString($assetLabel, $font, $black, $x, $y + $previewSize + 6)
            $graphics.DrawString($nameLabel, $font, $muted, $x, $y + $previewSize + 22)
        }
        finally {
            $partImage.Dispose()
            $composite.Dispose()
        }
    }

    $sheet.Save($resolvedOutput, [System.Drawing.Imaging.ImageFormat]::Png)
}
finally {
    $linePen.Dispose()
    $muted.Dispose()
    $black.Dispose()
    $font.Dispose()
    $fontTitle.Dispose()
    $graphics.Dispose()
    $sheet.Dispose()
}

[PSCustomObject]@{
    BatchId = $BatchId
    Part = $Part
    Items = $selectedRows.Count
    Output = Convert-ToProjectPath $resolvedOutput
    SavedBatchAdjustment = [bool]$Save
}
