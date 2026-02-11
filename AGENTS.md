# AGENTS.md — Project Rules for Codex

## Purpose
This file defines working rules and expectations for AI agents collaborating on this project.

## Workflow Rules
- Prefer minimal, safe changes; avoid large refactors unless explicitly requested.
- Ask before running destructive commands or changing DB schema/versions.
- Keep UI changes consistent with existing design (maroon/cream theme).
- Account screen uses grouped sections (ListTile-style) instead of flat buttons.
- Use Provider-based state management (no new state libs unless asked).
- Export PDF uses `printing`; keep macOS entitlements in sync if touched.
- When changing transaction timestamps, update filters and exports consistently.
- Backup/restore changes must be tested against rollback + schema/structure validation.
- Android file picker uses `FileType.any`; validate `.db` manually in app logic.
- Before each commit, review `AGENTS.md`, `PROJECT_NOTES.md`, `spec.md`, `CHANGELOG.md`, and `README.md` and update only the files impacted by the change (avoid noisy doc-only edits for trivial refactors/typos).
- Dashboard experiments should happen on a `codex/` feature branch until approved.
- Shorthand: `unc` = Update docs first (`AGENTS.md`, `PROJECT_NOTES.md`, `spec.md`, `CHANGELOG.md`, `README.md` as needed) **then** commit. Jadi cukup bilang “jalankan `unc`” tanpa menambahkan “update docs +” lagi.
- Release notes live in `CHANGELOG.md` (timeline v0.9.0 → v1.0.0-rc3).
- Default engineering mode:
  - Apply best-practice defaults automatically for UX, reliability, security, and data safety (no need to wait for user to type "best practice").
  - For high-risk or uncertain decisions, verify against official/primary references first.
- Blocker handling (timebox):
  - Timebox platform-specific blockers to max 45–60 minutes or 3 focused attempts.
  - If still blocked, declare blocker clearly, propose lowest-risk alternative path, and continue progress (do not stall the sprint).
  - Record unresolved platform issues as known limitations with context and workaround.
- Definition of Done per feature slice:
  - Code implemented.
  - Minimal validation/testing completed on target platform.
  - Relevant docs synced (only impacted docs).
  - Commit completed with focused message.
- Commit practice:
  - Commit after each coherent, testable change or feature slice.
  - Commit before switching to a different task/feature.
  - Use descriptive messages (`feat:`, `fix:`, `docs:`) and keep commits focused (avoid mixing unrelated changes).
- After commits, say: "Kalau sudah siap, silakan jalankan `git push` secara manual di terminal."

## Code Guidelines
- Keep files in ASCII unless necessary.
- Keep widgets small and reusable; avoid deeply nested widgets.
- Favor readability over cleverness.

## Database & Data Safety
- DB schema changes must be discussed and confirmed (risk of data reset).
- For stock logic: production adds stock, sales reduce stock, waste reduces stock.
- Deleting income transactions must restore stock.
- Staff deletes require audit reason; audit log supports restore/delete.

## Key Files
- Dashboard: `lib/screens/owner_dashboard.dart`
- Kasir/Transaksi: `lib/screens/add_transaction_screen.dart`
- Produksi/Stok: `lib/screens/production_screen.dart`
- Laporan: `lib/screens/report_screen.dart`
- Riwayat/Audit: `lib/screens/history_screen.dart`
- Struk Digital: `lib/screens/transaction_detail_screen.dart`
- Backup/Restore: `lib/services/backup_service.dart`
- Providers: `lib/providers/*`
- PDF: `lib/services/pdf_service.dart`
- Export Excel: `lib/services/export_service.dart`

## Build & Icons
- App icon is `assets/icon_toko.png` with `flutter_launcher_icons`.
- Do not run `flutter_launcher_icons` or `flutter pub get` unless requested.

## Commit Best Practices
- Commit after each coherent, testable change or feature slice.
- Commit before switching to a different task/feature.
- Use descriptive messages (`feat:`, `fix:`, `docs:`) and keep commits focused (avoid mixing unrelated changes).
- After commits, say: "Kalau sudah siap, silakan jalankan `git push` secara manual di terminal."

## Handoff Protocol
When tokens run low or the session ends, create a handoff prompt that includes:
1. **Context Snapshot:** current branch, last commit, uncommitted changes (if any).
2. **Work in Progress:** what is being worked on and what is incomplete.
3. **Next Action Items:** 3–5 concrete next steps for the new session.
4. **Critical Context:** sensitive constraints (e.g., DB version, schema rules, doc rules).
