import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Pins the load-bearing [NightshadeIcons] semantic roles to their intended
/// Lucide glyphs. These are the canonical icon surface screens adopt during the
/// design-system migration; a silent re-point would shift every adopting call
/// site at once, so the key device/status/action roles are locked here.
///
/// Mapping table of record: docs/design/icon-migration-map.md.
void main() {
  group('NightshadeIcons device roles → Lucide glyphs', () {
    test('equipment roles are wired to their intended glyphs', () {
      expect(NightshadeIcons.camera, LucideIcons.camera);
      expect(NightshadeIcons.mount, LucideIcons.mountain);
      expect(NightshadeIcons.focuser, LucideIcons.focus);
      expect(NightshadeIcons.filterWheel, LucideIcons.disc);
      expect(NightshadeIcons.guider, LucideIcons.crosshair);
      expect(NightshadeIcons.rotator, LucideIcons.rotateCw);
      expect(NightshadeIcons.dome, LucideIcons.warehouse);
      expect(NightshadeIcons.cover, LucideIcons.doorOpen);
      expect(NightshadeIcons.switch_, LucideIcons.toggleLeft);
    });
  });

  group('NightshadeIcons status roles → Lucide glyphs', () {
    test('status roles are wired to their intended glyphs', () {
      expect(NightshadeIcons.warning, LucideIcons.alertTriangle);
      expect(NightshadeIcons.error, LucideIcons.xCircle);
      expect(NightshadeIcons.success, LucideIcons.checkCircle);
      expect(NightshadeIcons.info, LucideIcons.info);
    });

    test('status roles are distinct from one another', () {
      final glyphs = <int>{
        NightshadeIcons.warning.codePoint,
        NightshadeIcons.error.codePoint,
        NightshadeIcons.success.codePoint,
        NightshadeIcons.info.codePoint,
      };
      expect(glyphs.length, 4, reason: 'each status must read distinctly');
    });
  });

  group('NightshadeIcons action / navigation roles', () {
    test('common action roles are wired to their intended glyphs', () {
      expect(NightshadeIcons.add, LucideIcons.plus);
      expect(NightshadeIcons.delete, LucideIcons.trash2);
      expect(NightshadeIcons.edit, LucideIcons.pencil);
      expect(NightshadeIcons.refresh, LucideIcons.refreshCw);
      expect(NightshadeIcons.search, LucideIcons.search);
      expect(NightshadeIcons.close, LucideIcons.x);
      expect(NightshadeIcons.settings, LucideIcons.settings);
    });

    test('transport controls are wired to their intended glyphs', () {
      expect(NightshadeIcons.play, LucideIcons.play);
      expect(NightshadeIcons.pause, LucideIcons.pause);
      expect(NightshadeIcons.stop, LucideIcons.square);
    });

    test('disclosure chevrons are wired to their intended glyphs', () {
      expect(NightshadeIcons.chevronDown, LucideIcons.chevronDown);
      expect(NightshadeIcons.chevronUp, LucideIcons.chevronUp);
      expect(NightshadeIcons.chevronLeft, LucideIcons.chevronLeft);
      expect(NightshadeIcons.chevronRight, LucideIcons.chevronRight);
    });
  });

  group('NightshadeIcons weather / data roles', () {
    test('weather + data roles are wired to their intended glyphs', () {
      expect(NightshadeIcons.weather, LucideIcons.cloudSun);
      expect(NightshadeIcons.cloud, LucideIcons.cloud);
      expect(NightshadeIcons.moon, LucideIcons.moon);
      expect(NightshadeIcons.disk, LucideIcons.hardDrive);
      expect(NightshadeIcons.database, LucideIcons.database);
    });
  });
}
