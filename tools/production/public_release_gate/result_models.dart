// Part of ../public_release_gate.dart -- extracted for maintainability.
//
// Small immutable result models used by the conservative release gate.
part of '../public_release_gate.dart';

class _ExternalEvidenceResult {
  final bool passed;
  final String detail;

  const _ExternalEvidenceResult({required this.passed, required this.detail});
}

class _SplitPlanCoverage {
  final bool valid;
  final String detail;

  const _SplitPlanCoverage({required this.valid, required this.detail});
}

class _GateCheck {
  final String id;
  final String label;
  final bool passed;
  final String? evidence;
  final String detail;

  const _GateCheck({
    required this.id,
    required this.label,
    required this.passed,
    required this.evidence,
    required this.detail,
  });

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'passed': passed,
    'evidence': evidence,
    'detail': detail,
  };
}
