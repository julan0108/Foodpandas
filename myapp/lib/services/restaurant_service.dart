import 'package:cloud_firestore/cloud_firestore.dart';

class VerifiedRestaurant {
  const VerifiedRestaurant({
    required this.id,
    required this.name,
    required this.branchName,
    required this.address,
    required this.category,
    required this.imageUrl,
    required this.latitude,
    required this.longitude,
    required this.deliveryRadiusKm,
    required this.deliveryFee,
    required this.menu,
  });

  final String id;
  final String name;
  final String branchName;
  final String address;
  final String category;
  final String imageUrl;
  final double latitude;
  final double longitude;
  final double deliveryRadiusKm;
  final double deliveryFee;
  final List<VerifiedMenuItem> menu;

  bool get hasVerifiedCatalogData =>
      name.trim().isNotEmpty &&
      branchName.trim().isNotEmpty &&
      address.trim().isNotEmpty &&
      category.trim().isNotEmpty &&
      imageUrl.trim().isNotEmpty &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180 &&
      deliveryRadiusKm > 0 &&
      deliveryFee >= 0 &&
      menu.isNotEmpty &&
      menu.every(
        (item) =>
            item.id.trim().isNotEmpty &&
            item.name.trim().isNotEmpty &&
            item.description.trim().isNotEmpty &&
            item.category.trim().isNotEmpty &&
            item.price > 0 &&
            item.imageUrl.trim().isNotEmpty,
      );

  factory VerifiedRestaurant.fromMap(Map<String, dynamic> data) {
    final rawMenu = data['menu'];
    return VerifiedRestaurant(
      id: data['id'] as String? ?? '',
      name: data['name'] as String? ?? '',
      branchName:
          data['branchName'] as String? ?? data['branch_name'] as String? ?? '',
      address: data['address'] as String? ?? '',
      category: data['category'] as String? ?? 'Restaurant',
      imageUrl:
          data['imageUrl'] as String? ?? data['image_url'] as String? ?? '',
      latitude: (data['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (data['longitude'] as num?)?.toDouble() ?? 0,
      deliveryRadiusKm:
          (data['deliveryRadiusKm'] as num? ??
                  data['delivery_radius_km'] as num?)
              ?.toDouble() ??
          0,
      deliveryFee:
          (data['deliveryFee'] as num? ?? data['delivery_fee'] as num?)
              ?.toDouble() ??
          0,
      menu: rawMenu is List
          ? rawMenu
                .whereType<Map>()
                .map(
                  (row) => VerifiedMenuItem(
                    id: row['id'] as String? ?? '',
                    name: row['name'] as String? ?? '',
                    description: row['description'] as String? ?? '',
                    category: row['category'] as String? ?? '',
                    price: (row['price'] as num?)?.toDouble() ?? 0,
                    imageUrl: row['imageUrl'] as String? ?? '',
                  ),
                )
                .toList(growable: false)
          : const [],
    );
  }
}

class VerifiedMenuItem {
  const VerifiedMenuItem({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.price,
    required this.imageUrl,
  });
  final String id;
  final String name;
  final String description;
  final String category;
  final double price;
  final String imageUrl;
}

class RestaurantService {
  RestaurantService({FirebaseFirestore? firestore})
    : _configuredFirestore = firestore;
  final FirebaseFirestore? _configuredFirestore;
  FirebaseFirestore get _firestore =>
      _configuredFirestore ?? FirebaseFirestore.instance;

  Stream<List<VerifiedRestaurant>> watchVerifiedRestaurants() => _firestore
      .collection('restaurants')
      .where('verified', isEqualTo: true)
      .where('active', isEqualTo: true)
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .map(
              (document) => VerifiedRestaurant.fromMap({
                ...document.data(),
                'id': document.id,
              }),
            )
            .where((restaurant) => restaurant.hasVerifiedCatalogData)
            .toList(growable: false),
      );
}
