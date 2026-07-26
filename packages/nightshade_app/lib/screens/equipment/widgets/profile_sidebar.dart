import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Device type enum for ordering dots in profile cards
enum _DeviceType {
  camera,
  mount,
  focuser,
  filterWheel,
  guider,
  rotator,
}

/// A vertical sidebar for profile selection and management
class ProfileSidebar extends ConsumerWidget {
  final int? selectedProfileId;
  final ValueChanged<int> onProfileSelected;
  final VoidCallback onCreateProfile;
  final ValueChanged<EquipmentProfileModel> onEditProfile;
  final ValueChanged<EquipmentProfileModel> onConnectAll;
  final VoidCallback onDisconnectAll;
  final ValueChanged<EquipmentProfileModel> onSetDefault;
  final ValueChanged<int> onDuplicateProfile;
  final ValueChanged<int> onDeleteProfile;
  final void Function(int oldIndex, int newIndex) onReorderProfiles;
  final VoidCallback? onCollapse;

  const ProfileSidebar({
    super.key,
    required this.selectedProfileId,
    required this.onProfileSelected,
    required this.onCreateProfile,
    required this.onEditProfile,
    required this.onConnectAll,
    required this.onDisconnectAll,
    required this.onSetDefault,
    required this.onDuplicateProfile,
    required this.onDeleteProfile,
    required this.onReorderProfiles,
    this.onCollapse,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final profiles = ref.watch(sortedProfilesProvider);

    // Find selected profile
    final selectedProfile = selectedProfileId != null
        ? profiles.where((p) => p.id == selectedProfileId).firstOrNull
        : null;

    // Determine if there are connected/disconnected devices for the selected
    // profile. The per-device connection matrix is computed once, canonically,
    // by `profileConnectionStatusProvider` (the single source of truth) rather
    // than re-derived here.
    final selectedStatus = selectedProfile != null
        ? ref.watch(profileConnectionStatusProvider(selectedProfile))
        : null;
    final hasConnectedDevices = selectedStatus?.hasConnectedCore ?? false;
    final hasDisconnectedDevices = selectedStatus?.hasDisconnectedCore ?? false;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
          right: BorderSide(color: colors.border),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          _buildHeader(context, colors),

          // Profile list or empty state
          Expanded(
            child: profiles.isEmpty
                ? _buildEmptyState(context, colors)
                : _buildProfileList(
                    context,
                    ref,
                    profiles,
                    colors,
                  ),
          ),

          // Footer actions
          if (selectedProfile != null)
            _buildFooter(
              context,
              colors,
              selectedProfile,
              hasConnectedDevices,
              hasDisconnectedDevices,
            ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, NightshadeColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colors.border),
        ),
      ),
      child: Row(
        children: [
          Text(
            'PROFILES',
            style: TextStyle(
              fontSize: NightshadeTypography.fontSize11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
              color: colors.textMuted,
            ),
          ),
          const Spacer(),
          SizedBox(
            width: 28,
            height: 28,
            child: IconButton(
              onPressed: onCreateProfile,
              icon: const Icon(LucideIcons.plus, size: 16),
              padding: EdgeInsets.zero,
              style: IconButton.styleFrom(
                foregroundColor: colors.textSecondary,
                backgroundColor: colors.surfaceAlt,
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(NightshadeTokens.radiusMd),
                ),
              ),
              tooltip: 'Create new profile',
            ),
          ),
          if (onCollapse != null) ...[
            const SizedBox(width: 4),
            Tooltip(
              message: 'Collapse panel',
              child: InkWell(
                onTap: onCollapse,
                borderRadius:
                    BorderRadius.circular(NightshadeTokens.radiusInline4),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    LucideIcons.panelLeftClose,
                    size: 16,
                    color: colors.textMuted,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, NightshadeColors colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.compass,
              size: 48,
              color: colors.textMuted,
            ),
            const SizedBox(height: 16),
            Text(
              'No profiles yet',
              style:
                  NightshadeTypography.h5.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              'Create a profile to save your equipment configuration',
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize12,
                color: colors.textMuted,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            NightshadeButton(
              label: 'Create First Profile',
              icon: LucideIcons.plus,
              variant: ButtonVariant.primary,
              onPressed: onCreateProfile,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileList(
    BuildContext context,
    WidgetRef ref,
    List<EquipmentProfileModel> profiles,
    NightshadeColors colors,
  ) {
    return ReorderableListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      buildDefaultDragHandles: false,
      onReorderItem: onReorderProfiles,
      itemCount: profiles.length,
      proxyDecorator: (child, index, animation) {
        return AnimatedBuilder(
          animation: animation,
          builder: (context, child) {
            final elevation = Tween<double>(begin: 0, end: 6)
                .animate(
                    CurvedAnimation(parent: animation, curve: Curves.easeOut))
                .value;
            return Material(
              elevation: elevation,
              color: Colors.transparent,
              shadowColor: colors.primary.withValues(alpha: 0.3),
              child: child,
            );
          },
          child: child,
        );
      },
      itemBuilder: (context, index) {
        final profile = profiles[index];
        final isSelected = profile.id == selectedProfileId;

        // Per-device connection state comes from the canonical
        // `profileConnectionStatusProvider`, the single source of truth for
        // the "is device X connected for profile Y" matrix.
        final status = ref.watch(profileConnectionStatusProvider(profile));
        final deviceStates = _toDeviceStateMap(status);
        final connectedCount = status.coreConnectedCount;
        final totalCount = status.coreTotalCount;

        return _ProfileCard(
          key: ValueKey(profile.id),
          profile: profile,
          isSelected: isSelected,
          deviceStates: deviceStates,
          connectedCount: connectedCount,
          totalCount: totalCount,
          index: index,
          colors: colors,
          onTap: () => onProfileSelected(profile.id!),
          onDoubleTap: () {
            onProfileSelected(profile.id!);
            onConnectAll(profile);
          },
          onShowContextMenu: (offset) => _showProfileContextMenu(
            context,
            ref,
            offset,
            profile,
            colors,
          ),
        );
      },
    );
  }

  Widget _buildFooter(
    BuildContext context,
    NightshadeColors colors,
    EquipmentProfileModel selectedProfile,
    bool hasConnectedDevices,
    bool hasDisconnectedDevices,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: colors.border),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Show Connect All when selected profile has disconnected devices
          if (hasDisconnectedDevices) ...[
            NightshadeButton(
              label: 'Connect All',
              icon: LucideIcons.plug,
              variant: ButtonVariant.primary,
              onPressed: () => onConnectAll(selectedProfile),
            ),
            const SizedBox(height: 8),
          ],
          // Show Disconnect All when any devices connected
          if (hasConnectedDevices) ...[
            NightshadeButton(
              label: 'Disconnect All',
              icon: LucideIcons.unplug,
              variant: ButtonVariant.ghost,
              onPressed: onDisconnectAll,
            ),
            const SizedBox(height: 8),
          ],
          // Always show Edit Profile when a profile is selected
          NightshadeButton(
            label: 'Edit Profile',
            icon: LucideIcons.pencil,
            variant: ButtonVariant.ghost,
            onPressed: () => onEditProfile(selectedProfile),
          ),
        ],
      ),
    );
  }

