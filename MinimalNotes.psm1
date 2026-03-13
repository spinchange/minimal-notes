Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Initialize-MinimalNotesContext {
    $Script:ProjectRoot = $PSScriptRoot
    $Script:ConfigPath = Get-MinimalNotesConfigPath
    $Script:Config = Get-MinimalNotesConfig
    $Script:VaultRoot = if ($env:MINIMAL_NOTES_VAULT) {
        $env:MINIMAL_NOTES_VAULT
    } else {
        [string](Get-ConfigValue -Config $Script:Config -Key "vault" -DefaultValue (Join-Path $Script:ProjectRoot "vault"))
    }
    $Script:TemplateRoot = if ($env:MINIMAL_NOTES_TEMPLATES) {
        $env:MINIMAL_NOTES_TEMPLATES
    } else {
        [string](Get-ConfigValue -Config $Script:Config -Key "templates" -DefaultValue (Join-Path $Script:ProjectRoot "templates"))
    }
    $Script:QueriesPath = if ($env:MINIMAL_NOTES_QUERIES) {
        $env:MINIMAL_NOTES_QUERIES
    } else {
        [string](Get-ConfigValue -Config $Script:Config -Key "queries" -DefaultValue (Join-Path $Script:ProjectRoot "saved-queries.json"))
    }
    $Script:NoOpen = if ($env:MINIMAL_NOTES_NO_OPEN) {
        $env:MINIMAL_NOTES_NO_OPEN -in @("1", "true", "yes")
    } else {
        [bool](Get-ConfigValue -Config $Script:Config -Key "noOpen" -DefaultValue $false)
    }
    $Script:DefaultEditor = if ($env:MINIMAL_NOTES_EDITOR) {
        $env:MINIMAL_NOTES_EDITOR
    } elseif (Get-ConfigValue -Config $Script:Config -Key "editor") {
        [string](Get-ConfigValue -Config $Script:Config -Key "editor")
    } elseif ($env:EDITOR) {
        $env:EDITOR
    } elseif (Get-Command code -ErrorAction SilentlyContinue) {
        "code"
    } else {
        "notepad.exe"
    }
    $Script:DefaultStaleDays = [int](Get-DefaultConfigValue -Config $Script:Config -Key "staleDays" -DefaultValue 30)
    $Script:DefaultDashboardLimit = [int](Get-DefaultConfigValue -Config $Script:Config -Key "dashboardLimit" -DefaultValue 5)
}

function Get-MinimalNotesVaultPath {
    return $Script:VaultRoot
}

function Get-SavedQueriesPath {
    return $Script:QueriesPath
}

function Get-MinimalNotesConfigPath {
    if ($env:MINIMAL_NOTES_CONFIG) {
        return $env:MINIMAL_NOTES_CONFIG
    }

    return Join-Path $Script:ProjectRoot "minimal-notes.config.json"
}

function Get-MinimalNotesConfig {
    $path = Get-MinimalNotesConfigPath
    if (-not (Test-Path -LiteralPath $path)) {
        return @{}
    }

    $raw = Get-Content -LiteralPath $path -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return @{}
    }

    $config = $raw | ConvertFrom-Json -AsHashtable
    if ($config) {
        return $config
    }

    return @{}
}

function Get-ConfigValue {
    param(
        [hashtable]$Config,
        [string]$Key,
        $DefaultValue = $null
    )

    if ($Config -and $Config.ContainsKey($Key)) {
        return $Config[$Key]
    }

    return $DefaultValue
}

function Get-DefaultConfigValue {
    param(
        [hashtable]$Config,
        [string]$Key,
        $DefaultValue = $null
    )

    if ($Config -and $Config.ContainsKey("defaults")) {
        $defaults = $Config["defaults"]
        if ($defaults -is [hashtable] -and $defaults.ContainsKey($Key)) {
            return $defaults[$Key]
        }
    }

    return $DefaultValue
}

Initialize-MinimalNotesContext

function Ensure-Vault {
    if (-not (Test-Path -LiteralPath $Script:VaultRoot)) {
        New-Item -ItemType Directory -Path $Script:VaultRoot | Out-Null
    }
}

function Ensure-TemplateRoot {
    if (-not (Test-Path -LiteralPath $Script:TemplateRoot)) {
        New-Item -ItemType Directory -Path $Script:TemplateRoot | Out-Null
    }
}

function ConvertTo-NoteSlug {
    param([Parameter(Mandatory)][string]$Name)

    $slug = $Name.Trim().ToLowerInvariant()
    $slug = [regex]::Replace($slug, "\s+", "-")
    $slug = [regex]::Replace($slug, "[^a-z0-9\-_]", "")
    $slug = [regex]::Replace($slug, "-{2,}", "-").Trim("-")

    if ([string]::IsNullOrWhiteSpace($slug)) {
        throw "Could not derive a valid note name from '$Name'."
    }

    return $slug
}

function Get-NoteTitle {
    param([Parameter(Mandatory)][string]$Path)

    $firstHeading = Get-Content -LiteralPath $Path -ErrorAction Stop |
        Where-Object { $_ -match '^#\s+' } |
        Select-Object -First 1

    if ($firstHeading) {
        return ($firstHeading -replace '^#\s+', '').Trim()
    }

    return [System.IO.Path]::GetFileNameWithoutExtension($Path)
}

function Get-RelativeVaultPath {
    param([Parameter(Mandatory)][string]$Path)

    return [System.IO.Path]::GetRelativePath($Script:VaultRoot, $Path)
}

function Get-RelativeTemplatePath {
    param([Parameter(Mandatory)][string]$Path)

    return [System.IO.Path]::GetRelativePath($Script:TemplateRoot, $Path)
}

function Normalize-NoteReference {
    param([Parameter(Mandatory)][string]$Reference)

    $value = $Reference.Trim().Replace('\', '/')
    if ($value.ToLowerInvariant().EndsWith(".md")) {
        $value = $value.Substring(0, $value.Length - 3)
    }

    return $value
}

function Get-LinkReferenceForPath {
    param([Parameter(Mandatory)][string]$Path)

    return Normalize-NoteReference -Reference (Get-RelativeVaultPath -Path $Path)
}

function ConvertFrom-FrontmatterScalar {
    param([string]$Value)

    $trimmed = $Value.Trim()
    if (($trimmed.StartsWith('"') -and $trimmed.EndsWith('"')) -or ($trimmed.StartsWith("'") -and $trimmed.EndsWith("'"))) {
        return $trimmed.Substring(1, $trimmed.Length - 2)
    }

    return $trimmed
}

function ConvertTo-FrontmatterScalar {
    param($Value)

    if ($null -eq $Value) {
        return '""'
    }

    $text = [string]$Value
    if ($text -match '[:#\[\]\{\},]' -or $text -match '^\s' -or $text -match '\s$' -or $text -eq '') {
        return '"' + ($text.Replace('"', '\"')) + '"'
    }

    return $text
}

function Get-Frontmatter {
    param([Parameter(Mandatory)][string]$Path)

    $lines = @(Get-Content -LiteralPath $Path)
    $properties = [ordered]@{}

    $firstLine = if ($lines.Count -gt 0) { $lines[0].TrimStart([char]0xFEFF).Trim() } else { "" }
    if ($lines.Count -eq 0 -or $firstLine -ne "---") {
        return [pscustomobject]@{
            HasFrontmatter = $false
            Properties     = $properties
            BodyLines      = $lines
        }
    }

    $endIndex = -1
    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -eq "---") {
            $endIndex = $i
            break
        }
    }

    if ($endIndex -lt 0) {
        return [pscustomobject]@{
            HasFrontmatter = $false
            Properties     = [ordered]@{}
            BodyLines      = $lines
        }
    }

    $currentListKey = $null
    for ($i = 1; $i -lt $endIndex; $i++) {
        $line = $lines[$i]

        if ($line -match '^\s*-\s*(.+)$' -and $currentListKey) {
            $properties[$currentListKey] += @(ConvertFrom-FrontmatterScalar -Value $matches[1])
            continue
        }

        $currentListKey = $null
        if ($line -match '^([A-Za-z0-9_-]+):\s*(.*)$') {
            $key = $matches[1]
            $rest = $matches[2]
            if ([string]::IsNullOrWhiteSpace($rest)) {
                $properties[$key] = @()
                $currentListKey = $key
            } else {
                $properties[$key] = ConvertFrom-FrontmatterScalar -Value $rest
            }
        }
    }

    return [pscustomobject]@{
        HasFrontmatter = $true
        Properties     = $properties
        BodyLines      = if ($endIndex + 1 -lt $lines.Count) { @($lines[($endIndex + 1)..($lines.Count - 1)]) } else { @() }
    }
}

function Set-Frontmatter {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][hashtable]$Properties
    )

    $existing = Get-Frontmatter -Path $Path
    $output = New-Object System.Collections.Generic.List[string]

    if ($Properties.Count -gt 0) {
        $output.Add("---")
        foreach ($entry in $Properties.GetEnumerator()) {
            if ($entry.Value -is [System.Collections.IEnumerable] -and -not ($entry.Value -is [string])) {
                $output.Add(("{0}:" -f $entry.Key))
                foreach ($item in @($entry.Value)) {
                    $output.Add(("  - {0}" -f (ConvertTo-FrontmatterScalar -Value $item)))
                }
            } else {
                $output.Add(("{0}: {1}" -f $entry.Key, (ConvertTo-FrontmatterScalar -Value $entry.Value)))
            }
        }
        $output.Add("---")
        $output.Add("")
    }

    foreach ($line in $existing.BodyLines) {
        $output.Add([string]$line)
    }

    Set-Content -LiteralPath $Path -Value $output -Encoding utf8
}

function Get-AllNotes {
    Ensure-Vault

    Get-ChildItem -LiteralPath $Script:VaultRoot -Recurse -File -Filter "*.md" |
        Sort-Object FullName |
        ForEach-Object {
            $frontmatter = Get-Frontmatter -Path $_.FullName
            [pscustomobject]@{
                Path         = $_.FullName
                RelativePath = Get-RelativeVaultPath -Path $_.FullName
                Slug         = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
                Title        = Get-NoteTitle -Path $_.FullName
                LastWrite    = $_.LastWriteTime
                Properties   = $frontmatter.Properties
                Aliases      = @($frontmatter.Properties["aliases"])
            }
        }
}

function Get-PlannedNotePath {
    param([Parameter(Mandatory)][string]$Name)

    $relativeName = $Name.Trim() -replace '/', '\'
    $leafName = Split-Path -Path $relativeName -Leaf
    $parentDir = Split-Path -Path $relativeName -Parent
    $slug = ConvertTo-NoteSlug -Name $leafName
    $targetDir = if ([string]::IsNullOrWhiteSpace($parentDir)) { $Script:VaultRoot } else { Join-Path $Script:VaultRoot $parentDir }

    return Join-Path $targetDir "$slug.md"
}

function Get-PlannedTemplatePath {
    param([Parameter(Mandatory)][string]$Name)

    $relativeName = $Name.Trim() -replace '/', '\'
    $leafName = Split-Path -Path $relativeName -Leaf
    $parentDir = Split-Path -Path $relativeName -Parent
    $slug = ConvertTo-NoteSlug -Name $leafName
    $targetDir = if ([string]::IsNullOrWhiteSpace($parentDir)) { $Script:TemplateRoot } else { Join-Path $Script:TemplateRoot $parentDir }

    return Join-Path $targetDir "$slug.md"
}

function Get-AllTemplates {
    Ensure-TemplateRoot

    Get-ChildItem -LiteralPath $Script:TemplateRoot -Recurse -File -Filter "*.md" |
        Sort-Object FullName |
        ForEach-Object {
            [pscustomobject]@{
                Path         = $_.FullName
                RelativePath = Get-RelativeTemplatePath -Path $_.FullName
                Slug         = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
                Title        = Get-NoteTitle -Path $_.FullName
                LastWrite    = $_.LastWriteTime
            }
        }
}

