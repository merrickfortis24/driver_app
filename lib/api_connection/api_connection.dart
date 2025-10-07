import 'package:flutter/foundation.dart';

class API {
  // Presets:
  // - Hostinger (production): HTTPS is recommended and avoids Android cleartext issues
  static const String _prodBase = 'https://naitsa.online/api_drivers';
  // - Android emulator to local XAMPP
  //   Using LAN IP since 10.0.2.2 did not respond in this environment
  //   Local PHP APIs are in /naitsa/driver_app/api_drivers in this workspace
  static const String _emulatorBase =
      'http://10.32.33.25/naitsa/driver_app/api_drivers';
  // - Physical device on same Wi‑Fi to local XAMPP (replace with your PC's LAN IP)
  // ignore: unused_field
  static const String _lanBase =
      'http://10.32.33.25/naitsa/driver_app/api_drivers';

  // Optional override via: flutter run --dart-define=API_BASE=https://example.com/api
  static const String _envBase = String.fromEnvironment(
    'API_BASE',
    defaultValue: '',
  );

  static String get _base {
    if (_envBase.isNotEmpty) return _envBase;
    // Debug/profile -> emulator; Release -> production
    return kReleaseMode ? _prodBase : _emulatorBase;
  }

  static String get hostConnectDriver => "$_base/driver";

  // login
  static String get login => "$hostConnectDriver/login.php";
  // driver endpoints
  static String get orders => "$hostConnectDriver/orders.php";
  static String get updateStatus => "$hostConnectDriver/update_status.php";
}
