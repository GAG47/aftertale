param(
    [Parameter(Mandatory = $true)]
    [string]$BatchId,

    [ValidateSet("", "body", "head", "hair", "outfit", "accessory", "held_item")]
    [string]$Part = "",

    [Nullable[double]]$OffsetX = $null,

    [Nullable[double]]$OffsetY = $null,

    [Nullable[double]]$Scale = $null,

    [Nullable[double]]$TargetX = $null,

    [Nullable[double]]$TargetY = $null,

    [Nullable[double]]$TargetWidth = $null,

    [Nullable[double]]$TargetHeight = $null,

    [ValidateSet("", "center", "bottom")]
    [string]$Align = "",

    [string]$AdjustmentsPath = "tools/art/catalogs/character_batch_adjustments.json"
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

function Read-JsonArray {
    param([string]$Path)
    $value = Get-Content -Raw -Encoding UTF8 -LiteralPath $Path | ConvertFrom-Json
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

$resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath((Resolve-ProjectPath $AdjustmentsPath))
if (-not (Test-Path -LiteralPath $resolvedPath)) {
    throw "Batch adjustment table not found: $resolvedPath"
}

$rows = @(Read-JsonArray $resolvedPath)
$matched = 0
foreach ($row in $rows) {
    $rowBatchId = [string](Get-Prop -Object $row -Name "batch_id" -DefaultValue "")
    $rowPart = [string](Get-Prop -Object $row -Name "standard_part" -DefaultValue "")
    if ($rowBatchId -ne $BatchId) {
        continue
    }
    if (-not [string]::IsNullOrWhiteSpace($Part) -and $rowPart -ne $Part) {
        continue
    }

    if ($null -ne $OffsetX) { $row.offset_x = [double]$OffsetX }
    if ($null -ne $OffsetY) { $row.offset_y = [double]$OffsetY }
    if ($null -ne $Scale) { $row.scale = [double]$Scale }
    if ($null -ne $TargetX) { $row.target_x = [double]$TargetX }
    if ($null -ne $TargetY) { $row.target_y = [double]$TargetY }
    if ($null -ne $TargetWidth) { $row.target_width = [double]$TargetWidth }
    if ($null -ne $TargetHeight) { $row.target_height = [double]$TargetHeight }
    if (-not [string]::IsNullOrWhiteSpace($Align)) { $row.align = $Align }
    if ([string]::IsNullOrWhiteSpace([string](Get-Prop $row "review_status" "")) -or [string](Get-Prop $row "review_status" "") -eq "pending") {
        $row.review_status = "batch_adjusted"
    }
    $matched += 1
}

if ($matched -le 0) {
    $partText = if ([string]::IsNullOrWhiteSpace($Part)) { "any part" } else { $Part }
    throw "No batch adjustment row found for '$BatchId' / '$partText'. Rebuild the source catalog first."
}

$rows | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 -LiteralPath $resolvedPath

[PSCustomObject]@{
    BatchId = $BatchId
    Part = $Part
    MatchedRows = $matched
    AdjustmentsPath = $resolvedPath
}
