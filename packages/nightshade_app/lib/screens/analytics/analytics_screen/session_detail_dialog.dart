part of '../analytics_screen.dart';

/// The layout width one header action occupies.
///
/// Material gives every [IconButton] a 48-pixel tap target whatever its glyph
/// measures, so this is what the header has to budget per control — not the
/// 18-pixel icon inside it.
const double _kSessionHeaderActionExtent = 48;

/// The narrowest the session name and its date may be squeezed before the
/// action cluster has to fold into a menu.
///
/// Below this the title ellipsizes to a word or two and the header stops
/// naming the session it belongs to, which is the one thing a dialog header
/// exists to do.
const double _kSessionHeaderTitleMinWidth = 180;

/// One session-dialog header action: what it is called, what it does, and the
/// glyph that stands for it.
///
/// Modelled rather than built inline because the same actions have to paint
/// EITHER as icons in the header OR as rows in an overflow menu, and a control
/// that exists in only one of the two forms is a control the accessibility tree
/// and the screen disagree about.
class _SessionHeaderAction {
  const _SessionHeaderAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.buttonKey,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  /// Identifies the inline icon button; the menu row carries no key because it
  /// only exists while the menu is open.
  final Key? buttonKey;
}

class _SessionDetailDialog extends ConsumerStatefulWidget {
  final ImagingSession session;

  const _SessionDetailDialog({required this.session});

  @override
  ConsumerState<_SessionDetailDialog> createState() =>
      _SessionDetailDialogState();
}

class _SessionDetailDialogState extends ConsumerState<_SessionDetailDialog> {
  ImagingSession get session => widget.session;

  /// Why the action the operator just pressed could not do what it offered.
  ///
  /// It is held HERE, and painted inside the dialog, because the dialog is what
  /// stays up to carry it. Posted to the page's `ScaffoldMessenger` instead,
  /// the sentence renders under this modal route: at every window width narrow
  /// enough for the dialog to cover the SnackBar the operator read a refusal
  /// with its first half hidden — "…t. Integrate it in Session Review" — and at
  /// phone width only the last two words survived.
  String? _refusal;

  void _refuse(String reason) {
    if (!mounted) return;
    setState(() => _refusal = reason);
  }

