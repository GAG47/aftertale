param(
    [Parameter(Mandatory = $true)]
    [string]$Source,

    [Parameter(Mandatory = $true)]
    [string]$Output,

    [Parameter(Mandatory = $true)]
    [ValidateSet("head", "hair_front", "hair_back", "outfit", "accessory", "held_item")]
    [string]$Part,

    [int]$AlphaThreshold = 8
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Drawing

function New-TargetRegion {
    param([string]$Part)

    switch ($Part) {
        "head" {
            return [PSCustomObject]@{
                X = 96
                Y = 88
                Width = 64
                Height = 68
                Align = "center"
            }
        }
        "hair_front" {
            return [PSCustomObject]@{
                X = 72
                Y = 72
                Width = 112
                Height = 124
                Align = "center"
            }
        }
        "hair_back" {
            return [PSCustomObject]@{
                X = 72
                Y = 60
                Width = 112
                Height = 132
                Align = "center"
            }
        }
        "outfit" {
            return [PSCustomObject]@{
                X = 88
                Y = 128
                Width = 80
                Height = 116
                Align = "bottom"
            }
        }
        "accessory" {
            return [PSCustomObject]@{
                X = 72
                Y = 8
                Width = 112
                Height = 108
                Align = "center"
            }
        }
        "held_item" {
            return [PSCustomObject]@{
                X = 140
                Y = 72
                Width = 88
                Height = 116
                Align = "center"
            }
        }
    }
}

function Get-AlphaBounds {
    param(
        [System.Drawing.Bitmap]$Image,
        [int]$Threshold
    )

    $minX = $Image.Width
    $minY = $Image.Height
    $maxX = -1
    $maxY = -1

    for ($y = 0; $y -lt $Image.Height; $y++) {
        for ($x = 0; $x -lt $Image.Width; $x++) {
            $pixel = $Image.GetPixel($x, $y)
            if ($pixel.A -le $Threshold) {
                continue
            }

            if ($x -lt $minX) { $minX = $x }
            if ($y -lt $minY) { $minY = $y }
            if ($x -gt $maxX) { $maxX = $x }
            if ($y -gt $maxY) { $maxY = $y }
        }
    }

    if ($maxX -lt $minX -or $maxY -lt $minY) {
        throw "No visible pixels found in $Source."
    }

    return [System.Drawing.Rectangle]::FromLTRB($minX, $minY, $maxX + 1, $maxY + 1)
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
    $bounds = Get-AlphaBounds -Image $sourceImage -Threshold $AlphaThreshold
    $region = New-TargetRegion -Part $Part
    $scale = [Math]::Min(
        [double]$region.Width / [double]$bounds.Width,
        [double]$region.Height / [double]$bounds.Height
    )
    $destWidth = [Math]::Max(1, [int][Math]::Round($bounds.Width * $scale))
    $destHeight = [Math]::Max(1, [int][Math]::Round($bounds.Height * $scale))
    $destX = [int][Math]::Round($region.X + ($region.Width - $destWidth) * 0.5)
    $destY = [int][Math]::Round($region.Y + ($region.Height - $destHeight) * 0.5)

    if ($region.Align -eq "bottom") {
        $destY = [int][Math]::Round($region.Y + $region.Height - $destHeight)
    }

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
        Canvas = "256x256"
        Anchor = "128,184"
    }
}
finally {
    $sourceImage.Dispose()
    $targetImage.Dispose()
}
