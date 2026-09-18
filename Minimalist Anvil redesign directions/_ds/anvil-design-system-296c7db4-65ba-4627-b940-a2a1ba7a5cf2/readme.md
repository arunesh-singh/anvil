# Anvil Design System

Anvil is a Flutter mobile app (Android first, iOS later) that recreates roughly 85% of
TinyWow's 259-tool catalog **entirely on-device** — offline, private, zero per-use cost.
PDF, image, video/audio and file-conversion tools run locally today; ML tools
(background removal, OCR, upscale, ASR) and an on-device Gemma agent that drives the
tools by natural language land in later phases.

The product story is the design brief: *instant, offline, nothing leaves your phone*.
The interface is deliberately plain — a search field, a grid of tools, a screen per tool,
a result. There is no onboarding, no marketing surface, no illustration system. Anvil is
a workbench, not a destination.

## Sources this system was built from

| Source | Path / link | What was taken from it |
| --- | --- | --- |
| Anvil codebase (Flutter/Dart) | mounted local folder `anvil/` | Every value in this system. Theme seed, screens, widget inventory, tool labels, icon ligatures, copy. |
| `anvil/lib/ui/theme.dart` | — | The single brand seed `#3D5AFE`; `ThemeData(useMaterial3: true)` |
| `anvil/lib/ui/**` | `home_screen.dart`, `generic_tool_screen.dart`, `progress_view.dart`, `result_screen.dart`, `history_screen.dart`, `settings_screen.dart` | Screen layouts, spacing, component inventory |
| `anvil/lib/tools/**/*.dart` | `pdf_tools.dart`, `image_native_tools.dart`, `video_tools.dart`, `converter_tools.dart`, `write_tools.dart` | Tool labels, descriptions, parameter labels, Material Icons ligature names |
| `anvil/README.md`, `ARCHITECTURE.md`, `DECISIONS.md`, `TOOL_CATALOG.md` | — | Product context and voice |
| TinyWow | https://tinywow.com | Named in the source as the catalog Anvil ports. Not a visual reference. |

No Figma file, no slide deck, no brand book, and **no logo** was provided. See
*Brand mark* below.

---

## VISUAL FOUNDATIONS

Anvil's visual language is **Material 3 (Material You), unmodified**, generated from one
seed colour. `theme.dart` is fourteen lines: `ColorScheme.fromSeed(seedColor: 0xFF3D5AFE)`
for light and dark. Everything here is the honest expansion of that — not an
interpretation of it. When a value looks like "just Material," that is correct and
intentional; do not stylise it.

**Colour.** One seed, `#3D5AFE` — a saturated electric indigo. All roles derive from it
via `material-color-utilities` tonal palettes (primary tones use the seed's own chroma;
secondary chroma 16, tertiary chroma 24 at hue +60, neutrals chroma 4/8). Light primary
lands at `#2848EE` (tone 40), dark primary at `#BBC3FF` (tone 80). Secondary is a muted
blue-grey, tertiary a dusty mauve-pink — both are container colours, never actions.
Error `#BA1A1A` is the only status colour in the system: there is **no success green, no
warning amber**, because a finished job navigates to a Result screen instead of turning
something green. Backgrounds are near-white with the faintest violet cast
(`#FFFBFF` surface, `#F6F2F7`–`#E4E1E6` containers) — never pure `#FFF` for a raised
surface, never a grey with a cool blue cast.

**Type.** Roboto at every size — the Flutter/Android default; there is no display or
brand face. The full M3 2021 type scale is tokenised, but the app itself only uses five
steps: title-large (22) for app bars, title-medium (16/500) for tool tiles, title-small
(14/500) for category headers, body-large (16) for descriptions and field text,
body-medium (14) for subtitles and metadata, label-large (14/500) for buttons. Tracking
is positive on body sizes (0.25–0.5px) and negative only on display-large. Roboto Mono
is reserved for filenames, page specs and tool output.

**Spacing & layout.** A 4px base, but only five values do real work: 4, 8, 12, 16, 24.
`16px` is screen padding, `12px` is list/tile padding, `8px` is the grid gutter.
The home grid is fixed at two columns with a `2.4:1` tile aspect ratio — never one column,
never three. Layout is a single scrolling column under a fixed 64px app bar; there is no
bottom navigation, no drawer, no tab bar, no floating action button, no sticky footer.
The primary action (`Run`, `Share`) sits at the bottom of the content column, full-width.

