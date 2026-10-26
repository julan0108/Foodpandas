import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/main.dart';
import 'package:myapp/models/food_order.dart';
import 'package:myapp/screens/order_pages.dart';
import 'package:myapp/services/auth_service.dart';
import 'package:myapp/services/customer_profile_service.dart';
import 'package:myapp/services/order_service.dart';
import 'package:myapp/services/restaurant_service.dart';

class _TestOrderService implements OrderService {
  final List<FoodOrder> orders = [];
  final List<OrderNotification> notifications = [];
  final List<bool> demoOrders = [];

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
    demoOrders.add(demoOrder);
    orders.add(
      FoodOrder(
        id: 'test-order',
        orderNumber: 'FP-TEST',
        userId: userId,
        customerName: customerName,
        phone: phone,
        items: items,
        subtotal: items.fold<double>(0, (v, i) => v + i.unitPrice * i.quantity),
        deliveryFee: 35,
        total: items.fold<double>(35, (v, i) => v + i.unitPrice * i.quantity),
        deliveryAddress: deliveryAddress,
        status: paymentMethod == 'cash_on_delivery'
            ? 'placed'
            : 'pending_payment',
        paymentStatus: 'pending',
        paymentMethod: paymentMethod,
        createdAt: DateTime.now(),
        invoiceUrl: paymentMethod != 'cash_on_delivery'
            ? 'https://checkout.xendit.co/web/test'
            : null,
      ),
    );
    return CreatedOrder(
      id: 'test-order',
      orderNumber: 'FP-TEST',
      invoiceUrl: paymentMethod != 'cash_on_delivery'
          ? 'https://checkout.xendit.co/web/test'
          : null,
    );
  }

  @override
  Stream<List<FoodOrder>> watchOrders(String userId) =>
      Stream.value(orders.where((order) => order.userId == userId).toList());

  @override
  Stream<FoodOrder?> watchOrder(String orderId, String userId) {
    final matching = orders.where(
      (order) => order.id == orderId && order.userId == userId,
    );
    return Stream.value(matching.isEmpty ? null : matching.first);
  }

  @override
  Stream<List<OrderNotification>> watchNotifications(String userId) =>
      Stream.value(notifications);

  @override
  Future<void> markNotificationRead(
    String userId,
    String notificationId,
  ) async {
    final index = notifications.indexWhere((item) => item.id == notificationId);
    if (index < 0) return;
    final old = notifications[index];
    notifications[index] = OrderNotification(
      id: old.id,
      title: old.title,
      body: old.body,
      type: old.type,
      read: true,
      createdAt: old.createdAt,
      orderId: old.orderId,
    );
  }

  @override
  Future<void> saveDeviceToken(
    String userId,
    String token,
    String platform,
  ) async {}

  @override
  Future<void> removeDeviceToken(String userId, String token) async {}
}

class _TestRestaurantService implements RestaurantService {
  _TestRestaurantService(this.restaurants);
  final List<VerifiedRestaurant> restaurants;

  @override
  Stream<List<VerifiedRestaurant>> watchVerifiedRestaurants() =>
      Stream.value(restaurants);
}

class _TestCustomerProfileService implements CustomerProfileService {
  final profiles = <String, CustomerProfile>{};

  @override
  Future<CustomerProfile?> getProfile(String uid) async => profiles[uid];

  @override
  Future<void> saveProfile(String uid, CustomerProfile profile) async {
    profiles[uid] = profile;
  }
}

class _TestAuthService implements AuthService {
  _TestAuthService({bool signedIn = true, bool emailVerified = true})
    : _user = signedIn
          ? AuthUser(
              uid: 'test-user',
              email: 'test@example.com',
              emailVerified: emailVerified,
              displayName: 'Test Customer',
            )
          : null;

  AuthUser? _user;

  @override
  AuthUser? get currentUser => _user;

  @override
  Stream<AuthUser?> get authStateChanges => Stream.value(_user);

  @override
  Future<AuthUser> register(
    String email,
    String password,
    String displayName,
  ) async => _user!;

  @override
  Future<AuthUser> signIn(String email, String password) async => _user!;

  @override
  Future<AuthUser> updateDisplayName(String displayName) async => _user!;

  @override
  Future<void> signOut() async {
    _user = null;
  }

  @override
  Future<void> sendVerificationEmail() async {}

  @override
  Future<AuthUser> reloadCurrentUser() async => _user!;

  @override
  Future<void> sendPasswordResetEmail(String email) async {}
}

