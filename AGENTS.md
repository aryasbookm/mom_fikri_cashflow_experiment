> **Tentang:** Aturan operasional AI eksekutor untuk menjaga konsistensi implementasi dan workflow repo.
> **Audiens:** AI coding agent dan developer yang menjalankan sesi implementasi.
> **Konteks:** Dibaca sebelum eksekusi perubahan, commit, dan handoff sesi.

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

## Communication Standards
- Use proactive heads-up labels before proceeding on risky or non-trivial work:
  - `[HEADS-UP: PLAN]` before implementing a complex/new feature; propose plan first.
  - `[HEADS-UP: TIMEBOX]` when debugging exceeds 3 focused loops or ~45 minutes; propose pivot/fallback.
  - `[HEADS-UP: QUALITY]` before milestone commit/merge; verify Happy Path + Edge Case + Rollback/Recovery.
  - `[HEADS-UP: DOCS]` when flow/architecture changes; list impacted docs only.
- When replying to quoted statements from another AI/tool, prefix source labels explicitly (`User said:`, `Gemini said:`, `Codex said:`) to avoid speaker ambiguity.
- Do not repeat setup instructions (OAuth/keystore) if `AI_CONTEXT.md` infrastructure status is already marked as `Registered`.

## Prompt Protocol (Default)
For non-trivial requests, structure instructions with:
- `Task`: tujuan akhir yang diminta.
- `Context`: file/fitur/status yang relevan.
- `Do`: hal yang wajib dikerjakan.
- `Avoid`: hal yang tidak boleh dilakukan.
- `Verify`: cara validasi hasil (command/test/checklist).

For cashflow/financial logic, `Verify` is mandatory and must include:
- minimal one numeric sanity check (expected balance/income/expense),
- one edge-case check (null/empty/cancel/offline as applicable),
- one rollback/recovery note if operation is destructive (restore/delete/overwrite).

## Docs + Commit Workflow
- Impacted-docs-only: update only docs affected by the change.
- If a new instruction is generic (cross-project), update global standard (`/Users/aryasaputra/Projects/_standards/AGENTS.template.md`) in the same session.
- Use Tiered Doc Sync (pragmatic, not full-scan by default):
  - Tier 1 (mandatory on non-trivial `unc`): `PROJECT_NOTES.md`, `spec.md`, `CHANGELOG.md`.
  - Tier 2 (contextual): `AI_CONTEXT.md`, `TESTING_*.md` when context/testing flow changes.
  - Tier 3 (milestone/release): `README.md`, `THESIS_REFERENCE.md`, `WORKFLOW.md`.
- For each checked doc, record status in handoff/summary:
  - `updated`, or
  - `checked, no update needed`.
- Full `.md` sweep is only required for pre-release, major handoff, or explicit user request.
- Project Capsule baseline (repo ini):
  - maintain `WORKFLOW.md` di root repo,
  - gunakan fixed dev port per project (saat ini `3010`),
  - gunakan browser profile dedicated untuk isolasi cookie/auth.
- Shorthand:
  - `unc` = review/update impacted core docs first, then commit.
  - `hld` = Hold / Answer Only: jawab/verifikasi saja; jangan jalankan tool, jangan edit file, jangan commit.
  - `sbp` = Search Best Practice: lakukan riset best-practice terlebih dahulu (sumber resmi/primer), lalu lanjutkan rekomendasi/eksekusi.
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

## Command Access & Blocker Policy
- Some commands can be blocked by environment policy (sandbox scope, network restriction, or OS privilege such as `sudo` with TTY password).
- Treat blocked commands as execution constraints, not feature failure.
- Mandatory fallback order when a command is blocked:
  1. Try a safe non-privileged alternative command/tool.
  2. If still blocked, ask user to run the required command manually.
  3. Continue execution using the command output/artifact provided by user.
- Never loop repeatedly on the same blocked command without changing approach.
- If user action is required, provide one exact command and explain expected output briefly.

## Runtime Bug Protocol (Mandatory)
- Evidence-first diagnosis: for runtime/file/restore bugs, capture and relay the concrete error (exception + path + operation stage) before concluding root cause.
- No single-platform assumption: do not label issue as platform-specific until at least one cross-platform check is attempted or user evidence confirms it.
- Two-failed-fixes pivot rule: if two consecutive fixes in the same bug area fail, stop incremental patching and pivot approach (e.g., path-based IO -> byte-based IO).
- End-to-end success criteria for restore/backup:
  - data restore success,
  - image/file restore count verified (or explicit warning),
  - UI outcome verified (no silent fallback/default state when assets should exist).

## Safety
- DB v8 is locked unless explicit migration approval exists.
- Backup/restore changes require rollback-safe behavior and validation.

## Handoff (Session End)
When ending session or context is low, provide:
1. Branch + latest commit + uncommitted status.
2. WIP and incomplete items.
3. Next 3–5 concrete actions.
4. Critical constraints (DB lock, SOP, known blockers).

## Appendix: Skripsi & Financial Safety Rules
- Precision standard: gunakan tipe data `int` untuk kalkulasi uang (satuan Rupiah), hindari `double` di logika bisnis.
- Data integrity: setiap transaksi harus memiliki `category_id` dan `timestamp` valid sebelum disimpan.
- Audit trail: hindari penghapusan data secara silent; tampilkan feedback UI atau log singkat saat aksi berhasil.
- UI safety: format `NumberFormat.currency` hanya di layer UI, bukan di provider/service kalkulasi.
