import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../localization/nightshade_localizations.dart';
import '../../widgets/contextual_tour_prompt.dart';
import '../../widgets/tutorial_keys/settings_keys.dart';
import 'catalog_settings_screen.dart';
import 'equipment_profiles_screen.dart';
import 'widgets/connection_settings.dart';
import 'widgets/general_settings.dart';
import 'widgets/appearance_settings.dart';
import 'widgets/location_settings.dart';
import 'widgets/imaging_settings.dart';
import 'widgets/autofocus_settings.dart';
import 'widgets/science_settings.dart';
import 'widgets/annotation_settings.dart';
import 'widgets/sequencer_settings.dart';
import 'widgets/plate_solving_settings.dart';
import 'widgets/phd2_guiding_settings.dart';
import 'widgets/notification_settings.dart';
import 'widgets/file_path_settings.dart';
import 'widgets/help_tutorials_settings.dart';
import 'widgets/about_settings.dart';
import 'widgets/calibration_settings.dart';
import 'widgets/dark_library_settings.dart';
import 'widgets/weather_safety_settings.dart';
import 'widgets/remote_access_settings.dart';
import 'widgets/log_viewer.dart';
import 'widgets/auto_save_settings.dart';
import 'widgets/observation_log_settings.dart';
import 'widgets/observing_lists_settings.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  int _selectedCategory = 0;
  // On mobile, null means show the category list; non-null shows the detail
  int? _mobileSelectedCategory;

  List<(String, IconData)> _categories(BuildContext context) {
    final l10n = context.l10n;
    return [
      (l10n.text('settingsConnection'), LucideIcons.wifi),
      (l10n.text('settingsGeneral'), LucideIcons.settings),
      (l10n.text('settingsAppearance'), LucideIcons.palette),
      (l10n.text('settingsLocation'), LucideIcons.mapPin),
      (l10n.text('settingsEquipmentProfiles'), LucideIcons.boxes),
      (l10n.text('settingsCatalogs'), LucideIcons.database),
      (l10n.text('settingsImaging'), LucideIcons.camera),
      (l10n.text('settingsDarkLibrary'), LucideIcons.moon),
      (l10n.text('settingsCalibration'), LucideIcons.sliders),
      (l10n.text('settingsWeatherSafety'), LucideIcons.cloudSun),
      (l10n.text('settingsAutofocus'), LucideIcons.focus),
      (l10n.text('settingsScience'), LucideIcons.flaskConical),
      (l10n.text('settingsAnnotations'), LucideIcons.tag),
      (l10n.text('settingsSequencer'), LucideIcons.listOrdered),
      (l10n.text('settingsPlateSolving'), LucideIcons.crosshair),
      (l10n.text('settingsPhd2Guiding'), LucideIcons.target),
      (l10n.text('settingsNotifications'), LucideIcons.bell),
      (l10n.text('settingsFilePaths'), LucideIcons.folder),
      (l10n.text('settingsRemoteAccess'), LucideIcons.globe),
      (l10n.text('settingsLogs'), LucideIcons.fileText),
      (l10n.text('settingsAutoSave'), LucideIcons.save),
      (l10n.text('settingsObservationLog'), LucideIcons.bookOpen),
      (l10n.text('settingsObservingLists'), LucideIcons.list),
      (l10n.text('settingsHelpTutorials'), LucideIcons.helpCircle),
      (l10n.text('settingsAbout'), LucideIcons.info),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final isMobile = Responsive.isMobile(context);
    final l10n = context.l10n;
    final categories = _categories(context);

    final child = isMobile
        ? _buildMobileLayout(colors, categories)
        : _buildDesktopLayout(colors, categories);

    return ContextualTourPrompt(
      screenId: 'settings',
      tourCategory: TutorialCategory.settingsTour,
      title: l10n.text('settingsTourTitle'),
      description: l10n.text('settingsTourDescription'),
      durationMinutes: 3,
      alignment: Alignment.bottomRight,
      child: FocusTraversalGroup(
        policy: ReadingOrderTraversalPolicy(),
        child: child,
      ),
    );
  }

  Widget _buildMobileLayout(
    NightshadeColors colors,
    List<(String, IconData)> categories,
  ) {
    // If no category selected, show the category list
    if (_mobileSelectedCategory == null) {
      return _MobileCategoryList(
        categories: categories,
        onCategoryTap: (index) {
          setState(() => _mobileSelectedCategory = index);
        },
        colors: colors,
        title: context.l10n.text('settingsTitle'),
      );
    }

    // Show the detail page with a back button
    final categoryIndex = _mobileSelectedCategory!;
    final (categoryName, _) = categories[categoryIndex];

    return Column(
      children: [
        // Mobile header with back button
        Container(
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border(bottom: BorderSide(color: colors.border)),
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    icon:
                        Icon(LucideIcons.arrowLeft, color: colors.textPrimary),
                    onPressed: () {
                      setState(() => _mobileSelectedCategory = null);
                    },
                  ),
                  const SizedBox(width: 8),
                  Text(
                    categoryName,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Content
        Expanded(
          child: _buildContent(colors,
              categoryIndex: categoryIndex, isMobile: true),
        ),
      ],
    );
  }

  Widget _buildDesktopLayout(
    NightshadeColors colors,
    List<(String, IconData)> categories,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Categories sidebar
        ResizablePanel(
          initialWidth: 240,
          minWidth: 180,
          maxWidth: 400,
          side: ResizeSide.right,
          child: Container(
            decoration: BoxDecoration(
              color: colors.surface,
              border: Border(right: BorderSide(color: colors.border)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    context.l10n.text('settingsTitle'),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    key: SettingsTutorialKeys.categories,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: categories.length,
                    itemBuilder: (context, index) {
                      final (label, icon) = categories[index];
                      return _CategoryItem(
                        icon: icon,
                        label: label,
                        isSelected: index == _selectedCategory,
                        onTap: () => setState(() => _selectedCategory = index),
                        colors: colors,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),

        // Settings content
        Expanded(
          child: _buildContent(colors,
              categoryIndex: _selectedCategory, isMobile: false),
        ),
      ],
    );
  }

  Widget _buildContent(NightshadeColors colors,
      {required int categoryIndex, required bool isMobile}) {
    switch (categoryIndex) {
      case 0:
        return ConnectionSettings(colors: colors, isMobile: isMobile);
      case 1:
        return GeneralSettings(colors: colors, isMobile: isMobile);
      case 2:
        return AppearanceSettings(colors: colors, isMobile: isMobile);
      case 3:
        return LocationSettingsPage(colors: colors, isMobile: isMobile);
      case 4:
        return EquipmentProfilesScreen(isMobile: isMobile);
      case 5:
        return CatalogSettingsScreen(isMobile: isMobile);
      case 6:
        return ImagingSettings(colors: colors, isMobile: isMobile);
      case 7:
        return DarkLibrarySettings(colors: colors, isMobile: isMobile);
      case 8:
        return CalibrationSettingsPage(colors: colors, isMobile: isMobile);
      case 9:
        return WeatherSafetySettings(colors: colors, isMobile: isMobile);
      case 10:
        return AutofocusSettingsPage(colors: colors, isMobile: isMobile);
      case 11:
        return ScienceSettingsPage(colors: colors, isMobile: isMobile);
      case 12:
        return AnnotationSettingsPage(colors: colors, isMobile: isMobile);
      case 13:
        return SequencerSettings(colors: colors, isMobile: isMobile);
      case 14:
        return PlateSolvingSettings(colors: colors, isMobile: isMobile);
      case 15:
        return Phd2GuidingSettings(colors: colors, isMobile: isMobile);
      case 16:
        return NotificationSettings(colors: colors, isMobile: isMobile);
      case 17:
        return FilePathSettings(colors: colors, isMobile: isMobile);
      case 18:
        return RemoteAccessSettings(colors: colors, isMobile: isMobile);
      case 19:
        return LogViewer(colors: colors, isMobile: isMobile);
      case 20:
        return AutoSaveSettings(colors: colors, isMobile: isMobile);
      case 21:
        return const ObservationLogSettings();
      case 22:
        return const ObservingListsSettings();
      case 23:
        return HelpTutorialsSettings(colors: colors, isMobile: isMobile);
      case 24:
        return AboutSettings(colors: colors, isMobile: isMobile);
      default:
        return const SizedBox();
    }
  }
}

/// Mobile-optimized category list shown as full-screen list
class _MobileCategoryList extends StatelessWidget {
  final List<(String, IconData)> categories;
  final void Function(int index) onCategoryTap;
  final NightshadeColors colors;
  final String title;

  const _MobileCategoryList({
    required this.categories,
    required this.onCategoryTap,
    required this.colors,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Container(
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border(bottom: BorderSide(color: colors.border)),
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
            ),
          ),
        ),
        // Category list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final (label, icon) = categories[index];
              return _MobileCategoryItem(
                icon: icon,
                label: label,
                onTap: () => onCategoryTap(index),
                colors: colors,
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Mobile category list item
class _MobileCategoryItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final NightshadeColors colors;

  const _MobileCategoryItem({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: colors.border.withValues(alpha: 0.5)),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colors.surfaceAlt,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: colors.textSecondary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: colors.textPrimary,
                ),
              ),
            ),
            Icon(
              LucideIcons.chevronRight,
              size: 20,
              color: colors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final NightshadeColors colors;

  const _CategoryItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.colors,
  });

  @override
  State<_CategoryItem> createState() => _CategoryItemState();
}

class _CategoryItemState extends State<_CategoryItem> {
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
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? widget.colors.primary.withValues(alpha: 0.1)
                : _isHovered
                    ? widget.colors.surfaceAlt
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: widget.isSelected
                ? Border.all(
                    color: widget.colors.primary.withValues(alpha: 0.3))
                : null,
          ),
          child: Row(
            children: [
              Icon(
                widget.icon,
                size: 18,
                color: widget.isSelected
                    ? widget.colors.primary
                    : widget.colors.textSecondary,
              ),
              const SizedBox(width: 12),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight:
                      widget.isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: widget.isSelected
                      ? widget.colors.textPrimary
                      : widget.colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