function Resolve-Template {
    param([Parameter(Mandatory)][string]$Name)

    $trimmed = $Name.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        throw "A template name is required."
    }

    if (Test-Path -LiteralPath $trimmed) {
        return (Resolve-Path -LiteralPath $trimmed).Path
    }

    $slug = ConvertTo-NoteSlug -Name $trimmed
    $templates = @(Get-AllTemplates)

    $exactSlug = @($templates | Where-Object { $_.Slug -eq $slug })
    if ($exactSlug.Count -eq 1) {
        return $exactSlug[0].Path
    }

    $exactTitle = @($templates | Where-Object { $_.Title -eq $trimmed })
    if ($exactTitle.Count -eq 1) {
        return $exactTitle[0].Path
    }

    $normalizedTrimmed = Normalize-NoteReference -Reference $trimmed
    $byRelativePath = @($templates | Where-Object {
        (Normalize-NoteReference -Reference $_.RelativePath) -eq $normalizedTrimmed
    })
    if ($byRelativePath.Count -eq 1) {
        return $byRelativePath[0].Path
    }

    $templateMatches = foreach ($template in $templates) {
        $titleScore = Get-FuzzyScore -Query $trimmed -Candidate $template.Title
        $slugScore = Get-FuzzyScore -Query $trimmed -Candidate $template.Slug
        $pathScore = Get-FuzzyScore -Query $trimmed -Candidate $template.RelativePath
        $score = ($titleScore, $slugScore, $pathScore | Measure-Object -Maximum).Maximum

        if ($score -ge 0) {
            [pscustomobject]@{
                Score    = $score
                Template = $template
            }
        }
    }

    $fuzzy = @(
        $templateMatches |
            Sort-Object @{ Expression = "Score"; Descending = $true }, @{ Expression = { $_.Template.LastWrite }; Descending = $true } |
            Select-Object -First 2
    )

    if ($fuzzy.Count -eq 1) {
        return $fuzzy[0].Template.Path
    }
    if ($fuzzy.Count -gt 1) {
        $candidates = $fuzzy | ForEach-Object { $_.Template.Title } | Sort-Object -Unique
        throw ("Ambiguous template name '{0}'. Matches: {1}" -f $trimmed, ($candidates -join ", "))
    }

    return $null
}

function Expand-TemplateContent {
    param(
        [Parameter(Mandatory)][string]$Content,
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Slug
    )

    $now = Get-Date
    $tokens = [ordered]@{
        "{{title}}"    = $Title
        "{{slug}}"     = $Slug
        "{{date}}"     = $now.ToString("yyyy-MM-dd")
        "{{time}}"     = $now.ToString("HH:mm")
        "{{datetime}}" = $now.ToString("yyyy-MM-dd HH:mm:ss")
        "{{year}}"     = $now.ToString("yyyy")
        "{{month}}"    = $now.ToString("MM")
        "{{day}}"      = $now.ToString("dd")
    }

    $expanded = $Content
    foreach ($entry in $tokens.GetEnumerator()) {
        $expanded = $expanded.Replace($entry.Key, $entry.Value)
    }

    return $expanded
}

function Get-FuzzyScore {
    param(
        [Parameter(Mandatory)][string]$Query,
        [Parameter(Mandatory)][string]$Candidate
    )

    $q = $Query.ToLowerInvariant()
    $c = $Candidate.ToLowerInvariant()

    if ($c.Contains($q)) {
        return 1000 - ($c.Length - $q.Length)
    }

    $qi = 0
    $streak = 0
    $score = 0

    for ($ci = 0; $ci -lt $c.Length -and $qi -lt $q.Length; $ci++) {
        if ($c[$ci] -eq $q[$qi]) {
            $qi++
            $streak++
            $score += 10 + ($streak * 3)
        } else {
            $streak = 0
        }
    }

    if ($qi -ne $q.Length) {
        return -1
    }

    return $score - ($c.Length - $q.Length)
}

function Find-Notes {
    param(
        [Parameter(Mandatory)][string]$Query,
        [int]$Limit = 10
    )

    $notes = @(Get-AllNotes)
    $noteMatches = foreach ($note in $notes) {
        $titleScore = Get-FuzzyScore -Query $Query -Candidate $note.Title
        $slugScore = Get-FuzzyScore -Query $Query -Candidate $note.Slug
        $pathScore = Get-FuzzyScore -Query $Query -Candidate $note.RelativePath
        $score = ($titleScore, $slugScore, $pathScore | Measure-Object -Maximum).Maximum

        if ($score -ge 0) {
            [pscustomobject]@{
                Score = $score
                Note  = $note
            }
        }
    }

    $noteMatches |
        Sort-Object @{ Expression = "Score"; Descending = $true }, @{ Expression = { $_.Note.LastWrite }; Descending = $true } |
        Select-Object -First $Limit
}

function Resolve-Note {
    param([Parameter(Mandatory)][string]$Name)

    $trimmed = $Name.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        throw "A note name is required."
    }

    if (Test-Path -LiteralPath $trimmed) {
        return (Resolve-Path -LiteralPath $trimmed).Path
    }

    $slug = ConvertTo-NoteSlug -Name $trimmed
    $notes = @(Get-AllNotes)

    $exactSlug = @($notes | Where-Object { $_.Slug -eq $slug })
    if ($exactSlug.Count -eq 1) {
        return $exactSlug[0].Path
    }

    $exactTitle = @($notes | Where-Object { $_.Title -eq $trimmed })
    if ($exactTitle.Count -eq 1) {
        return $exactTitle[0].Path
    }

    $aliasMatches = @($notes | Where-Object { @($_.Aliases) -contains $trimmed })
    if ($aliasMatches.Count -eq 1) {
        return $aliasMatches[0].Path
    }

    $normalizedTrimmed = Normalize-NoteReference -Reference $trimmed
    $byRelativePath = @($notes | Where-Object {
        (Normalize-NoteReference -Reference $_.RelativePath) -eq $normalizedTrimmed
    })
    if ($byRelativePath.Count -eq 1) {
        return $byRelativePath[0].Path
    }

    $fuzzy = @(Find-Notes -Query $trimmed -Limit 2)
    if ($fuzzy.Count -eq 1) {
        return $fuzzy[0].Note.Path
    }
    if ($fuzzy.Count -gt 1) {
        $candidates = $fuzzy | ForEach-Object { $_.Note.Title } | Sort-Object -Unique
        throw ("Ambiguous note name '{0}'. Matches: {1}" -f $trimmed, ($candidates -join ", "))
    }

    return $null
}

function Resolve-LinkTarget {
    param([Parameter(Mandatory)][string]$Target)

    $trimmed = $Target.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        return $null
    }

    $notes = @(Get-AllNotes)
    $slug = ConvertTo-NoteSlug -Name $trimmed

    $exactSlug = @($notes | Where-Object { $_.Slug -eq $slug })
    if ($exactSlug.Count -eq 1) {
        return $exactSlug[0].Path
    }

    $exactTitle = @($notes | Where-Object { $_.Title -eq $trimmed })
    if ($exactTitle.Count -eq 1) {
        return $exactTitle[0].Path
    }

    $aliasMatches = @($notes | Where-Object { @($_.Aliases) -contains $trimmed })
    if ($aliasMatches.Count -eq 1) {
        return $aliasMatches[0].Path
    }

    $normalizedTrimmed = Normalize-NoteReference -Reference $trimmed
    $byRelativePath = @($notes | Where-Object {
        (Normalize-NoteReference -Reference $_.RelativePath) -eq $normalizedTrimmed
    })
    if ($byRelativePath.Count -eq 1) {
        return $byRelativePath[0].Path
    }

    return $null
}

function New-NoteFile {
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$TemplateName,
        [switch]$Open
    )

    Ensure-Vault

    $relativeName = $Name.Trim() -replace '/', '\'
    $leafName = Split-Path -Path $relativeName -Leaf
    $slug = ConvertTo-NoteSlug -Name $leafName
    $targetDir = Split-Path -Parent (Get-PlannedNotePath -Name $Name)
    $path = Get-PlannedNotePath -Name $Name

    if (-not (Test-Path -LiteralPath $targetDir)) {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    }

    if (-not (Test-Path -LiteralPath $path)) {
        if ($TemplateName) {
            $templatePath = Resolve-Template -Name $TemplateName
            if (-not $templatePath) {
                throw "Template not found: $TemplateName"
            }

            $templateContent = Get-Content -LiteralPath $templatePath -Raw
            $content = Expand-TemplateContent -Content $templateContent -Title $leafName -Slug $slug
            Set-Content -LiteralPath $path -Value $content -Encoding utf8
        } else {
            $content = @(
                "# $leafName"
                ""
                "Created: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
                ""
            )
            Set-Content -LiteralPath $path -Value $content -Encoding utf8
        }
    }

    if ($Open) {
        Open-InEditor -Path $path
    } else {
        $path
    }
}

function Open-InEditor {
    param([Parameter(Mandatory)][string]$Path)

    if ($Script:NoOpen) {
        Write-Output $Path
        return
    }

    if ($Script:DefaultEditor -eq "code") {
        & $Script:DefaultEditor --goto $Path
        return
    }

    & $Script:DefaultEditor $Path
}

function Get-LinkTargets {
    param([Parameter(Mandatory)][string]$Path)

    $content = Get-Content -LiteralPath $Path -Raw
    $linkMatches = [regex]::Matches($content, '\[\[([^\]]+)\]\]')

    foreach ($match in $linkMatches) {
        $raw = $match.Groups[1].Value.Trim()
        if (-not $raw) {
            continue
        }

        $parts = $raw.Split('|', 2)
        $target = $parts[0].Trim()
        if ($target) {
            $target
        }
    }
}

function Get-UnresolvedLinks {
    param([string]$Name)

    $notes = if ($Name) {
        $resolved = Resolve-Note -Name $Name
        if (-not $resolved) {
            throw "Note not found: $Name"
        }

        @(Get-AllNotes | Where-Object { $_.Path -eq $resolved })
    } else {
        @(Get-AllNotes)
    }

    foreach ($note in $notes) {
        $seen = @{}

        foreach ($target in (Get-LinkTargets -Path $note.Path)) {
            $key = $target.ToLowerInvariant()
            if ($seen.ContainsKey($key)) {
                continue
            }
            $seen[$key] = $true

            if (-not (Resolve-LinkTarget -Target $target)) {
                [pscustomobject]@{
                    Source        = $note.RelativePath
                    Target        = $target
                    SuggestedPath = Get-RelativeVaultPath -Path (Get-PlannedNotePath -Name $target)
                }
            }
        }
    }
}

function Get-BacklinkMap {
    $notes = @(Get-AllNotes)
    $map = @{}

    foreach ($note in $notes) {
        if (-not $map.ContainsKey($note.Path)) {
            $map[$note.Path] = New-Object System.Collections.ArrayList
        }
    }

    foreach ($source in $notes) {
        $seen = @{}

        foreach ($target in (Get-LinkTargets -Path $source.Path)) {
            $resolvedPath = Resolve-LinkTarget -Target $target
            if (-not $resolvedPath) {
                continue
            }

            $key = $resolvedPath.ToLowerInvariant()
            if ($seen.ContainsKey($key)) {
                continue
            }
            $seen[$key] = $true

            if (-not $map.ContainsKey($resolvedPath)) {
                $map[$resolvedPath] = New-Object System.Collections.ArrayList
            }

            [void]$map[$resolvedPath].Add($source.Path)
        }
    }

    return $map
}

function Get-NoteTags {
    param([Parameter(Mandatory)][string]$Path)

    $frontmatter = Get-Frontmatter -Path $Path
    foreach ($value in @($frontmatter.Properties["tags"])) {
        $tag = [string]$value
        if (-not [string]::IsNullOrWhiteSpace($tag)) {
            $tag.Trim().TrimStart('#').ToLowerInvariant()
        }
    }

    $content = Get-Content -LiteralPath $Path -Raw
    $tagMatches = [regex]::Matches($content, '(?<!\w)#([a-zA-Z][\w\-/]*)')

    foreach ($match in $tagMatches) {
        $tag = $match.Groups[1].Value.Trim().ToLowerInvariant()
        if ($tag) {
            $tag
        }
    }
}

function Get-Tasks {
    param([ValidateSet("open", "done", "all", "today", "overdue")][string]$State = "open")

    $notes = @(Get-AllNotes)
    $today = (Get-Date).Date
    foreach ($note in $notes) {
        $properties = $note.Properties
        $noteStatus = ([string]$properties["status"]).Trim().ToLowerInvariant()
        $priority = ([string]$properties["priority"]).Trim()
        $project = if ($properties["project"]) { [string]$properties["project"] } else { $note.Title }
        $dueDate = Try-ParseAgendaDate -Value ([string]$properties["due"])
        $scheduledDate = Try-ParseAgendaDate -Value ([string]$properties["scheduled"])

        $lineNumber = 0
        foreach ($line in (Get-Content -LiteralPath $note.Path)) {
            $lineNumber++
            $taskMatch = [regex]::Match($line, '^\s*[-*]\s+\[( |x|X)\]\s+(.+)$')
            if (-not $taskMatch.Success) {
                continue
            }

            $isDone = $taskMatch.Groups[1].Value.ToLowerInvariant() -eq "x"
            if ($State -eq "open" -and $isDone) {
                continue
            }
            if ($State -eq "done" -and -not $isDone) {
                continue
            }
            if ($State -eq "today") {
                $isToday = ($scheduledDate -and $scheduledDate.Date -eq $today) -or ($dueDate -and $dueDate.Date -eq $today)
                if ($isDone -or -not $isToday) {
                    continue
                }
            }
            if ($State -eq "overdue") {
                $isOverdue = $dueDate -and ($dueDate.Date -lt $today)
                if ($isDone -or -not $isOverdue) {
                    continue
                }
            }

            [pscustomobject]@{
                State     = if ($isDone) { "done" } else { "open" }
                Path      = $note.RelativePath
                Line      = $lineNumber
                Text      = $taskMatch.Groups[2].Value.Trim()
                NoteTitle  = $note.Title
                Project    = $project
                NoteStatus = if ($noteStatus) { $noteStatus } else { "open" }
                Priority   = $priority
                Due        = $dueDate
                Scheduled  = $scheduledDate
            }
        }
    }
}