  void _showProfileContextMenu(
    BuildContext context,
    WidgetRef ref,
    Offset offset,
    EquipmentProfileModel profile,
    NightshadeColors colors,
  ) {
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromLTWH(offset.dx, offset.dy, 0, 0),
      Offset.zero & overlay.size,
    );

    showMenu<String>(
      context: context,
      position: position,
      color: colors.surface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8)),
      items: [
        PopupMenuItem(
          value: 'default',
          child: Row(
            children: [
              Icon(
                LucideIcons.star,
                size: 16,
                color: colors.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                profile.isDefault ? 'Default Profile' : 'Set as Default',
                style: TextStyle(color: colors.textPrimary),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              Icon(LucideIcons.pencil, size: 16, color: colors.textSecondary),
              const SizedBox(width: 8),
              Text('Edit Profile', style: TextStyle(color: colors.textPrimary)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'duplicate',
          child: Row(
            children: [
              Icon(LucideIcons.copy, size: 16, color: colors.textSecondary),
              const SizedBox(width: 8),
              Text('Duplicate', style: TextStyle(color: colors.textPrimary)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(LucideIcons.trash2, size: 16, color: colors.error),
              const SizedBox(width: 8),
              Text('Delete', style: TextStyle(color: colors.error)),
            ],
          ),
        ),
      ],
    ).then((value) async {
      if (value == null) return;
      if (!context.mounted) return;

      switch (value) {
        case 'default':
          onSetDefault(profile);
          break;
        case 'edit':
          onEditProfile(profile);
          break;
        case 'duplicate':
          onDuplicateProfile(profile.id!);
          break;
        case 'delete':
          final confirmed =
              await _showDeleteConfirmation(context, profile, colors);
          if (confirmed == true) {
            onDeleteProfile(profile.id!);
          }
          break;
      }
    });
  }

  Future<bool?> _showDeleteConfirmation(
    BuildContext context,
    EquipmentProfileModel profile,
    NightshadeColors colors,
  ) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text(
          'Delete Profile',
          style: TextStyle(color: colors.textPrimary),
        ),
        content: Text(
          'Delete "${profile.name}"? This cannot be undone.',
          style: TextStyle(color: colors.textSecondary),
        ),
        actions: [
          NightshadeButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            label: 'Cancel',
            variant: ButtonVariant.ghost,
            size: ButtonSize.small,
          ),
          NightshadeButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            label: 'Delete',
            variant: ButtonVariant.destructive,
            size: ButtonSize.small,
          ),
        ],
      ),
    );
  }

  /// Adapt the canonical [ProfileConnectionStatus] core-slot states onto this
  /// widget's local [_DeviceType] keys for the connection-dot row. Only
  /// assigned core slots are present; the dot builder filters on non-null, so
  /// unassigned slots are simply absent (matching the prior behavior where
  /// `_getDeviceConnectionStates` produced `null` for unassigned devices).
  Map<_DeviceType, DeviceConnectionState?> _toDeviceStateMap(
    ProfileConnectionStatus status,
  ) {
    DeviceConnectionState? stateFor(ProfileDeviceSlot slot) {
      final conn = status[slot];
      return conn.isAssigned ? conn.profileState : null;
    }

    return {
      _DeviceType.camera: stateFor(ProfileDeviceSlot.camera),
      _DeviceType.mount: stateFor(ProfileDeviceSlot.mount),
      _DeviceType.focuser: stateFor(ProfileDeviceSlot.focuser),
      _DeviceType.filterWheel: stateFor(ProfileDeviceSlot.filterWheel),
      _DeviceType.guider: stateFor(ProfileDeviceSlot.guider),
      _DeviceType.rotator: stateFor(ProfileDeviceSlot.rotator),
    };
  }
}

