/// Nightshade Constellation hub — the community backend service.
///
/// A self-hostable, multi-tenant Dart shelf service that fuses additive
/// sky-atlas tile contributions from many imagers into shared deeper stacks,
/// using the same additive co-add algebra as the Rust keystone
/// (`native/.../imaging/src/sky_atlas.rs`).
library;

export 'src/auth/account_service.dart';
export 'src/auth/password_hasher.dart';
export 'src/auth/secret_policy.dart';
export 'src/auth/token_service.dart';
export 'src/db/hub_database.dart';
export 'src/http/audit_log.dart';
export 'src/http/error_envelope.dart';
export 'src/http/rate_limiter.dart';
export 'src/hub_server.dart';
export 'src/scheduler/follow_the_night.dart';
export 'src/scheduler/handoff_service.dart';
export 'src/tiles/fusion_service.dart';
export 'src/tiles/tile_builder.dart';
export 'src/tiles/tile_codec.dart';
export 'src/tiles/tile_quality.dart';
export 'src/tiles/tile_store.dart';
