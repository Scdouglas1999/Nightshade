import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import 'package:nightshade_core/nightshade_core.dart' hide ObserverLocation;

import '../../../widgets/slew_dropdown_button.dart';
import '../../../widgets/tutorial_keys/planetarium_keys.dart';
import '../planetarium_screen.dart';
import 'observation_log_dialog.dart';

class ObjectInfoPopup extends StatefulWidget {
  final NightshadeColors colors;
  final CelestialObject object;
  final CelestialCoordinate coordinates;
  final SelectedObjectState selectedObjectState;
  final Offset position;
  final VoidCallback onDismiss;
  final VoidCallback onSendToFraming;
  final VoidCallback onAddToSequencer;
  final VoidCallback onSlewToTarget;
  final VoidCallback onSlewAndCenter;
  final VoidCallback onSlewCenterRotate;
  final VoidCallback? onExportChart;
  final bool hasRotator;

  const ObjectInfoPopup({
    super.key,
    required this.colors,
    required this.object,
    required this.coordinates,
    required this.selectedObjectState,
    required this.position,
    required this.onDismiss,
    required this.onSendToFraming,
    required this.onAddToSequencer,
    required this.onSlewToTarget,
    required this.onSlewAndCenter,
    required this.onSlewCenterRotate,
    this.onExportChart,
    required this.hasRotator,
  });

  @override
  State<ObjectInfoPopup> createState() => _ObjectInfoPopupState();
}

