import 'package:flutter/material.dart';

import '../services/restaurant_service.dart';

class RestaurantDirectoryPage extends StatefulWidget {
  const RestaurantDirectoryPage({
    super.key,
    this.restaurantService,
    this.onOpenRestaurant,
  });
  final RestaurantService? restaurantService;
  final ValueChanged<VerifiedRestaurant>? onOpenRestaurant;

  @override
  State<RestaurantDirectoryPage> createState() =>
      _RestaurantDirectoryPageState();
}

class _RestaurantDirectoryPageState extends State<RestaurantDirectoryPage> {
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    key: const Key('restaurants-page'),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 32, 22, 50),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Restaurants',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF30251E),
                ),
              ),
              const Text(
                'Browse verified branches. Enter your complete delivery address at checkout; delivery availability is checked against each branch’s verified service areas.',
              ),
              const SizedBox(height: 16),
              if (widget.restaurantService == null)
                const Text(
                  'Firebase must be configured to load verified restaurant branches.',
                )
              else
                StreamBuilder<List<VerifiedRestaurant>>(
                  stream: widget.restaurantService!.watchVerifiedRestaurants(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return const Text(
                        'Could not load restaurant availability. Check your Firebase connection.',
                      );
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.data!.isEmpty) {
                      return const Text(
                        'No verified restaurants are available yet. Listings appear after their branch and menu are verified in Firebase.',
                      );
                    }
                    return Column(
                      children: snapshot.data!.map(_restaurantCard).toList(),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _restaurantCard(VerifiedRestaurant restaurant) => Card(
    color: Colors.white,
    margin: const EdgeInsets.only(bottom: 14),
    child: ExpansionTile(
      leading: restaurant.imageUrl.isEmpty
          ? const Icon(Icons.restaurant_outlined)
          : ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                restaurant.imageUrl,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    const Icon(Icons.restaurant_outlined),
              ),
            ),
      title: Text(
        restaurant.name,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(
        '${restaurant.branchName} • ${restaurant.address} • ${restaurant.category} • ₱${restaurant.deliveryFee.toStringAsFixed(2)} delivery',
      ),
      childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
      children: [
        if (widget.onOpenRestaurant != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => widget.onOpenRestaurant!(restaurant),
              icon: const Icon(Icons.restaurant_menu_outlined),
              label: const Text('Browse this menu'),
            ),
          ),
        ...restaurant.menu.map(
          (item) => ListTile(
            contentPadding: EdgeInsets.zero,
            leading: item.imageUrl.isEmpty
                ? const Icon(Icons.restaurant_menu_outlined)
                : ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      item.imageUrl,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          const Icon(Icons.restaurant_menu_outlined),
                    ),
                  ),
            title: Text(item.name),
            subtitle: Text('${item.category} • ${item.description}'),
            trailing: Text('₱${item.price.toStringAsFixed(2)}'),
          ),
        ),
      ],
    ),
  );
}
