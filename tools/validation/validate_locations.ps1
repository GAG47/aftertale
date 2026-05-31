$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$locationDir = Join-Path $root "data\locations"
$questDir = Join-Path $root "data\quests"
$characterDir = Join-Path $root "data\characters"
$factionDir = Join-Path $root "data\factions"
$relationDir = Join-Path $root "data\relations"
$errors = New-Object System.Collections.Generic.List[string]
$questIds = @{}
$locationsById = @{}
$characterIds = @{}
$factionIds = @{}

function Get-TerrainValue {
    param($terrain, [string]$key)

    foreach ($property in $terrain.PSObject.Properties) {
        if ($property.Name -eq $key) {
            return $property.Value
        }
    }

    return $null
}

function Test-LocationCell {
    param($locationRecord, [int]$x, [int]$y, [string]$context)

    $locationJson = $locationRecord.Json
    if ($x -lt 0 -or $y -lt 0 -or $x -ge [int]$locationJson.size.width -or $y -ge [int]$locationJson.size.height) {
        $errors.Add("Schedule cell out of bounds '$x,$y': $context")
        return
    }

    $row = [string]$locationJson.tiles[$y]
    $terrainKey = [string]$row[$x]
    $terrainValue = Get-TerrainValue $locationJson.terrain $terrainKey
    if ($null -eq $terrainValue) {
        $errors.Add("Schedule cell has undefined terrain '$terrainKey': $context")
        return
    }

    if (-not [bool]$terrainValue.walkable) {
        $errors.Add("Schedule cell is not walkable '$x,$y': $context")
    }
}

foreach ($file in Get-ChildItem -LiteralPath $locationDir -Filter "*.json") {
    try {
        $locationJson = Get-Content -Raw -Encoding UTF8 -LiteralPath $file.FullName | ConvertFrom-Json
    }
    catch {
        continue
    }

    if ($locationJson.id) {
        $locationsById[$locationJson.id] = @{
            Json = $locationJson
            File = $file.Name
        }
    }
}

foreach ($file in Get-ChildItem -LiteralPath $characterDir -Filter "*.json") {
    try {
        $characterJson = Get-Content -Raw -Encoding UTF8 -LiteralPath $file.FullName | ConvertFrom-Json
    }
    catch {
        $errors.Add("Invalid character JSON: $($file.Name)")
        continue
    }

    if (-not $characterJson.id) {
        $errors.Add("Character source missing id: $($file.Name)")
        continue
    }

    $characterIds[$characterJson.id] = $true
}

foreach ($file in Get-ChildItem -LiteralPath $factionDir -Filter "*.json") {
    try {
        $factionJson = Get-Content -Raw -Encoding UTF8 -LiteralPath $file.FullName | ConvertFrom-Json
    }
    catch {
        $errors.Add("Invalid faction JSON: $($file.Name)")
        continue
    }

    if (-not $factionJson.id) {
        $errors.Add("Faction source missing id: $($file.Name)")
        continue
    }

    $factionIds[$factionJson.id] = $true
}

foreach ($file in Get-ChildItem -LiteralPath $relationDir -Filter "*.json") {
    try {
        $relationJson = Get-Content -Raw -Encoding UTF8 -LiteralPath $file.FullName | ConvertFrom-Json
    }
    catch {
        $errors.Add("Invalid relation JSON: $($file.Name)")
        continue
    }

    foreach ($relation in @($relationJson.character_relations)) {
        if (-not $relation.source_id -or -not $characterIds.ContainsKey($relation.source_id)) {
            $errors.Add("Character relation source missing '$($relation.source_id)': $($file.Name)")
        }

        if (-not $relation.target_id -or -not $characterIds.ContainsKey($relation.target_id)) {
            $errors.Add("Character relation target missing '$($relation.target_id)': $($file.Name)")
        }
    }

    foreach ($relation in @($relationJson.faction_relations)) {
        if (-not $relation.source_id -or -not $factionIds.ContainsKey($relation.source_id)) {
            $errors.Add("Faction relation source missing '$($relation.source_id)': $($file.Name)")
        }

        if (-not $relation.target_id -or -not $factionIds.ContainsKey($relation.target_id)) {
            $errors.Add("Faction relation target missing '$($relation.target_id)': $($file.Name)")
        }
    }
}

