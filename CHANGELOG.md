# Changelog

All notable changes to this project are documented here.

## Unreleased

### Added

- `agenda` command with `today`, `overdue`, and `all` views based on frontmatter fields like `scheduled`, `due`, `status`, and `priority`
- metadata-aware agenda tests covering active, today, and overdue cases
- metadata-aware `tasks` views with `today` and `overdue` filters driven by note frontmatter
- task output now includes note context like project, status, priority, scheduled date, and due date
- reusable template files in `templates/`
- `template` command for listing, previewing, and scaffolding templates
- `new "Note" --template name` with placeholder expansion for title, slug, and timestamps
- reusable `MinimalNotes` PowerShell module with a thin `note.ps1` CLI wrapper
- module manifest and smoke test for importing the public module entry points
- `dashboard` command for a compact multi-section vault overview
- `report` and `review` commands for recent activity summaries and structured check-ins
- `weekly` and `monthly` note workflows alongside the existing daily notes
- `related` note suggestions from links and shared tags
- `graph` command that prints Mermaid link graphs for one note or the whole vault
- `merge` command to combine notes and rewrite inbound links
- `split` command to extract a heading section into a new linked note
- `repair-links` command to repair unresolved links when there is a clear fuzzy match
- `props unset` command for removing frontmatter keys cleanly
- validation for structured frontmatter fields like `status`, `priority`, `due`, and `scheduled`
- `stale` command for listing notes untouched for at least N days
- read-only saved queries with `query save|list|show|run|delete`
- preview-only `dedupe` output for likely duplicate notes

### Changed

- roadmap and README examples updated to reflect the new agenda, task, and template workflows
- project structure now separates reusable logic from the CLI script
- README and roadmap updated to reflect dashboards, reviews, calendar notes, and graph tooling
- README and roadmap updated to reflect stale views, saved queries, and dedupe previews

## Since The Initial Commit

### Core note workflow

- markdown-based note creation and opening
- full-text literal search
- fuzzy note finding
- interactive note picker
- daily note creation
- quick capture to inbox and daily notes

### Linking and vault structure

- wiki link parsing
- backlinks
- unresolved-link detection
- create missing linked notes from unresolved links
- orphan note listing
- recent note listing
- safe note rename with automatic wiki-link updates

### Metadata and note intelligence

- frontmatter/property support
- aliases and tag support from frontmatter
- metadata-aware task collection from markdown checkboxes
- agenda from frontmatter dates
- reusable note templates with placeholder expansion
- dashboard, reporting, and review workflows
- daily, weekly, and monthly note workflows
- related-note suggestions and Mermaid graph output
- merge, split, and repair-link refactoring workflows
- stronger validated property workflows for frontmatter editing
- stale-note views, saved queries, and preview-only dedupe

### Quality and reliability

- automated Pester test suite
- modernized Pester 5 compatibility
- BOM-safe frontmatter detection
- clearer ambiguous-note resolution
- CI workflow for GitHub Actions
- `.gitattributes` for line-ending normalization
- module import smoke coverage
- broader workflow coverage for dashboard, report/review, calendar notes, and graph tooling
- regression coverage for merge, split, and link-repair commands
- regression coverage for props unset and validation rules
- regression coverage for stale, saved-query, and dedupe workflows

### Repository polish

- MIT license
- rewritten public-facing README
- published roadmap
- public GitHub repository setup and push
