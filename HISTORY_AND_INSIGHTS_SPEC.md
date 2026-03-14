# History And Insights Spec

## Goal

Add Git-powered history and insight commands to `minimal-notes` without changing the core local-first note model.

## Scope

1. `note history <note>`
   Shows commit history for one note, including timestamp, commit id, summary, and basic churn.
2. `note insights activity [daily|weekly|monthly]`
   Summarizes note creation and edit activity over time.
3. `note insights tags [limit]`
   Shows which tags appear most often in changed notes over a time window.
4. `note insights projects [limit]`
   Shows which `project` frontmatter values have the most activity over a time window.

## Non-goals

- no persistent analytics database
- no background indexing daemon
- no AI summarization layer
- no cross-machine reconciliation logic beyond Git itself

## CLI Draft

```powershell
note history "Meeting Notes"
note history "Meeting Notes" --limit 20
note insights activity weekly
note insights tags --period monthly --limit 10
note insights projects --period monthly --limit 10
```

## Behavior

- commands require the vault to live inside a Git repo
- if Git is unavailable or the vault is not tracked, fail with a clear message
- outputs are terminal-friendly summaries, not raw diffs by default
- later JSON output can be added, but not in v1

## Command Details

### `note history <note>`

- resolves the note using existing name resolution
- follows renames where possible
- outputs:
  - commit short SHA
  - author date
  - commit subject
  - added/removed line counts for that note
- optional flags:
  - `--limit N`
  - future: `--show-diff`

Example output:

```text
History for Meeting Notes  meeting-notes.md

14a562d  2026-03-14  Update note new and open man pages  +12 -3
cb16595  2026-03-14  Complete roadmap hardening and test coverage  +8 -1
bc20374  2026-03-13  Add config file support  +25 -0
```

### `note insights activity [period]`

- default period: `weekly`
- uses Git commit timestamps affecting files under the vault
- reports:
  - notes changed
  - notes created
  - total commits touching vault notes
  - total added/removed lines

Example output:

```text
Activity Insights (weekly)

2026-W11  changed 34  created 9  commits 12  +420 -110
2026-W10  changed 22  created 4  commits 8   +210 -95
```

### `note insights tags`

- looks at notes changed in the selected window
- reads current note metadata for those notes
- groups by tag frequency
- limitation: v1 is current-state tags on historically changed notes, not historical tag reconstruction

Example output:

```text
Tag Insights (monthly)

#work        18
#planning    11
#agents       9
#powershell   7
```

### `note insights projects`

- same pattern as tags, but keyed on `project` frontmatter
- useful for seeing where editing effort is concentrated

Example output:

```text
Project Insights (monthly)

Q2 Planning         14
Agent Config Sync    9
Minimal Notes        8
```

## Implementation Plan

1. Add Git helper functions
   - `Get-GitRootForPath`
   - `Get-NoteGitHistory`
   - `Get-VaultGitChangedFiles`
   - `Get-GitLineStatsForPath`
2. Add history formatter
3. Add activity aggregation
4. Add tag/project aggregators using existing note parsing
5. Add tests with a temporary Git repo in test setup

## Technical Notes

- use non-interactive Git only
- prefer `git log --follow --numstat -- <path>` for note history
- prefer `git log --name-only` for vault-wide touched files
- aggregate in PowerShell after collecting Git output
- keep Git parsing isolated from CLI formatting

## Risks

- rename tracking can be imperfect in complex histories
- current-state metadata for `tags`/`project` is not true historical metadata
- large repos may need caching if repeated Git scans become slow

## Good V1 Success Criteria

- user can inspect note history quickly
- user can see weekly/monthly writing activity
- user can identify which tags/projects are receiving attention
- commands fail clearly when Git context is missing
