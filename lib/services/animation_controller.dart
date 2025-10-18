import 'package:flutter/foundation.dart';

/// A tiny service to trigger the motorcycle animation overlay from anywhere.
class MotorcycleAnimationService {
  MotorcycleAnimationService._();
  static final MotorcycleAnimationService instance =
      MotorcycleAnimationService._();

  // Incrementing integer to notify listeners to play the animation once.
  final ValueNotifier<int> trigger = ValueNotifier<int>(0);

  /// Call to show the motorcycle animation once.
  // Last-play parameters that the overlay will read when trigger increments.
  double lastSize = 56.0;
  bool lastUseLottie = false;
  String? lastSoundAsset;

  /// Call to show the motorcycle animation once with optional parameters.
  /// - size: logical pixel size for the animation
  /// - useLottie: if true the overlay will try to render a Lottie animation
  /// - soundAsset: optional asset path to play with audioplayers (e.g. 'assets/sfx/moto.mp3')
  void show({double size = 56.0, bool useLottie = false, String? soundAsset}) {
    lastSize = size;
    lastUseLottie = useLottie;
    lastSoundAsset = soundAsset;
    trigger.value = trigger.value + 1;
  }
}
