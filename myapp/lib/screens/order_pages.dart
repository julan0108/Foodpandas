import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_core/firebase_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/food_order.dart';
import '../services/order_service.dart';

const _ink = Color(0xFF30251E);
const _muted = Color(0xFF81766E);
const _orange = Color(0xFFF47B20);

class OrderHistoryPage extends StatelessWidget {
  const OrderHistoryPage({
    super.key,
    required this.userId,
    required this.orderService,
  });
  final String userId;
  final OrderService? orderService;

  @override
  Widget build(BuildContext context) {
    final service = orderService;
    if (service == null) {
      return _message('Sign in to view your Firebase orders.');
    }
    return StreamBuilder<List<FoodOrder>>(
      stream: service.watchOrders(userId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _message(_ordersErrorMessage(snapshot.error));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final orders = snapshot.data!;
        return ListView.separated(
          key: const Key('orders-page'),
          padding: const EdgeInsets.fromLTRB(22, 32, 22, 50),
          itemCount: orders.length + (orders.isEmpty ? 2 : 1),
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            if (index == 0) {
              return const _PageHeading(
                title: 'My orders',
                subtitle: 'Recent orders and live status updates',
              );
            }
            if (orders.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Column(
                  children: [
                    Icon(Icons.receipt_long_outlined, size: 42, color: _muted),
                    SizedBox(height: 12),
                    Text(
                      'No orders yet',
                      style: TextStyle(
                        color: _ink,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Orders from verified restaurants will appear here after checkout. Sample menu preview checkouts are not saved to Firebase.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _muted),
                    ),
                  ],
                ),
              );
            }
            return _OrderCard(order: orders[index - 1]);
          },
        );
      },
    );
  }
}

class OrderDetailsDialog extends StatelessWidget {
  const OrderDetailsDialog({
    super.key,
    required this.order,
    required this.isDemoOrder,
    required this.orderService,
  });

  final FoodOrder order;
  final bool isDemoOrder;
  final OrderService? orderService;

  @override
  Widget build(BuildContext context) {
    final service = isDemoOrder ? null : orderService;
    if (service == null) return _dialog(context, order);
    return StreamBuilder<FoodOrder?>(
      stream: service.watchOrder(order.id, order.userId),
      builder: (context, snapshot) => _dialog(
        context,
        snapshot.data ?? order,
        databaseError: snapshot.hasError
            ? _ordersErrorMessage(snapshot.error)
            : null,
      ),
    );
  }

  Widget _dialog(
    BuildContext context,
    FoodOrder displayedOrder, {
    String? databaseError,
  }) {
    return AlertDialog(
      key: const Key('order-details-dialog'),
      title: const Text('Order details'),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.65,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                displayedOrder.orderNumber,
                key: const Key('order-details-number'),
                style: const TextStyle(
                  color: _orange,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (isDemoOrder) ...[
                const SizedBox(height: 10),
                Text(
                  order.paymentMethod == 'ewallet'
                      ? 'Sandbox payment only. This demo order is not sent to or fulfilled by a restaurant.'
                      : 'Sample checkout only. This order was not saved to Firebase or sent to a restaurant.',
                  key: Key('sample-order-dialog-notice'),
                  style: TextStyle(color: _muted),
                ),
              ],
              if (databaseError != null) ...[
                const SizedBox(height: 10),
                Text(
                  'Could not load live order details: $databaseError',
                  key: const Key('order-details-database-error'),
                  style: const TextStyle(color: Colors.red),
                ),
              ],
              const SizedBox(height: 14),
              Text('Customer: ${displayedOrder.customerName}'),
              if (displayedOrder.phone.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('Phone: ${displayedOrder.phone}'),
              ],
              const SizedBox(height: 6),
              Text('Deliver to: ${displayedOrder.deliveryAddress}'),
              const SizedBox(height: 12),
              const Divider(),
              ...displayedOrder.items.map(
                (item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: Text('${item.quantity} × ${item.name}')),
                      const SizedBox(width: 8),
                      Text(_peso(item.unitPrice * item.quantity)),
                    ],
                  ),
                ),
              ),
              const Divider(),
              _OrderTotalRow(
                label: 'Subtotal',
                amount: displayedOrder.subtotal,
              ),
              const SizedBox(height: 5),
              _OrderTotalRow(
                label: 'Delivery fee',
                amount: displayedOrder.deliveryFee,
              ),
              const SizedBox(height: 8),
              _OrderTotalRow(
                label: 'Total',
                amount: displayedOrder.total,
                bold: true,
              ),
              const SizedBox(height: 12),
              Text('Payment: ${_pretty(displayedOrder.paymentMethod)}'),
              Text('Payment status: ${_pretty(displayedOrder.paymentStatus)}'),
              Text('Status: ${_pretty(displayedOrder.status)}'),
              if (displayedOrder.invoiceUrl != null &&
                  (displayedOrder.paymentMethod == 'ewallet' ||
                      displayedOrder.paymentMethod == 'card' ||
                      displayedOrder.paymentMethod == 'xendit')) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () =>
                      openXenditInvoice(context, displayedOrder.invoiceUrl!),
                  icon: const Icon(Icons.account_balance_wallet_outlined),
                  label: const Text('Continue to payment'),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _OrderTotalRow extends StatelessWidget {
  const _OrderTotalRow({
    required this.label,
    required this.amount,
    this.bold = false,
  });

  final String label;
  final double amount;
  final bool bold;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label, style: TextStyle(fontWeight: bold ? FontWeight.w800 : null)),
      Text(
        _peso(amount),
        style: TextStyle(fontWeight: bold ? FontWeight.w900 : null),
      ),
    ],
  );
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order});
  final FoodOrder order;

  @override
  Widget build(BuildContext context) => Card(
    color: Colors.white,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: const BorderSide(color: Color(0xFFF0E8DF)),
    ),
    child: ExpansionTile(
      key: ValueKey('order-${order.id}'),
      title: Text(
        order.orderNumber,
        style: const TextStyle(color: _ink, fontWeight: FontWeight.w800),
      ),
      subtitle: Text('${_date(order.createdAt)}  •  ${_pretty(order.status)}'),
      trailing: Text(
        _peso(order.total),
        style: const TextStyle(color: _orange, fontWeight: FontWeight.w900),
      ),
      childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Payment: ${_pretty(order.paymentStatus)} (${_pretty(order.paymentMethod)})',
          ),
        ),
        if ((order.paymentMethod == 'ewallet' ||
                order.paymentMethod == 'card' ||
                order.paymentMethod == 'xendit') &&
            order.paymentStatus == 'pending' &&
            order.invoiceUrl != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => openXenditInvoice(context, order.invoiceUrl!),
              icon: const Icon(Icons.account_balance_wallet_outlined),
              label: const Text('Continue to Xendit'),
            ),
          ),
        ],
        const SizedBox(height: 8),
        ...order.items.map(
          (item) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Expanded(child: Text('${item.quantity} × ${item.name}')),
                Text(_peso(item.unitPrice * item.quantity)),
              ],
            ),
          ),
        ),
        const Divider(height: 20),
        Align(
          alignment: Alignment.centerLeft,
          child: Text('Deliver to: ${order.deliveryAddress}'),
        ),
        const SizedBox(height: 5),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Total: ${_peso(order.total)}',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    ),
  );
}

