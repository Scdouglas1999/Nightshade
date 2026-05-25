/// Barrel export for the Nightshade design-system theme layer.
///
/// **Layer stack** (bottom → top):
/// - [NightshadeColors] — semantic palette (`ThemeExtension`, resolve with `.of`)
/// - [NightshadeTokens] — spacing, radii, motion, shadows
/// - [NightshadeTypography] — type scale
/// - [NightshadeTheme] — `ThemeData` assembly
/// - [NightshadeDecorations] — reusable `BoxDecoration` helpers
/// - Domain `*Colors` classes — chart, annotation, backend protocol hues
library;

export 'annotation_type_colors.dart';
export 'backend_protocol_colors.dart';
export 'nightshade_chart_colors.dart';
export 'nightshade_colors.dart';
export 'nightshade_decorations.dart';
export 'nightshade_theme.dart';
export 'nightshade_tokens.dart';
export 'nightshade_typography.dart';
export '../tokens/shell_chrome_metrics.dart';
