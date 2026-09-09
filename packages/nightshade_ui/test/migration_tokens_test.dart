import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Pins the migration tokens added so the per-directory screen migration could
/// swap `BorderRadius.circular(8)` / `fontSize: 13` for a NAMED token. The
/// font-size half is still value-preserving and still locked below.
///
/// The RADIUS half no longer is. The Observatory design pass those tokens were
/// waiting for has landed (`docs/design/overhaul/03-tokens.md` §3.2): there are
/// four radii — 4, 6, 8, 12 — and every `radiusInline*` now forwards to the one
/// it maps to, so the 979 call sites take the new value without an edit. What
/// this group locks is therefore no longer "each token equals its old literal"
/// but "each token equals the scale value it folds onto", which is what wave 4
/// will sed-replace them with.
///
/// Mapping table of record: docs/design/overhaul/03-tokens.md §3.2.
void main() {
  group('In-use radius tokens fold onto the Observatory scale', () {
    test('the scale is the four values and nothing else', () {
      expect(NightshadeTokens.radiusXs, 4.0);
      expect(NightshadeTokens.radiusSm, 6.0);
      expect(NightshadeTokens.radiusMd, 6.0);
      expect(NightshadeTokens.radiusButton, 6.0);
      expect(NightshadeTokens.radiusLg, 8.0);
      expect(NightshadeTokens.radiusXl, 12.0);
      expect(NightshadeTokens.radiusFull, 999.0);
    });

    test('every migration alias equals its wave-4 replacement', () {
      expect(NightshadeTokens.radiusInline2, NightshadeTokens.radiusXs);
      expect(NightshadeTokens.radiusInline4, NightshadeTokens.radiusXs);
      expect(NightshadeTokens.radiusInline8, NightshadeTokens.radiusLg);
      expect(NightshadeTokens.radiusInline9, NightshadeTokens.radiusLg);
      expect(NightshadeTokens.radiusInline11, NightshadeTokens.radiusXl);
    });

    test('convenience BorderRadius objects match their double tokens', () {
      expect(
        NightshadeTokens.borderRadiusInline2,
        BorderRadius.circular(NightshadeTokens.radiusInline2),
      );
      expect(
        NightshadeTokens.borderRadiusInline4,
        BorderRadius.circular(NightshadeTokens.radiusInline4),
      );
      expect(
        NightshadeTokens.borderRadiusInline8,
        BorderRadius.circular(NightshadeTokens.radiusInline8),
      );
      expect(
        NightshadeTokens.borderRadiusInline9,
        BorderRadius.circular(NightshadeTokens.radiusInline9),
      );
      expect(
        NightshadeTokens.borderRadiusInline11,
        BorderRadius.circular(NightshadeTokens.radiusInline11),
      );
    });
  });

  group('In-use font-size tokens are exact-valued', () {
    test('every in-use fontSize literal has an exact token', () {
      expect(NightshadeTypography.fontSize8, 8.0);
      expect(NightshadeTypography.fontSize9, 9.0);
      expect(NightshadeTypography.fontSize9_5, 9.5);
      expect(NightshadeTypography.fontSize10, 10.0);
      expect(NightshadeTypography.fontSize11, 11.0);
      expect(NightshadeTypography.fontSize11_5, 11.5);
      expect(NightshadeTypography.fontSize12, 12.0);
      expect(NightshadeTypography.fontSize12_5, 12.5);
      expect(NightshadeTypography.fontSize13, 13.0);
      expect(NightshadeTypography.fontSize14, 14.0);
      expect(NightshadeTypography.fontSize15, 15.0);
      expect(NightshadeTypography.fontSize16, 16.0);
      expect(NightshadeTypography.fontSize17, 17.0);
      expect(NightshadeTypography.fontSize18, 18.0);
      expect(NightshadeTypography.fontSize20, 20.0);
      expect(NightshadeTypography.fontSize22, 22.0);
      expect(NightshadeTypography.fontSize24, 24.0);
      expect(NightshadeTypography.fontSize26, 26.0);
      expect(NightshadeTypography.fontSize28, 28.0);
    });

    test(
      'numeric tokens agree with the named styles that share their size',
      () {
        // The mapping table says these named styles ARE these sizes; keep that
        // true so a migration can pick either form interchangeably.
        expect(
          NightshadeTypography.overline.fontSize,
          NightshadeTypography.fontSize10,
        );
        expect(
          NightshadeTypography.captionSm.fontSize,
          NightshadeTypography.fontSize11,
        );
        expect(
          NightshadeTypography.caption.fontSize,
          NightshadeTypography.fontSize12,
        );
        expect(
          NightshadeTypography.bodySm.fontSize,
          NightshadeTypography.fontSize13,
        );
        expect(
          NightshadeTypography.body.fontSize,
          NightshadeTypography.fontSize14,
        );
        expect(
          NightshadeTypography.h4.fontSize,
          NightshadeTypography.fontSize16,
        );
        expect(
          NightshadeTypography.telemetryMd.fontSize,
          NightshadeTypography.fontSize18,
        );
        expect(
          NightshadeTypography.h3.fontSize,
          NightshadeTypography.fontSize20,
        );
        expect(
          NightshadeTypography.telemetryLg.fontSize,
          NightshadeTypography.fontSize22,
        );
        expect(
          NightshadeTypography.h2.fontSize,
          NightshadeTypography.fontSize24,
        );
      },
    );

    test('semibold-small inline combos fold onto named roles', () {
      // The migration map folds inline TextStyle(fontSize:, fontWeight:) combos
      // onto these roles; lock the (size + weight) of the two NEW roles added
      // for the semibold-small gap so the fold target stays correct.
      expect(
        NightshadeTypography.labelStrong.fontSize,
        NightshadeTypography.fontSize13,
      );
      expect(NightshadeTypography.labelStrong.fontWeight, FontWeight.w600);
      expect(
        NightshadeTypography.labelStrongSm.fontSize,
        NightshadeTypography.fontSize11,
      );
      expect(NightshadeTypography.labelStrongSm.fontWeight, FontWeight.w600);
    });
  });

  group('Semantic color coverage for migration', () {
    test('standard semantic roles exist on every built-in palette', () {
      for (final colors in [
        NightshadeColors.dark,
        NightshadeColors.light,
        NightshadeColors.redNight,
      ]) {
        // The migration map maps raw Colors.* onto these roles; they must all
        // be present (compile-time guaranteed by the type, asserted for intent).
        expect(colors.error, isA<Color>());
        expect(colors.warning, isA<Color>());
        expect(colors.success, isA<Color>());
        expect(colors.info, isA<Color>());
        expect(colors.textPrimary, isA<Color>());
        expect(colors.textSecondary, isA<Color>());
        expect(colors.textMuted, isA<Color>());
        expect(colors.accent, isA<Color>());
        expect(colors.surface, isA<Color>());
        expect(colors.border, isA<Color>());
      }
    });
  });
}
