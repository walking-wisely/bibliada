# Project Documentation Index

This file is auto-maintained by the codelore `document-feature` and
`migrate-project-docs` skills. Do not hand-edit — re-run the appropriate skill instead.

| Name | Description | File |
|------|-------------|------|
| desktop-overlay | How the desktop overlay works — a borderless NSPanel at desktop window level that supports arbitrary sizes, drag/resize with persistence, exact timer refresh, all-Spaces presence, and fading out during Mission Control. Covers the window flags and the frame-fighting gotcha. | [desktop-overlay.md](desktop-overlay.md) |
| overview | What Bibliada is and does — a menu-bar macOS app that shows a random public-domain Bible verse on a customizable gradient card, in two display modes (exact-timing desktop overlay, best-effort WidgetKit widget). Start here. | [overview.md](overview.md) |
| settings | Every user-facing setting across the four Settings tabs (Appearance, Size & Position, Updates, General), plus the input UX rules — commit-on-Return numeric fields, paired hour/minute clamping, Form row layout constraints — and how settings are persisted and migrated. | [settings.md](settings.md) |
| verse-source | Where verses come from — a bundled 178-verse curated catalog of World English Bible text plus live fetches from bible-api.com, with offline fallback and a cross-process last-verse cache. | [verse-source.md](verse-source.md) |
| widget | How the WidgetKit widget works — its per-instance AppIntent configuration (theme, frequency, show-reference), the multi-entry timeline, why its refresh cadence is only best-effort, and the App Group signing requirement that gates app-to-widget settings sharing. | [widget.md](widget.md) |
