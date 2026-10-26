import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'models/food_order.dart';
import 'screens/order_pages.dart';
import 'screens/restaurant_directory_page.dart';
import 'screens/auth/auth_pages.dart';
import 'services/auth_service.dart';
import 'services/customer_profile_service.dart';
import 'services/order_service.dart';
import 'services/push_notification_service.dart';
import 'services/restaurant_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  runApp(const FoodPandasApp());
}

const _ink = Color(0xFF30251E);
const _muted = Color(0xFF81766E);
const _orange = Color(0xFFF47B20);
const _yellow = Color(0xFFFFC84A);
const _cream = Color(0xFFFFF9EF);
const _green = Color(0xFF347A55);

class FoodPandasApp extends StatefulWidget {
  const FoodPandasApp({
    super.key,
    this.authService,
    this.customerProfileService,
    this.orderService,
    this.restaurantService,
    this.paymentLinkLauncher,
  });

  final AuthService? authService;
  final CustomerProfileService? customerProfileService;
  final OrderService? orderService;
  final RestaurantService? restaurantService;
  final Future<void> Function(BuildContext context, String url)?
  paymentLinkLauncher;

  @override
  State<FoodPandasApp> createState() => _FoodPandasAppState();
}

class _FoodPandasAppState extends State<FoodPandasApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  AppPage _page = AppPage.home;
  late final AuthService _authService;
  late final CustomerProfileService _customerProfileService;
  OrderService? _orderService;
  RestaurantService? _restaurantService;
  PushNotificationService? _pushService;
  String? _pushUserId;
  StreamSubscription<AuthUser?>? _authSubscription;
  AuthUser? _authUser;
  bool _pendingCheckout = false;
  AppPage? _pendingPage;
  Vendor? _selectedVendor;
  final List<Vendor> _verifiedVendors = [];
  final Map<String, int> _cart = {};
  String? _orderNumber;
  String _customerName = '';
  String _deliveryAddress = '';
  String? _orderDocumentId;
  bool _isDemoOrder = false;

  @override
  void initState() {
    super.initState();
    _authService = widget.authService ?? FirebaseAuthService();
    _customerProfileService =
        widget.customerProfileService ?? FirebaseCustomerProfileService();
    _orderService = widget.orderService ?? FirebaseOrderService();
    _restaurantService = widget.restaurantService ?? RestaurantService();
    _authUser = _authService.currentUser;
    if (_authUser != null) _configurePush(_authUser!);
    _authSubscription = _authService.authStateChanges.listen((user) {
      if (!mounted) return;
      if (user != null) _configurePush(user);
      setState(() {
        _authUser = user;
        if (user == null && _page == AppPage.checkout) {
          _pendingCheckout = true;
          _page = AppPage.auth;
        }
      });
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    unawaited(_pushService?.dispose());
    super.dispose();
  }

  int get _cartCount => _cart.values.fold(0, (sum, count) => sum + count);
  Iterable<Vendor> get _allVendors => vendors.followedBy(_verifiedVendors);
  List<MenuItem> get _cartItems => _allVendors
      .expand((vendor) => vendor.menu)
      .where((item) => _cart.containsKey(item.id))
      .toList();
  bool _isSampleMenuItem(MenuItem item) {
    for (final vendor in _allVendors) {
      if (vendor.menu.any((menuItem) => menuItem.id == item.id)) {
        return vendor.isSampleData;
      }
    }
    return true;
  }

  bool get _cartHasSampleItems => _cartItems.any(_isSampleMenuItem);
  bool get _cartHasVerifiedItems =>
      _cartItems.any((item) => !_isSampleMenuItem(item));
  double get _subtotal => _cartItems.fold(
    0,
    (sum, item) => sum + item.price * (_cart[item.id] ?? 0),
  );
  double get _deliveryFee {
    if (_cart.isEmpty) return 0;
    var total = 0.0;
    for (final vendor in _allVendors) {
      if (vendor.menu.any((item) => _cart.containsKey(item.id))) {
        total += vendor.deliveryFee;
      }
    }
    return total;
  }

  void _navigate(AppPage page) {
    if ((page == AppPage.orders || page == AppPage.notifications) &&
        _authService.currentUser == null) {
      setState(() {
        _pendingPage = page;
        _page = AppPage.auth;
      });
      return;
    }
    if (page == AppPage.checkout) {
      _beginCheckout();
      return;
    }
    setState(() => _page = page);
    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 120),
      alignment: 0,
    );
  }

  void _beginCheckout() {
    _pendingCheckout = true;
    final user = _authService.currentUser;
    setState(() {
      if (user == null) {
        _page = AppPage.auth;
      } else if (!user.emailVerified) {
        _authUser = user;
        _page = AppPage.verifyEmail;
      } else {
        _authUser = user;
        _page = AppPage.checkout;
      }
    });
  }

  void _onAuthenticated(AuthUser user) {
    setState(() {
      _authUser = user;
      _page = user.emailVerified ? _afterAuthPage() : AppPage.verifyEmail;
    });
  }

  AppPage _afterAuthPage() {
    final pendingPage = _pendingPage;
    if (pendingPage != null) {
      _pendingPage = null;
      return pendingPage;
    }
    if (_pendingCheckout) {
      _pendingCheckout = false;
      return AppPage.checkout;
    }
    return AppPage.home;
  }

  void _onEmailVerified() {
    final user = _authService.currentUser;
    setState(() {
      _authUser = user;
      if (user == null) {
        _page = AppPage.auth;
      } else if (!user.emailVerified) {
        _page = AppPage.verifyEmail;
      } else {
        _page = _afterAuthPage();
      }
    });
  }

  void _openAccount() {
    final user = _authService.currentUser;
    if (user == null) {
      _navigate(AppPage.auth);
    } else {
      setState(() {
        _authUser = user;
        _page = AppPage.profile;
      });
    }
  }

  void _openVerification() {
    final user = _authService.currentUser;
    if (user == null) {
      _navigate(AppPage.auth);
    } else {
      setState(() {
        _authUser = user;
        _page = AppPage.verifyEmail;
      });
    }
  }

  void _onProfileUpdated(AuthUser user) {
    setState(() => _authUser = user);
  }

  Future<void> _signOut() async {
    try {
      final user = _authService.currentUser;
      if (user != null && _orderService != null && _pushService != null) {
        await _pushService!.detachUser(
          userId: user.uid,
          orderService: _orderService!,
        );
      }
      _pushUserId = null;
      await _authService.signOut();
      if (mounted) {
        setState(() {
          _authUser = null;
          _pendingCheckout = false;
          _pendingPage = null;
          _page = AppPage.home;
        });
      }
    } on AuthFailure catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  void _openVendor(Vendor vendor) {
    setState(() {
      _selectedVendor = vendor;
      _page = AppPage.menu;
    });
  }

  void _openVerifiedRestaurant(VerifiedRestaurant restaurant) {
    final vendor = Vendor(
      id: restaurant.id,
      name: restaurant.name,
      description: restaurant.branchName,
      location: restaurant.address,
      category: restaurant.category,
      rating: '—',
      eta: 'Delivery available for your pin',
      image: restaurant.imageUrl,
      deliveryFee: restaurant.deliveryFee,
      isSampleData: false,
      menu: restaurant.menu
          .map(
            (item) => MenuItem(
              id: '${restaurant.id}_${item.id}',
              restaurantId: restaurant.id,
              catalogItemId: item.id,
              name: item.name,
              description: item.description,
              price: item.price,
              image: item.imageUrl,
            ),
          )
          .toList(growable: false),
    );
    _verifiedVendors.removeWhere((entry) => entry.id == vendor.id);
    _verifiedVendors.add(vendor);
    _openVendor(vendor);
  }

  void _changeQuantity(MenuItem item, int change) {
    setState(() {
      final quantity = (_cart[item.id] ?? 0) + change;
      if (quantity <= 0) {
        _cart.remove(item.id);
      } else {
        _cart[item.id] = quantity;
      }
    });
  }

  Future<void> _placeOrder(
    String name,
    String phone,
    String address,
    String paymentMethod,
  ) async {
    final isDemoOrder = _cartHasSampleItems;
    if (isDemoOrder && _cartHasVerifiedItems) {
      throw const OrderFailure(
        'Place sample menu items separately from verified restaurant items. Sample items are only for preview.',
      );
    }
    final user = _authService.currentUser;
    if (user == null || !user.emailVerified) {
      throw const CustomerProfileFailure(
        'Please sign in with a verified email before continuing.',
      );
    }
    await _customerProfileService.saveProfile(
      user.uid,
      CustomerProfile(
        email: user.email,
        displayName: name,
        phone: phone,
        deliveryAddress: address,
      ),
    );
    final orderService = _orderService;
    final startsOnlinePayment = paymentMethod != 'cash_on_delivery';
    if ((!isDemoOrder || startsOnlinePayment) && orderService == null) {
      throw const OrderFailure(
        'Firebase is not initialized. Configure Firebase before placing an order.',
      );
    }
    final orderNumber = isDemoOrder
        ? 'DEMO-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}'
        : 'FP-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
    final snapshots = _cartItems
        .map((item) {
          Vendor? vendor;
          for (final candidate in _allVendors) {
            if (candidate.menu.any((menuItem) => menuItem.id == item.id)) {
              vendor = candidate;
              break;
            }
          }
          return FoodOrderItem(
            id: item.catalogItemId ?? item.id,
            restaurantId: vendor?.isSampleData == true
                ? 'demo-${vendor!.id}'
                : item.restaurantId,
            name: item.name,
            restaurantName:
                vendor?.name ?? _selectedVendor?.name ?? 'Restaurant',
            quantity: _cart[item.id] ?? 0,
            unitPrice: item.price,
            imageUrl: item.image,
          );
        })
        .toList(growable: false);
    final createdOrder = isDemoOrder && !startsOnlinePayment
        ? null
        : await orderService!.createOrder(
            userId: user.uid,
            customerName: name,
            phone: phone,
            deliveryAddress: address,
            items: snapshots,
            paymentMethod: paymentMethod,
            demoOrder: isDemoOrder,
          );
    final order = FoodOrder(
      id: createdOrder?.id ?? orderNumber,
      orderNumber: createdOrder?.orderNumber ?? orderNumber,
      userId: user.uid,
      customerName: name,
      phone: phone,
      items: snapshots,
      subtotal: snapshots.fold<double>(
        0,
        (total, item) => total + item.unitPrice * item.quantity,
      ),
      deliveryFee: _deliveryFee,
      total:
          snapshots.fold<double>(
            0,
            (total, item) => total + item.unitPrice * item.quantity,
          ) +
          _deliveryFee,
      deliveryAddress: address,
      status: isDemoOrder
          ? startsOnlinePayment
                ? 'pending_payment'
                : 'sample'
          : paymentMethod != 'cash_on_delivery'
          ? 'pending_payment'
          : 'placed',
      paymentStatus: 'pending',
      paymentMethod: paymentMethod,
      createdAt: DateTime.now(),
      invoiceUrl: createdOrder?.invoiceUrl,
    );
    setState(() {
      _customerName = name;
      _deliveryAddress = address;
      _orderNumber = createdOrder?.orderNumber ?? orderNumber;
      _orderDocumentId = createdOrder?.id;
      _isDemoOrder = isDemoOrder;
      _cart.clear();
      _page = AppPage.status;
    });
    final dialogContext = _navigatorKey.currentContext;
    if (dialogContext != null && dialogContext.mounted) {
      final invoiceUrl = createdOrder?.invoiceUrl;
      if (invoiceUrl != null) {
        final launchPayment = widget.paymentLinkLauncher ?? openXenditInvoice;
        await launchPayment(dialogContext, invoiceUrl);
      }
      if (!dialogContext.mounted) return;
      await showDialog<void>(
        context: dialogContext,
        builder: (_) => OrderDetailsDialog(
          order: order,
          isDemoOrder: isDemoOrder,
          orderService: orderService,
        ),
      );
    }
  }

  void _configurePush(AuthUser user) {
    if (_orderService == null ||
        _pushUserId == user.uid ||
        Firebase.apps.isEmpty) {
      return;
    }
    _pushUserId = user.uid;
    _pushService ??= PushNotificationService();
    unawaited(
      _pushService!.initialize(userId: user.uid, orderService: _orderService!),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'Food-Pandas | Sarap from your neighborhood',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: _cream,
        colorScheme: ColorScheme.fromSeed(seedColor: _orange, primary: _orange),
        fontFamily: 'Arial',
        textTheme: const TextTheme(
          headlineLarge: TextStyle(
            color: _ink,
            fontWeight: FontWeight.w800,
            height: 1.1,
          ),
          headlineMedium: TextStyle(color: _ink, fontWeight: FontWeight.w800),
          titleLarge: TextStyle(color: _ink, fontWeight: FontWeight.w800),
          bodyLarge: TextStyle(color: _ink, height: 1.5),
          bodyMedium: TextStyle(color: _muted, height: 1.45),
        ),
      ),
      home: Scaffold(
        body: Column(
          children: [
            _SiteHeader(
              activePage: _page,
              cartCount: _cartCount,
              onNavigate: _navigate,
              authUser: _authUser,
              onOpenAccount: _openAccount,
              onOpenVerification: _openVerification,
              onSignOut: _signOut,
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: _buildPage(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPage() {
    switch (_page) {
      case AppPage.home:
        return HomePage(
          key: const ValueKey('home'),
          onBrowse: () => _navigate(AppPage.vendors),
          onOpenVendor: _openVendor,
        );
      case AppPage.vendors:
        return VendorListPage(
          key: const ValueKey('vendors'),
          onOpenVendor: _openVendor,
        );
      case AppPage.restaurants:
        return RestaurantDirectoryPage(
          key: const ValueKey('restaurants'),
          restaurantService: _restaurantService,
          onOpenRestaurant: _openVerifiedRestaurant,
        );
      case AppPage.menu:
        final vendor = _selectedVendor;
        if (vendor == null) return const VendorListPage();
        return MenuPage(
          key: ValueKey('menu-${vendor.id}'),
          vendor: vendor,
          onBack: () => _navigate(AppPage.vendors),
          onAdd: (item) => _changeQuantity(item, 1),
          onOpenCart: () => _navigate(AppPage.cart),
        );
      case AppPage.cart:
        return CartPage(
          key: const ValueKey('cart'),
          items: _cartItems,
          quantities: _cart,
          subtotal: _subtotal,
          deliveryFee: _deliveryFee,
          onQuantityChange: _changeQuantity,
          onBrowse: () => _navigate(AppPage.vendors),
          onCheckout: () => _navigate(AppPage.checkout),
        );
      case AppPage.checkout:
        final user = _authService.currentUser;
        if (user == null) {
          return AuthPage(
            key: const ValueKey('auth'),
            authService: _authService,
            onAuthenticated: _onAuthenticated,
            onForgotPassword: () => _navigate(AppPage.forgotPassword),
          );
        }
        return CheckoutPage(
          key: const ValueKey('checkout'),
          items: _cartItems,
          quantities: _cart,
          subtotal: _subtotal,
          deliveryFee: _deliveryFee,
          onBack: () => _navigate(AppPage.cart),
          onBrowseRestaurants: () => _navigate(AppPage.restaurants),
          customerProfileService: _customerProfileService,
          user: user,
          onPlaceOrder: _placeOrder,
          isSampleCheckout: _cartHasSampleItems,
        );
      case AppPage.status:
        return OrderStatusPage(
          key: const ValueKey('status'),
          orderNumber: _orderNumber,
          orderId: _orderDocumentId,
          isDemoOrder: _isDemoOrder,
          userId: _authService.currentUser?.uid,
          orderService: _orderService,
          customerName: _customerName,
          address: _deliveryAddress,
          onBrowse: () => _navigate(AppPage.vendors),
          onViewOrders: () => _navigate(AppPage.orders),
        );
      case AppPage.orders:
        final user = _authService.currentUser;
        if (user == null) return const SizedBox.shrink();
        return OrderHistoryPage(userId: user.uid, orderService: _orderService);
      case AppPage.notifications:
        final user = _authService.currentUser;
        if (user == null) return const SizedBox.shrink();
        return NotificationCenterPage(
          userId: user.uid,
          orderService: _orderService,
        );
      case AppPage.auth:
        return AuthPage(
          key: const ValueKey('auth'),
          authService: _authService,
          onAuthenticated: _onAuthenticated,
          onForgotPassword: () => _navigate(AppPage.forgotPassword),
        );
      case AppPage.verifyEmail:
        final user = _authUser ?? _authService.currentUser;
        if (user == null) {
          return AuthPage(
            key: const ValueKey('auth'),
            authService: _authService,
            onAuthenticated: _onAuthenticated,
            onForgotPassword: () => _navigate(AppPage.forgotPassword),
          );
        }
        return VerifyEmailPage(
          key: ValueKey('verify-${user.uid}'),
          authService: _authService,
          email: user.email,
          onVerified: _onEmailVerified,
          onSignOut: _signOut,
        );
      case AppPage.forgotPassword:
        return ForgotPasswordPage(
          key: const ValueKey('forgot-password'),
          authService: _authService,
          onBack: () => _navigate(AppPage.auth),
        );
      case AppPage.profile:
        final user = _authUser ?? _authService.currentUser;
        if (user == null) {
          return AuthPage(
            key: const ValueKey('auth'),
            authService: _authService,
            onAuthenticated: _onAuthenticated,
            onForgotPassword: () => _navigate(AppPage.forgotPassword),
          );
        }
        return ProfilePage(
          key: ValueKey('profile-${user.uid}'),
          authService: _authService,
          customerProfileService: _customerProfileService,
          user: user,
          onUpdated: _onProfileUpdated,
          onSignOut: _signOut,
        );
    }
  }
}

enum AppPage {
  home,
  vendors,
  menu,
  cart,
  checkout,
  status,
  auth,
  verifyEmail,
  forgotPassword,
  profile,
  restaurants,
  orders,
  notifications,
}

class Vendor {
  const Vendor({
    required this.id,
    required this.name,
    required this.description,
    required this.location,
    required this.category,
    required this.rating,
    required this.eta,
    required this.image,
    this.restaurantId = '',
    required this.menu,
    this.deliveryFee = 49,
    this.isSampleData = true,
    this.badge,
  });

  final String id;
  final String name;
  final String description;
  final String location;
  final String category;
  final String rating;
  final String eta;
  final String image;
  final String restaurantId;
  final List<MenuItem> menu;
  final double deliveryFee;
  final bool isSampleData;
  final String? badge;
}

class MenuItem {
  const MenuItem({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.image,
    this.restaurantId = '',
    this.catalogItemId,
    this.isPopular = false,
  });

  final String id;
  final String name;
  final String description;
  final double price;
  final String image;
  final String restaurantId;
  final String? catalogItemId;
  final bool isPopular;
}

final vendors = <Vendor>[
  Vendor(
    id: 'tita-luz',
    name: 'Tita Luz’s Kusina',
    description: 'Lutong-bahay classics, made fresh every morning.',
    location: 'Poblacion, Makati',
    category: 'Filipino',
    rating: '4.9',
    eta: '20–30 min',
    image: 'https://images.unsplash.com/photo-1546069901-ba9599a7e63c?auto=format&fit=crop&w=900&q=85',
    badge: 'Barkada favorite',
    menu: [
      MenuItem(
        id: 'adobo',
        name: 'Chicken Adobo',
        description: 'Soy-vinegar braised chicken, garlic rice & atchara.',
        price: 165,
        image: 'https://images.unsplash.com/photo-1604908176997-125f25cc6f3d?auto=format&fit=crop&w=700&q=85',
        isPopular: true,
      ),
      MenuItem(
        id: 'sinigang',
        name: 'Sinigang na Baboy',
        description: 'Tamarind-sour pork soup with fresh kangkong.',
        price: 195,
        image: 'https://images.unsplash.com/photo-1547592180-85f173990554?auto=format&fit=crop&w=700&q=85',
      ),
      MenuItem(
        id: 'sisig',
        name: 'Sizzling Pork Sisig',
        description: 'Crispy, tangy sisig with calamansi on the side.',
        price: 185,
        image: 'https://images.unsplash.com/photo-1544025162-d76694265947?auto=format&fit=crop&w=700&q=85',
        isPopular: true,
      ),
    ],
  ),
  Vendor(
    id: 'mang-tonyo',
    name: 'Mang Tonyo’s Ihaw-Ihaw',
    description: 'Charcoal-grilled merienda and ihaw-ihaw staples.',
    location: 'Kapitolyo, Pasig',
    category: 'Grill',
    rating: '4.8',
    eta: '25–35 min',
    image: 'https://images.unsplash.com/photo-1529193591184-b1d58069ecdd?auto=format&fit=crop&w=900&q=85',
    badge: 'Sulit meals',
    menu: [
      MenuItem(
        id: 'bbq',
        name: 'Pork BBQ Meal',
        description: 'Two sweet-savory skewers, java rice & toyomansi.',
        price: 145,
        image: 'https://images.unsplash.com/photo-1529193591184-b1d58069ecdd?auto=format&fit=crop&w=700&q=85',
        isPopular: true,
      ),
      MenuItem(
        id: 'liempo',
        name: 'Inihaw na Liempo',
        description: 'Smoky grilled pork belly with ensaladang talong.',
        price: 210,
        image: 'https://images.unsplash.com/photo-1544025162-d76694265947?auto=format&fit=crop&w=700&q=85',
      ),
      MenuItem(
        id: 'isaw',
        name: 'Isaw & Betamax Combo',
        description: 'Street-side classics with spicy suka dip.',
        price: 99,
        image: 'https://images.unsplash.com/photo-1555939594-58d7cb561ad1?auto=format&fit=crop&w=700&q=85',
      ),
    ],
  ),
  Vendor(
    id: 'ate-mels',
    name: 'Ate Mel’s Meryenda',
    description: 'Sweet Filipino merienda, just like home.',
    location: 'Marikina Heights',
    category: 'Meryenda',
    rating: '4.7',
    eta: '15–25 min',
    image: 'https://images.unsplash.com/photo-1563805042-7684c019e1cb?auto=format&fit=crop&w=900&q=85',
    menu: [
      MenuItem(
        id: 'halo-halo',
        name: 'Special Halo-Halo',
        description: 'Shaved ice, leche flan, ube & all the good stuff.',
        price: 120,
        image: 'https://images.unsplash.com/photo-1563805042-7684c019e1cb?auto=format&fit=crop&w=700&q=85',
        isPopular: true,
      ),
      MenuItem(
        id: 'turon',
        name: 'Banana Turon (3 pcs)',
        description: 'Crispy saba rolls with a caramelized sugar coat.',
        price: 75,
        image: 'https://images.unsplash.com/photo-1587132137056-bfbf0166836e?auto=format&fit=crop&w=700&q=85',
      ),
      MenuItem(
        id: 'pancit',
        name: 'Pancit Palabok',
        description: 'Noodles in rich shrimp sauce, topped with chicharon.',
        price: 135,
        image: 'https://images.unsplash.com/photo-1569718212165-3a8278d5f624?auto=format&fit=crop&w=700&q=85',
      ),
    ],
  ),
  Vendor(
    id: 'lola-bebang',
    name: 'Lola Bebang’s Panaderya',
    description: 'Fresh pandesal and bakery treats from the neighborhood.',
    location: 'Project 4, Quezon City',
    category: 'Bakery',
    rating: '4.9',
    eta: '15–25 min',
    image: 'https://images.unsplash.com/photo-1509440159596-0249088772ff?auto=format&fit=crop&w=900&q=85',
    menu: [
      MenuItem(
        id: 'pandesal',
        name: 'Pandesal (6 pcs)',
        description: 'Warm, soft pandesal rolled in toasted breadcrumbs.',
        price: 45,
        image: 'https://images.unsplash.com/photo-1509440159596-0249088772ff?auto=format&fit=crop&w=700&q=85',
        isPopular: true,
      ),
      MenuItem(
        id: 'ensaymada',
        name: 'Classic Ensaymada',
        description: 'Buttery brioche, whipped butter & grated cheese.',
        price: 65,
        image: 'https://images.unsplash.com/photo-1509365465985-25d11c17e812?auto=format&fit=crop&w=700&q=85',
      ),
      MenuItem(
        id: 'ube-cheese',
        name: 'Ube Cheese Pandesal (4 pcs)',
        description: 'Soft ube bread with a creamy cheese center.',
        price: 88,
        image: 'https://images.unsplash.com/photo-1555507036-ab1f4038808a?auto=format&fit=crop&w=700&q=85',
      ),
    ],
  ),
];

class _SiteHeader extends StatelessWidget {
  const _SiteHeader({
    required this.activePage,
    required this.cartCount,
    required this.onNavigate,
    required this.authUser,
    required this.onOpenAccount,
    required this.onOpenVerification,
    required this.onSignOut,
  });

  final AppPage activePage;
  final int cartCount;
  final ValueChanged<AppPage> onNavigate;
  final AuthUser? authUser;
  final VoidCallback onOpenAccount;
  final VoidCallback onOpenVerification;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 900;
                  return Row(
                    children: [
                      InkWell(
                        key: const Key('brand-home'),
                        onTap: () => onNavigate(AppPage.home),
                        borderRadius: BorderRadius.circular(14),
                        child: const Row(
                          children: [
                            _BrandMark(size: 42),
                            SizedBox(width: 10),
                            Text(
                              'food-pandas',
                              style: TextStyle(
                                color: _ink,
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.8,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      if (!compact) ...[
                        _NavButton(
                          label: 'Home',
                          selected: activePage == AppPage.home,
                          onTap: () => onNavigate(AppPage.home),
                        ),
                        _NavButton(
                          label: 'Find food stalls',
                          selected:
                              activePage == AppPage.vendors ||
                              activePage == AppPage.menu,
                          onTap: () => onNavigate(AppPage.vendors),
                        ),
                        _NavButton(
                          label: 'Restaurants',
                          selected: activePage == AppPage.restaurants,
                          onTap: () => onNavigate(AppPage.restaurants),
                        ),
                        const SizedBox(width: 12),
                      ],
                      if (compact)
                        PopupMenuButton<AppPage>(
                          tooltip: 'Open navigation',
                          icon: const Icon(Icons.menu_rounded, color: _ink),
                          onSelected: onNavigate,
                          itemBuilder: (context) => const [
                            PopupMenuItem(
                              value: AppPage.home,
                              child: Text('Home'),
                            ),
                            PopupMenuItem(
                              value: AppPage.vendors,
                              child: Text('Find food stalls'),
                            ),
                            PopupMenuItem(
                              value: AppPage.restaurants,
                              child: Text('Restaurants'),
                            ),
                            PopupMenuItem(
                              value: AppPage.orders,
                              child: Text('My orders'),
                            ),
                            PopupMenuItem(
                              value: AppPage.notifications,
                              child: Text('Notifications'),
                            ),
                          ],
                        ),
                      _CartButton(
                        count: cartCount,
                        onTap: () => onNavigate(AppPage.cart),
                      ),
                      const SizedBox(width: 8),
                      _AccountMenu(
                        user: authUser,
                        compact: compact,
                        onOpenAccount: onOpenAccount,
                        onOpenVerification: onOpenVerification,
                        onSignOut: onSignOut,
                        onNavigate: onNavigate,
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AccountMenu extends StatelessWidget {
  const _AccountMenu({
    required this.user,
    required this.compact,
    required this.onOpenAccount,
    required this.onOpenVerification,
    required this.onSignOut,
    required this.onNavigate,
  });

  final AuthUser? user;
  final bool compact;
  final VoidCallback onOpenAccount;
  final VoidCallback onOpenVerification;
  final VoidCallback onSignOut;
  final ValueChanged<AppPage> onNavigate;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: user == null ? 'Sign in or create an account' : 'Account options',
    onSelected: (action) {
      if (action == 'sign-out') {
        onSignOut();
      } else if (action == 'verify') {
        onOpenVerification();
      } else if (action == 'orders') {
        onNavigate(AppPage.orders);
      } else if (action == 'notifications') {
        onNavigate(AppPage.notifications);
      } else {
        onOpenAccount();
      }
    },
    itemBuilder: (context) => [
      if (user == null)
        const PopupMenuItem(
          value: 'sign-in',
          child: Text('Sign in / create account'),
        )
      else ...[
        PopupMenuItem(
          enabled: false,
          child: Text(user!.email, overflow: TextOverflow.ellipsis),
        ),
        const PopupMenuItem(value: 'profile', child: Text('Profile')),
        const PopupMenuItem(value: 'orders', child: Text('My orders')),
        const PopupMenuItem(
          value: 'notifications',
          child: Text('Notifications'),
        ),
        if (!user!.emailVerified)
          const PopupMenuItem(value: 'verify', child: Text('Verify email')),
        const PopupMenuItem(value: 'sign-out', child: Text('Sign out')),
      ],
    ],
    child: compact
        ? Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFE9E0D7)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              user == null
                  ? Icons.person_outline_rounded
                  : Icons.person_rounded,
              color: _ink,
              size: 20,
            ),
          )
        : Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFE9E0D7)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  user == null
                      ? Icons.person_outline_rounded
                      : Icons.person_rounded,
                  size: 18,
                  color: _ink,
                ),
                const SizedBox(width: 7),
                Text(
                  user == null ? 'Sign in' : 'Account',
                  style: const TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
  );
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: _yellow,
      borderRadius: BorderRadius.circular(size * .34),
    ),
    child: Icon(Icons.delivery_dining_rounded, size: size * .68, color: _ink),
  );
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onTap,
    style: TextButton.styleFrom(
      foregroundColor: selected ? _orange : _ink,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      textStyle: TextStyle(
        fontSize: 14,
        fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
      ),
    ),
    child: Text(label),
  );
}

class _CartButton extends StatelessWidget {
  const _CartButton({required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    key: const Key('header-cart'),
    onPressed: onTap,
    icon: Badge(
      isLabelVisible: count > 0,
      label: Text('$count'),
      child: const Icon(Icons.shopping_bag_outlined, size: 19),
    ),
    label: const Text('Cart'),
    style: OutlinedButton.styleFrom(
      foregroundColor: _ink,
      side: const BorderSide(color: Color(0xFFE9E0D7)),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      textStyle: const TextStyle(fontWeight: FontWeight.w700),
    ),
  );
}

class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.onBrowse,
    required this.onOpenVendor,
  });

  final VoidCallback onBrowse;
  final ValueChanged<Vendor> onOpenVendor;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    key: const Key('home-page'),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 56),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final narrow = constraints.maxWidth < 760;
                  final intro = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFEBC5),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: const Text(
                          'YOUR NEIGHBORHOOD, ON THE MENU',
                          style: TextStyle(
                            color: Color(0xFF8D4A10),
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Sarap na malapit.\nOne tap na lang.',
                        style: TextStyle(
                          color: _ink,
                          fontSize: narrow ? 42 : 56,
                          fontWeight: FontWeight.w900,
                          height: 1.05,
                          letterSpacing: -2.2,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Your favorite lutong-bahay, ihaw-ihaw, and merienda '
                        'from the food stalls around your kanto.',
                        style: TextStyle(
                          color: _muted,
                          fontSize: 16,
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        key: const Key('browse-stalls'),
                        onPressed: onBrowse,
                        icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                        label: const Text('Explore food stalls'),
                        style: FilledButton.styleFrom(
                          backgroundColor: _orange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 22,
                            vertical: 17,
                          ),
                        ),
                      ),
                    ],
                  );
                  final heroImage = ClipRRect(
                    borderRadius: BorderRadius.circular(30),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _FoodImage(
                          url: vendors.first.menu.first.image,
                          icon: Icons.rice_bowl_rounded,
                        ),
                        Positioned(
                          left: 16,
                          bottom: 16,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 11,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: .95),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Row(
                              children: [
                                Icon(
                                  Icons.star_rounded,
                                  color: _orange,
                                  size: 20,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'Neighborhood-loved meals',
                                  style: TextStyle(
                                    color: _ink,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                  if (narrow) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        intro,
                        const SizedBox(height: 28),
                        SizedBox(height: 270, child: heroImage),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(flex: 11, child: intro),
                      const SizedBox(width: 42),
                      Expanded(
                        flex: 10,
                        child: SizedBox(height: 390, child: heroImage),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 52),
              const _SectionHeading(
                eyebrow: 'GOOD FOOD, GOOD NEIGHBORS',
                title: 'Meet the food stalls',
                subtitle: 'Small local kitchens, big-time sarap.',
              ),
              const SizedBox(height: 22),
              _VendorGrid(
                vendors: vendors.take(3).toList(),
                onOpen: onOpenVendor,
              ),
              const SizedBox(height: 24),
              Center(
                child: OutlinedButton.icon(
                  onPressed: onBrowse,
                  icon: const Icon(Icons.storefront_outlined),
                  label: const Text('See all food stalls'),
                ),
              ),
              const SizedBox(height: 56),
              const _WhySection(),
              const SizedBox(height: 38),
              const _SiteFooter(),
            ],
          ),
        ),
      ),
    ),
  );
}

class VendorListPage extends StatefulWidget {
  const VendorListPage({super.key, this.onOpenVendor});
  final ValueChanged<Vendor>? onOpenVendor;

  @override
  State<VendorListPage> createState() => _VendorListPageState();
}

class _VendorListPageState extends State<VendorListPage> {
  String _category = 'All';
  String _query = '';
  static const categories = ['All', 'Filipino', 'Grill', 'Meryenda', 'Bakery'];

  @override
  Widget build(BuildContext context) {
    final filtered = vendors.where((vendor) {
      final matchesCategory =
          _category == 'All' || vendor.category == _category;
      final matchesQuery =
          '${vendor.name} ${vendor.category} ${vendor.location}'
              .toLowerCase()
              .contains(_query.toLowerCase());
      return matchesCategory && matchesQuery;
    }).toList();

    return SingleChildScrollView(
      key: const Key('vendors-page'),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 36, 22, 56),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionHeading(
                  eyebrow: 'FROM OUR KANTO TO YOUR TABLE',
                  title: 'Find your next favorite',
                  subtitle: 'Discover independent food stalls serving your neighborhood.',
                ),
                const SizedBox(height: 24),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: TextField(
                    key: const Key('vendor-search'),
                    onChanged: (value) => setState(() => _query = value),
                    decoration: InputDecoration(
                      hintText: 'Search stalls, food, or location',
                      prefixIcon: const Icon(Icons.search_rounded),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 10,
                  runSpacing: 9,
                  children: categories
                      .map(
                        (category) => ChoiceChip(
                          label: Text(category),
                          selected: _category == category,
                          onSelected: (_) =>
                              setState(() => _category = category),
                          selectedColor: const Color(0xFFFFE6C9),
                          labelStyle: TextStyle(
                            color: _category == category ? _orange : _ink,
                            fontWeight: FontWeight.w700,
                          ),
                          side: BorderSide.none,
                          backgroundColor: Colors.white,
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 24),
                if (filtered.isEmpty)
                  const _EmptyState(
                    icon: Icons.search_off_rounded,
                    title: 'Walang mahanap',
                    message: 'Try another name or browse a different category.',
                  )
                else
                  _VendorGrid(
                    vendors: filtered,
                    onOpen: widget.onOpenVendor ?? (_) {},
                  ),
                const SizedBox(height: 42),
                const _SiteFooter(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VendorGrid extends StatelessWidget {
  const _VendorGrid({required this.vendors, required this.onOpen});
  final List<Vendor> vendors;
  final ValueChanged<Vendor> onOpen;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 900
          ? 3
          : constraints.maxWidth >= 580
          ? 2
          : 1;
      final ratio = columns == 1 ? 1.32 : 0.91;
      return GridView.builder(
        key: const Key('vendor-grid'),
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: vendors.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: 18,
          mainAxisSpacing: 18,
          childAspectRatio: ratio,
        ),
        itemBuilder: (context, index) => _VendorCard(
          vendor: vendors[index],
          onTap: () => onOpen(vendors[index]),
        ),
      );
    },
  );
}

class _VendorCard extends StatelessWidget {
  const _VendorCard({required this.vendor, required this.onTap});
  final Vendor vendor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    key: Key('vendor-card-${vendor.id}'),
    clipBehavior: Clip.antiAlias,
    elevation: 0,
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(22),
      side: const BorderSide(color: Color(0xFFF0E8DF)),
    ),
    child: InkWell(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 6,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _FoodImage(url: vendor.image, icon: Icons.storefront_rounded),
                if (vendor.badge != null)
                  Positioned(
                    left: 12,
                    top: 12,
                    child: _Pill(
                      label: vendor.badge!,
                      color: Colors.white,
                      textColor: _ink,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 5,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          vendor.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _ink,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const Icon(Icons.star_rounded, color: _orange, size: 18),
                      const SizedBox(width: 3),
                      Text(
                        vendor.rating,
                        style: const TextStyle(
                          color: _ink,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    vendor.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        size: 15,
                        color: _muted,
                      ),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          vendor.location,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: _muted, fontSize: 11),
                        ),
                      ),
                      Text(
                        vendor.eta,
                        style: const TextStyle(
                          color: _green,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class MenuPage extends StatelessWidget {
  const MenuPage({
    super.key,
    required this.vendor,
    required this.onBack,
    required this.onAdd,
    required this.onOpenCart,
  });

  final Vendor vendor;
  final VoidCallback onBack;
  final ValueChanged<MenuItem> onAdd;
  final VoidCallback onOpenCart;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    key: const Key('menu-page'),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 26, 22, 52),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextButton.icon(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('All food stalls'),
              ),
              const SizedBox(height: 10),
              LayoutBuilder(
                builder: (context, constraints) {
                  final narrow = constraints.maxWidth < 650;
                  final image = ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: _FoodImage(
                      url: vendor.image,
                      icon: Icons.storefront_rounded,
                    ),
                  );
                  final info = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _Pill(
                        label: vendor.category,
                        color: const Color(0xFFFFE9CA),
                        textColor: _orange,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        vendor.name,
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 9),
                      Text(vendor.description),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 16,
                        runSpacing: 8,
                        children: [
                          _Meta(
                            icon: Icons.star_rounded,
                            text: '${vendor.rating} rating',
                          ),
                          _Meta(icon: Icons.schedule_rounded, text: vendor.eta),
                          _Meta(
                            icon: Icons.location_on_outlined,
                            text: vendor.location,
                          ),
                        ],
                      ),
                    ],
                  );
                  if (narrow) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(height: 210, child: image),
                        const SizedBox(height: 20),
                        info,
                      ],
                    );
                  }
                  return SizedBox(
                    height: 250,
                    child: Row(
                      children: [
                        Expanded(child: image),
                        const SizedBox(width: 28),
                        Expanded(child: info),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 38),
              const _SectionHeading(
                eyebrow: 'FRESH FROM THE KITCHEN',
                title: 'The menu',
                subtitle: 'Made with love. Add your favorites to the bag.',
              ),
              const SizedBox(height: 18),
              ...vendor.menu.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _MenuItemCard(item: item, onAdd: () => onAdd(item)),
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  key: const Key('menu-view-cart'),
                  onPressed: onOpenCart,
                  icon: const Icon(Icons.shopping_bag_outlined),
                  label: const Text('View cart'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 15,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _MenuItemCard extends StatelessWidget {
  const _MenuItemCard({required this.item, required this.onAdd});
  final MenuItem item;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF0E8DF)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 480;
          final photo = ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: _FoodImage(url: item.image, icon: Icons.restaurant_rounded),
          );
          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      item.name,
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (item.isPopular)
                    const _Pill(
                      label: 'POPULAR',
                      color: Color(0xFFFFE9CA),
                      textColor: Color(0xFF9B5112),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(item.description, style: const TextStyle(fontSize: 13)),
              const Spacer(),
              Row(
                children: [
                  Text(
                    _peso(item.price),
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Spacer(),
                  FilledButton(
                    key: Key('add-${item.id}'),
                    onPressed: onAdd,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(42, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      backgroundColor: const Color(0xFFFFF0D8),
                      foregroundColor: _orange,
                      elevation: 0,
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.add_rounded, size: 18),
                        SizedBox(width: 4),
                        Text(
                          'Add',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          );
          if (compact) {
            return SizedBox(
              height: 150,
              child: Row(
                children: [
                  SizedBox(width: 112, height: 122, child: photo),
                  const SizedBox(width: 14),
                  Expanded(child: details),
                ],
              ),
            );
          }
          return SizedBox(
            height: 152,
            child: Row(
              children: [
                SizedBox(width: 155, height: 124, child: photo),
                const SizedBox(width: 18),
                Expanded(child: details),
              ],
            ),
          );
        },
      ),
    );
  }
}

class CartPage extends StatelessWidget {
  const CartPage({
    super.key,
    required this.items,
    required this.quantities,
    required this.subtotal,
    required this.deliveryFee,
    required this.onQuantityChange,
    required this.onBrowse,
    required this.onCheckout,
  });

  final List<MenuItem> items;
  final Map<String, int> quantities;
  final double subtotal;
  final double deliveryFee;
  final void Function(MenuItem, int) onQuantityChange;
  final VoidCallback onBrowse;
  final VoidCallback onCheckout;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    key: const Key('cart-page'),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 36, 22, 56),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionHeading(
                eyebrow: 'YOUR PICKS',
                title: 'Your cart',
                subtitle: 'A little something delicious is on its way.',
              ),
              const SizedBox(height: 24),
              if (items.isEmpty)
                _EmptyState(
                  icon: Icons.shopping_bag_outlined,
                  title: 'Your cart is empty',
                  message:
                      'Find a neighborhood favorite and add something sarap.',
                  actionLabel: 'Browse food stalls',
                  onAction: onBrowse,
                )
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    final narrow = constraints.maxWidth < 720;
                    final itemList = Column(
                      children: items
                          .map(
                            (item) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _CartItemRow(
                                item: item,
                                quantity: quantities[item.id] ?? 0,
                                onChange: (change) =>
                                    onQuantityChange(item, change),
                              ),
                            ),
                          )
                          .toList(),
                    );
                    final summary = _OrderSummary(
                      subtotal: subtotal,
                      deliveryFee: deliveryFee,
                      buttonLabel: 'Proceed to checkout',
                      onPressed: onCheckout,
                    );
                    if (narrow) {
                      return Column(
                        children: [
                          itemList,
                          const SizedBox(height: 16),
                          summary,
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 7, child: itemList),
                        const SizedBox(width: 22),
                        Expanded(flex: 4, child: summary),
                      ],
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _CartItemRow extends StatelessWidget {
  const _CartItemRow({
    required this.item,
    required this.quantity,
    required this.onChange,
  });
  final MenuItem item;
  final int quantity;
  final ValueChanged<int> onChange;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFF0E8DF)),
    ),
    child: Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(13),
          child: SizedBox(
            width: 78,
            height: 78,
            child: _FoodImage(url: item.image, icon: Icons.restaurant_rounded),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.name,
                style: const TextStyle(
                  color: _ink,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                _peso(item.price),
                style: const TextStyle(color: _muted, fontSize: 13),
              ),
            ],
          ),
        ),
        _QuantityControl(quantity: quantity, onChange: onChange),
      ],
    ),
  );
}

