part of '../equipment_profiles_screen.dart';

class _ProfileList extends StatelessWidget {
  final List<EquipmentProfileModel> profiles;
  final EquipmentProfileModel? selectedProfile;
  final EquipmentProfileModel? activeProfile;
  final ValueChanged<EquipmentProfileModel> onProfileSelected;
  final VoidCallback onCreateProfile;
  final VoidCallback? onImportProfiles;
  final bool isImportingProfiles;
  final bool isMobile;

  const _ProfileList({
    required this.profiles,
    required this.selectedProfile,
    required this.activeProfile,
    required this.onProfileSelected,
    required this.onCreateProfile,
    required this.onImportProfiles,
    required this.isImportingProfiles,
    this.isMobile = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final padding = isMobile ? 16.0 : 20.0;

    Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header - hide on mobile since parent shows it
        if (!isMobile)
          Padding(
            padding: EdgeInsets.all(padding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Equipment Profiles',
                  style: TextStyle(
                    fontSize: NightshadeTypography.fontSize20,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Manage your imaging rigs and configurations',
                  style: TextStyle(
                    fontSize: NightshadeTypography.fontSize12,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),

        // Actions
        Padding(
          padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 16),
          child: Row(
            children: [
              Expanded(
                child: NightshadeButton(
                  label: 'New Profile',
                  icon: LucideIcons.plus,
                  variant: ButtonVariant.primary,
                  onPressed: onCreateProfile,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: onImportProfiles,
                icon: isImportingProfiles
                    ? SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.primary,
                        ),
                      )
                    : Icon(
                        LucideIcons.download,
                        color: colors.textSecondary,
                        size: 18,
                      ),
                tooltip: isImportingProfiles
                    ? 'Importing profiles…'
                    : 'Import profiles',
                style: IconButton.styleFrom(
                  backgroundColor: colors.surfaceAlt,
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(NightshadeTokens.radiusInline8),
                    side: BorderSide(color: colors.border),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Profile list
        Expanded(
          child: profiles.isEmpty
              ? Center(
                  child: Text(
                    'No profiles yet',
                    style: TextStyle(color: colors.textMuted),
                  ),
                )
              : ListView.builder(
                  padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 12),
                  itemCount: profiles.length,
                  itemBuilder: (context, index) {
                    final profile = profiles[index];
                    final isSelected =
                        !isMobile && profile.id == selectedProfile?.id;
                    final isActive = profile.id == activeProfile?.id;

                    return _ProfileListItem(
                      profile: profile,
                      isSelected: isSelected,
                      isActive: isActive,
                      isMobile: isMobile,
                      onTap: () => onProfileSelected(profile),
                    );
                  },
                ),
        ),
      ],
    );

    // On mobile, just return the content without fixed width
    if (isMobile) {
      return content;
    }

    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(right: BorderSide(color: colors.border)),
      ),
      child: content,
    );
  }
}

class _ProfileListItem extends StatefulWidget {
  final EquipmentProfileModel profile;
  final bool isSelected;
  final bool isActive;
  final VoidCallback onTap;
  final bool isMobile;

  const _ProfileListItem({
    required this.profile,
    required this.isSelected,
    required this.isActive,
    required this.onTap,
    this.isMobile = false,
  });

  @override
  State<_ProfileListItem> createState() => _ProfileListItemState();
}

class _ProfileListItemState extends State<_ProfileListItem> {
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
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? NightshadeColors.of(context).primary.withValues(alpha: 0.1)
                : _isHovered
                    ? NightshadeColors.of(context).surfaceAlt
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusLg),
            border: widget.isSelected
                ? Border.all(
                    color: NightshadeColors.of(context)
                        .primary
                        .withValues(alpha: 0.3))
                : null,
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: widget.isActive
                      ? NightshadeColors.of(context)
                          .primary
                          .withValues(alpha: 0.2)
                      : NightshadeColors.of(context).surfaceAlt,
                  borderRadius:
                      BorderRadius.circular(NightshadeTokens.radiusInline8),
                ),
                child: Icon(
                  LucideIcons.aperture,
                  size: 18,
                  color: widget.isActive
                      ? NightshadeColors.of(context).primary
                      : NightshadeColors.of(context).textSecondary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.profile.name,
                            style: NightshadeTypography.labelStrong.copyWith(
                                color:
                                    NightshadeColors.of(context).textPrimary),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (widget.isActive) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: NightshadeColors.of(context)
                                  .primary
                                  .withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(
                                  NightshadeTokens.radiusInline4),
                            ),
                            child: Text(
                              'Active',
                              style: TextStyle(
                                fontSize: NightshadeTypography.fontSize10,
                                fontWeight: FontWeight.w600,
                                color: NightshadeColors.of(context).primary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (widget.profile.description != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        widget.profile.description!,
                        style: TextStyle(
                          fontSize: NightshadeTypography.fontSize11,
                          color: NightshadeColors.of(context).textMuted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Profile Details
// ============================================================================
