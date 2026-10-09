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
| `lib/ui/tokens.dart`, `theme.dart`, `widgets/slab.dart` | github.com/arunesh-singh/anvil | The "Slab, resolved" palette, type scale, radii and widget inventory |
| `anvil/lib/ui/**` | `home_screen.dart`, `generic_tool_screen.dart`, `progress_view.dart`, `result_screen.dart`, `history_screen.dart`, `settings_screen.dart` | Screen layouts, spacing, component inventory |
| `anvil/lib/tools/**/*.dart` | `pdf_tools.dart`, `image_native_tools.dart`, `video_tools.dart`, `converter_tools.dart`, `write_tools.dart` | Tool labels, descriptions, parameter labels, Material Icons ligature names |
| `anvil/README.md`, `ARCHITECTURE.md`, `DECISIONS.md`, `TOOL_CATALOG.md` | — | Product context and voice |
| TinyWow | https://tinywow.com | Named in the source as the catalog Anvil ports. Not a visual reference. |

No Figma file, no slide deck, no brand book, and **no logo** was provided. See
*Brand mark* below.

---

## VISUAL FOUNDATIONS

Anvil's visual language is **"Slab, resolved"** — the app's own look, defined in
`lib/ui/tokens.dart`, `theme.dart` and `widgets/slab.dart`. It replaced the stock
Material 3 / Roboto theme the app shipped in its first phase: Material is still the
substrate (ripples, `MaterialPageRoute`, Material Icons), but every colour, radius and
type step is now hand-picked. Flat, rounded, quiet, with exactly one saturated colour.

**Colour.** Fifteen roles, light and dark, hand-picked rather than generated from a seed.
The accent is `#4D67FF` and does not shift between schemes; only its text variant
lightens (`#3346D6` light → `#8FA0FF` dark) to stay legible on containers. The page is
grey (`#F3F3F6`) and panels are white (`#FFFFFF`) — the inverse of the old
near-white-page scheme, and in dark `#16171A` page / `#1F2126` panel. Neutrals are
cool but untinted: no violet cast anywhere. Text has four levels —
on-surface `#1A1B1E`, muted `#565A61`, hint `#83888F`, faint `#A8ACB3`. Error
`#BA1A1A` is still the only status colour: **no success green, no warning amber**,
because a finished job navigates to a Result screen.

**Type.** **Space Grotesk** for everything, **JetBrains Mono** for filenames, sizes,
page specs and tool output — both bundled with the app. Eight steps do all the work:
headline-medium (30/700) for tool titles and the progress percentage, headline-small (25),
title-large (21/700) for editor headers, title-medium (18/600), title-small (15/600) for
rows, panels and buttons, body-large (15) for descriptions, body-medium (13) for
metadata, label-small (11/600, +1 tracking, uppercase) for section eyebrows — the only
uppercase type in the system. Tracking is **negative** and tightens as size grows
(-0.1 at 15px, -1.0 at 30px). Roboto is gone.

**Spacing & layout.** 20px screen gutter, 16px panel padding, 14px default stack gap,
10px thumbnail-grid gutter, 8px between adjacent controls. Controls are 44px, fields and
segments 48px, the one primary action per screen is **60px, full-width, at the foot of
the column**. Layout is a single scrolling column; no bottom navigation, no drawer, no
tab bar, no FAB.

**Corners.** Six radii, all generous, nothing square and nothing a pill: chip 12,
control and icon chip 14, search field 16, row 18, action button 20, panel 22.

**Panels.** A panel is a *flat tinted container* — no border, no shadow. Level 1 is
`--anvil-container` at 22px; a raised element (stepper button, snackbar, disabled
action) moves to `--anvil-container-high`. **There are no shadows anywhere in the app**;
`--elevation-1…5` resolve to `none`.

**Backgrounds & imagery.** There are none. No photography, no illustration, no pattern,
no texture, no gradient, no grain. Every surface is a flat colour token. Empty states are
plain body text, centred — "No tools match.", "No history yet." — with no artwork.

**Transparency & blur.** Used only for state layers, disabled states and the modal scrim
behind the full-page zoom viewer. No frosted glass, no protection gradients.

