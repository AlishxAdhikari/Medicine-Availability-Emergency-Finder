import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:medalert/services/shake_detector.dart';

/// A driver that feeds samples and a clock the detector reads, so a "shake"
/// is expressed as timings rather than as real elapsed time.
class _Rig {
  final StreamController<ShakeSample> controller =
      StreamController<ShakeSample>.broadcast();
  Duration elapsed = Duration.zero;
  int shakes = 0;

  late final ShakeDetector detector = ShakeDetector(
    samples: () => controller.stream,
    clock: () => DateTime.fromMillisecondsSinceEpoch(elapsed.inMilliseconds),
  );

  void start() => detector.start(onShake: () => shakes++);

  /// One accelerometer reading of [gForce] gravities along x, delivered
  /// [afterMs] after the previous one.
  Future<void> sample(double gForce, {int afterMs = 150}) async {
    elapsed += Duration(milliseconds: afterMs);
    controller.add(ShakeSample(gForce * 9.80665, 0, 0));
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> shake({int afterMs = 150}) async {
    for (var i = 0; i < 3; i++) {
      await sample(4.0, afterMs: afterMs);
    }
  }

  Future<void> dispose() async {
    detector.stop();
    await controller.close();
  }
}

void main() {
  test('quiet samples never fire', () async {
    final rig = _Rig()..start();
    for (var i = 0; i < 20; i++) {
      await rig.sample(1.0);
    }
    expect(rig.shakes, 0);
    await rig.dispose();
  });

  test('three hard jolts inside the window fire once', () async {
    final rig = _Rig()..start();
    await rig.shake();
    expect(rig.shakes, 1);
    await rig.dispose();
  });

  test('jolts spread beyond the window do not fire', () async {
    final rig = _Rig()..start();
    for (var i = 0; i < 3; i++) {
      await rig.sample(4.0, afterMs: 900);
    }
    expect(rig.shakes, 0);
    await rig.dispose();
  });

  test('samples closer than the debounce count as one jolt', () async {
    final rig = _Rig()..start();
    for (var i = 0; i < 6; i++) {
      await rig.sample(4.0, afterMs: 20);
    }
    expect(rig.shakes, 0);
    await rig.dispose();
  });

  test('a second shake inside the cooldown is ignored', () async {
    final rig = _Rig()..start();
    await rig.shake();
    await rig.shake();
    expect(rig.shakes, 1);
    await rig.dispose();
  });

  test('a shake after the cooldown fires again', () async {
    final rig = _Rig()..start();
    await rig.shake();
    await rig.sample(1.0, afterMs: kShakeCooldown.inMilliseconds + 1);
    await rig.shake();
    expect(rig.shakes, 2);
    await rig.dispose();
  });

  test('stop() ends the subscription', () async {
    final rig = _Rig()..start();
    rig.detector.stop();
    await rig.shake();
    expect(rig.shakes, 0);
    await rig.dispose();
  });

  test('start() twice does not double-count a single shake', () async {
    final rig = _Rig()..start();
    rig.start();
    await rig.shake();
    expect(rig.shakes, 1);
    await rig.dispose();
  });
}
