# Minimal Notes

A lightweight, local-first, Obsidian-inspired notes CLI for PowerShell 7.

Minimal Notes keeps the model simple: your notes are plain markdown files in a local `vault`, and the CLI adds the connective tissue around them. The project now ships as both a reusable PowerShell module and a thin CLI wrapper.

## Why this exists

This project aims for the useful core of Obsidian without the heavyweight app shell:

- local markdown files
- wiki links and backlinks
- fast capture and retrieval
- lightweight metadata and aliases
- scriptable PowerShell workflows

## Features

- note creation and opening
- full-text search and fuzzy note finding
- interactive note picker
- wiki links, backlinks, and unresolved-link detection
- quick capture to inbox or daily notes
- orphan and recent note views
- agenda from frontmatter dates
- metadata-aware task collection from markdown checkboxes
- reusable note templates with placeholder expansion
- dashboard, report, and review views
- weekly and monthly notes
- related-note suggestions and Mermaid graph output
- merge, split, and repair-link refactoring tools
- frontmatter properties, tags, aliases, and validation
- stale-note views, saved queries, and preview-only dedupe
- JSON config file with env-var override precedence
- safe note rename with automatic link updates
- terminal preview

## Quick start

From the project folder:

```powershell
pwsh -NoProfile -File .\note.ps1 help
pwsh -NoProfile -File .\note.ps1 new "Project Ideas"
pwsh -NoProfile -File .\note.ps1 capture "remember this"
pwsh -NoProfile -File .\note.ps1 template new meeting
pwsh -NoProfile -File .\note.ps1 new "Sprint Review" --template meeting
pwsh -NoProfile -File .\note.ps1 dashboard
pwsh -NoProfile -File .\note.ps1 weekly
pwsh -NoProfile -File .\note.ps1 merge "Draft" "Project Archive"
pwsh -NoProfile -File .\note.ps1 props "Project Ideas" unset priority
pwsh -NoProfile -File .\note.ps1 stale 60
pwsh -NoProfile -File .\note.ps1 query save work-today tasks today
pwsh -NoProfile -File .\note.ps1 config init
pwsh -NoProfile -File .\note.ps1 tasks
pwsh -NoProfile -File .\note.ps1 tasks today
pwsh -NoProfile -File .\note.ps1 props "Project Ideas" set status active
pwsh -NoProfile -File .\run-tests.ps1
```

## Privacy defaults

The repository intentionally ignores the contents of `vault/` by default.

- your real notes are treated as private local data
- the repo tracks code, docs, tests, and `vault/.gitkeep`
- if you want to version a vault later, you can change `.gitignore` deliberately

## Project layout

```text
minimal-notes/
  note.ps1
  MinimalNotes.psm1
  MinimalNotes.psd1
  run-tests.ps1
  tests/
  templates/
  vault/
```

## Commands

```text
new        Create a note from a title or path-like name.
open       Open an existing note, or create it if missing.
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
tasks      Collect markdown checkbox tasks across the vault.
          Supports open, done, all, today, and overdue views.
related    Suggest notes related to a target note by links and tags.
graph      Print a Mermaid note-link graph for one note or the full vault.
merge      Merge one note into another and rewrite inbound links.
split      Split a heading section into a new linked note.
repair-links Attempt to repair unresolved wiki links using fuzzy note matches.
query      Save, list, show, run, or delete read-only saved queries.
dedupe     Preview likely duplicate notes without changing files.
template   List, preview, or create note templates.
props      Read or update frontmatter properties for a note.
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
path       Print the current vault path.
help       Show this help.
```

## Environment

```powershell
$env:MINIMAL_NOTES_VAULT = "C:\Users\user\Documents\notes"
$env:MINIMAL_NOTES_CONFIG = "C:\Users\user\Documents\minimal-notes.config.json"
$env:MINIMAL_NOTES_TEMPLATES = "C:\Users\user\Documents\note-templates"
$env:MINIMAL_NOTES_EDITOR = "notepad.exe"
$env:MINIMAL_NOTES_NO_OPEN = "1"
```

If `MINIMAL_NOTES_EDITOR` is not set, the script tries `code` first and falls back to `notepad.exe`.

