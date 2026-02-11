# AGENTS.md — Operational Workflow (Codex-Focused)

⚠️ FOR PROJECT CONTEXT & ARCHITECTURE, READ `AI_CONTEXT.md` FIRST.

## Purpose
Operational mechanics for implementation sessions (commands, commit flow, safety rails).

## Core Operational Rules
- Prefer minimal, safe changes; avoid broad refactors unless requested.
- Ask before destructive actions or DB schema/version changes.
- Keep commit scope focused and testable.
- After commits, use wording:
  - `Kalau sudah siap, silakan jalankan git push secara manual di terminal.`

## Docs + Commit Workflow
- Impacted-docs-only: update only docs affected by the change.
- Shorthand:
  - `unc` = review/update impacted core docs first, then commit.
- Core docs to consider on `unc`:
  - `AGENTS.md`
  - `AI_CONTEXT.md`
  - `PROJECT_NOTES.md`
  - `spec.md`
  - `CHANGELOG.md`
  - `README.md`

## Git Workflow
- Use `codex/*` branches for feature experiments until stable.
- Merge to `main` after validation.
- Prefer clear commit prefixes: `feat:`, `fix:`, `chore:`, `docs:`.

## Build / Tooling Notes
- App icon source: `assets/icon_toko.png` (`flutter_launcher_icons`).
- Do not run `flutter_launcher_icons` or `flutter pub get` unless requested.

## Safety
- DB v8 is locked unless explicit migration approval exists.
- Backup/restore changes require rollback-safe behavior and validation.

## Handoff (Session End)
When ending session or context is low, provide:
1. Branch + latest commit + uncommitted status.
2. WIP and incomplete items.
3. Next 3–5 concrete actions.
4. Critical constraints (DB lock, SOP, known blockers).
