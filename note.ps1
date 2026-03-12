param(
    [Parameter(Position = 0)]
    [string]$Command = "help",

    [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
    [string[]]$Args
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$Args = @($Args)

$Script:ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$Script:VaultRoot = if ($env:MINIMAL_NOTES_VAULT) { $env:MINIMAL_NOTES_VAULT } else { Join-Path $Script:ProjectRoot "vault" }
$Script:NoOpen = $env:MINIMAL_NOTES_NO_OPEN -in @("1", "true", "yes")
$Script:DefaultEditor = if ($env:MINIMAL_NOTES_EDITOR) {
    $env:MINIMAL_NOTES_EDITOR
} elseif ($env:EDITOR) {
    $env:EDITOR
} elseif (Get-Command code -ErrorAction SilentlyContinue) {
    "code"
} else {
    "notepad.exe"
}

function Ensure-Vault {
    if (-not (Test-Path -LiteralPath $Script:VaultRoot)) {
        New-Item -ItemType Directory -Path $Script:VaultRoot | Out-Null
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

    if ($lines.Count -eq 0 -or $lines[0].Trim() -ne "---") {
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
    $matches = foreach ($note in $notes) {
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

    $matches |
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
        [switch]$Open
    )

    Ensure-Vault

    $relativeName = $Name.Trim() -replace '/', '\'
    $leafName = Split-Path -Path $relativeName -Leaf
    $targetDir = Split-Path -Parent (Get-PlannedNotePath -Name $Name)
    $path = Get-PlannedNotePath -Name $Name

    if (-not (Test-Path -LiteralPath $targetDir)) {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    }

    if (-not (Test-Path -LiteralPath $path)) {
        $content = @(
            "# $leafName"
            ""
            "Created: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
            ""
        )
        Set-Content -LiteralPath $path -Value $content -Encoding utf8
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
    $matches = [regex]::Matches($content, '\[\[([^\]]+)\]\]')

    foreach ($match in $matches) {
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
    $matches = [regex]::Matches($content, '(?<!\w)#([a-zA-Z][\w\-/]*)')

    foreach ($match in $matches) {
        $tag = $match.Groups[1].Value.Trim().ToLowerInvariant()
        if ($tag) {
            $tag
        }
    }
}

function Get-Tasks {
    param([ValidateSet("open", "done", "all")][string]$State = "open")

    $notes = @(Get-AllNotes)
    foreach ($note in $notes) {
        $lineNumber = 0
        foreach ($line in (Get-Content -LiteralPath $note.Path)) {
            $lineNumber++
            if ($line -notmatch '^\s*[-*]\s+\[( |x|X)\]\s+(.+)$') {
                continue
            }

            $isDone = $matches[1].ToLowerInvariant() -eq "x"
            if ($State -eq "open" -and $isDone) {
                continue
            }
            if ($State -eq "done" -and -not $isDone) {
                continue
            }

            [pscustomobject]@{
                State = if ($isDone) { "done" } else { "open" }
                Path  = $note.RelativePath
                Line  = $lineNumber
                Text  = $matches[2].Trim()
            }
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

    $valueText = Require-Argument -Values $Values -Message "Property value is required."
    if ($Key -in @("tags", "aliases")) {
        $properties[$Key] = @($valueText -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    } else {
        $properties[$Key] = $valueText
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

    $items = @((Require-Argument -Values $Values -Message "Property value is required.") -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $existing = @($properties[$Key])
    $properties[$Key] = @($existing + $items | Sort-Object -Unique)
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

    $itemsToRemove = @((Require-Argument -Values $Values -Message "Property value is required.") -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $remaining = @($properties[$Key] | Where-Object { $_ -notin $itemsToRemove })
    if ($remaining.Count -eq 0) {
        if ($properties.Contains($Key)) {
            $properties.Remove($Key)
        }
    } else {
        $properties[$Key] = $remaining
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

function Show-Help {
    @"
Minimal Notes CLI

Usage:
  ./note.ps1 new "My Note"
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
  ./note.ps1 tasks
  ./note.ps1 tasks all
  ./note.ps1 tasks done
  ./note.ps1 props "My Note"
  ./note.ps1 props "My Note" set status active
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
  new        Create a note from a title or path-like name.
  open       Open an existing note in your editor.
  list       List notes in the vault, optionally filtered.
  search     Full-text search across all markdown notes.
  find       Fuzzy-find notes by title, slug, or path.
  pick       Interactively choose a note to open.
  capture    Append a quick note to inbox.md or today's daily note.
  orphans    List notes with no inbound wiki links.
  recent     List recently modified notes, newest first.
  tasks      Collect markdown checkbox tasks across the vault.
  props      Read or update frontmatter properties for a note.
  rename     Rename a note file and update wiki links that point to it.
  unresolved List unresolved wiki links across the vault or in one note.
  create-unresolved  Create notes for one unresolved link target or all missing targets.
  links      Show outgoing wiki links from a note.
  backlinks  Show notes that link to a note.
  tags       List all tags, or notes containing a tag.
  preview    Print a note to the terminal.
  daily      Open or create a daily note at daily/YYYY-MM-DD.md.
  path       Print the vault path.
  help       Show this help.

Environment:
  MINIMAL_NOTES_VAULT   Override the vault location.
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

    $matches = @(Find-Notes -Query $query)

    if ($matches.Count -eq 0) {
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
    for ($i = 0; $i -lt $matches.Count; $i++) {
        $match = $matches[$i]
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

    if ($index -lt 1 -or $index -gt $matches.Count) {
        throw "Selection out of range."
    }

    Open-InEditor -Path $matches[$index - 1].Note.Path
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

function Show-Tasks {
    param([string]$StateText)

    $state = if ($StateText) { $StateText.Trim().ToLowerInvariant() } else { "open" }
    if ($state -notin @("open", "done", "all")) {
        throw "Task filter must be one of: open, done, all."
    }

    foreach ($task in (Get-Tasks -State $state)) {
        "{0}:{1}  [{2}] {3}" -f $task.Path, $task.Line, $task.State, $task.Text
    }
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
    $renamedLines = @($renamedContent -split "\r?\n")
    for ($i = 0; $i -lt $renamedLines.Count; $i++) {
        if ($renamedLines[$i] -eq "# $oldTitle") {
            $renamedLines[$i] = "# $newLeafName"
            break
        }
    }
    $renamedContent = ($renamedLines -join [Environment]::NewLine)
    $renamedContent = Update-LinksInContent -Content $renamedContent -OldKeys $oldKeys -NewTarget $newLinkTarget
    Set-Content -LiteralPath $newPath -Value $renamedContent -Encoding utf8

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

function Get-DailyNotePath {
    param([datetime]$Date = (Get-Date))

    $dailyDir = Join-Path $Script:VaultRoot "daily"
    if (-not (Test-Path -LiteralPath $dailyDir)) {
        New-Item -ItemType Directory -Path $dailyDir -Force | Out-Null
    }

    return Join-Path $dailyDir ("{0}.md" -f $Date.ToString("yyyy-MM-dd"))
}

function Ensure-DailyNoteExists {
    param([datetime]$Date = (Get-Date))

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

Ensure-Vault

try {
    switch ($Command.ToLowerInvariant()) {
        "new" {
            $name = Require-Argument -Values $Args -Message "Usage: ./note.ps1 new `"My Note`""
            $path = New-NoteFile -Name $name
            Write-Output $path
        }
        "open" {
            $name = Require-Argument -Values $Args -Message "Usage: ./note.ps1 open `"My Note`""
            Open-Note -Name $name
        }
        "list" {
            $filter = if ($Args.Count -gt 0) { $Args -join " " } else { $null }
            List-Notes -Filter $filter
        }
        "search" {
            $pattern = Require-Argument -Values $Args -Message "Usage: ./note.ps1 search powershell"
            Search-Notes -Pattern $pattern
        }
        "find" {
            $query = Require-Argument -Values $Args -Message "Usage: ./note.ps1 find pwsh"
            Show-FindResults -Query $query
        }
        "pick" {
            $query = if ($Args.Count -gt 0) { $Args -join " " } else { $null }
            Invoke-NotePicker -InitialQuery $query
        }
        "switch" {
            $query = if ($Args.Count -gt 0) { $Args -join " " } else { $null }
            Invoke-NotePicker -InitialQuery $query
        }
        "capture" {
            Add-CaptureEntry -CaptureArgs $Args
        }
        "orphans" {
            Show-Orphans
        }
        "recent" {
            $limit = if ($Args.Count -gt 0) { $Args -join " " } else { $null }
            Show-RecentNotes -LimitText $limit
        }
        "tasks" {
            $state = if ($Args.Count -gt 0) { $Args -join " " } else { $null }
            Show-Tasks -StateText $state
        }
        "props" {
            if ($Args.Count -eq 0) {
                throw "Usage: ./note.ps1 props `"My Note`" [set|add|remove] [key] [value]"
            }

            $name = $Args[0]
            if ($Args.Count -eq 1) {
                Show-Properties -Name $name
                break
            }

            if ($Args.Count -lt 4) {
                throw "Usage: ./note.ps1 props `"My Note`" [set|add|remove] [key] [value]"
            }

            $action = $Args[1].Trim().ToLowerInvariant()
            $key = $Args[2].Trim()
            $values = @($Args[3..($Args.Count - 1)])

            switch ($action) {
                "set" { Set-PropertyValue -Name $name -Key $key -Values $values }
                "add" { Add-PropertyValue -Name $name -Key $key -Values $values }
                "remove" { Remove-PropertyValue -Name $name -Key $key -Values $values }
                default { throw "Unknown props action: $action" }
            }
        }
        "rename" {
            if ($Args.Count -lt 2) {
                throw "Usage: ./note.ps1 rename `"Old Note`" `"New Note`""
            }

            $oldName = $Args[0]
            $newName = ($Args[1..($Args.Count - 1)] -join " ").Trim()
            Rename-Note -OldName $oldName -NewName $newName
        }
        "unresolved" {
            $name = if ($Args.Count -gt 0) { $Args -join " " } else { $null }
            Show-UnresolvedLinks -Name $name
        }
        "create-unresolved" {
            $target = if ($Args.Count -gt 0) { $Args -join " " } else { $null }
            if ($target -and $target.Trim().ToLowerInvariant() -eq "all") {
                $target = $null
            }
            New-UnresolvedLinks -Target $target
        }
        "links" {
            $name = Require-Argument -Values $Args -Message "Usage: ./note.ps1 links `"My Note`""
            Show-Links -Name $name
        }
        "backlinks" {
            $name = Require-Argument -Values $Args -Message "Usage: ./note.ps1 backlinks `"My Note`""
            Show-Backlinks -Name $name
        }
        "tags" {
            $tag = if ($Args.Count -gt 0) { $Args -join " " } else { $null }
            Show-Tags -Tag $tag
        }
        "preview" {
            $name = Require-Argument -Values $Args -Message "Usage: ./note.ps1 preview `"My Note`""
            Show-Preview -Name $name
        }
        "daily" {
            $dateText = if ($Args.Count -gt 0) { $Args -join " " } else { $null }
            Open-DailyNote -DateText $dateText
        }
        "path" {
            Write-Output $Script:VaultRoot
        }
        "help" {
            Show-Help
        }
        default {
            throw "Unknown command: $Command`n`n$(Show-Help)"
        }
    }
} catch {
    Write-Error $_
    exit 1
}
