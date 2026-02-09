# AGENTS.md — Project Rules for Codex

## Purpose
This file defines working rules and expectations for AI agents collaborating on this project.

## Workflow Rules
- Prefer minimal, safe changes; avoid large refactors unless explicitly requested.
- Ask before running destructive commands or changing DB schema/versions.
- Keep UI changes consistent with existing design (maroon/cream theme).
- Use Provider-based state management (no new state libs unless asked).
 - Export PDF uses `printing`; keep macOS entitlements in sync if touched.

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
- Providers: `lib/providers/*`
- PDF: `lib/services/pdf_service.dart`
- Export Excel: `lib/services/export_service.dart`

## Build & Icons
- App icon is `assets/icon_toko.png` with `flutter_launcher_icons`.
- Do not run `flutter_launcher_icons` or `flutter pub get` unless requested.