function Try-ParseAgendaDate {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    try {
        return [datetime]::Parse($Value)
    } catch {
        return $null
    }
}

function Get-AgendaItems {
    param([ValidateSet("active", "today", "overdue", "all")][string]$Mode = "active")

    $today = (Get-Date).Date
    $closedStatuses = @("done", "completed", "cancelled", "canceled", "archived")

    foreach ($note in @(Get-AllNotes)) {
        $properties = $note.Properties
        $dueDate = Try-ParseAgendaDate -Value ([string]$properties["due"])
        $scheduledDate = Try-ParseAgendaDate -Value ([string]$properties["scheduled"])
        $status = ([string]$properties["status"]).Trim().ToLowerInvariant()
        $priority = ([string]$properties["priority"]).Trim()

        if (-not $dueDate -and -not $scheduledDate) {
            continue
        }

        if ($Mode -ne "all" -and $status -and $status -in $closedStatuses) {
            continue
        }

        $anchorDate = if ($scheduledDate) { $scheduledDate.Date } else { $dueDate.Date }
        $isOverdue = $dueDate -and ($dueDate.Date -lt $today)
        $isToday = ($scheduledDate -and $scheduledDate.Date -eq $today) -or ($dueDate -and $dueDate.Date -eq $today)

        $includeItem = switch ($Mode) {
            "today" { $isToday }
            "overdue" { $isOverdue }
            "active" { -not ($anchorDate -lt $today -and -not $isOverdue) }
            default { $true }
        }

        if (-not $includeItem) {
            continue
        }

        [pscustomobject]@{
            Title      = $note.Title
            Path       = $note.RelativePath
            Due        = $dueDate
            Scheduled  = $scheduledDate
            Status     = if ($status) { $status } else { "open" }
            Priority   = $priority
            AnchorDate = $anchorDate
            IsOverdue  = [bool]$isOverdue
            IsToday    = [bool]$isToday
        }
    }
}

function Get-LinkMatcherKeys {
    param([Parameter(Mandatory)][string]$Path)

    $frontmatter = Get-Frontmatter -Path $Path
    $title = Get-NoteTitle -Path $Path
    $slug = [System.IO.Path]::GetFileNameWithoutExtension($Path)
    $relative = Get-LinkReferenceForPath -Path $Path

    return @(
        $title,
        $slug,
        $relative
    ) + @($frontmatter.Properties["aliases"]) |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        ForEach-Object { Normalize-NoteReference -Reference $_ } |
        Sort-Object -Unique
}

function Format-PropertyValue {
    param($Value)

    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        return (@($Value) -join ", ")
    }

    return [string]$Value
}

function Normalize-PropertyKey {
    param([Parameter(Mandatory)][string]$Key)

    $normalized = $Key.Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        throw "Property key is required."
    }

    return $normalized
}

function Test-PropertyValueDate {
    param([Parameter(Mandatory)][string]$Value)

    return $null -ne (Try-ParseAgendaDate -Value $Value)
}

function Get-ValidatedPropertyValues {
    param(
        [Parameter(Mandatory)][string]$Key,
        [string[]]$Values,
        [switch]$AllowEmpty
    )

    $normalizedKey = Normalize-PropertyKey -Key $Key
    $rawText = ($Values -join " ").Trim()
    if (-not $AllowEmpty -and [string]::IsNullOrWhiteSpace($rawText)) {
        throw "Property value is required."
    }

    $items = if ($normalizedKey -in @("tags", "aliases")) {
        @($rawText -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    } elseif ($AllowEmpty -and [string]::IsNullOrWhiteSpace($rawText)) {
        @()
    } else {
        @($rawText)
    }

    switch ($normalizedKey) {
        "status" {
            $valid = @("open", "active", "in-progress", "blocked", "waiting", "done", "completed", "cancelled", "canceled", "archived")
            foreach ($item in $items) {
                if ($item.Trim().ToLowerInvariant() -notin $valid) {
                    throw ("Invalid status '{0}'. Valid values: {1}" -f $item, ($valid -join ", "))
                }
            }
        }
        "priority" {
            $valid = @("low", "medium", "normal", "high", "urgent")
            foreach ($item in $items) {
                if ($item.Trim().ToLowerInvariant() -notin $valid) {
                    throw ("Invalid priority '{0}'. Valid values: {1}" -f $item, ($valid -join ", "))
                }
            }
        }
        { $_ -in @("due", "scheduled") } {
            foreach ($item in $items) {
                if (-not (Test-PropertyValueDate -Value $item)) {
                    throw ("Invalid {0} date '{1}'. Use a parseable date like YYYY-MM-DD." -f $normalizedKey, $item)
                }
            }
        }
        { $_ -in @("tags", "aliases") } {
            foreach ($item in $items) {
                if ([string]::IsNullOrWhiteSpace($item)) {
                    throw ("{0} values cannot be empty." -f $normalizedKey)
                }
            }
        }
    }

    return [pscustomobject]@{
        Key    = $normalizedKey
        Values = @($items)
    }
}

function Show-Properties {
    param([Parameter(Mandatory)][string]$Name)

    $path = Resolve-Note -Name $Name
    if (-not $path) {
        throw "Note not found: $Name"
    }

    $frontmatter = Get-Frontmatter -Path $path
    foreach ($entry in $frontmatter.Properties.GetEnumerator()) {
        "{0}: {1}" -f $entry.Key, (Format-PropertyValue -Value $entry.Value)
    }
}

function Set-PropertyValue {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string[]]$Values
    )

    $path = Resolve-Note -Name $Name
    if (-not $path) {
        throw "Note not found: $Name"
    }

    $frontmatter = Get-Frontmatter -Path $path
    $properties = [ordered]@{}
    foreach ($entry in $frontmatter.Properties.GetEnumerator()) {
        $properties[$entry.Key] = $entry.Value
    }

    $validated = Get-ValidatedPropertyValues -Key $Key -Values $Values
    if ($validated.Key -in @("tags", "aliases")) {
        $properties[$validated.Key] = @($validated.Values)
    } else {
        $properties[$validated.Key] = @($validated.Values)[0]
    }

    Set-Frontmatter -Path $path -Properties $properties
    Write-Output $path
}

function Add-PropertyValue {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string[]]$Values
    )

    $path = Resolve-Note -Name $Name
    if (-not $path) {
        throw "Note not found: $Name"
    }

    $frontmatter = Get-Frontmatter -Path $path
    $properties = [ordered]@{}
    foreach ($entry in $frontmatter.Properties.GetEnumerator()) {
        $properties[$entry.Key] = $entry.Value
    }

    $validated = Get-ValidatedPropertyValues -Key $Key -Values $Values
    $existing = @($properties[$validated.Key])
    $properties[$validated.Key] = @($existing + $validated.Values | Sort-Object -Unique)
    Set-Frontmatter -Path $path -Properties $properties
    Write-Output $path
}

function Remove-PropertyValue {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string[]]$Values
    )

    $path = Resolve-Note -Name $Name
    if (-not $path) {
        throw "Note not found: $Name"
    }

    $frontmatter = Get-Frontmatter -Path $path
    $properties = [ordered]@{}
    foreach ($entry in $frontmatter.Properties.GetEnumerator()) {
        $properties[$entry.Key] = $entry.Value
    }

    $validated = Get-ValidatedPropertyValues -Key $Key -Values $Values
    $remaining = @($properties[$validated.Key] | Where-Object { $_ -notin $validated.Values })
    if ($remaining.Count -eq 0) {
        if ($properties.Contains($validated.Key)) {
            $properties.Remove($validated.Key)
        }
    } else {
        $properties[$validated.Key] = $remaining
    }

    Set-Frontmatter -Path $path -Properties $properties
    Write-Output $path
}

function Unset-PropertyValue {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Key
    )

    $path = Resolve-Note -Name $Name
    if (-not $path) {
        throw "Note not found: $Name"
    }

    $frontmatter = Get-Frontmatter -Path $path
    $properties = [ordered]@{}
    foreach ($entry in $frontmatter.Properties.GetEnumerator()) {
        $properties[$entry.Key] = $entry.Value
    }

    $normalizedKey = Normalize-PropertyKey -Key $Key
    if ($properties.Contains($normalizedKey)) {
        $properties.Remove($normalizedKey)
    }

    Set-Frontmatter -Path $path -Properties $properties
    Write-Output $path
}

function Update-LinksInContent {
    param(
        [Parameter(Mandatory)][string]$Content,
        [Parameter(Mandatory)][string[]]$OldKeys,
        [Parameter(Mandatory)][string]$NewTarget
    )

    return [regex]::Replace($Content, '\[\[([^\]]+)\]\]', {
        param($match)

        $raw = $match.Groups[1].Value
        $parts = $raw.Split('|', 2)
        $target = $parts[0].Trim()
        $alias = if ($parts.Count -gt 1) { $parts[1] } else { $null }

        if ((Normalize-NoteReference -Reference $target) -notin $OldKeys) {
            return $match.Value
        }

        if ($null -ne $alias) {
            return "[[{0}|{1}]]" -f $NewTarget, $alias
        }

        return "[[{0}]]" -f $NewTarget
    })
}

function Get-HeadingMatch {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Line,
        [Parameter(Mandatory)][string]$Heading
    )

    $match = [regex]::Match($Line, '^(#+)\s+(.+?)\s*$')
    if (-not $match.Success) {
        return $null
    }

    if ($match.Groups[2].Value.Trim() -ne $Heading.Trim()) {
        return $null
    }

    return [pscustomobject]@{
        Level = $match.Groups[1].Value.Length
        Title = $match.Groups[2].Value.Trim()
    }
}

function Get-SectionRange {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string[]]$Lines,
        [Parameter(Mandatory)][string]$Heading
    )

    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $headingMatch = Get-HeadingMatch -Line $Lines[$i] -Heading $Heading
        if (-not $headingMatch) {
            continue
        }

        $start = $i
        $end = $Lines.Count - 1
        for ($j = $i + 1; $j -lt $Lines.Count; $j++) {
            $nextMatch = [regex]::Match($Lines[$j], '^(#+)\s+(.+?)\s*$')
            if ($nextMatch.Success -and $nextMatch.Groups[1].Value.Length -le $headingMatch.Level) {
                $end = $j - 1
                break
            }
        }

        return [pscustomobject]@{
            Start = $start
            End   = $end
            Level = $headingMatch.Level
            Title = $headingMatch.Title
        }
    }

    return $null
}

function Merge-Notes {
    param(
        [Parameter(Mandatory)][string]$SourceName,
        [Parameter(Mandatory)][string]$TargetName
    )

    $sourcePath = Resolve-Note -Name $SourceName
    if (-not $sourcePath) {
        throw "Source note not found: $SourceName"
    }

    $targetPath = Resolve-Note -Name $TargetName
    if (-not $targetPath) {
        throw "Target note not found: $TargetName"
    }

    if ($sourcePath -eq $targetPath) {
        throw "Source and target notes must be different."
    }

    $sourceTitle = Get-NoteTitle -Path $sourcePath
    $targetTitle = Get-NoteTitle -Path $targetPath
    $sourceContent = Get-Content -LiteralPath $sourcePath -Raw
    $targetContent = Get-Content -LiteralPath $targetPath -Raw
    $sourceKeys = @(Get-LinkMatcherKeys -Path $sourcePath)
    $targetLinkTarget = $targetTitle

    $mergedBlock = @(
        ""
        "## Merged from $sourceTitle"
        ""
        (Update-LinksInContent -Content $sourceContent -OldKeys $sourceKeys -NewTarget $targetLinkTarget)
    ) -join [Environment]::NewLine

    $updatedTarget = ($targetContent.TrimEnd() + [Environment]::NewLine + $mergedBlock.TrimEnd() + [Environment]::NewLine)
    Set-Content -LiteralPath $targetPath -Value $updatedTarget -Encoding utf8

    Get-ChildItem -LiteralPath $Script:VaultRoot -Recurse -File -Filter "*.md" |
        Where-Object { $_.FullName -ne $sourcePath } |
        ForEach-Object {
            $content = Get-Content -LiteralPath $_.FullName -Raw
            $updated = Update-LinksInContent -Content $content -OldKeys $sourceKeys -NewTarget $targetLinkTarget
            if ($updated -cne $content) {
                Set-Content -LiteralPath $_.FullName -Value $updated -Encoding utf8
            }
        }

    Remove-Item -LiteralPath $sourcePath -Force
    Write-Output $targetPath
}

