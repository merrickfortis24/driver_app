class API {
  // Fixed to your PC's LAN IP so physical Android devices can reach XAMPP
  static const String hostConnectBase =
      'http://192.168.1.6/naitsa/driver_app/api_drivers';

  static String get hostConnectDriver => "$hostConnectBase/driver";

  //login
  static String get login => "$hostConnectDriver/login.php";
  // driver endpoints
  static String get orders => "$hostConnectDriver/orders.php";
  static String get updateStatus => "$hostConnectDriver/update_status.php";
}