  /// Run [action], dropping whatever the LAST action had to say first.
  ///
  /// A refusal is about the press that produced it. Left standing over the next
  /// press it becomes a sentence about a control the operator has moved on
  /// from — the alert would still read "this session has no integrated master"
  /// while a CSV export was busy underneath it.
  void _invoke(_SessionHeaderAction action) {
    if (_refusal != null) setState(() => _refusal = null);
    action.onPressed();
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final imagesAsyncValue = ref.watch(dbSessionImagesProvider(session.id));
    final isRemote = ref.watch(backendProvider) is NetworkBackend;
    final l10n = context.l10n;
    final actions = _headerActions(isRemote: isRemote, l10n: l10n);
    final refusal = _refusal;

    return Dialog(
      backgroundColor: colors.surface,
      child: ConstrainedBox(
        constraints: AdaptiveDialogConstraints.hybrid(
          context,
          designMaxWidth: 600,
          designMaxHeight: 700,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.surfaceAlt,
                border: Border(bottom: BorderSide(color: colors.border)),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // A Row hands its children unbounded width, so a cluster of
                  // icon buttons beside a title does not shrink — the ones that
                  // run past the end are clipped away while the accessibility
                  // tree still advertises every one of them, and a tap on the
                  // space where one used to be lands on nothing. Below the
                  // width where the whole cluster and a readable title both
                  // fit, they fold into a single overflow menu, so what the
                  // tree reports is what paints.
                  //
                  // Close is not in that menu: it is how this modal is
                  // dismissed, not one of the things it does.
                  final inlineExtent =
                      (actions.length + 1) * _kSessionHeaderActionExtent;
                  final inline = constraints.maxWidth - inlineExtent >=
                      _kSessionHeaderTitleMinWidth;
                  return Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              session.name ??
                                  l10n.text('analyticsUnnamedSession'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: NightshadeTypography.h4.copyWith(
                                color: colors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              DateFormat('MMM d, yyyy HH:mm')
                                  .format(session.startTime),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: NightshadeTypography.fontSize12,
                                  color: colors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      if (inline)
                        for (final action in actions)
                          _headerAction(
                            key: action.buttonKey,
                            icon: action.icon,
                            label: action.label,
                            onPressed: () => _invoke(action),
                          )
                      else
                        _headerOverflowMenu(colors, actions),
                      _headerAction(
                        key: const ValueKey('session_detail_close'),
                        icon: LucideIcons.x,
                        label: l10n.text('commonClose'),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  );
                },
              ),
            ),

            // The refusal an action just returned, inside the route that
            // carries it rather than under it.
            if (refusal != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: NightshadeAlert(
                  key: const ValueKey('session_detail_refusal'),
                  severity: NightshadeAlertSeverity.info,
                  message: refusal,
                  onDismiss: () => setState(() => _refusal = null),
                ),
              ),

            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Statistics
                    _buildStatisticsSection(context, colors),
                    const SizedBox(height: 16),

                    // Images
                    imagesAsyncValue.when(
                      data: (images) =>
                          _buildImagesSection(context, colors, images),
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (err, stack) => Text(
                        'Error loading images: $err',
                        style: TextStyle(color: colors.error),
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

  /// Everything this dialog can do to the session, in header order.
  ///
  /// The closures reach for `State.context`, not a context handed in: the
  /// Darkroom action resolves the night's masters before it decides, and only a
  /// `mounted` check on this State guards the context it uses on the far side
  /// of that await.
  List<_SessionHeaderAction> _headerActions({
    required bool isRemote,
    required NightshadeLocalizations l10n,
  }) {
    return [
      // Open the Session Review / Morning Report (cull + integrate).
      _SessionHeaderAction(
        buttonKey: const ValueKey('session_detail_review'),
        icon: LucideIcons.sparkles,
        label: isRemote ? 'Review on imaging host' : 'Review & Integrate',
        onPressed: () {
          if (isRemote) {
            _refuse('Session Review is available on the imaging host.');
            return;
          }
          Navigator.of(context).pop();
          context.push('/session-review?session=${session.id}');
        },
      ),
      // Open the night's linear master in the Darkroom. Resolves the session's
      // masters first so a session that was never integrated says so instead of
      // opening an editor with nothing in it.
      _SessionHeaderAction(
        buttonKey: const ValueKey('session_detail_darkroom'),
        icon: LucideIcons.sliders,
        label: isRemote ? 'Refine on imaging host' : 'Refine in Darkroom',
        onPressed: () async {
          // Resolve BEFORE dismissing: a session with no master must leave the
          // dialog up to carry the explanation, and only a resolved master
          // earns the pop.
          final target = await resolveDarkroomTargetForSession(
            ref,
            session.id,
          );
          if (!mounted) return;
          final masterId = target.masterId;
          if (masterId == null) {
            _refuse(target.unavailableReason!);
            return;
          }
          Navigator.of(context).pop();
          openDarkroomForMaster(context, masterId);
        },
      ),
      // View the rich Feature-A session report.
      _SessionHeaderAction(
        icon: LucideIcons.fileBarChart,
        label: 'Session Report',
        onPressed: () => SessionReportDialog.show(context, session.id),
      ),
      // Export buttons
      _SessionHeaderAction(
        icon: LucideIcons.fileJson,
        label: l10n.text('analyticsExportJson'),
        onPressed: () => _exportJson(context, ref),
      ),
      _SessionHeaderAction(
        icon: LucideIcons.fileSpreadsheet,
        label: l10n.text('analyticsExportCsv'),
        onPressed: () => _exportCsv(context, ref),
      ),
      _SessionHeaderAction(
        icon: LucideIcons.fileText,
        label: l10n.text('analyticsExportHtml'),
        onPressed: () => _exportReport(context, ref),
      ),
      // Share only exists where the OS has a share sheet. On desktop
      // `shareXFiles()` is unimplemented, and the CSV button beside it already
      // writes the same file and shows its path.
      if (Platform.isAndroid || Platform.isIOS)
        _SessionHeaderAction(
          icon: LucideIcons.share,
          label: l10n.text('share'),
          onPressed: () => _exportAndShare(context, ref),
        ),
    ];
  }

  /// The folded form of the action cluster.
  ///
  /// One button that names itself, and the same actions as named rows once it
  /// is opened — so a control is either painted and in the tree, or in neither.
  Widget _headerOverflowMenu(
    NightshadeColors colors,
    List<_SessionHeaderAction> actions,
  ) {
    return PopupMenuButton<_SessionHeaderAction>(
      key: const ValueKey('session_detail_actions_menu'),
      icon: const Icon(
        LucideIcons.moreVertical,
        size: 18,
        semanticLabel: 'Session actions',
      ),
      tooltip: 'Session actions',
      onSelected: _invoke,
      itemBuilder: (context) => [
        for (final action in actions)
          PopupMenuItem<_SessionHeaderAction>(
            value: action,
            child: Row(
              children: [
                Icon(
                  action.icon,
                  size: NightshadeTokens.iconSm,
                  color: colors.textSecondary,
                ),
                const SizedBox(width: NightshadeTokens.spaceMd),
                // Flexible, not min-sized: a label that grows by a word must
                // wrap inside the menu rather than overflow its row.
                Flexible(
                  child: Text(
                    action.label,
                    style: NightshadeTypography.bodySm.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// One header action: an icon button that publishes [label] as its accessible
  /// name.
  ///
  /// The name goes on the [Icon], not on a surrounding [Semantics]. A Material
  /// [IconButton] wraps itself in `Semantics(container: true, …)`, so an
  /// enclosing `Semantics(label: …)` cannot merge into it: it forms a SECOND
  /// node above the button, and the split publishes a named node with no tap
  /// action over a nameless node that carries the action. `Icon.semanticLabel`
  /// sits inside the button's own node instead, which is why one node comes out
  /// carrying the name, the button role, the enabled state and the tap
  /// together. Before this every one of these buttons published an empty name —
  /// seven anonymous buttons in the header, unreachable by name and
  /// indistinguishable from each other to a screen reader.
  Widget _headerAction({
    Key? key,
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      key: key,
      icon: Icon(icon, size: 18, semanticLabel: label),
      onPressed: onPressed,
      tooltip: label,
    );
  }

  Widget _buildStatisticsSection(
      BuildContext context, NightshadeColors colors) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.text('analyticsStatistics'),
          style: NightshadeTypography.h5.copyWith(
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            _buildStat(
              l10n.text('analyticsTotalExposures'),
              session.totalExposures.toString(),
              colors,
            ),
            _buildStat(
              l10n.text('analyticsSuccessful'),
              session.successfulExposures.toString(),
              colors,
            ),
            _buildStat(
              l10n.text('analyticsFailed'),
              session.failedExposures.toString(),
              colors,
            ),
            _buildStat(
              l10n.text('analyticsIntegration'),
              '${(session.totalIntegrationSecs / 3600).toStringAsFixed(2)}h',
              colors,
            ),
            if (session.avgHfr != null)
              _buildStat(
                l10n.text('analyticsAvgHfr'),
                session.avgHfr!.toStringAsFixed(2),
                colors,
              ),
            if (session.avgGuidingRms != null)
              _buildStat(
                l10n.text('analyticsAvgRms'),
                session.avgGuidingRms!.toStringAsFixed(2),
                colors,
              ),
          ],
        ),
        const SizedBox(height: 6),
        // These counters come from the session's own light-frame tallies, while
        // the image list below holds every frame written to disk. Unlabelled,
        // "Total Exposures 12" over "Images (16)" reads as one count the app
        // cannot keep straight.
        Text(
          l10n.text('analyticsExposureCountsLightOnly'),
          style: TextStyle(
            fontSize: NightshadeTypography.fontSize11,
            color: colors.textMuted,
          ),
        ),
      ],
    );
  }

  Widget _buildStat(String label, String value, NightshadeColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
              fontSize: NightshadeTypography.fontSize11,
              color: colors.textSecondary),
        ),
        Text(
          value,
          style: NightshadeTypography.h5.copyWith(
            color: colors.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildImagesSection(
    BuildContext context,
    NightshadeColors colors,
    List<DbCapturedImage> images,
  ) {
    final lightCount = images
        .where((image) => image.frameType.toLowerCase() == 'light')
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.text(
            'analyticsImages',
            params: {'count': images.length.toString()},
          ),
          style: NightshadeTypography.h5.copyWith(
            color: colors.textPrimary,
          ),
        ),
        // Says what the list is made of, so it can be compared with the
        // light-only exposure counters above it.
        if (images.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            context.l10n.text(
              'analyticsFrameMix',
              params: {
                'light': lightCount.toString(),
                'calibration': (images.length - lightCount).toString(),
              },
            ),
            style: TextStyle(
              fontSize: NightshadeTypography.fontSize11,
              color: colors.textMuted,
            ),
          ),
        ],
        const SizedBox(height: 8),
        ImageThumbnailStrip(images: images),
      ],
    );
  }

  Future<void> _exportJson(BuildContext context, WidgetRef ref) async {
    try {
      final backend = ref.read(backendProvider);
      if (backend is NetworkBackend) {
        final filePath = await _saveRemoteExport(backend, session.id, 'json');
        if (context.mounted) {
          await revealExportedFile(
            context,
            filePath,
            subject: 'Nightshade session data',
          );
        }
        return;
      }
      final clock = ref.read(clockProvider);
      final exportService = SessionExportService(
        sessionsDao: ref.read(sessionsDaoProvider),
        imagesDao: ref.read(imagesDaoProvider),
        nowProvider: clock.now,
      );

      // The export lands in getApplicationDocumentsDirectory(), which is the
      // private sandbox on Android/iOS — an "Exported to: <path>" line there
      // names a file the user cannot open, so hand it to the share sheet.
      final filePath = await exportService.exportToJson(session.id);

      if (context.mounted) {
        await revealExportedFile(
          context,
          filePath,
          subject: 'Nightshade session data',
        );
      }
    } catch (e) {
      if (context.mounted) {
        context.showErrorSnackBar('Export failed: $e');
      }
    }
  }

  Future<void> _exportCsv(BuildContext context, WidgetRef ref) async {
    try {
      final backend = ref.read(backendProvider);
      if (backend is NetworkBackend) {
        final filePath = await _saveRemoteExport(backend, session.id, 'csv');
        if (context.mounted) {
          await revealExportedFile(
            context,
            filePath,
            subject: 'Nightshade session data',
          );
        }
        return;
      }
      final clock = ref.read(clockProvider);
      final exportService = SessionExportService(
        sessionsDao: ref.read(sessionsDaoProvider),
        imagesDao: ref.read(imagesDaoProvider),
        nowProvider: clock.now,
      );

      // Same sandbox problem as the JSON export: reveal rather than announce
      // a path the phone user can never reach.
      final filePath = await exportService.exportToCsv(session.id);

      if (context.mounted) {
        await revealExportedFile(
          context,
          filePath,
          subject: 'Nightshade session data',
        );
      }
    } catch (e) {
      if (context.mounted) {
        context.showErrorSnackBar('Export failed: $e');
      }
    }
  }

  /// Export the session to CSV and hand it to the platform's reachable
  /// destination.
  ///
  /// Routed through [revealExportedFile] — share sheet on Android/iOS, path
  /// snackbar on desktop — because `Share.shareXFiles` is unimplemented on the
  /// shipping desktop build.
  Future<void> _exportAndShare(BuildContext context, WidgetRef ref) async {
    try {
      final backend = ref.read(backendProvider);
      final String filePath;
      if (backend is NetworkBackend) {
        filePath = await _saveRemoteExport(backend, session.id, 'csv');
      } else {
        final clock = ref.read(clockProvider);
        final exportService = SessionExportService(
          sessionsDao: ref.read(sessionsDaoProvider),
          imagesDao: ref.read(imagesDaoProvider),
          nowProvider: clock.now,
        );
        // CSV is the most universal format to hand off.
        filePath = await exportService.exportToCsv(session.id);
      }

      if (!context.mounted) return;
      await revealExportedFile(
        context,
        filePath,
        subject: 'Session data for ${session.name ?? "session"}',
      );
    } catch (e) {
      if (context.mounted) {
        context.showErrorSnackBar('Export failed: $e');
      }
    }
  }

  Future<void> _exportReport(BuildContext context, WidgetRef ref) async {
    try {
      final backend = ref.read(backendProvider);
      if (backend is NetworkBackend) {
        final filePath = await _saveRemoteExport(backend, session.id, 'html');
        if (context.mounted) {
          await revealExportedFile(
            context,
            filePath,
            subject: 'Nightshade session report',
          );
        }
        return;
      }
      final clock = ref.read(clockProvider);
      final exportService = SessionExportService(
        sessionsDao: ref.read(sessionsDaoProvider),
        imagesDao: ref.read(imagesDaoProvider),
        nowProvider: clock.now,
      );

      final filePath = await exportService.exportToHtml(session.id);

      if (context.mounted) {
        await revealExportedFile(
          context,
          filePath,
          subject: 'Nightshade session report',
        );
      }
    } catch (e) {
      if (context.mounted) {
        context.showErrorSnackBar('Report export failed: $e');
      }
    }
  }
}

Stream<List<DbCapturedImage>> _pollRemoteSessionImages(
  NetworkBackend backend,
  int sessionId, {
  required Duration interval,
}) =>
    _pollRemoteImages(
      () => _fetchRemoteSessionImages(backend, sessionId),
      interval: interval,
    );

Stream<List<DbCapturedImage>> _pollRemoteStandaloneImages(
  NetworkBackend backend, {
  required Duration interval,
}) =>
    _pollRemoteImages(
      () => _fetchRemoteStandaloneImages(backend),
      interval: interval,
    );

Stream<List<DbCapturedImage>> _pollRemoteImages(
  Future<List<DbCapturedImage>> Function() fetch, {
  required Duration interval,
}) =>
    resilientDistinctPoll(
      fetch: fetch,
      unchanged: listEquals,
      interval: interval,
    );

Future<List<DbCapturedImage>> _fetchRemoteSessionImages(
  NetworkBackend backend,
  int sessionId,
) async {
  final rows = await backend.getSessionImageRows(sessionId);
  return rows.map(DbCapturedImage.fromJson).toList(growable: false);
}

Future<List<DbCapturedImage>> _fetchRemoteStandaloneImages(
  NetworkBackend backend,
) async {
  final rows = await backend.getStandaloneImageRows();
  return rows.map(DbCapturedImage.fromJson).toList(growable: false);
}

Future<String> _saveRemoteExport(
  NetworkBackend backend,
  int sessionId,
  String format,
) async {
  final bytes = await backend.downloadSessionExport(sessionId, format);
  final docsDir = await getApplicationDocumentsDirectory();
  final exportDir = Directory(path.join(docsDir.path, 'Nightshade', 'exports'));
  if (!await exportDir.exists()) {
    await exportDir.create(recursive: true);
  }
  final fileName =
      'session_${sessionId}_${DateTime.now().millisecondsSinceEpoch}.$format';
  final filePath = path.join(exportDir.path, fileName);
  await File(filePath).writeAsBytes(bytes, flush: true);
  return filePath;
}
