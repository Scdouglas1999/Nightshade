// Finders the Settings tests share.
//
// `find.byTooltip` matches a Material [Tooltip] widget by its message. The
// design system's [NightshadeIconButton] does not build one: it shows a
// [NightshadeTooltip], an OverlayPortal that exists only while the pointer is
// over the control, and publishes the same string as the button's accessible
// NAME instead. So every icon control migrated in wave 3 became invisible to
// `find.byTooltip` even though it is BETTER labelled than before — the tooltip
// used to be a hover affordance and no name at all.
//
// [findByTooltip] matches either, so a test says what it means ("the control
// whose tooltip is X") without caring which of the two a screen happens to use.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// A control whose tooltip reads [message], whether it is a Material [Tooltip]
/// or a [NightshadeIconButton].
Finder findByTooltip(String message) => find.byWidgetPredicate(
      (widget) =>
          (widget is Tooltip && widget.message == message) ||
          (widget is NightshadeIconButton && widget.tooltip == message),
      description: 'tooltip "$message"',
    );
