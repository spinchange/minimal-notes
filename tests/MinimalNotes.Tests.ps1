$global:MinimalNotes_TestHere = Split-Path -Parent $MyInvocation.MyCommand.Path
$global:MinimalNotes_ProjectRoot = Split-Path -Parent $global:MinimalNotes_TestHere
$global:MinimalNotes_ScriptPath = Join-Path $global:MinimalNotes_ProjectRoot "note.ps1"
$global:MinimalNotes_ModuleManifestPath = Join-Path $global:MinimalNotes_ProjectRoot "MinimalNotes.psd1"

function script:New-TestVault {
    $path = Join-Path ([System.IO.Path]::GetTempPath()) ("minimal-notes-tests-" + [guid]::NewGuid().ToString("n"))
    New-Item -ItemType Directory -Path $path | Out-Null
    return $path
}

function script:Remove-TestVault {
    param([string]$Path)

    if ($Path -and (Test-Path -LiteralPath $Path)) {
        Remove-Item -LiteralPath $Path -Recurse -Force
    }
}

function script:Invoke-NoteCliSubprocess {
    param(
        [string]$VaultPath,
        [string]$TemplatesPath,
        [string]$ConfigPath,
        [string[]]$Arguments
    )

    $env:MINIMAL_NOTES_VAULT = $VaultPath
    $env:MINIMAL_NOTES_NO_OPEN = "1"
    if ($TemplatesPath) {
        $env:MINIMAL_NOTES_TEMPLATES = $TemplatesPath
    } else {
        Remove-Item Env:MINIMAL_NOTES_TEMPLATES -ErrorAction SilentlyContinue
    }
    if ($ConfigPath) {
        $env:MINIMAL_NOTES_CONFIG = $ConfigPath
    } else {
        Remove-Item Env:MINIMAL_NOTES_CONFIG -ErrorAction SilentlyContinue
    }

    $output = & pwsh -NoProfile -File $global:MinimalNotes_ScriptPath @Arguments 2>&1
    $exitCode = $LASTEXITCODE

    return [pscustomobject]@{
        ExitCode = $exitCode
        Output   = @($output)
        Text     = (@($output) -join [Environment]::NewLine).Trim()
    }
}

function script:Invoke-NoteCli {
    param(
        [string]$VaultPath,
        [string]$TemplatesPath,
        [string]$ConfigPath,
        [string[]]$Arguments
    )

    $originalVault = $env:MINIMAL_NOTES_VAULT
    $originalTemplates = $env:MINIMAL_NOTES_TEMPLATES
    $originalConfig = $env:MINIMAL_NOTES_CONFIG
    $originalNoOpen = $env:MINIMAL_NOTES_NO_OPEN

    $env:MINIMAL_NOTES_VAULT = $VaultPath
    $env:MINIMAL_NOTES_NO_OPEN = "1"
    if ($TemplatesPath) {
        $env:MINIMAL_NOTES_TEMPLATES = $TemplatesPath
    } else {
        Remove-Item Env:MINIMAL_NOTES_TEMPLATES -ErrorAction SilentlyContinue
    }
    if ($ConfigPath) {
        $env:MINIMAL_NOTES_CONFIG = $ConfigPath
    } else {
        Remove-Item Env:MINIMAL_NOTES_CONFIG -ErrorAction SilentlyContinue
    }

    try {
        $command = if ($Arguments.Count -gt 0) { $Arguments[0] } else { "help" }
        $commandArgs = if ($Arguments.Count -gt 1) { @($Arguments[1..($Arguments.Count - 1)]) } else { @() }
        $output = @(Invoke-MinimalNotesCli -Command $command -Arguments $commandArgs 2>&1)
        $exitCode = 0
    } catch {
        $output = @($_.Exception.Message)
        $exitCode = 1
    } finally {
        if ($null -ne $originalVault) { $env:MINIMAL_NOTES_VAULT = $originalVault } else { Remove-Item Env:MINIMAL_NOTES_VAULT -ErrorAction SilentlyContinue }
        if ($null -ne $originalTemplates) { $env:MINIMAL_NOTES_TEMPLATES = $originalTemplates } else { Remove-Item Env:MINIMAL_NOTES_TEMPLATES -ErrorAction SilentlyContinue }
        if ($null -ne $originalConfig) { $env:MINIMAL_NOTES_CONFIG = $originalConfig } else { Remove-Item Env:MINIMAL_NOTES_CONFIG -ErrorAction SilentlyContinue }
        if ($null -ne $originalNoOpen) { $env:MINIMAL_NOTES_NO_OPEN = $originalNoOpen } else { Remove-Item Env:MINIMAL_NOTES_NO_OPEN -ErrorAction SilentlyContinue }
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Output   = @($output)
        Text     = (@($output) -join [Environment]::NewLine).Trim()
    }
}

function script:Invoke-InteractivePick {
    param(
        [string]$VaultPath,
        [string]$InputText,
        [string]$Query
    )

    $escapedScriptPath = $global:MinimalNotes_ScriptPath.Replace('"', '""')
    $escapedVaultPath = $VaultPath.Replace('"', '""')
    $escapedInput = $InputText.Replace('"', '""')
    $escapedQuery = $Query.Replace('"', '""')
    $command = 'set "MINIMAL_NOTES_VAULT={0}" && set "MINIMAL_NOTES_NO_OPEN=1" && (echo {1}) | pwsh -NoProfile -File "{2}" pick "{3}"' -f $escapedVaultPath, $escapedInput, $escapedScriptPath, $escapedQuery

    $output = & cmd /c $command 2>&1
    $exitCode = $LASTEXITCODE

    return [pscustomobject]@{
        ExitCode = $exitCode
        Output   = @($output)
        Text     = (@($output) -join [Environment]::NewLine).Trim()
    }
}

