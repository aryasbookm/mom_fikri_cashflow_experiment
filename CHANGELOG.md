# Changelog

All notable changes to this project will be documented in this file.

## [1.0.0] - 2026-02-10
### Added
- Top Products (7 hari) di dashboard owner.
- Sistem backup & restore database dengan rollback serta validasi versi/struktur.
- PIN guard untuk tab Akun (session 5 menit) dengan PIN panjang variabel.

### Changed
- UI menu Akun dirombak menjadi grouped sections berbasis ListTile.

### Fixed
- File picker Android dibuat lebih stabil dengan `FileType.any` + validasi manual `.db`.
