import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import '../../../mixins/device_connection_mixin.dart';
import '../../../utils/device_format_utils.dart';
import '../../../utils/snackbar_helper.dart';
import '../dialogs/fujifilm_disclaimer_dialog.dart';
import '../dialogs/indi_server_dialog.dart';
import '../widgets/backend_selector_chips.dart';

part 'connections/camera_card.dart';
part 'connections/connections_tab_widget.dart';
part 'connections/device_discovery_card.dart';
part 'connections/filter_wheel_card.dart';
part 'connections/focuser_card.dart';
part 'connections/guider_card.dart';
part 'connections/mount_card.dart';
part 'connections/rotator_card.dart';
part 'connections/save_to_profile_dialog.dart';
part 'connections/telescope_card.dart';
part 'connections/unified_base_device_card.dart';
