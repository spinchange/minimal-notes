# Minimal Notes

A lightweight, local-first, Obsidian-inspired notes CLI for PowerShell 7.

Minimal Notes keeps the model simple: your notes are plain markdown files in a local `vault`, and the CLI adds the connective tissue around them.

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
- frontmatter properties, tags, and aliases
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
agenda     Show notes with due or scheduled frontmatter dates.
tasks      Collect markdown checkbox tasks across the vault.
          Supports open, done, all, today, and overdue views.
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
path       Print the current vault path.
help       Show this help.
```

## Environment

```powershell
$env:MINIMAL_NOTES_VAULT = "C:\Users\user\Documents\notes"
$env:MINIMAL_NOTES_TEMPLATES = "C:\Users\user\Documents\note-templates"
$env:MINIMAL_NOTES_EDITOR = "notepad.exe"
$env:MINIMAL_NOTES_NO_OPEN = "1"
```

If `MINIMAL_NOTES_EDITOR` is not set, the script tries `code` first and falls back to `notepad.exe`.

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

Capture and review:

```powershell
pwsh -NoProfile -File .\note.ps1 capture "remember to simplify the picker"
pwsh -NoProfile -File .\note.ps1 capture daily "ship the prototype"
pwsh -NoProfile -File .\note.ps1 orphans
pwsh -NoProfile -File .\note.ps1 recent 5
pwsh -NoProfile -File .\note.ps1 agenda
pwsh -NoProfile -File .\note.ps1 tasks
pwsh -NoProfile -File .\note.ps1 tasks today
pwsh -NoProfile -File .\note.ps1 tasks overdue
```

Read or update frontmatter properties:

```powershell
pwsh -NoProfile -File .\note.ps1 props "Project Ideas"
pwsh -NoProfile -File .\note.ps1 props "Project Ideas" set status active
pwsh -NoProfile -File .\note.ps1 props "Project Ideas" add tags work,planning
pwsh -NoProfile -File .\note.ps1 props "Project Ideas" add aliases "Idea Bank"
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
```

## Roadmap

### Phase 1: Metadata-aware workflows

Focus: turn frontmatter into day-to-day utility.

- ~~`agenda` driven by fields like `due`, `scheduled`, `status`, and `priority`~~
- ~~smarter `tasks` that include note context such as project, status, and priority~~
- ~~note templates for common frontmatter and note shapes~~
- better `props` support, including `unset`, clearer list editing, and stronger validation
- weekly and monthly note workflows built on top of the existing daily note model

### Phase 2: Retrieval and structure

Focus: make the vault easier to navigate as it grows.

- `related <note>` suggestions from links, tags, aliases, and text overlap
- stricter orphan and stale-note views
- local note maps or Mermaid graph export
- saved queries and richer search filters that combine text, tags, props, and task state
- dashboards that summarize recent notes, tasks, unresolved links, and due items

### Phase 3: Refactoring tools

Focus: help reorganize a growing vault safely.

- merge two notes and rewrite incoming links
- split sections into new linked notes
- repair broken or ambiguous links with suggestions
- dedupe near-duplicate notes by title or content similarity
- extend `rename` to handle more path-move and alias-update cases

### Phase 4: Architecture and polish

Focus: keep the codebase maintainable as features expand.

- split the project into a reusable PowerShell module plus a thin CLI wrapper
- add deeper parsing and unit tests alongside the current smoke tests
- introduce a config file for vault defaults, editor, templates, and display preferences
- improve performance for larger vaults, potentially with an optional lightweight index

### Suggested next build order

1. ~~`agenda`~~
2. ~~metadata-aware `tasks`~~
3. ~~templates~~
4. module refactor
5. dashboards or reports
6. related/graph tooling
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

- 35 tests passing
- 0 failures

## License

[MIT](./LICENSE)
