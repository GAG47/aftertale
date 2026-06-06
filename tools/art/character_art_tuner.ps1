param(
    [string]$CharacterId = "debug_villager",

    [string]$InitialLayer = "",

    [switch]$SmokeTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$PreviewScript = Join-Path $ProjectRoot "tools\art\preview_character.ps1"
$AdjustmentsPath = Join-Path $ProjectRoot "tools\art\catalogs\character_asset_adjustments.json"
$PreviewDir = Join-Path $ProjectRoot "tools\art\previews\tuner"
$PreviewPath = Join-Path $PreviewDir ("{0}_live.png" -f $CharacterId)

New-Item -ItemType Directory -Force -Path $PreviewDir | Out-Null

function Read-Json {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "JSON file not found: $Path"
    }
    return Get-Content -Raw -Encoding UTF8 -LiteralPath $Path | ConvertFrom-Json
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

function Convert-ToDouble {
    param(
        [object]$Value,
        [double]$DefaultValue
    )
    if ($null -eq $Value) {
        return $DefaultValue
    }
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $DefaultValue
    }
    return [double]::Parse($text, [System.Globalization.CultureInfo]::InvariantCulture)
}

function Format-Double {
    param([double]$Value)
    return $Value.ToString("0.###", [System.Globalization.CultureInfo]::InvariantCulture)
}

function Get-Adjustment {
    param([string]$AssetId)
    $rows = @(Normalize-Rows (Read-Json $AdjustmentsPath))
    $row = $rows | Where-Object { [string](Get-Prop $_ "asset_id" "") -eq $AssetId } | Select-Object -First 1
    return [PSCustomObject]@{
        OffsetX = Convert-ToDouble (Get-Prop $row "offset_x" 0) 0.0
        OffsetY = Convert-ToDouble (Get-Prop $row "offset_y" 0) 0.0
        Scale = Convert-ToDouble (Get-Prop $row "scale" 1.0) 1.0
        ReviewStatus = [string](Get-Prop $row "review_status" "")
        Notes = [string](Get-Prop $row "notes" "")
    }
}

function Invoke-PreviewEngine {
    param(
        [string]$LayerKey = "",
        [Nullable[double]]$OffsetX = $null,
        [Nullable[double]]$OffsetY = $null,
        [Nullable[double]]$Scale = $null,
        [switch]$Save,
        [switch]$Regenerate
    )

    $arguments = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $PreviewScript,
        "-CharacterId", $CharacterId,
        "-Output", $PreviewPath
    )

    if (-not [string]::IsNullOrWhiteSpace($LayerKey)) {
        $arguments += @("-Layer", $LayerKey)
        if ($null -ne $OffsetX) {
            $arguments += @("-OffsetX", (Format-Double ([double]$OffsetX)))
        }
        if ($null -ne $OffsetY) {
            $arguments += @("-OffsetY", (Format-Double ([double]$OffsetY)))
        }
        if ($null -ne $Scale) {
            $arguments += @("-Scale", (Format-Double ([double]$Scale)))
        }
        if ($Save) {
            $arguments += "-Save"
        }
        if ($Regenerate) {
            $arguments += "-Regenerate"
        }
    }

    $output = & powershell @arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw (($output | Out-String).Trim())
    }

    $json = ($output | Out-String).Trim()
    if ([string]::IsNullOrWhiteSpace($json)) {
        throw "Preview engine produced no JSON output."
    }
    return $json | ConvertFrom-Json
}

function Load-BitmapNoLock {
    param([string]$Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $stream = New-Object System.IO.MemoryStream (, $bytes)
    try {
        $image = [System.Drawing.Image]::FromStream($stream)
        try {
            return New-Object System.Drawing.Bitmap $image
        }
        finally {
            $image.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }
}

if ($SmokeTest) {
    $result = Invoke-PreviewEngine
    [PSCustomObject]@{
        CharacterId = $CharacterId
        Preview = $PreviewPath
        Layers = @($result.Layers | ForEach-Object { $_.asset_id })
    } | ConvertTo-Json -Depth 4
    return
}

[System.Windows.Forms.Application]::EnableVisualStyles()

$script:LayerByDisplay = @{}
$script:CurrentResult = $null
$script:CurrentImage = $null
$script:IsSyncingControls = $false

$form = New-Object System.Windows.Forms.Form
$form.Text = "Aftertale Character Art Tuner - $CharacterId"
$form.StartPosition = "CenterScreen"
$form.Size = New-Object System.Drawing.Size 1180, 760
$form.MinimumSize = New-Object System.Drawing.Size 1020, 680

$main = New-Object System.Windows.Forms.TableLayoutPanel
$main.Dock = "Fill"
$main.ColumnCount = 2
$main.RowCount = 1
$main.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle ([System.Windows.Forms.SizeType]::Percent), 68)) | Out-Null
$main.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle ([System.Windows.Forms.SizeType]::Percent), 32)) | Out-Null
$form.Controls.Add($main)