**Borders.** Effectively none. A focused field draws a 2px `--anvil-accent` inset ring;
a page marked for deletion draws a 2px `--anvil-error` outline. Nothing else is stroked.

**Motion.** Material defaults, nothing bespoke. Standard easing `cubic-bezier(0.2,0,0,1)`;
durations 100/200/300/500ms. Ripples on every tap target. Screen changes are the platform
`MaterialPageRoute` push. **No bounces, no springs, no parallax, no entrance choreography.**

**Interaction states.** State layers only — a translucent wash of the *content* colour at
hover 8%, focus 10%, pressed 10%, dragged 16%. A pressed button never shrinks, never
changes hue. Disabled is `--anvil-hint` content on a `--anvil-container-high` container.

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
- **Colour:** `--anvil-icon-strong` by default, `--anvil-muted` for subtitles. Icons inside a filled button inherit the button's `on-` colour; inside an icon chip, `--anvil-accent-text`. Only destructive affordances use `--md-error`.
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
default Flutter launcher icon. Wherever a mark would go, set the word **Anvil** in Space Grotesk
Bold, tight tracking, in `--anvil-on-surface` or white on `--anvil-accent`. Nothing in this
system attempts to reconstruct or invent a mark. If a real logo exists, drop it into
`assets/` and replace the wordmark card.

---

## Index

### Root
- `styles.css` — the single entry point consumers link. `@import` lines only.
- `thumbnail.html` — homepage tile.
- `SKILL.md` — Agent Skills front matter for use in Claude Code.
- `github.md` — the source repository this system tracks.
- `readme.md` — this file.

### `tokens/`
`fonts.css` (Space Grotesk, JetBrains Mono, Material Icons) · `colors.css` (fifteen
`--anvil-*` roles light + dark, plus `--md-*` aliases for Material-shaped consumers) ·
`typography.css` · `shape.css` · `elevation.css` (all `none`) · `spacing.css` ·
`motion.css` · `state.css`

### Components — `components/`

| Group | Components |
| --- | --- |
| `components/actions/` | **Button**, **IconButton**, **IconChip** |
| `components/inputs/` | **TextField**, **SegmentedControl**, **StepperField**, **RadioTile** |
| `components/surfaces/` | **Card**, **ToolRow**, **ToolTile**, **ListTile**, **SectionEyebrow** |
| `components/feedback/` | **ProgressRing**, **LinearProgress**, **CircularProgress**, **InfoCard**, **Banner**, **Snackbar** |
| `components/navigation/` | **TopAppBar** |
| `components/icons/` | **Icon** |

Every one is a widget the Slab source actually uses: **IconChip**, **ToolRow**,
**SectionEyebrow**, **StepperField**, **InfoCard** and **ProgressRing** are the web
equivalents of `slab.dart`'s `IconChip`, `ToolRow`, `SectionEyebrow`, `StepperField`,
`InfoCard` and `CircularPercent`; **SegmentedControl** is the method switch in
`pdf_compress_screen.dart`; **Icon** wraps the Material Icons ligature font, which has no
web equivalent in Flutter's `Icon(IconData)`.

Deliberately **not** built, because the source has no counterpart: Avatar, Tabs, Chip,
Dialog, Tooltip, Switch, Slider, Toast queue, bottom navigation, FAB.

### UI kits — `ui_kits/`
- `ui_kits/anvil-app/` — click-through recreation of the Android app: Home, Tool + progress,
  Result, My Files (history), Settings. See its `README.md` for the screen→source map.

### Explorations — `explorations/`
- `explorations/pdf-workspace.html` — current PDF editors vs. two redesign directions.

### Templates — `templates/`
- `templates/anvil-screen/` — a blank Anvil screen (app bar + content column + primary
  action) to start a new mock from.

### Guidelines — `guidelines/`
Twenty specimen cards backing the Design System tab: colour (accent, neutral ramp, text,
surfaces, roles in use, dark), type (display/headline/title/body/label/mono), spacing,
shape, elevation, motion, state layers, wordmark, iconography.

### `assets/`
Empty. No logo, imagery, illustration or icon binaries exist in the sources; fonts and
icons are served from Google Fonts. Do not populate it with generated artwork.
