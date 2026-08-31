import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// The light palette's contrast floor, enforced instead of documented.
///
/// The four status roles were tuned against `surface` — plain white, the
/// LIGHTEST thing they ever land on — and the roles that passed there failed on
/// every card. Sampled off the running app in the Darkroom, the light theme's
/// "Applied by the last render" measured `#2A7F4F` on the step card's
/// `#EEF1F4` at 4.36:1, under the 4.5:1 AA floor for text below 18.66px, with
/// `info` at 4.27 and `error` at 4.11 on the same surface. Dark and red night
/// both cleared it on the same string, so this was the palette and not the
/// screen.
///
/// The arithmetic lives here, in the shape `red_night_contrast_test.dart`
/// already established: a prose floor cannot fail a build.
void main() {
  const colors = NightshadeColors.light;

  /// WCAG 2.x contrast ratio. [Color.computeLuminance] is the same relative
  /// luminance the standard defines, so the ratio is the standard's verbatim.
  double contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final lighter = la > lb ? la : lb;
    final darker = la > lb ? lb : la;
    return (lighter + 0.05) / (darker + 0.05);
  }

  /// Every surface a body of text can land on in this palette.
  ///
  /// `surfaceHover` is in the list because `NightshadeCard` paints it under the
  /// card's whole contents whenever the pointer is over one — the text on a
  /// hovered card is the same text, and it is the darkest ground the palette
  /// puts it on, so it is what the floor is decided by.
  const surfaces = <String, Color>{
    'background': Color(0xFFF4F6F8),
    'surface': Color(0xFFFFFFFF),
    'surfaceAlt': Color(0xFFEEF1F4),
    'surfaceHover': Color(0xFFE4E8EC),
    'surfaceElevated': Color(0xFFFFFFFF),
    'surfaceOverlay': Color(0xFFFFFFFF),
  };

  /// The tokens this palette hands to a `Text` or `Icon` colour: the three-level
  /// text ladder plus the four status semantics. `primary` and `accent` are
  /// fill tokens, paired with [NightshadeColors.onPrimary] rather than a
  /// surface, so they are not measured against one here.
  final textRoles = <String, Color>{
    'textPrimary': colors.textPrimary,
    'textSecondary': colors.textSecondary,
    'textMuted': colors.textMuted,
    'success': colors.success,
    'warning': colors.warning,
    'error': colors.error,
    'info': colors.info,
  };

  group('light text contrast', () {
    for (final role in textRoles.entries) {
      test('${role.key} clears 4.5:1 on every surface level', () {
        for (final surface in surfaces.entries) {
          final ratio = contrast(role.value, surface.value);
          expect(
            ratio,
            greaterThanOrEqualTo(4.5),
            reason:
                '${role.key} on ${surface.key} measures '
                '${ratio.toStringAsFixed(2)}:1, under the 4.5:1 floor this '
                'palette documents',
          );
        }
      });
    }

    /// The exact pair the audit sampled, pinned so a regression report can be
    /// compared to it directly rather than re-derived.
    test('the sampled pair — success on the step card — is measured', () {
      const card = Color(0xFFEEF1F4);
      expect(surfaces['surfaceAlt'], card);
      final ratio = contrast(colors.success, card);
      expect(
        ratio,
        greaterThanOrEqualTo(4.5),
        reason:
            'the Darkroom step card\'s "Applied by the last render" '
            'measured 4.36:1 here before this floor existed; it is now '
            '${ratio.toStringAsFixed(2)}:1',
      );
    });

    /// The status roles are the ones that moved, so their direction is stated:
    /// each one is DARKER than the ground it is read on, in a light palette,
    /// and none of them drifted into another role's hue while being fixed.
    test('the status roles stay distinguishable from each other', () {
      final statuses = <String, Color>{
        'success': colors.success,
        'warning': colors.warning,
        'error': colors.error,
        'info': colors.info,
      };
      for (final a in statuses.entries) {
        expect(
          a.value.computeLuminance(),
          lessThan(surfaces['surfaceHover']!.computeLuminance()),
          reason: '${a.key} is drawn as ink on a light ground',
        );
        for (final b in statuses.entries) {
          if (a.key == b.key) continue;
          expect(
            a.value,
            isNot(b.value),
            reason:
                '${a.key} and ${b.key} would state two different '
                'outcomes in one colour',
          );
        }
      }
    });
  });
}