$previewBox = New-Object System.Windows.Forms.PictureBox
$previewBox.Dock = "Fill"
$previewBox.SizeMode = "Zoom"
$previewBox.BackColor = [System.Drawing.Color]::FromArgb(46, 42, 36)
$main.Controls.Add($previewBox, 0, 0)

$side = New-Object System.Windows.Forms.TableLayoutPanel
$side.Dock = "Fill"
$side.Padding = New-Object System.Windows.Forms.Padding 12
$side.ColumnCount = 1
$side.RowCount = 16
@(
    34, 34, 80, 26, 58, 58, 58, 32, 32, 34, 34, 34, 34, 34, 34, 100
) | ForEach-Object {
    $side.RowStyles.Add((New-Object System.Windows.Forms.RowStyle ([System.Windows.Forms.SizeType]::Absolute), $_)) | Out-Null
}
$main.Controls.Add($side, 1, 0)

$title = New-Object System.Windows.Forms.Label
$title.Text = "Character: $CharacterId"
$title.Dock = "Fill"
$title.Font = New-Object System.Drawing.Font "Segoe UI", 13, ([System.Drawing.FontStyle]::Bold)
$side.Controls.Add($title, 0, 0)

$layerCombo = New-Object System.Windows.Forms.ComboBox
$layerCombo.Dock = "Fill"
$layerCombo.DropDownStyle = "DropDownList"
$side.Controls.Add($layerCombo, 0, 1)

$details = New-Object System.Windows.Forms.TextBox
$details.Dock = "Fill"
$details.Multiline = $true
$details.ReadOnly = $true
$details.ScrollBars = "Vertical"
$details.Font = New-Object System.Drawing.Font "Consolas", 9
$side.Controls.Add($details, 0, 2)

function New-ValueRow {
    param(
        [string]$Label,
        [decimal]$Minimum,
        [decimal]$Maximum,
        [decimal]$Increment,
        [int]$DecimalPlaces
    )

    $panel = New-Object System.Windows.Forms.TableLayoutPanel
    $panel.Dock = "Fill"
    $panel.ColumnCount = 3
    $panel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle ([System.Windows.Forms.SizeType]::Absolute), 72)) | Out-Null
    $panel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle ([System.Windows.Forms.SizeType]::Percent), 100)) | Out-Null
    $panel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle ([System.Windows.Forms.SizeType]::Absolute), 74)) | Out-Null

    $labelControl = New-Object System.Windows.Forms.Label
    $labelControl.Text = $Label
    $labelControl.Dock = "Fill"
    $labelControl.TextAlign = "MiddleLeft"
    $panel.Controls.Add($labelControl, 0, 0)

    $track = New-Object System.Windows.Forms.TrackBar
    $track.Dock = "Fill"
    $track.TickStyle = "None"
    $panel.Controls.Add($track, 1, 0)

    $numeric = New-Object System.Windows.Forms.NumericUpDown
    $numeric.Dock = "Fill"
    $numeric.Minimum = $Minimum
    $numeric.Maximum = $Maximum
    $numeric.Increment = $Increment
    $numeric.DecimalPlaces = $DecimalPlaces
    $panel.Controls.Add($numeric, 2, 0)

    return [PSCustomObject]@{
        Panel = $panel
        Track = $track
        Numeric = $numeric
    }
}

$offsetXRow = New-ValueRow "OffsetX" -64 64 1 0
$offsetXRow.Track.Minimum = -64
$offsetXRow.Track.Maximum = 64
$side.Controls.Add($offsetXRow.Panel, 0, 4)

$offsetYRow = New-ValueRow "OffsetY" -64 64 1 0
$offsetYRow.Track.Minimum = -64
$offsetYRow.Track.Maximum = 64
$side.Controls.Add($offsetYRow.Panel, 0, 5)

$scaleRow = New-ValueRow "Scale" 0.2 2.0 0.01 2
$scaleRow.Track.Minimum = 20
$scaleRow.Track.Maximum = 200
$side.Controls.Add($scaleRow.Panel, 0, 6)

