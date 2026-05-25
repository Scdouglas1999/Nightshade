// Developer-only screen used to verify the Rust→Flutter texture spike.
// Once Phase 1 is done, this screen can be removed (Task 122).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:irondash_engine_context/irondash_engine_context.dart';
import 'package:nightshade_bridge/src/api/planetarium_spike.dart' as spike;

class PlanetariumSpikeScreen extends StatefulWidget {
  const PlanetariumSpikeScreen({super.key});

  @override
  State<PlanetariumSpikeScreen> createState() => _PlanetariumSpikeScreenState();
}

class _PlanetariumSpikeScreenState extends State<PlanetariumSpikeScreen>
    with SingleTickerProviderStateMixin {
  int? _handle;
  int? _textureId;
  String? _error;
  Ticker? _ticker;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      final engineHandle = await EngineContext.instance.getEngineHandle();
      final handle = spike.planetariumSpikeCreate(engineHandle: engineHandle);
      final textureId = spike.planetariumSpikeResize(
        handle: handle,
        width: 1280,
        height: 720,
      );
      if (!mounted) return;
      setState(() {
        _handle = handle;
        _textureId = textureId;
      });
      _startTicking(handle);
    } catch (e, st) {
      if (!mounted) return;
      setState(() => _error = '$e\n$st');
    }
  }

  void _startTicking(int handle) {
    _ticker?.dispose();
    _ticker = createTicker((_) {
      try {
        spike.planetariumSpikeTick(handle: handle);
      } catch (e, st) {
        _ticker?.stop();
        if (!mounted) return;
        setState(() => _error = 'Tick failed:\n\n$e\n$st');
      }
    });
    _ticker!.start();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    final handle = _handle;
    if (handle != null) {
      spike.planetariumSpikeDispose(handle: handle);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final body = _error != null
        ? SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: SelectableText(
              'Spike error:\n\n$_error',
              style: const TextStyle(
                color: Colors.redAccent,
                fontFamily: 'monospace',
              ),
            ),
          )
        : _textureId == null
            ? const Center(child: CircularProgressIndicator())
            : Texture(textureId: _textureId!);
    return Scaffold(
      appBar: AppBar(title: const Text('Planetarium spike')),
      body: body,
    );
  }
}