**Corners.** Fields 4px, cards and tiles 12px, bottom sheets 28px, buttons and chips
fully rounded. Nothing is square except the app bar and full-bleed dividers.

**Cards.** A card is a *tinted surface plus a shadow pair*, never a border. Level 1 is
`--md-surface-container-low` with `0 1px 2px rgba(0,0,0,.3), 0 1px 3px 1px rgba(0,0,0,.15)`,
12px radius, contents clipped to the corner. Elevation moves the tint and the shadow
together. There are no outlined cards, no coloured left rails, no gradient fills.

**Backgrounds & imagery.** There are none. No photography, no illustration, no pattern,
no texture, no gradient, no grain. Every surface is a flat colour token. When a screen
has nothing to show it says so in plain body text, centred — "No tools match.",
"No history yet." — with no empty-state artwork. If you need an image in a marketing
context, that decision has not been made yet; ask before inventing one.

**Transparency & blur.** Used only for state layers and disabled states. There is no
frosted glass, no scrim over content except the standard modal scrim (`#000000`), and no
protection gradients — text always sits on a solid token.

**Borders.** A 1px `--md-outline` on text fields (2px `--md-primary` on focus) and a 1px
`--md-outline-variant` hairline under banners. That is the whole border system.

**Motion.** Material defaults, nothing bespoke. Standard easing `cubic-bezier(0.2,0,0,1)`;
durations 100/200/300/500ms. Ripples on every tap target. Screen changes are the platform
`MaterialPageRoute` push. **No bounces, no springs, no parallax, no scroll-linked
animation, no entrance choreography.**

**Interaction states.** State layers only — a translucent wash of the *content* colour at
the M3 opacities: hover 8%, focus 10%, pressed 10%, dragged 16%. A pressed button never
shrinks, never darkens to a different hex, never changes hue. Disabled is 38% content on
a 12% container, never a grey swatch.

---

## CONTENT FUNDAMENTALS

The copy in `anvil/` is terse, functional and unbranded. Match it.

**Voice.** Second person, implied. Instructions are imperative — "Pick a tool",
"Enter a password.", "Add between 1 and 100 pages." Anvil never says *I*, rarely says
*you*, and never *we*. It does not have a personality; it reports.

**Casing.** Tool labels are **Title Case** with formats upper-cased: `CSV to JSON`,
`Merge PDFs`, `MP4 to GIF`, `Website to PDF`. Screen titles are Title Case (`My Files`,
`Settings`, `Result`). Everything else — descriptions, field labels, errors, progress,
buttons — is **sentence case**. Buttons are single words where possible: `Run`, `Share`,
`Done`, `Cancel`, `Dismiss`, `Save`.

**Descriptions** are one sentence, present tense, ending in a period, leading with the
verb: *"Combine several PDF files into one document."* · *"Shrink a PDF by optimizing its
images."* · *"Extract a video's audio track as an MP3."* Never a sales adjective, never
"easily", never "with just one tap".

**Field labels** carry their unit in parentheses: `Image quality (1-100)`,
`Width (px)`, `Start (seconds)`, `Pages to delete (e.g. 2,4-6)`, `Color (hex, e.g. #FF0000)`.
Examples go inside the parentheses, never in helper text below.

**Errors** state the fix, not the fault: *"Enter a password."* · *"Cannot delete every page
of the PDF."* · *"No selectable text found — this PDF may be scanned images."* ·
*"Invalid page '7' — the PDF has 4 pages."* They are sentence case, end in a period, and
use an em dash to append the reason.

**Progress messages** are gerunds with an ellipsis character (`…`, never three dots):
`Reading PDF…`, `Converting…`, `Splitting…`, `Saving…`, `Working…`, `Counting…`.

**Empty states** are four words or fewer: `No tools match.` · `No history yet.`

**Numbers and units** are unspaced and lowercase where technical: `36pt`, `480px`,
`AES-256`, `1pt = 1/72"`.

**Emoji: never.** Not in labels, not in copy, not in docs. No exclamation marks. No
sentence fragments used as headings. Product-facing prose in the repo (README, ARCHITECTURE)
is allowed to be blunter and more technical than in-app copy — that register belongs in
docs, not in the UI.

---

## ICONOGRAPHY

**Material Icons, filled, 24px** — the set Flutter bundles via
`uses-material-design: true` in `pubspec.yaml`. Every tool in the registry names one by
its `IconData` constant (`Icons.data_object`, `Icons.call_split`, `Icons.branding_watermark`),
and every one of those maps 1:1 to a ligature in the web `Material Icons` font.

