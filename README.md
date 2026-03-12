# Minimal Notes

A lightweight, stripped-down Obsidian-style notes setup for PowerShell 7.

Notes are just markdown files in the local `vault` folder. The CLI gives you:

- note creation
- editor launch
- plain-text search
- fuzzy note finding
- interactive note picker
- quick capture
- orphan-note detection
- recent note listing
- task collection
- frontmatter properties
- note rename with link updates
- unresolved-link detection
- wiki links like `[[Project Ideas]]`
- backlinks
- tag discovery
- terminal preview
- daily notes

## Quick start

From `C:\Users\user\minimal-notes`:

```powershell
pwsh -NoProfile -File .\note.ps1 help
pwsh -NoProfile -File .\note.ps1 new "Project Ideas"
pwsh -NoProfile -File .\note.ps1 open "Project Ideas"
pwsh -NoProfile -File .\note.ps1 search powershell
pwsh -NoProfile -File .\note.ps1 find pwsh
pwsh -NoProfile -File .\note.ps1 pick termui
pwsh -NoProfile -File .\note.ps1 capture "remember this"
pwsh -NoProfile -File .\note.ps1 capture daily "follow up on the build"
pwsh -NoProfile -File .\note.ps1 orphans
pwsh -NoProfile -File .\note.ps1 recent 5
pwsh -NoProfile -File .\note.ps1 tasks
pwsh -NoProfile -File .\note.ps1 props "Project Ideas"
pwsh -NoProfile -File .\note.ps1 props "Project Ideas" set status active
pwsh -NoProfile -File .\note.ps1 rename "Old Note" "New Note"
pwsh -NoProfile -File .\note.ps1 unresolved
pwsh -NoProfile -File .\note.ps1 create-unresolved all
pwsh -NoProfile -File .\note.ps1 backlinks "Project Ideas"
pwsh -NoProfile -File .\note.ps1 tags
pwsh -NoProfile -File .\note.ps1 daily
```

Run tests:

```powershell
pwsh -NoProfile -File .\run-tests.ps1
```

## Vault layout

```text
minimal-notes/
  note.ps1
  README.md
  vault/
    inbox.md
    welcome.md
    daily/
```

## Commands

```text
new        Create a note from a title or path-like name.
open       Open an existing note, or create it if missing.
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
path       Print the current vault path.
help       Show the built-in help.
```

## Optional environment variables

```powershell
$env:MINIMAL_NOTES_VAULT = "C:\Users\user\Documents\notes"
$env:MINIMAL_NOTES_EDITOR = "notepad.exe"
```

If `MINIMAL_NOTES_EDITOR` is not set, the script tries `code` first and falls back to `notepad.exe`.

For tests or headless usage, you can skip opening the editor:

```powershell
$env:MINIMAL_NOTES_NO_OPEN = "1"
```

## Example workflow

Create a note:

```powershell
pwsh -NoProfile -File .\note.ps1 new "PowerShell Ideas"
```

Add links inside it:

```md
# PowerShell Ideas

Tags: #powershell #ideas

Look at [[Terminal UI]] and [[Daily Review]].
```

Find outgoing links:

```powershell
pwsh -NoProfile -File .\note.ps1 links "PowerShell Ideas"
```

Find backlinks:

```powershell
pwsh -NoProfile -File .\note.ps1 backlinks "Terminal UI"
```

Find notes fuzzily:

```powershell
pwsh -NoProfile -File .\note.ps1 find termui
```

Open from a shortlist:

```powershell
pwsh -NoProfile -File .\note.ps1 pick termui
```

If you omit the query, the script asks for one and then shows a numbered list.

Quick capture to inbox:

```powershell
pwsh -NoProfile -File .\note.ps1 capture "remember to simplify the picker"
```

Quick capture to today's daily note:

```powershell
pwsh -NoProfile -File .\note.ps1 capture daily "ship the prototype"
```

Show orphan notes:

```powershell
pwsh -NoProfile -File .\note.ps1 orphans
```

Show the most recent notes:

```powershell
pwsh -NoProfile -File .\note.ps1 recent
pwsh -NoProfile -File .\note.ps1 recent 5
```

Collect open tasks:

```powershell
pwsh -NoProfile -File .\note.ps1 tasks
pwsh -NoProfile -File .\note.ps1 tasks all
pwsh -NoProfile -File .\note.ps1 tasks done
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

Rename a note and rewrite links:

```powershell
pwsh -NoProfile -File .\note.ps1 rename "Project Ideas" "Project Archive"
```

Show missing linked notes:

```powershell
pwsh -NoProfile -File .\note.ps1 unresolved
pwsh -NoProfile -File .\note.ps1 unresolved "Project Ideas"
```

Create all missing linked notes:

```powershell
pwsh -NoProfile -File .\note.ps1 create-unresolved all
```

List all tags:

```powershell
pwsh -NoProfile -File .\note.ps1 tags
```
