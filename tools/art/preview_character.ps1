param(
    [Parameter(Mandatory = $true)]
    [string]$CharacterId,

    [string]$Layer = "",

    [Nullable[double]]$OffsetX = $null,

    [Nullable[double]]$OffsetY = $null,

    [Nullable[double]]$Scale = $null,

    [switch]$Save,

    [switch]$Regenerate,

    [string]$Output = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Drawing

$ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$CatalogPath = Join-Path $ProjectRoot "data\appearance\common_appearance_parts.json"
$AdjustmentsPath = Join-Path $ProjectRoot "tools\art\catalogs\character_asset_adjustments.json"
$SourceCatalogPath = Join-Path $ProjectRoot "tools\art\catalogs\character_source_catalog.json"
$StandardizeScript = Join-Path $ProjectRoot "tools\art\standardize_character_part.ps1"
$PreviewDir = Join-Path $ProjectRoot "tools\art\previews"

if ([string]::IsNullOrWhiteSpace($Output)) {
    $Output = Join-Path $PreviewDir ("{0}_preview.png" -f $CharacterId)
}

function Read-Json {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "JSON file not found: $Path"
    }
    return Get-Content -Raw -Encoding UTF8 -LiteralPath $Path | ConvertFrom-Json
}

function Read-JsonArray {
    param([string]$Path)
    $value = Read-Json $Path
    return @(Normalize-Rows $value)
}

function Normalize-Rows {
    param([object]$Value)
    if ($null -eq $Value) {
        return @()
    }
    if ($Value -is [System.Array]) {
        return @($Value)
    }
    if ($Value.PSObject.Properties["value"] -and $Value.PSObject.Properties["Count"]) {
        return @($Value.value)
    }
    if ($Value.PSObject.Properties["SyncRoot"] -and $Value.PSObject.Properties["Count"]) {
        return @($Value.SyncRoot)
    }
    return @($Value)
}

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

