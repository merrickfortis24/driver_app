import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeController {
  ThemeController._();
  static final ThemeController instance = ThemeController._();

  static const _prefKey = 'themeMode'; // values: light | dark | system
  final ValueNotifier<ThemeMode> mode = ValueNotifier<ThemeMode>(ThemeMode.light);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_prefKey);
    switch (s) {
      case 'dark':
        mode.value = ThemeMode.dark;
        break;
      case 'system':
        mode.value = ThemeMode.system;
        break;
      case 'light':
      default:
        mode.value = ThemeMode.light;
        break;
    }
  }

  Future<void> set(ThemeMode m) async {
    mode.value = m;
    final prefs = await SharedPreferences.getInstance();
    final s = m == ThemeMode.dark
        ? 'dark'
        : (m == ThemeMode.system ? 'system' : 'light');
    await prefs.setString(_prefKey, s);
  }

  Future<void> toggleLightDark() async {
    final next = mode.value == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    await set(next);
  }
}
