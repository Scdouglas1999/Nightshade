import 'dart:ffi';
import 'dart:io';

import '../models/update_manifest.dart';

String normalizeUpdatePlatform(String value) {
  return switch (value.trim().toLowerCase()) {
    'win32' || 'win64' => 'windows',
    'darwin' || 'osx' => 'macos',
    final normalized => normalized,
  };
}

String normalizeUpdateArchitecture(String value) {
  return switch (value.trim().toLowerCase()) {
    'amd64' || 'x86_64' || 'x86-64' => 'x64',
    'ia32' || 'i386' || 'i686' => 'x86',
    'aarch64' => 'arm64',
    final normalized => normalized,
  };
}

String currentUpdatePlatform() =>
    normalizeUpdatePlatform(Platform.operatingSystem);

String currentUpdateArchitecture() {
  final abi = Abi.current().toString().split('.').last.toLowerCase();
  if (abi.endsWith('riscv64')) return 'riscv64';
  if (abi.endsWith('riscv32')) return 'riscv32';
  if (abi.endsWith('arm64')) return 'arm64';
  if (abi.endsWith('arm')) return 'arm';
  if (abi.endsWith('x64')) return 'x64';
  if (abi.endsWith('ia32')) return 'x86';
  return normalizeUpdateArchitecture(abi);
}

String? incompatibleUpdateTargetMessage(
  UpdateManifest manifest, {
  required String currentPlatform,
  required String currentArch,
}) {
  final targetPlatform = normalizeUpdatePlatform(manifest.platform);
  final targetArch = normalizeUpdateArchitecture(manifest.arch);
  final hostPlatform = normalizeUpdatePlatform(currentPlatform);
  final hostArch = normalizeUpdateArchitecture(currentArch);
  if (targetPlatform == hostPlatform && targetArch == hostArch) return null;
  return 'Update ${manifest.version}+${manifest.buildNumber} targets '
      '$targetPlatform/$targetArch, but this Nightshade host is '
      '$hostPlatform/$hostArch.';
}
