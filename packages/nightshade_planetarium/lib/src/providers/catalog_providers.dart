import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../catalogs/catalog_manager.dart';
import '../catalogs/catalog.dart';
import '../catalogs/star_catalog.dart';
import '../celestial_object.dart';

/// State for catalog installation status
class CatalogState {
  final CatalogStatus starCatalogStatus;
  final CatalogStatus dsoCatalogStatus;
  final bool isInitialized;
  final bool isDownloading;
  final double downloadProgress;
  final String? downloadError;
  
  const CatalogState({
    this.starCatalogStatus = const CatalogStatus(isInstalled: false),
    this.dsoCatalogStatus = const CatalogStatus(isInstalled: false),
    this.isInitialized = false,
    this.isDownloading = false,
    this.downloadProgress = 0,
    this.downloadError,
  });
  
  bool get catalogsInstalled => 
    starCatalogStatus.isInstalled && dsoCatalogStatus.isInstalled;
  
  bool get anyCatalogInstalled => 
    starCatalogStatus.isInstalled || dsoCatalogStatus.isInstalled;
  
  int get totalStarCount => starCatalogStatus.objectCount ?? 0;
  int get totalDsoCount => dsoCatalogStatus.objectCount ?? 0;
  
  CatalogState copyWith({
    CatalogStatus? starCatalogStatus,
    CatalogStatus? dsoCatalogStatus,
    bool? isInitialized,
    bool? isDownloading,
    double? downloadProgress,
    String? downloadError,
  }) {
    return CatalogState(
      starCatalogStatus: starCatalogStatus ?? this.starCatalogStatus,
      dsoCatalogStatus: dsoCatalogStatus ?? this.dsoCatalogStatus,
      isInitialized: isInitialized ?? this.isInitialized,
      isDownloading: isDownloading ?? this.isDownloading,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      downloadError: downloadError,
    );
  }
}

/// Notifier for managing catalog state
class CatalogStateNotifier extends StateNotifier<CatalogState> {
  CatalogStateNotifier() : super(const CatalogState());
  
  /// Initialize the catalog manager and check status
  Future<void> initialize(String catalogDirectory) async {
    try {
      await CatalogManager.instance.initialize(catalogDirectory);
      await refreshStatus();
      state = state.copyWith(isInitialized: true);
    } catch (e) {
      state = state.copyWith(
        isInitialized: true,
        downloadError: 'Failed to initialize: $e',
      );
    }
  }
  
  /// Refresh catalog status
  Future<void> refreshStatus() async {
    try {
      final starStatus = await CatalogManager.instance.getStarCatalogStatus();
      final dsoStatus = await CatalogManager.instance.getDsoCatalogStatus();
      
      state = state.copyWith(
        starCatalogStatus: starStatus,
        dsoCatalogStatus: dsoStatus,
        downloadError: null,
      );
    } catch (e) {
      state = state.copyWith(downloadError: 'Failed to check status: $e');
    }
  }
  
  /// Download catalogs with the specified package
  Future<bool> downloadCatalogs(CatalogPackage package) async {
    state = state.copyWith(
      isDownloading: true,
      downloadProgress: 0,
      downloadError: null,
    );
    
    try {
      // Download star catalog
      final starSuccess = await CatalogManager.instance.downloadStarCatalog(
        package: package,
        onProgress: (progress) {
          state = state.copyWith(
            downloadProgress: progress.progress * 0.5,
          );
        },
      );
      
      if (!starSuccess) {
        throw Exception('Star catalog download failed');
      }
      
      // Download DSO catalog
      final dsoSuccess = await CatalogManager.instance.downloadDsoCatalog(
        package: package,
        onProgress: (progress) {
          state = state.copyWith(
            downloadProgress: 0.5 + (progress.progress * 0.5),
          );
        },
      );
      
      if (!dsoSuccess) {
        throw Exception('DSO catalog download failed');
      }
      
      await refreshStatus();
      state = state.copyWith(
        isDownloading: false,
        downloadProgress: 1.0,
      );
      
      return true;
    } catch (e) {
      state = state.copyWith(
        isDownloading: false,
        downloadError: e.toString(),
      );
      return false;
    }
  }
  
  /// Delete all catalogs
  Future<void> deleteCatalogs() async {
    await CatalogManager.instance.deleteCatalogs();
    await refreshStatus();
  }
}

/// Provider for catalog state
final catalogStateProvider = StateNotifierProvider<CatalogStateNotifier, CatalogState>(
  (ref) => CatalogStateNotifier(),
);

/// Provider for whether catalogs need to be downloaded
final catalogsNeedDownloadProvider = Provider<bool>((ref) {
  final state = ref.watch(catalogStateProvider);
  return state.isInitialized && !state.catalogsInstalled;
});

/// Provider for the star catalog
final starCatalogProvider = Provider<HygStarCatalog>((ref) {
  return HygStarCatalog();
});

/// Provider for the DSO catalog
final dsoCatalogProvider = Provider<OpenNgcDsoCatalog>((ref) {
  return OpenNgcDsoCatalog();
});

/// Provider for loading stars
final starsProvider = FutureProvider<List<Star>>((ref) async {
  final catalog = ref.watch(starCatalogProvider);
  return catalog.loadObjects();
});

/// Provider for loading DSOs
final dsosProvider = FutureProvider<List<DeepSkyObject>>((ref) async {
  final catalog = ref.watch(dsoCatalogProvider);
  return catalog.loadObjects();
});

/// Provider for star count
final starCountProvider = FutureProvider<int>((ref) async {
  final stars = await ref.watch(starsProvider.future);
  return stars.length;
});

/// Provider for DSO count
final dsoCountProvider = FutureProvider<int>((ref) async {
  final dsos = await ref.watch(dsosProvider.future);
  return dsos.length;
});

/// Provider for searching stars
final starSearchProvider = FutureProvider.family<List<Star>, String>((ref, query) async {
  if (query.isEmpty) return [];
  final catalog = ref.watch(starCatalogProvider);
  return catalog.search(query);
});

/// Provider for searching DSOs
final dsoSearchProvider = FutureProvider.family<List<DeepSkyObject>, String>((ref, query) async {
  if (query.isEmpty) return [];
  final catalog = ref.watch(dsoCatalogProvider);
  return catalog.search(query);
});

/// Provider for Messier objects only
final messierObjectsProvider = FutureProvider<List<DeepSkyObject>>((ref) async {
  final catalog = ref.watch(dsoCatalogProvider);
  return catalog.getMessierObjects();
});

/// Provider for bright stars (magnitude < 6.0)
final brightStarsProvider = FutureProvider<List<Star>>((ref) async {
  final catalog = ref.watch(starCatalogProvider);
  return catalog.getStarsByMagnitude(6.0);
});

/// Provider for visible DSOs (magnitude < 10.0)
final visibleDsosProvider = FutureProvider<List<DeepSkyObject>>((ref) async {
  final catalog = ref.watch(dsoCatalogProvider);
  return catalog.getByMagnitude(10.0);
});





