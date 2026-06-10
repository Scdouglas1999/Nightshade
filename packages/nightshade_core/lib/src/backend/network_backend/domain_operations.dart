part of '../network_backend.dart';

mixin _NetworkBackendDomainOperations on _NetworkBackendTransport {
  // =========================================================================
  // Target Management
  // =========================================================================

  /// Get all targets from the headless server
  /// Returns JSON maps that can be used to construct CelestialTarget objects
  Future<List<Map<String, dynamic>>> getAllTargets() async {
    final response = await _get('targets');
    final targetsList = response['targets'] as List? ?? [];
    return targetsList.cast<Map<String, dynamic>>();
  }

  /// Get a specific target by ID
  Future<Map<String, dynamic>?> getTargetById(int id) async {
    try {
      final response = await _get('targets/$id');
      return response['target'] as Map<String, dynamic>?;
    } catch (e) {
      developer.log(
        'Failed to get target $id: $e',
        name: 'NetworkBackend',
        level: 1000,
        error: e,
      );
      return null;
    }
  }

  /// Search targets by query string
  Future<List<Map<String, dynamic>>> searchTargets(String query) async {
    final response = await _get('targets/search', {'query': query});
    final targetsList = response['targets'] as List? ?? [];
    return targetsList.cast<Map<String, dynamic>>();
  }

  /// Create a new target
  Future<int> createTarget(Map<String, dynamic> target) async {
    final response = await _post('targets', target);
    return response['id'] as int;
  }

  /// Update an existing target
  Future<void> updateTarget(int id, Map<String, dynamic> target) async {
    await _put('targets/$id', target);
  }

  /// Delete a target
  Future<void> deleteTarget(int id) async {
    await _delete('targets/$id');
  }

  /// Toggle favorite status for a target
  Future<void> toggleTargetFavorite(int id) async {
    await _post('targets/$id/favorite');
  }

  /// Update target progress
  Future<void> updateTargetProgress(
    int id, {
    int? capturedSubs,
    double? totalIntegrationSecs,
  }) async {
    await _put('targets/$id/progress', {
      if (capturedSubs != null) 'capturedSubs': capturedSubs,
      if (totalIntegrationSecs != null)
        'totalIntegrationSecs': totalIntegrationSecs,
    });
  }

  /// Get favorite targets
  Future<List<Map<String, dynamic>>> getFavoriteTargets() async {
    final response = await _get('targets/favorites');
    final targetsList = response['targets'] as List? ?? [];
    return targetsList.cast<Map<String, dynamic>>();
  }

  /// Get targets by object type
  Future<List<Map<String, dynamic>>> getTargetsByType(String objectType) async {
    final response = await _get('targets/by-type', {'type': objectType});
    final targetsList = response['targets'] as List? ?? [];
    return targetsList.cast<Map<String, dynamic>>();
  }

  /// Get targets by priority
  Future<List<Map<String, dynamic>>> getTargetsByPriority(int priority) async {
    final response = await _get('targets/by-priority', {
      'priority': priority.toString(),
    });
    final targetsList = response['targets'] as List? ?? [];
    return targetsList.cast<Map<String, dynamic>>();
  }

  // =========================================================================
  // Sequence Management (CRUD - separate from sequencer execution)
  // =========================================================================

  /// Get all sequences
  Future<List<Map<String, dynamic>>> getSequenceList() async {
    final response = await _get('sequence-management/list');
    final sequencesList = response['sequences'] as List? ?? [];
    return sequencesList.cast<Map<String, dynamic>>();
  }

  /// Get all sequence templates
  Future<List<Map<String, dynamic>>> getSequenceTemplates() async {
    final response = await _get('sequence-management/templates');
    final templatesList = response['templates'] as List? ?? [];
    return templatesList.cast<Map<String, dynamic>>();
  }

  /// Get a specific sequence by ID
  Future<Map<String, dynamic>?> getSequenceDetails(int id) async {
    try {
      final response = await _get('sequence-management/$id');
      return response['sequence'] as Map<String, dynamic>?;
    } catch (e) {
      developer.log(
        'Failed to get sequence $id: $e',
        name: 'NetworkBackend',
        level: 1000,
        error: e,
      );
      return null;
    }
  }

  /// Get nodes for a sequence
  Future<List<Map<String, dynamic>>> getSequenceNodes(int sequenceId) async {
    final response = await _get('sequence-management/$sequenceId/nodes');
    final nodesList = response['nodes'] as List? ?? [];
    return nodesList.cast<Map<String, dynamic>>();
  }

  /// Create a new sequence
  Future<int> createSequence(Map<String, dynamic> sequence) async {
    final response = await _post('sequence-management', sequence);
    return response['id'] as int;
  }

  /// Update an existing sequence
  Future<void> updateSequence(int id, Map<String, dynamic> sequence) async {
    await _put('sequence-management/$id', sequence);
  }

  /// Delete a sequence
  Future<void> deleteSequence(int id) async {
    await _delete('sequence-management/$id');
  }

  /// Duplicate a sequence
  Future<int> duplicateSequence(int sourceId, String newName) async {
    final response = await _post('sequence-management/$sourceId/duplicate', {
      'newName': newName,
    });
    return response['id'] as int;
  }

  /// Save a full sequence document to the host database.
  Future<int> saveFullSequence(
    Map<String, dynamic> sequence, {
    bool isTemplate = false,
    int? databaseId,
  }) async {
    final response = await _post('sequence-management/save-full', {
      'sequence': sequence,
      'isTemplate': isTemplate,
      if (databaseId != null) 'databaseId': databaseId,
    });
    return response['id'] as int;
  }

  /// Load all sequences with full node trees from the host.
  Future<List<Map<String, dynamic>>> listFullSequences() async {
    final response = await _get('sequence-management/list-full');
    final sequencesList = response['sequences'] as List? ?? [];
    return sequencesList.cast<Map<String, dynamic>>();
  }

  /// Load all templates with full node trees from the host.
  Future<List<Map<String, dynamic>>> listFullTemplates() async {
    final response = await _get('sequence-management/templates-full');
    final templatesList = response['templates'] as List? ?? [];
    return templatesList.cast<Map<String, dynamic>>();
  }

  /// Create a new sequence node
  Future<void> createSequenceNode(
    int sequenceId,
    Map<String, dynamic> node,
  ) async {
    await _post('sequence-management/$sequenceId/nodes', node);
  }

  /// Update a sequence node
  Future<void> updateSequenceNode(
    String nodeId,
    Map<String, dynamic> node,
  ) async {
    await _put('sequence-management/nodes/$nodeId', node);
  }

  /// Delete a sequence node
  Future<void> deleteSequenceNode(String nodeId) async {
    await _delete('sequence-management/nodes/$nodeId');
  }

  /// Reorder sequence nodes
  Future<void> reorderSequenceNodes(
    int sequenceId,
    List<String> nodeIds,
  ) async {
    await _post('sequence-management/$sequenceId/reorder', {
      'nodeIds': nodeIds,
    });
  }

  // =========================================================================
  // Flat Wizard
  // =========================================================================

  /// Calibrate a single filter for flat frames
  Future<Map<String, dynamic>> flatWizardCalibrateFilter({
    required String deviceId,
    required String filter,
    required int targetAdu,
    required int tolerance,
    double minExposure = 0.001,
    double maxExposure = 30.0,
    int? gain,
    int binning = 1,
  }) async {
    final response = await _post('flat-wizard/calibrate', {
      'deviceId': deviceId,
      'filter': filter,
      'targetAdu': targetAdu,
      'tolerance': tolerance,
      'minExposure': minExposure,
      'maxExposure': maxExposure,
      if (gain != null) 'gain': gain,
      'binning': binning,
    });
    return response;
  }

  /// Calibrate multiple filters for flat frames
  Future<Map<String, dynamic>> flatWizardCalibrateMultiple({
    required String deviceId,
    required List<String> filters,
    required int targetAdu,
    required int tolerance,
    double minExposure = 0.001,
    double maxExposure = 30.0,
    int? gain,
    int binning = 1,
  }) async {
    final response = await _post('flat-wizard/calibrate-multi', {
      'deviceId': deviceId,
      'filters': filters,
      'targetAdu': targetAdu,
      'tolerance': tolerance,
      'minExposure': minExposure,
      'maxExposure': maxExposure,
      if (gain != null) 'gain': gain,
      'binning': binning,
    });
    return response;
  }

  /// Generate a flat frame sequence from calibration results
  Future<Map<String, dynamic>> flatWizardGenerateSequence({
    required List<Map<String, dynamic>> calibrations,
    required int framesPerFilter,
    String sequenceName = 'Flat Frames',
    bool dither = false,
  }) async {
    final response = await _post('flat-wizard/generate-sequence', {
      'calibrations': calibrations,
      'framesPerFilter': framesPerFilter,
      'sequenceName': sequenceName,
      'dither': dither,
    });
    return response;
  }

  // =========================================================================
  // Mosaic Planning
  // =========================================================================

  /// Generate mosaic panels
  Future<Map<String, dynamic>> mosaicGeneratePanels(
    Map<String, dynamic> config,
  ) async {
    final response = await _post('mosaic/generate-panels', config);
    return response;
  }

  /// Generate a mosaic sequence
  Future<Map<String, dynamic>> mosaicGenerateSequence({
    required Map<String, dynamic> config,
    required Map<String, dynamic> exposureSettings,
    required Map<String, dynamic> options,
  }) async {
    final response = await _post('mosaic/generate-sequence', {
      'config': config,
      'exposureSettings': exposureSettings,
      'options': options,
    });
    return response;
  }

  /// Calculate mosaic area
  Future<Map<String, dynamic>> mosaicCalculateArea(
    Map<String, dynamic> config,
  ) async {
    final response = await _post('mosaic/calculate-area', config);
    return response;
  }

  /// Validate mosaic configuration
  Future<Map<String, dynamic>> mosaicValidate(
    Map<String, dynamic> config,
  ) async {
    final response = await _post('mosaic/validate', config);
    return response;
  }
}
