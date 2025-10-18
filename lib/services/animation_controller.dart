import 'package:flutter/foundation.dart';

/// A tiny service to trigger the motorcycle animation overlay from anywhere.
class MotorcycleAnimationService {
  MotorcycleAnimationService._();
  static final MotorcycleAnimationService instance = MotorcycleAnimationService._();

  // Incrementing integer to notify listeners to play the animation once.
  final ValueNotifier<int> trigger = ValueNotifier<int>(0);

  /// Call to show the motorcycle animation once.
  void show() {
    trigger.value = trigger.value + 1;
  }
}
