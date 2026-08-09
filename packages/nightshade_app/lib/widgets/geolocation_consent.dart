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
      content: Text(
        'Nightshade asks this device for a GPS fix. Desktop computers have '
        'no GPS receiver, so on those it instead sends an HTTPS request to a '
        'third-party geolocation service (ipapi.co, falling back to '
        'ipwho.is) which estimates your position from your public IP '
        'address to roughly city level — about 10 km.\n\n'
        '$outcome',
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