Environment variables override config file values.

## Module use

You can use the reusable module directly:

```powershell
Import-Module .\MinimalNotes.psd1 -Force
Invoke-MinimalNotesCli -Command list
Get-MinimalNotesVaultPath
```

## Config file

Initialize a starter config:

```powershell
pwsh -NoProfile -File .\note.ps1 config init
pwsh -NoProfile -File .\note.ps1 config
```

Example:

```json
{
  "vault": "C:\\Users\\user\\Documents\\notes",
  "templates": "C:\\Users\\user\\Documents\\note-templates",
  "queries": "C:\\Users\\user\\Documents\\saved-queries.json",
  "editor": "notepad.exe",
  "noOpen": false,
  "defaults": {
    "staleDays": 30,
    "dashboardLimit": 5
  }
}
```

## Example workflow

Create a note:

```powershell
pwsh -NoProfile -File .\note.ps1 new "PowerShell Ideas"
```

Create and use a template:

```powershell
pwsh -NoProfile -File .\note.ps1 template new meeting
pwsh -NoProfile -File .\note.ps1 template show meeting
pwsh -NoProfile -File .\note.ps1 new "Weekly Sync" --template meeting
```

Add links inside it:

```md
# PowerShell Ideas

Tags: #powershell #ideas

Look at [[Terminal UI]] and [[Daily Review]].
```

Work with notes:

```powershell
pwsh -NoProfile -File .\note.ps1 links "PowerShell Ideas"
pwsh -NoProfile -File .\note.ps1 backlinks "Terminal UI"
pwsh -NoProfile -File .\note.ps1 find termui
pwsh -NoProfile -File .\note.ps1 pick termui
```

When fuzzy note or template matches tie on score, Minimal Notes prefers the most recently modified match.

Capture and review:

```powershell
pwsh -NoProfile -File .\note.ps1 capture "remember to simplify the picker"
pwsh -NoProfile -File .\note.ps1 capture daily "ship the prototype"
pwsh -NoProfile -File .\note.ps1 orphans
pwsh -NoProfile -File .\note.ps1 recent 5
pwsh -NoProfile -File .\note.ps1 dashboard
pwsh -NoProfile -File .\note.ps1 agenda
pwsh -NoProfile -File .\note.ps1 tasks
pwsh -NoProfile -File .\note.ps1 tasks today
pwsh -NoProfile -File .\note.ps1 tasks overdue
pwsh -NoProfile -File .\note.ps1 review
pwsh -NoProfile -File .\note.ps1 report weekly
```

Read or update frontmatter properties:

```powershell
pwsh -NoProfile -File .\note.ps1 props "Project Ideas"
pwsh -NoProfile -File .\note.ps1 props "Project Ideas" set status active
pwsh -NoProfile -File .\note.ps1 props "Project Ideas" add tags work,planning
pwsh -NoProfile -File .\note.ps1 props "Project Ideas" add aliases "Idea Bank"
pwsh -NoProfile -File .\note.ps1 props "Project Ideas" unset priority
```

Frontmatter looks like:

```md
---
status: active
tags:
  - work
  - planning
aliases:
  - Idea Bank
---
```

Built-in validation currently covers:

- `status`: `open`, `active`, `in-progress`, `blocked`, `waiting`, `done`, `completed`, `cancelled`, `canceled`, `archived`
- `priority`: `low`, `medium`, `normal`, `high`, `urgent`
- `due` and `scheduled`: parseable dates like `2026-03-20`

Agenda reads frontmatter like:

```md
---
status: active
priority: high
scheduled: 2026-03-14
due: 2026-03-16
---
```

Then:

```powershell
pwsh -NoProfile -File .\note.ps1 agenda
pwsh -NoProfile -File .\note.ps1 agenda today
pwsh -NoProfile -File .\note.ps1 agenda overdue
pwsh -NoProfile -File .\note.ps1 agenda all
pwsh -NoProfile -File .\note.ps1 tasks
pwsh -NoProfile -File .\note.ps1 tasks today
pwsh -NoProfile -File .\note.ps1 tasks overdue
```

