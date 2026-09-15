import '../../database/daos/settings_dao.dart';

/// Where the backlash figure autofocus will use came from. Ordered best-first:
/// this is the resolution chain.
enum FocuserBacklashOrigin {
  /// The operator typed it into Settings. Always wins; nothing overwrites it.
  operatorEntered,

  /// This app measured it on the focuser in question.
  measured,

  /// No figure — neither entered nor measured, or measured and found to be
  /// nothing worth compensating.
  none,
}

/// The backlash figure that will actually be applied, with the sentence that
/// says where it came from.
class EffectiveFocuserBacklash {
  const EffectiveFocuserBacklash({
    required this.steps,
    required this.origin,
    required this.provenance,
    this.record,
  });

  /// Backlash in focuser steps, 0 when [origin] is
  /// [FocuserBacklashOrigin.none].
  final int steps;

  final FocuserBacklashOrigin origin;

  /// Where this number came from, as a phrase that reads as the tail of
  /// `<n> steps, <provenance>`. For [FocuserBacklashOrigin.none] it reads as
  /// the tail of `Backlash compensation is off: <provenance>`.
  final String provenance;

  /// The measurement behind [steps]. Non-null only for
  /// [FocuserBacklashOrigin.measured].
  final FocuserBacklashCalibrationRecord? record;

  /// Whether there is a figure to size a run-up from.
  bool get hasFigure => origin != FocuserBacklashOrigin.none;
}

/// What the operator typed outranks what we measured, always.
const String _operatorProvenance = 'the value you entered';

/// Resolve the figure to apply from the two places one can come from.
///
/// [operatorEnteredSteps] is `AppSettings.afBacklashIn`, which ships as 0.
/// A non-zero value there is the operator's own answer to this question and
/// wins outright — measuring never overwrites a number somebody typed.
/// [measured] is consulted only when they have left theirs at 0.
///
/// A measured record of 0 steps ([FocuserBacklashCalibrationRecord.measurable]
/// false) resolves to [FocuserBacklashOrigin.none]: "no backlash larger than
/// the scans could resolve" is a real result, and it is not a figure to size a
/// run-up from.
EffectiveFocuserBacklash resolveEffectiveFocuserBacklash({
  required int operatorEnteredSteps,
  required FocuserBacklashCalibrationRecord? measured,
}) {
  if (operatorEnteredSteps > 0) {
    return EffectiveFocuserBacklash(
      steps: operatorEnteredSteps,
      origin: FocuserBacklashOrigin.operatorEntered,
      provenance: _operatorProvenance,
    );
  }
  if (measured == null || !measured.isUsable) {
    return const EffectiveFocuserBacklash(
      steps: 0,
      origin: FocuserBacklashOrigin.none,
      provenance:
          'this focuser has not been measured and you have not entered a '
          'figure',
    );
  }
  if (!measured.measurable) {
    return EffectiveFocuserBacklash(
      steps: 0,
      origin: FocuserBacklashOrigin.none,
      provenance:
          'no backlash larger than '
          '${_formatSteps(measured.resolutionLimitSteps)} steps was '
          'detectable when this focuser was ${_measuredPhrase(measured)}',
    );
  }
  return EffectiveFocuserBacklash(
    steps: measured.steps,
    origin: FocuserBacklashOrigin.measured,
    provenance: _measuredPhrase(measured),
    record: measured,
  );
}

/// `measured on 2026-09-14 at position 6620, 14.5 °C`.
///
/// The position is never left out: backlash varies along the travel (105 steps
/// at 6600 against 83 at 2500 on the same focuser), so a figure quoted without
/// where it was taken claims more than the measurement supports.
String _measuredPhrase(FocuserBacklashCalibrationRecord record) {
  final temperature = record.temperatureCelsius;
  final at = temperature == null
      ? ''
      : ', ${temperature.toStringAsFixed(1)} °C';
  return 'measured on ${_formatDate(record.measuredAt)} at position '
      '${record.measuredAtPosition}$at';
}

String _formatDate(DateTime value) {
  final local = value.toLocal();
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}

String _formatSteps(double value) => value == value.roundToDouble()
    ? value.round().toString()
    : value.toStringAsFixed(1);
