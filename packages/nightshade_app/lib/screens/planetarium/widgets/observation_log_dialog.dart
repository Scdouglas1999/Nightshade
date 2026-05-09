import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Dialog for quickly logging an observation from the planetarium view.
/// Pre-fills object name, coordinates, altitude, current time.
class ObservationLogDialog extends ConsumerStatefulWidget {
  final CelestialObject object;
  final CelestialCoordinate coordinates;
  final (double, double)? altAz; // (altitude, azimuth)

  const ObservationLogDialog({
    super.key,
    required this.object,
    required this.coordinates,
    this.altAz,
  });

  @override
  ConsumerState<ObservationLogDialog> createState() =>
      _ObservationLogDialogState();
}

class _ObservationLogDialogState extends ConsumerState<ObservationLogDialog> {
  final _notesController = TextEditingController();
  int _rating = 3;
  String _seeingConditions = 'good';
  String _transparency = 'good';
  bool _isSaving = false;

  static const _conditionOptions = ['excellent', 'good', 'fair', 'poor'];

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  String _getObjectType() {
    final obj = widget.object;
    if (obj is Star) return 'star';
    if (obj is DeepSkyObject) {
      if (obj.type.isGalaxy) return 'galaxy';
      if (obj.type.isNebula) return 'nebula';
      if (obj.type.isCluster) return 'cluster';
      return obj.type.displayName.toLowerCase();
    }
    return 'object';
  }

  String? _getCatalogId() {
    final obj = widget.object;
    if (obj is DeepSkyObject) {
      if (obj.isMessier) return obj.messierNumber;
      final ngcIc = obj.ngcIcDesignation;
      if (ngcIc != null) return ngcIc;
    }
    return obj.id;
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);

    // Read location data
    final location = ref.read(observerLocationProvider);
    final activeProfile = ref.read(activeProfileProvider).valueOrNull;

    final notifier = ref.read(observationLogNotifierProvider.notifier);
    final id = await notifier.logObservation(
      timestamp: DateTime.now(),
      objectName: widget.object.name,
      ra: widget.coordinates.ra,
      dec: widget.coordinates.dec,
      objectType: _getObjectType(),
      catalogId: _getCatalogId(),
      altitude: widget.altAz?.$1,
      azimuth: widget.altAz?.$2,
      notes: _notesController.text.isNotEmpty ? _notesController.text : null,
      rating: _rating,
      equipmentProfileId: activeProfile?.id,
      seeingConditions: _seeingConditions,
      transparency: _transparency,
      locationName: location.locationName,
      latitude: location.latitude,
      longitude: location.longitude,
    );

    if (mounted) {
      Navigator.of(context).pop(id != null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return AlertDialog(
      backgroundColor: colors.surface,
      title: Row(
        children: [
          Icon(LucideIcons.bookOpen, color: colors.primary, size: 20),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Log Observation',
              style: TextStyle(fontSize: 18),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Object info (read-only)
              _InfoRow(
                label: 'Object',
                value: widget.object.name,
                colors: colors,
              ),
              const SizedBox(height: 8),
              _InfoRow(
                label: 'RA / Dec',
                value:
                    '${widget.coordinates.ra.toStringAsFixed(4)}h / ${widget.coordinates.dec.toStringAsFixed(4)}°',
                colors: colors,
              ),
              if (widget.altAz != null) ...[
                const SizedBox(height: 8),
                _InfoRow(
                  label: 'Alt / Az',
                  value:
                      '${widget.altAz!.$1.toStringAsFixed(1)}° / ${widget.altAz!.$2.toStringAsFixed(1)}°',
                  colors: colors,
                ),
              ],
              const SizedBox(height: 8),
              _InfoRow(
                label: 'Time',
                value: _formatTimestamp(DateTime.now()),
                colors: colors,
              ),

              const SizedBox(height: 16),
              Divider(color: colors.border),
              const SizedBox(height: 16),

              // Rating
              Text(
                'Rating',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: List.generate(5, (index) {
                  final starNum = index + 1;
                  return GestureDetector(
                    onTap: () => setState(() => _rating = starNum),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(
                        starNum <= _rating
                            ? LucideIcons.star
                            : LucideIcons.star,
                        size: 28,
                        color: starNum <= _rating
                            ? Colors.amber
                            : colors.textSecondary.withValues(alpha: 0.3),
                      ),
                    ),
                  );
                }),
              ),

              const SizedBox(height: 16),

              // Seeing conditions
              Text(
                'Seeing',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              _ConditionSelector(
                options: _conditionOptions,
                selected: _seeingConditions,
                onChanged: (v) => setState(() => _seeingConditions = v),
                colors: colors,
              ),

              const SizedBox(height: 16),

              // Transparency
              Text(
                'Transparency',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              _ConditionSelector(
                options: _conditionOptions,
                selected: _transparency,
                onChanged: (v) => setState(() => _transparency = v),
                colors: colors,
              ),

              const SizedBox(height: 16),

              // Notes
              Text(
                'Notes',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _notesController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Observation notes...',
                  hintStyle: TextStyle(color: colors.textSecondary),
                  filled: true,
                  fillColor: colors.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: colors.primary),
                  ),
                  contentPadding: const EdgeInsets.all(12),
                ),
                style: TextStyle(color: colors.textPrimary, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
      actions: [
        NightshadeButton(
          onPressed: () => Navigator.of(context).pop(false),
          label: 'Cancel',
          variant: ButtonVariant.ghost,
          size: ButtonSize.small,
        ),
        NightshadeButton(
          onPressed: _isSaving ? null : _save,
          label: _isSaving ? 'Saving...' : 'Log Observation',
          variant: ButtonVariant.primary,
          size: ButtonSize.small,
        ),
      ],
    );
  }

  String _formatTimestamp(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final NightshadeColors colors;

  const _InfoRow({
    required this.label,
    required this.value,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 70,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: colors.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: colors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

class _ConditionSelector extends StatelessWidget {
  final List<String> options;
  final String selected;
  final ValueChanged<String> onChanged;
  final NightshadeColors colors;

  const _ConditionSelector({
    required this.options,
    required this.selected,
    required this.onChanged,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: options.map((option) {
        final isSelected = option == selected;
        return GestureDetector(
          onTap: () => onChanged(option),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isSelected
                  ? colors.primary.withValues(alpha: 0.2)
                  : colors.background,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isSelected
                    ? colors.primary
                    : colors.border,
              ),
            ),
            child: Text(
              option[0].toUpperCase() + option.substring(1),
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? colors.primary : colors.textSecondary,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
