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
- Before each commit, update `AGENTS.md`, `PROJECT_NOTES.md`, and `spec.md` to reflect the latest progress and keep them in sync.
- Dashboard experiments should happen on a `codex/` feature branch until approved.
- Shorthand: `unc` = Update `AGENTS.md`, `PROJECT_NOTES.md`, `spec.md` and then Commit.
- Release notes live in `CHANGELOG.md`.

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
