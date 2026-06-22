// Dual-rig / multi-camera synchronized imaging — Secondary Rig card.
//
// A small, additive card for configuring + running a secondary (piggyback)
// camera that captures its own exposure loop alongside the primary sequence,
// coordinated with the primary's dithers natively. v1 scope: same mount, no
// secondary guiding/dither/plate-solve/autofocus.
//
// Strings are intentionally hardcoded English (a concurrent i18n pass extracts
// them later). Kept self-contained so it can be dropped into the sequencer or
// equipment area without touching surrounding layout.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart' as bridge_api;
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

class SecondaryRigCard extends ConsumerWidget {
  const SecondaryRigCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(secondaryRigConfigProvider);
    final notifier = ref.read(secondaryRigConfigProvider.notifier);
    final statusAsync = ref.watch(secondaryRigStatusProvider);
    final camerasAsync = ref.watch(availableCamerasProvider);
    final theme = Theme.of(context);

    final status = statusAsync.value;
    final isRunning = status?.running ?? false;

    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.camera_alt_outlined, size: 20),
                const SizedBox(width: 8),
                Text('Secondary Rig', style: theme.textTheme.titleMedium),
                const Spacer(),
                if (status != null) _StatusBadge(status: status),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Piggyback camera on the same mount. Pauses during dithers.',
              style: theme.textTheme.bodySmall,
            ),
            const Divider(height: 24),

            // Camera selection.
            camerasAsync.when(
              data: (cameras) => DropdownButtonFormField<String>(
                initialValue: config.cameraId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Secondary camera',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  for (final cam in cameras)
                    DropdownMenuItem(value: cam.id, child: Text(cam.name)),
                ],
                onChanged: isRunning ? null : notifier.setCamera,
              ),
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text(
                'Cameras unavailable.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ),
            const SizedBox(height: 12),

            // Exposure + bin row.
            Row(
              children: [
                Expanded(
                  child: _NumberField(
                    label: 'Exposure (s)',
                    value: config.exposureSecs,
                    enabled: !isRunning,
                    onChanged: (v) => notifier.setExposure(v),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _NumberField(
                    label: 'Gain',
                    value: config.gain?.toDouble(),
                    enabled: !isRunning,
                    onChanged: (v) => notifier.setGain(v.round()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Frame count + dither policy row.
            Row(
              children: [
                Expanded(
                  child: _NumberField(
                    label: 'Frames (blank = until end)',
                    value: config.frameCount?.toDouble(),
                    enabled: !isRunning,
                    onChanged: (v) =>
                        notifier.setFrameCount(v <= 0 ? null : v.round()),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<SecondaryDitherPolicy>(
                    initialValue: config.ditherPolicy,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'On dither',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      for (final p in SecondaryDitherPolicy.values)
                        DropdownMenuItem(value: p, child: Text(p.label)),
                    ],
                    onChanged: isRunning
                        ? null
                        : (p) {
                            if (p != null) notifier.setDitherPolicy(p);
                          },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Controls.
            Row(
              children: [
                if (!isRunning)
                  FilledButton.icon(
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Start secondary'),
                    onPressed:
                        config.isValid ? () => _start(context, ref) : null,
                  )
                else
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop secondary'),
                    onPressed: () => _stop(context, ref),
                  ),
                const SizedBox(width: 8),
                if (status != null)
                  Flexible(
                    child: Text(
                      '${status.framesCaptured} captured'
                      '${status.framesAborted > 0 ? ' · ${status.framesAborted} aborted' : ''}',
                      style: theme.textTheme.bodySmall,
                      textAlign: TextAlign.end,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
            if (status?.lastError != null) ...[
              const SizedBox(height: 8),
              Text(
                status!.lastError!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _start(BuildContext context, WidgetRef ref) async {
    try {
      // v1: no automatic target/save-path inheritance from the UI — the
      // headless/start-with-context path can pass those. Here we arm with
      // whatever the primary save path is, if discoverable.
      await ref
          .read(secondaryRigControllerProvider)
          .start(const SecondaryRigStartContext());
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not start secondary rig: $e')),
        );
      }
    }
  }

  Future<void> _stop(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(secondaryRigControllerProvider).stop();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not stop secondary rig: $e')),
        );
      }
    }
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final bridge_api.SecondaryRigStatusApi status;

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final (label, color) = switch (status) {
      _ when status.waitingForDither => ('Paused (dither)', colors.warning),
      _ when status.exposing => ('Exposing', colors.success),
      _ when status.running => ('Running', colors.success),
      _ => ('Idle', colors.textMuted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusFull),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });
  final String label;
  final double? value;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      enabled: enabled,
      initialValue: value == null
          ? ''
          : (value == value!.roundToDouble()
              ? value!.toInt().toString()
              : value!.toString()),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      onChanged: (text) {
        final parsed = double.tryParse(text.trim());
        if (parsed != null) onChanged(parsed);
        if (text.trim().isEmpty) onChanged(0);
      },
    );
  }
}