class _QuantityControl extends StatelessWidget {
  const _QuantityControl({required this.quantity, required this.onChange});
  final int quantity;
  final ValueChanged<int> onChange;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _QuantityButton(icon: Icons.remove_rounded, onTap: () => onChange(-1)),
      SizedBox(
        width: 34,
        child: Text(
          '$quantity',
          textAlign: TextAlign.center,
          style: const TextStyle(color: _ink, fontWeight: FontWeight.w800),
        ),
      ),
      _QuantityButton(icon: Icons.add_rounded, onTap: () => onChange(1)),
    ],
  );
}

class _QuantityButton extends StatelessWidget {
  const _QuantityButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(9),
    child: Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: const Color(0xFFFFF0D8),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Icon(icon, color: _orange, size: 18),
    ),
  );
}

class CheckoutPage extends StatefulWidget {
  const CheckoutPage({
    super.key,
    required this.items,
    required this.quantities,
    required this.subtotal,
    required this.deliveryFee,
    required this.onBack,
    required this.onBrowseRestaurants,
    required this.customerProfileService,
    required this.user,
    required this.onPlaceOrder,
    this.isSampleCheckout = false,
  });

  final List<MenuItem> items;
  final Map<String, int> quantities;
  final double subtotal;
  final double deliveryFee;
  final VoidCallback onBack;
  final VoidCallback onBrowseRestaurants;
  final CustomerProfileService customerProfileService;
  final AuthUser user;
  final Future<void> Function(
    String name,
    String phone,
    String address,
    String paymentMethod,
  )
  onPlaceOrder;
  final bool isSampleCheckout;

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  String? _profileError;
  String? _submitError;
  String _paymentMethod = 'cash_on_delivery';