function Convert-ToProjectRelative {
    param([string]$Path)
    $resolved = (Resolve-Path -LiteralPath $Path).Path
    if ($resolved.StartsWith($ProjectRoot)) {
        return $resolved.Substring($ProjectRoot.Length + 1).Replace("\", "/")
    }
    return $resolved
}

function As-Array {
    param([object]$Value)
    if ($null -eq $Value) {
        return @()
    }
    if ($Value -is [System.Array]) {
        return @($Value)
    }
    return @($Value)
}

function Get-Prop {
    param(
        [object]$Object,
        [string]$Name,
        [object]$DefaultValue = $null
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

function Get-Role {
    param([object]$Profile)
    $role = [string](Get-Prop $Profile "role" "villager")
    if ([string]::IsNullOrWhiteSpace($role)) {
        $role = "villager"
    }
    switch ($role.ToLowerInvariant()) {
        { $_ -in @("shopkeep", "shopkeeper") } { return "shopkeeper" }
        "merchant" { return "merchant" }
        { $_ -in @("guard", "militia", "patrol") } { return "guard" }
        "farmer" { return "farmer" }
        "worker" { return "worker" }
        { $_ -in @("scholar", "researcher") } { return "scholar" }
        { $_ -in @("traveler", "wanderer") } { return "traveler" }
        default { return "villager" }
    }
}

function Get-StableIndex {
    param(
        [string]$Seed,
        [string]$Salt,
        [int]$Count
    )
    if ($Count -le 0) {
        return 0
    }

    $value = [int64]17
    $text = "{0}:{1}" -f $Seed, $Salt
    foreach ($character in $text.ToCharArray()) {
        $value = [int64](($value * 131 + [int][char]$character) % 2147483647)
    }
    return [int]($value % $Count)
}

function Test-PartMatchesRole {
    param(
        [object]$Part,
        [string]$Role
    )
    $roles = @(As-Array (Get-Prop $Part "roles" @()))
    if ($roles.Count -eq 0) {
        return $true
    }
    if ($roles -contains $Role -or $roles -contains "common") {
        return $true
    }
    if ($Role -eq "shopkeeper" -and $roles -contains "merchant") {
        return $true
    }
    if ($Role -eq "farmer" -and ($roles -contains "worker" -or $roles -contains "villager")) {
        return $true
    }
    if ($Role -eq "worker" -and $roles -contains "villager") {
        return $true
    }
    if ($Role -eq "traveler" -and $roles -contains "villager") {
        return $true
    }
    return $false
}

function Test-PartMatchesLayerPolicy {
    param(
        [object]$Part,
        [string]$Role,
        [string]$LayerId
    )
    $category = [string](Get-Prop $Part "category" "")
    if ($LayerId -eq "outfit") {
        if ($Role -eq "guard") {
            return $category -eq "armor"
        }
        return $category -ne "armor"
    }
    if ($LayerId -eq "accessory") {
        if ($Role -eq "guard") {
            return $category -eq "helmet"
        }
        return $category -eq "hat"
    }
    return $true
}

function Select-AppearancePart {
    param(
        [object[]]$Parts,
        [string]$LayerId,
        [string]$CharacterId,
        [object]$Profile,
        [object]$Appearance
    )

    $role = Get-Role $Profile
    $layerParts = @($Parts | Where-Object { [string](Get-Prop $_ "layer" "") -eq $LayerId })
    if ($layerParts.Count -eq 0) {
        return $null
    }

    $candidates = @($layerParts | Where-Object {
        (Test-PartMatchesRole $_ $role) -and (Test-PartMatchesLayerPolicy $_ $role $LayerId)
    })
    if ($candidates.Count -eq 0) {
        $candidates = @($layerParts | Where-Object { Test-PartMatchesLayerPolicy $_ $role $LayerId })
    }
    if ($candidates.Count -eq 0) {
        $candidates = $layerParts
    }

    $explicitId = [string](Get-Prop $Appearance ("{0}_id" -f $LayerId) "")
    if ($LayerId -eq "hair") {
        $explicitId = [string](Get-Prop $Appearance "hair_id" $explicitId)
    }
    if (-not [string]::IsNullOrWhiteSpace($explicitId)) {
        $explicitPart = $candidates | Where-Object { [string](Get-Prop $_ "id" "") -eq $explicitId } | Select-Object -First 1
        if ($null -ne $explicitPart) {
            return $explicitPart
        }
    }

    $index = Get-StableIndex $CharacterId ("{0}:{1}" -f $LayerId, $role) $candidates.Count
    return $candidates[$index]
}

function Get-HairColor {
    param(
        [string]$CharacterId,
        [object]$Appearance,
        [object]$Catalog
    )
    $palette = Get-Prop $Appearance "palette" $null
    $explicitColor = [string](Get-Prop $palette "hair" "")
    if (-not [string]::IsNullOrWhiteSpace($explicitColor)) {
        return $explicitColor
    }

    $colors = @(As-Array (Get-Prop $Catalog "hair_palettes" @()))
    if ($colors.Count -eq 0) {
        return "#74502e"
    }
    return [string]$colors[(Get-StableIndex $CharacterId "hair_palette" $colors.Count)]
}

function Convert-HtmlColor {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) {
        return [System.Drawing.Color]::White
    }
    return [System.Drawing.ColorTranslator]::FromHtml($Value)
}

function Get-SourcePart {
    param(
        [object[]]$SourceCatalog,
        [string]$AssetId
    )
    return $SourceCatalog | Where-Object { [string](Get-Prop $_ "asset_id" "") -eq $AssetId } | Select-Object -First 1
}

function Build-LayerInfo {
    param(
        [object]$Part,
        [string]$LayerId,
        [string]$PartType,
        [string]$Modulate = ""
    )
    if ($null -eq $Part) {
        return $null
    }

    $assetId = [string](Get-Prop $Part "id" "")
    return [PSCustomObject]@{
        Layer = $LayerId
        Part = $PartType
        AssetId = $assetId
        Source = [string](Get-Prop $Part "source" "")
        SourceAsset = [string](Get-Prop $Part "source_asset" "")
        Category = [string](Get-Prop $Part "category" "")
        DyeMode = [string](Get-Prop $Part "dye_mode" "fixed")
        Modulate = $Modulate
        PreviewSource = [string](Get-Prop $Part "source" "")
        RuntimeSource = [string](Get-Prop $Part "source" "")
    }
}

function Resolve-CharacterAppearance {
    param(
        [string]$CharacterId,
        [object]$Definition,
        [object]$Catalog
    )

    $profile = Get-Prop $Definition "appearance_profile" $null
    $appearance = Get-Prop $Definition "appearance" $null
    $kind = [string](Get-Prop $Definition "character_kind" "npc")
    $importance = [string](Get-Prop $profile "importance" "common")
    $autoResolve = [bool](Get-Prop $appearance "auto_resolve" $false)
    $shouldAutoResolve = $autoResolve -or (($kind -ne "player") -and ($kind -ne "enemy") -and $importance -eq "common")

    $parts = @(Get-Prop $Catalog "parts" @())
    $layers = @()

    if ($shouldAutoResolve) {
        $body = Select-AppearancePart $parts "body" $CharacterId $profile $appearance
        $outfit = Select-AppearancePart $parts "outfit" $CharacterId $profile $appearance
        $head = Select-AppearancePart $parts "head" $CharacterId $profile $appearance
        $accessory = $null
        $role = Get-Role $profile
        if ($role -eq "guard" -or (Get-StableIndex $CharacterId "accessory_chance" 100) -lt 18) {
            $accessory = Select-AppearancePart $parts "accessory" $CharacterId $profile $appearance
        }
        $hair = $null
        if (-not ($role -eq "guard" -and $null -ne $accessory)) {
            $hair = Select-AppearancePart $parts "hair" $CharacterId $profile $appearance
        }

        $layers += Build-LayerInfo $body "body" "body"
        $layers += Build-LayerInfo $outfit "outfit" "outfit"
        $layers += Build-LayerInfo $head "head" "head"
        if ($null -ne $hair) {
            $hairColor = ""
            if ([string](Get-Prop $hair "dye_mode" "fixed") -eq "tint") {
                $hairColor = Get-HairColor $CharacterId $appearance $Catalog
            }
            $layers += Build-LayerInfo $hair "hair" "hair" $hairColor
        }
        $layers += Build-LayerInfo $accessory "accessory" "accessory"
    }
    else {
        $appearanceLayers = Get-Prop $appearance "layers" $null
        foreach ($layerId in @("body", "outfit", "head", "hair", "accessory", "held_item")) {
            $layerData = Get-Prop $appearanceLayers $layerId $null
            $source = [string](Get-Prop $layerData "source" "")
            if ([string]::IsNullOrWhiteSpace($source)) {
                continue
            }
            $assetId = [System.IO.Path]::GetFileNameWithoutExtension($source) -replace "_south_std256$", ""
            $layers += [PSCustomObject]@{
                Layer = $layerId
                Part = if ($layerId -eq "accessory") { "accessory" } else { $layerId }
                AssetId = $assetId
                Source = $source
                SourceAsset = ""
                Category = ""
                DyeMode = "fixed"
                Modulate = [string](Get-Prop $layerData "modulate" "")
                PreviewSource = $source
                RuntimeSource = $source
            }
        }
    }

    return @($layers | Where-Object { $null -ne $_ })
}

function Get-AdjustmentRow {
    param(
        [object[]]$Rows,
        [string]$AssetId
    )
    return $Rows | Where-Object { [string](Get-Prop $_ "asset_id" "") -eq $AssetId } | Select-Object -First 1
}

function Copy-AdjustmentRowsWithOverride {
    param(
        [object[]]$Rows,
        [object]$LayerInfo,
        [string]$Path,
        [Nullable[double]]$OffsetX,
        [Nullable[double]]$OffsetY,
        [Nullable[double]]$Scale
    )

    $Rows = @(Normalize-Rows $Rows)
    $updated = @()
    $found = $false
    foreach ($row in $Rows) {
        $copy = [PSCustomObject]@{}
        foreach ($property in $row.PSObject.Properties) {
            $copy | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value
        }
        if ([string](Get-Prop $row "asset_id" "") -eq $LayerInfo.AssetId) {
            $found = $true
            if ($null -ne $OffsetX) { $copy.offset_x = [double]$OffsetX }
            if ($null -ne $OffsetY) { $copy.offset_y = [double]$OffsetY }
            if ($null -ne $Scale) { $copy.scale = [double]$Scale }
            if ([string]::IsNullOrWhiteSpace([string](Get-Prop $copy "review_status" ""))) {
                $copy.review_status = "adjusted"
            }
        }
        $updated += $copy
    }

    if (-not $found) {
        $newRow = [PSCustomObject]@{
            asset_id = $LayerInfo.AssetId
            source_path = $LayerInfo.SourceAsset
            layer = $LayerInfo.Layer
            standard_part = $LayerInfo.Part
            category = $LayerInfo.Category
            offset_x = if ($null -ne $OffsetX) { [double]$OffsetX } else { 0 }
            offset_y = if ($null -ne $OffsetY) { [double]$OffsetY } else { 0 }
            scale = if ($null -ne $Scale) { [double]$Scale } else { 1.0 }
            target_x = ""
            target_y = ""
            target_width = ""
            target_height = ""
            align = ""
            review_status = "adjusted"
            notes = ""
        }
        $updated += $newRow
    }

    $directory = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
    @($updated) | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 -LiteralPath $Path
    return $updated
}

function Invoke-Standardize {
    param(
        [object]$LayerInfo,
        [string]$AdjustmentsPath,
        [string]$OutputPath
    )

    if ([string]::IsNullOrWhiteSpace($LayerInfo.SourceAsset)) {
        throw "Layer '$($LayerInfo.Layer)' asset '$($LayerInfo.AssetId)' has no source_asset path in the catalog."
    }

    $sourcePath = Resolve-ProjectPath $LayerInfo.SourceAsset
    & powershell -NoProfile -ExecutionPolicy Bypass -File $StandardizeScript `
        -Source $sourcePath `
        -Output $OutputPath `
        -Part $LayerInfo.Part `
        -AssetId $LayerInfo.AssetId `
        -AdjustmentsPath $AdjustmentsPath | Out-Null
}

function Apply-Modulate {
    param(
        [System.Drawing.Bitmap]$Image,
        [string]$ColorValue
    )
    if ([string]::IsNullOrWhiteSpace($ColorValue)) {
        return $Image
    }

    $mod = Convert-HtmlColor $ColorValue
    $copy = New-Object System.Drawing.Bitmap $Image.Width, $Image.Height, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    for ($y = 0; $y -lt $Image.Height; $y++) {
        for ($x = 0; $x -lt $Image.Width; $x++) {
            $pixel = $Image.GetPixel($x, $y)
            if ($pixel.A -eq 0) {
                $copy.SetPixel($x, $y, [System.Drawing.Color]::FromArgb(0, 0, 0, 0))
                continue
            }
            $r = [Math]::Min(255, [int]([double]$pixel.R * [double]$mod.R / 255.0))
            $g = [Math]::Min(255, [int]([double]$pixel.G * [double]$mod.G / 255.0))
            $b = [Math]::Min(255, [int]([double]$pixel.B * [double]$mod.B / 255.0))
            $a = [Math]::Min(255, [int]([double]$pixel.A * [double]$mod.A / 255.0))
            $copy.SetPixel($x, $y, [System.Drawing.Color]::FromArgb($a, $r, $g, $b))
        }
    }
    return $copy
}

function Draw-TransparentChecker {
    param(
        [System.Drawing.Graphics]$Graphics,
        [System.Drawing.Rectangle]$Rect,
        [int]$CellSize = 8
    )
    $light = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(245, 242, 232))
    $dark = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(224, 218, 204))
    try {
        for ($y = $Rect.Top; $y -lt $Rect.Bottom; $y += $CellSize) {
            for ($x = $Rect.Left; $x -lt $Rect.Right; $x += $CellSize) {
                $useDark = (([Math]::Floor(($x - $Rect.Left) / $CellSize) + [Math]::Floor(($y - $Rect.Top) / $CellSize)) % 2) -eq 0
                $brush = if ($useDark) { $dark } else { $light }
                $Graphics.FillRectangle($brush, $x, $y, $CellSize, $CellSize)
            }
        }
    }
    finally {
        $light.Dispose()
        $dark.Dispose()
    }
}

function Render-Composite64 {
    param([object[]]$Layers)

    $image = New-Object System.Drawing.Bitmap 64, 64, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($image)
    try {
        $graphics.Clear([System.Drawing.Color]::FromArgb(0, 0, 0, 0))
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceOver

        foreach ($layer in $Layers) {
            $path = Resolve-ProjectPath $layer.PreviewSource
            if (-not (Test-Path -LiteralPath $path)) {
                continue
            }
            $partImage = [System.Drawing.Bitmap]::FromFile($path)
            $drawImage = $partImage
            try {
                if (-not [string]::IsNullOrWhiteSpace($layer.Modulate)) {
                    $drawImage = Apply-Modulate $partImage $layer.Modulate
                }
                $graphics.DrawImage($drawImage, (New-Object System.Drawing.Rectangle 0, 0, 64, 64), 0, 0, 256, 256, [System.Drawing.GraphicsUnit]::Pixel)
            }
            finally {
                if ($drawImage -ne $partImage) {
                    $drawImage.Dispose()
                }
                $partImage.Dispose()
            }
        }
    }
    finally {
        $graphics.Dispose()
    }
    return $image
}

function Draw-PreviewSheet {
    param(
        [string]$Path,
        [string]$CharacterId,
        [object[]]$Layers,
        [System.Drawing.Bitmap]$Composite
    )

    $width = 1100
    $height = 360 + [Math]::Max(0, $Layers.Count - 4) * 62
    $sheet = New-Object System.Drawing.Bitmap $width, $height, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($sheet)
    $fontTitle = New-Object System.Drawing.Font "Consolas", 18, ([System.Drawing.FontStyle]::Bold)
    $font = New-Object System.Drawing.Font "Consolas", 10
    $fontSmall = New-Object System.Drawing.Font "Consolas", 8
    $black = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(42, 34, 24))
    $muted = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(100, 90, 78))
    $linePen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(110, 90, 64)), 1
    $anchorPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(220, 45, 40)), 1
    try {
        $graphics.Clear([System.Drawing.Color]::FromArgb(250, 244, 226))
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::None
        $graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

        $graphics.DrawString(("Character Preview: {0}" -f $CharacterId), $fontTitle, $black, 24, 18)
        $graphics.DrawString(("Generated: {0}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss")), $fontSmall, $muted, 26, 48)

        $previewRect = New-Object System.Drawing.Rectangle 32, 82, 256, 256
        Draw-TransparentChecker $graphics $previewRect 16
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
        $graphics.DrawImage($Composite, $previewRect, 0, 0, 64, 64, [System.Drawing.GraphicsUnit]::Pixel)
        $graphics.DrawRectangle($linePen, $previewRect)
        $graphics.DrawLine($anchorPen, 32 + 32 * 4, 82, 32 + 32 * 4, 82 + 256)
        $graphics.DrawLine($anchorPen, 32, 82 + 46 * 4, 32 + 256, 82 + 46 * 4)
        $graphics.DrawString("64x64 runtime composite, scaled 4x", $font, $black, 32, 342)
        $graphics.DrawString("red cross = runtime anchor (32,46)", $fontSmall, $muted, 32, 360)

        $y = 82
        $graphics.DrawString("Resolved layers", $fontTitle, $black, 330, 82)
        $y += 38

        foreach ($layer in $Layers) {
            $thumbRect = New-Object System.Drawing.Rectangle 330, $y, 52, 52
            Draw-TransparentChecker $graphics $thumbRect 8
            $pathOnDisk = Resolve-ProjectPath $layer.PreviewSource
            if (Test-Path -LiteralPath $pathOnDisk) {
                $bitmap = [System.Drawing.Bitmap]::FromFile($pathOnDisk)
                $drawBitmap = $bitmap
                try {
                    if (-not [string]::IsNullOrWhiteSpace($layer.Modulate)) {
                        $drawBitmap = Apply-Modulate $bitmap $layer.Modulate
                    }
                    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                    $graphics.DrawImage($drawBitmap, $thumbRect, 0, 0, 256, 256, [System.Drawing.GraphicsUnit]::Pixel)
                }
                finally {
                    if ($drawBitmap -ne $bitmap) {
                        $drawBitmap.Dispose()
                    }
                    $bitmap.Dispose()
                }
            }
            $graphics.DrawRectangle($linePen, $thumbRect)

            $graphics.DrawString(("{0}: {1}" -f $layer.Layer, $layer.AssetId), $font, $black, 396, $y)
            $graphics.DrawString(("part={0} category={1} dye={2} modulate={3}" -f $layer.Part, $layer.Category, $layer.DyeMode, $layer.Modulate), $fontSmall, $muted, 396, $y + 18)
            $graphics.DrawString($layer.RuntimeSource, $fontSmall, $muted, 396, $y + 34)
            $y += 62
        }

        $directory = Split-Path -Parent $Path
        New-Item -ItemType Directory -Force -Path $directory | Out-Null
        $sheet.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $anchorPen.Dispose()
        $linePen.Dispose()
        $muted.Dispose()
        $black.Dispose()
        $fontSmall.Dispose()
        $font.Dispose()
        $fontTitle.Dispose()
        $graphics.Dispose()
        $sheet.Dispose()
    }
}

$catalog = Read-Json $CatalogPath
$sourceCatalog = if (Test-Path -LiteralPath $SourceCatalogPath) { @(Read-JsonArray $SourceCatalogPath) } else { @() }
$adjustments = @(Read-JsonArray $AdjustmentsPath)
$characterPath = Join-Path $ProjectRoot ("data\characters\{0}.json" -f $CharacterId)
$definition = Read-Json $characterPath
$layers = @(Resolve-CharacterAppearance $CharacterId $definition $catalog)

if (-not [string]::IsNullOrWhiteSpace($Layer)) {
    $selected = $layers | Where-Object { $_.Layer -eq $Layer -or $_.AssetId -eq $Layer } | Select-Object -First 1
    if ($null -eq $selected) {
        throw "Layer or asset not found for '$Layer'. Available: $($layers.AssetId -join ', ')"
    }

    if ($null -ne $OffsetX -or $null -ne $OffsetY -or $null -ne $Scale) {
        if ([string]::IsNullOrWhiteSpace($selected.SourceAsset)) {
            $sourcePart = Get-SourcePart $sourceCatalog $selected.AssetId
            if ($null -ne $sourcePart) {
                $selected.SourceAsset = [string](Get-Prop $sourcePart "source_path" "")
            }
        }

        $tempDir = Join-Path $PreviewDir "_tmp"
        New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
        $tempAdjustments = Join-Path $tempDir ("{0}_{1}_adjustments.json" -f $CharacterId, $selected.AssetId)
        Copy-AdjustmentRowsWithOverride $adjustments $selected $tempAdjustments $OffsetX $OffsetY $Scale | Out-Null
        $tempOutput = Join-Path $tempDir ("{0}_{1}_std256.png" -f $CharacterId, $selected.AssetId)
        Invoke-Standardize $selected $tempAdjustments $tempOutput
        $selected.PreviewSource = Convert-ToProjectRelative $tempOutput

        if ($Save) {
            $adjustments = @(Copy-AdjustmentRowsWithOverride $adjustments $selected $AdjustmentsPath $OffsetX $OffsetY $Scale)
        }
        if ($Regenerate) {
            Invoke-Standardize $selected $AdjustmentsPath (Resolve-ProjectPath $selected.RuntimeSource)
            $selected.PreviewSource = $selected.RuntimeSource
        }
    }
}

$renderOrder = @("body", "outfit", "head", "hair", "accessory", "held_item")
$orderedLayers = @()
foreach ($orderLayer in $renderOrder) {
    $orderedLayers += @($layers | Where-Object { $_.Layer -eq $orderLayer })
}

$composite = Render-Composite64 $orderedLayers
try {
    Draw-PreviewSheet $Output $CharacterId $orderedLayers $composite
}
finally {
    $composite.Dispose()
}

[PSCustomObject]@{
    CharacterId = $CharacterId
    Output = Convert-ToProjectRelative $Output
    Layers = @($orderedLayers | ForEach-Object {
        [PSCustomObject]@{
            layer = $_.Layer
            asset_id = $_.AssetId
            runtime = $_.RuntimeSource
            source_asset = $_.SourceAsset
            modulate = $_.Modulate
        }
    })
} | ConvertTo-Json -Depth 6
