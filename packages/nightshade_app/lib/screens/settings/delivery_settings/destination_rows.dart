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
                  // The one state an operator can act on from here: every
                  // attempt is spent, so nothing on the rig will look at those
                  // files again until somebody says to.
                  if (status.kind == DeliveryStatusKind.failed && id != null)
                    _RetryNowButton(destination: destination, id: id),
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

/// One `delivery_targets` row this build cannot decode.
///
/// Rendered as a row of its own rather than as the page's error state: the row
/// sends nothing, and the operator needs to see WHICH destination that is and
/// what is wrong with it while the destinations that do work are still on
/// screen. Only Delete is offered — every editing path reads the row through
/// the same decode that just refused it, so an editor opened here would have
/// nothing to render.
class _UnreadableDestinationRow extends ConsumerStatefulWidget {
  const _UnreadableDestinationRow({
    super.key,
    required this.row,
    required this.isMobile,
  });

  final UndecodableDeliveryTarget row;
  final bool isMobile;

  @override
  ConsumerState<_UnreadableDestinationRow> createState() =>
      _UnreadableDestinationRowState();
}

class _UnreadableDestinationRowState
    extends ConsumerState<_UnreadableDestinationRow> {
  bool _deleting = false;

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final row = widget.row;
    final id = row.id;
    return MergeSemantics(
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: widget.isMobile ? 12.0 : NightshadeTokens.spaceLg,
          vertical: widget.isMobile ? 12.0 : 14.0,
        ),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: colors.border.withValues(alpha: 0.5)),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: widget.isMobile ? 32.0 : 36.0,
              height: widget.isMobile ? 32.0 : 36.0,
              decoration: BoxDecoration(
                color: colors.surfaceAlt,
                borderRadius: NightshadeTokens.borderRadiusMd,
              ),
              child: Icon(
                LucideIcons.fileWarning,
                size: widget.isMobile ? 14.0 : NightshadeTokens.iconSm,
                color: colors.error,
              ),
            ),
            SizedBox(width: widget.isMobile ? 10 : 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.label,
                    style: (widget.isMobile
                            ? NightshadeTypography.labelSm
                            : NightshadeTypography.label)
                        .copyWith(color: colors.textPrimary),
                  ),
                  const SizedBox(height: NightshadeTokens.spaceXs),
                  _StatusLine(
                    status: DeliveryStatusLine(
                      DeliveryStatusKind.failed,
                      'This row cannot be read, so nothing is sent here: '
                      '${row.reason}.',
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Every other destination delivers normally. Deleting this '
                    'row removes it and its delivery journal; files already '
                    'delivered are left alone.',
                    style: NightshadeTypography.captionSm.copyWith(
                      color: colors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (id != null)
              Flexible(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: NightshadeButton(
                    label: 'Delete',
                    icon: LucideIcons.trash2,
                    variant: ButtonVariant.destructive,
                    size: ButtonSize.small,
                    isLoading: _deleting,
                    onPressed: _deleting ? null : () => _delete(id),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _delete(int id) async {
    final confirmed = await ConfirmDialog.show(
      context: context,
      title: 'Delete ${widget.row.label}?',
      message: 'This destination cannot be read, so it delivers nothing. '
          'Deleting removes the row and its delivery journal. Files already '
          'delivered there are left alone — delivery copies, it never moves.',
      confirmLabel: 'Delete',
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _deleting = true);
    try {
      await ref.read(deliverySettingsStoreProvider).deleteDestination(id);
    } catch (error) {
      if (mounted) {
        context.showErrorSnackBar(
          'Could not delete this destination: ${userFacingError(error)}',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _deleting = false);
        ref.invalidate(deliveryDestinationsProvider);
      }
    }
  }
}

/// Re-queues the spent rows of a destination's newest job and runs a sweep.
///
/// Shown only beside a `failed` status line, because that is the only state
/// where nothing else is going to happen: `retrying` rows are already on the
/// sweep's list and a second push at them would only reset a backoff that is
/// doing its job.
class _RetryNowButton extends ConsumerStatefulWidget {
  const _RetryNowButton({required this.destination, required this.id});

  final ArtifactDestination destination;
  final int id;

  @override
  ConsumerState<_RetryNowButton> createState() => _RetryNowButtonState();
}

class _RetryNowButtonState extends ConsumerState<_RetryNowButton> {
  bool _running = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: NightshadeTokens.spaceXs),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Semantics(
          label: 'Retry delivery to ${widget.destination.name}',
          child: NightshadeButton(
            label: 'Retry now',
            icon: LucideIcons.refreshCw,
            variant: ButtonVariant.outline,
            size: ButtonSize.small,
            isLoading: _running,
            onPressed: _running ? null : _retry,
          ),
        ),
      ),
    );
  }

  Future<void> _retry() async {
    setState(() => _running = true);
    final name = widget.destination.name;
    try {
      final store = ref.read(deliverySettingsStoreProvider);
      final requeued = await store.requeueTerminalRows(widget.id);
      if (requeued == 0) {
        // The journal moved under the page — a sweep or a fresh run already
        // took these rows. Saying "re-queued 0 files" would be a report of
        // work that did not need doing, not of work that failed.
        if (mounted) {
          context.showInfoSnackBar(
            'Nothing on $name is waiting to be retried any more; the list is '
            'reloading.',
          );
        }
        return;
      }
      final report = await ref.read(deliverySweepRequestProvider)();
      if (!mounted) return;
      context.showInfoSnackBar(_outcomeSentence(name, requeued, report));
    } catch (error) {
      if (mounted) {
        context.showErrorSnackBar(
          'Could not retry delivery to $name: ${userFacingError(error)}',
        );
      }
    } finally {
      // Both calls need a live element: `ref` on a disposed ConsumerState
      // throws. A page the operator left behind re-reads the journal when it
      // is opened again, because the destinations provider is autoDispose.
      if (mounted) {
        setState(() => _running = false);
        ref.invalidate(deliveryDestinationsProvider);
      }
    }
  }

  /// What the sweep actually did with the re-queued files.
  ///
  /// A null [report] is a sweep that was already running when this one asked:
  /// that pass read its work list before these rows went back on it, so the
  /// files wait for the next tick. Saying they are being delivered right now
  /// would be the claim this page exists to avoid.
  String _outcomeSentence(
      String name, int requeued, DeliveryRunReport? report) {
    final files = requeued == 1 ? '1 file' : '$requeued files';
    if (report == null) {
      return 'Re-queued $files for $name with a fresh attempt budget. A '
          'delivery sweep was already running, so the next one takes them.';
    }
    for (final swept in report.destinations) {
      if (swept.targetId == widget.id) {
        return 'Re-queued $files for $name, then the sweep reported '
            '${_sweptCounts(swept)}.';
      }
    }
    return 'Re-queued $files for $name with a fresh attempt budget. The sweep '
        'that ran did not reach this destination, so the next one takes them.';
  }

  /// The sweep's own counts for this destination, so the sentence states what
  /// happened to the files rather than that something happened.
  static String _sweptCounts(DeliveryDestinationReport swept) {
    final parts = <String>[
      if (swept.delivered > 0) '${swept.delivered} delivered',
      if (swept.awaitingPull > 0) '${swept.awaitingPull} awaiting a pull',
      if (swept.retrying > 0) '${swept.retrying} owed another attempt',
      if (swept.failed > 0) '${swept.failed} failed again',
      if (swept.unjournalled > 0) '${swept.unjournalled} not journalled',
    ];
    return parts.isEmpty ? 'nothing was attempted' : parts.join(', ');
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
