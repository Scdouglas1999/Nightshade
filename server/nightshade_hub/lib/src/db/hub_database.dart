import 'package:sqlite3/sqlite3.dart';

/// Embedded sqlite store for the Constellation hub. Chosen over postgres for
/// self-host parity: a single file (or `:memory:` in tests) and the system
/// `libsqlite3`, no external service. Schema is created idempotently on open.
///
/// Tables:
///  - `accounts`        — identity + auth (password hash, public key, trust)
///  - `tokens`          — issued bearer tokens (SHA-256 of the raw token only)
///  - `shared_targets`  — cone-addressable shared targets ("follow-the-night")
///  - `contributions`   — per-contributor upload ledger (for retraction + audit)
///  - `tile_index`      — per-tile fused summary (frames, seconds, contributors)
///  - `raw_subframe_contributions` — per-account raw FITS subframe ledger (the
///    opt-in `acceptsRawSubs` path; one row per stored frame, file on disk)
///  - `handoff_claims`  — single-holder follow-the-night claim per target
///  - `audit_log`       — append-only request audit trail
class HubDatabase {
  HubDatabase._(this.db);

  final Database db;

  /// Open a hub database at [path] (use `':memory:'` for tests) and ensure the
  /// schema exists. Foreign keys are enforced; WAL improves concurrent reads.
  factory HubDatabase.open(String path) {
    final db = sqlite3.open(path);
    db.execute('PRAGMA foreign_keys = ON;');
    if (path != ':memory:') {
      db.execute('PRAGMA journal_mode = WAL;');
    }
    final hub = HubDatabase._(db);
    hub._migrate();
    return hub;
  }

  void _migrate() {
    db.execute('''
      CREATE TABLE IF NOT EXISTS accounts (
        id            TEXT PRIMARY KEY,
        display_name  TEXT NOT NULL,
        public_key    TEXT NOT NULL,
        password_hash TEXT,
        trust         REAL NOT NULL DEFAULT 0.5,
        is_admin      INTEGER NOT NULL DEFAULT 0,
        residual_sum  REAL NOT NULL DEFAULT 0,
        residual_n    INTEGER NOT NULL DEFAULT 0,
        accepted_frames INTEGER NOT NULL DEFAULT 0,
        rejected_frames INTEGER NOT NULL DEFAULT 0,
        created_at    TEXT NOT NULL,
        UNIQUE (public_key)
      );
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS tokens (
        token_hash TEXT PRIMARY KEY,
        account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
        scope      TEXT NOT NULL,
        created_at TEXT NOT NULL,
        expires_at TEXT
      );
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS shared_targets (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        name          TEXT NOT NULL,
        center_ra_deg REAL NOT NULL,
        center_dec_deg REAL NOT NULL,
        radius_deg    REAL NOT NULL,
        priority      REAL NOT NULL DEFAULT 0.5,
        integration_seconds REAL NOT NULL DEFAULT 0,
        created_at    TEXT NOT NULL
      );
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS tile_index (
        tile_id       INTEGER NOT NULL,
        healpix_order INTEGER NOT NULL,
        channels      INTEGER NOT NULL,
        center_ra_deg REAL NOT NULL,
        center_dec_deg REAL NOT NULL,
        total_frames  INTEGER NOT NULL DEFAULT 0,
        integration_seconds REAL NOT NULL DEFAULT 0,
        contributors  INTEGER NOT NULL DEFAULT 0,
        sidecar_path  TEXT NOT NULL,
        updated_at    TEXT NOT NULL,
        PRIMARY KEY (tile_id, healpix_order)
      );
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS contributions (
        id            TEXT PRIMARY KEY,
        account_id    TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
        tile_id       INTEGER NOT NULL,
        healpix_order INTEGER NOT NULL,
        frames_delta  INTEGER NOT NULL,
        integration_seconds_delta REAL NOT NULL,
        median_fwhm   REAL,
        trust_applied REAL NOT NULL,
        status        TEXT NOT NULL,
        delta_path    TEXT NOT NULL,
        instrument    TEXT,
        solver        TEXT,
        created_at    TEXT NOT NULL
      );
    ''');
    db.execute(
      'CREATE INDEX IF NOT EXISTS idx_contrib_tile '
      'ON contributions(tile_id, healpix_order);',
    );
    db.execute(
      'CREATE INDEX IF NOT EXISTS idx_contrib_account '
      'ON contributions(account_id);',
    );

    // Raw subframe ledger (the opt-in `acceptsRawSubs` path). Unlike additive
    // sums, each raw FITS lives as its own file on disk and its own row here so
    // a single-frame DELETE is an exact file-delete. `contribution_id` is the
    // opaque handle the client persists and later retracts on.
    db.execute('''
      CREATE TABLE IF NOT EXISTS raw_subframe_contributions (
        contribution_id   TEXT PRIMARY KEY,
        account_id        TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
        tile_id           INTEGER NOT NULL,
        healpix_order     INTEGER NOT NULL,
        captured_image_id INTEGER,
        path              TEXT NOT NULL,
        bytes             INTEGER NOT NULL,
        instrument        TEXT,
        exposure_seconds  REAL,
        received_at       TEXT NOT NULL
      );
    ''');
    db.execute(
      'CREATE INDEX IF NOT EXISTS idx_raw_sub_tile '
      'ON raw_subframe_contributions(tile_id, healpix_order);',
    );
    db.execute(
      'CREATE INDEX IF NOT EXISTS idx_raw_sub_account '
      'ON raw_subframe_contributions(account_id);',
    );

    db.execute('''
      CREATE TABLE IF NOT EXISTS handoff_claims (
        target_id   INTEGER PRIMARY KEY REFERENCES shared_targets(id)
                       ON DELETE CASCADE,
        account_id  TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
        claim_token TEXT NOT NULL,
        claimed_at  TEXT NOT NULL,
        expires_at  TEXT NOT NULL
      );
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS audit_log (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        at         TEXT NOT NULL,
        account_id TEXT,
        method     TEXT NOT NULL,
        path       TEXT NOT NULL,
        status     INTEGER NOT NULL,
        detail     TEXT
      );
    ''');
    db.execute('CREATE INDEX IF NOT EXISTS idx_audit_at ON audit_log(at);');
  }

  void dispose() => db.dispose();
}
