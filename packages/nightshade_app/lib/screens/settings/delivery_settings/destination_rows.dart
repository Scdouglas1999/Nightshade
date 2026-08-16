part of '../delivery_settings.dart';

/// Masked stand-in for a stored key. The keyring's value is written and never
/// read back into the UI, so this string is all the page can ever show.
const String kDeliverySecretPlaceholder = '•••••••• (stored in OS keyring)';

/// Icon for each transport.
IconData deliveryKindIcon(ArtifactDestinationKind kind) {
  switch (kind) {
    case ArtifactDestinationKind.watchedFolder:
      return LucideIcons.folder;
    case ArtifactDestinationKind.sftp:
      return LucideIcons.server;
    case ArtifactDestinationKind.peer:
      return LucideIcons.monitor;
  }
}

/// What each transport is called on screen.
String deliveryKindLabel(ArtifactDestinationKind kind) {
  switch (kind) {
    case ArtifactDestinationKind.watchedFolder:
      return 'Watched folder';
    case ArtifactDestinationKind.sftp:
      return 'SFTP';
    case ArtifactDestinationKind.peer:
      return 'Paired desktop pulls';
  }
}

/// The endpoint a destination writes to, rendered from its non-secret config.
String deliveryEndpointSummary(ArtifactDestination destination) {
  final config = decodeDestinationConfig(destination.configJson);
  switch (destination.kind) {
    case ArtifactDestinationKind.watchedFolder:
      final path = configString(config, 'path').trim();
      return path.isEmpty ? 'No folder set' : path;
    case ArtifactDestinationKind.sftp:
      final host = configString(config, 'host').trim();
      if (host.isEmpty) return 'No host set';
      final user = configString(config, 'user').trim();
      final port = configInt(config, 'port');
      final remoteDir = configString(config, 'remoteDir').trim();
      final authority = user.isEmpty ? host : '$user@$host';
      final withPort = port == null ? authority : '$authority:$port';
      return remoteDir.isEmpty ? withPort : '$withPort $remoteDir';
    case ArtifactDestinationKind.peer:
      final peerId = configString(config, 'peerId').trim();
      return peerId.isEmpty ? 'No peer id set' : peerId;
  }
}

/// The selected content classes, in the order the model serializes them.
String deliveryContentSummary(Set<ArtifactContent> content) {
  if (content.isEmpty) return 'Sends nothing';
  final names = <String>[];
  for (final entry in kArtifactContentLabels.entries) {
    if (content.contains(entry.key)) names.add(entry.value);
  }
  return 'Sends ${names.join(', ')}';
}

/// One destination in the list: what it is, what the journal says happened,
/// and the two controls delivery owns — on/off and edit.
class _DestinationRow extends ConsumerWidget {
  const _DestinationRow({
    super.key,
    required this.view,
    required this.isMobile,
    required this.isLast,
  });

  final DeliveryDestinationView view;
  final bool isMobile;
  final bool isLast;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final destination = view.destination;
    final status = view.status;
    final id = destination.id;

    final detailStyle = NightshadeTypography.captionSm.copyWith(
      color: colors.textMuted,
    );

    return MergeSemantics(
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 12.0 : NightshadeTokens.spaceLg,
          vertical: isMobile ? 12.0 : 14.0,
        ),
        decoration: BoxDecoration(
          border: isLast
              ? null
              : Border(
                  bottom: BorderSide(
                    color: colors.border.withValues(alpha: 0.5),
                  ),
                ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: isMobile ? 32.0 : 36.0,
              height: isMobile ? 32.0 : 36.0,
              decoration: BoxDecoration(
                color: colors.surfaceAlt,
                borderRadius: NightshadeTokens.borderRadiusMd,
              ),
              child: Icon(
                deliveryKindIcon(destination.kind),
                size: isMobile ? 14.0 : NightshadeTokens.iconSm,
                color: colors.textSecondary,
              ),
            ),
            SizedBox(width: isMobile ? 10 : 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    destination.name,
                    style: (isMobile
                            ? NightshadeTypography.labelSm
                            : NightshadeTypography.label)
                        .copyWith(color: colors.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  // A remote directory or a deep mount path is long and has
                  // few break opportunities, so it is clipped rather than
                  // allowed to push the row past the card edge. The full value
                  // is in the editor, which is where it is changed.
                  Text(
                    '${deliveryKindLabel(destination.kind)} · '
                    '${deliveryEndpointSummary(destination)}',
                    style: detailStyle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: NightshadeTokens.spaceXs),
                  _StatusLine(status: status),
                  if (destination.kind == ArtifactDestinationKind.peer) ...[
                    const SizedBox(height: 2),
                    _PeerPairingLine(destination: destination),
                  ],
                  const SizedBox(height: 2),
                  Text(
                    deliveryContentSummary(destination.content),
                    style: detailStyle,
                  ),
                  if (destination.kind == ArtifactDestinationKind.sftp) ...[
                    const SizedBox(height: 2),
                    Text(_secretIndicator(view), style: detailStyle),
                  ],
                ],
              ),
            ),
            Flexible(
              child: Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  spacing: NightshadeTokens.spaceSm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Semantics(
                      label: 'Deliver to ${destination.name}',
                      child: NightshadeSwitch(
                        value: destination.enabled,
                        onChanged: id == null
                            ? null
                            : (value) =>
                                _setEnabled(context, ref, id, value: value),
                      ),
                    ),
                    AccessibleIconButton(
                      icon: LucideIcons.settings2,
                      label: 'Edit ${destination.name}',
                      size: 18,
                      onPressed: id == null
                          ? null
                          : () => _DestinationEditorDialog.edit(
                                context,
                                ref,
                                view: view,
                              ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _secretIndicator(DeliveryDestinationView view) {
    switch (view.secret) {
      case StoredSecretState.present:
        return 'SSH key: $kDeliverySecretPlaceholder';
      case StoredSecretState.absent:
        return 'SSH key: none stored';
      case StoredSecretState.unreadable:
        final error = view.secretError;
        if (error != null && error.trim().isNotEmpty) {
          return 'SSH key: the keyring could not be read (${error.trim()})';
        }
        return 'SSH key: the keyring could not be read';
    }
  }

  static Future<void> _setEnabled(
    BuildContext context,
    WidgetRef ref,
    int id, {
    required bool value,
  }) async {
    try {
      await ref
          .read(deliverySettingsStoreProvider)
          .updateDestination(id, enabled: value);
    } catch (error) {
      if (context.mounted) {
        context.showErrorSnackBar(
          'Could not change this destination: ${userFacingError(error)}',
        );
      }
    }
    ref.invalidate(deliveryDestinationsProvider);
  }
}

/// The status dot plus its sentence.
class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.status});