Describe "Minimal Notes CLI" {
    BeforeAll {
        Import-Module $global:MinimalNotes_ModuleManifestPath -Force -ErrorAction Stop
    }

    BeforeEach {
        $script:VaultPath = New-TestVault
    }

    AfterEach {
        Remove-TestVault -Path $script:VaultPath
        Remove-Item Env:MINIMAL_NOTES_VAULT -ErrorAction SilentlyContinue
        Remove-Item Env:MINIMAL_NOTES_TEMPLATES -ErrorAction SilentlyContinue
        Remove-Item Env:MINIMAL_NOTES_CONFIG -ErrorAction SilentlyContinue
        Remove-Item Env:MINIMAL_NOTES_NO_OPEN -ErrorAction SilentlyContinue
    }

    It "creates a note with new" {
        $result = Invoke-NoteCliSubprocess -VaultPath $script:VaultPath -Arguments @("new", "Project Ideas")

        $result.ExitCode | Should -Be 0
        (Test-Path -LiteralPath (Join-Path $script:VaultPath "project-ideas.md")) | Should -Be $true
        (Get-Content -LiteralPath (Join-Path $script:VaultPath "project-ideas.md") -Raw) | Should -Match "# Project Ideas"
    }

    It "wraps the module through the note.ps1 CLI script" {
        $result = Invoke-NoteCliSubprocess -VaultPath $script:VaultPath -Arguments @("path")

        $result.ExitCode | Should -Be 0
        $result.Text | Should -Be $script:VaultPath
    }

    It "imports the module manifest and exposes the CLI entry point" {
        Import-Module $global:MinimalNotes_ModuleManifestPath -Force -ErrorAction Stop

        $commands = Get-Command -Module MinimalNotes

        ($commands.Name -contains "Invoke-MinimalNotesCli") | Should -Be $true
        ($commands.Name -contains "Get-MinimalNotesVaultPath") | Should -Be $true
    }

    It "creates a note from a template with placeholders" {
        $templatesPath = Join-Path $script:VaultPath "templates"
        New-Item -ItemType Directory -Path $templatesPath | Out-Null
        Set-Content -LiteralPath (Join-Path $templatesPath "meeting.md") -Value @(
            "---",
            "status: active",
            "---",
            "",
            "# {{title}}",
            "",
            "Slug: {{slug}}",
            "Created: {{date}}"
        )

        $result = Invoke-NoteCli -VaultPath $script:VaultPath -TemplatesPath $templatesPath -Arguments @("new", "Sprint Review", "--template", "meeting")
        $notePath = Join-Path $script:VaultPath "sprint-review.md"

        $result.ExitCode | Should -Be 0
        $result.Text | Should -Be $notePath
        (Get-Content -LiteralPath $notePath -Raw) | Should -Match "# Sprint Review"
        (Get-Content -LiteralPath $notePath -Raw) | Should -Match "Slug: sprint-review"
        (Get-Content -LiteralPath $notePath -Raw) | Should -Match "status: active"
    }

    It "lists and previews templates" {
        $templatesPath = Join-Path $script:VaultPath "templates"
        New-Item -ItemType Directory -Path $templatesPath | Out-Null
        Set-Content -LiteralPath (Join-Path $templatesPath "meeting.md") -Value @(
            "# {{title}}",
            "",
            "Agenda item"
        )

        $listResult = Invoke-NoteCli -VaultPath $script:VaultPath -TemplatesPath $templatesPath -Arguments @("template")
        $showResult = Invoke-NoteCli -VaultPath $script:VaultPath -TemplatesPath $templatesPath -Arguments @("template", "show", "meeting")

        $listResult.ExitCode | Should -Be 0
        $listResult.Text | Should -Match "meeting.md"
        $showResult.ExitCode | Should -Be 0
        $showResult.Text | Should -Match "{{title}}"
        $showResult.Text | Should -Match "Agenda item"
    }

    It "creates a template scaffold" {
        $templatesPath = Join-Path $script:VaultPath "templates"

        $result = Invoke-NoteCli -VaultPath $script:VaultPath -TemplatesPath $templatesPath -Arguments @("template", "new", "Meeting Notes")
        $templatePath = Join-Path $templatesPath "meeting-notes.md"

        $result.ExitCode | Should -Be 0
        $result.Text | Should -Be $templatePath
        (Test-Path -LiteralPath $templatePath) | Should -Be $true
        (Get-Content -LiteralPath $templatePath -Raw) | Should -Match "# {{title}}"
    }

    It "lists notes with a filter" {
        Set-Content -LiteralPath (Join-Path $script:VaultPath "alpha.md") -Value @(
            "# Alpha Note",
            "",
            "Tags: #alpha"
        )
        Set-Content -LiteralPath (Join-Path $script:VaultPath "beta.md") -Value @(
            "# Beta Note"
        )

        $result = Invoke-NoteCli -VaultPath $script:VaultPath -Arguments @("list", "alpha")

        $result.ExitCode | Should -Be 0
        $result.Text | Should -Match "Alpha Note"
        $result.Text | Should -Not -Match "Beta Note"
    }

    It "searches note content" {
        Set-Content -LiteralPath (Join-Path $script:VaultPath "search-target.md") -Value @(
            "# Search Target",
            "",
            "PowerShell is great for automation."
        )

        $result = Invoke-NoteCli -VaultPath $script:VaultPath -Arguments @("search", "automation")

        $result.ExitCode | Should -Be 0
        $result.Text | Should -Match "search-target.md:3: PowerShell is great for automation."
    }

    It "shows links from a note" {
        Set-Content -LiteralPath (Join-Path $script:VaultPath "source.md") -Value @(
            "# Source",
            "",
            "See [[Target Note]] and [[another-note|Alias]]."
        )

        $result = Invoke-NoteCli -VaultPath $script:VaultPath -Arguments @("links", "source")

        $result.ExitCode | Should -Be 0
        $result.Text | Should -Match "Target Note"
        $result.Text | Should -Match "another-note"
    }

    It "finds backlinks including aliased wiki links" {
        Set-Content -LiteralPath (Join-Path $script:VaultPath "target-note.md") -Value @(
            "# Target Note"
        )
        Set-Content -LiteralPath (Join-Path $script:VaultPath "source.md") -Value @(
            "# Source",
            "",
            "Points to [[Target Note|the target]]."
        )

        $result = Invoke-NoteCli -VaultPath $script:VaultPath -Arguments @("backlinks", "Target Note")

        $result.ExitCode | Should -Be 0
        $result.Text | Should -Match "source.md"
    }

    It "fuzzy finds a note by partial query" {
        Set-Content -LiteralPath (Join-Path $script:VaultPath "terminal-ui.md") -Value @(
            "# Terminal UI"
        )

        $result = Invoke-NoteCli -VaultPath $script:VaultPath -Arguments @("find", "termui")

        $result.ExitCode | Should -Be 0
        $result.Text | Should -Match "Terminal UI"
    }

    It "lists tags and filters by tag" {
        Set-Content -LiteralPath (Join-Path $script:VaultPath "inbox.md") -Value @(
            "# Inbox",
            "",
            "Tags: #inbox #capture"
        )
        Set-Content -LiteralPath (Join-Path $script:VaultPath "ideas.md") -Value @(
            "# Ideas",
            "",
            "Tags: #ideas"
        )

        $allTags = Invoke-NoteCli -VaultPath $script:VaultPath -Arguments @("tags")
        $filtered = Invoke-NoteCli -VaultPath $script:VaultPath -Arguments @("tags", "inbox")

        $allTags.ExitCode | Should -Be 0
        $allTags.Text | Should -Match "#inbox"
        $allTags.Text | Should -Match "#capture"
        $filtered.ExitCode | Should -Be 0
        $filtered.Text | Should -Match "Inbox  inbox.md"
    }

    It "prints a preview of a note" {
        Set-Content -LiteralPath (Join-Path $script:VaultPath "welcome.md") -Value @(
            "# Welcome",
            "",
            "Hello from preview."
        )

        $result = Invoke-NoteCli -VaultPath $script:VaultPath -Arguments @("preview", "welcome")

        $result.ExitCode | Should -Be 0
        $result.Text | Should -Match "Hello from preview."
    }

    It "creates a daily note without opening an editor" {
        $result = Invoke-NoteCli -VaultPath $script:VaultPath -Arguments @("daily", "2026-03-12")
        $dailyPath = Join-Path (Join-Path $script:VaultPath "daily") "2026-03-12.md"

        $result.ExitCode | Should -Be 0
        $result.Text | Should -Be $dailyPath
        (Test-Path -LiteralPath $dailyPath) | Should -Be $true
        (Get-Content -LiteralPath $dailyPath -Raw) | Should -Match "## Notes"
    }

    It "captures a quick note to inbox" {
        $result = Invoke-NoteCli -VaultPath $script:VaultPath -Arguments @("capture", "remember the milk")
        $inboxPath = Join-Path $script:VaultPath "inbox.md"

        $result.ExitCode | Should -Be 0
        $result.Text | Should -Be $inboxPath
        (Test-Path -LiteralPath $inboxPath) | Should -Be $true
        (Get-Content -LiteralPath $inboxPath -Raw) | Should -Match "remember the milk"
    }

    It "captures a quick note to today's daily note" {
        $todayPath = Join-Path (Join-Path $script:VaultPath "daily") ("{0}.md" -f (Get-Date).ToString("yyyy-MM-dd"))
        $result = Invoke-NoteCli -VaultPath $script:VaultPath -Arguments @("capture", "daily", "ship the prototype")

        $result.ExitCode | Should -Be 0
        $result.Text | Should -Be $todayPath
        (Test-Path -LiteralPath $todayPath) | Should -Be $true
        (Get-Content -LiteralPath $todayPath -Raw) | Should -Match "ship the prototype"
    }

    It "lists orphan notes with no inbound links" {
        Set-Content -LiteralPath (Join-Path $script:VaultPath "hub.md") -Value @(
            "# Hub",
            "",
            "Links to [[Child Note]]."
        )
        Set-Content -LiteralPath (Join-Path $script:VaultPath "child-note.md") -Value @(
            "# Child Note"
        )
        Set-Content -LiteralPath (Join-Path $script:VaultPath "lonely.md") -Value @(
            "# Lonely"
        )

        $result = Invoke-NoteCli -VaultPath $script:VaultPath -Arguments @("orphans")

        $result.ExitCode | Should -Be 0
        $result.Text | Should -Match "Hub  hub.md"
        $result.Text | Should -Match "Lonely  lonely.md"
        $result.Text | Should -Not -Match "Child Note"
    }

    It "lists recent notes in newest-first order with a limit" {
        $firstPath = Join-Path $script:VaultPath "first.md"
        $secondPath = Join-Path $script:VaultPath "second.md"
        $thirdPath = Join-Path $script:VaultPath "third.md"

        Set-Content -LiteralPath $firstPath -Value "# First"
        Set-Content -LiteralPath $secondPath -Value "# Second"
        Set-Content -LiteralPath $thirdPath -Value "# Third"

        (Get-Item -LiteralPath $firstPath).LastWriteTime = [datetime]"2026-03-09T10:00:00"
        (Get-Item -LiteralPath $secondPath).LastWriteTime = [datetime]"2026-03-10T10:00:00"
        (Get-Item -LiteralPath $thirdPath).LastWriteTime = [datetime]"2026-03-11T10:00:00"

        $result = Invoke-NoteCli -VaultPath $script:VaultPath -Arguments @("recent", "2")

        $result.ExitCode | Should -Be 0
        $lines = @($result.Output | Where-Object { $_ -and $_.ToString().Trim() })
        $lines.Count | Should -Be 2
        $lines[0].ToString() | Should -Match "Third  third.md"
        $lines[1].ToString() | Should -Match "Second  second.md"
    }

    It "lists stale notes older than a threshold" {
        $stalePath = Join-Path $script:VaultPath "stale.md"
        $freshPath = Join-Path $script:VaultPath "fresh.md"

        Set-Content -LiteralPath $stalePath -Value "# Stale"
        Set-Content -LiteralPath $freshPath -Value "# Fresh"

        (Get-Item -LiteralPath $stalePath).LastWriteTime = (Get-Date).AddDays(-45)
        (Get-Item -LiteralPath $freshPath).LastWriteTime = (Get-Date).AddDays(-5)

        $result = Invoke-NoteCli -VaultPath $script:VaultPath -Arguments @("stale", "30")

        $result.ExitCode | Should -Be 0
        $result.Text | Should -Match "Stale  stale.md"
        $result.Text | Should -Not -Match "Fresh"
    }

    It "initializes and shows the config file" {
        $configPath = Join-Path $script:VaultPath "minimal-notes.config.json"

        $initResult = Invoke-NoteCli -VaultPath $script:VaultPath -ConfigPath $configPath -Arguments @("config", "init")
        $showResult = Invoke-NoteCli -VaultPath $script:VaultPath -ConfigPath $configPath -Arguments @("config")

        $initResult.ExitCode | Should -Be 0
        $initResult.Text | Should -Be $configPath
        (Test-Path -LiteralPath $configPath) | Should -Be $true
        $showResult.Text | Should -Match "configPath: $([regex]::Escape($configPath))"
        $showResult.Text | Should -Match "defaultStaleDays: 30"
    }

    It "uses config defaults when no explicit stale argument is provided" {
        $configPath = Join-Path $script:VaultPath "minimal-notes.config.json"
        Set-Content -LiteralPath $configPath -Value @'
{
  "defaults": {
    "staleDays": 10
  }
}
'@

        $stalePath = Join-Path $script:VaultPath "stale.md"
        $freshPath = Join-Path $script:VaultPath "fresh.md"
        Set-Content -LiteralPath $stalePath -Value "# Stale"
        Set-Content -LiteralPath $freshPath -Value "# Fresh"
        (Get-Item -LiteralPath $stalePath).LastWriteTime = (Get-Date).AddDays(-15)
        (Get-Item -LiteralPath $freshPath).LastWriteTime = (Get-Date).AddDays(-5)

        $result = Invoke-NoteCli -VaultPath $script:VaultPath -ConfigPath $configPath -Arguments @("stale")

        $result.ExitCode | Should -Be 0
        $result.Text | Should -Match "Stale  stale.md"
        $result.Text | Should -Not -Match "Fresh"
    }

    It "saves, shows, runs, and deletes a saved query" {
        $queryPath = Join-Path $global:MinimalNotes_ProjectRoot "saved-queries.json"
        if (Test-Path -LiteralPath $queryPath) {
            Remove-Item -LiteralPath $queryPath -Force
        }

        Set-Content -LiteralPath (Join-Path $script:VaultPath "today-task.md") -Value @(
            "---",
            ("scheduled: {0}" -f (Get-Date).ToString("yyyy-MM-dd")),
            "---",
            "",
            "# Today Task",
            "",
            "- [ ] Follow up today"
        )

        $saveResult = Invoke-NoteCli -VaultPath $script:VaultPath -Arguments @("query", "save", "work-today", "tasks", "today")
        $listResult = Invoke-NoteCli -VaultPath $script:VaultPath -Arguments @("query")
        $showResult = Invoke-NoteCli -VaultPath $script:VaultPath -Arguments @("query", "show", "work-today")
        $runResult = Invoke-NoteCli -VaultPath $script:VaultPath -Arguments @("query", "run", "work-today")
        $deleteResult = Invoke-NoteCli -VaultPath $script:VaultPath -Arguments @("query", "delete", "work-today")

        $saveResult.ExitCode | Should -Be 0
        (Test-Path -LiteralPath $queryPath) | Should -Be $true
        $listResult.Text | Should -Match "work-today: tasks today"
        $showResult.Text | Should -Match "work-today: tasks today"
        $runResult.Text | Should -Match "Follow up today"
        $deleteResult.ExitCode | Should -Be 0

        if (Test-Path -LiteralPath $queryPath) {
            Remove-Item -LiteralPath $queryPath -Force
        }
    }

    It "only previews dedupe candidates without changing files" {
        $firstPath = Join-Path $script:VaultPath "project-plan.md"
        $secondPath = Join-Path $script:VaultPath "project-plan-copy.md"

        Set-Content -LiteralPath $firstPath -Value @(
            "# Project Plan",
            "",
            "Tags: #work #plan",
            "",
            "See [[Shared Note]]."
        )
        Set-Content -LiteralPath $secondPath -Value @(
            "# Project Plan Copy",
            "",
            "Tags: #work #plan",
            "",
            "See [[Shared Note]]."
        )
        Set-Content -LiteralPath (Join-Path $script:VaultPath "shared-note.md") -Value "# Shared Note"

        $beforeFirst = Get-Content -LiteralPath $firstPath -Raw
        $beforeSecond = Get-Content -LiteralPath $secondPath -Raw
        $result = Invoke-NoteCli -VaultPath $script:VaultPath -Arguments @("dedupe")

        $result.ExitCode | Should -Be 0
        $result.Text | Should -Match "project-plan(-copy)?\.md <-> project-plan(-copy)?\.md"
        $result.Text | Should -Match "score"
        (Get-Content -LiteralPath $firstPath -Raw) | Should -Be $beforeFirst
        (Get-Content -LiteralPath $secondPath -Raw) | Should -Be $beforeSecond
    }

    It "shows a dashboard with multiple vault sections" {
        Set-Content -LiteralPath (Join-Path $script:VaultPath "project.md") -Value @(
            "---",
            ("due: {0}" -f (Get-Date).AddDays(-1).ToString("yyyy-MM-dd")),
            ("scheduled: {0}" -f (Get-Date).ToString("yyyy-MM-dd")),
            "priority: high",
            "---",
            "",
            "# Project",
            "",
            "- [ ] Fix the urgent thing",
            "",
            "Related to [[Missing Note]]."
        )

        $result = Invoke-NoteCli -VaultPath $script:VaultPath -Arguments @("dashboard", "3")

        $result.ExitCode | Should -Be 0
        $result.Text | Should -Match "Minimal Notes Dashboard"
        $result.Text | Should -Match "== Agenda Overdue =="
        $result.Text | Should -Match "== Tasks Overdue =="
        $result.Text | Should -Match "== Unresolved Links =="
        $result.Text | Should -Match "Missing Note"
        $result.Text | Should -Match "Fix the urgent thing"
    }

    It "shows a weekly report summary" {
        $changedPath = Join-Path $script:VaultPath "weekly-report.md"
        Set-Content -LiteralPath $changedPath -Value @(
            "---",
            ("due: {0}" -f (Get-Date).ToString("yyyy-MM-dd")),
            "---",
            "",
            "# Weekly Report",
            "",
            "- [ ] Follow up"
        )
        (Get-Item -LiteralPath $changedPath).LastWriteTime = (Get-Date).AddDays(-1)

        $result = Invoke-NoteCli -VaultPath $script:VaultPath -Arguments @("report", "weekly")

        $result.ExitCode | Should -Be 0
        $result.Text | Should -Match "Weekly Report"
        $result.Text | Should -Match "Notes changed: 1"
        $result.Text | Should -Match "Open tasks: 1"
        $result.Text | Should -Match "Changed Notes"
    }

    It "shows a daily review with checklist and focus sections" {
        Set-Content -LiteralPath (Join-Path $script:VaultPath "review-note.md") -Value @(
            "---",
            ("due: {0}" -f (Get-Date).AddDays(-1).ToString("yyyy-MM-dd")),
            "---",
            "",
            "# Review Note",
            "",
            "- [ ] Clear the blocker",
            "",
            "Reference [[Missing Review Link]]."
        )

        $result = Invoke-NoteCli -VaultPath $script:VaultPath -Arguments @("review")

        $result.ExitCode | Should -Be 0
        $result.Text | Should -Match "Daily Review"
        $result.Text | Should -Match "\[ \] Process inbox captures"
        $result.Text | Should -Match "== Overdue Tasks =="
        $result.Text | Should -Match "Missing Review Link"
    }

    It "shows active agenda items from scheduled and due frontmatter" {
        Set-Content -LiteralPath (Join-Path $script:VaultPath "project-a.md") -Value @(
            "---",
            "status: active",
            "priority: high",
            ("scheduled: {0}" -f (Get-Date).AddDays(1).ToString("yyyy-MM-dd")),
            "---",
            "",
            "# Project A"
        )
        Set-Content -LiteralPath (Join-Path $script:VaultPath "project-b.md") -Value @(
            "---",
            "status: completed",
            ("due: {0}" -f (Get-Date).AddDays(2).ToString("yyyy-MM-dd")),
            "---",
            "",
            "# Project B"
        )

        $result = Invoke-NoteCli -VaultPath $script:VaultPath -Arguments @("agenda")

        $result.ExitCode | Should -Be 0
        $result.Text | Should -Match "Project A  project-a.md"
        $result.Text | Should -Match "priority high"
        $result.Text | Should -Not -Match "Project B"
    }

    It "filters agenda items for today and overdue views" {
        Set-Content -LiteralPath (Join-Path $script:VaultPath "today-note.md") -Value @(
            "---",
            ("scheduled: {0}" -f (Get-Date).ToString("yyyy-MM-dd")),
            "---",
            "",
            "# Today Note"
        )
        Set-Content -LiteralPath (Join-Path $script:VaultPath "overdue-note.md") -Value @(
            "---",
            ("due: {0}" -f (Get-Date).AddDays(-1).ToString("yyyy-MM-dd")),
            "---",
            "",
            "# Overdue Note"
        )

        $todayResult = Invoke-NoteCli -VaultPath $script:VaultPath -Arguments @("agenda", "today")
        $overdueResult = Invoke-NoteCli -VaultPath $script:VaultPath -Arguments @("agenda", "overdue")

        $todayResult.ExitCode | Should -Be 0
        $todayResult.Text | Should -Match "Today Note"
        $todayResult.Text | Should -Not -Match "Overdue Note"

        $overdueResult.ExitCode | Should -Be 0
        $overdueResult.Text | Should -Match "Overdue Note"
        $overdueResult.Text | Should -Match "overdue"
        $overdueResult.Text | Should -Not -Match "Today Note"
    }

    It "collects open tasks by default" {
        Set-Content -LiteralPath (Join-Path $script:VaultPath "tasks.md") -Value @(
            "# Tasks",
            "",
            "- [ ] First open task",
            "- [x] Finished task",
            "* [ ] Second open task"
        )

        $result = Invoke-NoteCli -VaultPath $script:VaultPath -Arguments @("tasks")

        $result.ExitCode | Should -Be 0
        $result.Text | Should -Match "tasks.md:3  \[open\] First open task"
        $result.Text | Should -Match "tasks.md:5  \[open\] Second open task"
        $result.Text | Should -Not -Match "Finished task"
    }

    It "can collect done tasks or all tasks" {
        Set-Content -LiteralPath (Join-Path $script:VaultPath "tasks.md") -Value @(
            "# Tasks",
            "",
            "- [ ] First open task",
            "- [x] Finished task"
        )

        $doneResult = Invoke-NoteCli -VaultPath $script:VaultPath -Arguments @("tasks", "done")
        $allResult = Invoke-NoteCli -VaultPath $script:VaultPath -Arguments @("tasks", "all")

        $doneResult.ExitCode | Should -Be 0
        $doneResult.Text | Should -Match "tasks.md:4  \[done\] Finished task"
        $doneResult.Text | Should -Not -Match "First open task"

        $allResult.ExitCode | Should -Be 0
        $allResult.Text | Should -Match "First open task"
        $allResult.Text | Should -Match "Finished task"
    }

    It "includes note metadata context in task output" {
        Set-Content -LiteralPath (Join-Path $script:VaultPath "project-a.md") -Value @(
            "---",
            "project: Website Refresh",
            "status: active",
            "priority: high",
            "due: 2026-03-15",
            "scheduled: 2026-03-13",
            "---",
            "",
            "# Project A",
            "",
            "- [ ] Review landing page copy"
        )

        $result = Invoke-NoteCli -VaultPath $script:VaultPath -Arguments @("tasks")

        $result.ExitCode | Should -Be 0
        $result.Text | Should -Match "Review landing page copy"
        $result.Text | Should -Match "project Website Refresh"
        $result.Text | Should -Match "status active"
        $result.Text | Should -Match "priority high"
        $result.Text | Should -Match "scheduled 2026-03-13"
        $result.Text | Should -Match "due 2026-03-15"
    }

    It "filters open tasks for today based on note frontmatter dates" {
        $today = (Get-Date).ToString("yyyy-MM-dd")
        $tomorrow = (Get-Date).AddDays(1).ToString("yyyy-MM-dd")

        Set-Content -LiteralPath (Join-Path $script:VaultPath "today-task.md") -Value @(
            "---",
            ("scheduled: {0}" -f $today),
            "status: active",
            "---",
            "",
            "# Today Task",
            "",
            "- [ ] Follow up today"
        )
        Set-Content -LiteralPath (Join-Path $script:VaultPath "later-task.md") -Value @(
            "---",
            ("due: {0}" -f $tomorrow),
            "---",
            "",
            "# Later Task",
            "",
            "- [ ] Handle later"
        )

        $result = Invoke-NoteCli -VaultPath $script:VaultPath -Arguments @("tasks", "today")

        $result.ExitCode | Should -Be 0
        $result.Text | Should -Match "Follow up today"
        $result.Text | Should -Match "scheduled $today"
        $result.Text | Should -Not -Match "Handle later"
    }

    It "filters overdue tasks based on note due dates" {
        $yesterday = (Get-Date).AddDays(-1).ToString("yyyy-MM-dd")
        $today = (Get-Date).ToString("yyyy-MM-dd")

        Set-Content -LiteralPath (Join-Path $script:VaultPath "overdue-task.md") -Value @(
            "---",
            ("due: {0}" -f $yesterday),
            "priority: urgent",
            "---",
            "",
            "# Overdue Task",
            "",
            "- [ ] Fix overdue item"
        )
        Set-Content -LiteralPath (Join-Path $script:VaultPath "today-task.md") -Value @(
            "---",
            ("due: {0}" -f $today),
            "---",
            "",
            "# Today Task",
            "",
            "- [ ] Fix today item"
        )

        $result = Invoke-NoteCli -VaultPath $script:VaultPath -Arguments @("tasks", "overdue")

        $result.ExitCode | Should -Be 0
        $result.Text | Should -Match "Fix overdue item"
        $result.Text | Should -Match "due $yesterday"
        $result.Text | Should -Match "priority urgent"
        $result.Text | Should -Not -Match "Fix today item"
    }

    It "creates weekly and monthly notes without opening an editor" {
        $weeklyResult = Invoke-NoteCli -VaultPath $script:VaultPath -Arguments @("weekly", "2026-03-12")
        $monthlyResult = Invoke-NoteCli -VaultPath $script:VaultPath -Arguments @("monthly", "2026-03-12")
        $weeklyPath = Join-Path (Join-Path $script:VaultPath "weekly") "2026-W11.md"
        $monthlyPath = Join-Path (Join-Path $script:VaultPath "monthly") "2026-03.md"

        $weeklyResult.ExitCode | Should -Be 0
        $weeklyResult.Text | Should -Be $weeklyPath
        (Get-Content -LiteralPath $weeklyPath -Raw) | Should -Match "## Priorities"

        $monthlyResult.ExitCode | Should -Be 0
        $monthlyResult.Text | Should -Be $monthlyPath
        (Get-Content -LiteralPath $monthlyPath -Raw) | Should -Match "## Goals"
    }

    It "suggests related notes and prints a local graph" {
        Set-Content -LiteralPath (Join-Path $script:VaultPath "project-a.md") -Value @(
            "# Project A",
            "",
            "Tags: #work #planning",
            "",
            "See [[Shared Note]]."
        )
        Set-Content -LiteralPath (Join-Path $script:VaultPath "project-b.md") -Value @(
            "# Project B",
            "",
            "Tags: #work",
            "",
            "See [[Project A]] and [[Shared Note]]."
        )
        Set-Content -LiteralPath (Join-Path $script:VaultPath "shared-note.md") -Value @(
            "# Shared Note"
        )

        $relatedResult = Invoke-NoteCli -VaultPath $script:VaultPath -Arguments @("related", "Project A")
        $graphResult = Invoke-NoteCli -VaultPath $script:VaultPath -Arguments @("graph", "Project A")

        $relatedResult.ExitCode | Should -Be 0
        $relatedResult.Text | Should -Match "Project B"
        $relatedResult.Text | Should -Match "score"

        $graphResult.ExitCode | Should -Be 0
        $graphResult.Text | Should -Match "graph TD"
        $graphResult.Text | Should -Match "Project A"
        $graphResult.Text | Should -Match "Shared Note"
    }

    It "merges a note into another and rewrites links" {
        $sourcePath = Join-Path $script:VaultPath "source-note.md"
        $targetPath = Join-Path $script:VaultPath "target-note.md"
        $referrerPath = Join-Path $script:VaultPath "referrer.md"

        Set-Content -LiteralPath $sourcePath -Value @(
            "# Source Note",
            "",
            "Body from source."
        )
        Set-Content -LiteralPath $targetPath -Value @(
            "# Target Note",
            "",
            "Existing target body."
        )
        Set-Content -LiteralPath $referrerPath -Value @(
            "# Referrer",
            "",
            "See [[Source Note]]."
        )

        $result = Invoke-NoteCli -VaultPath $script:VaultPath -Arguments @("merge", "Source Note", "Target Note")

        $result.ExitCode | Should -Be 0
        $result.Text | Should -Be $targetPath
        (Test-Path -LiteralPath $sourcePath) | Should -Be $false

        $mergedContent = Get-Content -LiteralPath $targetPath -Raw
        $referrerContent = Get-Content -LiteralPath $referrerPath -Raw

        $mergedContent | Should -Match "## Merged from Source Note"
        $mergedContent | Should -Match "Body from source."
        $referrerContent | Should -Match "\[\[Target Note\]\]"
        $referrerContent | Should -Not -Match "\[\[Source Note\]\]"
    }

    It "splits a heading section into a new linked note" {
        $sourcePath = Join-Path $script:VaultPath "project.md"

        Set-Content -LiteralPath $sourcePath -Value @(
            "# Project",
            "",
            "Intro.",
            "",
            "## Decisions",
            "",
            "Decision details.",
            "",
            "## Next Steps",
            "",
            "Do the thing."
        )

        $result = Invoke-NoteCli -VaultPath $script:VaultPath -Arguments @("split", "Project", "Decisions", "Project Decisions")
        $newPath = Join-Path $script:VaultPath "project-decisions.md"

        $result.ExitCode | Should -Be 0
        $result.Text | Should -Be $newPath
        (Test-Path -LiteralPath $newPath) | Should -Be $true

        $newContent = Get-Content -LiteralPath $newPath -Raw
        $sourceContent = Get-Content -LiteralPath $sourcePath -Raw

        $newContent | Should -Match "# Decisions"
        $newContent | Should -Match "Decision details."
        $sourceContent | Should -Match "Moved to \[\[Project Decisions\]\]"
        $sourceContent | Should -Match "## Next Steps"
    }

    It "repairs unresolved links when there is a clear fuzzy match" {
        $sourcePath = Join-Path $script:VaultPath "source.md"
        $targetPath = Join-Path $script:VaultPath "project-archive.md"

        Set-Content -LiteralPath $targetPath -Value @(
            "# Project Archive"
        )
        Set-Content -LiteralPath $sourcePath -Value @(
            "# Source",
            "",
            "See [[Project Archve]]."
        )

        $result = Invoke-NoteCli -VaultPath $script:VaultPath -Arguments @("repair-links")
        $updatedContent = Get-Content -LiteralPath $sourcePath -Raw

        $result.ExitCode | Should -Be 0
        $result.Text | Should -Match "Project Archve"
        $result.Text | Should -Match "Project Archive"
        $updatedContent | Should -Match "\[\[Project Archive\]\]"
        $updatedContent | Should -Not -Match "\[\[Project Archve\]\]"
    }

    It "reads and updates frontmatter properties" {
        Set-Content -LiteralPath (Join-Path $script:VaultPath "project.md") -Value @(
            "# Project"
        )

        $setStatus = Invoke-NoteCli -VaultPath $script:VaultPath -Arguments @("props", "project", "set", "status", "active")
        $addTags = Invoke-NoteCli -VaultPath $script:VaultPath -Arguments @("props", "project", "add", "tags", "work,planning")
        $show = Invoke-NoteCli -VaultPath $script:VaultPath -Arguments @("props", "project")
        $content = Get-Content -LiteralPath (Join-Path $script:VaultPath "project.md") -Raw

        $setStatus.ExitCode | Should -Be 0
        $addTags.ExitCode | Should -Be 0
        $show.ExitCode | Should -Be 0
        $show.Text | Should -Match "status: active"
        $show.Text | Should -Match "tags: planning, work|tags: work, planning"
        $content | Should -Match "(?s)^---"
        $content | Should -Match "status: active"
        $content | Should -Match "tags:"
    }

    It "can unset an existing frontmatter property" {
        Set-Content -LiteralPath (Join-Path $script:VaultPath "project.md") -Value @(
            "---",
            "status: active",
            "priority: high",
            "---",
            "",
            "# Project"
        )

        $unset = Invoke-NoteCli -VaultPath $script:VaultPath -Arguments @("props", "project", "unset", "priority")
        $show = Invoke-NoteCli -VaultPath $script:VaultPath -Arguments @("props", "project")
        $content = Get-Content -LiteralPath (Join-Path $script:VaultPath "project.md") -Raw

        $unset.ExitCode | Should -Be 0
        $show.ExitCode | Should -Be 0
        $show.Text | Should -Match "status: active"
        $show.Text | Should -Not -Match "priority:"
        $content | Should -Not -Match "priority:"
    }

    It "validates structured property values" {
        Set-Content -LiteralPath (Join-Path $script:VaultPath "project.md") -Value @(
            "# Project"
        )

        $badStatus = Invoke-NoteCli -VaultPath $script:VaultPath -Arguments @("props", "project", "set", "status", "flying")
        $badPriority = Invoke-NoteCli -VaultPath $script:VaultPath -Arguments @("props", "project", "set", "priority", "extreme")
        $badDue = Invoke-NoteCli -VaultPath $script:VaultPath -Arguments @("props", "project", "set", "due", "not-a-date")

        $badStatus.ExitCode | Should -Be 1
        $badStatus.Text | Should -Match "Invalid status"
        $badPriority.ExitCode | Should -Be 1
        $badPriority.Text | Should -Match "Invalid priority"
        $badDue.ExitCode | Should -Be 1
        $badDue.Text | Should -Match "Invalid due date"
    }

    It "reads frontmatter correctly when the file starts with a UTF-8 BOM" {
        $path = Join-Path $script:VaultPath "bom-note.md"
        $bom = [char]0xFEFF
        Set-Content -LiteralPath $path -Value @(
            ($bom + "---"),
            "tags:",
            "  - work",
            "---",
            "",
            "# BOM Note"
        )

        $result = Invoke-NoteCli -VaultPath $script:VaultPath -Arguments @("tags", "work")

        $result.ExitCode | Should -Be 0
        $result.Text | Should -Match "BOM Note  bom-note.md"
    }

    It "resolves aliases from frontmatter in existing commands" {
        Set-Content -LiteralPath (Join-Path $script:VaultPath "project.md") -Value @(
            "---",
            "aliases:",
            "  - Idea Bank",
            "tags:",
            "  - work",
            "---",
            "",
            "# Project"
        )

        $preview = Invoke-NoteCli -VaultPath $script:VaultPath -Arguments @("preview", "Idea Bank")
        $tags = Invoke-NoteCli -VaultPath $script:VaultPath -Arguments @("tags", "work")

        $preview.ExitCode | Should -Be 0
        $preview.Text | Should -Match "# Project"
        $tags.ExitCode | Should -Be 0
        $tags.Text | Should -Match "Project  project.md"
    }

    It "renames a note and updates wiki links while preserving aliases" {
        $oldPath = Join-Path $script:VaultPath "old-note.md"
        $sourcePath = Join-Path $script:VaultPath "source.md"

        Set-Content -LiteralPath $oldPath -Value @(
            "# Old Note",
            "",
            "Self link to [[Old Note]]."
        )
        Set-Content -LiteralPath $sourcePath -Value @(
            "# Source",
            "",
            "Plain [[Old Note]] and aliased [[old-note|Custom Label]]."
        )

        $result = Invoke-NoteCli -VaultPath $script:VaultPath -Arguments @("rename", "Old Note", "New Note")
        $newPath = Join-Path $script:VaultPath "new-note.md"

        $result.ExitCode | Should -Be 0
        $result.Text | Should -Be $newPath
        (Test-Path -LiteralPath $newPath) | Should -Be $true
        (Test-Path -LiteralPath $oldPath) | Should -Be $false

        $renamedNote = Get-Content -LiteralPath $newPath -Raw
        $sourceNote = Get-Content -LiteralPath $sourcePath -Raw

        $renamedNote | Should -Match "# New Note"
        $renamedNote | Should -Match "\[\[New Note\]\]"
        $sourceNote | Should -Match "\[\[New Note\]\]"
        $sourceNote | Should -Match "\[\[New Note\|Custom Label\]\]"
        $sourceNote | Should -Not -Match "\[\[Old Note\]\]"
        $sourceNote | Should -Not -Match "\[\[old-note\|Custom Label\]\]"
    }

    It "renames a note and updates headings with irregular heading whitespace" {
        $oldPath = Join-Path $script:VaultPath "old-note.md"
        Set-Content -LiteralPath $oldPath -Value @(
            "#  Old Note   ",
            "",
            "Body"
        )

        $result = Invoke-NoteCli -VaultPath $script:VaultPath -Arguments @("rename", "Old Note", "New Note")
        $newPath = Join-Path $script:VaultPath "new-note.md"
        $content = Get-Content -LiteralPath $newPath -Raw

        $result.ExitCode | Should -Be 0
        $content | Should -Match "^# New Note"
    }

    It "renames a note into a folder and adds old title and path aliases" {
        $oldPath = Join-Path $script:VaultPath "projects\\old-note.md"
        $sourcePath = Join-Path $script:VaultPath "source.md"
        New-Item -ItemType Directory -Path (Split-Path -Parent $oldPath) -Force | Out-Null

        Set-Content -LiteralPath $oldPath -Value @(
            "---",
            "aliases:",
            "  - Existing Alias",
            "---",
            "",
            "# Old Note",
            "",
            "Self link to [[projects/old-note]]."
        )
        Set-Content -LiteralPath $sourcePath -Value @(
            "# Source",
            "",
            "Link to [[Old Note]] and [[projects/old-note]]."
        )

        $result = Invoke-NoteCli -VaultPath $script:VaultPath -Arguments @("rename", "projects/old-note", "archive/New Note")
        $newPath = Join-Path (Join-Path $script:VaultPath "archive") "new-note.md"
        $renamedContent = Get-Content -LiteralPath $newPath -Raw
        $sourceNote = Get-Content -LiteralPath $sourcePath -Raw

        $result.ExitCode | Should -Be 0
        $result.Text | Should -Be $newPath
        (Test-Path -LiteralPath $newPath) | Should -Be $true
        $renamedContent | Should -Match "Existing Alias"
        $renamedContent | Should -Match "Old Note"
        $renamedContent | Should -Match "projects/old-note"
        $sourceNote | Should -Match "\[\[archive/new-note\]\]"
        $sourceNote | Should -Not -Match "\[\[Old Note\]\]"
        $sourceNote | Should -Not -Match "\[\[projects/old-note\]\]"
    }

    It "rejects renames that would move a note outside the vault" {
        $oldPath = Join-Path $script:VaultPath "old-note.md"
        Set-Content -LiteralPath $oldPath -Value @(
            "# Old Note"
        )

        $result = Invoke-NoteCli -VaultPath $script:VaultPath -Arguments @("rename", "Old Note", "..\\escape")

        $result.ExitCode | Should -Not -Be 0
        $result.Text | Should -Match "must stay within the vault"
        (Test-Path -LiteralPath $oldPath) | Should -Be $true
    }

    It "reports an ambiguous fuzzy note match instead of creating a new note silently" {
        Set-Content -LiteralPath (Join-Path $script:VaultPath "terminal-ui.md") -Value @("# Terminal UI")
        Set-Content -LiteralPath (Join-Path $script:VaultPath "terminal-usage.md") -Value @("# Terminal Usage")

        $result = Invoke-NoteCli -VaultPath $script:VaultPath -Arguments @("open", "termu")

        $result.ExitCode | Should -Not -Be 0
        $result.Text | Should -Match "Ambiguous note name"
        (Test-Path -LiteralPath (Join-Path $script:VaultPath "termu.md")) | Should -Be $false
    }

    It "lists unresolved wiki links across the vault" {
        Set-Content -LiteralPath (Join-Path $script:VaultPath "source.md") -Value @(
            "# Source",
            "",
            "Links to [[Missing Note]] and [[Existing Note]]."
        )
        Set-Content -LiteralPath (Join-Path $script:VaultPath "existing-note.md") -Value @(
            "# Existing Note"
        )

        $result = Invoke-NoteCli -VaultPath $script:VaultPath -Arguments @("unresolved")

        $result.ExitCode | Should -Be 0
        $result.Text | Should -Match "source.md -> \[\[Missing Note\]\] -> missing-note.md"
        $result.Text | Should -Not -Match "Existing Note"
    }

    It "lists unresolved wiki links for a single note" {
        Set-Content -LiteralPath (Join-Path $script:VaultPath "source.md") -Value @(
            "# Source",
            "",
            "Links to [[Missing Note]]."
        )
        Set-Content -LiteralPath (Join-Path $script:VaultPath "other.md") -Value @(
            "# Other",
            "",
            "Links to [[Another Missing]]."
        )

        $result = Invoke-NoteCli -VaultPath $script:VaultPath -Arguments @("unresolved", "source")

        $result.ExitCode | Should -Be 0
        $result.Text | Should -Match "source.md -> \[\[Missing Note\]\] -> missing-note.md"
        $result.Text | Should -Not -Match "Another Missing"
    }

    It "creates notes for all unresolved links" {
        Set-Content -LiteralPath (Join-Path $script:VaultPath "source.md") -Value @(
            "# Source",
            "",
            "Links to [[Missing Note]] and [[Another Missing]]."
        )

        $result = Invoke-NoteCli -VaultPath $script:VaultPath -Arguments @("create-unresolved", "all")

        $result.ExitCode | Should -Be 0
        (Test-Path -LiteralPath (Join-Path $script:VaultPath "missing-note.md")) | Should -Be $true
        (Test-Path -LiteralPath (Join-Path $script:VaultPath "another-missing.md")) | Should -Be $true
        $result.Text | Should -Match "missing-note.md"
        $result.Text | Should -Match "another-missing.md"
    }

    It "creates one selected unresolved link target" {
        Set-Content -LiteralPath (Join-Path $script:VaultPath "source.md") -Value @(
            "# Source",
            "",
            "Links to [[Missing Note]] and [[Another Missing]]."
        )

        $result = Invoke-NoteCli -VaultPath $script:VaultPath -Arguments @("create-unresolved", "Missing Note")

        $result.ExitCode | Should -Be 0
        (Test-Path -LiteralPath (Join-Path $script:VaultPath "missing-note.md")) | Should -Be $true
        (Test-Path -LiteralPath (Join-Path $script:VaultPath "another-missing.md")) | Should -Be $false
        $result.Text | Should -Match "missing-note.md"
    }

    It "pick opens the selected fuzzy match in no-open mode" {
        Set-Content -LiteralPath (Join-Path $script:VaultPath "welcome.md") -Value @(
            "# Welcome"
        )

        $result = Invoke-InteractivePick -VaultPath $script:VaultPath -InputText "1" -Query "welcome"

        $result.ExitCode | Should -Be 0
        $result.Text | Should -Match "Matches for 'welcome':"
        $result.Text | Should -Match "1\. Welcome  welcome\.md"
        $result.Text | Should -Match ([regex]::Escape((Join-Path $script:VaultPath "welcome.md")))
    }

    It "pick can create a new note when there are no matches" {
        $result = Invoke-InteractivePick -VaultPath $script:VaultPath -InputText "y" -Query "scratch-pad"
        $createdPath = Join-Path $script:VaultPath "scratch-pad.md"

        $result.ExitCode | Should -Be 0
        $result.Text | Should -Match ([regex]::Escape($createdPath))
        (Test-Path -LiteralPath $createdPath) | Should -Be $true
        (Get-Content -LiteralPath $createdPath -Raw) | Should -Match "# scratch-pad"
    }
}
