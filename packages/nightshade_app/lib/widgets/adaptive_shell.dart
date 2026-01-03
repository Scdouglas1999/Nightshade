import 'package:flutter/material.dart';
import 'package:nightshade_app/screens/shell/app_shell.dart';

class AdaptiveShell extends StatelessWidget {
  final bool isMobile;
  final bool isDesktop;
  final Widget child;
  
  const AdaptiveShell({
    required this.child,
    this.isMobile = false,
    this.isDesktop = false,
    super.key,
  });
  
  @override
  Widget build(BuildContext context) {
    // Currently we reuse the AppShell which seems to be designed for desktop
    // We might need to adapt it or use a different shell for mobile
    // For now, let's use the existing AppShell as it likely handles navigation
    
    // If AppShell is already responsive, we just use it.
    // If not, we might need to wrap it or configure it.
    
    return AppShell(child: child);
  }
}
