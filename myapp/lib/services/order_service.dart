import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/food_order.dart';

abstract interface class OrderService {
  Future<CreatedOrder> createOrder({
    required String userId,
    required String customerName,
    required String phone,
    required String deliveryAddress,
    required List<FoodOrderItem> items,
    String paymentMethod = 'cash_on_delivery',
    bool demoOrder = false,
  });

  Stream<List<FoodOrder>> watchOrders(String userId);
  Stream<FoodOrder?> watchOrder(String orderId, String userId);
  Stream<List<OrderNotification>> watchNotifications(String userId);
  Future<void> markNotificationRead(String userId, String notificationId);
  Future<void> saveDeviceToken(String userId, String token, String platform);
  Future<void> removeDeviceToken(String userId, String token);
}

class CreatedOrder {
  const CreatedOrder({
    required this.id,
    required this.orderNumber,
    this.invoiceUrl,
  });
  final String id;
  final String orderNumber;
  final String? invoiceUrl;
}

class FirebaseOrderService implements OrderService {
  FirebaseOrderService({
    FirebaseFunctions? functions,
    FirebaseFirestore? firestore,
  }) : _configuredFunctions = functions,
       _configuredFirestore = firestore;

  final FirebaseFunctions? _configuredFunctions;
  final FirebaseFirestore? _configuredFirestore;
  FirebaseFunctions get _functions =>
      _configuredFunctions ?? FirebaseFunctions.instance;
  FirebaseFirestore get _firestore =>
      _configuredFirestore ?? FirebaseFirestore.instance;

  @override
  Future<CreatedOrder> createOrder({
    required String userId,
    required String customerName,
    required String phone,
    required String deliveryAddress,
    required List<FoodOrderItem> items,
    String paymentMethod = 'cash_on_delivery',
    bool demoOrder = false,
  }) async {
    try {
      final result = await _functions.httpsCallable('createOrder').call({
        'customerName': customerName,
        'phone': phone,
        'deliveryAddress': deliveryAddress,
        'paymentMethod': paymentMethod,
        'demoOrder': demoOrder,
        'items': items
            .map(
              (item) => {
                'restaurantId': item.restaurantId,
                'id': item.id,
                'quantity': item.quantity,
              },
            )
            .toList(growable: false),
      });
      final data = Map<String, dynamic>.from(result.data as Map);
      final id = data['orderId'];
      final orderNumber = data['orderNumber'];
      final invoiceUrl = data['invoiceUrl'];
      if (id is! String || orderNumber is! String) {
        throw const OrderFailure(
          'The order service returned an invalid confirmation.',
        );
      }
      if (invoiceUrl != null && invoiceUrl is! String) {
        throw const OrderFailure(
          'The payment service returned an invalid payment link.',
        );
      }
      if (paymentMethod != 'cash_on_delivery' && invoiceUrl is! String) {
        throw const OrderFailure(
          'The payment service did not return an online payment link.',
        );
      }
      return CreatedOrder(
        id: id,
        orderNumber: orderNumber,
        invoiceUrl: invoiceUrl is String ? invoiceUrl : null,
      );
    } on FirebaseFunctionsException catch (error) {
      final message = error.code == 'internal'
          ? _functionsMessage(error.code)
          : error.message ?? _functionsMessage(error.code);
      final details = error.details;
      final orderNumber = details is Map ? details['orderNumber'] : null;
      if (orderNumber is String && orderNumber.isNotEmpty) {
        throw OrderFailure(
          '$message Order $orderNumber is saved with a failed payment status in My orders.',
        );
      }
      throw OrderFailure(message);
    }
  }

  String _functionsMessage(String code) => switch (code) {
    'unauthenticated' => 'Please sign in again before placing an order.',
    'permission-denied' => 'Verify your email before placing an order.',
    'failed-precondition' => 'The restaurant cannot deliver to this address or the menu is no longer available.',
    'invalid-argument' =>
      'Check the delivery details and cart, then try again.',
    'unavailable' => 'Could not reach the order or payment service. Try again.',
    'internal' =>
      'The payment service failed unexpectedly. Check that Firebase Functions are deployed and XENDIT_SECRET_KEY is configured.',
    _ => 'Could not place the order ($code).',
  };

  @override
  Stream<List<FoodOrder>> watchOrders(String userId) => _firestore
      .collection('orders')
      .where('userId', isEqualTo: userId)
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .map(
              (document) =>
                  FoodOrder.fromMap({...document.data(), 'id': document.id}),
            )
            .toList(growable: false),
      );

  @override
  Stream<FoodOrder?> watchOrder(String orderId, String userId) =>
      _firestore.collection('orders').doc(orderId).snapshots().map((document) {
        final data = document.data();
        if (data == null || data['userId'] != userId) return null;
        return FoodOrder.fromMap({...data, 'id': document.id});
      });

  @override
  Stream<List<OrderNotification>> watchNotifications(String userId) =>
      _firestore
          .collection('users')
          .doc(userId)
          .collection('notifications')
          .orderBy('createdAt', descending: true)
          .limit(50)
          .snapshots()
          .map(
            (snapshot) => snapshot.docs
                .map((document) {
                  final row = document.data();
                  return OrderNotification(
                    id: document.id,
                    title: row['title'] as String? ?? 'Order update',
                    body: row['body'] as String? ?? '',
                    type: row['type'] as String? ?? 'order',
                    read: row['read'] as bool? ?? false,
                    createdAt: _date(row['createdAt']),
                    orderId: row['orderId'] as String?,
                  );
                })
                .toList(growable: false),
          );

  @override
  Future<void> markNotificationRead(
    String userId,
    String notificationId,
  ) async {
    try {
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('notifications')
          .doc(notificationId)
          .update({'read': true});
    } on FirebaseException catch (error) {
      throw OrderFailure(_firebaseMessage(error));
    }
  }

  @override
  Future<void> saveDeviceToken(
    String userId,
    String token,
    String platform,
  ) async {
    try {
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('devices')
          .doc(token)
          .set({
            'token': token,
            'platform': platform,
            'updatedAt': FieldValue.serverTimestamp(),
          });
    } on FirebaseException catch (error) {
      throw OrderFailure(_firebaseMessage(error));
    }
  }

  @override
  Future<void> removeDeviceToken(String userId, String token) async {
    try {
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('devices')
          .doc(token)
          .delete();
    } on FirebaseException catch (error) {
      throw OrderFailure(_firebaseMessage(error));
    }
  }

  DateTime? _date(Object? value) => switch (value) {
    Timestamp timestamp => timestamp.toDate(),
    DateTime dateTime => dateTime,
    String date => DateTime.tryParse(date)?.toLocal(),
    _ => null,
  };

  String _firebaseMessage(FirebaseException error) =>
      'Firebase request failed (${error.code}): ${error.message ?? 'database request failed'}.';
}

class OrderFailure implements Exception {
  const OrderFailure(this.message);
  final String message;
  @override
  String toString() => message;
}
