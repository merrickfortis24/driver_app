import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../api_connection/api_connection.dart';
import '../models/delivery.dart';
import 'delivery_exceptions.dart';
import 'package:logging/logging.dart';
import 'package:http_parser/http_parser.dart';
import 'package:flutter/foundation.dart';

class DeliveryApi {
  DeliveryApi._();
  static final DeliveryApi instance = DeliveryApi._();
  static final Logger _logger = Logger('DeliveryApi');

  DateTime? _safeDate(dynamic v) {
    if (v == null) return null;
    try {
      String s = v.toString().trim();
      if (s.isEmpty || s == 'null') return null;
      // Common MySQL zero dates or placeholders
      if (s == '0000-00-00' || s == '0000-00-00 00:00:00') return null;
      // Normalize 'YYYY-MM-DD HH:MM:SS' -> 'YYYY-MM-DDTHH:MM:SS'
      if (s.length >= 19 && s[10] == ' ' && !s.contains('T')) {
        s = s.replaceFirst(' ', 'T');
      }
      // If timezone missing, let tryParse handle (will assume local)
      return DateTime.tryParse(s);
    } catch (_) {
      return null;
    }
  }

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
      throw UnauthorizedException('missing_token');
    }

    final uri = Uri.parse(API.orders);
    final res = await http
        .get(
          uri,
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
        )
        .timeout(const Duration(seconds: 20));

    _logger.info('orders response status: ${res.statusCode}');
    _logger.fine('orders response headers: ${res.headers}');
    _logger.fine(
      'orders response body (truncated 2000 chars): ${res.body.length > 2000 ? "${res.body.substring(0, 2000)}..." : res.body}',
    );

    // If unauthorized, clear token and throw a specific exception so UI can react.
    if (res.statusCode == 401) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('token');
      } catch (_) {}
      throw UnauthorizedException('Unauthorized: ${res.body}');
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException(
        'orders_http_${res.statusCode}: ${res.body}',
        statusCode: res.statusCode,
      );
    }

    // Try to decode JSON but provide a helpful error if the body contains HTML or invalid JSON.
    dynamic jsonBody;
    try {
      jsonBody = json.decode(res.body);
    } catch (e) {
      final bodyLower = res.body.toLowerCase();
      final isHtml =
          res.body.trimLeft().startsWith('<') ||
          bodyLower.contains('<html') ||
          bodyLower.contains('<!doctype');
      final looksLikeLogin =
          bodyLower.contains('login') ||
          bodyLower.contains('sign in') ||
          bodyLower.contains('<form');

      if (isHtml && looksLikeLogin) {
        // Clear stored token to force re-auth in the app
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove('token');
        } catch (_) {}
        throw UnauthorizedException(
          'Server returned HTML login page; cleared token.',
        );
      }

      throw ApiException(
        'Failed to parse JSON from orders endpoint. HTTP ${res.statusCode}. Body (truncated 2000 chars): ${res.body.length > 2000 ? "${res.body.substring(0, 2000)}..." : res.body}',
        statusCode: res.statusCode,
      );
    }

    // Server may return a top-level list, or a map with key 'data' (old style),
    // or a map with key 'orders' (current server implementation).
    final list = jsonBody is List
        ? jsonBody
        : (jsonBody is Map
              ? (jsonBody['data'] is List
                    ? jsonBody['data']
                    : (jsonBody['orders'] is List ? jsonBody['orders'] : []))
              : []);

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
      // Accept multiple possible keys the backend might use for coordinates
      double? lat = double.tryParse(
        (e['lat'] ??
                e['latitude'] ??
                e['customer_lat'] ??
                e['customerLat'] ??
                e['dest_lat'] ??
                e['destination_lat'] ??
                '')
            .toString(),
      );
      double? lng = double.tryParse(
        (e['lng'] ??
                e['lon'] ??
                e['longitude'] ??
                e['customer_lng'] ??
                e['customerLng'] ??
                e['dest_lng'] ??
                e['destination_lng'] ??
                '')
            .toString(),
      );
      if (lat != null && lat == 0) lat = null; // treat 0 as missing
      if (lng != null && lng == 0) lng = null;
      // Capture order type under multiple naming conventions
      final orderType =
          (e['order_type'] ??
                  e['orderType'] ??
                  e['type'] ??
                  e['Order_Type'] ??
                  e['OrderType'] ??
                  'Delivery')
              .toString();
      return DeliveryOrder(
        id: (e['id'] ?? '').toString(),
        customerName: (e['customerName'] ?? '').toString(),
        customerPhone: (e['customerPhone'] ?? '').toString(),
        deliveryAddress: (e['deliveryAddress'] ?? '').toString(),
        deliveryInstructions: (e['deliveryInstructions'])?.toString(),
        latitude: lat,
        longitude: lng,
        orderType: orderType,
        items: items,
        totalAmount:
            double.tryParse((e['totalAmount'] ?? '0').toString()) ?? 0.0,
        estimatedTime: (e['estimatedTime'] ?? '').toString(),
        status: _mapStatus((e['status'] ?? 'assigned').toString()),
        paymentStatus: (e['paymentStatus'] ?? '').toString(),
        createdAt: _safeDate(e['createdAt']) ?? DateTime.now(),
        pickedUpAt: _safeDate(e['pickedUpAt']),
        deliveredAt: _safeDate(e['deliveredAt']),
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
      _logger.info(
        'updateStatus ok order=$orderId status=$statusStr body=${res.body}',
      );
      return true;
    }
    _logger.warning(
      'updateStatus failed order=$orderId status=$statusStr code=${res.statusCode} body=${res.body}',
    );
    return false;
  }

  Future<bool> acceptOrder(String orderId) =>
      updateOrderStatus(orderId, OrderStatus.accepted);
  Future<bool> rejectOrder(String orderId) =>
      updateOrderStatus(orderId, OrderStatus.rejected);

  Future<List<String>> uploadProofPhotos(
    String orderId,
    List<Uint8List> files, {
    List<String>? fileNames,
  }) async {
    final token = await _getToken();
    if (token == null || token.isEmpty) {
      throw UnauthorizedException('missing_token');
    }
    final uri = Uri.parse(API.uploadProofs);
    final req = http.MultipartRequest('POST', uri);
    req.headers.addAll({'Authorization': 'Bearer $token'});
    req.fields['orderId'] = orderId;
    for (var i = 0; i < files.length; i++) {
      final name = (fileNames != null && i < fileNames.length)
          ? fileNames[i]
          : 'proof_$i.jpg';
      req.files.add(
        http.MultipartFile.fromBytes(
          'photos[]',
          files[i],
          filename: name,
          contentType: MediaType('image', 'jpeg'),
        ),
      );
    }
    final res = await http.Response.fromStream(
      await req.send(),
    ).timeout(const Duration(seconds: 30));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException(
        'upload_proofs_http_${res.statusCode}: ${res.body}',
        statusCode: res.statusCode,
      );
    }
    final body = json.decode(res.body);
    final List<dynamic> paths = body['paths'] ?? [];
    return paths.map((e) => e.toString()).toList();
  }

  Future<String> uploadSignaturePng(String orderId, Uint8List pngBytes) async {
    final token = await _getToken();
    if (token == null || token.isEmpty) {
      throw UnauthorizedException('missing_token');
    }
    final uri = Uri.parse(API.uploadSignature);
    final req = http.MultipartRequest('POST', uri);
    req.headers.addAll({'Authorization': 'Bearer $token'});
    req.fields['orderId'] = orderId;
    req.files.add(
      http.MultipartFile.fromBytes(
        'signature',
        pngBytes,
        filename: 'signature.png',
        contentType: MediaType('image', 'png'),
      ),
    );
    final res = await http.Response.fromStream(
      await req.send(),
    ).timeout(const Duration(seconds: 30));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException(
        'upload_signature_http_${res.statusCode}: ${res.body}',
        statusCode: res.statusCode,
      );
    }
    final body = json.decode(res.body);
    return (body['path'] ?? '').toString();
  }

  Future<Driver> fetchProfile() async {
    final token = await _getToken();
    if (token == null || token.isEmpty) {
      throw UnauthorizedException('missing_token');
    }
    final uri = Uri.parse(API.profile);
    final res = await http
        .get(
          uri,
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
        )
        .timeout(const Duration(seconds: 20));

    if (res.statusCode == 401) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('token');
      } catch (_) {}
      throw UnauthorizedException('Unauthorized');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException(
        'profile_http_${res.statusCode}: ${res.body}',
        statusCode: res.statusCode,
      );
    }
    dynamic jsonBody;
    try {
      jsonBody = json.decode(res.body);
    } catch (e) {
      throw ApiException('Invalid JSON from profile endpoint');
    }
    final d = jsonBody['driver'] ?? {};
    DateTime? parseDate(dynamic v) {
      return _safeDate(v);
    }

    final statusStr = (d['status'] ?? '').toString().toLowerCase();
    final isActive = statusStr.isEmpty || statusStr == 'active';
    return Driver(
      id: (d['id'] ?? '').toString(),
      name: (d['name'] ?? '').toString(),
      email: (d['email'] ?? d['gmail'] ?? '').toString(),
      isActive: isActive,
      createdAt: parseDate(d['createdAt']),
      lastLogin: parseDate(d['lastLogin']),
      tokenExpires: parseDate(d['tokenExpires']),
    );
  }

  // Cash summary model
  Future<Map<String, dynamic>> fetchCashSummary() async {
    final token = await _getToken();
    if (token == null || token.isEmpty) {
      throw UnauthorizedException('missing_token');
    }
    final uri = Uri.parse(API.cashSummary);
    final res = await http.get(uri, headers: {
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
    }).timeout(const Duration(seconds: 20));
    if (res.statusCode == 401) throw UnauthorizedException('Unauthorized');
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException('cash_summary_http_${res.statusCode}: ${res.body}',
          statusCode: res.statusCode);
    }
    return json.decode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> submitRemittance({
    required double amount,
    String? note,
    Uint8List? proofJpeg,
  }) async {
    final token = await _getToken();
    if (token == null || token.isEmpty) {
      throw UnauthorizedException('missing_token');
    }
    final uri = Uri.parse(API.remit);
    final req = http.MultipartRequest('POST', uri);
    req.headers['Authorization'] = 'Bearer $token';
    req.fields['amount'] = amount.toStringAsFixed(2);
    if (note != null && note.isNotEmpty) req.fields['note'] = note;
    if (proofJpeg != null && proofJpeg.isNotEmpty) {
      req.files.add(http.MultipartFile.fromBytes(
        'proof',
        proofJpeg,
        filename: 'proof.jpg',
        contentType: MediaType('image', 'jpeg'),
      ));
    }
    final res = await http.Response.fromStream(await req.send())
        .timeout(const Duration(seconds: 30));
    if (res.statusCode == 401) throw UnauthorizedException('Unauthorized');
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException('remit_http_${res.statusCode}: ${res.body}',
          statusCode: res.statusCode);
    }
    return json.decode(res.body) as Map<String, dynamic>;
  }
}
