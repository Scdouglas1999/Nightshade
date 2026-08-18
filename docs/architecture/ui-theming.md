# UI Theming — Architecture Guide

Nightshade’s design system lives in `packages/nightshade_ui`. Widgets resolve colors at runtime from the active `ThemeData`; do not pass palette objects down the tree unless a parent already holds them for layout reasons (e.g. settings scaffolding).

## Layer stack (bottom → top)

| Layer | Location | Role |
|-------|----------|------|
| **Colors** | `nightshade_colors.dart` | Semantic palette (`NightshadeColors`) registered as a `ThemeExtension` |
| **Tokens** | `nightshade_tokens.dart` | Spacing, radii, motion, shadows, opacity |
| **Typography** | `nightshade_typography.dart` | Type scale derived from active colors |
| **Theme** | `nightshade_theme.dart` | Assembles `ThemeData` + `ColorScheme` from colors |
| **Decorations** | `nightshade_decorations.dart` | Reusable `BoxDecoration` helpers |
| **Components** | `lib/src/components/` | Buttons, switches, cards, inputs, etc. |
| **Domain *Colors** | e.g. `nightshade_chart_colors.dart`, `annotation_type_colors.dart` | Fixed hues or theme-derived colors for charts, annotations, protocol badges |

Barrel export: `nightshade_theme_system.dart`.

## Resolving colors in widgets

**Rule:** use `NightshadeColors.of(context)` (or `context.nightshadeColors`) — not prop-drilling.

```dart
final colors = NightshadeColors.of(context);
// or
final colors = context.nightshadeColors;
```

`NightshadeTheme` registers `NightshadeColors` on `ThemeData.extensions`. Presets: `NightshadeColors.dark`, `.light`, `.redNight`, plus `darkWithAccent` / `lightWithAccent` for custom accent colors.

Do **not** import static presets inside leaf widgets unless building a theme variant. Do **not** thread `NightshadeColors colors` through every constructor when `BuildContext` is available.

## Switch components — when to use which

| Widget | Package | Use when |
|--------|---------|----------|
| **`NightshadeSwitch`** | `nightshade_ui` | Bare toggle only — table cell, toolbar, compact inline control |
| **`NightshadeSwitchRow`** | `nightshade_ui` | Label (+ optional subtitle/tooltip) + switch; imaging panels or simple forms **without** a leading icon |
| **`SettingsSwitch`** | `nightshade_app` | Settings persistence: wraps `NightshadeSwitch` with 300 ms debounced `onChanged` so rapid toggles coalesce before DB writes |
| **`SettingRow`** | `nightshade_app` | Full settings row: leading icon, title, subtitle, trailing control (compose with `SettingsSwitch`, `SettingsDropdown`, etc.) |

Prefer `NightshadeSwitch` over Material `Switch`. Theme `SwitchThemeData` exists only as a fallback via `NightshadeSwitchStyle.switchThemeData`.

## Domain color classes vs core palette

Add to **`NightshadeColors`** when the color is **semantic and theme-wide** — surfaces, borders, status (success/warning/error), primary/accent, text roles.

Add a **domain `*Colors` class** when:

- The hue is **fixed by domain meaning** (e.g. galaxy vs nebula annotation types, chart series indices)
- Multiple unrelated features share the same specialized palette (PSF heatmap gradients, backend protocol badges)
- The color **derives from** `NightshadeColors` for interactive states but is not a general UI token (`AnnotationStatusColors`, `NightshadeChartColors.selectedFrame`)

Keep domain classes in `packages/nightshade_ui/lib/src/theme/` and export from `nightshade_theme_system.dart`.

## Red night vision mode

`NightshadeColors.redNight` sets `useDarkOnPrimary: true` so switch thumbs and primary buttons use `background` (dark red-black) instead of white — white on red would ruin dark adaptation. Dark and light themes use white `onPrimary`.

**Platform dialogs are outside the theme, and this is a stated limitation.** Every window Nightshade paints itself is red under red night — measured on the Darkroom flow, where sampling the whole window with the image viewport masked out found zero chrome pixels outside hue 335°–25°. A window the *platform* paints is not: `file_selector` on Linux hands off to the GTK file chooser, and the chooser that opens behind `Import .nsrecipe` renders blue-grey with light text (≈24% of its sampled pixels at hue ≈225°, measured on this build). Nothing in `nightshade_ui` can retint it — it is not a Flutter surface. So red night preserves dark adaptation across the app's own surfaces, and a file chooser is a bright interruption of it. Replacing that hand-off with an in-app path picker for the flows that use it is an owner decision, not something this document claims is done.

**Image data is exempt, by design.** Chrome takes the theme; pixels do not. The Darkroom viewport, image previews, thumbnails and every other surface that paints *captured data* render their true colours under every theme, red night included — retinting them would falsify the very pixels the operator is judging, and a colour cast the theme invented is indistinguishable from one the stack introduced. Everything drawn *around* the image — labels, overlay strokes, histograms, controls — is chrome and takes the theme as usual. The one thing an app-drawn glyph must never be is a colour emoji: the platform's emoji font paints those, no theme can retint them, and a literal `🔭` in the status bar was the only non-red cluster in a red-night window. Use a `NightshadeIcons` glyph with a theme colour instead. An emoji the *operator* typed (a profile badge, a note) is their data and is printed as typed.

## Visual QA

Use **`NightshadeDesignSystemGallery`** (`lib/src/widgets/design_system_gallery.dart`) to preview tokens and components across themes. Widget tests in `packages/nightshade_ui/test/design_system_gallery_test.dart` pump the gallery in dark, light, and red night themes.

## Theme selection (app layer)

Desktop **`NightshadeApp`** reads persisted theme from `appSettingsProvider` (`settings.theme`: `dark`, `light`, `redNight`) and optional accent color. See comments on providers in `nightshade_theme.dart`.