void main() {
  testWidgets('card payment is available and submitted as a card choice', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    String? selectedPaymentMethod;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CheckoutPage(
            items: const [
              MenuItem(
                id: 'meal',
                name: 'Test meal',
                description: 'Test meal',
                price: 100,
                image: '',
              ),
            ],
            quantities: const {'meal': 1},
            subtotal: 100,
            deliveryFee: 20,
            onBack: () {},
            onBrowseRestaurants: () {},
            customerProfileService: _TestCustomerProfileService(),
            user: const AuthUser(
              uid: 'test-user',
              email: 'test@example.com',
              emailVerified: true,
              displayName: 'Test Customer',
            ),
            onPlaceOrder: (_, _, _, paymentMethod) async {
              selectedPaymentMethod = paymentMethod;
            },
          ),
        ),
      ),
    );
    await tester.enterText(find.byKey(const Key('customer-name')), 'Test User');
    await tester.enterText(
      find.byKey(const Key('customer-phone')),
      '09171234567',
    );
    await tester.enterText(
      find.byKey(const Key('delivery-address')),
      '12 Sampaguita Street, Makati',
    );
    await tester.tap(find.byKey(const Key('payment-card')));
    await tester.tap(find.byKey(const Key('place-order')));
    await tester.pumpAndSettle();

    expect(selectedPaymentMethod, 'card');
    await tester.tap(find.byKey(const Key('payment-xendit-all')));
    await tester.tap(find.byKey(const Key('place-order')));
    await tester.pumpAndSettle();

    expect(selectedPaymentMethod, 'xendit');
  });

  testWidgets('Food-Pandas opens with the neighborhood food landing page', (
    tester,
  ) async {
    await tester.pumpWidget(FoodPandasApp(authService: _TestAuthService()));

    expect(find.text('Sarap na malapit.\nOne tap na lang.'), findsOneWidget);
    expect(find.byKey(const Key('browse-stalls')), findsOneWidget);
  });

  testWidgets('customer can add food, check out, and see order status', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final profileService = _TestCustomerProfileService();
    final orderService = _TestOrderService();
    profileService.profiles['test-user'] = const CustomerProfile(
      email: 'test@example.com',
      displayName: 'Saved Customer',
      phone: '09170000000',
      deliveryAddress: 'Saved address',
    );
    String? openedPaymentUrl;
    await tester.pumpWidget(
      FoodPandasApp(
        authService: _TestAuthService(),
        customerProfileService: profileService,
        orderService: orderService,
        paymentLinkLauncher: (_, url) async {
          openedPaymentUrl = url;
        },
      ),
    );
    await tester.tap(find.byKey(const Key('browse-stalls')));
    await tester.pumpAndSettle();

    final vendorCard = find.byKey(const Key('vendor-card-tita-luz'));
    await tester.ensureVisible(vendorCard);
    await tester.tap(vendorCard);
    await tester.pumpAndSettle();

    final addAdobo = find.byKey(const Key('add-adobo'));
    await tester.ensureVisible(addAdobo);
    await tester.tap(addAdobo);
    await tester.pump();

    final viewCart = find.byKey(const Key('menu-view-cart'));
    await tester.ensureVisible(viewCart);
    await tester.tap(viewCart);
    await tester.pumpAndSettle();
    expect(find.textContaining('Chicken Adobo'), findsOneWidget);

    await tester.tap(find.byKey(const Key('go-checkout')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('payment-ewallet')), findsOneWidget);
    expect(find.byKey(const Key('payment-card')), findsOneWidget);
    expect(find.byKey(const Key('payment-xendit-all')), findsOneWidget);
    expect(find.byKey(const Key('sample-order-notice')), findsNothing);
    expect(find.byKey(const Key('sample-payment-notice')), findsOneWidget);
    expect(
      find.byKey(const Key('browse-verified-restaurants')),
      findsNothing,
    );
    expect(
      tester
          .widget<RadioListTile<String>>(
            find.byKey(const Key('payment-ewallet')),
          )
          .enabled,
      isTrue,
    );
    expect(
      tester.widget<RadioListTile<String>>(
        find.byKey(const Key('payment-card')),
      ).enabled,
      isFalse,
    );
    expect(
      tester
          .widget<TextFormField>(
            find.descendant(
              of: find.byKey(const Key('customer-name')),
              matching: find.byType(TextFormField),
            ),
          )
          .controller
          ?.text,
      'Saved Customer',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('customer-name')),
        matching: find.byType(TextFormField),
      ),
      'Maya Santos',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('customer-phone')),
        matching: find.byType(TextFormField),
      ),
      '09171234567',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('delivery-address')),
        matching: find.byType(TextFormField),
      ),
      '12 Sampaguita Street, Makati',
    );
    await tester.tap(find.byKey(const Key('payment-ewallet')));
    await tester.tap(find.byKey(const Key('place-order')));
    await tester.pumpAndSettle();

    expect(orderService.orders, hasLength(1));
    expect(orderService.demoOrders, [true]);
    expect(openedPaymentUrl, 'https://checkout.xendit.co/web/test');
    expect(find.byKey(const Key('order-details-dialog')), findsOneWidget);
    expect(find.textContaining('Chicken Adobo'), findsOneWidget);
    expect(find.byKey(const Key('sample-order-dialog-notice')), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(find.text('Thanks, salamat!'), findsOneWidget);
    expect(find.textContaining('Maya Santos'), findsOneWidget);
    final savedProfile = profileService.profiles['test-user'];
    expect(savedProfile?.email, 'test@example.com');
    expect(savedProfile?.displayName, 'Maya Santos');
    expect(savedProfile?.phone, '09171234567');
    expect(savedProfile?.deliveryAddress, '12 Sampaguita Street, Makati');
    expect(
      find.textContaining('No restaurant will fulfill this demo menu order'),
      findsOneWidget,
    );
  });

  testWidgets('verified restaurant checkout saves the order and opens Xendit', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final profileService = _TestCustomerProfileService();
    final orderService = _TestOrderService();
    String? openedPaymentUrl;
    final restaurantService = _TestRestaurantService([
      const VerifiedRestaurant(
        id: 'jollibee-makati',
        name: 'Jollibee',
        branchName: 'Makati Branch',
        address: 'Makati City',
        category: 'Fast food',
        imageUrl: '',
        latitude: 14.55,
        longitude: 121.02,
        deliveryRadiusKm: 5,
        deliveryFee: 35,
        menu: [
          VerifiedMenuItem(
            id: 'chicken-joy',
            name: 'Chickenjoy Meal',
            description: 'Test verified item',
            category: 'Chicken',
            price: 129,
            imageUrl: '',
          ),
        ],
      ),
    ]);
    await tester.pumpWidget(
      FoodPandasApp(
        authService: _TestAuthService(),
        customerProfileService: profileService,
        orderService: orderService,
        restaurantService: restaurantService,
        paymentLinkLauncher: (_, url) async {
          openedPaymentUrl = url;
        },
      ),
    );
    await tester.tap(find.text('Restaurants'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Jollibee'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Browse this menu'));
    await tester.pumpAndSettle();
    final addMeal = find.byKey(const Key('add-jollibee-makati_chicken-joy'));
    await tester.ensureVisible(addMeal);
    await tester.tap(addMeal);
    await tester.pump();
    final viewCart = find.byKey(const Key('menu-view-cart'));
    await tester.ensureVisible(viewCart);
    await tester.tap(viewCart);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('go-checkout')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('customer-name')),
        matching: find.byType(TextFormField),
      ),
      'Maya Santos',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('customer-phone')),
        matching: find.byType(TextFormField),
      ),
      '09171234567',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('delivery-address')),
        matching: find.byType(TextFormField),
      ),
      '12 Sampaguita Street, Makati',
    );
    expect(
      tester.widget<RadioListTile<String>>(
        find.byKey(const Key('payment-ewallet')),
      ).enabled,
      isTrue,
    );
    expect(find.byKey(const Key('payment-card')), findsOneWidget);
    expect(
      tester.widget<RadioListTile<String>>(
        find.byKey(const Key('payment-card')),
      ).enabled,
      isTrue,
    );
    expect(
      tester.widget<RadioListTile<String>>(
        find.byKey(const Key('payment-xendit-all')),
      ).enabled,
      isTrue,
    );
    await tester.tap(find.byKey(const Key('payment-ewallet')));
    await tester.tap(find.byKey(const Key('place-order')));
    await tester.pumpAndSettle();

    expect(orderService.orders, hasLength(1));
    expect(openedPaymentUrl, 'https://checkout.xendit.co/web/test');
    expect(find.byKey(const Key('order-details-dialog')), findsOneWidget);
    expect(find.textContaining('Chickenjoy Meal'), findsOneWidget);
    expect(
      find.text('Deliver to: 12 Sampaguita Street, Makati'),
      findsOneWidget,
    );
    expect(find.text('Phone: 09171234567'), findsOneWidget);
    expect(find.text('₱164.00'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(orderService.orders.single.items.single.name, 'Chickenjoy Meal');
    expect(orderService.orders.single.paymentMethod, 'ewallet');
    expect(orderService.orders.single.deliveryFee, 35);
    expect(orderService.orders.single.phone, '09171234567');
    expect(
      find.textContaining('Delivery status: Pending Payment'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('continue-xendit-payment')), findsOneWidget);
  });

  testWidgets('order history shows persisted items, total, and statuses', (
    tester,
  ) async {
    final orderService = _TestOrderService()
      ..orders.add(
        FoodOrder(
          id: 'order-1',
          orderNumber: 'FP-12345',
          userId: 'test-user',
          customerName: 'Maya Santos',
          items: const [
            FoodOrderItem(
              id: 'adobo',
              restaurantId: 'tita-luz',
              name: 'Chicken Adobo',
              restaurantName: 'Tita Luz',
              quantity: 2,
              unitPrice: 165,
              imageUrl: '',
            ),
          ],
          subtotal: 330,
          deliveryFee: 49,
          total: 379,
          deliveryAddress: '12 Sampaguita Street',
          status: 'preparing',
          paymentStatus: 'pending',
          paymentMethod: 'cash_on_delivery',
          createdAt: DateTime(2026, 10, 26),
        ),
      );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OrderHistoryPage(
            userId: 'test-user',
            orderService: orderService,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('FP-12345'), findsOneWidget);
    await tester.tap(find.text('FP-12345'));
    await tester.pumpAndSettle();
    expect(find.text('2 × Chicken Adobo'), findsOneWidget);
    expect(find.textContaining('Preparing'), findsOneWidget);
    expect(find.textContaining('Pending'), findsOneWidget);
    expect(find.text('Deliver to: 12 Sampaguita Street'), findsOneWidget);
  });

  testWidgets('empty order history explains which checkouts are saved', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OrderHistoryPage(
            userId: 'test-user',
            orderService: _TestOrderService(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('My orders'), findsOneWidget);
    expect(find.text('No orders yet'), findsOneWidget);
    expect(
      find.textContaining('Sample menu preview checkouts are not saved'),
      findsOneWidget,
    );
  });

  testWidgets('notification center lists updates and marks them read', (
    tester,
  ) async {
    final orderService = _TestOrderService()
      ..notifications.add(
        const OrderNotification(
          id: 'notification-1',
          title: 'Order being prepared',
          body: 'FP-12345: The restaurant started preparing your order.',
          type: 'order',
          read: false,
          createdAt: null,
          orderId: 'order-1',
        ),
      );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NotificationCenterPage(
            userId: 'test-user',
            orderService: orderService,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Order being prepared'), findsOneWidget);
    await tester.tap(find.text('Order being prepared'));
    await tester.pump();
    expect(orderService.notifications.single.read, isTrue);
  });

  testWidgets('guest checkout routes to sign in instead of checkout', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      FoodPandasApp(authService: _TestAuthService(signedIn: false)),
    );
    await tester.tap(find.byKey(const Key('browse-stalls')));
    await tester.pumpAndSettle();

    final vendorCard = find.byKey(const Key('vendor-card-tita-luz'));
    await tester.ensureVisible(vendorCard);
    await tester.tap(vendorCard);
    await tester.pumpAndSettle();

    final addAdobo = find.byKey(const Key('add-adobo'));
    await tester.ensureVisible(addAdobo);
    await tester.tap(addAdobo);
    await tester.pump();

    final viewCart = find.byKey(const Key('menu-view-cart'));
    await tester.ensureVisible(viewCart);
    await tester.tap(viewCart);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('go-checkout')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('auth-page')), findsOneWidget);
    expect(find.byKey(const Key('checkout-page')), findsNothing);
  });

  testWidgets('unverified users cannot enter checkout', (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      FoodPandasApp(authService: _TestAuthService(emailVerified: false)),
    );
    await tester.tap(find.byKey(const Key('browse-stalls')));
    await tester.pumpAndSettle();

    final vendorCard = find.byKey(const Key('vendor-card-tita-luz'));
    await tester.ensureVisible(vendorCard);
    await tester.tap(vendorCard);
    await tester.pumpAndSettle();

    final addAdobo = find.byKey(const Key('add-adobo'));
    await tester.ensureVisible(addAdobo);
    await tester.tap(addAdobo);
    await tester.pump();

    final viewCart = find.byKey(const Key('menu-view-cart'));
    await tester.ensureVisible(viewCart);
    await tester.tap(viewCart);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('go-checkout')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byKey(const Key('verify-email-page')), findsOneWidget);
    expect(find.byKey(const Key('checkout-page')), findsNothing);
    expect(find.byKey(const Key('email-otp')), findsNothing);
    expect(find.text('Resend verification email'), findsOneWidget);
    await tester.tap(find.byKey(const Key('check-email-verified')));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Email is not verified yet. Open the link in your inbox, then try again.',
      ),
      findsOneWidget,
    );
  });
}