foreach ($questFile in Get-ChildItem -LiteralPath $questDir -Filter "*.json") {
    try {
        $questJson = Get-Content -Raw -Encoding UTF8 -LiteralPath $questFile.FullName | ConvertFrom-Json
    }
    catch {
        $errors.Add("Invalid quest JSON: $($questFile.Name)")
        continue
    }

    if (-not $questJson.id) {
        $errors.Add("Quest source missing id: $($questFile.Name)")
        continue
    }

    $questIds[$questJson.id] = $true

    if (-not $questJson.objectives -or $questJson.objectives.Count -eq 0) {
        $errors.Add("Quest has no objectives: $($questFile.Name)")
    }

    foreach ($requirement in @($questJson.requirements)) {
        if ($requirement.type -in @("relation_at_least", "relation_below", "relation_stance")) {
            foreach ($side in @("source", "target")) {
                $value = $requirement.$side
                if (-not $value -or $value -eq "actor" -or $value -eq "source") {
                    continue
                }

                if (-not $characterIds.ContainsKey($value)) {
                    $errors.Add("Quest relation requirement references unknown character '$value': $($questFile.Name)")
                }
            }
        }
        elseif ($requirement.type -in @("faction_relation_at_least", "faction_relation_below", "faction_stance")) {
            foreach ($side in @("source", "target")) {
                $value = $requirement.$side
                if (-not $value -or $value -eq "actor") {
                    continue
                }

                if (-not $factionIds.ContainsKey($value)) {
                    $errors.Add("Quest faction requirement references unknown faction '$value': $($questFile.Name)")
                }
            }
        }
    }

    foreach ($reward in @($questJson.rewards)) {
        if ($reward.type -eq "item") {
            $rewardPath = $reward.source -replace "^res://", ""
            if (-not (Test-Path -LiteralPath (Join-Path $root $rewardPath))) {
                $errors.Add("Quest reward item missing '$($reward.source)': $($questFile.Name)")
            }
        }
        elseif ($reward.type -eq "relation") {
            $scope = "character"
            if ($reward.scope) {
                $scope = [string]$reward.scope
            }

            if (-not $reward.source_id) {
                $errors.Add("Quest relation reward missing source_id: $($questFile.Name)")
            }
            elseif ($scope -eq "character" -and -not $characterIds.ContainsKey($reward.source_id)) {
                $errors.Add("Quest relation reward source character missing '$($reward.source_id)': $($questFile.Name)")
            }
            elseif ($scope -eq "faction" -and -not $factionIds.ContainsKey($reward.source_id)) {
                $errors.Add("Quest relation reward source faction missing '$($reward.source_id)': $($questFile.Name)")
            }

            if (-not $reward.target_actor) {
                if (-not $reward.target_id) {
                    $errors.Add("Quest relation reward missing target_id or target_actor: $($questFile.Name)")
                }
                elseif ($scope -eq "character" -and -not $characterIds.ContainsKey($reward.target_id)) {
                    $errors.Add("Quest relation reward target character missing '$($reward.target_id)': $($questFile.Name)")
                }
                elseif ($scope -eq "faction" -and -not $factionIds.ContainsKey($reward.target_id)) {
                    $errors.Add("Quest relation reward target faction missing '$($reward.target_id)': $($questFile.Name)")
                }
            }
        }
    }
}

