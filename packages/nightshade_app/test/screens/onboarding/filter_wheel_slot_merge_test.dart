// Unit tests for the onboarding filter-wheel slot/name seeding rule.
//
// Regression for the ZWO EFW bug: onboarding used to render a hardcoded 5
// slots regardless of the connected wheel. The fix reads the driver's real
// slot count + names; `mergeFilterSlotNames` is the pure core of that rule —
// the result must always have the DEVICE's slot count, while preserving any
// names the user already typed in the draft.

import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/onboarding/steps/filter_wheel_step.dart';

void main() {
  group('mergeFilterSlotNames', () {
    test('uses the driver slot count, not the draft length (8-slot EFW)', () {
      // An 8-position EFW reports 8 names; an empty/short draft must NOT shrink
      // it to 5 (the old hardcoded default) or to the draft length.
      final driver = List.generate(8, (i) => 'Filter ${i + 1}');
      final merged = mergeFilterSlotNames(driver, const <String>[]);
      expect(merged.length, 8);
      expect(merged, driver);
    });

    test('preserves user-entered draft names for the slots they cover', () {
      final driver = List.generate(8, (i) => 'Filter ${i + 1}');
      final draft = ['Ha', 'OIII', 'SII']; // user named the first three
      final merged = mergeFilterSlotNames(driver, draft);
      expect(merged.length, 8, reason: 'count follows the device');
      expect(merged.take(3).toList(), ['Ha', 'OIII', 'SII']);
      // Remaining slots fall back to the driver names.
      expect(merged.sublist(3), driver.sublist(3));
    });

    test('blank/whitespace draft entries fall back to the driver name', () {
      final driver = ['Lum', 'Red', 'Green'];
      final draft = ['', '   ', 'G-custom'];
      final merged = mergeFilterSlotNames(driver, draft);
      expect(merged, ['Lum', 'Red', 'G-custom']);
    });

    test('a draft longer than the device is truncated to the device count', () {
      final driver = ['A', 'B']; // 2-slot wheel
      final draft = ['one', 'two', 'three', 'four'];
      final merged = mergeFilterSlotNames(driver, draft);
      expect(merged, ['one', 'two']);
    });
  });
}
