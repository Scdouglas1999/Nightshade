/// Declarative route table for profile + settings + location endpoints.
///
/// Counterpart to `handlers/profile_handlers.dart`. Three logical
/// surfaces that share a handler class because they all read/write the
/// settings DAO: equipment profiles, app settings, and observer
/// location.
library;

import '../handlers/profile_handlers.dart';
import 'headless_route.dart';

/// Build the declarative route table for [ProfileHandlers].
List<HeadlessRoute> buildProfileRoutes(ProfileHandlers h) => <HeadlessRoute>[
  // Profiles
  HeadlessRoute(HttpMethod.get, '/api/profiles', h.handleGetProfiles),
  HeadlessRoute(HttpMethod.post, '/api/profiles', h.handleSaveProfile),
  HeadlessRoute(
    HttpMethod.delete,
    '/api/profiles/<profileId>',
    h.handleDeleteProfile,
  ),
  HeadlessRoute(
    HttpMethod.post,
    '/api/profiles/<profileId>/load',
    h.handleLoadProfile,
  ),
  HeadlessRoute(
    HttpMethod.get,
    '/api/profiles/active',
    h.handleGetActiveProfile,
  ),

  // Settings
  HeadlessRoute(HttpMethod.get, '/api/settings', h.handleGetSettings),
  HeadlessRoute(HttpMethod.post, '/api/settings', h.handleUpdateSettings),
  HeadlessRoute(HttpMethod.get, '/api/settings/location', h.handleGetLocation),
  HeadlessRoute(HttpMethod.post, '/api/settings/location', h.handleSetLocation),
  HeadlessRoute(
    HttpMethod.get,
    '/api/location',
    h.handleGetLocationFromInternet,
  ),
];
