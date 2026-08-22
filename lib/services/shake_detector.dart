import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// One accelerometer reading, in m/s^2 on each axis.
///
/// The detector takes these rather than the plugin's `AccelerometerEvent` so
/// the shake rules can be tested against synthetic timings instead of real
/// hardware -- there is no way to shake a test runner.
@immutable
class ShakeSample {
  const ShakeSample(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;

  /// Total acceleration in gravities, with gravity itself removed, so a phone
  /// sitting on a table reads ~0 rather than ~1.
  double get gForce => (math.sqrt(x * x + y * y + z * z) / 9.80665 - 1).abs();
}

/// How hard a single reading must be to count as a jolt.
const double kShakeThreshold = 2.7;

/// Readings closer together than this belong to the same jolt. Without it a
/// single swing registers as three at the sensor's sample rate.
const Duration kShakeDebounce = Duration(milliseconds: 120);

/// Jolts must land inside this window of each other to be one shake.
const Duration kShakeWindow = Duration(milliseconds: 1500);

/// Jolts required before the detector fires.
const int kShakeJoltCount = 3;

/// After firing, the detector stays quiet this long. A real shake keeps
/// producing jolts well past the third one, and each of those must not queue
/// another emergency call.
const Duration kShakeCooldown = Duration(seconds: 10);

/// Watches the accelerometer and reports a deliberate shake.
///
/// Deliberately knows nothing about what happens next: the shell decides that
/// a shake means an emergency call, and this decides only what a shake is.
class ShakeDetector {
  ShakeDetector({
    Stream<ShakeSample> Function()? samples,
    DateTime Function()? clock,
  })  : _samples = samples ?? _accelerometer,
        _clock = clock ?? DateTime.now;

  final Stream<ShakeSample> Function() _samples;
  final DateTime Function() _clock;

  StreamSubscription<ShakeSample>? _subscription;
  final List<DateTime> _jolts = <DateTime>[];
  DateTime? _lastFired;

  bool get isRunning => _subscription != null;

  /// Begins listening, calling [onShake] each time a shake is recognised.
  /// Calling it while already running is a no-op, so a lifecycle resume that
  /// races the initial start can't produce two subscriptions.
  void start({required VoidCallback onShake}) {
    if (_subscription != null) return;
    _jolts.clear();
    try {
      _subscription = _samples().listen(
        (sample) => _onSample(sample, onShake),
        // A device with no accelerometer (or a desktop build) reports the
        // failure here. Losing the gesture is not worth taking the app down:
        // every SOS button still works.
        onError: (_) => stop(),
      );
    } catch (_) {
      _subscription = null;
    }
  }

  void stop() {
    _subscription?.cancel();
    _subscription = null;
    _jolts.clear();
  }

  void _onSample(ShakeSample sample, VoidCallback onShake) {
    if (sample.gForce < kShakeThreshold) return;

    final now = _clock();

    final firedAt = _lastFired;
    if (firedAt != null && now.difference(firedAt) < kShakeCooldown) return;

    if (_jolts.isNotEmpty && now.difference(_jolts.last) < kShakeDebounce) {
      return;
    }

    _jolts
      ..add(now)
      ..removeWhere((at) => now.difference(at) > kShakeWindow);

    if (_jolts.length < kShakeJoltCount) return;

    _jolts.clear();
    _lastFired = now;
    onShake();
  }

  static Stream<ShakeSample> _accelerometer() =>
      accelerometerEventStream().map((e) => ShakeSample(e.x, e.y, e.z));
}
