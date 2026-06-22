import 'package:flutter/foundation.dart' show listEquals, setEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/network_backend.dart';
import '../database/daos/observing_lists_dao.dart';
import '../database/database.dart';
import 'backend_provider.dart';
import 'database_provider.dart';

/// DAO provider for ObservingListsDao.
final observingListsDaoProvider = Provider<ObservingListsDao>((ref) {
  return ObservingListsDao(ref.watch(databaseProvider));
});

/// Reactive stream of all observing lists.
///
/// On a remote SLAVE the local observing-lists tables are never populated — the
/// curated lists live in the HOST DB — so this branches onto the host's
/// `/api/observing-lists` instead of the empty local DAO stream.
final observingListsProvider = StreamProvider<List<ObservingList>>((ref) {
  final backend = ref.watch(backendProvider);
  if (backend is NetworkBackend) {
    return _pollRemoteObservingLists(
      () => backend.getObservingLists(),
      listEquals,
    );
  }
  return ref.watch(observingListsDaoProvider).watchAllLists();
});

/// Reactive stream of items in a specific list.
final observingListItemsProvider =
    StreamProvider.family<List<ObservingListItem>, int>((ref, listId) {
      final backend = ref.watch(backendProvider);
      if (backend is NetworkBackend) {
        return _pollRemoteObservingLists(
          () => backend.getObservingListItems(listId),
          listEquals,
        );
      }
      return ref.watch(observingListsDaoProvider).watchItemsForList(listId);
    });

/// Watch catalog IDs across all observing lists (for planetarium markers).
final listedCatalogIdsProvider = StreamProvider<Set<String>>((ref) {
  final backend = ref.watch(backendProvider);
  if (backend is NetworkBackend) {
    return _pollRemoteObservingLists(
      () => backend.getListedCatalogIds(),
      setEquals,
    );
  }
  return ref.watch(observingListsDaoProvider).watchAllListedCatalogIds();
});

/// Watch catalog IDs for the active list only.
final activeListCatalogIdsProvider = StreamProvider<Set<String>>((ref) {
  final activeId = ref.watch(activeObservingListIdProvider);
  if (activeId == null) {
    return const Stream.empty();
  }
  final backend = ref.watch(backendProvider);
  if (backend is NetworkBackend) {
    return _pollRemoteObservingLists(
      () => backend.getListedCatalogIds(listId: activeId),
      setEquals,
    );
  }
  return ref.watch(observingListsDaoProvider).watchCatalogIdsForList(activeId);
});

/// Currently selected/active observing list ID for the planetarium sidebar.
final activeObservingListIdProvider = StateProvider<int?>((ref) => null);

/// Polls [fetch] every [interval], emitting the first value and thereafter ONLY
/// when the value actually changes (per [unchanged]). The observing-lists
/// tables are not pushed over the event stream, so the slave polls the host the
/// same way `database_provider.dart` polls targets/sessions/images; the
/// change-guard keeps a quiet host from re-emitting an identical payload every
/// tick (which would thrash the planetarium markers and list views).
Stream<T> _pollRemoteObservingLists<T>(
  Future<T> Function() fetch,
  bool Function(T a, T b) unchanged, {
  Duration interval = const Duration(seconds: 10),
}) async* {
  var last = await fetch();
  yield last;
  while (true) {
    await Future.delayed(interval);
    final next = await fetch();
    if (!unchanged(last, next)) {
      last = next;
      yield next;
    }
  }
}

/// StateNotifier for managing observing list UI interactions.
final observingListNotifierProvider =
    StateNotifierProvider<ObservingListNotifier, ObservingListUiState>((ref) {
      return ObservingListNotifier(ref);
    });

/// UI state for observing list management.
class ObservingListUiState {
  final bool isSaving;
  final String? statusMessage;
  final String? errorMessage;

  const ObservingListUiState({
    this.isSaving = false,
    this.statusMessage,
    this.errorMessage,
  });

  ObservingListUiState copyWith({
    bool? isSaving,
    String? statusMessage,
    String? errorMessage,
  }) {
    return ObservingListUiState(
      isSaving: isSaving ?? this.isSaving,
      statusMessage: statusMessage,
      errorMessage: errorMessage,
    );
  }
}

class ObservingListNotifier extends StateNotifier<ObservingListUiState> {
  final Ref ref;

  ObservingListNotifier(this.ref) : super(const ObservingListUiState());

  ObservingListsDao get _dao => ref.read(observingListsDaoProvider);

  /// On a slave, mutations MUST persist on the master, not the slave's
  /// throwaway local DB; this returns the host transport when remote.
  NetworkBackend? get _remote {
    final backend = ref.read(backendProvider);
    return backend is NetworkBackend ? backend : null;
  }

  /// Force the remote-aware list/items/marker streams to re-poll the host
  /// immediately after a slave mutation (otherwise the change is invisible
  /// until the next 10s poll tick).
  void _invalidateRemoteReads() {
    ref.invalidate(observingListsProvider);
    ref.invalidate(observingListItemsProvider);
    ref.invalidate(listedCatalogIdsProvider);
    ref.invalidate(activeListCatalogIdsProvider);
  }

