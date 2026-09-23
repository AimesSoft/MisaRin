import 'package:flutter/foundation.dart';

TargetPlatform resolvedTargetPlatform() {
  return defaultTargetPlatform;
}

bool isResolvedPlatformMacOS() {
  return resolvedTargetPlatform() == TargetPlatform.macOS;
}
