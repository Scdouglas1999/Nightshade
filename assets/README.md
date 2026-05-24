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
| `desktop-dashboard.png` | Dashboard |
| `equipment.png` | Equipment discovery & profiles |
| `imaging.png` | Imaging / capture |
| `guiding.png` | PHD2 guiding |
| `sequencer.png` | Sequence builder |
| `planetarium.png` | Planetarium sky view |
| `framing.png` | Framing assistant |
| `analytics.png` | Session analytics |
| `flat-wizard.png` | Flat frame wizard |
| `weather.png` | Weather radar |
| `plan-tonight.png` | Plan Tonight recommendations |
| `web-dashboard.png` | Browser remote dashboard |
| `settings-equipment-profiles.png` | Equipment profile settings |

### Refreshing screenshots

1. Capture clean PNGs at **1920×1080** or native window size in the dark theme.
2. Dismiss welcome flows, tutorial popups, and weather banners where possible.
3. Copy into `assets/screenshots/` using the filenames above (overwrite in place).
4. Keep the same Nightshade version across all shots for a coherent release page.

You can keep working copies anywhere (for example `Screenshots/` at the repo root); only files under `assets/screenshots/` are referenced by the README.

Automated capture (Windows release build):

```powershell
.\scripts\capture-readme-screenshots.ps1 -SkipBuild
```

## License

Screenshots you commit should depict **your** equipment and data, or synthetic/demo content you have rights to publish.