  /// Create a new observing list.
  Future<int?> createList({required String name, String? description}) async {
    state = state.copyWith(isSaving: true, errorMessage: null);
    try {
      final remote = _remote;
      final id = remote != null
          ? await remote.createObservingList(
              name: name,
              description: description,
            )
          : await _dao.createList(name: name, description: description);
      if (remote != null) _invalidateRemoteReads();
      state = state.copyWith(
        isSaving: false,
        statusMessage: 'Created list "$name"',
      );
      return id;
    } catch (e) {
      state = state.copyWith(
        isSaving: false,
        errorMessage: 'Failed to create list: $e',
      );
      return null;
    }
  }

  /// Rename an observing list.
  Future<void> renameList(int id, String newName) async {
    try {
      final remote = _remote;
      if (remote != null) {
        await remote.updateObservingList(id: id, name: newName);
        _invalidateRemoteReads();
      } else {
        await _dao.updateList(id: id, name: newName);
      }
      state = state.copyWith(statusMessage: 'Renamed list to "$newName"');
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to rename list: $e');
    }
  }

  /// Update a list's description.
  Future<void> updateDescription(int id, String? description) async {
    try {
      final remote = _remote;
      if (remote != null) {
        await remote.updateObservingList(id: id, description: description);
        _invalidateRemoteReads();
      } else {
        await _dao.updateList(id: id, description: description);
      }
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to update description: $e');
    }
  }

  /// Delete an observing list.
  Future<void> deleteList(int id) async {
    try {
      final remote = _remote;
      if (remote != null) {
        await remote.deleteObservingList(id);
        _invalidateRemoteReads();
      } else {
        await _dao.deleteList(id);
      }
      // If this was the active list, clear the selection
      if (ref.read(activeObservingListIdProvider) == id) {
        ref.read(activeObservingListIdProvider.notifier).state = null;
      }
      state = state.copyWith(statusMessage: 'List deleted.');
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to delete list: $e');
    }
  }

  /// Duplicate a list and all its items.
  Future<int?> duplicateList(int sourceId) async {
    state = state.copyWith(isSaving: true, errorMessage: null);
    try {
      final remote = _remote;
      final newId = remote != null
          ? await remote.duplicateObservingList(sourceId)
          : await _dao.duplicateList(sourceId);
      if (remote != null) _invalidateRemoteReads();
      state = state.copyWith(
        isSaving: false,
        statusMessage: 'List duplicated.',
      );
      return newId;
    } catch (e) {
      state = state.copyWith(
        isSaving: false,
        errorMessage: 'Failed to duplicate list: $e',
      );
      return null;
    }
  }

  /// Add an object to a list.
  Future<int?> addItem({
    required int listId,
    required String objectName,
    String? catalogId,
    String? objectType,
    required double ra,
    required double dec,
    double? magnitude,
    double? sizeArcmin,
    String? notes,
  }) async {
    state = state.copyWith(isSaving: true, errorMessage: null);
    try {
      final remote = _remote;
      final id = remote != null
          ? await remote.addObservingListItem(
              listId: listId,
              objectName: objectName,
              catalogId: catalogId,
              objectType: objectType,
              ra: ra,
              dec: dec,
              magnitude: magnitude,
              sizeArcmin: sizeArcmin,
              notes: notes,
            )
          : await _dao.addItem(
              listId: listId,
              objectName: objectName,
              catalogId: catalogId,
              objectType: objectType,
              ra: ra,
              dec: dec,
              magnitude: magnitude,
              sizeArcmin: sizeArcmin,
              notes: notes,
            );
      if (remote != null) _invalidateRemoteReads();
      state = state.copyWith(
        isSaving: false,
        statusMessage: 'Added $objectName to list',
      );
      return id;
    } catch (e) {
      state = state.copyWith(isSaving: false, errorMessage: '$e');
      return null;
    }
  }

  /// Remove an item from a list.
  Future<void> removeItem(int itemId) async {
    try {
      final remote = _remote;
      if (remote != null) {
        await remote.removeObservingListItem(itemId);
        _invalidateRemoteReads();
      } else {
        await _dao.removeItem(itemId);
      }
      state = state.copyWith(statusMessage: 'Item removed from list.');
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to remove item: $e');
    }
  }

  /// Update notes on an item.
  Future<void> updateItemNotes(int itemId, String? notes) async {
    try {
      final remote = _remote;
      if (remote != null) {
        await remote.updateObservingListItemNotes(itemId, notes);
        _invalidateRemoteReads();
      } else {
        await _dao.updateItemNotes(itemId, notes);
      }
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to update notes: $e');
    }
  }

  /// Get which lists contain a given catalog ID.
  Future<List<ObservingList>> getListsContaining(String catalogId) {
    final remote = _remote;
    if (remote != null) {
      return remote.getListsContaining(catalogId);
    }
    return _dao.getListsContaining(catalogId);
  }

  /// Clear status/error messages.
  void clearMessages() {
    state = state.copyWith(statusMessage: null, errorMessage: null);
  }
}
