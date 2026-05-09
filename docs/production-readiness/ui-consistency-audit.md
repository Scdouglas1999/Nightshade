# UI Consistency Audit

Command:

```powershell
dart run tools\production\ui_consistency_audit.dart
```

Latest local result, 2026-05-06:

- `empty_callback`: 0
- `large_radius`: 0
- `fake_callback`: 0
- `raw_button_style`: 0
- `raw_material_color`: 203
- `headless_route_not_advertised`: 0
- `design_system_gallery_missing`: 0

Raw color classification:

- `semantic_theme_color`: 0
- `intentional_image_overlay`: 203

Design-system gallery evidence:

- Ready: true
- Widget: `packages/nightshade_ui/lib/src/widgets/design_system_gallery.dart`
- Test: `packages/nightshade_ui/test/design_system_gallery_test.dart`
- Export: `packages/nightshade_ui/lib/nightshade_ui.dart`
- Missing evidence: none

Generated report:

- `.ui_consistency_audit.txt`
- `docs/production-readiness/ui-consistency-audit.json`

## Scope

The audit scans UI-facing Dart sources under:

- `apps/desktop/lib`
- `apps/mobile/lib`
- `packages/nightshade_app/lib`
- `packages/nightshade_ui/lib`

It reports:

- Raw `ElevatedButton.styleFrom`, `OutlinedButton.styleFrom`,
  `FilledButton.styleFrom`, `TextButton.styleFrom`, and `ButtonStyle` usage
- Raw `Colors.*` usages that should be classified as semantic theme colors or
  intentional image/overlay colors
- `BorderRadius.circular` and `Radius.circular` values of `12` or larger
- Empty callbacks such as `onPressed: () {}`
- Fake no-op callbacks such as `onPressed: () => Future.value()`
- Headless API routes registered under `/api/` but missing from
  `_getAvailableEndpoints`
- Missing design-system gallery evidence for buttons, cards, inputs, tabs,
  chips, alerts, status pills, exported widget availability, and representative
  widget-test interaction coverage

The audit excludes `raw_button_style` matches in
`packages/nightshade_ui/lib/src/theme/nightshade_theme.dart` because those are
the shared Material theme defaults that screen-level code is allowed to inherit.

Raw color findings include a classification segment in the finding line:

- `semantic_theme_color` means the color is ordinary UI/status styling and
  should usually move to `NightshadeColors`, `ColorScheme`, or a shared status
  helper.
- `intentional_image_overlay` means the color is used for image preview,
  annotation, sky, chart, paint/canvas, shadow, alpha overlay, or similar visual
  content where literal black/white/accent colors may be intentional.

## Release Interpretation

This is currently a report gate, not a zero-findings gate. The 2026-05-06
result has no raw button-style, large-radius, empty-callback, fake-callback,
semantic-color, or unadvertised-headless-route findings, and the design-system
gallery evidence is present. The remaining raw colors are all classified as
`intentional_image_overlay` and still need visual review for red-night
compatibility before final sign-off.

`headless_route_not_advertised` should remain zero. A nonzero value means a
registered API route is absent from `/api/info` and generated OpenAPI route
advertising.

## Follow-Up Work

- Replace or justify `semantic_theme_color` findings; prefer theme extension
  colors for ordinary controls, status indicators, and panels.
- Review `intentional_image_overlay` findings for red-night compatibility and
  retain only the literal colors needed for image/sky/chart legibility.
- Reduce ordinary panel/card radii to tokenized 8px-or-smaller surfaces where
  appropriate.
- Keep empty and fake callbacks at zero by replacing fake interactions with
  disabled controls, real actions, or explicit event absorbers.
- Re-run the audit after each UI cleanup pass and attach the updated summary to
  release evidence.