function Split-NoteSection {
    param(
        [Parameter(Mandatory)][string]$SourceName,
        [Parameter(Mandatory)][string]$Heading,
        [string]$NewName
    )

    $sourcePath = Resolve-Note -Name $SourceName
    if (-not $sourcePath) {
        throw "Source note not found: $SourceName"
    }

    $sourceLines = @(Get-Content -LiteralPath $sourcePath)
    $range = Get-SectionRange -Lines $sourceLines -Heading $Heading
    if (-not $range) {
        throw "Heading not found in note: $Heading"
    }

    $newNoteName = if ($NewName) { $NewName } else { $range.Title }
    $newPath = Get-PlannedNotePath -Name $newNoteName
    if (Test-Path -LiteralPath $newPath) {
        throw "Target note already exists: $newPath"
    }
    $replacementTarget = $newNoteName

    $sectionLines = @($sourceLines[$range.Start..$range.End])
    $bodyLines = if ($sectionLines.Count -gt 1) { @($sectionLines[1..($sectionLines.Count - 1)]) } else { @() }
    $newContent = @(
        "# $($range.Title)"
        ""
    ) + $bodyLines
    Set-Content -LiteralPath $newPath -Value $newContent -Encoding utf8

    $replacement = @(
        "## $($range.Title)"
        ""
        "Moved to [[{0}]]." -f $replacementTarget
        ""
    )

    $updatedLines = @()
    if ($range.Start -gt 0) {
        $updatedLines += @($sourceLines[0..($range.Start - 1)])
    }
    $updatedLines += $replacement
    if ($range.End + 1 -lt $sourceLines.Count) {
        $updatedLines += @($sourceLines[($range.End + 1)..($sourceLines.Count - 1)])
    }

    Set-Content -LiteralPath $sourcePath -Value $updatedLines -Encoding utf8
    Write-Output $newPath
}

function Repair-Links {
    param([string]$Target)

    $items = @(Get-UnresolvedLinks)
    if ($items.Count -eq 0) {
        return
    }

    if ($Target) {
        $normalized = $Target.Trim().ToLowerInvariant()
        if ($normalized -ne "all") {
            $items = @($items | Where-Object { $_.Target.ToLowerInvariant() -eq $normalized })
        }
    }

    $repaired = New-Object System.Collections.Generic.List[string]

    foreach ($group in @($items | Group-Object Target)) {
        $matches = @(Find-Notes -Query $group.Name -Limit 2)
        if ($matches.Count -ne 1) {
            continue
        }

        $replacementTitle = $matches[0].Note.Title
        foreach ($item in @($group.Group)) {
            $sourcePath = Join-Path $Script:VaultRoot $item.Source
            if (-not (Test-Path -LiteralPath $sourcePath)) {
                continue
            }

            $content = Get-Content -LiteralPath $sourcePath -Raw
            $updated = Update-LinksInContent -Content $content -OldKeys @((Normalize-NoteReference -Reference $item.Target)) -NewTarget $replacementTitle
            if ($updated -cne $content) {
                Set-Content -LiteralPath $sourcePath -Value $updated -Encoding utf8
                $repaired.Add(("{0} -> [[{1}]] => [[{2}]]" -f $item.Source, $item.Target, $replacementTitle))
            }
        }
    }

    $repaired | Sort-Object -Unique
}

function New-TemplateFile {
    param([Parameter(Mandatory)][string]$Name)

    Ensure-TemplateRoot

    $path = Get-PlannedTemplatePath -Name $Name
    $targetDir = Split-Path -Parent $path
    $leafName = Split-Path -Leaf ($Name.Trim() -replace '/', '\')

    if (-not (Test-Path -LiteralPath $targetDir)) {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    }

    if (-not (Test-Path -LiteralPath $path)) {
        $content = @(
            "# {{title}}"
            ""
            "Created: {{datetime}}"
            ""
            "<!-- Template: $leafName -->"
            ""
        )
        Set-Content -LiteralPath $path -Value $content -Encoding utf8
    }

    return $path
}

function Show-Templates {
    foreach ($template in @(Get-AllTemplates)) {
        "{0}  {1}" -f $template.Title, $template.RelativePath
    }
}

function Show-TemplatePreview {
    param([Parameter(Mandatory)][string]$Name)

    $path = Resolve-Template -Name $Name
    if (-not $path) {
        throw "Template not found: $Name"
    }

    Get-Content -LiteralPath $path
}

function Parse-NewCommandArguments {
    param([string[]]$Values)

    if ($Values.Count -eq 0) {
        throw "Usage: ./note.ps1 new `"My Note`" [--template template-name]"
    }

    $templateIndex = [Array]::IndexOf($Values, "--template")
    if ($templateIndex -lt 0) {
        return [pscustomobject]@{
            Name         = Require-Argument -Values $Values -Message "Usage: ./note.ps1 new `"My Note`" [--template template-name]"
            TemplateName = $null
        }
    }

    if ($templateIndex -eq 0 -or $templateIndex -eq ($Values.Count - 1)) {
        throw "Usage: ./note.ps1 new `"My Note`" [--template template-name]"
    }

    $nameParts = @($Values[0..($templateIndex - 1)])
    $templateParts = @($Values[($templateIndex + 1)..($Values.Count - 1)])

    return [pscustomobject]@{
        Name         = Require-Argument -Values $nameParts -Message "Usage: ./note.ps1 new `"My Note`" [--template template-name]"
        TemplateName = Require-Argument -Values $templateParts -Message "Template name is required."
    }
}

function Show-Help {
    @"
Minimal Notes CLI

Usage:
  ./note.ps1 new "My Note"
  ./note.ps1 new "My Note" --template meeting
  ./note.ps1 open "My Note"
  ./note.ps1 list
  ./note.ps1 list idea
  ./note.ps1 search powershell
  ./note.ps1 find pwsh
  ./note.ps1 pick
  ./note.ps1 pick termui
  ./note.ps1 capture "remember this"
  ./note.ps1 capture daily "ship the prototype"
  ./note.ps1 orphans
  ./note.ps1 recent
  ./note.ps1 recent 5
  ./note.ps1 stale
  ./note.ps1 stale 60
  ./note.ps1 config
  ./note.ps1 config init
  ./note.ps1 config path
  ./note.ps1 dashboard
  ./note.ps1 dashboard 7
  ./note.ps1 agenda
  ./note.ps1 agenda today
  ./note.ps1 agenda overdue
  ./note.ps1 report
  ./note.ps1 report monthly
  ./note.ps1 review
  ./note.ps1 review weekly
  ./note.ps1 tasks
  ./note.ps1 tasks all
  ./note.ps1 tasks done
  ./note.ps1 tasks today
  ./note.ps1 tasks overdue
  ./note.ps1 related "My Note"
  ./note.ps1 graph
  ./note.ps1 graph "My Note"
  ./note.ps1 merge "Source Note" "Target Note"
  ./note.ps1 split "Source Note" "Section Heading"
  ./note.ps1 split "Source Note" "Section Heading" "New Note"
  ./note.ps1 repair-links
  ./note.ps1 repair-links all
  ./note.ps1 query
  ./note.ps1 query save work-today tasks today
  ./note.ps1 query run work-today
  ./note.ps1 dedupe
  ./note.ps1 template
  ./note.ps1 template list
  ./note.ps1 template show meeting
  ./note.ps1 template new meeting
  ./note.ps1 props "My Note"
  ./note.ps1 props "My Note" set status active
  ./note.ps1 props "My Note" unset status
  ./note.ps1 props "My Note" add tags work,planning
  ./note.ps1 rename "Old Note" "New Note"
  ./note.ps1 unresolved
  ./note.ps1 unresolved "My Note"
  ./note.ps1 create-unresolved "Target Note"
  ./note.ps1 create-unresolved all
  ./note.ps1 links "My Note"
  ./note.ps1 backlinks "My Note"
  ./note.ps1 tags
  ./note.ps1 tags idea
  ./note.ps1 preview "My Note"
  ./note.ps1 daily
  ./note.ps1 daily 2026-03-12

Commands:
  new        Create a note from a title or path-like name, optionally from a template.
  open       Open an existing note in your editor.
  list       List notes in the vault, optionally filtered.
  search     Literal full-text search across all markdown notes.
  find       Fuzzy-find notes by title, slug, or path.
  pick       Interactively choose a note to open.
  capture    Append a quick note to inbox.md or today's daily note.
  orphans    List notes with no inbound wiki links.
  recent     List recently modified notes, newest first.
  stale      List notes untouched for at least N days.
  config     Show, initialize, or locate the JSON config file.
  dashboard  Show a compact multi-section vault overview.
  agenda     Show notes with due or scheduled frontmatter dates.
  report     Summarize recent note and task activity for a time window.
  review     Show a daily or weekly review checklist and focus items.
  tasks      Collect markdown checkbox tasks with frontmatter context.
  related    Suggest notes related to a target note by links and tags.
  graph      Print a Mermaid note-link graph for one note or the full vault.
  merge      Merge one note into another and rewrite inbound links.
  split      Split a heading section into a new linked note.
  repair-links Attempt to repair unresolved wiki links using fuzzy note matches.
  query      Save, list, show, run, or delete read-only saved queries.
  dedupe     Preview likely duplicate notes without changing files.
  template   List, preview, or create note templates in templates/.
  props      Read or update frontmatter properties for a note, including unset and validation.
  rename     Rename a note file and update wiki links that point to it.
  unresolved List unresolved wiki links across the vault or in one note.
  create-unresolved  Create notes for one unresolved link target or all missing targets.
  links      Show outgoing wiki links from a note.
  backlinks  Show notes that link to a note.
  tags       List all tags, or notes containing a tag.
  preview    Print a note to the terminal.
  daily      Open or create a daily note at daily/YYYY-MM-DD.md.
  weekly     Open or create a weekly note at weekly/YYYY-Www.md.
  monthly    Open or create a monthly note at monthly/YYYY-MM.md.
  path       Print the vault path.
  help       Show this help.

Environment:
  MINIMAL_NOTES_CONFIG  Override the config file location.
  MINIMAL_NOTES_VAULT   Override the vault location.
  MINIMAL_NOTES_TEMPLATES Override the templates location.
  MINIMAL_NOTES_EDITOR  Override the editor command.
  MINIMAL_NOTES_NO_OPEN Skip launching the editor and print the file path instead.
"@
}

function Require-Argument {
    param(
        [string[]]$Values,
        [string]$Message
    )

    $value = ($Values -join " ").Trim()
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw $Message
    }

    return $value
}

function Search-Notes {
    param([Parameter(Mandatory)][string]$Pattern)

    $hits = Get-ChildItem -LiteralPath $Script:VaultRoot -Recurse -File -Filter "*.md" |
        Select-String -Pattern $Pattern -SimpleMatch

    foreach ($hit in $hits) {
        $relativePath = Get-RelativeVaultPath -Path $hit.Path
        "{0}:{1}: {2}" -f $relativePath, $hit.LineNumber, $hit.Line.Trim()
    }
}

function List-Notes {
    param([string]$Filter)

    $notes = @(Get-AllNotes)
    if ($Filter) {
        $needle = $Filter.ToLowerInvariant()
        $notes = $notes | Where-Object {
            $_.Title.ToLowerInvariant().Contains($needle) -or
            $_.RelativePath.ToLowerInvariant().Contains($needle)
        }
    }

    foreach ($note in $notes) {
        "{0}  {1}  {2}" -f $note.LastWrite.ToString("yyyy-MM-dd HH:mm"), $note.Title, $note.RelativePath
    }
}

function Show-FindResults {
    param([Parameter(Mandatory)][string]$Query)

    foreach ($match in (Find-Notes -Query $Query)) {
        "{0}  {1}  {2}" -f $match.Score, $match.Note.Title, $match.Note.RelativePath
    }
}

function Read-ShortInput {
    param([Parameter(Mandatory)][string]$Prompt)

    $value = Read-Host -Prompt $Prompt
    if ($null -eq $value) {
        return ""
    }

    return $value.Trim()
}

function Invoke-NotePicker {
    param([string]$InitialQuery)

    $query = if ($InitialQuery) { $InitialQuery.Trim() } else { "" }

    if ([string]::IsNullOrWhiteSpace($query)) {
        $query = Read-ShortInput -Prompt "Find note"
        if ([string]::IsNullOrWhiteSpace($query)) {
            throw "A search query is required."
        }
    }

    $pickerMatches = @(Find-Notes -Query $query)

    if ($pickerMatches.Count -eq 0) {
        $create = Read-ShortInput -Prompt "No matches for '$query'. Create it? [y/N]"
        if ($create -match '^(y|yes)$') {
            $path = New-NoteFile -Name $query
            Open-InEditor -Path $path
            return
        }

        Write-Output "No note selected."
        return
    }

    Write-Output ""
    Write-Output ("Matches for '{0}':" -f $query)
    for ($i = 0; $i -lt $pickerMatches.Count; $i++) {
        $match = $pickerMatches[$i]
        "{0}. {1}  {2}" -f ($i + 1), $match.Note.Title, $match.Note.RelativePath
    }
    Write-Output "0. Cancel"
    Write-Output ""

    $selection = Read-ShortInput -Prompt "Open which note"
    if ($selection -eq "0" -or [string]::IsNullOrWhiteSpace($selection)) {
        Write-Output "No note selected."
        return
    }

    $index = 0
    if (-not [int]::TryParse($selection, [ref]$index)) {
        throw "Please enter a number from the list."
    }

    if ($index -lt 1 -or $index -gt $pickerMatches.Count) {
        throw "Selection out of range."
    }

    Open-InEditor -Path $pickerMatches[$index - 1].Note.Path
}