class NotificationCenterPage extends StatelessWidget {
  const NotificationCenterPage({
    super.key,
    required this.userId,
    required this.orderService,
  });
  final String userId;
  final OrderService? orderService;

  @override
  Widget build(BuildContext context) {
    final service = orderService;
    if (service == null) {
      return _message('Sign in to view your in-app order notifications.');
    }
    return StreamBuilder<List<OrderNotification>>(
      stream: service.watchNotifications(userId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _message(
            'Could not load notifications. Check your Firebase connection.',
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final notifications = snapshot.data!;
        return ListView.separated(
          key: const Key('notifications-page'),
          padding: const EdgeInsets.fromLTRB(22, 32, 22, 50),
          itemCount: notifications.length + 1,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            if (index == 0) {
              return const _PageHeading(
                title: 'Notifications',
                subtitle: 'Order confirmations and status updates',
              );
            }
            final notification = notifications[index - 1];
            return Card(
              color: notification.read ? Colors.white : const Color(0xFFFFF1DF),
              child: ListTile(
                leading: Icon(
                  notification.type == 'payment'
                      ? Icons.payments_outlined
                      : Icons.receipt_long_outlined,
                  color: _orange,
                ),
                title: Text(
                  notification.title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  '${notification.body}\n${_date(notification.createdAt)}',
                ),
                isThreeLine: true,
                onTap: notification.read
                    ? null
                    : () =>
                          service.markNotificationRead(userId, notification.id),
              ),
            );
          },
        );
      },
    );
  }
}

class _PageHeading extends StatelessWidget {
  const _PageHeading({required this.title, required this.subtitle});
  final String title;
  final String subtitle;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w900,
            color: _ink,
          ),
        ),
        Text(subtitle, style: const TextStyle(color: _muted)),
      ],
    ),
  );
}

Widget _message(String text) => Center(
  child: Padding(
    padding: const EdgeInsets.all(28),
    child: Text(text, textAlign: TextAlign.center),
  ),
);

String _ordersErrorMessage(Object? error) {
  if (error is FirebaseException) {
    return 'Could not load your Firebase data (${error.code}): ${error.message ?? 'database request failed'}.';
  }
  return 'Could not load your Firebase data. Check your connection and Firestore setup.';
}

Future<void> openXenditInvoice(BuildContext context, String invoiceUrl) async {
  final uri = Uri.tryParse(invoiceUrl);
  if (uri == null ||
      uri.scheme != 'https' ||
      (uri.host != 'xendit.co' && !uri.host.endsWith('.xendit.co'))) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('The Xendit payment link is invalid.')),
    );
    return;
  }
  try {
    final opened = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
      webOnlyWindowName: kIsWeb ? '_self' : null,
    );
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open the Xendit payment page.'),
        ),
      );
    }
  } on PlatformException {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open the Xendit payment page.'),
        ),
      );
    }
  }
}

String _peso(double amount) => '₱${amount.toStringAsFixed(2)}';
String _date(DateTime? date) => date == null
    ? 'Date pending'
    : '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
String _pretty(String value) {
  if (value == 'xendit') return 'Xendit online';
  return value
      .replaceAll('_', ' ')
      .split(' ')
      .map(
        (word) => word.isEmpty
            ? word
            : '${word[0].toUpperCase()}${word.substring(1)}',
      )
      .join(' ');
}
