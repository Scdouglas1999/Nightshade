import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart';
import '../../../utils/snackbar_helper.dart';
import 'panel_widgets.dart';

class CameraPanel extends ConsumerStatefulWidget {
  final NightshadeColors colors;

  const CameraPanel({super.key, required this.colors});

  @override
  ConsumerState<CameraPanel> createState() => _CameraPanelState();
}

class _CameraPanelState extends ConsumerState<CameraPanel> {
  bool _isCooling = false; // Only for UI loading state

  @override
  Widget build(BuildContext context) {
    final cameraState = ref.watch(cameraStateProvider);
    final coolingSettings = ref.watch(coolingSettingsProvider);
    final coolingStatus = ref.watch(coolingStatusProvider);
    final exposureSettings = ref.watch(exposureSettingsProvider);
    // Use target temp from provider (persists across navigation)
    final targetTemp = cameraState.targetTemp;

    final isConnected =
        cameraState.connectionState == DeviceConnectionState.connected;

    // Watch camera capabilities to gate UI features
    final capabilitiesAsync =
        ref.watch(cameraCapabilitiesProvider(cameraState.deviceId ?? ''));
    final capabilities = capabilitiesAsync.valueOrNull;
    final capabilitiesLoading = capabilitiesAsync.isLoading;
    final hasCoolingTelemetry = cameraState.temperature != null ||
        cameraState.coolerPower != null ||
        cameraState.isCooling;
    // Show cooling controls when support is known, still loading, or live
    // telemetry confirms cooling is active.
    final showCoolingSection = isConnected &&
        (capabilitiesLoading ||
            (capabilities?.canSetCcdTemperature == true) ||
            hasCoolingTelemetry);
    // Cooler target-temperature slider range. Prefer the camera's reported
    // operating range; fall back to a conservative -30..20°C window when caps
    // are unknown or when a driver reports a nonsensical range (min >= max).
    const double kDefaultCoolerMinTempC = -30;
    const double kDefaultCoolerMaxTempC = 20;
    final double? capCoolerMin = capabilities?.coolerMinTempC;
    final double? capCoolerMax = capabilities?.coolerMaxTempC;
    // Only honor the reported range when both bounds are present AND sane
    // (min < max). A nonsensical range from buggy driver data falls back to
    // the conservative default window rather than feeding the slider an
    // inverted range.
    final bool hasValidCoolerRange = capCoolerMin != null &&
        capCoolerMax != null &&
        capCoolerMin < capCoolerMax;
    final double coolerMinTempC =
        hasValidCoolerRange ? capCoolerMin : kDefaultCoolerMinTempC;
    final double coolerMaxTempC =
        hasValidCoolerRange ? capCoolerMax : kDefaultCoolerMaxTempC;

    // If capabilities are unavailable, infer controls from live camera telemetry
    // to avoid blocking devices that omit explicit capability reporting.
    final canSetGain = capabilities?.canSetGain ?? (cameraState.gain != null);
    final canSetOffset =
        capabilities?.canSetOffset ?? (cameraState.offset != null);

    // Get binning options based on camera capabilities
    final binningOptions = ref.watch(
      cameraBinningOptionsProvider(cameraState.deviceId ?? ''),
    );

    // Ensure current binning value is valid for available options
    final currentBinning = binningOptions.contains(exposureSettings.binning)
        ? exposureSettings.binning
        : binningOptions.first;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Connection status
          if (!isConnected)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: NightshadeDecorations.emphasisSurface(
                widget.colors.warning,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.alertCircle,
                      size: 16, color: widget.colors.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'No camera connected',
                      style:
                          TextStyle(fontSize: 12, color: widget.colors.warning),
                    ),
                  ),
                ],
              ),
            ),

          // Cooling Section - show if camera supports cooling or while loading capabilities
          if (showCoolingSection)
            PanelSection(
              title: 'Cooling',
              colors: widget.colors,
              child: Column(
                children: [
                  // Current temperature display
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Current',
                          style: TextStyle(
                              fontSize: 12,
                              color: widget.colors.textSecondary)),
                      Row(
                        children: [
                          Text(
                            isConnected && cameraState.temperature != null
                                ? '${cameraState.temperature!.toStringAsFixed(1)}°C'
                                : '---',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: widget.colors.textPrimary,
                            ),
                          ),
                          if (isConnected && coolingStatus.isCooling)
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Icon(
                                coolingStatus.isAtTarget
                                    ? LucideIcons.checkCircle2
                                    : LucideIcons.arrowDown,
                                size: 14,
                                color: coolingStatus.isAtTarget
                                    ? widget.colors.success
                                    : widget.colors.primary,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Power',
                          style: TextStyle(
                              fontSize: 12,
                              color: widget.colors.textSecondary)),
                      Text(
                        isConnected && cameraState.coolerPower != null
                            ? '${cameraState.coolerPower!.toStringAsFixed(0)}%'
                            : '---',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: widget.colors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  if (isConnected && coolingStatus.isCooling)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Target',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: widget.colors.textSecondary)),
                          Text(
                            '${coolingStatus.targetTemp.toStringAsFixed(1)}°C',
                            style: TextStyle(
                              fontSize: 12,
                              color: widget.colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),

                  // Target temperature slider
                  SliderRowInteractive(
                    label: 'Target Temperature',
                    value: targetTemp.clamp(coolerMinTempC, coolerMaxTempC),
                    min: coolerMinTempC,
                    max: coolerMaxTempC,
                    suffix: '°C',
                    colors: widget.colors,
                    onChanged: isConnected
                        ? (value) {
                            // Update provider so value persists across navigation
                            ref
                                .read(cameraStateProvider.notifier)
                                .setTargetTemp(value);
                            // Also update settings provider for consistency
                            ref.read(coolingSettingsProvider.notifier).state =
                                coolingSettings.copyWith(targetTemp: value);
                          }
                        : null,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: SmallButton(
                          label: _isCooling ? 'Setting...' : 'Cool Down',
                          icon: LucideIcons.snowflake,
                          colors: widget.colors,
                          isEnabled: isConnected && !_isCooling,
                          onTap: () async {
                            setState(() => _isCooling = true);
                            try {
                              await ref
                                  .read(deviceServiceProvider)
                                  .setCameraCooling(
                                    enabled: true,
                                    targetTemp: targetTemp,
                                  );

                              // Update settings state
                              ref.read(coolingSettingsProvider.notifier).state =
                                  coolingSettings.copyWith(
                                      enabled: true, targetTemp: targetTemp);
                              // Update camera state
                              ref
                                  .read(cameraStateProvider.notifier)
                                  .setCooling(true);
                            } catch (e) {
                              if (!context.mounted) return;
                              context.showErrorSnackBar(
                                  'Failed to set cooling: $e');
                            } finally {
                              if (mounted) setState(() => _isCooling = false);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SmallButton(
                          label: 'Warm Up',
                          icon: LucideIcons.flame,
                          isOutline: true,
                          colors: widget.colors,
                          isEnabled: isConnected,
                          onTap: () async {
                            try {
                              await ref
                                  .read(deviceServiceProvider)
                                  .setCameraCooling(
                                    enabled: false,
                                  );

                              ref.read(coolingSettingsProvider.notifier).state =
                                  coolingSettings.copyWith(enabled: false);
                              ref
                                  .read(cameraStateProvider.notifier)
                                  .setCooling(false);
                            } catch (e) {
                              if (!context.mounted) return;
                              context.showErrorSnackBar(
                                  'Failed to turn off cooler: $e');
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          // Show "not supported" message when camera is connected and capabilities confirm no cooling support
          if (isConnected &&
              !capabilitiesLoading &&
              !capabilitiesAsync.hasError &&
              capabilities != null &&
              !capabilities.canSetCcdTemperature)
            PanelSection(
              title: 'Cooling',
              colors: widget.colors,
              child: Text(
                'Cooling not supported by this camera',
                style: TextStyle(
                  fontSize: 12,
                  color: widget.colors.textSecondary,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          const SizedBox(height: 20),

          // Sensor Settings
          PanelSection(
            title: 'Sensor',
            colors: widget.colors,
            child: Column(
              children: [
                DropdownRow(
                  label: 'Binning',
                  value: currentBinning,
                  items: binningOptions,
                  colors: widget.colors,
                  onChanged: isConnected
                      ? (value) {
                          if (value != null) {
                            final parts = value.split('x');
                            ref.read(exposureSettingsProvider.notifier).state =
                                exposureSettings.copyWith(
                              binningX: int.parse(parts[0]),
                              binningY: int.parse(parts[1]),
                            );
                            ref
                                .read(exposureSettingsUserDirtyProvider.notifier)
                                .state = true;
                          }
                        }
                      : null,
                ),
                // Read Mode is driver-reported. Hide the row entirely when the
                // camera exposes no readout modes (matches the hide-when-
                // unsupported pattern used for unsupported device features);
                // there is intentionally no synthetic binary fallback.
                if ((capabilities?.readoutModes ?? const []).isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Builder(
                    builder: (context) {
                      final readoutModes = capabilities!.readoutModes;
                      final selectedIndex = exposureSettings
                          .resolveReadoutModeIndex(readoutModes.length)
                          .clamp(0, readoutModes.length - 1);
                      return DropdownRow(
                        label: 'Read Mode',
                        value: readoutModes[selectedIndex],
                        items: readoutModes,
                        colors: widget.colors,
                        onChanged: isConnected
                            ? (value) async {
                                if (value == null) return;
                                final idx = readoutModes.indexOf(value);
                                if (idx < 0) return;
                                ref
                                    .read(exposureSettingsProvider.notifier)
                                    .state = exposureSettings.copyWith(
                                  readoutModeIndex: idx,
                                  fastReadout: idx == readoutModes.length - 1,
                                );
                                ref
                                    .read(exposureSettingsUserDirtyProvider
                                        .notifier)
                                    .state = true;
                                final deviceId = cameraState.deviceId;
                                if (deviceId == null) return;
                                // Errors are a feature: surface a failed driver
                                // call rather than silently dropping it.
                                try {
                                  await ref
                                      .read(deviceBackendProvider)
                                      .cameraSetReadoutMode(deviceId, idx);
                                } catch (e) {
                                  if (!context.mounted) return;
                                  context.showErrorSnackBar(
                                      'Failed to set read mode: $e');
                                }
                              }
                            : null,
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Gain/Offset - only show if camera supports these features
          if (canSetGain || canSetOffset)
            PanelSection(
              title: 'Gain / Offset',
              colors: widget.colors,
              child: Column(
                children: [
                  // Only show gain control if camera supports it
                  if (canSetGain)
                    InputRowEditable(
                      label:
                          'Gain${capabilities?.gainMin != null ? ' (${capabilities!.gainMin}-${capabilities.gainMax})' : ''}',
                      value: exposureSettings.gain.toString(),
                      colors: widget.colors,
                      onChanged: (value) {
                        final parsed = int.tryParse(value);
                        if (parsed != null && parsed >= 0) {
                          // Clamp to valid range if capabilities available
                          final clamped = capabilities?.gainMin != null
                              ? parsed.clamp(
                                  capabilities!.gainMin!, capabilities.gainMax!)
                              : parsed;
                          ref.read(exposureSettingsProvider.notifier).state =
                              exposureSettings.copyWith(gain: clamped);
                          ref
                              .read(exposureSettingsUserDirtyProvider.notifier)
                              .state = true;
                        }
                      },
                    ),
                  if (canSetGain && canSetOffset) const SizedBox(height: 12),
                  // Only show offset control if camera supports it
                  if (canSetOffset)
                    InputRowEditable(
                      label:
                          'Offset${capabilities?.offsetMin != null ? ' (${capabilities!.offsetMin}-${capabilities.offsetMax})' : ''}',
                      value: exposureSettings.offset.toString(),
                      colors: widget.colors,
                      onChanged: (value) {
                        final parsed = int.tryParse(value);
                        if (parsed != null && parsed >= 0) {
                          // Clamp to valid range if capabilities available
                          final clamped = capabilities?.offsetMin != null
                              ? parsed.clamp(capabilities!.offsetMin!,
                                  capabilities.offsetMax!)
                              : parsed;
                          ref.read(exposureSettingsProvider.notifier).state =
                              exposureSettings.copyWith(offset: clamped);
                          ref
                              .read(exposureSettingsUserDirtyProvider.notifier)
                              .state = true;
                        }
                      },
                    ),
                ],
              ),
            ),
          const SizedBox(height: 20),
          const DebayeringCard(),
        ],
      ),
    );
  }
}

class DebayeringCard extends ConsumerWidget {
  const DebayeringCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.nightshadeColors;
    final debayerEnabled = ref.watch(debayerEnabledProvider);
    final bayerPattern = ref.watch(bayerPatternProvider);
    final debayerAlgorithm = ref.watch(debayerAlgorithmProvider);

    return PanelSection(
      title: 'Debayering',
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Enable Debayering',
                style: TextStyle(
                  fontSize: 12,
                  color: colors.textSecondary,
                ),
              ),
              NightshadeSwitch(
                value: debayerEnabled,
                onChanged: (value) {
                  ref.read(debayerEnabledProvider.notifier).state = value;
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Enable for color cameras to convert raw Bayer data to RGB',
            style: TextStyle(fontSize: 10, color: colors.textMuted),
          ),
          const SizedBox(height: 16),

          // Algorithm selection
          DropdownRow(
            label: 'Algorithm',
            value: debayerAlgorithm.displayName,
            items: DebayerAlgorithm.values.map((a) => a.displayName).toList(),
            colors: colors,
            onChanged: debayerEnabled
                ? (value) {
                    if (value != null) {
                      final algorithm = DebayerAlgorithm.values.firstWhere(
                        (a) => a.displayName == value,
                        orElse: () => DebayerAlgorithm.bilinear,
                      );
                      ref.read(debayerAlgorithmProvider.notifier).state =
                          algorithm;
                    }
                  }
                : null,
          ),
          const SizedBox(height: 12),

          // Bayer pattern selection
          DropdownRow(
            label: 'Pattern',
            value: bayerPattern.displayName,
            items: BayerPattern.values.map((p) => p.displayName).toList(),
            colors: colors,
            onChanged: debayerEnabled
                ? (value) {
                    if (value != null) {
                      final pattern = BayerPattern.values.firstWhere(
                        (p) => p.displayName == value,
                        orElse: () => BayerPattern.rggb,
                      );
                      ref.read(bayerPatternProvider.notifier).state = pattern;
                    }
                  }
                : null,
          ),
          const SizedBox(height: 12),

          // Auto-detect option
          Consumer(
            builder: (context, ref, _) {
              final autoDetect = ref.watch(autoDetectBayerPatternProvider);
              return Row(
                children: [
                  NightshadeCheckbox(
                    value: autoDetect,
                    onChanged: debayerEnabled
                        ? (v) {
                            ref
                                .read(autoDetectBayerPatternProvider.notifier)
                                .state = v ?? false;
                          }
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Auto-detect from FITS header',
                      style: TextStyle(
                        fontSize: 12,
                        color: debayerEnabled
                            ? colors.textSecondary
                            : colors.textMuted,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