foreach ($file in Get-ChildItem -LiteralPath $locationDir -Filter "*.json") {
    try {
        $json = Get-Content -Raw -Encoding UTF8 -LiteralPath $file.FullName | ConvertFrom-Json
    }
    catch {
        $errors.Add("Invalid JSON: $($file.Name)")
        continue
    }

    if (-not $json.id) {
        $errors.Add("Missing id: $($file.Name)")
    }

    if (-not $json.size -or [int]$json.size.width -le 0 -or [int]$json.size.height -le 0) {
        $errors.Add("Invalid size: $($file.Name)")
        continue
    }

    if ($json.tiles.Count -ne [int]$json.size.height) {
        $errors.Add("Height mismatch: $($file.Name)")
    }

    $terrainKeys = @{}
    foreach ($property in $json.terrain.PSObject.Properties) {
        $terrainKeys[$property.Name] = $true
    }

    foreach ($row in $json.tiles) {
        if ($row.Length -ne [int]$json.size.width) {
            $errors.Add("Width mismatch: $($file.Name) row '$row'")
        }

        foreach ($char in $row.ToCharArray()) {
            $key = [string]$char
            if (-not $terrainKeys.ContainsKey($key)) {
                $errors.Add("Undefined terrain '$key': $($file.Name)")
            }
        }
    }

    foreach ($exit in @($json.exits)) {
        $targetPath = $exit.target_scene_path -replace "^res://", ""
        if (-not (Test-Path -LiteralPath (Join-Path $root $targetPath))) {
            $errors.Add("Missing exit target '$($exit.target_scene_path)': $($file.Name)")
        }
    }

    foreach ($character in @($json.characters)) {
        if (-not $character.id) {
            $errors.Add("Missing character id: $($file.Name)")
        }

        if (-not $character.source) {
            $errors.Add("Missing character source: $($file.Name)")
            continue
        }

        $characterPath = $character.source -replace "^res://", ""
        $fullCharacterPath = Join-Path $root $characterPath
        if (-not (Test-Path -LiteralPath $fullCharacterPath)) {
            $errors.Add("Missing character source '$($character.source)': $($file.Name)")
            continue
        }

        try {
            $characterJson = Get-Content -Raw -Encoding UTF8 -LiteralPath $fullCharacterPath | ConvertFrom-Json
        }
        catch {
            $errors.Add("Invalid character JSON '$($character.source)': $($file.Name)")
            continue
        }

        if (-not $characterJson.id) {
            $errors.Add("Character source missing id '$($character.source)': $($file.Name)")
        }

        if (-not $characterJson.character_kind) {
            $errors.Add("Character source missing character_kind '$($character.source)': $($file.Name)")
        }

        if ($characterJson.faction_id -and -not $factionIds.ContainsKey($characterJson.faction_id)) {
            $errors.Add("Character references unknown faction '$($characterJson.faction_id)': $($character.source)")
        }

        if ($characterJson.dialogue_source) {
            $dialoguePath = $characterJson.dialogue_source -replace "^res://", ""
            $fullDialoguePath = Join-Path $root $dialoguePath
            if (-not (Test-Path -LiteralPath $fullDialoguePath)) {
                $errors.Add("Missing dialogue source '$($characterJson.dialogue_source)': $($character.source)")
                continue
            }

            try {
                $dialogueJson = Get-Content -Raw -Encoding UTF8 -LiteralPath $fullDialoguePath | ConvertFrom-Json
            }
            catch {
                $errors.Add("Invalid dialogue JSON '$($characterJson.dialogue_source)': $($character.source)")
                continue
            }

            if (-not $dialogueJson.id) {
                $errors.Add("Dialogue source missing id '$($characterJson.dialogue_source)'")
            }

            if (-not $dialogueJson.start_node) {
                $errors.Add("Dialogue source missing start_node '$($characterJson.dialogue_source)'")
            }

            $nodeNames = @{}
            foreach ($nodeProperty in $dialogueJson.nodes.PSObject.Properties) {
                $nodeNames[$nodeProperty.Name] = $true
            }

            if ($dialogueJson.start_node -and -not $nodeNames.ContainsKey($dialogueJson.start_node)) {
                $errors.Add("Dialogue start_node does not exist '$($dialogueJson.start_node)': $($characterJson.dialogue_source)")
            }

            foreach ($nodeProperty in $dialogueJson.nodes.PSObject.Properties) {
                foreach ($option in @($nodeProperty.Value.options)) {
                    if ($option.next -and -not $nodeNames.ContainsKey($option.next)) {
                        $errors.Add("Dialogue option next node missing '$($option.next)': $($characterJson.dialogue_source)")
                    }

                    foreach ($result in @($option.results)) {
                        if ($result.action_type -eq "AcceptQuestAction") {
                            if (-not $result.quest_id) {
                                $errors.Add("Dialogue AcceptQuestAction missing quest_id: $($characterJson.dialogue_source)")
                            }
                            elseif (-not $questIds.ContainsKey($result.quest_id)) {
                                $errors.Add("Dialogue references unknown quest '$($result.quest_id)': $($characterJson.dialogue_source)")
                            }
                        }

                        if ($result.type -eq "relation_delta") {
                            $scope = "character"
                            if ($result.scope) {
                                $scope = [string]$result.scope
                            }

                            foreach ($side in @("source", "target")) {
                                $value = $result.$side
                                if (-not $value -or $value -eq "actor" -or $value -eq "speaker") {
                                    continue
                                }

                                if ($scope -eq "character" -and -not $characterIds.ContainsKey($value)) {
                                    $errors.Add("Dialogue relation result references unknown character '$value': $($characterJson.dialogue_source)")
                                }
                                elseif ($scope -eq "faction" -and -not $factionIds.ContainsKey($value)) {
                                    $errors.Add("Dialogue relation result references unknown faction '$value': $($characterJson.dialogue_source)")
                                }
                            }
                        }
                    }

                    foreach ($condition in @($option.conditions)) {
                        if ($condition.type -in @("relation_at_least", "relation_below", "relation_stance")) {
                            foreach ($side in @("source", "target")) {
                                $value = $condition.$side
                                if (-not $value -or $value -eq "actor" -or $value -eq "speaker") {
                                    continue
                                }

                                if (-not $characterIds.ContainsKey($value)) {
                                    $errors.Add("Dialogue relation condition references unknown character '$value': $($characterJson.dialogue_source)")
                                }
                            }
                        }
                        elseif ($condition.type -in @("faction_relation_at_least", "faction_relation_below", "faction_stance")) {
                            foreach ($side in @("source", "target")) {
                                $value = $condition.$side
                                if (-not $value -or $value -eq "actor" -or $value -eq "speaker") {
                                    continue
                                }

                                if (-not $factionIds.ContainsKey($value)) {
                                    $errors.Add("Dialogue faction condition references unknown faction '$value': $($characterJson.dialogue_source)")
                                }
                            }
                        }
                    }
                }
            }
        }

        if ($characterJson.schedule) {
            foreach ($scheduleEntry in @($characterJson.schedule)) {
                if (-not $scheduleEntry.id) {
                    $errors.Add("Schedule entry missing id '$($character.source)': $($file.Name)")
                }

                if (-not $scheduleEntry.start -or [string]$scheduleEntry.start -notmatch "^\d{2}:\d{2}$") {
                    $errors.Add("Schedule entry has invalid start '$($scheduleEntry.id)': $($character.source)")
                }

                if (-not $scheduleEntry.end -or [string]$scheduleEntry.end -notmatch "^\d{2}:\d{2}$") {
                    $errors.Add("Schedule entry has invalid end '$($scheduleEntry.id)': $($character.source)")
                }

                $scheduledLocationId = [string]$json.id
                if ($scheduleEntry.location_id) {
                    $scheduledLocationId = [string]$scheduleEntry.location_id
                }

                if (-not $locationsById.ContainsKey($scheduledLocationId)) {
                    $errors.Add("Schedule references unknown location '$scheduledLocationId': $($character.source)")
                    continue
                }

                if (-not $scheduleEntry.grid_position) {
                    $errors.Add("Schedule entry missing grid_position '$($scheduleEntry.id)': $($character.source)")
                    continue
                }

                Test-LocationCell $locationsById[$scheduledLocationId] ([int]$scheduleEntry.grid_position.x) ([int]$scheduleEntry.grid_position.y) "$($character.source) / $($scheduleEntry.id)"
            }
        }
    }

    foreach ($object in @($json.objects)) {
        if ($object.item -and $object.item.source) {
            $itemPath = $object.item.source -replace "^res://", ""
            $fullItemPath = Join-Path $root $itemPath
            if (-not (Test-Path -LiteralPath $fullItemPath)) {
                $errors.Add("Missing item source '$($object.item.source)': $($file.Name)")
                continue
            }

            try {
                $itemJson = Get-Content -Raw -Encoding UTF8 -LiteralPath $fullItemPath | ConvertFrom-Json
            }
            catch {
                $errors.Add("Invalid item JSON '$($object.item.source)': $($file.Name)")
                continue
            }

            if (-not $itemJson.id) {
                $errors.Add("Item source missing id '$($object.item.source)': $($file.Name)")
            }
        }
    }
}

if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Output "Project data validation passed."