function Show-Links {
    param([Parameter(Mandatory)][string]$Name)

    $path = Resolve-Note -Name $Name
    if (-not $path) {
        throw "Note not found: $Name"
    }

    Get-LinkTargets -Path $path |
        Sort-Object -Unique
}

function Show-Backlinks {
    param([Parameter(Mandatory)][string]$Name)

    $path = Resolve-Note -Name $Name
    if (-not $path) {
        throw "Note not found: $Name"
    }

    $title = Get-NoteTitle -Path $path
    $slug = [System.IO.Path]::GetFileNameWithoutExtension($path)
    $escapedTitle = [regex]::Escape($title)
    $escapedSlug = [regex]::Escape($slug)
    $pattern = "\[\[(?:$escapedTitle|$escapedSlug)(?:\|[^\]]+)?\]\]"

    Get-ChildItem -LiteralPath $Script:VaultRoot -Recurse -File -Filter "*.md" |
        Where-Object { $_.FullName -ne $path } |
        Select-String -Pattern $pattern |
        Select-Object -ExpandProperty Path -Unique |
        ForEach-Object {
            Get-RelativeVaultPath -Path $_
        }
}

function Show-Tags {
    param([string]$Tag)

    $notes = @(Get-AllNotes)

    if ($Tag) {
        $normalizedTag = $Tag.Trim().TrimStart('#').ToLowerInvariant()
        foreach ($note in $notes) {
            $tags = @(Get-NoteTags -Path $note.Path | Sort-Object -Unique)
            if ($tags -contains $normalizedTag) {
                "{0}  {1}" -f $note.Title, $note.RelativePath
            }
        }
        return
    }

    foreach ($group in ($notes |
        ForEach-Object { Get-NoteTags -Path $_.Path } |
        Group-Object |
        Sort-Object @{ Expression = "Count"; Descending = $true }, @{ Expression = "Name"; Descending = $false })) {
        "#{0}  {1}" -f $group.Name, $group.Count
    }
}

function Show-Preview {
    param([Parameter(Mandatory)][string]$Name)

    $path = Resolve-Note -Name $Name
    if (-not $path) {
        throw "Note not found: $Name"
    }

    Get-Content -LiteralPath $path
}

function Show-UnresolvedLinks {
    param([string]$Name)

    $items = @(Get-UnresolvedLinks -Name $Name)
    foreach ($item in $items) {
        "{0} -> [[{1}]] -> {2}" -f $item.Source, $item.Target, $item.SuggestedPath
    }
}

function Show-Orphans {
    $notes = @(Get-AllNotes)
    $backlinkMap = Get-BacklinkMap

    foreach ($note in $notes) {
        $incomingCount = if ($backlinkMap.ContainsKey($note.Path)) { $backlinkMap[$note.Path].Count } else { 0 }
        if ($incomingCount -eq 0) {
            "{0}  {1}" -f $note.Title, $note.RelativePath
        }
    }
}

function Show-RecentNotes {
    param([string]$LimitText)

    $limit = 10
    if ($LimitText) {
        if (-not [int]::TryParse($LimitText.Trim(), [ref]$limit)) {
            throw "Recent limit must be a whole number."
        }
        if ($limit -lt 1) {
            throw "Recent limit must be at least 1."
        }
    }

    Get-AllNotes |
        Sort-Object LastWrite -Descending |
        Select-Object -First $limit |
        ForEach-Object {
            "{0}  {1}  {2}" -f $_.LastWrite.ToString("yyyy-MM-dd HH:mm"), $_.Title, $_.RelativePath
        }
}

function Show-Agenda {
    param([string]$ModeText)

    $mode = if ($ModeText) { $ModeText.Trim().ToLowerInvariant() } else { "active" }
    if ($mode -notin @("active", "today", "overdue", "all")) {
        throw "Agenda filter must be one of: active, today, overdue, all."
    }

    Get-AgendaItems -Mode $mode |
        Sort-Object @{ Expression = "AnchorDate"; Descending = $false }, @{ Expression = "Title"; Descending = $false } |
        ForEach-Object {
            $dateParts = @()
            if ($_.Scheduled) {
                $dateParts += ("scheduled {0}" -f $_.Scheduled.ToString("yyyy-MM-dd"))
            }
            if ($_.Due) {
                $dateParts += ("due {0}" -f $_.Due.ToString("yyyy-MM-dd"))
            }

            $suffixParts = @()
            $suffixParts += $_.Status
            if ($_.Priority) {
                $suffixParts += ("priority {0}" -f $_.Priority)
            }
            if ($_.IsOverdue) {
                $suffixParts += "overdue"
            } elseif ($_.IsToday) {
                $suffixParts += "today"
            }

            "{0}  {1}  [{2}]  {3}" -f $_.Title, $_.Path, ($dateParts -join "; "), ($suffixParts -join ", ")
        }
}

function Show-Tasks {
    param([string]$StateText)

    $state = if ($StateText) { $StateText.Trim().ToLowerInvariant() } else { "open" }
    if ($state -notin @("open", "done", "all", "today", "overdue")) {
        throw "Task filter must be one of: open, done, all, today, overdue."
    }

    foreach ($task in (Get-Tasks -State $state)) {
        $contextParts = @()
        if ($task.Project) {
            $contextParts += ("project {0}" -f $task.Project)
        }
        if ($task.NoteStatus) {
            $contextParts += ("status {0}" -f $task.NoteStatus)
        }
        if ($task.Priority) {
            $contextParts += ("priority {0}" -f $task.Priority)
        }
        if ($task.Scheduled) {
            $contextParts += ("scheduled {0}" -f $task.Scheduled.ToString("yyyy-MM-dd"))
        }
        if ($task.Due) {
            $contextParts += ("due {0}" -f $task.Due.ToString("yyyy-MM-dd"))
        }

        $contextText = if ($contextParts.Count -gt 0) {
            "  (" + ($contextParts -join ", ") + ")"
        } else {
            ""
        }

        "{0}:{1}  [{2}] {3}{4}" -f $task.Path, $task.Line, $task.State, $task.Text, $contextText
    }
}

function Format-Section {
    param(
        [Parameter(Mandatory)][string]$Title,
        [string[]]$Lines
    )

    Write-Output ("== {0} ==" -f $Title)
    if ($Lines -and $Lines.Count -gt 0) {
        foreach ($line in $Lines) {
            Write-Output $line
        }
    } else {
        Write-Output "(none)"
    }
    Write-Output ""
}

function Format-AgendaItemLine {
    param([Parameter(Mandatory)]$Item)

    $dateParts = @()
    if ($Item.Scheduled) {
        $dateParts += ("scheduled {0}" -f $Item.Scheduled.ToString("yyyy-MM-dd"))
    }
    if ($Item.Due) {
        $dateParts += ("due {0}" -f $Item.Due.ToString("yyyy-MM-dd"))
    }

    $suffixParts = @()
    $suffixParts += $Item.Status
    if ($Item.Priority) {
        $suffixParts += ("priority {0}" -f $Item.Priority)
    }
    if ($Item.IsOverdue) {
        $suffixParts += "overdue"
    } elseif ($Item.IsToday) {
        $suffixParts += "today"
    }

    return ("{0}  {1}  [{2}]  {3}" -f $Item.Title, $Item.Path, ($dateParts -join "; "), ($suffixParts -join ", "))
}

function Format-TaskLine {
    param([Parameter(Mandatory)]$Task)

    $contextParts = @()
    if ($Task.Project) {
        $contextParts += ("project {0}" -f $Task.Project)
    }
    if ($Task.NoteStatus) {
        $contextParts += ("status {0}" -f $Task.NoteStatus)
    }
    if ($Task.Priority) {
        $contextParts += ("priority {0}" -f $Task.Priority)
    }
    if ($Task.Scheduled) {
        $contextParts += ("scheduled {0}" -f $Task.Scheduled.ToString("yyyy-MM-dd"))
    }
    if ($Task.Due) {
        $contextParts += ("due {0}" -f $Task.Due.ToString("yyyy-MM-dd"))
    }

    $contextText = if ($contextParts.Count -gt 0) {
        "  (" + ($contextParts -join ", ") + ")"
    } else {
        ""
    }

    return ("{0}:{1}  [{2}] {3}{4}" -f $Task.Path, $Task.Line, $Task.State, $Task.Text, $contextText)
}

function Get-RecentNotes {
    param([int]$Limit = 10)

    if ($Limit -lt 1) {
        throw "Recent limit must be at least 1."
    }

    return @(Get-AllNotes |
        Sort-Object LastWrite -Descending |
        Select-Object -First $Limit)
}

function Get-StaleNotes {
    param([int]$Days = 30)

    if ($Days -lt 1) {
        throw "Stale threshold must be at least 1 day."
    }

    $cutoff = (Get-Date).AddDays(-$Days)
    return @(Get-AllNotes |
        Where-Object { $_.LastWrite -lt $cutoff } |
        Sort-Object LastWrite, Title)
}

function Get-AllowedSavedQueryCommands {
    return @(
        "list", "search", "find", "tags", "recent", "dashboard", "agenda", "report", "review",
        "tasks", "related", "graph", "unresolved", "orphans", "preview", "path", "stale", "dedupe"
    )
}

function Get-SavedQueries {
    $path = Get-SavedQueriesPath
    if (-not (Test-Path -LiteralPath $path)) {
        return @{}
    }

    $raw = Get-Content -LiteralPath $path -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return @{}
    }

    $data = $raw | ConvertFrom-Json -AsHashtable
    if ($data) {
        return $data
    }

    return @{}
}

function Set-SavedQueries {
    param([Parameter(Mandatory)][hashtable]$Queries)

    $path = Get-SavedQueriesPath
    $json = $Queries | ConvertTo-Json -Depth 5
    Set-Content -LiteralPath $path -Value $json -Encoding utf8
}

function Save-Query {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string[]]$CommandParts
    )

    $queryName = $Name.Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($queryName)) {
        throw "Query name is required."
    }

    if ($CommandParts.Count -eq 0) {
        throw "Saved query command is required."
    }

    $command = $CommandParts[0].Trim().ToLowerInvariant()
    if ($command -notin (Get-AllowedSavedQueryCommands)) {
        throw ("Saved queries only support read-only commands. Allowed: {0}" -f ((Get-AllowedSavedQueryCommands) -join ", "))
    }

    $savedArgs = if ($CommandParts.Count -gt 1) { @($CommandParts[1..($CommandParts.Count - 1)]) } else { @() }
    $queries = Get-SavedQueries
    $queries[$queryName] = @{
        command = $command
        args    = $savedArgs
    }
    Set-SavedQueries -Queries $queries
    Write-Output (Get-SavedQueriesPath)
}

function Remove-SavedQuery {
    param([Parameter(Mandatory)][string]$Name)

    $queryName = $Name.Trim().ToLowerInvariant()
    $queries = Get-SavedQueries
    if ($queries.ContainsKey($queryName)) {
        $queries.Remove($queryName)
        Set-SavedQueries -Queries $queries
    }
    Write-Output (Get-SavedQueriesPath)
}

function Show-SavedQueries {
    foreach ($entry in ((Get-SavedQueries).GetEnumerator() | Sort-Object Key)) {
        $argsText = @($entry.Value["args"]) -join " "
        "{0}: {1} {2}" -f $entry.Key, $entry.Value["command"], $argsText.Trim()
    }
}

function Show-SavedQuery {
    param([Parameter(Mandatory)][string]$Name)

    $queryName = $Name.Trim().ToLowerInvariant()
    $queries = Get-SavedQueries
    if (-not $queries.ContainsKey($queryName)) {
        throw "Saved query not found: $Name"
    }

    $entry = $queries[$queryName]
    $argsText = @($entry["args"]) -join " "
    "{0}: {1} {2}" -f $queryName, $entry["command"], $argsText.Trim()
}

function Invoke-SavedQuery {
    param([Parameter(Mandatory)][string]$Name)

    $queryName = $Name.Trim().ToLowerInvariant()
    $queries = Get-SavedQueries
    if (-not $queries.ContainsKey($queryName)) {
        throw "Saved query not found: $Name"
    }

    $entry = $queries[$queryName]
    Invoke-MinimalNotesCli -Command ([string]$entry["command"]) -Arguments @($entry["args"])
}

function Get-NormalizedNoteTitle {
    param([Parameter(Mandatory)][string]$Title)

    return (($Title.ToLowerInvariant() -replace '[^a-z0-9]+', ' ').Trim())
}

