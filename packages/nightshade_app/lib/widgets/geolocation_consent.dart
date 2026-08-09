import 'package:flutter/material.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Ask before a location lookup is allowed to leave the machine.
///
/// Every "find my location" affordance in the app funnels through
/// `GeolocationService`, which tries the device GPS and — on the desktops that
/// have no GPS receiver, i.e. all of them — silently falls back to a
/// third-party HTTPS lookup that resolves the machine's *public IP address*.
/// Nightshade is routinely run on isolated observatory networks, so that
/// request is exactly the kind of thing an operator expects to be asked about
/// first. One shared dialog so Settings and the first-run wizard cannot
/// disagree about what is being sent, or fail to ask at all.
///
/// [outcome] closes the dialog with what the caller will do with the answer,
/// because "replaces your saved site" and "shows you a suggestion" deserve
/// different consent.
Future<bool> confirmGeolocationLookup(
  BuildContext context, {
  required String outcome,
}) async {
  final consented = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Detect this site’s location?'),
      // Without a width constraint this AlertDialog sizes to the window: on
      // the 1600 px desktop it rendered ~1520 px wide, one unbroken line of
      // body text edge to edge, while every other dialog in the app (the
      // sequence-issues list, the unwritable-folder confirm) sits at the
      // 480 px design width. Same constraint helper they use.
      // The Align is load-bearing, not decoration: AlertDialog stretches its
      // content to the dialog's own width, which arrives as a TIGHT
      // constraint, and a ConstrainedBox can only narrow a loose one. Align
      // loosens it, so the body honours the 480 px cap even when the action
      // row is what decides how wide the dialog ends up.
      content: Align(
        alignment: AlignmentDirectional.centerStart,
        child: ConstrainedBox(
          constraints: AdaptiveDialogConstraints.hybrid(
            dialogContext,
            designMaxWidth: 480,
          ),
          child: Text(
            'Nightshade asks this device for a GPS fix. Desktop computers have '
            'no GPS receiver, so on those it instead sends an HTTPS request to a '
            'third-party geolocation service (ipapi.co, falling back to '
            'ipwho.is) which estimates your position from your public IP '
            'address to roughly city level — about 10 km.\n\n'
            '$outcome',
          ),
        ),
      ),
      actions: [
        NightshadeButton(
          label: 'Cancel',
          variant: ButtonVariant.ghost,
          size: ButtonSize.small,
          onPressed: () => Navigator.pop(dialogContext, false),
        ),
        NightshadeButton(
          label: 'Detect location',
          variant: ButtonVariant.primary,
          size: ButtonSize.small,
          onPressed: () => Navigator.pop(dialogContext, true),
        ),
      ],
    ),
  );
  return consented == true;
}

/// Closing paragraph for a lookup that writes straight to the observing site.
const String kGeolocationWritesSiteOutcome =
    'Neither source reports elevation. Latitude and longitude are '
    'replaced; the elevation is kept only if the new position is near '
    'the current one, and is otherwise cleared for you to enter.';

/// Closing paragraph for a lookup that only *offers* a starting point.
const String kGeolocationOffersEstimateOutcome =
    'The result is only shown as a suggested starting point — nothing is '
    'saved to your observing site until you accept it.';
