import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_webrtc/nightshade_webrtc.dart';

/// Screen for scanning QR codes to connect to Nightshade servers.
///
/// Pops with one of three results:
///   * [QrConnectionData] — payload was schema-valid, host was local, and the
///     operator confirmed the host+fingerprint sheet.
///   * `null` — operator backed out before a confirmed scan.
///
/// Anything that fails validation surfaces as a snackbar inside the scanner
/// and resumes scanning; the audit specifically calls out that the previous
/// `startsWith('{')` check was too permissive and let arbitrary JSON through.
class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  MobileScannerController? _controller;
  // Two flags so we don't fire detect callbacks while a confirmation sheet is
  // open; releasing on cancel lets the operator try a different code without
  // leaving the scanner.
  bool _hasScanned = false;
  bool _confirming = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_hasScanned || _confirming) return;

    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value == null || value.isEmpty) continue;

      // Mark scanned upfront so a stream of identical detections doesn't queue
      // multiple confirmation sheets.
      _hasScanned = true;
      _confirming = true;

      try {
        final data = QrConnectionData.parseStrict(value);
        final confirmed = await _confirmConnection(data);
        if (!mounted) return;
        if (confirmed) {
          Navigator.of(context).pop(data);
          return;
        }
        // Operator cancelled — let them rescan a different code.
        _confirming = false;
        _hasScanned = false;
        return;
      } on QrValidationException catch (e) {
        if (!mounted) return;
        _confirming = false;
        _hasScanned = false;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Rejected QR code: ${e.message}'),
            duration: const Duration(seconds: 4),
          ),
        );
        return;
      }
    }
  }

  Future<bool> _confirmConnection(QrConnectionData data) async {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.surface,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Confirm pairing',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                Text.rich(
                  TextSpan(
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 15,
                    ),
                    children: [
                      const TextSpan(text: 'Connect to '),
                      TextSpan(
                        text: '${data.host}:${data.webPort}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const TextSpan(
                        text: '?\n\nServer fingerprint: ',
                      ),
                      TextSpan(
                        text: data.shortFingerprint,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Verify this fingerprint matches the desktop app before continuing.',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('Connect'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    return result == true;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        foregroundColor: colors.textPrimary,
        title: const Text('Scan QR Code'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: () => _controller?.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.flip_camera_ios),
            onPressed: () => _controller?.switchCamera(),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                MobileScanner(
                  controller: _controller,
                  onDetect: _onDetect,
                ),
                // Scanning overlay
                Center(
                  child: Container(
                    width: 250,
                    height: 250,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: colors.primary,
                        width: 3,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Instructions
          Container(
            padding: const EdgeInsets.all(24),
            color: colors.surface,
            child: Column(
              children: [
                Text(
                  'Scan the QR code displayed on your Nightshade server',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'The QR code can be found in the desktop app\'s status bar or headless mode console output',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
