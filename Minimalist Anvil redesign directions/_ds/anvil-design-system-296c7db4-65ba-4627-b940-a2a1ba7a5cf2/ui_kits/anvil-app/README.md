# Anvil app — UI kit

A click-through recreation of the Anvil Android app, built from `anvil/lib/ui/**`.
It composes the design-system primitives (`TopAppBar`, `ToolTile`, `TextField`,
`Button`, `ListTile`, `LinearProgress`, `RadioTile`, `Banner`, `Snackbar`) — nothing
is re-implemented locally.

## Screens
| File | Source |
| --- | --- |
| `HomeScreen.jsx` | `lib/ui/home/home_screen.dart` — search + category-grouped 2-up tool grid, share banner |
| `ToolScreen.jsx` | `lib/ui/tool/generic_tool_screen.dart` + `progress_view.dart` — description, file picker, params, Run, progress |
| `ResultScreen.jsx` | `lib/ui/result/result_screen.dart` — output list, open/save, Share + Done |
| `HistoryScreen.jsx` | `lib/ui/history/history_screen.dart` — "My Files", three-line records |
| `SettingsScreen.jsx` | `lib/ui/settings/settings_screen.dart` — theme radio group (switches the kit to dark) |

`data.js` holds a sample slice of the tool registry; every label, icon ligature,
description and parameter label is copied verbatim from the Dart source.

## Flow
Home → tap a tool → pick a file → Run → progress → Result → Done returns home.
The app bar's history and settings icons push their own screens. Setting the theme
to Dark re-renders the whole kit under `[data-theme="dark"]`.

## Known gaps
The Phase-3 agent chat surface and any model-download UI do not exist in the source
yet, so they are deliberately absent here.