Task output includes note context when available, such as `project`, `status`, `priority`, `scheduled`, and `due`.

Templates are plain markdown files stored in `templates/`. They support a few built-in placeholders:

- `{{title}}`
- `{{slug}}`
- `{{date}}`
- `{{time}}`
- `{{datetime}}`
- `{{year}}`
- `{{month}}`
- `{{day}}`

Maintain link structure:

```powershell
pwsh -NoProfile -File .\note.ps1 rename "Project Ideas" "Project Archive"
pwsh -NoProfile -File .\note.ps1 unresolved
pwsh -NoProfile -File .\note.ps1 create-unresolved all
pwsh -NoProfile -File .\note.ps1 related "Project Archive"
pwsh -NoProfile -File .\note.ps1 graph "Project Archive"
pwsh -NoProfile -File .\note.ps1 merge "Project Draft" "Project Archive"
pwsh -NoProfile -File .\note.ps1 split "Project Archive" "Decisions" "Project Decisions"
pwsh -NoProfile -File .\note.ps1 repair-links
pwsh -NoProfile -File .\note.ps1 stale 45
pwsh -NoProfile -File .\note.ps1 query save work-today tasks today
pwsh -NoProfile -File .\note.ps1 query run work-today
pwsh -NoProfile -File .\note.ps1 dedupe
pwsh -NoProfile -File .\note.ps1 config
```

Calendar and overview workflows:

```powershell
pwsh -NoProfile -File .\note.ps1 dashboard
pwsh -NoProfile -File .\note.ps1 report monthly
pwsh -NoProfile -File .\note.ps1 review weekly
pwsh -NoProfile -File .\note.ps1 weekly
pwsh -NoProfile -File .\note.ps1 monthly
```

## Roadmap

### Phase 1: Metadata-aware workflows

Focus: turn frontmatter into day-to-day utility.

- ~~`agenda` driven by fields like `due`, `scheduled`, `status`, and `priority`~~
- ~~smarter `tasks` that include note context such as project, status, and priority~~
- ~~note templates for common frontmatter and note shapes~~
- ~~better `props` support, including `unset`, clearer list editing, and stronger validation~~
- ~~weekly and monthly note workflows built on top of the existing daily note model~~

### Phase 2: Retrieval and structure

Focus: make the vault easier to navigate as it grows.

- ~~`related <note>` suggestions from links, tags, aliases, and text overlap~~
- ~~stricter orphan and stale-note views~~
- ~~local note maps or Mermaid graph export~~
- ~~saved queries and richer search filters that combine text, tags, props, and task state~~
- ~~dashboards that summarize recent notes, tasks, unresolved links, and due items~~
- ~~reports or review views built from agenda, task, and note activity~~

### Phase 3: Refactoring tools

Focus: help reorganize a growing vault safely.

- ~~merge two notes and rewrite incoming links~~
- ~~split sections into new linked notes~~
- ~~repair broken or ambiguous links with suggestions~~
- ~~dedupe near-duplicate notes by title or content similarity~~
- ~~extend `rename` to handle more path-move and alias-update cases~~

### Phase 4: Architecture and polish

Focus: keep the codebase maintainable as features expand.

- ~~split the project into a reusable PowerShell module plus a thin CLI wrapper~~
- ~~add deeper parsing and unit tests alongside the current smoke tests~~
- ~~introduce a config file for vault defaults, editor, templates, and display preferences~~
- ~~improve performance for larger vaults, potentially with an optional lightweight index~~

### Suggested next build order

1. ~~`agenda`~~
2. ~~metadata-aware `tasks`~~
3. ~~templates~~
4. ~~module refactor~~
5. ~~dashboards or reports~~
6. ~~related/graph tooling~~
7. merge/split/repair refactoring commands

## Testing

Run the local test suite:

```powershell
pwsh -NoProfile -File .\run-tests.ps1
```

`run-tests.ps1` expects Pester 5 or later. If needed:

```powershell
Install-Module Pester -Scope CurrentUser -Force -SkipPublisherCheck
```

Current local status:

- 72 tests passing
- 0 failures

## License

[MIT](./LICENSE)
