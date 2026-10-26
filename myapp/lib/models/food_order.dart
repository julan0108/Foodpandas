import 'package:cloud_firestore/cloud_firestore.dart';

class FoodOrderItem {
  const FoodOrderItem({
    required this.id,
    required this.restaurantId,
    required this.name,
    required this.restaurantName,
    required this.quantity,
    required this.unitPrice,
    required this.imageUrl,
  });

  final String id;
  final String restaurantId;
  final String name;
  final String restaurantName;
  final int quantity;
  final double unitPrice;
  final String imageUrl;

  Map<String, dynamic> toMap() => {
    'id': id,
    'restaurantId': restaurantId,
    'name': name,
    'restaurantName': restaurantName,
    'quantity': quantity,
    'unitPrice': unitPrice,
    'imageUrl': imageUrl,
  };

  factory FoodOrderItem.fromMap(Map<String, dynamic> data) => FoodOrderItem(
    id: data['id'] as String? ?? '',
    restaurantId: data['restaurantId'] as String? ?? '',
    name: data['name'] as String? ?? 'Food item',
    restaurantName: data['restaurantName'] as String? ?? '',
    quantity: (data['quantity'] as num?)?.toInt() ?? 0,
    unitPrice: (data['unitPrice'] as num?)?.toDouble() ?? 0,
    imageUrl: data['imageUrl'] as String? ?? '',
  );
}

class FoodOrder {
  const FoodOrder({
    required this.id,
    required this.orderNumber,
    required this.userId,
    required this.customerName,
    this.phone = '',
    required this.items,
    required this.subtotal,
    required this.deliveryFee,
    required this.total,
    required this.deliveryAddress,
    required this.status,
    required this.paymentStatus,
    required this.paymentMethod,
    required this.createdAt,
    this.invoiceUrl,
  });

  final String id;
  final String orderNumber;
  final String userId;
  final String customerName;
  final String phone;
  final List<FoodOrderItem> items;
  final double subtotal;
  final double deliveryFee;
  final double total;
  final String deliveryAddress;
  final String status;
  final String paymentStatus;
  final String paymentMethod;
  final DateTime? createdAt;
  final String? invoiceUrl;

  factory FoodOrder.fromMap(Map<String, dynamic> data) {
    final rawItems = data['items'];
    return FoodOrder(
      id: data['id'] as String? ?? '',
      orderNumber:
          data['orderNumber'] as String? ??
          data['order_number'] as String? ??
          data['id'] as String? ??
          '',
      userId: data['userId'] as String? ?? data['user_id'] as String? ?? '',
      customerName:
          data['customerName'] as String? ??
          data['customer_name'] as String? ??
          '',
      phone: data['phone'] as String? ?? '',
      items: rawItems is List
          ? rawItems
                .whereType<Map>()
                .map(
                  (item) =>
                      FoodOrderItem.fromMap(Map<String, dynamic>.from(item)),
                )
                .toList(growable: false)
          : const [],
      subtotal: (data['subtotal'] as num?)?.toDouble() ?? 0,
      deliveryFee:
          (data['deliveryFee'] as num? ?? data['delivery_fee'] as num?)
              ?.toDouble() ??
          0,
      total: (data['total'] as num?)?.toDouble() ?? 0,
      deliveryAddress:
          data['deliveryAddress'] as String? ??
          data['delivery_address'] as String? ??
          '',
      status: data['status'] as String? ?? 'placed',
      paymentStatus:
          data['paymentStatus'] as String? ??
          data['payment_status'] as String? ??
          'pending',
      paymentMethod:
          data['paymentMethod'] as String? ??
          data['payment_method'] as String? ??
          'cash_on_delivery',
      createdAt: _date(data['createdAt'] ?? data['created_at']),
      invoiceUrl:
          data['invoiceUrl'] as String? ?? data['invoice_url'] as String?,
    );
  }

  static DateTime? _date(Object? value) => switch (value) {
    Timestamp timestamp => timestamp.toDate(),
    DateTime dateTime => dateTime,
    String date => DateTime.tryParse(date)?.toLocal(),
    _ => null,
  };
}

class OrderNotification {
  const OrderNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.read,
    required this.createdAt,
    this.orderId,
  });

  final String id;
  final String title;
  final String body;
  final String type;
  final bool read;
  final DateTime? createdAt;
  final String? orderId;
}