- **Delivery:** the Material Icons webfont is loaded from Google Fonts in
  `tokens/fonts.css`. This is the same glyph set the app ships, not a substitute.
  Use the `Icon` component with the exact ligature name — `<Icon name="call_split" />`.
- **No SVG sprite, no PNG icons, no icon components** exist in the codebase; there is
  nothing to copy into `assets/`, and `assets/` is therefore empty by design.
- **Size:** 24px everywhere — app-bar actions, tool tiles, list-tile leading slots,
  banner leading. 18px inside a button label. Never larger than 32px.
- **Colour:** `--md-on-surface-variant` by default. Icons inside a filled button inherit
  the button's `on-` colour. Only destructive affordances use `--md-error`.
- **Filled set only.** The base `Material Icons` webfont carries no `_outlined`, `_rounded`
  or `_sharp` variants — those Dart constants render as literal text if passed straight
  through. Map them to the filled ligature: `Icons.circle_outlined` → `panorama_fish_eye`,
  `Icons.insert_drive_file_outlined` → `insert_drive_file`.
- **Emoji and unicode symbols are never used as icons.** Neither are hand-drawn SVGs. If a
  concept has no Material Icons glyph, pick the nearest one the Dart source already uses
  rather than drawing something.
- **Cupertino Icons** is a dependency but unused in the current UI; ignore it unless the
  iOS build lands.

### Brand mark

**Anvil has no logo.** The sources contain no wordmark, app icon, or brand illustration —
`AppBar(title: Text('Anvil'))` is the entire brand expression, and the app still runs the
default Flutter launcher icon. Wherever a mark would go, set the word **Anvil** in Roboto
Medium, tight tracking, in `--md-on-surface` or white on `--anvil-seed`. Nothing in this
system attempts to reconstruct or invent a mark. If a real logo exists, drop it into
`assets/` and replace the wordmark card.

---

## Index

### Root
- `styles.css` — the single entry point consumers link. `@import` lines only.
- `thumbnail.html` — homepage tile.
- `SKILL.md` — Agent Skills front matter for use in Claude Code.
- `readme.md` — this file.

### `tokens/`
`fonts.css` (Roboto, Roboto Mono, Material Icons) · `colors.css` (six tonal palettes,
light + dark semantic roles) · `typography.css` (M3 type scale) · `shape.css` ·
`elevation.css` · `spacing.css` · `motion.css` · `state.css`

### Components — `components/`
Every family below is one the Anvil source actually uses; nothing was added for
completeness.

| Group | Components |
| --- | --- |
| `components/actions/` | **Button**, **IconButton** |
| `components/inputs/` | **TextField**, **RadioTile** |
| `components/surfaces/` | **Card**, **ListTile**, **ToolTile** |
| `components/feedback/` | **LinearProgress**, **CircularProgress**, **Banner**, **Snackbar** |
| `components/navigation/` | **TopAppBar** |
| `components/icons/` | **Icon** |

**Intentional additions (2).**
- **Icon** — a thin wrapper over the Material Icons ligature font. The codebase uses
  Flutter's built-in `Icon(IconData)`, which has no web equivalent; consumers need one.
- **ToolTile** — the home grid's tile is a private `_ToolTile` widget in
  `home_screen.dart`. It is promoted to a named component because it is the app's most
  repeated unit.

Deliberately **not** built, because the source has no counterpart: Avatar, Tabs, Chip,
Dialog, Tooltip, Switch, Slider, Toast queue, bottom navigation, FAB.

### UI kits — `ui_kits/`
- `ui_kits/anvil-app/` — click-through recreation of the Android app: Home, Tool + progress,
  Result, My Files (history), Settings. See its `README.md` for the screen→source map.

### Templates — `templates/`
- `templates/anvil-screen/` — a blank Anvil screen (app bar + content column + primary
  action) to start a new mock from.

### Guidelines — `guidelines/`
Twenty specimen cards backing the Design System tab: colour (seed, tonal palettes,
surfaces, semantics, dark), type (display/headline/title/body/label/mono), spacing,
shape, elevation, motion, state layers, wordmark, iconography.

### `assets/`
Empty. No logo, imagery, illustration or icon binaries exist in the sources; fonts and
icons are served from Google Fonts. Do not populate it with generated artwork.
