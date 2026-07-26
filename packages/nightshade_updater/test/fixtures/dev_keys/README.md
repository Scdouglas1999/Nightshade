# Dev update keys — **DEV-ONLY, NEVER PRODUCTION**

These Ed25519 keys exist solely for local OTA-update testing on a developer
machine. **Do not use them to sign anything a real user could install.**

- `dev_update_public_key.b64` — base64 raw 32-byte Ed25519 public key.
- `dev_update_private_key.b64` — base64 raw 32-byte Ed25519 private seed.
- `sample_manifest.signed.json` — a sample `UpdateManifest` signed with the
  dev seed over `UpdateVerifier.canonicalManifestPayload`, so it verifies
  through the exact code path a release build runs.

## Why this is safe to commit

The dev public key is **never baked into a release build**. Release builds
source `NIGHTSHADE_UPDATE_PUBLIC_KEY` exclusively from the owner's GitHub
Secret at build time (`scripts/package_windows.ps1`), and a build with no key
**fails closed** — it refuses every OTA download and apply. So even though
this private seed is public, no shipped Nightshade trusts it: it cannot sign
an update that a real installation would accept.

## Regenerating

```sh
# from packages/nightshade_updater/
dart run tool/generate_dev_keypair.dart   # writes the .b64 keypair here
dart run tool/sign_dev_manifest.dart      # writes sample_manifest.signed.json
```

## Production keys (owner-gated)

The real release keypair is generated and held by the project owner. The
private key lives only in the GitHub Secret `NIGHTSHADE_UPDATE_PRIVATE_KEY`
and the public key is passed at build time via
`--dart-define=NIGHTSHADE_UPDATE_PUBLIC_KEY=...`. Key-id rotation
(`NIGHTSHADE_UPDATE_PUBLIC_KEY_NEXT` / `NIGHTSHADE_UPDATE_KEY_ID*`) and the
revocation roster (`NIGHTSHADE_UPDATE_REVOKED_KEY_IDS`) are operational
decisions made by the owner, not committed here.
