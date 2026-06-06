param(
    [string]$SourceRoot = "assets/art/source",

    [string]$CatalogPath = "tools/art/catalogs/character_source_catalog.json",

    [string]$BatchAdjustmentsPath = "tools/art/catalogs/character_batch_adjustments.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path

function Resolve-ProjectPath {
    param([string]$Path)
    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }
    return Join-Path $ProjectRoot $Path
}

function Convert-ToProjectPath {
    param([string]$Path)
    $full = (Resolve-Path -LiteralPath $Path).Path
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
        return "asset"
    }
    return $text
}

function Get-StandardPart {
    param(
        [string]$Kind,
        [string]$Name
    )

    switch ($Kind.ToLowerInvariant()) {
        "hair" { return "hair" }
        "body" { return "body" }
        "head" { return "head" }
        "weapon" { return "held_item" }
        "apparel" {
            if ($Name -match "(?i)(hat|helmet|helm|crown|coronet|hood|veil|coif|headband|hairband|corsage|mask|glasses|mhat)") {
                return "accessory"
            }
            return "outfit"
        }
    }
    return "accessory"
}

function Get-Category {
    param(
        [string]$Kind,
        [string]$Part,
        [string]$Name
    )

    if ($Part -eq "accessory") {
        if ($Name -match "(?i)helmet|helm") { return "helmet" }
        if ($Name -match "(?i)hat|mhat") { return "hat" }
        if ($Name -match "(?i)crown|coronet") { return "crown" }
        if ($Name -match "(?i)mask|glasses") { return "face_accessory" }
        return "head_accessory"
    }
    if ($Part -eq "outfit") {
        if ($Name -match "(?i)armor|plate|suit") { return "armor" }
        if ($Name -match "(?i)dress|robe|gown|onepiece") { return "robe_dress" }
        if ($Name -match "(?i)worker|garden|chef|apron") { return "workwear" }
        return "outfit"
    }
    if ($Part -eq "hair") {
        return "hair"
    }
    return $Kind.ToLowerInvariant()
}

function Get-OutputDirectory {
    param([string]$Part)
    switch ($Part) {
        "body" { return "assets/art/characters/_staging/body" }
        "head" { return "assets/art/characters/_staging/head" }
        "hair" { return "assets/art/characters/_staging/hair" }
        "outfit" { return "assets/art/characters/_staging/outfits" }
        "held_item" { return "assets/art/characters/_staging/held_items" }
        default { return "assets/art/characters/_staging/accessories" }
    }
}

$resolvedSourceRoot = (Resolve-Path -LiteralPath (Resolve-ProjectPath $SourceRoot)).Path
$catalogOutput = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath((Resolve-ProjectPath $CatalogPath))
$batchOutput = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath((Resolve-ProjectPath $BatchAdjustmentsPath))

$rows = @()
$assetIds = @{}
$files = Get-ChildItem -LiteralPath $resolvedSourceRoot -Recurse -File -Filter "*.png" |
    Where-Object { $_.Name -notlike "*_std256.png" } |
    Sort-Object FullName

foreach ($file in $files) {
    $relativeDirectory = $file.DirectoryName.Substring($resolvedSourceRoot.Length).TrimStart("\", "/")
    $parts = $relativeDirectory.Split([char]92, [System.StringSplitOptions]::RemoveEmptyEntries)
    if ($parts.Length -lt 2) {
        continue
    }

    $kind = $parts[0].ToLowerInvariant()
    $batchId = ($parts[0..1] -join "/")
    $part = Get-StandardPart -Kind $kind -Name $file.BaseName
    $category = Get-Category -Kind $kind -Part $part -Name $file.BaseName
    $baseId = "src_{0}_{1}_{2}" -f (Convert-ToId $kind), (Convert-ToId $parts[1]), (Convert-ToId $file.BaseName)
    $assetId = $baseId
    if ($assetIds.ContainsKey($assetId)) {
        $assetIds[$assetId] += 1
        $assetId = "{0}_{1:d2}" -f $baseId, $assetIds[$baseId]
    }
    else {
        $assetIds[$assetId] = 1
    }

    $runtimePath = "{0}/{1}_south_std256.png" -f (Get-OutputDirectory -Part $part), $assetId
    $rows += [PSCustomObject]@{
        asset_id = $assetId
        source_path = Convert-ToProjectPath $file.FullName
        source_kind = $kind
        batch_id = $batchId
        original_name = $file.Name
        filename = $file.Name
        standard_part = $part
        layer = $part
        category = $category
        status = "pending"
        review_status = "pending"
        runtime_path = $runtimePath
        notes = ""
    }
}

$batchRows = @(
    $rows |
        Group-Object batch_id, standard_part |
        Sort-Object Name |
        ForEach-Object {
            $first = $_.Group[0]
            [PSCustomObject]@{
                batch_id = $first.batch_id
                source_kind = $first.source_kind
                standard_part = $first.standard_part
                offset_x = "0"
                offset_y = "0"
                scale = "1.0"
                target_x = ""
                target_y = ""
                target_width = ""
                target_height = ""
                align = ""
                review_status = "pending"
                notes = ""
            }
        }
)

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $catalogOutput) | Out-Null
$rows | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 -LiteralPath $catalogOutput
$batchRows | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 -LiteralPath $batchOutput

[PSCustomObject]@{
    CatalogPath = Convert-ToProjectPath $catalogOutput
    CatalogRows = $rows.Count
    BatchAdjustmentsPath = Convert-ToProjectPath $batchOutput
    BatchRows = $batchRows.Count
}