function Get-DedupeCandidates {
    param([int]$Limit = 10)

    if ($Limit -lt 1) {
        throw "Dedupe limit must be at least 1."
    }

    $notes = @(Get-AllNotes)
    $results = New-Object System.Collections.Generic.List[object]

    for ($i = 0; $i -lt $notes.Count; $i++) {
        for ($j = $i + 1; $j -lt $notes.Count; $j++) {
            $left = $notes[$i]
            $right = $notes[$j]

            $score = 0
            $reasons = @()
            $leftTitle = Get-NormalizedNoteTitle -Title $left.Title
            $rightTitle = Get-NormalizedNoteTitle -Title $right.Title

            if ($leftTitle -eq $rightTitle) {
                $score += 6
                $reasons += "same normalized title"
            } elseif ((Get-FuzzyScore -Query $leftTitle -Candidate $rightTitle) -ge 0 -or (Get-FuzzyScore -Query $rightTitle -Candidate $leftTitle) -ge 0) {
                $score += 3
                $reasons += "similar title"
            }

            $leftTags = @(Get-NoteTags -Path $left.Path | Sort-Object -Unique)
            $rightTags = @(Get-NoteTags -Path $right.Path | Sort-Object -Unique)
            $sharedTags = @($leftTags | Where-Object { $_ -in $rightTags })
            if ($sharedTags.Count -gt 0) {
                $score += $sharedTags.Count
                $reasons += ("shared tags {0}" -f ($sharedTags -join ", "))
            }

            $leftLinks = @(Get-ResolvedLinkPathsForNote -Path $left.Path)
            $rightLinks = @(Get-ResolvedLinkPathsForNote -Path $right.Path)
            $sharedLinks = @($leftLinks | Where-Object { $_ -in $rightLinks })
            if ($sharedLinks.Count -gt 0) {
                $score += $sharedLinks.Count
                $reasons += ("shared links {0}" -f $sharedLinks.Count)
            }

            if ($score -ge 4) {
                $results.Add([pscustomobject]@{
                    Score   = $score
                    Left    = $left
                    Right   = $right
                    Reasons = $reasons
                })
            }
        }
    }

    return @($results |
        Sort-Object @{ Expression = "Score"; Descending = $true }, @{ Expression = { $_.Left.Title } ; Descending = $false } |
        Select-Object -First $Limit)
}

function Get-ResolvedLinkPathsForNote {
    param([Parameter(Mandatory)][string]$Path)

    $resolved = foreach ($target in (Get-LinkTargets -Path $Path)) {
        $resolvedPath = Resolve-LinkTarget -Target $target
        if ($resolvedPath) {
            $resolvedPath
        }
    }

    return @($resolved | Sort-Object -Unique)
}

function Show-Dashboard {
    param([string]$LimitText)

    $limit = $Script:DefaultDashboardLimit
    if ($LimitText) {
        if (-not [int]::TryParse($LimitText.Trim(), [ref]$limit)) {
            throw "Dashboard limit must be a whole number."
        }
        if ($limit -lt 1) {
            throw "Dashboard limit must be at least 1."
        }
    }

    Write-Output "Minimal Notes Dashboard"
    Write-Output ("Generated: {0}" -f (Get-Date -Format "yyyy-MM-dd HH:mm"))
    Write-Output ""

    $overdueAgenda = @(Get-AgendaItems -Mode overdue | Sort-Object AnchorDate, Title | Select-Object -First $limit | ForEach-Object { Format-AgendaItemLine -Item $_ })
    $todayAgenda = @(Get-AgendaItems -Mode today | Sort-Object AnchorDate, Title | Select-Object -First $limit | ForEach-Object { Format-AgendaItemLine -Item $_ })
    $overdueTasks = @(Get-Tasks -State overdue | Select-Object -First $limit | ForEach-Object { Format-TaskLine -Task $_ })
    $todayTasks = @(Get-Tasks -State today | Select-Object -First $limit | ForEach-Object { Format-TaskLine -Task $_ })
    $recentNotes = @(Get-RecentNotes -Limit $limit | ForEach-Object { "{0}  {1}  {2}" -f $_.LastWrite.ToString("yyyy-MM-dd HH:mm"), $_.Title, $_.RelativePath })
    $unresolved = @(Get-UnresolvedLinks | Select-Object -First $limit | ForEach-Object { "{0} -> [[{1}]]  suggested {2}" -f $_.Source, $_.Target, $_.SuggestedPath })

    Format-Section -Title "Agenda Overdue" -Lines $overdueAgenda
    Format-Section -Title "Agenda Today" -Lines $todayAgenda
    Format-Section -Title "Tasks Overdue" -Lines $overdueTasks
    Format-Section -Title "Tasks Today" -Lines $todayTasks
    Format-Section -Title "Recent Notes" -Lines $recentNotes
    Format-Section -Title "Unresolved Links" -Lines $unresolved
}

function Get-ReportWindow {
    param([ValidateSet("daily", "weekly", "monthly")][string]$Period = "weekly")

    $today = (Get-Date).Date
    switch ($Period) {
        "daily" {
            $start = $today
            $end = $start.AddDays(1)
        }
        "weekly" {
            $offset = ([int]$today.DayOfWeek + 6) % 7
            $start = $today.AddDays(-$offset)
            $end = $start.AddDays(7)
        }
        "monthly" {
            $start = Get-Date -Year $today.Year -Month $today.Month -Day 1 -Hour 0 -Minute 0 -Second 0
            $end = $start.AddMonths(1)
        }
    }

    [pscustomobject]@{
        Start  = $start
        End    = $end
        Period = $Period
    }
}

function Show-Report {
    param([string]$PeriodText)

    $period = if ($PeriodText) { $PeriodText.Trim().ToLowerInvariant() } else { "weekly" }
    if ($period -notin @("daily", "weekly", "monthly")) {
        throw "Report period must be one of: daily, weekly, monthly."
    }

    $window = Get-ReportWindow -Period $period
    $changedNotes = @(Get-AllNotes | Where-Object { $_.LastWrite -ge $window.Start -and $_.LastWrite -lt $window.End })
    $openTasks = @(Get-Tasks -State open)
    $todayTasks = @(Get-Tasks -State today)
    $overdueTasks = @(Get-Tasks -State overdue)
    $todayAgenda = @(Get-AgendaItems -Mode today)
    $overdueAgenda = @(Get-AgendaItems -Mode overdue)
    $unresolvedLinks = @(Get-UnresolvedLinks)

    Write-Output ("{0} Report" -f ([cultureinfo]::InvariantCulture.TextInfo.ToTitleCase($period)))
    Write-Output ("Window: {0} to {1}" -f $window.Start.ToString("yyyy-MM-dd"), $window.End.AddDays(-1).ToString("yyyy-MM-dd"))
    Write-Output ("Notes changed: {0}" -f $changedNotes.Count)
    Write-Output ("Open tasks: {0}" -f $openTasks.Count)
    Write-Output ("Tasks due today: {0}" -f $todayTasks.Count)
    Write-Output ("Overdue tasks: {0}" -f $overdueTasks.Count)
    Write-Output ("Agenda today: {0}" -f $todayAgenda.Count)
    Write-Output ("Agenda overdue: {0}" -f $overdueAgenda.Count)
    Write-Output ("Unresolved links: {0}" -f $unresolvedLinks.Count)
    Write-Output ""

    $recentChanged = @($changedNotes |
        Sort-Object LastWrite -Descending |
        Select-Object -First 5 |
        ForEach-Object { "{0}  {1}" -f $_.LastWrite.ToString("yyyy-MM-dd HH:mm"), $_.Title })
    Format-Section -Title "Changed Notes" -Lines $recentChanged
}

function Show-Review {
    param([string]$PeriodText)

    $period = if ($PeriodText) { $PeriodText.Trim().ToLowerInvariant() } else { "daily" }
    if ($period -notin @("daily", "weekly")) {
        throw "Review period must be one of: daily, weekly."
    }

    $window = Get-ReportWindow -Period $period
    $changedNotes = @(Get-AllNotes | Where-Object { $_.LastWrite -ge $window.Start -and $_.LastWrite -lt $window.End })

    Write-Output ("{0} Review" -f ([cultureinfo]::InvariantCulture.TextInfo.ToTitleCase($period)))
    Write-Output ("Window: {0} to {1}" -f $window.Start.ToString("yyyy-MM-dd"), $window.End.AddDays(-1).ToString("yyyy-MM-dd"))
    Write-Output ""

    Format-Section -Title "Checklist" -Lines @(
        "[ ] Process inbox captures"
        "[ ] Review overdue commitments"
        "[ ] Clear unresolved links"
        "[ ] Scan recent note activity"
    )

    Format-Section -Title "Overdue Tasks" -Lines @(
        @(Get-Tasks -State overdue | Select-Object -First 5 | ForEach-Object { Format-TaskLine -Task $_ })
    )
    Format-Section -Title "Agenda Today" -Lines @(
        @(Get-AgendaItems -Mode today | Sort-Object AnchorDate, Title | Select-Object -First 5 | ForEach-Object { Format-AgendaItemLine -Item $_ })
    )
    Format-Section -Title "Changed Notes" -Lines @(
        @($changedNotes | Sort-Object LastWrite -Descending | Select-Object -First 5 | ForEach-Object { "{0}  {1}" -f $_.LastWrite.ToString("yyyy-MM-dd HH:mm"), $_.Title })
    )
    Format-Section -Title "Unresolved Links" -Lines @(
        @(Get-UnresolvedLinks | Select-Object -First 5 | ForEach-Object { "{0} -> [[{1}]]" -f $_.Source, $_.Target })
    )
}

