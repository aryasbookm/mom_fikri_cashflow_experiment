# AI_CONTEXT.md

> ⚠️ ALL AI AGENTS MUST READ THIS FILE BEFORE STARTING A SESSION.

Last updated: 2026-02-11  
Project: **Mom Fiqry Cashflow**

## 1) Purpose
Single Source of Truth for project context, role boundaries, and quality standards across all AI agents.

## 2) Role Boundary (Must Follow)
- **Gemini (mentor/architect):** review, critique, planning, and writing Codex-ready prompts.
- **Codex (coding agent):** edits files, runs commands/tests, commits, and reports concrete repo changes.
- **User (Aryasaputra):** final decision maker and approver.

Hard rules for mentor/reviewer AI:
- Do **not** claim you executed code or edited files.
- Do **not** rewrite project history; ask Codex/user to verify if unsure.
- Return implementation advice in **Codex-ready prompt** format when action is requested.

## 3) Current Project State
- Active branch: `main`
- Recent commits:
  - `be47fe9` chore: add bootstrap script and standardize agent workflow rules
  - `7456ee9` chore: hide dev-only backup simulation behind `kDebugMode`
  - `ed9d9c4` merge `codex/feat-cloud-backup` into `main`
- DB policy: **SQLite v8 locked** (no schema changes without migration approval).

## 3.1) Technical Context
- Language/runtime:
  - Dart SDK: `3.7.2`
  - Flutter SDK: local environment indicates `3.29.0` path usage (`/opt/homebrew/Caskroom/flutter/3.29.0/...`)
- State management: `provider`
- Local database: `sqflite` (DB schema/version locked at v8)
- Cloud stack (Android):
  - `google_sign_in`
  - `googleapis` (Drive v3)
  - `extension_google_sign_in_as_googleapis_auth`
  - Drive storage target: `appDataFolder`
- Other key packages: `file_picker`, `path_provider`, `share_plus`, `pdf`, `printing`, `fl_chart`, `shared_preferences`

## 3.2) Project Map (High-Level)
- Entry point: `lib/main.dart`
- Database: `lib/database/database_helper.dart`
- Providers: `lib/providers/*`
- Screens:
  - `lib/screens/owner_dashboard.dart`
  - `lib/screens/staff_dashboard.dart`
  - `lib/screens/add_transaction_screen.dart`
  - `lib/screens/history_screen.dart`
  - `lib/screens/account_screen.dart`
  - `lib/screens/report_screen.dart`
- Services:
  - `lib/services/backup_service.dart`
  - `lib/services/cloud_drive_service.dart`
  - `lib/services/export_service.dart`
  - `lib/services/pdf_service.dart`
- Shared widgets:
  - `lib/widgets/account_panel.dart`
  - `lib/widgets/owner_pin_dialog.dart`
- Core docs:
  - `AGENTS.md`, `PROJECT_NOTES.md`, `spec.md`, `CHANGELOG.md`, `README.md`

### 3.3) Project Structure Snapshot (Depth 2, condensed)
```
.
assets/
lib/
  database/
  models/
  providers/
  screens/
  services/
  utils/
  widgets/
```

## 4) Completed Cloud Scope (Android)
- Google Sign-In + Drive integration works on Android.
- Cloud backup uploads local DB (`mom_fikri_cashflow_v2.db`) to Drive `appDataFolder`.
- Filename format: `Backup_MomFiqry_YYYYMMDD_HHMMSS.db`.
- Cloud restore downloads latest backup, safely swaps local DB:
  - close DB → replace file → reopen DB → reload providers.
- Cloud restore supports file picker list from `appDataFolder` (select specific backup by id).
- Account UI shows local cloud metadata: "Terakhir Backup Cloud" (`last_cloud_backup_time`).
- UI:
  - owner sees cloud backup/restore actions.
  - `[DEV] Simulasi Lupa Backup (4 Hari)` only appears in debug mode (`kDebugMode`).

## 5) Known Limitation
- macOS Google Sign-In path can fail with keychain/signing environment issues (Personal Team context).
- This is treated as a platform/dev-environment limitation; Android flow is validated end-to-end.

## 6) Documentation Policy
- Use impacted-docs-only updates (avoid noisy doc edits for trivial refactors).
- Key docs:
  - `AGENTS.md`
  - `PROJECT_NOTES.md`
  - `spec.md`
  - `CHANGELOG.md`
  - `README.md`

## 6.1) Session Modes & Shorthand (Quick Reference)
- Purpose: provide fast, shared control signals for all agents in-session.
- Active shorthand:
  - `unc` = update impacted core docs first, then commit.
  - `hld` = hold mode (answer/verify only; no tool run, no file edits, no commit).
- Communication modes:
  - `hld` should be treated as a hard stop for execution actions.
  - Normal mode resumes when user gives explicit execution instruction.
- Source of operational detail: `AGENTS.md` (this section is summary only).

## 7) Working SOP
- Best practice is default (no need to wait for keyword).
- Timebox blockers: **3 attempts or 45–60 minutes max**.
- If blocked: declare blocker, propose fallback path, continue progress.
- Definition of Done per feature slice:
  - code complete
  - minimal validation on target platform
  - impacted docs updated
  - focused commit done

### 7.3) Best-Practice Enforcement (Mandatory)
- Mentor AI should proactively include a brief **Best-Practice Check** in recommendations for any non-trivial task.
- The check must include:
  1. chosen approach,
  2. safer/cleaner alternative (if any),
  3. key risk and mitigation.
- For platform-specific tasks, call out platform limits (Android/iOS/macOS) before proposing implementation.
- For integrations (auth/cloud/storage/backup/restore), include failure-path behavior by default.

## 7.2) Quality Gate / Mini Eval (Required Before Merge)
For each feature slice, require these 3 checks:
- **Happy Path:** normal user flow succeeds end-to-end.
- **Edge Case:** at least one failure-path is validated (e.g. cancel auth, null/missing data, offline request).
- **Rollback/Recovery:** verify safe recovery behavior (e.g. restore rollback, no partial/corrupt state after failure).

Output format expected from mentor AI:
- list test scenario
- expected outcome
- observed result
- pass/fail

## 7.1) Coding Preferences
- Favor composition and small, readable widgets over deep inheritance.
- Keep business logic in providers/services; keep screen widgets focused on UI orchestration.
- Avoid schema changes by default; if unavoidable, require migration plan approval first.
- Prefer minimal-risk, incremental changes over broad refactors.

## 8) Git Workflow
- Feature work should use `codex/*` branches until stable.
- Merge to `main` only after validation.
- Keep commits focused and descriptive (`feat:`, `fix:`, `chore:`, `docs:`).

## 9) Bootstrap for New Projects
- Use `./init_project.sh <project_name> [destination_dir]`.
- Script creates Flutter project and auto-copies `AGENTS.md` and `AI_CONTEXT.md` into new project root.

## 10) Preferred Response Style for Gemini
- Concise, practical, no over-claims.
- If giving implementation steps, provide:
  1. decision/tradeoff summary
  2. Codex-ready prompt
  3. validation checklist

## 11) Gemini Operational Constraints
- Treat repo state as source of truth; if not verified, explicitly mark as assumption.
- Never imply code/files/commits were executed by Gemini; execution belongs to Codex/user.
- Prefer recommendations that preserve momentum (fallbacks when blocked), not open-ended debugging loops.
- Keep changelog guidance concise; deep technical detail belongs in `PROJECT_NOTES.md`/`spec.md`.
- If uncertainty is high, ask for one concrete artifact (error log, `git status`, file snippet) before concluding.
