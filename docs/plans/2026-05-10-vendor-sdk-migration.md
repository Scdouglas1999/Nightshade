# Vendor SDK Loader Migration — Follow-up Tasks

**Created:** 2026-05-10
**Parent task:** v2.5.0 audit §5.20 (W3-DRV-SDK)
**Status:** ZWO migrated as proof-of-pattern; 12 vendors queued.

## Background

`native/nightshade_native/native/src/vendor/sdk_loader.rs` introduces a shared
`VendorSdk` trait + `load_vendor_sdk!` macro that consolidates the path-search,
`libloading::Library::open`, per-symbol resolution, and `OnceLock` storage
boilerplate that previously lived (duplicated) in every vendor module.

`zwo.rs` was migrated as the canonical example. It demonstrates three distinct
SDK loaders being declared with the macro:

- `AsiSdk` (ZWO ASI Camera, with a rich Windows install-tree search list)
- `EafSdk` (ZWO EAF focuser, simple platform-specific filename)
- `EfwSdk` (ZWO EFW filter wheel, simple platform-specific filename)

ZWO file size: **2548 → 2447 lines** (~100 lines net). The boilerplate
specifically (path-search + library-open + load_symbol + OnceLock storage)
contracted from ~286 LOC to ~50 LOC of `candidate_paths_fn` declarations + a
declarative symbol table per SDK.

## Migration pattern

For each remaining vendor:

1. Identify the per-SDK loader block (look for `struct *Sdk { ... }`,
   `static *_SDK: OnceLock<...>`, and `impl *Sdk { fn load() / fn get() }`).
2. Extract candidate paths into a `*_candidate_paths() -> Vec<PathBuf>`
   function. Per-platform paths should already be filtered.
3. Replace the loader block with a `load_vendor_sdk! { ... }` invocation.
4. Add `use crate::load_vendor_sdk;` and `use std::path::PathBuf;` near the top
   of the file.
5. Remove the now-unused `OnceLock` import.
6. Run `cargo check -p nightshade_native --all-features` to verify.
7. Run `cargo clippy -p nightshade_native --all-features -- -D warnings` to
   verify lint cleanliness.
8. Run the vendor's unit tests:
   `cargo test -p nightshade_native vendor::<vendor>::tests --lib`.

**Critical:** the migrated `*Sdk::get()` accessor must keep the same signature
(`pub fn get() -> Option<&'static *Sdk>`) so call sites continue to work
unchanged. The macro generates exactly that signature.

## Remaining vendors

| Vendor file       | SDK loaders to migrate                                    | Estimated effort | Notes |
|-------------------|-----------------------------------------------------------|------------------|-------|
| `atik.rs`         | `AtikSdk` (1 loader)                                      | 0.5 day          | Returns `Result<Self, NativeError>` today — adapt return type to `Option<Self>` to match macro. |
| `fli.rs`          | `FliSdk` + optional focuser/filter-wheel loaders          | 0.5–1 day        | Multiple sub-SDK loaders — pattern matches ZWO. |
| `fujifilm.rs`     | `FujifilmSdk` (Windows-only via `#[cfg(target_os = "windows")]`) | 0.5 day    | Make sure `cfg` gating is preserved when declaring `candidate_paths_fn`. |
| `gphoto2.rs`      | `Gphoto2Sdk` (Linux primary, optional macOS)              | 0.5 day          | |
| `ioptron.rs`      | Mount serial protocol — no shared-library loader          | 0 day            | **Skip** — no SDK boilerplate; uses serialport crate directly. |
| `lx200.rs`        | Mount serial protocol — no shared-library loader          | 0 day            | **Skip** — same as ioptron. |
| `moravian.rs`     | `MoravianSdk`                                             | 0.5 day          | |
| `player_one.rs`   | `PoaSdk` (+ EAF/EFW analogs if present)                   | 0.5–1 day        | Largest vendor file after ZWO; check for multiple loaders. |
| `qhy.rs`          | `QhySdk` + `QhyCfwSdk` (filter wheel)                     | 1 day            | Two loaders; QHY has serial-number based discovery complications. |
| `skywatcher.rs`   | Mount serial protocol — no shared-library loader          | 0 day            | **Skip**. |
| `svbony.rs`       | `SvbonySdk`                                               | 0.5 day          | |
| `touptek.rs`      | `TouptekSdk` — **multi-brand HashMap**                    | 1.5 days         | **Special case:** Touptek uses `OnceLock<Mutex<HashMap<String, ...>>>` for multi-brand SDK storage. The macro cannot generate this directly. Use `open_vendor_library` + `resolve_symbol` helpers directly inside Touptek's `with_sdk(brand, ...)` flow rather than the `load_vendor_sdk!` macro. |

**Camera/imaging vendors net effort:** ~6 days
**Mount vendors:** 0 days (no boilerplate to migrate)
**Total:** ~6 working days, one vendor per commit.

## Per-vendor commit checklist

Each migration should land as a separate commit with this template:

```
[W3-DRV-SDK] §5.20 — migrate <vendor> to load_vendor_sdk! macro

- Replace hand-rolled <Vendor>Sdk struct + OnceLock + load() boilerplate
- Public API unchanged: <Vendor>Sdk::get() -> Option<&'static <Vendor>Sdk>
- Verify: cargo check + cargo clippy + cargo test vendor::<vendor>

LOC delta: <before> -> <after>
```

## Why these vendors weren't migrated together

The audit explicitly requested ZWO as the proof-of-pattern only. Migrating all
13 vendors in one commit would:

1. Create a 5000-line diff that's effectively unreviewable.
2. Risk a single macro-expansion bug propagating across every native driver.
3. Block independent verification of each vendor's discovery + tests.

Doing one vendor per commit keeps the blast radius small and lets the imaging
laptop sanity-check each migration before the next lands.
