# Third-Party Notices

This document is a release-readiness license and redistribution audit for
**Nightshade 4.1.0**. Nightshade ships **compiled binaries** to end users:

- Windows: `nightshade-4.1.0-windows-x64.zip`
- Linux: `nightshade-4.1.0-linux-x64.tar.gz`
- Android: `nightshade-4.1.0-android-universal.apk`

These artifacts are produced by `.github/workflows/release.yml` and published to
a public GitHub Release. Because we distribute binaries (not just source), every
third-party component that is *compiled in*, *statically linked*, or *bundled as
a shared library* must have its redistribution right confirmed — that is the
purpose of this file.

Nightshade itself is **source-available, not OSI open-source**. See the
repository `LICENSE` (Nightshade Source-Available License, Version 1.2,
Copyright (c) 2025 Sean Douglas). That license governs Nightshade's own code and
assets; it does not grant any rights over the third-party components listed
below, whose own licenses apply.

> **Honesty note.** This audit was produced by reading the repository tree, the
> release workflow, the Cargo manifests/lockfile, the pubspecs, and the in-tree
> license files. Where an in-tree license file confirms a redistribution right,
> it is cited. Where a right **cannot** be confirmed from in-tree evidence, the
> Redistribution status column says **CONFIRM** and the item is repeated in
> "Action items for the maintainer." Nothing here should be read as legal advice
> or as a blanket assertion that every component is cleared.

## Runtime-only / user-installed tools (NOT redistributed)

The following are **external programs the user installs themselves**. Nightshade
invokes them at runtime but does **not** bundle, link, or redistribute them, so
their licenses do not attach to our binaries:

| Tool | Role | Bundled? | Notes |
|------|------|----------|-------|
| ASTAP | Plate solving | No | User-installed; invoked as an external process. |
| astrometry.net (`solve-field`) | Plate solving | No | User-installed; invoked as an external process. |
| PHD2 | Autoguiding | No | User-installed; Nightshade talks to it over its socket/event API. |
| INDI server + drivers | Linux device backend | No | User-installed / distro packages; not bundled. |
| ASCOM / Alpaca drivers | Windows device backend | No | Vendor/ASCOM-platform installed; not bundled. |

---

## 1. Bundled native libraries

These ship **inside** the release artifacts.

