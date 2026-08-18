// The dawn Darkroom autopilot — the pass that runs after the masters exist.
//
// This page exists because the feature did not have one. `darkroom.auto_draft`
// was a raw `app_settings` row with no widget and no API, absent-means-on, and
// nothing in Settings mentioned the Darkroom at all: searching "darkroom",
// "draft", "recipe" and "auto draft" each returned "No settings match your
// search", and "dawn" returned only the sequencer's park control. One D1 night
// with that unmentioned default on produced 4 recipes, 4 draft JPEGs, 4
// `.nsrecipe` sidecars, a night report, 9 delivered files and a morning
// notification — none of which the operator had a control for, or was ever told
// about. The nearest switch, "Auto-integrate at end of run", describes only the
// master.
//
// So the whole chain is named here, in the order it runs, with the neighbours
// that can silence each link named too. The switch itself is the only thing
// this page writes.
//
// Remote clients: `darkroom.auto_draft` lives in the LOCAL profile database and
// the pass runs on the machine that integrated the masters. A phone driving a
// remote rig would be editing its own row, which governs nothing, so the page
// says where the setting lives rather than offering a switch for the wrong
// machine — the same stance the Delivery page takes for the same reason.
//
// That refusal reads the client ROLE, not the live connection. A desktop
// launched with `--remote-host` is that rig's client for the whole window
// before its first handshake lands, and again after every drop, and
// `isRemoteModeProvider` reads false through both. Gating on it offered the
// live switch there: one click wrote `darkroom.auto_draft=false` into a
// database no dawn job reads, while the rig it was pointed at kept drafting,
// delivering and notifying at dawn.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../session_review/auto_integration_service.dart';
import 'settings_widgets.dart';

/// Whether a finished run drafts itself.
///
/// Delegates to [AutoIntegrationService.isDarkroomAutoDraftEnabled] rather than
/// reading the row here: "absent means on, only the literal string `false`
/// turns it off, and an unreadable store reports on" is a contract with exactly
/// one definition, and a settings page that reimplemented it would be the
/// second one.
final darkroomAutoDraftEnabledProvider = FutureProvider.autoDispose<bool>((
  ref,
) async {
  return ref.watch(autoIntegrationServiceProvider).isDarkroomAutoDraftEnabled();
});

/// Writes the switch. `'true'` rather than deleting the row: an explicit value
/// says the operator decided, where absence only means nobody has yet.
class DarkroomAutoDraftActions {
  const DarkroomAutoDraftActions(this._ref);

  final Ref _ref;

  Future<void> setEnabled(bool enabled) async {
    await _ref
        .read(settingsDaoProvider)
        .setSetting(kDarkroomAutoDraftSettingKey, enabled.toString());
    _ref.invalidate(darkroomAutoDraftEnabledProvider);
  }
}

final darkroomAutoDraftActionsProvider = Provider(
  DarkroomAutoDraftActions.new,
);

/// Settings section for the dawn Darkroom pass.
class DarkroomAutopilotSettings extends ConsumerWidget {
  const DarkroomAutopilotSettings({super.key, this.isMobile = false});

  final bool isMobile;

  static const String _description =
      'What happens to a night after its masters are integrated: a first-draft '
      'recipe per master, a rendered draft, the night report, delivery, and one '
      'message in the morning.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(isRemoteClientProvider)) {
      return SettingsPage(
        title: 'Darkroom autopilot',
        description: _description,
        isMobile: isMobile,
        children: const [
          EmptyState(
            icon: LucideIcons.server,
            title: 'The dawn pass runs on the imaging host',
            body: 'The switch and the drafts it produces live in the imaging '
                'host\'s own database, and the pass runs there when its run '
                'finishes. Open Settings on the host to change it.',
          ),
        ],
      );
    }

    return SettingsPage(
      title: 'Darkroom autopilot',
      description: _description,
      isMobile: isMobile,
      children: [
        SettingsSection(
          title: 'At the end of a run',
          isMobile: isMobile,
          children: [
            SettingRow(
              icon: LucideIcons.sparkles,
              title: 'Draft, deliver and report at dawn',
              subtitle:
                  'When on, each master the night produced gets a first-draft '
                  'recipe composed for it, a draft render, an entry in the '
                  'night report, a copy to every delivery destination that '
                  'wants one, and one notification when it is all done. When '
                  'off, the masters are still integrated and nothing else '
                  'happens — the Darkroom waits for you.',
              trailing: const _AutoDraftSwitch(),
              isLast: true,
              isMobile: isMobile,
            ),
          ],
        ),
        SettingsSection(
          title: 'What can silence it',
          isMobile: isMobile,
          children: [
            _AutoIntegrateDependencyRow(isMobile: isMobile),
            SettingRow(
              icon: LucideIcons.send,
              title: 'Delivery destinations decide what leaves the rig',
              subtitle:
                  'The pass hands its masters, drafts and report to Delivery. '
                  'A destination with nothing selected receives nothing, and a '
                  'rig with no destinations keeps everything locally — the '
                  'drafts are still in the Darkroom either way. Settings › '
                  'Delivery.',
              trailing: const SizedBox.shrink(),
              isMobile: isMobile,
            ),
            SettingRow(
              icon: LucideIcons.bell,
              title: 'The morning message rides the sequence-complete alerts',
              subtitle:
                  'One notification goes out when the pass finishes, through '
                  'the same gates as any end-of-sequence alert. With '
                  'notifications off, or sequence-complete alerts off, the job '
                  'records that it was silenced and names the flag rather than '
                  'sending it another way. Settings › Notifications.',
              trailing: const SizedBox.shrink(),
              isLast: true,
              isMobile: isMobile,
            ),
          ],
        ),
      ],
    );
  }
}