class _ObjectInfoPopupState extends State<ObjectInfoPopup>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  void _consumeTap() {
    // Popup body absorbs taps so sky-map clicks do not pass through.
  }
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutBack),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    const popupWidth = 300.0;
    const popupHeight = 400.0;

    // Calculate position to keep popup on screen
    double left = widget.position.dx - popupWidth / 2;
    double top = widget.position.dy + 20; // Offset below the click

    // Clamp to screen bounds with padding
    const padding = 16.0;
    left = left.clamp(padding, screenSize.width - popupWidth - padding);

    // If popup would go below screen, show it above the click point
    if (top + popupHeight > screenSize.height - padding) {
      top = widget.position.dy - popupHeight - 20;
    }
    top = top.clamp(padding, screenSize.height - popupHeight - padding);

    // Determine if showing above or below click point for arrow direction
    final showAbove = top < widget.position.dy;

    return Positioned(
      left: left,
      top: top,
      child: AnimatedBuilder(
        animation: _animationController,
        builder: (context, child) {
          return Opacity(
            opacity: _fadeAnimation.value,
            child: Transform.scale(
              scale: _scaleAnimation.value,
              alignment:
                  showAbove ? Alignment.bottomCenter : Alignment.topCenter,
              child: child,
            ),
          );
        },
        child: Material(
          color: Colors.transparent,
          child: GestureDetector(
            onTap: _consumeTap,
            child: Container(
              key: PlanetariumTutorialKeys.objectPopup,
              width: popupWidth,
              constraints: const BoxConstraints(maxHeight: popupHeight),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A24).withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: widget.colors.primary.withValues(alpha: 0.3),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 24,
                    spreadRadius: 4,
                  ),
                  BoxShadow(
                    color: widget.colors.primary.withValues(alpha: 0.1),
                    blurRadius: 40,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header
                      _buildHeader(),

                      // Divider
                      Container(
                        height: 1,
                        color: widget.colors.border.withValues(alpha: 0.5),
                      ),

                      // Content
                      Flexible(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildObjectDetails(),
                              const SizedBox(height: 16),
                              _buildCoordinates(),
                              if (widget.selectedObjectState.currentAltAz !=
                                  null) ...[
                                const SizedBox(height: 12),
                                _buildAltAz(),
                              ],
                            ],
                          ),
                        ),
                      ),

                      // Divider
                      Container(
                        height: 1,
                        color: widget.colors.border.withValues(alpha: 0.5),
                      ),

                      // Action buttons
                      _buildActions(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final obj = widget.object;
    IconData icon;
    Color iconColor;

    if (obj is Star) {
      icon = LucideIcons.star;
      iconColor = Colors.amber;
    } else if (obj is DeepSkyObject) {
      final dso = obj;
      if (dso.type.isGalaxy) {
        icon = LucideIcons.circle;
        iconColor = widget.colors.info;
      } else if (dso.type.isNebula) {
        icon = LucideIcons.cloud;
        iconColor = widget.colors.error;
      } else if (dso.type.isCluster) {
        icon = LucideIcons.sparkles;
        iconColor = widget.colors.warning;
      } else {
        icon = LucideIcons.target;
        iconColor = widget.colors.primary;
      }
    } else {
      icon = LucideIcons.target;
      iconColor = widget.colors.primary;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 20, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  obj is DeepSkyObject ? getDsoDisplayInfo(obj).$1 : obj.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: widget.colors.primary.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        obj is DeepSkyObject
                            ? getDsoDisplayInfo(obj).$2
                            : obj.id,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: widget.colors.primary,
                        ),
                      ),
                    ),
                    if (obj.magnitude != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        'mag ${obj.magnitude!.toStringAsFixed(1)}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white60,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          // Export chart button
          if (widget.onExportChart != null) ...[
            GestureDetector(
              onTap: widget.onExportChart,
              child: Tooltip(
                message: 'Export finder chart',
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(LucideIcons.fileDown,
                      size: 14, color: Colors.white60),
                ),
              ),
            ),
            const SizedBox(width: 4),
          ],
          // Close button
          GestureDetector(
            onTap: widget.onDismiss,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(LucideIcons.x, size: 14, color: Colors.white60),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildObjectDetails() {
    final obj = widget.object;
    String typeLabel = 'Object';

    if (obj is Star) {
      typeLabel = 'Star';
      if (obj.spectralType != null) {
        typeLabel = 'Star (${obj.spectralType})';
      }
    } else if (obj is DeepSkyObject) {
      typeLabel = obj.type.displayName;
    }

    return Row(
      children: [
        PopupInfoChip(
          label: 'Type',
          value: typeLabel,
          colors: widget.colors,
        ),
        const SizedBox(width: 8),
        if (obj is DeepSkyObject && obj.sizeString != null)
          PopupInfoChip(
            label: 'Size',
            value: obj.sizeString!,
            colors: widget.colors,
          ),
      ],
    );
  }

  Widget _buildCoordinates() {
    final coords = widget.coordinates;

    // Format RA
    final raH = coords.ra.floor();
    final raM = ((coords.ra - raH) * 60).floor();
    final raS = (((coords.ra - raH) * 60 - raM) * 60).toStringAsFixed(1);
    final raStr = '${raH}h ${raM}m ${raS}s';

    // Format Dec
    final sign = coords.dec >= 0 ? '+' : '-';
    final decD = coords.dec.abs().floor();
    final decM = ((coords.dec.abs() - decD) * 60).floor();
    final decS =
        (((coords.dec.abs() - decD) * 60 - decM) * 60).toStringAsFixed(0);
    final decStr = "$sign$decD\u00b0 $decM' $decS\"";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Coordinates',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: Colors.white38,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: PopupCoordRow(
                label: 'RA',
                value: raStr,
                colors: widget.colors,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: PopupCoordRow(
                label: 'Dec',
                value: decStr,
                colors: widget.colors,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAltAz() {
    final altAz = widget.selectedObjectState.currentAltAz!;
    final alt = altAz.$1;
    final az = altAz.$2;

    Color altColor;
    String statusText;
    if (alt > 30) {
      altColor = widget.colors.success;
      statusText = 'Excellent';
    } else if (alt > 15) {
      altColor = widget.colors.warning;
      statusText = 'Good';
    } else if (alt > 0) {
      altColor = widget.colors.warning;
      statusText = 'Low';
    } else {
      altColor = widget.colors.error;
      statusText = 'Below Horizon';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Current Position',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: Colors.white38,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: altColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: altColor.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    alt > 0 ? LucideIcons.arrowUp : LucideIcons.arrowDown,
                    size: 12,
                    color: altColor,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${alt.toStringAsFixed(1)}\u00b0',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: altColor,
                      fontFeatures: const [ui.FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Az ${az.toStringAsFixed(1)}\u00b0',
              style: const TextStyle(
                fontSize: 11,
                color: Colors.white60,
                fontFeatures: [ui.FontFeature.tabularFigures()],
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: altColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                statusText,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: altColor,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showAddToListDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => _AddToListDialog(
        object: widget.object,
        coordinates: widget.coordinates,
      ),
    );
  }

  Widget _buildActions() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: SlewPopupMenuButton(
                  colors: widget.colors,
                  onSlew: widget.onSlewToTarget,
                  onSlewAndCenter: widget.onSlewAndCenter,
                  onSlewCenterRotate: widget.onSlewCenterRotate,
                  showRotateOption: widget.hasRotator,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: PopupActionButton(
                  key: PlanetariumTutorialKeys.sendFraming,
                  icon: LucideIcons.frame,
                  label: 'Framing',
                  colors: widget.colors,
                  onTap: widget.onSendToFraming,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: PopupActionButton(
                  key: PlanetariumTutorialKeys.addSequence,
                  icon: LucideIcons.listPlus,
                  label: 'Sequence',
                  colors: widget.colors,
                  isPrimary: true,
                  onTap: widget.onAddToSequencer,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: PopupActionButton(
                  icon: LucideIcons.bookOpen,
                  label: 'Log Observation',
                  colors: widget.colors,
                  onTap: () {
                    showDialog<bool>(
                      context: context,
                      builder: (context) => ObservationLogDialog(
                        object: widget.object,
                        coordinates: widget.coordinates,
                        altAz: widget.selectedObjectState.currentAltAz,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: PopupActionButton(
                  icon: LucideIcons.listPlus,
                  label: 'Add to List',
                  colors: widget.colors,
                  onTap: () {
                    _showAddToListDialog(context);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Slew popup menu button for planetarium object popup
class SlewPopupMenuButton extends StatefulWidget {
  final NightshadeColors colors;
  final VoidCallback onSlew;
  final VoidCallback onSlewAndCenter;
  final VoidCallback onSlewCenterRotate;
  final bool showRotateOption;

  const SlewPopupMenuButton({
    super.key,
    required this.colors,
    required this.onSlew,
    required this.onSlewAndCenter,
    required this.onSlewCenterRotate,
    required this.showRotateOption,
  });

  @override
  State<SlewPopupMenuButton> createState() => _SlewPopupMenuButtonState();
}

class _SlewPopupMenuButtonState extends State<SlewPopupMenuButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<SlewMode>(
      onSelected: (mode) {
        switch (mode) {
          case SlewMode.slew:
            widget.onSlew();
            break;
          case SlewMode.slewAndCenter:
            widget.onSlewAndCenter();
            break;
          case SlewMode.slewCenterRotate:
            widget.onSlewCenterRotate();
            break;
        }
      },
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      color: widget.colors.surface,
      itemBuilder: (context) => [
        PopupMenuItem<SlewMode>(
          value: SlewMode.slew,
          child: Row(
            children: [
              Icon(LucideIcons.move,
                  size: 16, color: widget.colors.textPrimary),
              const SizedBox(width: 8),
              Text('Slew', style: TextStyle(color: widget.colors.textPrimary)),
            ],
          ),
        ),
        PopupMenuItem<SlewMode>(
          value: SlewMode.slewAndCenter,
          child: Row(
            children: [
              Icon(LucideIcons.target,
                  size: 16, color: widget.colors.textPrimary),
              const SizedBox(width: 8),
              Text('Slew & Center',
                  style: TextStyle(color: widget.colors.textPrimary)),
            ],
          ),
        ),
        if (widget.showRotateOption)
          PopupMenuItem<SlewMode>(
            value: SlewMode.slewCenterRotate,
            child: Row(
              children: [
                Icon(LucideIcons.rotateCw,
                    size: 16, color: widget.colors.textPrimary),
                const SizedBox(width: 8),
                Text('Slew, Center & Rotate',
                    style: TextStyle(color: widget.colors.textPrimary)),
              ],
            ),
          ),
      ],
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                widget.colors.primary,
                widget.colors.primary.withValues(alpha: 0.8),
              ],
            ),
            borderRadius: BorderRadius.circular(8),
            boxShadow: _isHovered
                ? [
                    BoxShadow(
                      color: widget.colors.primary.withValues(alpha: 0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: const FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  LucideIcons.crosshair,
                  size: 14,
                  color: Colors.white,
                ),
                SizedBox(width: 6),
                Text(
                  'Slew',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                SizedBox(width: 4),
                Icon(
                  LucideIcons.chevronDown,
                  size: 12,
                  color: Colors.white70,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PopupInfoChip extends StatelessWidget {
  final String label;
  final String value;
  final NightshadeColors colors;

  const PopupInfoChip({
    super.key,
    required this.label,
    required this.value,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 9,
              color: Colors.white38,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }
}

class PopupCoordRow extends StatelessWidget {
  final String label;
  final String value;
  final NightshadeColors colors;

  const PopupCoordRow({
    super.key,
    required this.label,
    required this.value,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          '$label: ',
          style: const TextStyle(
            fontSize: 11,
            color: Colors.white38,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Colors.white70,
              fontFeatures: [ui.FontFeature.tabularFigures()],
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class PopupActionButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final NightshadeColors colors;
  final bool isPrimary;
  final VoidCallback onTap;

  const PopupActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.colors,
    this.isPrimary = false,
    required this.onTap,
  });

  @override
  State<PopupActionButton> createState() => _PopupActionButtonState();
}

class _PopupActionButtonState extends State<PopupActionButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
            gradient: widget.isPrimary
                ? LinearGradient(
                    colors: [
                      widget.colors.primary,
                      widget.colors.primary.withValues(alpha: 0.8),
                    ],
                  )
                : null,
            color: widget.isPrimary
                ? null
                : _isHovered
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(8),
            border: widget.isPrimary
                ? null
                : Border.all(
                    color: _isHovered
                        ? widget.colors.primary.withValues(alpha: 0.5)
                        : Colors.white.withValues(alpha: 0.1),
                  ),
            boxShadow: widget.isPrimary && _isHovered
                ? [
                    BoxShadow(
                      color: widget.colors.primary.withValues(alpha: 0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 14,
                color: widget.isPrimary ? Colors.white : Colors.white70,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: widget.isPrimary ? Colors.white : Colors.white70,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dialog for adding a celestial object to an observing list.
class _AddToListDialog extends ConsumerStatefulWidget {
  final CelestialObject object;
  final CelestialCoordinate coordinates;

  const _AddToListDialog({
    required this.object,
    required this.coordinates,
  });

  @override
  ConsumerState<_AddToListDialog> createState() => _AddToListDialogState();
}

class _AddToListDialogState extends ConsumerState<_AddToListDialog> {
  final _newListNameController = TextEditingController();
  bool _creatingNew = false;

  @override
  void dispose() {
    _newListNameController.dispose();
    super.dispose();
  }

  String get _objectName {
    final obj = widget.object;
    if (obj is DeepSkyObject) {
      return getDsoDisplayInfo(obj).$1;
    }
    return obj.name;
  }

  String? get _catalogId {
    final obj = widget.object;
    if (obj is DeepSkyObject) {
      // Prefer Messier, then NGC/IC, then id
      if (obj.isMessier && obj.messierNumber != null) return obj.messierNumber;
      if (obj.ngcIcDesignation != null) return obj.ngcIcDesignation;
      return obj.id;
    }
    return obj.id;
  }

  String? get _objectType {
    final obj = widget.object;
    if (obj is DeepSkyObject) return obj.type.displayName;
    if (obj is Star) return 'Star';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final listsAsync = ref.watch(observingListsProvider);

    return AlertDialog(
      title: Text('Add "$_objectName" to List'),
      content: SizedBox(
        width: 300,
        child: listsAsync.when(
          data: (lists) {
            if (lists.isEmpty && !_creatingNew) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('No observing lists yet. Create one first.'),
                  const SizedBox(height: 16),
                  _buildNewListField(),
                ],
              );
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (lists.isNotEmpty) ...[
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: lists.length,
                      itemBuilder: (context, index) {
                        final list = lists[index];
                        return ListTile(
                          dense: true,
                          leading: const Icon(LucideIcons.list, size: 18),
                          title: Text(list.name),
                          onTap: () => _addToList(list.id),
                        );
                      },
                    ),
                  ),
                  const Divider(),
                ],
                if (_creatingNew)
                  _buildNewListField()
                else
                  TextButton.icon(
                    onPressed: () => setState(() => _creatingNew = true),
                    icon: const Icon(LucideIcons.plus, size: 16),
                    label: const Text('Create New List'),
                  ),
              ],
            );
          },
          loading: () => const SizedBox(
            height: 80,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          error: (e, _) => Text('Error loading lists: $e'),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        if (_creatingNew)
          FilledButton(
            onPressed: _createAndAdd,
            child: const Text('Create & Add'),
          ),
      ],
    );
  }

  Widget _buildNewListField() {
    return TextField(
      controller: _newListNameController,
      decoration: const InputDecoration(
        labelText: 'New List Name',
        hintText: 'e.g., Winter Galaxies',
      ),
      autofocus: true,
      onSubmitted: (_) => _createAndAdd(),
    );
  }

  Future<void> _addToList(int listId) async {
    final notifier = ref.read(observingListNotifierProvider.notifier);
    final id = await notifier.addItem(
      listId: listId,
      objectName: _objectName,
      catalogId: _catalogId,
      objectType: _objectType,
      ra: widget.coordinates.ra,
      dec: widget.coordinates.dec,
      magnitude: widget.object.magnitude,
      sizeArcmin: widget.object is DeepSkyObject
          ? (widget.object as DeepSkyObject).sizeArcMin
          : null,
    );

    if (mounted) {
      Navigator.of(context).pop();
      final uiState = ref.read(observingListNotifierProvider);
      if (id != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added $_objectName to list')),
        );
      } else if (uiState.errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(uiState.errorMessage!)),
        );
      }
    }
  }

  Future<void> _createAndAdd() async {
    final name = _newListNameController.text.trim();
    if (name.isEmpty) return;

    final notifier = ref.read(observingListNotifierProvider.notifier);
    final listId = await notifier.createList(name: name);
    if (listId == null) {
      if (mounted) {
        final uiState = ref.read(observingListNotifierProvider);
        if (uiState.errorMessage != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(uiState.errorMessage!)),
          );
        }
      }
      return;
    }

    await _addToList(listId);
  }
}
