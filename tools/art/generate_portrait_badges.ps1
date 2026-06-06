param(
    [string]$ConfigPath = "tools/art/catalogs/portrait_badge_crops.json",
    [switch]$CreateMissingPlaceholders
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

function Resolve-WorkspacePath {
    param([string]$Path)
    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }
    return Join-Path (Get-Location) $Path
}

function Convert-HexColor {
    param(
        [string]$Hex,
        [System.Drawing.Color]$Fallback
    )
    if ([string]::IsNullOrWhiteSpace($Hex)) {
        return $Fallback
    }
    $text = $Hex.Trim().TrimStart("#")
    if ($text.Length -ne 6) {
        return $Fallback
    }
    return [System.Drawing.Color]::FromArgb(
        255,
        [Convert]::ToInt32($text.Substring(0, 2), 16),
        [Convert]::ToInt32($text.Substring(2, 2), 16),
        [Convert]::ToInt32($text.Substring(4, 2), 16)
    )
}

function New-CirclePath {
    param([int]$Size, [int]$Inset)
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $diameter = $Size - $Inset * 2
    $path.AddEllipse($Inset, $Inset, $diameter, $diameter)
    return $path
}

function Write-BadgeFromPortrait {
    param(
        [pscustomobject]$Entry,
        [int]$OutputSize
    )

    $sourcePath = Resolve-WorkspacePath $Entry.source
    $outputPath = Resolve-WorkspacePath $Entry.output
    if (-not (Test-Path $sourcePath)) {
        throw "Missing portrait source: $($Entry.source)"
    }

    $source = [System.Drawing.Image]::FromFile($sourcePath)
    try {
        $bitmap = New-Object System.Drawing.Bitmap $OutputSize, $OutputSize
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        try {
            $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $graphics.Clear([System.Drawing.Color]::Transparent)

            $circlePath = New-CirclePath $OutputSize 8
            $graphics.SetClip($circlePath)

            $minDimension = [Math]::Min($source.Width, $source.Height)
            $cropSize = [Math]::Max(1, [int]($minDimension * [double]$Entry.crop_size))
            $centerX = [int]($source.Width * [double]$Entry.center.x)
            $centerY = [int]($source.Height * [double]$Entry.center.y)
            $cropX = [Math]::Max(0, [Math]::Min($source.Width - $cropSize, $centerX - [int]($cropSize / 2)))
            $cropY = [Math]::Max(0, [Math]::Min($source.Height - $cropSize, $centerY - [int]($cropSize / 2)))
            $sourceRect = New-Object System.Drawing.Rectangle $cropX, $cropY, $cropSize, $cropSize
            $targetRect = New-Object System.Drawing.Rectangle 8, 8, ($OutputSize - 16), ($OutputSize - 16)
            $graphics.DrawImage($source, $targetRect, $sourceRect, [System.Drawing.GraphicsUnit]::Pixel)
            $graphics.ResetClip()

            $ringColor = Convert-HexColor $Entry.ring ([System.Drawing.Color]::FromArgb(255, 55, 43, 32))
            $highlightColor = Convert-HexColor $Entry.highlight ([System.Drawing.Color]::FromArgb(255, 242, 217, 153))
            $ringPen = New-Object System.Drawing.Pen $ringColor, 8
            $highlightPen = New-Object System.Drawing.Pen $highlightColor, 3
            try {
                $graphics.DrawEllipse($ringPen, 6, 6, ($OutputSize - 12), ($OutputSize - 12))
                $graphics.DrawArc($highlightPen, 15, 15, ($OutputSize - 30), ($OutputSize - 30), 210, 120)
            } finally {
                $ringPen.Dispose()
                $highlightPen.Dispose()
            }

            $outputDir = Split-Path $outputPath -Parent
            New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
            $bitmap.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Png)
        } finally {
            $graphics.Dispose()
            $bitmap.Dispose()
        }
    } finally {
        $source.Dispose()
    }
}

function Write-PlaceholderBadge {
    param(
        [pscustomobject]$Entry,
        [int]$OutputSize
    )

    $outputPath = Resolve-WorkspacePath $Entry.output
    $bitmap = New-Object System.Drawing.Bitmap $OutputSize, $OutputSize
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.Clear([System.Drawing.Color]::Transparent)
        $ringColor = Convert-HexColor $Entry.ring ([System.Drawing.Color]::FromArgb(255, 55, 43, 32))
        $fillColor = [System.Drawing.Color]::FromArgb(255, [Math]::Max(30, $ringColor.R), [Math]::Max(30, $ringColor.G), [Math]::Max(30, $ringColor.B))
        $fillBrush = New-Object System.Drawing.SolidBrush $fillColor
        $ringPen = New-Object System.Drawing.Pen $ringColor, 8
        $textBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 255, 245, 218))
        $font = New-Object System.Drawing.Font "Arial", 42, ([System.Drawing.FontStyle]::Bold)
        try {
            $graphics.FillEllipse($fillBrush, 8, 8, ($OutputSize - 16), ($OutputSize - 16))
            $graphics.DrawEllipse($ringPen, 6, 6, ($OutputSize - 12), ($OutputSize - 12))
            $label = switch ($Entry.role) {
                "player" { "P"; break }
                "guard" { "G"; break }
                default { "M"; break }
            }
            $format = New-Object System.Drawing.StringFormat
            $format.Alignment = [System.Drawing.StringAlignment]::Center
            $format.LineAlignment = [System.Drawing.StringAlignment]::Center
            $textRect = New-Object System.Drawing.RectangleF 0, 0, $OutputSize, $OutputSize
            $graphics.DrawString($label, $font, $textBrush, $textRect, $format)
            $format.Dispose()
        } finally {
            $font.Dispose()
            $textBrush.Dispose()
            $ringPen.Dispose()
            $fillBrush.Dispose()
        }

        $outputDir = Split-Path $outputPath -Parent
        New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
        $bitmap.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

$resolvedConfigPath = Resolve-WorkspacePath $ConfigPath
$config = Get-Content -Path $resolvedConfigPath -Raw | ConvertFrom-Json
$outputSize = [int]$config.output_size
$generated = 0
$placeholderCount = 0
$missing = @()

foreach ($entry in $config.entries) {
    $sourcePath = Resolve-WorkspacePath $entry.source
    if (Test-Path $sourcePath) {
        Write-BadgeFromPortrait $entry $outputSize
        $generated += 1
        continue
    }

    $missing += $entry.source
    if ($CreateMissingPlaceholders) {
        Write-PlaceholderBadge $entry $outputSize
        $placeholderCount += 1
    }
}

Write-Output ("Generated portrait badges: {0}" -f $generated)
if ($placeholderCount -gt 0) {
    Write-Output ("Generated placeholder badges: {0}" -f $placeholderCount)
}
if ($missing.Count -gt 0) {
    Write-Warning ("Missing portrait sources: {0}" -f ($missing -join ", "))
}
