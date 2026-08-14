/// The session-picker entry that means "the frames shot outside any session".
///
/// Analytics ▸ Session and ▸ Science both derive the night under review from an
/// `int? _selectedSessionId` where `null` meant "auto": follow the live session,
/// else the newest one on record. That left no way to *say* quick captures.
/// Once a single sequence run existed the auto-pick resolved to it forever, and
/// the 37 loose frames — with their charts, captured-image grid, photometry and
/// field-quality products — were unreachable, while History's own Quick
/// captures card told the operator to "open Analytics ▸ Session to review them
/// frame by frame".
///
/// A sentinel id gives the picker a third state: a real menu entry the operator
/// can choose, distinct from "auto". Diagnostics already had its own copy of
/// this idea; this constant is the one both other pickers share so the three
/// cannot drift apart again. No `imaging_sessions` row can carry it — the
/// column is a positive autoincrement key.
const int kQuickCaptureSessionSelection = -1;

/// What every picker calls that entry. One string, so a user who learns it on
/// Diagnostics recognises it on Session and Science.
const String kQuickCaptureSessionLabel = 'Quick captures (no session)';
