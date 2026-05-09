# Linux Release CI Recipe

This recipe makes the Linux release build repeatable. It does not replace the
external Linux release evidence gate because that gate still requires a runtime
smoke log from the built Linux artifact.

## GitHub Actions Workflow

Run `.github/workflows/linux-release-build.yml` manually with
`workflow_dispatch`, or let it run on pull requests that touch Linux build
inputs. The workflow:

- installs Flutter, Rust, Melos, and Linux desktop build packages;
- runs `dart run melos run build:desktop:linux --no-select`;
- packages `apps/desktop/build/linux/x64/release/bundle` as a tarball;
- writes `docs/production-readiness/linux-release-package-metadata.json`;
- writes a `build/release-linux/*.sha256` sidecar for the package;
- records `metadataSchemaVersion`, `toolVersions`, and `packageSha256Path`
  provenance for the external evidence verifier;
- records structured `nativeLibraryNotes` and `linuxPermissionNotes` so the
  later external Linux smoke can document bundled shared libraries, vendor SDK
  runtime assumptions, `udev` rules, and `dialout`/`plugdev`/`video`
  membership checks;
- uploads the tarball, SHA256 sidecar, and metadata as workflow artifacts.

## Local Linux Command

After a successful Linux build:

```bash
dart run tools/production/linux_release_package_metadata.dart \
  --bundle-dir=apps/desktop/build/linux/x64/release/bundle \
  --output-dir=build/release-linux \
  --metadata-output=docs/production-readiness/linux-release-package-metadata.json
```

To produce the gate evidence after a real Linux runtime smoke or headless smoke
passes:

```bash
dart run tools/production/linux_release_package_metadata.dart \
  --bundle-dir=apps/desktop/build/linux/x64/release/bundle \
  --output-dir=build/release-linux \
  --metadata-output=docs/production-readiness/linux-release-package-metadata.json \
  --native-library-note="ldd checked against packaged bundle and required shared libraries recorded" \
  --linux-permission-note="udev rules and dialout/plugdev/video access checked on the smoke host" \
  --write-evidence \
  --runtime-smoke-log=docs/production-readiness/linux-runtime-smoke.log \
  --runtime-smoke-passed
```

Then run:

```bash
dart run melos run audit:public-release-external-evidence --no-select
dart run melos run audit:public-release-gate --no-select
```

The evidence remains blocked unless the smoke log exists, is non-empty, and
`runtimeSmokePassed` is explicitly true.

The generated evidence also includes a structured `runtimeSmokeChecks` array so
the public release verifier can confirm the Linux artifact actually exercised
the expected runtime surface. The required checks are:

- `headless_process_started`
- `api_info_ok`
- `openapi_ok`
- `dashboard_asset_ok`

The generated metadata and evidence must also include:

- `nativeLibraryNotes`
- `linuxPermissionNotes`

Expected generated artifacts:

- `build/release-linux/*.tar.gz`
- `build/release-linux/*.sha256`
- `docs/production-readiness/linux-release-package-metadata.json`
- `docs/production-readiness/linux-release-build-evidence.json` when
  `--write-evidence` is used

The metadata JSON must include `metadataSchemaVersion`, `toolVersions`, package
size/hash fields, `packageSha256Path`, `nativeLibraryNotes`, and
`linuxPermissionNotes`. The external evidence gate compares those values
against the package and sidecar before accepting Linux evidence.