/// Individual profile card widget with all interactions
class _ProfileCard extends StatefulWidget {
  final EquipmentProfileModel profile;
  final bool isSelected;
  final Map<_DeviceType, DeviceConnectionState?> deviceStates;
  final int connectedCount;
  final int totalCount;
  final int index;
  final NightshadeColors colors;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final void Function(Offset globalPosition) onShowContextMenu;

  const _ProfileCard({
    super.key,
    required this.profile,
    required this.isSelected,
    required this.deviceStates,
    required this.connectedCount,
    required this.totalCount,
    required this.index,
    required this.colors,
    required this.onTap,
    required this.onDoubleTap,
    required this.onShowContextMenu,
  });

  @override
  State<_ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends State<_ProfileCard>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _pulseAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _checkForConnecting();
  }

  @override
  void didUpdateWidget(_ProfileCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _checkForConnecting();
  }

  void _checkForConnecting() {
    final hasConnecting = widget.deviceStates.values
        .any((state) => state == DeviceConnectionState.connecting);

    if (hasConnecting) {
      if (!_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
    } else {
      _pulseController.stop();
      _pulseController.reset();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Get profile color or fall back to primary
    final profileColor = widget.profile.profileColor != null
        ? Color(widget.profile.profileColor!)
        : widget.colors.primary;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      // FocusRing makes profile rows keyboard-discoverable; without it the
      // raw GestureDetector silently swallowed focus traversal.
      child: FocusRing(
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusLg),
        child: GestureDetector(
          onTap: widget.onTap,
          onDoubleTap: widget.onDoubleTap,
          onSecondaryTapUp: (details) {
            widget.onShowContextMenu(details.globalPosition);
          },
          onLongPressStart: (details) {
            widget.onShowContextMenu(details.globalPosition);
          },
          child: ReorderableDragStartListener(
            index: widget.index,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: widget.isSelected
                    ? widget.colors.surfaceAlt
                    : _isHovered
                        ? widget.colors.surface
                        : Colors.transparent,
                borderRadius: BorderRadius.circular(NightshadeTokens.radiusLg),
                border: Border.all(
                  color: widget.isSelected
                      ? profileColor
                      : _isHovered
                          ? widget.colors.border
                          : Colors.transparent,
                  width: widget.isSelected ? 2 : 1,
                ),
                boxShadow: widget.isSelected
                    ? [
                        BoxShadow(
                          color: profileColor.withValues(alpha: 0.15),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top row: icon, name, default star
                  Row(
                    children: [
                      // Profile icon
                      Text(
                        widget.profile.profileIcon ??
                            '\u{1F52D}', // Default telescope emoji
                        style: const TextStyle(
                            fontSize: NightshadeTypography.fontSize18),
                      ),
                      const SizedBox(width: 8),

                      // Profile name
                      Expanded(
                        child: Text(
                          widget.profile.name,
                          style: NightshadeTypography.labelStrong
                              .copyWith(color: widget.colors.textPrimary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),

                      // Default star indicator
                      if (widget.profile.isDefault)
                        Icon(
                          LucideIcons.star,
                          size: 14,
                          color: widget.colors.warning,
                        ),
                    ],
                  ),

                  const SizedBox(height: 4),

                  // Subtitle row
                  Text(
                    widget.profile.subtitle,
                    style: TextStyle(
                      fontSize: NightshadeTypography.fontSize11,
                      color: widget.colors.textMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),

                  const SizedBox(height: 8),

                  // Bottom row: device dots + connection count
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Device dots
                      _buildDeviceDots(),

                      // Connection count
                      if (widget.totalCount > 0)
                        Text(
                          '${widget.connectedCount}/${widget.totalCount}',
                          style: TextStyle(
                            fontSize: NightshadeTypography.fontSize10,
                            fontWeight: FontWeight.w500,
                            color: widget.connectedCount == widget.totalCount
                                ? widget.colors.success
                                : widget.connectedCount > 0
                                    ? widget.colors.warning
                                    : widget.colors.textMuted,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDeviceDots() {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: _DeviceType.values
              .where((type) => widget.deviceStates[type] != null)
              .map((type) => _buildDot(type, widget.deviceStates[type]!))
              .toList(),
        );
      },
    );
  }

  Widget _buildDot(_DeviceType type, DeviceConnectionState state) {
    final Color color;
    final bool isHollow;
    final bool isPulsing;

    switch (state) {
      case DeviceConnectionState.connected:
        color = widget.colors.success;
        isHollow = false;
        isPulsing = false;
      case DeviceConnectionState.connecting:
        color = widget.colors.warning;
        isHollow = false;
        isPulsing = true;
      case DeviceConnectionState.error:
        color = widget.colors.error;
        isHollow = false;
        isPulsing = false;
      case DeviceConnectionState.disconnected:
        color = widget.colors.textMuted.withValues(alpha: 0.5);
        isHollow = true;
        isPulsing = false;
    }

    final effectiveOpacity = isPulsing ? _pulseAnimation.value : 1.0;

    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Tooltip(
        message: _getDeviceTypeTooltip(type, state),
        child: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isHollow
                ? Colors.transparent
                : color.withValues(alpha: effectiveOpacity),
            border: Border.all(
              color: color.withValues(alpha: effectiveOpacity),
              width: isHollow ? 1.5 : 0,
            ),
          ),
        ),
      ),
    );
  }

  String _getDeviceTypeTooltip(_DeviceType type, DeviceConnectionState state) {
    final typeName = switch (type) {
      _DeviceType.camera => 'Camera',
      _DeviceType.mount => 'Mount',
      _DeviceType.focuser => 'Focuser',
      _DeviceType.filterWheel => 'Filter Wheel',
      _DeviceType.guider => 'Guider',
      _DeviceType.rotator => 'Rotator',
    };

    final stateName = switch (state) {
      DeviceConnectionState.connected => 'Connected',
      DeviceConnectionState.connecting => 'Connecting...',
      DeviceConnectionState.error => 'Error',
      DeviceConnectionState.disconnected => 'Disconnected',
    };

    return '$typeName: $stateName';
  }
}
