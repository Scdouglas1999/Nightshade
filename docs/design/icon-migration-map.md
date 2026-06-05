# Screen icon-migration map (Material `Icons.*` → `NightshadeIcons` / Lucide)

This is the canonical "Material icon → semantic icon" mapping for the
per-directory migration of `packages/nightshade_app/lib/screens` onto the
`nightshade_ui` design system. Lucide is the **go-forward** icon family (the
node-palette and most screens already use `LucideIcons.*`); the remaining
Material `Icons.*` call sites are the gap this pass closes.

**Prefer the semantic role** (`NightshadeIcons.<role>`) — it names *intent*, not
a glyph, so a later design change re-points every adopting site at once. Where no
role is a clean fit, a bare `LucideIcons.<glyph>` is given. A handful of Material
icons have **no clean Lucide equivalent**; those are flagged **KEEP MATERIAL** —
do NOT substitute a misleading glyph for them.

Surface: `packages/nightshade_ui/lib/src/theme/nightshade_icons.dart`
(exported from `nightshade_ui.dart`). Lucide pkg: `lucide_icons ^0.257.0`.

## In-use Material icons (67 distinct)

Counts are occurrences in `nightshade_app/lib/screens`. "Replacement" is the
adopt target; an empty "role" column means use the bare `LucideIcons.*` glyph
(no semantic role is a natural fit).

| Material `Icons.*` | n | `NightshadeIcons` role | Lucide glyph (if no role) | Notes |
|--------------------|---|------------------------|---------------------------|-------|
| `refresh` | 6 | `refresh` | | |
| `error_outline` | 6 | `error` | | outline → Lucide `xCircle` |
| `check_circle` | 5 | `success` | | |
| `delete_outline` | 4 | `delete` | | |
| `check` | 4 | `check` | | |
| `star` | 3 | `star` | | |
| `block` | 3 | | `ban` | "not allowed / disabled" |
| `add` | 3 | `add` | | |
| `wb_sunny` | 2 | `sun` | | |
| `radio_button_unchecked` | 2 | `circle` | | empty selection ring |
| `info_outline` | 2 | `info` | | |
| `image` | 2 | `image` | | |
| `folder_open` | 2 | `folderOpen` | | |
| `error` | 2 | `error` | | |
| `edit` | 2 | `edit` | | |
| `download` | 2 | `download` | | |
| `delete` | 2 | `delete` | | |
| `copy` | 2 | `copy` | | |
| `center_focus_strong` | 2 | `crosshair` | | centering reticle |
| `broken_image` | 2 | `imageOff` | | |
| `wb_twilight` | 1 | `sunset` | | twilight |
| `warning_amber` | 1 | `warning` | | |
| `warning` | 1 | `warning` | | |
| `vertical_align_top_outlined` | 1 | | `arrowUpToLine` | "to top" |
| `track_changes` | 1 | `target` | | tracking target |
| `timer_outlined` | 1 | `timer` | | |
| `thermostat` | 1 | `temperature` | | |
| `terrain_outlined` | 1 | `mount` | | horizon/terrain → mountain |
| `tablet` | 1 | | `tablet` | |
| `star_border` | 1 | | `star` | unfilled star = same glyph (Lucide is line-art) |
| `smartphone` | 1 | `phone` | | |
| `replay_circle_filled` | 1 | `undo` | | replay = counter-clockwise |
| `remove` | 1 | `remove` | | |
| `power` | 1 | `power` | | |
| `play_arrow` | 1 | `play` | | |
| `notifications_off` | 1 | `notificationsOff` | | |
| `notifications_active` | 1 | `notifications` | | |
| `nightlight_outlined` | 1 | `moon` | | |
| `navigation` | 1 | | `navigation` | direction arrow |
| `moving` | 1 | `move` | | "in motion" |
| `link` | 1 | `link` | | |
| `lightbulb` | 1 | `idea` | | |
| `layers_outlined` | 1 | `layers` | | |
| `label_outline` | 1 | `tag` | | |
| `grid_on` | 1 | `grid` | | |
| `gps_fixed` | 1 | | `locateFixed` | precise fix |
| `filter_alt` | 1 | `filter` | | |
| `expand_more` | 1 | `chevronDown` | | disclosure |
| `devices_outlined` | 1 | `device` | | |
| `devices` | 1 | `device` | | |
| `dark_mode_outlined` | 1 | `moon` | | dark theme |
| `crop_free_outlined` | 1 | | `crop` | framing crop |
| `computer` | 1 | `device` | | host machine → `monitor` |
| `close` | 1 | `close` | | |
| `chevron_right` | 1 | `chevronRight` | | |
| `chevron_left` | 1 | `chevronLeft` | | |
| `center_focus_weak` | 1 | `crosshair` | | |
| `cast_outlined` | 1 | | `cast` | screen-cast/remote |
| `camera` | 1 | `camera` | | |
| `calculate` | 1 | | `calculator` | |
| `arrow_forward` | 1 | `arrowRight` | | |
| `arrow_drop_down` | 1 | `chevronDown` | | dropdown caret |
| `analytics_outlined` | 1 | `chart` | | analytics → line chart |
| `add_circle_outline` | 1 | `add` | | (drop the circle, or `LucideIcons.plusCircle`) |
| `ac_unit` | 1 | `frost` | | snowflake / cooling |
| `blur_circular` | 1 | | — | **KEEP MATERIAL** — see flagged list |

## Flagged: no clean Lucide equivalent — KEEP MATERIAL

These Material glyphs have no faithful Lucide counterpart in `^0.257.0`.
Substituting would mislead, so the migration **keeps the Material icon** at the
call site (the only intentional Material survivors). Re-evaluate if Lucide adds
the glyph later.

| Material `Icons.*` | why no clean Lucide swap |
|--------------------|--------------------------|
| `blur_circular` | Lucide has no "out-of-focus / Gaussian-blur disc" glyph; it conveys image *softness* (e.g. an FWHM/seeing indicator). `circle`/`disc` would read as a solid status dot and lose the blur semantics. |

Everything else (66 of 67) maps cleanly to a `NightshadeIcons` role or a bare
Lucide glyph. **`star_border`** is worth a note: Lucide icons are line-art, so
the filled/outline Material distinction collapses to a single `star` — adopt
`NightshadeIcons.star` and convey selection with color/fill at the call site.

## Pinned mappings (test of record)

A few load-bearing mappings are pinned in
`packages/nightshade_ui/test/nightshade_icons_test.dart` so the semantic roles
stay wired to their intended Lucide glyphs (a silent re-point would shift every
adopting screen). Device/status/action roles are asserted there.
