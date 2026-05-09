import 'route_metadata.dart' as route_metadata;

enum HeadlessTokenScope {
  view,
  control,
  admin,
}

HeadlessTokenScope? parseHeadlessTokenScope(String? value) {
  switch (value?.trim().toLowerCase()) {
    case 'view':
    case 'view-only':
    case 'readonly':
    case 'read-only':
      return HeadlessTokenScope.view;
    case 'control':
    case 'imaging-control':
    case 'imaging':
      return HeadlessTokenScope.control;
    case 'admin':
      return HeadlessTokenScope.admin;
    default:
      return null;
  }
}

String headlessTokenScopeName(HeadlessTokenScope scope) {
  switch (scope) {
    case HeadlessTokenScope.view:
      return 'view';
    case HeadlessTokenScope.control:
      return 'control';
    case HeadlessTokenScope.admin:
      return 'admin';
  }
}

class HeadlessAuthPolicy {
  const HeadlessAuthPolicy._();

  static HeadlessTokenScope requiredScopeFor({
    required String method,
    required String path,
  }) {
    final scopeName = route_metadata.requiredAuthScopeNameForEndpoint(
      method: method,
      path: path,
    );
    return parseHeadlessTokenScope(scopeName) ?? HeadlessTokenScope.view;
  }

  static bool allows({
    required HeadlessTokenScope actual,
    required String method,
    required String path,
  }) {
    final required = requiredScopeFor(method: method, path: path);
    return _rank(actual) >= _rank(required);
  }

  static int _rank(HeadlessTokenScope scope) {
    switch (scope) {
      case HeadlessTokenScope.view:
        return 0;
      case HeadlessTokenScope.control:
        return 1;
      case HeadlessTokenScope.admin:
        return 2;
    }
  }
}
