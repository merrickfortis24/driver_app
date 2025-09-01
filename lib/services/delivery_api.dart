import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../api_connection/api_connection.dart';
import '../models/delivery.dart';

class DeliveryApi {
  DeliveryApi._();
  static final DeliveryApi instance = DeliveryApi._();

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  OrderStatus _mapStatus(String s) {
    switch (s.toLowerCase()) {
      case 'assigned':
        return OrderStatus.assigned;
      case 'accepted':
        return OrderStatus.accepted;
      case 'rejected':
        return OrderStatus.rejected;
      case 'on_the_way':
      case 'ontheway':
      case 'on the way':
        return OrderStatus.onTheWay;
      case 'picked_up':
      case 'pickedup':
      case 'picked up':
        return OrderStatus.pickedUp;
      case 'delivered':
        return OrderStatus.delivered;
      default:
        return OrderStatus.assigned;
    }
  }

  Future<List<DeliveryOrder>> fetchOrders() async {
    final token = await _getToken();
    if (token == null || token.isEmpty) {
      throw Exception('missing_token');
    }
    final uri = Uri.parse(API.orders);
    final res = await http
        .get(
          uri,
          headers: {
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
          },
        )
        .timeout(const Duration(seconds: 20));

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('orders_http_${res.statusCode}: ${res.body}');
    }
    final jsonBody = json.decode(res.body);
    final List list = (jsonBody is Map && jsonBody['orders'] is List)
        ? jsonBody['orders']
        : (jsonBody is List ? jsonBody : []);

    return list.map<DeliveryOrder>((e) {
      final items = (e['items'] as List? ?? [])
          .map<DeliveryItem>(
            (i) => DeliveryItem(
              id: (i['id'] ?? '').toString(),
              name: (i['name'] ?? '').toString(),
              quantity: int.tryParse((i['quantity'] ?? '0').toString()) ?? 0,
              price: double.tryParse((i['price'] ?? '0').toString()) ?? 0.0,
            ),
          )
          .toList();
      return DeliveryOrder(
        id: (e['id'] ?? '').toString(),
        customerName: (e['customerName'] ?? '').toString(),
        customerPhone: (e['customerPhone'] ?? '').toString(),
        deliveryAddress: (e['deliveryAddress'] ?? '').toString(),
        deliveryInstructions: (e['deliveryInstructions'])?.toString(),
        items: items,
        totalAmount:
            double.tryParse((e['totalAmount'] ?? '0').toString()) ?? 0.0,
        estimatedTime: (e['estimatedTime'] ?? '').toString(),
        status: _mapStatus((e['status'] ?? 'assigned').toString()),
        paymentStatus: (e['paymentStatus'] ?? '').toString(),
        createdAt:
            DateTime.tryParse((e['createdAt'] ?? '').toString()) ??
            DateTime.now(),
        pickedUpAt: DateTime.tryParse((e['pickedUpAt'] ?? '').toString()),
        deliveredAt: DateTime.tryParse((e['deliveredAt'] ?? '').toString()),
      );
    }).toList();
  }

  Future<bool> updateOrderStatus(String orderId, OrderStatus status) async {
    final token = await _getToken();
    if (token == null || token.isEmpty) return false;
    final uri = Uri.parse(API.updateStatus);
    final statusStr = () {
      switch (status) {
        case OrderStatus.assigned:
          return 'assigned';
        case OrderStatus.accepted:
          return 'accepted';
        case OrderStatus.rejected:
          return 'rejected';
        case OrderStatus.onTheWay:
          return 'on_the_way';
        case OrderStatus.pickedUp:
          return 'picked_up';
        case OrderStatus.delivered:
          return 'delivered';
      }
    }();

    final res = await http
        .post(
          uri,
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: json.encode({'orderId': orderId, 'status': statusStr}),
        )
        .timeout(const Duration(seconds: 20));

    if (res.statusCode >= 200 && res.statusCode < 300) {
      return true;
    }
    return false;
  }

  Future<bool> acceptOrder(String orderId) =>
      updateOrderStatus(orderId, OrderStatus.accepted);
  Future<bool> rejectOrder(String orderId) =>
      updateOrderStatus(orderId, OrderStatus.rejected);
}
