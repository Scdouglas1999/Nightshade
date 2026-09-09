# Repository assets

Files in this folder are for **GitHub presentation** (README, social preview, release pages)—not runtime app bundles. App icons live under `apps/desktop/` per platform.

## Branding

| File | Use |
|------|-----|
| `branding/logo-512.png` | README header |
| `branding/social-preview.png` | GitHub **Settings → General → Social preview** (1280×640) |

Upload `assets/branding/social-preview.png` in your repo settings so link previews look polished on GitHub, Discord, and social feeds.

## Screenshots

Published README screenshots live in `assets/screenshots/`. Each file maps to one primary screen:

| File | Screen |
|------|--------|
| `desktop-dashboard.png` | Tonight |
| `equipment.png` | Equipment discovery & profiles |
| `imaging.png` | Imaging / capture |
| `guiding.png` | PHD2 guiding |
| `sequencer.png` | Sequence builder |
| `planetarium.png` | Planetarium sky view |
| `framing.png` | Framing assistant |
| `analytics.png` | Session analytics |
| `flat-wizard.png` | Flat frame wizard |
| `weather.png` | Weather radar |
| `plan-tonight.png` | Plan recommendations |
| `web-dashboard.png` | Browser remote dashboard |
| `settings-equipment-profiles.png` | Equipment profile settings |

### Refreshing screenshots

Every image the root README shows comes from this folder, and all but one are **generated**, not hand-captured. `packages/nightshade_app/test/golden/public_screenshots_test.dart` pumps each surface with seeded data and writes the twelve files above, so running it refreshes them in place:

```bash
cd packages/nightshade_app && flutter test test/golden/public_screenshots_test.dart
```

CI runs ubuntu-latest, so these are Linux renders and a Linux re-render is the correct baseline. Commit the regenerated PNGs. Do not hand-edit one and do not drop a manual capture in its place — the next suite run overwrites it.

`web-dashboard.png` is the exception: the browser dashboard is not a Flutter surface, so that one is still captured by hand from `http://127.0.0.1:8080/dashboard/` on a running headless instance.

`scripts/capture-readme-screenshots.ps1` is the **old** Windows capture path and writes into this same folder. It drives the app by clicking sidebar coordinates (`-NavTop`, `-NavRow`), which the Observatory rail geometry invalidated, and anything it writes is overwritten by the next suite run. Use the test, not the script; the script is kept only for the web-dashboard shot.

## License

Screenshots you commit should depict **your** equipment and data, or synthetic/demo content you have rights to publish.