/// The one control this page writes.
class _AutoDraftSwitch extends ConsumerStatefulWidget {
  const _AutoDraftSwitch();

  @override
  ConsumerState<_AutoDraftSwitch> createState() => _AutoDraftSwitchState();
}

class _AutoDraftSwitchState extends ConsumerState<_AutoDraftSwitch> {
  bool _saving = false;
  String? _error;

  Future<void> _set(bool value) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(darkroomAutoDraftActionsProvider).setEnabled(value);
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _error = 'Could not save the dawn autopilot setting: $error',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final setting = ref.watch(darkroomAutoDraftEnabledProvider);
    // Only the value it has actually read is offered as a state. A store that
    // could not be read reports ON, because that is what the pass itself will
    // do with the same unreadable row — the switch must not show `off` for a
    // feature that is about to run.
    final loadError = setting.hasError
        ? 'Could not read the dawn autopilot setting: ${setting.error}'
        : null;
    final control = NightshadeSwitch(
      key: const ValueKey('darkroom-auto-draft-switch'),
      value: setting.valueOrNull ?? true,
      enabled: setting.hasValue && !_saving,
      onChanged: _set,
    );
    final error = _error ?? loadError;
    return error == null ? control : Tooltip(message: error, child: control);
  }
}

/// The dependency that can make every switch on this page moot.
///
/// The dawn pass hangs off the post-session integration: no auto-integration
/// means no masters at the end of the run, and no masters means there is
/// nothing to draft. Stated with the neighbour's LIVE state, because "this
/// depends on another setting" is only useful next to what that setting says.
class _AutoIntegrateDependencyRow extends ConsumerWidget {
  const _AutoIntegrateDependencyRow({required this.isMobile});

  /// The page's own density flag. Hardcoding `false` here put one row at
  /// desktop padding, icon size and title ramp inside a phone-width section
  /// whose siblings were at phone density — three misalignments in one column.
  final bool isMobile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final integrate = ref.watch(autoIntegrationEnabledProvider);
    final (String state, Color color) = switch (integrate) {
      AsyncData(value: true) => ('on', colors.success),
      AsyncData(value: false) => ('off', colors.warning),
      AsyncError() => ('could not be read', colors.error),
      _ => ('reading…', colors.textMuted),
    };
    return SettingRow(
      icon: LucideIcons.layers,
      title: 'Auto-integrate has to be on for any of this to run',
      subtitle:
          'The dawn pass starts from the masters the post-session integration '
          'produces, so with "Auto-integrate at end of run" off nothing is '
          'drafted, delivered or reported — the switch above governs what '
          'happens next, not whether the night is integrated at all. It is '
          'currently $state. Settings › Image Grading › Post-session '
          'integration.',
      // The colour-coded echo is for the eye scanning the column. A screen
      // reader has already been told the state by the sentence above, so
      // publishing the echo as well adds a node named only "off" a column
      // away from the sentence that explains it.
      trailing: ExcludeSemantics(
        child: Text(
          state,
          style: NightshadeTypography.labelSm.copyWith(color: color),
        ),
      ),
      isMobile: isMobile,
    );
  }
}