  @override
  void initState() {
    super.initState();
    unawaited(_loadSavedProfile());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    key: const Key('checkout-page'),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 36, 22, 56),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_profileError != null) ...[
                Text(
                  _profileError!,
                  key: const Key('profile-load-error'),
                  style: const TextStyle(color: Colors.red),
                ),
                const SizedBox(height: 12),
              ],
              if (_submitError != null) ...[
                Text(
                  _submitError!,
                  key: const Key('profile-save-error'),
                  style: const TextStyle(color: Colors.red),
                ),
                const SizedBox(height: 12),
              ],
              const _SectionHeading(
                eyebrow: 'ALMOST THERE',
                title: 'Checkout',
                subtitle: 'Where should we bring the good stuff?',
              ),
              const SizedBox(height: 22),
              if (widget.items.isEmpty)
                _EmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'Nothing to check out yet',
                  message:
                      'Your cart is empty. Browse stalls to start an order.',
                  actionLabel: 'Browse food stalls',
                  onAction: widget.onBack,
                )
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    final narrow = constraints.maxWidth < 720;
                    final form = _checkoutForm();
                    final summary = _OrderSummary(
                      subtotal: widget.subtotal,
                      deliveryFee: widget.deliveryFee,
                      buttonLabel: 'Place my order',
                      onPressed: _submit,
                    );
                    if (narrow) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [form, const SizedBox(height: 16), summary],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 7, child: form),
                        const SizedBox(width: 22),
                        Expanded(flex: 4, child: summary),
                      ],
                    );
                  },
                ),
              const SizedBox(height: 20),
              TextButton.icon(
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('Back to cart'),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _checkoutForm() => Form(
    key: _formKey,
    child: Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF0E8DF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Delivery details',
            style: TextStyle(
              color: _ink,
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          _CheckoutField(
            key: const Key('customer-name'),
            controller: _nameController,
            label: 'Full name',
            icon: Icons.person_outline_rounded,
            maxLength: 100,
            validator: (value) =>
                value == null ||
                    value.trim().isEmpty ||
                    value.trim().length > 100
                ? 'Enter a name up to 100 characters'
                : null,
          ),
          const SizedBox(height: 12),
          _CheckoutField(
            key: const Key('customer-phone'),
            controller: _phoneController,
            label: 'Mobile number',
            icon: Icons.phone_outlined,
            keyboardType: TextInputType.phone,
            maxLength: 30,
            validator: (value) =>
                value == null ||
                    value.trim().length < 7 ||
                    value.trim().length > 30
                ? 'Enter a valid mobile number'
                : null,
          ),
          const SizedBox(height: 12),
          _CheckoutField(
            key: const Key('delivery-address'),
            controller: _addressController,
            label: 'Complete delivery address',
            icon: Icons.location_on_outlined,
            maxLines: 3,
            maxLength: 500,
            validator: (value) =>
                value == null ||
                    value.trim().isEmpty ||
                    value.trim().length > 500
                ? 'Enter a delivery address up to 500 characters'
                : null,
          ),
          const SizedBox(height: 14),
          const Text(
            'Payment method',
            style: TextStyle(
              color: _ink,
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Material(
            color: Colors.transparent,
            child: RadioGroup<String>(
              groupValue: _paymentMethod,
              onChanged: (value) {
                if (value != null) setState(() => _paymentMethod = value);
              },
              child: Column(
                children: [
                  const RadioListTile<String>(
                    key: Key('payment-cash-on-delivery'),
                    contentPadding: EdgeInsets.zero,
                    value: 'cash_on_delivery',
                    title: Text('Cash on delivery'),
                    subtitle: Text('Pay when your order arrives'),
                    activeColor: _green,
                  ),
                  RadioListTile<String>(
                    key: const Key('payment-ewallet'),
                    contentPadding: EdgeInsets.zero,
                    value: 'ewallet',
                    title: const Text('E-wallet'),
                    subtitle: Text(
                      widget.isSampleCheckout
                          ? 'Opens Xendit sandbox checkout (GCash or GrabPay)'
                          : 'Place your order to open secure Xendit checkout (GCash or GrabPay)',
                    ),
                    activeColor: _green,
                    enabled: true,
                  ),
                  RadioListTile<String>(
                    key: const Key('payment-card'),
                    contentPadding: EdgeInsets.zero,
                    value: 'card',
                    title: const Text('Credit or debit card'),
                    subtitle: Text(
                      widget.isSampleCheckout
                          ? 'Available for verified restaurant orders'
                          : 'Pay securely by card via Xendit',
                    ),
                    activeColor: _green,
                    enabled: !widget.isSampleCheckout,
                  ),
                  RadioListTile<String>(
                    key: const Key('payment-xendit-all'),
                    contentPadding: EdgeInsets.zero,
                    value: 'xendit',
                    title: const Text('All available online methods'),
                    subtitle: Text(
                      widget.isSampleCheckout
                          ? 'Available for verified restaurant orders'
                          : 'Choose any payment method enabled on Xendit',
                    ),
                    activeColor: _green,
                    enabled: !widget.isSampleCheckout,
                  ),
                  if (widget.isSampleCheckout)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Demo menu only. E-wallet opens a Xendit development checkout; no restaurant will fulfill this order.',
                            key: Key('sample-payment-notice'),
                            style: TextStyle(color: _muted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> _loadSavedProfile() async {
    try {
      final profile = await widget.customerProfileService.getProfile(
        widget.user.uid,
      );
      if (!mounted || profile == null) return;
      if (_nameController.text.isEmpty) {
        _nameController.text = profile.displayName;
      }
      if (_phoneController.text.isEmpty) {
        _phoneController.text = profile.phone;
      }
      if (_addressController.text.isEmpty) {
        _addressController.text = profile.deliveryAddress;
      }
      setState(() => _profileError = null);
    } on CustomerProfileFailure catch (error) {
      if (mounted) setState(() => _profileError = error.message);
    }
  }

  Future<void> _submit() async {
    if (_formKey.currentState?.validate() ?? false) {
      setState(() => _submitError = null);
      try {
        await widget.onPlaceOrder(
          _nameController.text.trim(),
          _phoneController.text.trim(),
          _addressController.text.trim(),
          _paymentMethod,
        );
      } on CustomerProfileFailure catch (error) {
        if (mounted) setState(() => _submitError = error.message);
      } on OrderFailure catch (error) {
        if (mounted) setState(() => _submitError = error.message);
      }
    }
  }
}

class _CheckoutField extends StatelessWidget {
  const _CheckoutField({
    super.key,
    required this.controller,
    required this.label,
    required this.icon,
    required this.validator,
    this.keyboardType,
    this.maxLines = 1,
    this.maxLength,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final String? Function(String?) validator;
  final TextInputType? keyboardType;
  final int maxLines;
  final int? maxLength;

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    validator: validator,
    keyboardType: keyboardType,
    maxLines: maxLines,
    maxLength: maxLength,
    decoration: InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20),
      alignLabelWithHint: maxLines > 1,
      filled: true,
      fillColor: const Color(0xFFFFFCF7),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: Color(0xFFECE4DA)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: Color(0xFFECE4DA)),
      ),
    ),
  );
}

class OrderStatusPage extends StatelessWidget {
  const OrderStatusPage({
    super.key,
    required this.orderNumber,
    required this.orderId,
    required this.isDemoOrder,
    required this.userId,
    required this.orderService,
    required this.customerName,
    required this.address,
    required this.onBrowse,
    required this.onViewOrders,
  });

  final String? orderNumber;
  final String? orderId;
  final bool isDemoOrder;
  final String? userId;
  final OrderService? orderService;
  final String customerName;
  final String address;
  final VoidCallback onBrowse;
  final VoidCallback onViewOrders;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    key: const Key('status-page'),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 52, 22, 60),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(30),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: const Color(0xFFF0E8DF)),
            ),
            child: Column(
              children: [
                Container(
                  width: 78,
                  height: 78,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE7F4E9),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: _green,
                    size: 42,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Thanks, salamat!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _ink,
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isDemoOrder
                      ? 'Thanks${customerName.isEmpty ? '' : ', $customerName'}! This demo e-wallet order is for sandbox payment only; no restaurant will fulfill it.'
                      : 'Thanks${customerName.isEmpty ? '' : ', $customerName'}! Your order was saved. Payment and restaurant status updates appear below.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: _cream,
                    borderRadius: BorderRadius.circular(17),
                  ),
                  child: Column(
                    children: [
                      Text(
                        isDemoOrder ? 'SAMPLE CHECKOUT' : 'ORDER NUMBER',
                        style: TextStyle(
                          color: _muted,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        orderNumber ?? 'No recent order',
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (address.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Delivering to: $address',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _liveOrderStatus(),
                const SizedBox(height: 22),
                FilledButton.tonalIcon(
                  onPressed: onViewOrders,
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('View my orders'),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: onBrowse,
                  icon: const Icon(Icons.storefront_outlined),
                  label: const Text('Order something else'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 15,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Demo only — order status is not connected to a live kitchen.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  Widget _liveOrderStatus() {
    if (isDemoOrder) {
      return const Text(
        'Sandbox payment only. No restaurant will fulfill this demo menu order.',
        textAlign: TextAlign.center,
      );
    }
    final service = orderService;
    final id = orderId;
    final uid = userId;
    if (service == null || id == null || uid == null) {
      return const Text(
        'Your order was recorded. Status updates are available in My orders.',
      );
    }
    return StreamBuilder<FoodOrder?>(
      stream: service.watchOrder(id, uid),
      builder: (context, snapshot) {
        final order = snapshot.data;
        if (order == null) {
          return const Text(
            'Your order was recorded in Firebase. Live updates will appear in My orders.',
          );
        }
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _cream,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              Text(
                'Delivery status: ${_orderLabel(order.status)}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text('Payment: ${_orderLabel(order.paymentStatus)}'),
              if ((order.paymentMethod == 'ewallet' ||
                      order.paymentMethod == 'card' ||
                      order.paymentMethod == 'xendit') &&
                  order.paymentStatus == 'pending' &&
                  order.invoiceUrl != null) ...[
                const SizedBox(height: 10),
                FilledButton.icon(
                  key: const Key('continue-xendit-payment'),
                  onPressed: () =>
                      openXenditInvoice(context, order.invoiceUrl!),
                  icon: const Icon(Icons.account_balance_wallet_outlined),
                  label: const Text('Continue to Xendit'),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

String _orderLabel(String value) {
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

class _OrderSummary extends StatelessWidget {
  const _OrderSummary({
    required this.subtotal,
    required this.deliveryFee,
    required this.buttonLabel,
    required this.onPressed,
  });

  final double subtotal;
  final double deliveryFee;
  final String buttonLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFF0E8DF)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Order summary',
          style: TextStyle(
            color: _ink,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 18),
        _PriceRow(label: 'Subtotal', amount: subtotal),
        const SizedBox(height: 10),
        _PriceRow(label: 'Delivery fee', amount: deliveryFee),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 14),
          child: Divider(height: 1),
        ),
        _PriceRow(label: 'Total', amount: subtotal + deliveryFee, bold: true),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            key: Key(
              buttonLabel == 'Place my order' ? 'place-order' : 'go-checkout',
            ),
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              backgroundColor: _orange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 15),
            ),
            child: Text(buttonLabel),
          ),
        ),
        const SizedBox(height: 9),
        const Center(
          child: Text(
            'Delivery fee is a demo estimate.',
            style: TextStyle(color: _muted, fontSize: 11),
          ),
        ),
      ],
    ),
  );
}

class _PriceRow extends StatelessWidget {
  const _PriceRow({
    required this.label,
    required this.amount,
    this.bold = false,
  });
  final String label;
  final double amount;
  final bool bold;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          label,
          style: TextStyle(
            color: bold ? _ink : _muted,
            fontWeight: bold ? FontWeight.w900 : FontWeight.w500,
          ),
        ),
      ),
      Text(
        _peso(amount),
        style: TextStyle(
          color: _ink,
          fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
          fontSize: bold ? 18 : 14,
        ),
      ),
    ],
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 45),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xFFF0E8DF)),
    ),
    child: Column(
      children: [
        Icon(icon, color: _orange, size: 42),
        const SizedBox(height: 12),
        Text(
          title,
          style: const TextStyle(
            color: _ink,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(message, textAlign: TextAlign.center),
        if (actionLabel != null) ...[
          const SizedBox(height: 18),
          OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ],
    ),
  );
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
  });
  final String eyebrow;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        eyebrow,
        style: const TextStyle(
          color: _orange,
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.4,
        ),
      ),
      const SizedBox(height: 7),
      Text(
        title,
        style: const TextStyle(
          color: _ink,
          fontSize: 30,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.8,
        ),
      ),
      const SizedBox(height: 5),
      Text(subtitle, style: const TextStyle(color: _muted)),
    ],
  );
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.color,
    required this.textColor,
  });
  final String label;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(30),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: textColor,
        fontSize: 10,
        fontWeight: FontWeight.w900,
        letterSpacing: .2,
      ),
    ),
  );
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 16, color: _orange),
      const SizedBox(width: 5),
      Text(text, style: const TextStyle(color: _muted, fontSize: 12)),
    ],
  );
}

