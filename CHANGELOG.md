# Changelog

All notable changes to this project are documented here.

## Unreleased

### Added

- `agenda` command with `today`, `overdue`, and `all` views based on frontmatter fields like `scheduled`, `due`, `status`, and `priority`
- metadata-aware agenda tests covering active, today, and overdue cases
- metadata-aware `tasks` views with `today` and `overdue` filters driven by note frontmatter
- task output now includes note context like project, status, priority, scheduled date, and due date

### Changed

- roadmap and README examples updated to reflect the new agenda and task workflows

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

### Quality and reliability

- automated Pester test suite
- modernized Pester 5 compatibility
- BOM-safe frontmatter detection
- clearer ambiguous-note resolution
- CI workflow for GitHub Actions
- `.gitattributes` for line-ending normalization

### Repository polish

- MIT license
- rewritten public-facing README
- published roadmap
- public GitHub repository setup and push
