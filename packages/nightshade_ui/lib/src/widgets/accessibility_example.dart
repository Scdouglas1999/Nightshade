import 'package:flutter/material.dart';
import '../theme/nightshade_colors.dart';
import '../components/nightshade_button.dart';
import 'error_dialog.dart';
import 'accessible_icon_button.dart';
import 'focus_traversal_scaffold.dart';

/// Example screen demonstrating accessibility and error handling features.
///
/// This file serves as both a reference implementation and a testbed
/// for the accessibility features added to Nightshade UI.
///
/// Features demonstrated:
/// - ErrorDialog with user-friendly messages
/// - AccessibleIconButton with semantic labels
/// - FocusTraversalScaffold for keyboard navigation
/// - FocusOrderedWidget for custom tab order
/// - Proper Semantics throughout
class AccessibilityExampleScreen extends StatefulWidget {
  const AccessibilityExampleScreen({super.key});

  @override
  State<AccessibilityExampleScreen> createState() =>
      _AccessibilityExampleScreenState();
}

class _AccessibilityExampleScreenState
    extends State<AccessibilityExampleScreen> {
  final _nameController = TextEditingController();
  bool _isProcessing = false;
  String _status = 'Idle';

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _simulateSuccess() async {
    setState(() {
      _isProcessing = true;
      _status = 'Processing...';
    });

    await Future.delayed(const Duration(seconds: 1));

    if (mounted) {
      setState(() {
        _isProcessing = false;
        _status = 'Success!';
      });
    }
  }

  Future<void> _simulateError() async {
    setState(() {
      _isProcessing = true;
      _status = 'Processing...';
    });

    await Future.delayed(const Duration(seconds: 1));

    if (mounted) {
      setState(() {
        _isProcessing = false;
        _status = 'Error occurred';
      });

      // Show error dialog
      ErrorDialog.show(
        context,
        title: 'Connection Timeout',
        message:
            'The operation took too long to complete. Please check your network connection and try again.',
        technicalDetails:
            'SocketException: Failed to connect to example.com:443\n'
            'Cause: Network is unreachable\n'
            'Stack trace: ...',
        onRetry: _simulateError,
      );
    }
  }

  Future<void> _simulateAutoError() async {
    try {
      setState(() {
        _isProcessing = true;
        _status = 'Processing...';
      });

      await Future.delayed(const Duration(seconds: 1));
      throw Exception('Network timeout after 30 seconds');
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _status = 'Auto error handled';
        });

        // Use ErrorMessageHelper for automatic message generation
        ErrorMessageHelper.showError(
          context,
          error: e,
          onRetry: _simulateAutoError,
        );
      }
    }
  }

  void _resetStatus() {
    setState(() => _status = 'Reset');
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        title: Semantics(
          header: true,
          child: Text(
            'Accessibility Example',
            style: TextStyle(color: colors.textPrimary),
          ),
        ),
        actions: [
          AccessibleIconButton(
            icon: Icons.help_outline,
            label: 'Show help',
            tooltip: 'Help',
            onPressed: () => _showHelp(context, colors),
          ),
        ],
      ),
      body: FocusTraversalScaffold(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Semantics(
                header: true,
                child: Text(
                  'Demonstration Screen',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: colors.textPrimary,
                  ),
                ),
              ),

              const SizedBox(height: 8),

              Text(
                'This screen demonstrates accessibility features including '
                'keyboard navigation, screen reader support, and user-friendly error handling.',
                style: TextStyle(
                  fontSize: 14,
                  color: colors.textSecondary,
                ),
              ),

              const SizedBox(height: 32),

              // Status indicator (live region for screen readers)
              Semantics(
                liveRegion: true,
                label: 'Current status: $_status',
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colors.border),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _isProcessing
                            ? Icons.hourglass_empty
                            : Icons.info_outline,
                        color: colors.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Status: $_status',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: colors.textPrimary,
                        ),
                      ),
                      if (_isProcessing) ...[
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colors.primary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // Input section with focus order
              Semantics(
                header: true,
                child: Text(
                  'Form Example',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Text field (tab order 1)
              FocusOrderedWidget(
                order: 1,
                child: Semantics(
                  textField: true,
                  label: 'Name input field',
                  child: TextField(
                    controller: _nameController,
                    style: TextStyle(color: colors.textPrimary),
                    decoration: InputDecoration(
                      labelText: 'Name',
                      labelStyle: TextStyle(color: colors.textMuted),
                      hintText: 'Enter your name',
                      hintStyle:
                          TextStyle(color: colors.textMuted.withValues(alpha: 0.5)),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: colors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: colors.primary),
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // Action buttons section
              Semantics(
                header: true,
                child: Text(
                  'Error Handling Examples',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Buttons with custom tab order (tab order 2-5)
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FocusOrderedWidget(
                    order: 2,
                    child: NightshadeButton(
                      label: 'Success Demo',
                      icon: Icons.check_circle_outline,
                      onPressed: _isProcessing ? null : _simulateSuccess,
                      variant: ButtonVariant.primary,
                    ),
                  ),
                  FocusOrderedWidget(
                    order: 3,
                    child: NightshadeButton(
                      label: 'Error Dialog Demo',
                      icon: Icons.error_outline,
                      onPressed: _isProcessing ? null : _simulateError,
                      variant: ButtonVariant.outline,
                    ),
                  ),
                  FocusOrderedWidget(
                    order: 4,
                    child: NightshadeButton(
                      label: 'Auto Error Demo',
                      icon: Icons.auto_awesome,
                      onPressed: _isProcessing ? null : _simulateAutoError,
                      variant: ButtonVariant.outline,
                    ),
                  ),
                  FocusOrderedWidget(
                    order: 5,
                    child: NightshadeButton(
                      label: 'Reset',
                      icon: Icons.refresh,
                      onPressed: _resetStatus,
                      variant: ButtonVariant.ghost,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 32),

              // Accessibility notes
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colors.primary.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.accessibility_new,
                            color: colors.primary, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Accessibility Features',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildFeatureItem(
                      colors,
                      'Press Tab to navigate between interactive elements',
                    ),
                    _buildFeatureItem(
                      colors,
                      'Press Shift+Tab to navigate backwards',
                    ),
                    _buildFeatureItem(
                      colors,
                      'Press Enter or Space to activate buttons',
                    ),
                    _buildFeatureItem(
                      colors,
                      'Status updates are announced to screen readers',
                    ),
                    _buildFeatureItem(
                      colors,
                      'Error dialogs include both user-friendly and technical details',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureItem(NightshadeColors colors, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check, color: colors.success, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                color: colors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showHelp(BuildContext context, NightshadeColors colors) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text('Help', style: TextStyle(color: colors.textPrimary)),
        content: Text(
          'This screen demonstrates the accessibility and error handling features:\n\n'
          '1. Use Tab/Shift+Tab to navigate\n'
          '2. Try each button to see different error patterns\n'
          '3. Notice how errors are shown with clear, friendly messages\n'
          '4. Technical details are hidden by default but available',
          style: TextStyle(color: colors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close', style: TextStyle(color: colors.primary)),
          ),
        ],
      ),
    );
  }
}