$previewButton = New-Object System.Windows.Forms.Button
$previewButton.Text = "Preview Now"
$previewButton.Dock = "Fill"
$side.Controls.Add($previewButton, 0, 8)

$saveButton = New-Object System.Windows.Forms.Button
$saveButton.Text = "Save + Regenerate"
$saveButton.Dock = "Fill"
$saveButton.BackColor = [System.Drawing.Color]::FromArgb(224, 242, 214)
$side.Controls.Add($saveButton, 0, 9)

$resetButton = New-Object System.Windows.Forms.Button
$resetButton.Text = "Reload Saved Values"
$resetButton.Dock = "Fill"
$side.Controls.Add($resetButton, 0, 10)

$openButton = New-Object System.Windows.Forms.Button
$openButton.Text = "Open Preview Folder"
$openButton.Dock = "Fill"
$side.Controls.Add($openButton, 0, 11)

$status = New-Object System.Windows.Forms.TextBox
$status.Dock = "Fill"
$status.Multiline = $true
$status.ReadOnly = $true
$status.ScrollBars = "Vertical"
$status.Font = New-Object System.Drawing.Font "Consolas", 9
$side.Controls.Add($status, 0, 15)

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 350

function Set-Status {
    param([string]$Text)
    $status.Text = $Text
    $status.SelectionStart = $status.Text.Length
    $status.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}

function Set-PreviewImage {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }
    $newImage = Load-BitmapNoLock $Path
    $oldImage = $previewBox.Image
    $previewBox.Image = $newImage
    if ($null -ne $oldImage) {
        $oldImage.Dispose()
    }
}

function Get-SelectedLayerInfo {
    $key = [string]$layerCombo.SelectedItem
    if ([string]::IsNullOrWhiteSpace($key) -or -not $script:LayerByDisplay.ContainsKey($key)) {
        return $null
    }
    return $script:LayerByDisplay[$key]
}

function Set-ControlValues {
    param(
        [double]$OffsetX,
        [double]$OffsetY,
        [double]$Scale
    )
    $script:IsSyncingControls = $true
    try {
        $offsetXClamped = [Math]::Max(-64, [Math]::Min(64, [int][Math]::Round($OffsetX)))
        $offsetYClamped = [Math]::Max(-64, [Math]::Min(64, [int][Math]::Round($OffsetY)))
        $scaleClamped = [Math]::Max(0.2, [Math]::Min(2.0, [double]$Scale))

        $offsetXRow.Track.Value = $offsetXClamped
        $offsetXRow.Numeric.Value = [decimal]$offsetXClamped
        $offsetYRow.Track.Value = $offsetYClamped
        $offsetYRow.Numeric.Value = [decimal]$offsetYClamped
        $scaleRow.Track.Value = [int][Math]::Round($scaleClamped * 100.0)
        $scaleRow.Numeric.Value = [decimal]$scaleClamped
    }
    finally {
        $script:IsSyncingControls = $false
    }
}

function Update-Details {
    $layer = Get-SelectedLayerInfo
    if ($null -eq $layer) {
        $details.Text = ""
        return
    }
    $adjustment = Get-Adjustment ([string]$layer.asset_id)
    $details.Text = @(
        "layer: $($layer.layer)",
        "asset_id: $($layer.asset_id)",
        "runtime: $($layer.runtime)",
        "source_asset: $($layer.source_asset)",
        "modulate: $($layer.modulate)",
        "saved_offset_x: $($adjustment.OffsetX)",
        "saved_offset_y: $($adjustment.OffsetY)",
        "saved_scale: $($adjustment.Scale)",
        "review: $($adjustment.ReviewStatus)"
    ) -join [Environment]::NewLine
}

function Load-SavedValuesForSelection {
    $layer = Get-SelectedLayerInfo
    if ($null -eq $layer) {
        return
    }
    $adjustment = Get-Adjustment ([string]$layer.asset_id)
    Set-ControlValues $adjustment.OffsetX $adjustment.OffsetY $adjustment.Scale
    Update-Details
}

