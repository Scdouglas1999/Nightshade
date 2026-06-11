import 'route_metadata.dart' as route_metadata;

enum HeadlessTokenScope { view, control, admin }

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
    // Public endpoints never reach this check in the middleware (they are
    // short-circuited before token resolution), but keep the mapping
    // truthful for any other caller: public is satisfiable by any scope.
    if (scopeName == 'public') {
      return HeadlessTokenScope.view;
    }
    // Fail CLOSED on anything unrecognised. The route metadata only emits
    // public/view/control/admin today; if a future scope name is added
    // there without updating the parser, the safe failure mode is to
    // require the highest privilege, not silently grant view access.
    return parseHeadlessTokenScope(scopeName) ?? HeadlessTokenScope.admin;
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