function Rename-Note {
    param(
        [Parameter(Mandatory)][string]$OldName,
        [Parameter(Mandatory)][string]$NewName
    )

    $oldPath = Resolve-Note -Name $OldName
    if (-not $oldPath) {
        throw "Note not found: $OldName"
    }

    $newPath = Get-PlannedNotePath -Name $NewName
    if ($oldPath -ne $newPath -and (Test-Path -LiteralPath $newPath)) {
        throw "Target note already exists: $newPath"
    }

    $oldTitle = Get-NoteTitle -Path $oldPath
    $newLeafName = Split-Path -Leaf ($NewName.Trim() -replace '/', '\')
    $newLinkTarget = Normalize-NoteReference -Reference $newLeafName
    if (-not [string]::IsNullOrWhiteSpace((Split-Path -Parent ($NewName.Trim() -replace '/', '\')))) {
        $newLinkTarget = Normalize-NoteReference -Reference (Get-LinkReferenceForPath -Path $newPath)
    }

    $oldKeys = @(Get-LinkMatcherKeys -Path $oldPath)
    $newDirectory = Split-Path -Parent $newPath
    if (-not (Test-Path -LiteralPath $newDirectory)) {
        New-Item -ItemType Directory -Path $newDirectory -Force | Out-Null
    }

    if ($oldPath -ne $newPath) {
        Move-Item -LiteralPath $oldPath -Destination $newPath
    }

    $renamedContent = Get-Content -LiteralPath $newPath -Raw
    $updatedRenamedContent = $renamedContent
    $renamedLines = @($renamedContent -split "\r?\n")
    $headingUpdated = $false
    for ($i = 0; $i -lt $renamedLines.Count; $i++) {
        if ($renamedLines[$i] -match '^#\s+' -and (($renamedLines[$i] -replace '^#\s+', '').Trim() -eq $oldTitle)) {
            $renamedLines[$i] = "# $newLeafName"
            $headingUpdated = $true
            break
        }
    }
    if ($headingUpdated) {
        $updatedRenamedContent = ($renamedLines -join [Environment]::NewLine)
    }
    $updatedRenamedContent = Update-LinksInContent -Content $updatedRenamedContent -OldKeys $oldKeys -NewTarget $newLinkTarget
    if ($updatedRenamedContent -cne $renamedContent) {
        Set-Content -LiteralPath $newPath -Value $updatedRenamedContent -Encoding utf8
    }

    Get-ChildItem -LiteralPath $Script:VaultRoot -Recurse -File -Filter "*.md" |
        Where-Object { $_.FullName -ne $newPath } |
        ForEach-Object {
            $content = Get-Content -LiteralPath $_.FullName -Raw
            $updated = Update-LinksInContent -Content $content -OldKeys $oldKeys -NewTarget $newLinkTarget
            if ($updated -cne $content) {
                Set-Content -LiteralPath $_.FullName -Value $updated -Encoding utf8
            }
        }

    Write-Output $newPath
}

function New-UnresolvedLinks {
    param([string]$Target)

    $items = @(Get-UnresolvedLinks)
    if ($items.Count -eq 0) {
        return
    }

    $created = @()

    if ($Target) {
        $normalized = $Target.Trim().ToLowerInvariant()
        $items = @($items | Where-Object { $_.Target.ToLowerInvariant() -eq $normalized })
        if ($items.Count -eq 0) {
            throw "No unresolved link found for target: $Target"
        }
    } else {
        $items = @($items | Group-Object Target | ForEach-Object { $_.Group[0] })
    }

    foreach ($item in $items) {
        $path = New-NoteFile -Name $item.Target
        $created += $path
    }

    $created | Sort-Object -Unique
}

function Open-Note {
    param([Parameter(Mandatory)][string]$Name)

    $path = Resolve-Note -Name $Name
    if (-not $path) {
        $path = New-NoteFile -Name $Name
    }

    Open-InEditor -Path $path
}

function Open-DailyNote {
    param([string]$DateText)

    $date = if ($DateText) {
        [datetime]::Parse($DateText)
    } else {
        Get-Date
    }

    $path = Ensure-DailyNoteExists -Date $date

    Open-InEditor -Path $path
}

function Get-WeeklyNotePath {
    param([datetime]$Date = (Get-Date))

    $weeklyDir = Join-Path $Script:VaultRoot "weekly"
    $weekYear = [System.Globalization.ISOWeek]::GetYear($Date)
    $weekNumber = [System.Globalization.ISOWeek]::GetWeekOfYear($Date)
    return Join-Path $weeklyDir ("{0}-W{1}.md" -f $weekYear, $weekNumber.ToString("00"))
}

function Ensure-WeeklyNoteExists {
    param([datetime]$Date = (Get-Date))

    $weeklyDir = Join-Path $Script:VaultRoot "weekly"
    if (-not (Test-Path -LiteralPath $weeklyDir)) {
        New-Item -ItemType Directory -Path $weeklyDir -Force | Out-Null
    }

    $path = Get-WeeklyNotePath -Date $Date
    if (-not (Test-Path -LiteralPath $path)) {
        $weekYear = [System.Globalization.ISOWeek]::GetYear($Date)
        $weekNumber = [System.Globalization.ISOWeek]::GetWeekOfYear($Date)
        $content = @(
            "# {0}-W{1}" -f $weekYear, $weekNumber.ToString("00")
            ""
            "## Priorities"
            ""
            "## Notes"
            ""
            "## Review"
            ""
        )
        Set-Content -LiteralPath $path -Value $content -Encoding utf8
    }

    return $path
}

function Open-WeeklyNote {
    param([string]$DateText)

    $date = if ($DateText) {
        [datetime]::Parse($DateText)
    } else {
        Get-Date
    }

    $path = Ensure-WeeklyNoteExists -Date $date
    Open-InEditor -Path $path
}

function Get-MonthlyNotePath {
    param([datetime]$Date = (Get-Date))

    $monthlyDir = Join-Path $Script:VaultRoot "monthly"
    return Join-Path $monthlyDir ("{0}.md" -f $Date.ToString("yyyy-MM"))
}

function Ensure-MonthlyNoteExists {
    param([datetime]$Date = (Get-Date))

    $monthlyDir = Join-Path $Script:VaultRoot "monthly"
    if (-not (Test-Path -LiteralPath $monthlyDir)) {
        New-Item -ItemType Directory -Path $monthlyDir -Force | Out-Null
    }

    $path = Get-MonthlyNotePath -Date $Date
    if (-not (Test-Path -LiteralPath $path)) {
        $content = @(
            "# {0}" -f $Date.ToString("yyyy-MM")
            ""
            "## Goals"
            ""
            "## Notes"
            ""
            "## Review"
            ""
        )
        Set-Content -LiteralPath $path -Value $content -Encoding utf8
    }

    return $path
}

function Open-MonthlyNote {
    param([string]$DateText)

    $date = if ($DateText) {
        [datetime]::Parse($DateText)
    } else {
        Get-Date
    }

    $path = Ensure-MonthlyNoteExists -Date $date
    Open-InEditor -Path $path
}

function Get-DailyNotePath {
    param([datetime]$Date = (Get-Date))

    $dailyDir = Join-Path $Script:VaultRoot "daily"
    return Join-Path $dailyDir ("{0}.md" -f $Date.ToString("yyyy-MM-dd"))
}

function Ensure-DailyNoteExists {
    param([datetime]$Date = (Get-Date))

    $dailyDir = Join-Path $Script:VaultRoot "daily"
    if (-not (Test-Path -LiteralPath $dailyDir)) {
        New-Item -ItemType Directory -Path $dailyDir -Force | Out-Null
    }

    $path = Get-DailyNotePath -Date $Date
    if (-not (Test-Path -LiteralPath $path)) {
        $name = $Date.ToString("yyyy-MM-dd")
        $content = @(
            "# $name"
            ""
            "## Notes"
            ""
            "## Links"
            ""
        )
        Set-Content -LiteralPath $path -Value $content -Encoding utf8
    }

    return $path
}

function Get-InboxPath {
    return Join-Path $Script:VaultRoot "inbox.md"
}

function Ensure-InboxExists {
    $path = Get-InboxPath
    if (-not (Test-Path -LiteralPath $path)) {
        $content = @(
            "# Inbox"
            ""
            "Quick capture lives here."
            ""
        )
        Set-Content -LiteralPath $path -Value $content -Encoding utf8
    }

    return $path
}

function Get-RelatedNotes {
    param(
        [Parameter(Mandatory)][string]$Name,
        [int]$Limit = 10
    )

    $path = Resolve-Note -Name $Name
    if (-not $path) {
        throw "Note not found: $Name"
    }

    $notes = @(Get-AllNotes)
    $targetNote = $notes | Where-Object { $_.Path -eq $path } | Select-Object -First 1
    $backlinkMap = Get-BacklinkMap
    $targetOutgoing = @(Get-ResolvedLinkPathsForNote -Path $path)
    $targetOutgoingSet = @{}
    foreach ($item in $targetOutgoing) { $targetOutgoingSet[$item] = $true }
    $targetIncoming = if ($backlinkMap.ContainsKey($path)) { @($backlinkMap[$path]) } else { @() }
    $targetIncomingSet = @{}
    foreach ($item in $targetIncoming) { $targetIncomingSet[$item] = $true }
    $targetTags = @(Get-NoteTags -Path $path | Sort-Object -Unique)

    $results = foreach ($note in $notes) {
        if ($note.Path -eq $path) {
            continue
        }

        $score = 0
        $reasons = @()
        $candidateOutgoing = @(Get-ResolvedLinkPathsForNote -Path $note.Path)
        $candidateTags = @(Get-NoteTags -Path $note.Path | Sort-Object -Unique)

        if ($candidateOutgoing -contains $path) {
            $score += 5
            $reasons += "links here"
        }
        if ($targetOutgoing -contains $note.Path) {
            $score += 4
            $reasons += "linked from target"
        }

        $sharedOutgoing = @($candidateOutgoing | Where-Object { $targetOutgoingSet.ContainsKey($_) })
        if ($sharedOutgoing.Count -gt 0) {
            $score += $sharedOutgoing.Count
            $reasons += ("shared links {0}" -f $sharedOutgoing.Count)
        }

        if ($targetIncomingSet.ContainsKey($note.Path)) {
            $score += 2
            $reasons += "shared backlink neighborhood"
        }

        $sharedTags = @($candidateTags | Where-Object { $_ -in $targetTags })
        if ($sharedTags.Count -gt 0) {
            $score += ($sharedTags.Count * 2)
            $reasons += ("shared tags {0}" -f ($sharedTags -join ", "))
        }

        if ($score -gt 0) {
            [pscustomobject]@{
                Score  = $score
                Title  = $note.Title
                Path   = $note.RelativePath
                Reasons = $reasons
            }
        }
    }

    return @($results |
        Sort-Object @{ Expression = "Score"; Descending = $true }, @{ Expression = "Title"; Descending = $false } |
        Select-Object -First $Limit)
}

function Show-RelatedNotes {
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$LimitText
    )

    $limit = 10
    if ($LimitText) {
        if (-not [int]::TryParse($LimitText.Trim(), [ref]$limit)) {
            throw "Related limit must be a whole number."
        }
        if ($limit -lt 1) {
            throw "Related limit must be at least 1."
        }
    }

    foreach ($item in (Get-RelatedNotes -Name $Name -Limit $limit)) {
        "{0}  {1}  [score {2}]  {3}" -f $item.Title, $item.Path, $item.Score, ($item.Reasons -join ", ")
    }
}

function Show-StaleNotes {
    param([string]$DaysText)

    $days = $Script:DefaultStaleDays
    if ($DaysText) {
        if (-not [int]::TryParse($DaysText.Trim(), [ref]$days)) {
            throw "Stale threshold must be a whole number of days."
        }
    }

    foreach ($note in (Get-StaleNotes -Days $days)) {
        "{0}d  {1}  {2}" -f [int](((Get-Date) - $note.LastWrite).TotalDays), $note.Title, $note.RelativePath
    }
}

function Show-Config {
    Write-Output ("configPath: {0}" -f $Script:ConfigPath)
    Write-Output ("vault: {0}" -f $Script:VaultRoot)
    Write-Output ("templates: {0}" -f $Script:TemplateRoot)
    Write-Output ("queries: {0}" -f $Script:QueriesPath)
    Write-Output ("editor: {0}" -f $Script:DefaultEditor)
    Write-Output ("noOpen: {0}" -f $Script:NoOpen.ToString().ToLowerInvariant())
    Write-Output ("defaultStaleDays: {0}" -f $Script:DefaultStaleDays)
    Write-Output ("defaultDashboardLimit: {0}" -f $Script:DefaultDashboardLimit)
}

function Initialize-ConfigFile {
    $path = Get-MinimalNotesConfigPath
    if (-not (Test-Path -LiteralPath $path)) {
        $config = [ordered]@{
            vault     = Join-Path $Script:ProjectRoot "vault"
            templates = Join-Path $Script:ProjectRoot "templates"
            queries   = Join-Path $Script:ProjectRoot "saved-queries.json"
            editor    = "notepad.exe"
            noOpen    = $false
            defaults  = [ordered]@{
                staleDays      = 30
                dashboardLimit = 5
            }
        }
        $json = $config | ConvertTo-Json -Depth 5
        Set-Content -LiteralPath $path -Value $json -Encoding utf8
    }

    Write-Output $path
}

function Show-DedupeCandidates {
    param([string]$LimitText)

    $limit = 10
    if ($LimitText) {
        if (-not [int]::TryParse($LimitText.Trim(), [ref]$limit)) {
            throw "Dedupe limit must be a whole number."
        }
    }

    foreach ($item in (Get-DedupeCandidates -Limit $limit)) {
        $paths = @($item.Left.RelativePath, $item.Right.RelativePath) | Sort-Object
        "{0} <-> {1}  [score {2}]  {3}" -f $paths[0], $paths[1], $item.Score, ($item.Reasons -join ", ")
    }
}

function ConvertTo-MermaidNodeId {
    param([Parameter(Mandatory)][string]$Path)

    return "n_" + ([regex]::Replace((Normalize-NoteReference -Reference $Path), '[^a-zA-Z0-9_]', '_'))
}

function ConvertTo-MermaidLabel {
    param([Parameter(Mandatory)][string]$Text)

    return $Text.Replace('"', "'")
}

function Show-Graph {
    param([string]$NameText)

    $notes = @(Get-AllNotes)
    $backlinkMap = Get-BacklinkMap
    $edges = New-Object System.Collections.Generic.List[string]
    $includedPaths = New-Object System.Collections.Generic.HashSet[string]

    if (-not $NameText -or $NameText.Trim().ToLowerInvariant() -eq "--all") {
        foreach ($note in $notes) {
            [void]$includedPaths.Add($note.Path)
            foreach ($targetPath in (Get-ResolvedLinkPathsForNote -Path $note.Path)) {
                [void]$includedPaths.Add($targetPath)
                $edges.Add(("{0}[`"{1}`"] --> {2}[`"{3}`"]" -f
                    (ConvertTo-MermaidNodeId -Path $note.Path),
                    (ConvertTo-MermaidLabel -Text $note.Title),
                    (ConvertTo-MermaidNodeId -Path $targetPath),
                    (ConvertTo-MermaidLabel -Text (Get-NoteTitle -Path $targetPath))))
            }
        }
    } else {
        $targetPath = Resolve-Note -Name $NameText
        if (-not $targetPath) {
            throw "Note not found: $NameText"
        }

        [void]$includedPaths.Add($targetPath)
        $targetTitle = Get-NoteTitle -Path $targetPath
        foreach ($target in (Get-ResolvedLinkPathsForNote -Path $targetPath)) {
            [void]$includedPaths.Add($target)
            $edges.Add(("{0}[`"{1}`"] --> {2}[`"{3}`"]" -f
                (ConvertTo-MermaidNodeId -Path $targetPath),
                (ConvertTo-MermaidLabel -Text $targetTitle),
                (ConvertTo-MermaidNodeId -Path $target),
                (ConvertTo-MermaidLabel -Text (Get-NoteTitle -Path $target))))
        }

        if ($backlinkMap.ContainsKey($targetPath)) {
            foreach ($source in @($backlinkMap[$targetPath])) {
                [void]$includedPaths.Add($source)
                $edges.Add(("{0}[`"{1}`"] --> {2}[`"{3}`"]" -f
                    (ConvertTo-MermaidNodeId -Path $source),
                    (ConvertTo-MermaidLabel -Text (Get-NoteTitle -Path $source)),
                    (ConvertTo-MermaidNodeId -Path $targetPath),
                    (ConvertTo-MermaidLabel -Text $targetTitle)))
            }
        }
    }

    Write-Output "graph TD"
    foreach ($path in @($includedPaths)) {
        $note = $notes | Where-Object { $_.Path -eq $path } | Select-Object -First 1
        if ($note) {
            Write-Output ("{0}[`"{1}`"]" -f (ConvertTo-MermaidNodeId -Path $path), (ConvertTo-MermaidLabel -Text $note.Title))
        }
    }
    foreach ($edge in @($edges | Sort-Object -Unique)) {
        Write-Output $edge
    }
}

function Add-CaptureEntry {
    param(
        [Parameter(Mandatory)][string[]]$CaptureArgs
    )

    if ($CaptureArgs.Count -eq 0) {
        throw "Usage: ./note.ps1 capture `"remember this`" or ./note.ps1 capture daily `"ship the prototype`""
    }

    $target = "inbox"
    $messageArgs = $CaptureArgs

    if ($CaptureArgs.Count -gt 1) {
        $first = $CaptureArgs[0].Trim().ToLowerInvariant()
        if ($first -in @("inbox", "daily")) {
            $target = $first
            $messageArgs = @($CaptureArgs[1..($CaptureArgs.Count - 1)])
        }
    }

    $message = Require-Argument -Values $messageArgs -Message "Capture text is required."
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm"

    if ($target -eq "daily") {
        $path = Ensure-DailyNoteExists
    } else {
        $path = Ensure-InboxExists
    }

    Add-Content -LiteralPath $path -Value ("- [{0}] {1}" -f $timestamp, $message) -Encoding utf8
    Write-Output $path
}

function Invoke-MinimalNotesCli {
    param(
        [string]$Command = "help",
        [string[]]$Arguments
    )

    $Arguments = @($Arguments)
    Initialize-MinimalNotesContext
    Ensure-Vault

    switch ($Command.ToLowerInvariant()) {
        "new" {
            $newArguments = Parse-NewCommandArguments -Values $Arguments
            $path = New-NoteFile -Name $newArguments.Name -TemplateName $newArguments.TemplateName
            Write-Output $path
        }
        "open" {
            $name = Require-Argument -Values $Arguments -Message "Usage: ./note.ps1 open `"My Note`""
            Open-Note -Name $name
        }
        "list" {
            $filter = if ($Arguments.Count -gt 0) { $Arguments -join " " } else { $null }
            List-Notes -Filter $filter
        }
        "search" {
            $pattern = Require-Argument -Values $Arguments -Message "Usage: ./note.ps1 search powershell"
            Search-Notes -Pattern $pattern
        }
        "find" {
            $query = Require-Argument -Values $Arguments -Message "Usage: ./note.ps1 find pwsh"
            Show-FindResults -Query $query
        }
        "pick" {
            $query = if ($Arguments.Count -gt 0) { $Arguments -join " " } else { $null }
            Invoke-NotePicker -InitialQuery $query
        }
        "switch" {
            $query = if ($Arguments.Count -gt 0) { $Arguments -join " " } else { $null }
            Invoke-NotePicker -InitialQuery $query
        }
        "capture" {
            Add-CaptureEntry -CaptureArgs $Arguments
        }
        "orphans" {
            Show-Orphans
        }
        "recent" {
            $limit = if ($Arguments.Count -gt 0) { $Arguments -join " " } else { $null }
            Show-RecentNotes -LimitText $limit
        }
        "stale" {
            $days = if ($Arguments.Count -gt 0) { $Arguments -join " " } else { $null }
            Show-StaleNotes -DaysText $days
        }
        "config" {
            $configArgs = @($Arguments | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
            if ($configArgs.Count -eq 0) {
                Show-Config
                break
            }

            $action = $configArgs[0].Trim().ToLowerInvariant()
            switch ($action) {
                "show" { Show-Config }
                "init" { Initialize-ConfigFile }
                "path" { Write-Output (Get-MinimalNotesConfigPath) }
                default { throw "Unknown config action: $action" }
            }
        }
        "dashboard" {
            $limit = if ($Arguments.Count -gt 0) { $Arguments -join " " } else { $null }
            Show-Dashboard -LimitText $limit
        }
        "agenda" {
            $mode = if ($Arguments.Count -gt 0) { $Arguments -join " " } else { $null }
            Show-Agenda -ModeText $mode
        }
        "report" {
            $period = if ($Arguments.Count -gt 0) { $Arguments -join " " } else { $null }
            Show-Report -PeriodText $period
        }
        "review" {
            $period = if ($Arguments.Count -gt 0) { $Arguments -join " " } else { $null }
            Show-Review -PeriodText $period
        }
        "tasks" {
            $state = if ($Arguments.Count -gt 0) { $Arguments -join " " } else { $null }
            Show-Tasks -StateText $state
        }
        "related" {
            if ($Arguments.Count -eq 0) {
                throw "Usage: ./note.ps1 related `"My Note`" [limit]"
            }

            $name = $Arguments[0]
            $limit = if ($Arguments.Count -gt 1) { $Arguments[1] } else { $null }
            Show-RelatedNotes -Name $name -LimitText $limit
        }
        "graph" {
            $name = if ($Arguments.Count -gt 0) { $Arguments -join " " } else { $null }
            Show-Graph -NameText $name
        }
        "merge" {
            if ($Arguments.Count -lt 2) {
                throw "Usage: ./note.ps1 merge `"Source Note`" `"Target Note`""
            }

            $sourceName = $Arguments[0]
            $targetName = ($Arguments[1..($Arguments.Count - 1)] -join " ").Trim()
            Merge-Notes -SourceName $sourceName -TargetName $targetName
        }
        "split" {
            if ($Arguments.Count -lt 2) {
                throw "Usage: ./note.ps1 split `"Source Note`" `"Section Heading`" [`"New Note`"]"
            }

            $sourceName = $Arguments[0]
            $heading = $Arguments[1]
            $newName = if ($Arguments.Count -gt 2) { ($Arguments[2..($Arguments.Count - 1)] -join " ").Trim() } else { $null }
            Split-NoteSection -SourceName $sourceName -Heading $heading -NewName $newName
        }
        "repair-links" {
            $target = if ($Arguments.Count -gt 0) { $Arguments -join " " } else { $null }
            Repair-Links -Target $target
        }
        "query" {
            $queryArgs = @($Arguments | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
            if ($queryArgs.Count -eq 0) {
                Show-SavedQueries
                break
            }

            $action = $queryArgs[0].Trim().ToLowerInvariant()
            switch ($action) {
                "list" {
                    Show-SavedQueries
                }
                "show" {
                    if ($queryArgs.Count -lt 2) {
                        throw "Usage: ./note.ps1 query show work-today"
                    }
                    Show-SavedQuery -Name $queryArgs[1]
                }
                "save" {
                    if ($queryArgs.Count -lt 3) {
                        throw "Usage: ./note.ps1 query save work-today tasks today"
                    }
                    Save-Query -Name $queryArgs[1] -CommandParts @($queryArgs[2..($queryArgs.Count - 1)])
                }
                "run" {
                    if ($queryArgs.Count -lt 2) {
                        throw "Usage: ./note.ps1 query run work-today"
                    }
                    Invoke-SavedQuery -Name $queryArgs[1]
                }
                "delete" {
                    if ($queryArgs.Count -lt 2) {
                        throw "Usage: ./note.ps1 query delete work-today"
                    }
                    Remove-SavedQuery -Name $queryArgs[1]
                }
                default {
                    throw "Unknown query action: $action"
                }
            }
        }
        "dedupe" {
            $limit = if ($Arguments.Count -gt 0) { $Arguments -join " " } else { $null }
            Show-DedupeCandidates -LimitText $limit
        }
        "template" {
            $templateArgs = @($Arguments | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
            if ($templateArgs.Count -eq 0) {
                Show-Templates
                break
            }

            $action = $templateArgs[0].Trim().ToLowerInvariant()
            switch ($action) {
                "list" {
                    Show-Templates
                }
                "show" {
                    if ($templateArgs.Count -lt 2) {
                        throw "Usage: ./note.ps1 template show meeting"
                    }
                    $name = Require-Argument -Values @($templateArgs[1..($templateArgs.Count - 1)]) -Message "Usage: ./note.ps1 template show meeting"
                    Show-TemplatePreview -Name $name
                }
                "new" {
                    if ($templateArgs.Count -lt 2) {
                        throw "Usage: ./note.ps1 template new meeting"
                    }
                    $name = Require-Argument -Values @($templateArgs[1..($templateArgs.Count - 1)]) -Message "Usage: ./note.ps1 template new meeting"
                    New-TemplateFile -Name $name
                }
                default {
                    throw "Unknown template action: $action"
                }
            }
        }
        "props" {
            if ($Arguments.Count -eq 0) {
                throw "Usage: ./note.ps1 props `"My Note`" [set|add|remove|unset] [key] [value]"
            }

            $name = $Arguments[0]
            if ($Arguments.Count -eq 1) {
                Show-Properties -Name $name
                break
            }

            $action = $Arguments[1].Trim().ToLowerInvariant()
            $key = $Arguments[2].Trim()

            switch ($action) {
                "unset" {
                    if ($Arguments.Count -ne 3) {
                        throw "Usage: ./note.ps1 props `"My Note`" unset [key]"
                    }
                    Unset-PropertyValue -Name $name -Key $key
                }
                "set" {
                    if ($Arguments.Count -lt 4) {
                        throw "Usage: ./note.ps1 props `"My Note`" set [key] [value]"
                    }
                    $values = @($Arguments[3..($Arguments.Count - 1)])
                    Set-PropertyValue -Name $name -Key $key -Values $values
                }
                "add" {
                    if ($Arguments.Count -lt 4) {
                        throw "Usage: ./note.ps1 props `"My Note`" add [key] [value]"
                    }
                    $values = @($Arguments[3..($Arguments.Count - 1)])
                    Add-PropertyValue -Name $name -Key $key -Values $values
                }
                "remove" {
                    if ($Arguments.Count -lt 4) {
                        throw "Usage: ./note.ps1 props `"My Note`" remove [key] [value]"
                    }
                    $values = @($Arguments[3..($Arguments.Count - 1)])
                    Remove-PropertyValue -Name $name -Key $key -Values $values
                }
                default { throw "Unknown props action: $action" }
            }
        }
        "rename" {
            if ($Arguments.Count -lt 2) {
                throw "Usage: ./note.ps1 rename `"Old Note`" `"New Note`""
            }

            $oldName = $Arguments[0]
            $newName = ($Arguments[1..($Arguments.Count - 1)] -join " ").Trim()
            Rename-Note -OldName $oldName -NewName $newName
        }
        "unresolved" {
            $name = if ($Arguments.Count -gt 0) { $Arguments -join " " } else { $null }
            Show-UnresolvedLinks -Name $name
        }
        "create-unresolved" {
            $target = if ($Arguments.Count -gt 0) { $Arguments -join " " } else { $null }
            if ($target -and $target.Trim().ToLowerInvariant() -eq "all") {
                $target = $null
            }
            New-UnresolvedLinks -Target $target
        }
        "links" {
            $name = Require-Argument -Values $Arguments -Message "Usage: ./note.ps1 links `"My Note`""
            Show-Links -Name $name
        }
        "backlinks" {
            $name = Require-Argument -Values $Arguments -Message "Usage: ./note.ps1 backlinks `"My Note`""
            Show-Backlinks -Name $name
        }
        "tags" {
            $tag = if ($Arguments.Count -gt 0) { $Arguments -join " " } else { $null }
            Show-Tags -Tag $tag
        }
        "preview" {
            $name = Require-Argument -Values $Arguments -Message "Usage: ./note.ps1 preview `"My Note`""
            Show-Preview -Name $name
        }
        "daily" {
            $dateText = if ($Arguments.Count -gt 0) { $Arguments -join " " } else { $null }
            Open-DailyNote -DateText $dateText
        }
        "weekly" {
            $dateText = if ($Arguments.Count -gt 0) { $Arguments -join " " } else { $null }
            Open-WeeklyNote -DateText $dateText
        }
        "monthly" {
            $dateText = if ($Arguments.Count -gt 0) { $Arguments -join " " } else { $null }
            Open-MonthlyNote -DateText $dateText
        }
        "path" {
            Write-Output (Get-MinimalNotesVaultPath)
        }
        "help" {
            Show-Help
        }
        default {
            throw "Unknown command: $Command`n`n$(Show-Help)"
        }
    }
}

Export-ModuleMember -Function Invoke-MinimalNotesCli, Get-MinimalNotesVaultPath
