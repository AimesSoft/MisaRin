import 'dart:async';

// These widget tests do not use the Rust canvas engine.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await testMain();
}
