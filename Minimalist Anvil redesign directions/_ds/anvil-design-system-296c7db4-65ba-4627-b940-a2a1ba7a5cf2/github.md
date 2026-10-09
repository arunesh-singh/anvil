repo: arunesh-singh/anvil
branch: main

## Last sync
date: 2026-09-18T19:43:18Z

### Updated in this project
- Retokenised the whole design system to the app's current "Slab, resolved" theme — Space Grotesk + JetBrains Mono, accent #4D67FF, flat panels, six radii. Material 3 / Roboto is gone.
- Added the seven Slab widgets the system was missing: IconChip, ToolRow, SectionEyebrow, SegmentedControl, StepperField, InfoCard, ProgressRing.
- Rewrote the colour, type, shape, spacing, elevation and component cards, the readme foundations and the homepage thumbnail.
- New `explorations/pdf-workspace.html` — today's PDF editors vs. two single-workspace redesign directions.

## Screen map
| Project screen | Repo files |
| --- | --- |
| `ui_kits/anvil-app/ToolScreen.jsx` | `lib/ui/tool/generic_tool_screen.dart`, `lib/ui/tool/progress_view.dart` |
| `ui_kits/anvil-app/HomeScreen.jsx` | `lib/ui/home/home_screen.dart` |
| `ui_kits/anvil-app/ResultScreen.jsx` | `lib/ui/result/result_screen.dart` |
| `ui_kits/anvil-app/HistoryScreen.jsx` | `lib/ui/history/history_screen.dart` |
| `ui_kits/anvil-app/SettingsScreen.jsx` | `lib/ui/settings/settings_screen.dart` |
| `explorations/pdf-workspace.html` (current column) | `lib/ui/tool/editors/pdf_merge_editor_screen.dart`, `pdf_pages_editor_screen.dart`, `pdf_compress_screen.dart`, `editor_scaffold.dart` |
| `tokens/*.css`, `components/**` | `lib/ui/tokens.dart`, `lib/ui/theme.dart`, `lib/ui/widgets/slab.dart` |