class _FoodImage extends StatelessWidget {
  const _FoodImage({required this.url, required this.icon});
  final String url;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Image.network(
    url,
    fit: BoxFit.cover,
    loadingBuilder: (context, child, progress) => progress == null
        ? child
        : Container(
            color: const Color(0xFFFFE8C7),
            child: Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: _orange,
                value: progress.expectedTotalBytes == null
                    ? null
                    : progress.cumulativeBytesLoaded /
                          progress.expectedTotalBytes!,
              ),
            ),
          ),
    errorBuilder: (context, error, stackTrace) => Container(
      color: const Color(0xFFFFE8C7),
      child: Center(child: Icon(icon, color: _orange, size: 40)),
    ),
  );
}

class _WhySection extends StatelessWidget {
  const _WhySection();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(26),
    decoration: BoxDecoration(
      color: const Color(0xFFFFE9C9),
      borderRadius: BorderRadius.circular(24),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 700;
        final features = const [
          _Feature(
            icon: Icons.storefront_rounded,
            title: 'Support your kanto',
            description:
                'Every order helps local cooks and small food stalls grow.',
          ),
          _Feature(
            icon: Icons.soup_kitchen_rounded,
            title: 'Made fresh, always',
            description:
                'Real neighborhood kitchens. Real lutong-bahay goodness.',
          ),
          _Feature(
            icon: Icons.favorite_rounded,
            title: 'Sarap with a story',
            description: 'Find the family recipes and stalls people love most.',
          ),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Food tastes better when it helps the neighborhood.',
              style: TextStyle(
                color: _ink,
                fontSize: 21,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 22),
            if (compact)
              Column(
                children: features
                    .map(
                      (feature) => Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: feature,
                      ),
                    )
                    .toList(),
              )
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: features
                    .map(
                      (feature) => Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 18),
                          child: feature,
                        ),
                      ),
                    )
                    .toList(),
              ),
          ],
        );
      },
    ),
  );
}

class _Feature extends StatelessWidget {
  const _Feature({
    required this.icon,
    required this.title,
    required this.description,
  });
  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: _orange, size: 20),
      ),
      const SizedBox(width: 11),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(color: _ink, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              description,
              style: const TextStyle(color: _muted, fontSize: 12),
            ),
          ],
        ),
      ),
    ],
  );
}

class _SiteFooter extends StatelessWidget {
  const _SiteFooter();

  @override
  Widget build(BuildContext context) => const Center(
    child: Text(
      'Made with ♥ for neighborhood food lovers  •  Food-Pandas demo',
      textAlign: TextAlign.center,
      style: TextStyle(color: _muted, fontSize: 12),
    ),
  );
}

String _peso(double amount) => '₱${amount.toStringAsFixed(0)}';