| Component | Version | License | Bundled in release? | Redistribution status |
|-----------|---------|---------|---------------------|-----------------------|
| Nightshade native bridge (`libnightshade_bridge.so` / `nightshade_bridge.dll`) | 4.1.0 (workspace 0.1.0) | Nightshade Source-Available (own code); Rust deps per §3 | Yes — Linux `bundle/lib/`, Windows `Release/` | Own code — OK. Statically-linked Rust crates: see §3. |
| LibRaw (`libraw.so` / `libraw.dll`) | 0.21.4 (headers say 0.21.x, April 2025 build) | LGPL-2.1 **or** CDDL-1.0 (dual, licensee's choice — confirmed in `imaging/vendor/libraw/libraw_version.h`) | Yes — Linux bundle copies host `libraw.so`; Windows ships `lib/libraw/libraw.dll` | **CONFIRM** — dynamically linked (LGPL-friendly), but LGPL-2.1 requires shipping the license text and enabling relinking; CDDL has its own notice terms. Pick a branch and satisfy its conditions. |
| SQLite (`libsqlite3.so.0` + `libsqlite3.so` symlink) | Host build (whatever `ubuntu-22.04` ships) | Public domain | Yes — Linux bundle only (Windows/Android use the plugin's own copy) | Public-domain; redistribution is unrestricted. Recommended: include the SQLite public-domain blessing note. Version is the CI host's — see "Regenerating." |
| MSVC runtime DLLs | MSVC toolchain | Microsoft redistributable | Windows only (staged by `scripts/stage_windows_release.ps1`) | **CONFIRM** — Microsoft permits redistribution of the VC++ runtime under the Visual Studio license; confirm the exact DLLs staged are on the redistributable list. |
| libwebrtc (bundled by `flutter_webrtc`) | per `flutter_webrtc ^1.4.1` | BSD-3-Clause (WebRTC/Chromium) | Yes (native lib bundled by the plugin) | BSD-3-Clause — redistribution OK with notice. Confirm against the plugin's pinned version. |

`scripts/docker_build_linux.sh` can also copy vendor camera `.so` files into
`bundle/lib` when `NIGHTSHADE_VENDOR_LIB_DIR` is set. **The tagged
`release.yml` build does NOT do this** — it only stages the bridge, LibRaw, and
SQLite. If a future official build bundles vendor SDKs that way, every item in
§2 becomes a redistributed component and must be cleared first.

---

## 2. Vendor camera / mount SDKs

**Status of the in-repo `SDKs/` directory:** it is **gitignored**
(`.gitignore` line `SDKs/`) and is therefore **not part of the source-available
repository** and **not present on CI**. The tagged release workflow never
references it. These SDKs exist only in the maintainer's local working tree for
development and are loaded **dynamically at runtime** via `libloading`
(`native/src/vendor/sdk_loader.rs`) from the user's own vendor install — they
are **not compiled in and not bundled** by the official release.

They become redistributed **only** if bundled via the optional
`NIGHTSHADE_VENDOR_LIB_DIR` Docker path described in
`docs/supported-hardware-by-platform.md` ("Linux Packaging"). Until then, the
right to redistribute each must be confirmed **per vendor before any official
binary includes it.**

| Vendor SDK | Version (local tree) | License (in-tree evidence) | Bundled in release? | Redistribution status |
|-----------|----------------------|----------------------------|---------------------|-----------------------|
| ZWO ASI / EAF / EFW | ASI V1.40, EAF V1.6, EFW V1.7 | MIT-style permissive — "Copyright (c) 2015, ZWO Company … permission … to use, copy, modify, merge, publish, distribute, sublicense, and/or sell" (`license.txt`) | No (dynamic, user-installed) | Permissive grant present; **CONFIRM** when bundling — keep the ZWO license text alongside the binary. |
| Player One | V3.7.1 | Permissive — "You can use our company's products and this SDK to develop any products without any restrictions" (`license.txt`) | No | Permissive grant present; **CONFIRM** redistribution-of-binary specifics with Player One before bundling. |
| QHY (qhyccd) | SDK 25.09.29 (linux64/arm64/win/android/mac) | No explicit LICENSE file found in tree | No | **CONFIRM** — no in-tree license; obtain QHYCCD redistribution terms. |
| Touptek / ToupTek (also covers Altair/Mallincam/OGMA OEM rebrands) | local clone + "ToupTekOfficial/extracted" | No explicit LICENSE file found in tree | No | **CONFIRM** — no in-tree license; obtain ToupTek redistribution terms. |
| SVBony | SVBONY SDK | Only `ReadMe.txt` files found; no license text | No | **CONFIRM** — no in-tree license; obtain SVBony redistribution terms. |
| Atik | "extracted" SDK | Only `README.txt`; no license text | No | **CONFIRM** — no in-tree license; obtain Atik redistribution terms. |
| FLI (libfli / fliusb) | libfli-1.104, fliusb-1.3 | README present; no clear top-level LICENSE confirmed in tree | No | **CONFIRM** — libfli is commonly distributed under an FLI/BSD-style grant, but this could **not** be confirmed from an in-tree license file; verify (and note the `fliusb` kernel driver is separate). |
| Moravian (Gx) | "extracted" SDK | No explicit LICENSE file found in tree | No | **CONFIRM** — no in-tree license; obtain Moravian redistribution terms. |
| SBIG DLAPI | dlapi-sdk-4.0.2.0-win-x64 | Only `README.txt`; no license text | No | **CONFIRM** — no in-tree license; obtain Diffraction Limited / SBIG terms. |
| Fujifilm | SDK13410 | Only sample `Readme.txt`; SDK is under Fujifilm's developer agreement | No | **CONFIRM** — Fujifilm camera SDK typically requires an NDA/developer agreement; redistribution almost certainly restricted. |
| SkyWatcher | mount SDK dir | No license file found in tree | No | **CONFIRM** — obtain SkyWatcher terms (mount protocol/SDK). |

> Every row in §2 is flagged **CONFIRM** for redistribution. ZWO and Player One
> carry an explicit permissive grant in-tree; the rest have **no in-tree license
> evidence at all** and must not be bundled into an official binary until their
> terms are obtained in writing.

---

## 3. Rust crates (native bridge)

The native bridge and its workspace crates statically link the following Rust
dependencies (top-level deps from `native/nightshade_native/*/Cargo.toml`; the
full transitive set is **417 crates** in `Cargo.lock`). The Rust ecosystem is
overwhelmingly MIT/Apache-2.0 dual-licensed (permissive, redistribution OK with
notice), but this should be machine-verified — see "Regenerating."

| Crate | Version (manifest) | Typical license | Bundled in release? | Redistribution status |
|-------|--------------------|-----------------|---------------------|-----------------------|
| flutter_rust_bridge | =2.11.1 | MIT / Apache-2.0 | Yes (compiled in) | OK with notice |
| windows / windows-sys | 0.52 | MIT / Apache-2.0 (Microsoft) | Yes, Windows | OK with notice |
| tokio | 1.35 | MIT | Yes | OK with notice |
| serde / serde_json | 1.0 | MIT / Apache-2.0 | Yes | OK with notice |
| image | 0.24 | MIT / Apache-2.0 | Yes | OK with notice |
| reqwest | 0.11 | MIT / Apache-2.0 | Yes | OK with notice. Pulls TLS — **CONFIRM** whether OpenSSL is linked (see below). |
| rusb | 0.9 (`vendored`, Unix) | MIT — but vendors **libusb** (LGPL-2.1) | Yes, Linux | **CONFIRM** — `vendored` statically links libusb (LGPL-2.1); confirm LGPL relink obligation is met for the bundled bridge. |
| wgpu | 0.19 | MIT / Apache-2.0 | Yes | OK with notice |
| chrono | 0.4 | MIT / Apache-2.0 | Yes | OK with notice |
| rayon | 1.10 | MIT / Apache-2.0 | Yes | OK with notice |
| memmap2 | 0.9 | MIT / Apache-2.0 | Yes | OK with notice |
| bytemuck | 1.14 | MIT / Apache-2.0 / Zlib | Yes | OK with notice |
| quick-xml | 0.31 | MIT | Yes | OK with notice |
| libloading | (transitive) | ISC | Yes | OK with notice |
| openssl | (transitive, present in `Cargo.lock`) | Apache-2.0 (OpenSSL 3) | Possibly, Linux | **CONFIRM** — if OpenSSL is actually linked into the shipped bridge, ship its Apache-2.0 notice. Verify whether it's `openssl-sys` (system) vs vendored. |

`native/nightshade_native/deny.toml` and a `cargo about`/`cargo-license` run are
the authoritative source for the exact licenses — regenerate before release.

---

## 4. Flutter / Dart packages

App-level third-party packages from `apps/desktop/pubspec.yaml`,
`apps/mobile/pubspec.yaml`, and `packages/*/pubspec.yaml`. (Workspace-internal
`nightshade_*` path deps are first-party and omitted.) pub.dev packages are
almost all BSD-3/MIT; the exact pinned versions are in the `pubspec.lock` files
(not transcribed here to avoid fabricating versions).

| Package | Constraint | Typical license | Bundled in release? | Redistribution status |
|---------|-----------|-----------------|---------------------|-----------------------|
| flutter_riverpod | ^2.5.1 | MIT | Yes | OK with notice |
| go_router | ^14.0.0 | BSD-3 (Flutter team) | Yes | OK with notice |
| drift | ^2.30.0 | MIT | Yes | OK with notice |
| sqlite3_flutter_libs | ^0.5.18 | MIT (bundles SQLite, public domain) | Yes | OK; SQLite is public-domain (see §1) |
| flutter_hooks | ^0.20.5 | MIT | Yes | OK with notice |
| freezed_annotation / json_annotation | ^3.0.0 / ^4.9.0 | MIT / BSD-3 | Yes | OK with notice |
| path_provider / path / collection / crypto / intl / ffi / uuid / equatable | various | BSD-3 / MIT | Yes | OK with notice |
| package_info_plus / connectivity_plus / battery_plus / wakelock_plus | various | BSD-3 (plus_plugins) | Yes | OK with notice |
| window_manager | ^0.3.8 | MIT | Yes (desktop) | OK with notice |
| file_selector | ^1.0.3 | BSD-3 (Flutter team) | Yes | OK with notice |
| url_launcher | ^6.2.4 | BSD-3 (Flutter team) | Yes | OK with notice |
| image (Dart) | ^4.1.7 | MIT | Yes | OK with notice |
| qr_flutter | ^4.1.0 | BSD-3 | Yes | OK with notice |
| shelf / shelf_router / shelf_web_socket / web_socket_channel | various | BSD-3 (Dart team) | Yes | OK with notice |
| multicast_dns | ^0.3.2 | BSD-3 (Dart team) | Yes (desktop) | OK with notice |
| basic_utils | ^5.7.0 | Apache-2.0 | Yes | OK with notice |
| pointycastle | ^3.9.1 | MIT (+ Bouncy Castle-derived portions) | Yes | OK with notice |
| irondash_engine_context | 0.5.0 | MIT | Yes (desktop) | OK with notice |
| flutter_webrtc | ^1.4.1 | MIT (bundles libwebrtc — BSD-3, see §1) | Yes | OK; confirm libwebrtc notice |
| nsd | ^3.0.0 | Apache-2.0 | Yes (mobile) | OK with notice |
| flutter_secure_storage | ^9.2.2 | BSD-3 | Yes (mobile) | OK with notice |
| mobile_scanner | ^5.2.3 | BSD-3 (bundles platform barcode libs) | Yes (mobile) | **CONFIRM** — bundles native scanning libs (e.g. Apple Vision / MLKit-free build); confirm its native dep licensing on Android. |
| permission_handler | ^11.3.1 | MIT | Yes (mobile) | OK with notice |
| flutter_foreground_task / flutter_local_notifications | ^6.0.0 / ^18.0.0 | MIT | Yes (mobile) | OK with notice |
| shared_preferences | ^2.2.2 | BSD-3 (Flutter team) | Yes (mobile) | OK with notice |
| cupertino_icons | ^1.0.8 | MIT | Yes (mobile) | OK with notice |
| http | ^1.2.0 | BSD-3 (Dart team) | Yes (mobile) | OK with notice |

---

## 5. Icons, fonts, and assets

These are tracked in-repo and ship inside the artifacts.

| Asset | License | In-tree license file | Bundled in release? | Redistribution status |
|-------|---------|----------------------|---------------------|-----------------------|
| Lucide icon font (`third_party/lucide_icons/lucide.ttf`) + Dart wrapper, also `lucide_icons ^0.257.0` | ISC (portions MIT from Feather) | `third_party/lucide_icons/LICENSE` | Yes | OK — ISC, redistribution permitted. Keep the LICENSE file. |
| Hanken Grotesk (`HankenGrotesk-VF.ttf`) | SIL Open Font License 1.1 | `assets/fonts/HankenGrotesk-OFL.txt` | Yes | OK — OFL permits bundling; the OFL text ships alongside as required. |
| Spline Sans Mono (`SplineSansMono-VF.ttf`) | SIL Open Font License 1.1 | `assets/fonts/SplineSansMono-OFL.txt` | Yes | OK — OFL; license text ships alongside. |
| cupertino_icons font | MIT | (pub package) | Yes (mobile) | OK with notice |
| Nightshade branding/screenshots (`assets/branding`, `assets/screenshots`) | Nightshade Source-Available | repo `LICENSE` | Repo only (screenshots not shipped) | Own assets — OK. |
| Planetarium catalog packs (`assets/planetarium/catalogs/`) | See that dir's `README.md` | per-catalog | Yes | **CONFIRM** — astronomical catalogs (e.g. HYG, HIP/Tycho-derived) have their own attribution terms; verify the catalog `README.md` covers redistribution. |
| `de421.bsp` (JPL ephemeris) | NASA/JPL public data | — | Confirm if shipped | **CONFIRM** — JPL ephemerides are public but carry JPL attribution conventions; confirm whether `de421.bsp` is bundled and add the JPL credit if so. |

---

## Action items for the maintainer before public binary distribution

Confirm each of the following **before** shipping an official binary that
includes the component. Items are ordered roughly by risk.

1. **Vendor camera/mount SDKs (§2).** Do **not** bundle any vendor `.so`/`.dll`
   into an official artifact until its redistribution right is confirmed:
   - QHY, ToupTek (and Altair/Mallincam/OGMA rebrands), SVBony, Atik, Moravian,
     SBIG/Diffraction Limited, SkyWatcher — **no in-tree license**; obtain terms
     in writing.
   - Fujifilm — almost certainly under a developer agreement/NDA; treat as
     **not redistributable** unless explicitly cleared.
   - FLI (libfli) — confirm the actual license; no clear in-tree LICENSE file.
   - ZWO and Player One carry permissive in-tree grants, but still confirm the
     "redistribute the compiled `.so`" case and ship their license text.
   - The current tagged `release.yml` bundles **none** of these — keep it that
     way until cleared, and audit any use of `NIGHTSHADE_VENDOR_LIB_DIR`.
2. **LibRaw (LGPL-2.1 / CDDL-1.0).** Pick a license branch and satisfy it:
   under LGPL-2.1, ship the LGPL text and preserve the ability to relink against
   a modified LibRaw (we link dynamically, which helps); under CDDL-1.0, include
   the CDDL notice. Add the chosen license text to the artifact.
3. **libusb via `rusb` `vendored` (Linux).** This statically links libusb
   (LGPL-2.1) into the bridge. Confirm the LGPL relink obligation is met (e.g.
   provide object files or rely on dynamic linking) or switch off `vendored`.
4. **OpenSSL** (if linked). `openssl` appears in `Cargo.lock`. Determine whether
   it is actually linked into the shipped bridge (vs system `openssl-sys`); if
   vendored/static, ship the Apache-2.0 (OpenSSL 3) notice.
5. **SQLite.** Public domain — no obligation, but include the standard SQLite
   public-domain note as a courtesy. The Linux bundle ships the **CI host's**
   SQLite; record its version from the release build logs.
6. **MSVC runtime DLLs (Windows).** Verify the exact DLLs staged by
   `scripts/stage_windows_release.ps1` are on Microsoft's redistributable list.
7. **flutter_webrtc / libwebrtc and mobile_scanner.** Confirm the bundled native
   library licenses (WebRTC = BSD-3; mobile_scanner's Android barcode backend)
   and ship their notices.
8. **Catalog packs and `de421.bsp`.** Confirm the planetarium catalog and JPL
   ephemeris attribution/redistribution terms and add the required credits.
9. **GPL check.** No GPL-licensed dependency was confirmed compiled into the
   shipped binaries from in-tree evidence. The `fliusb` kernel driver in the
   (gitignored, unbundled) FLI tree is a separate kernel module and is **not**
   shipped — keep it that way. Run the regeneration step below to confirm no
   GPL/AGPL crate slipped into the transitive Rust or Dart graph.

---

## Regenerating the full, machine-readable list

Do not hand-maintain exact versions — generate them:

**Rust (native bridge, authoritative for §1 native deps + §3):**

```bash
cd native/nightshade_native
# License summary per crate:
cargo install cargo-license && cargo license
# Full attribution bundle (uses about.toml / templates):
cargo install cargo-about && cargo about generate about.hbs > THIRD_PARTY_RUST.html
# Policy/deny gate (already configured):
cargo deny check licenses   # honors deny.toml
```

**Dart/Flutter (§4):**

```bash
# Resolved dependency graph with exact versions:
cd apps/desktop && flutter pub deps
cd apps/mobile  && flutter pub deps
# Exact pinned versions live in each pubspec.lock.
# In-app license registry (Flutter aggregates LICENSE files at build time):
#   showLicensePage(...) / LicenseRegistry — verify it renders all bundled deps.
```

**Bundled C libraries (LibRaw, SQLite, libusb, OpenSSL):** read the version
strings from the actual shipped binaries / CI build logs after a release build,
since the Linux bundle copies the CI host's shared objects.

The version numbers in the tables above are taken from manifests and in-tree
headers where available; treat the generated output as authoritative.
