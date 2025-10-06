enum OrderStatus { assigned, accepted, rejected, onTheWay, pickedUp, delivered }

class DeliveryItem {
  final String id;
  final String name;
  final int quantity;
  final double price;

  DeliveryItem({
    required this.id,
    required this.name,
    required this.quantity,
    required this.price,
  });
}

class DeliveryOrder {
  final String id;
  final String customerName;
  final String customerPhone;
  final String deliveryAddress;
  final String? deliveryInstructions;
  // Optional geocoordinates for the delivery destination
  final double? latitude;
  final double? longitude;
  // Order type: e.g., Delivery or Pickup (default Delivery if absent in API)
  final String orderType;
  final List<DeliveryItem> items;
  double totalAmount;
  final String estimatedTime;
  OrderStatus status;
  final String paymentStatus;
  final DateTime createdAt;
  DateTime? pickedUpAt;
  DateTime? deliveredAt;

  DeliveryOrder({
    required this.id,
    required this.customerName,
    required this.customerPhone,
    required this.deliveryAddress,
    this.deliveryInstructions,
    this.latitude,
    this.longitude,
    this.orderType = 'Delivery',
    required this.items,
    required this.totalAmount,
    required this.estimatedTime,
    required this.status,
    required this.paymentStatus,
    required this.createdAt,
    this.pickedUpAt,
    this.deliveredAt,
  });
}

class Driver {
  final String id;
  final String name;
  final String email;
  final String phone;
  final bool isActive;

  Driver({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.isActive,
  });
}