  final DeliveryStatusLine status;

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final color = deliveryStatusColor(status.kind, colors);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: StatusDot(color: color, size: 7),
        ),
        const SizedBox(width: NightshadeTokens.spaceSm),
        Expanded(
          child: Text(
            status.sentence,
            style: NightshadeTypography.captionSm.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

/// Whether a paired desktop actually answers to this peer destination's id.
class _PeerPairingLine extends ConsumerWidget {
  const _PeerPairingLine({required this.destination});

  final ArtifactDestination destination;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final style = NightshadeTypography.captionSm.copyWith(
      color: colors.textMuted,
    );
    final config = decodeDestinationConfig(destination.configJson);
    final peerId = configString(config, 'peerId').trim();
    if (peerId.isEmpty) {
      return Text('Pairing: no peer id to match', style: style);
    }

    final devices = ref.watch(deliveryPairedDesktopsProvider);
    return devices.when(
      loading: () => Text('Pairing: reading the paired devices…', style: style),
      error: (error, _) => Text(
        'Pairing: the paired-device list could not be read '
        '(${userFacingError(error)})',
        style: style.copyWith(color: colors.warning),
      ),
      data: (list) {
        final match = _matchFor(list, peerId);
        if (match == null) {
          return Text(
            'Pairing: no active pairing answers to "$peerId", so nothing can '
            'pull these files',
            style: style.copyWith(color: colors.warning),
          );
        }
        final lastSeen = match.lastConnectedAt;
        final seen = lastSeen == null
            ? 'not connected since pairing'
            : 'last connected '
                '${DateFormat('d MMM HH:mm').format(lastSeen.toLocal())}';
        return Text(
          'Pairing: ${match.deviceName} ($seen)',
          style: style,
        );
      },
    );
  }

  /// A peer destination names its desktop by the identity that desktop sends
  /// when it asks for a manifest, which is the paired device id. Matching the
  /// display name too is deliberate: an operator who typed the name they see
  /// in the pairing list gets the truth rather than a false "not paired".
  static PairedDevice? _matchFor(List<PairedDevice> devices, String peerId) {
    for (final device in devices) {
      if (device.deviceId == peerId) return device;
    }
    for (final device in devices) {
      if (device.deviceName == peerId) return device;
    }
    return null;
  }
}

/// What the destinations card shows before anything is configured.
class _NoDestinationsRow extends StatelessWidget {
  const _NoDestinationsRow();

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return Container(
      padding: const EdgeInsets.all(NightshadeTokens.spaceLg),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colors.border.withValues(alpha: 0.5)),
        ),
      ),
      child: const EmptyState.compact(
        icon: LucideIcons.send,
        title: 'No delivery destination',
        body: 'Nothing is copied off this machine after a dawn run. Add a '
            'watched folder or an SFTP host to change that.',
      ),
    );
  }
}

/// The two add buttons, in the card's last row.
class _AddDestinationRow extends ConsumerWidget {
  const _AddDestinationRow({required this.isMobile});

  final bool isMobile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12.0 : NightshadeTokens.spaceLg,
        vertical: isMobile ? 12.0 : 14.0,
      ),
      child: Wrap(
        spacing: NightshadeTokens.spaceSm,
        runSpacing: NightshadeTokens.spaceSm,
        children: [
          NightshadeButton(
            label: 'Add watched folder',
            icon: LucideIcons.folderPlus,
            variant: ButtonVariant.outline,
            size: ButtonSize.small,
            onPressed: () => _DestinationEditorDialog.create(
              context,
              ref,
              kind: ArtifactDestinationKind.watchedFolder,
            ),
          ),
          NightshadeButton(
            label: 'Add SFTP destination',
            icon: LucideIcons.serverCog,
            variant: ButtonVariant.outline,
            size: ButtonSize.small,
            onPressed: () => _DestinationEditorDialog.create(
              context,
              ref,
              kind: ArtifactDestinationKind.sftp,
            ),
          ),
        ],
      ),
    );
  }
}
