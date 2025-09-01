import 'dart:io' show Platform;

class API {
  // Use 10.0.2.2 when running on Android emulator to reach host machine
  static String get hostConnectBase => Platform.isAndroid
      ? 'http://10.0.2.2/api_drivers'
      : 'http://192.168.1.8/api_drivers';

  static String get hostConnectDriver => "$hostConnectBase/driver";

  //login
  static String get login => "$hostConnectDriver/login.php";
  // driver endpoints
  static String get orders => "$hostConnectDriver/orders.php";
  static String get updateStatus => "$hostConnectDriver/update_status.php";
}
