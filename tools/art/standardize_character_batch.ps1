param(
    [Parameter(Mandatory = $true)]
    [string]$BatchId,

    [ValidateSet("", "body", "head", "hair", "outfit", "accessory", "held_item")]
    [string]$Part = "",

    [string]$CatalogPath = "tools/art/catalogs/character_source_catalog.json",

    [string]$BatchAdjustmentsPath = "tools/art/catalogs/character_batch_adjustments.json",

    [string]$AssetAdjustmentsPath = "tools/art/catalogs/character_asset_adjustments.json",

    [string]$OutputRoot = "",

    [int]$MaxItems = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$StandardizeScript = Join-Path $PSScriptRoot "standardize_character_part.ps1"

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

function Get-PartDirectory {
    param([string]$StandardPart)
    switch ($StandardPart) {
        "body" { return "body" }
        "head" { return "head" }
        "hair" { return "hair" }
        "outfit" { return "outfits" }
        "held_item" { return "held_items" }
        default { return "accessories" }
    }
}

$catalog = Read-JsonArray $CatalogPath
$selectedRows = @(
    $catalog |
        Where-Object {
            [string](Get-Prop -Object $_ -Name "batch_id" -DefaultValue "") -eq $BatchId -and
            ([string]::IsNullOrWhiteSpace($Part) -or [string](Get-Prop -Object $_ -Name "standard_part" -DefaultValue "") -eq $Part)
        }
)

if ($MaxItems -gt 0) {
    $selectedRows = @($selectedRows | Select-Object -First $MaxItems)
}

if ($selectedRows.Count -le 0) {
    throw "No source assets found for batch '$BatchId' and part '$Part'."
}

$outputs = @()
foreach ($row in $selectedRows) {
    $assetId = [string](Get-Prop -Object $row -Name "asset_id" -DefaultValue "")
    $standardPart = [string](Get-Prop -Object $row -Name "standard_part" -DefaultValue "")
    $sourcePath = Resolve-ProjectPath ([string](Get-Prop -Object $row -Name "source_path" -DefaultValue ""))
    if ([string]::IsNullOrWhiteSpace($assetId) -or [string]::IsNullOrWhiteSpace($standardPart) -or [string]::IsNullOrWhiteSpace($sourcePath)) {
        throw "Invalid source catalog row for batch '$BatchId'."
    }

    if (-not (Test-Path -LiteralPath $sourcePath)) {
        throw "Source image not found: $sourcePath"
    }

    $outputPath = [string](Get-Prop -Object $row -Name "runtime_path" -DefaultValue "")
    if (-not [string]::IsNullOrWhiteSpace($OutputRoot)) {
        $outputPath = Join-Path (Join-Path $OutputRoot (Get-PartDirectory -StandardPart $standardPart)) ("{0}_south_std256.png" -f $assetId)
    }
    if ([string]::IsNullOrWhiteSpace($outputPath)) {
        $outputPath = Join-Path (Join-Path "assets/art/characters/_staging" (Get-PartDirectory -StandardPart $standardPart)) ("{0}_south_std256.png" -f $assetId)
    }

    $resolvedOutput = Resolve-ProjectPath $outputPath
    & powershell -NoProfile -ExecutionPolicy Bypass -File $StandardizeScript `
        -Source $sourcePath `
        -Output $resolvedOutput `
        -Part $standardPart `
        -AssetId $assetId `
        -AdjustmentsPath (Resolve-ProjectPath $AssetAdjustmentsPath) `
        -BatchId $BatchId `
        -BatchAdjustmentsPath (Resolve-ProjectPath $BatchAdjustmentsPath) | Out-Null

    $outputs += [PSCustomObject]@{
        asset_id = $assetId
        source_path = Convert-ToProjectPath $sourcePath
        output_path = Convert-ToProjectPath $resolvedOutput
        standard_part = $standardPart
    }
}

[PSCustomObject]@{
    BatchId = $BatchId
    Part = $Part
    Count = $outputs.Count
    Outputs = $outputs
} | ConvertTo-Json -Depth 6