function Refresh-LayerList {
    param([object]$Result)
    $script:LayerByDisplay.Clear()
    $layerCombo.Items.Clear()
    foreach ($layer in @($Result.Layers)) {
        $display = "{0}: {1}" -f $layer.layer, $layer.asset_id
        $script:LayerByDisplay[$display] = $layer
        [void]$layerCombo.Items.Add($display)
    }

    $selectedIndex = 0
    if (-not [string]::IsNullOrWhiteSpace($InitialLayer)) {
        for ($i = 0; $i -lt $layerCombo.Items.Count; $i++) {
            $text = [string]$layerCombo.Items[$i]
            if ($text.Contains($InitialLayer)) {
                $selectedIndex = $i
                break
            }
        }
    }
    elseif ($layerCombo.Items.Count -gt 0) {
        for ($i = 0; $i -lt $layerCombo.Items.Count; $i++) {
            $text = [string]$layerCombo.Items[$i]
            if ($text.StartsWith("hair:")) {
                $selectedIndex = $i
                break
            }
        }
    }

    if ($layerCombo.Items.Count -gt 0) {
        $layerCombo.SelectedIndex = $selectedIndex
    }
}

function Invoke-LivePreview {
    param([switch]$SaveAndRegenerate)
    $layer = Get-SelectedLayerInfo
    if ($null -eq $layer) {
        return
    }

    $offsetX = [double]$offsetXRow.Numeric.Value
    $offsetY = [double]$offsetYRow.Numeric.Value
    $scale = [double]$scaleRow.Numeric.Value
    Set-Status ("Rendering {0} offset=({1},{2}) scale={3}..." -f $layer.asset_id, $offsetX, $offsetY, $scale)

    try {
        $result = Invoke-PreviewEngine `
            -LayerKey ([string]$layer.asset_id) `
            -OffsetX $offsetX `
            -OffsetY $offsetY `
            -Scale $scale `
            -Save:$SaveAndRegenerate `
            -Regenerate:$SaveAndRegenerate

        $script:CurrentResult = $result
        Set-PreviewImage $PreviewPath
        if ($SaveAndRegenerate) {
            Update-Details
            Set-Status ("Saved and regenerated {0}." -f $layer.asset_id)
        }
        else {
            Set-Status ("Preview updated for {0}." -f $layer.asset_id)
        }
    }
    catch {
        Set-Status ("ERROR: {0}" -f $_.Exception.Message)
    }
}

$timer.Add_Tick({
    $timer.Stop()
    Invoke-LivePreview
})

function Queue-LivePreview {
    if ($script:IsSyncingControls) {
        return
    }
    $timer.Stop()
    $timer.Start()
}

$offsetXRow.Track.Add_ValueChanged({
    if ($script:IsSyncingControls) { return }
    $offsetXRow.Numeric.Value = [decimal]$offsetXRow.Track.Value
    Queue-LivePreview
})
$offsetXRow.Numeric.Add_ValueChanged({
    if ($script:IsSyncingControls) { return }
    $offsetXRow.Track.Value = [int]$offsetXRow.Numeric.Value
    Queue-LivePreview
})

$offsetYRow.Track.Add_ValueChanged({
    if ($script:IsSyncingControls) { return }
    $offsetYRow.Numeric.Value = [decimal]$offsetYRow.Track.Value
    Queue-LivePreview
})
$offsetYRow.Numeric.Add_ValueChanged({
    if ($script:IsSyncingControls) { return }
    $offsetYRow.Track.Value = [int]$offsetYRow.Numeric.Value
    Queue-LivePreview
})

$scaleRow.Track.Add_ValueChanged({
    if ($script:IsSyncingControls) { return }
    $scaleRow.Numeric.Value = [decimal]($scaleRow.Track.Value / 100.0)
    Queue-LivePreview
})
$scaleRow.Numeric.Add_ValueChanged({
    if ($script:IsSyncingControls) { return }
    $scaleRow.Track.Value = [int][Math]::Round([double]$scaleRow.Numeric.Value * 100.0)
    Queue-LivePreview
})

$layerCombo.Add_SelectedIndexChanged({
    Load-SavedValuesForSelection
    Invoke-LivePreview
})

$previewButton.Add_Click({
    Invoke-LivePreview
})

$saveButton.Add_Click({
    Invoke-LivePreview -SaveAndRegenerate
})

$resetButton.Add_Click({
    Load-SavedValuesForSelection
    Invoke-LivePreview
})

$openButton.Add_Click({
    Start-Process -FilePath explorer.exe -ArgumentList "`"$PreviewDir`""
})

$form.Add_FormClosed({
    if ($null -ne $previewBox.Image) {
        $previewBox.Image.Dispose()
    }
})

try {
    Set-Status "Loading character preview..."
    $script:CurrentResult = Invoke-PreviewEngine
    Set-PreviewImage $PreviewPath
    Refresh-LayerList $script:CurrentResult
    Set-Status "Ready."
}
catch {
    Set-Status ("ERROR: {0}" -f $_.Exception.Message)
}

[void]$form.ShowDialog()
