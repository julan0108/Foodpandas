import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../services/location_service.dart';

Future<DeliveryLocation?> showDeliveryLocationPicker(
  BuildContext context, {
  required DeliveryLocation initialLocation,
}) => showDialog<DeliveryLocation>(
  context: context,
  builder: (_) => _DeliveryLocationDialog(initialLocation: initialLocation),
);

class _DeliveryLocationDialog extends StatefulWidget {
  const _DeliveryLocationDialog({required this.initialLocation});
  final DeliveryLocation initialLocation;

  @override
  State<_DeliveryLocationDialog> createState() =>
      _DeliveryLocationDialogState();
}

class _DeliveryLocationDialogState extends State<_DeliveryLocationDialog> {
  late LatLng _selected;

  @override
  void initState() {
    super.initState();
    _selected = LatLng(
      widget.initialLocation.latitude,
      widget.initialLocation.longitude,
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Choose delivery pin'),
    content: SizedBox(
      width: 650,
      height: 420,
      child: Column(
        children: [
          const Text(
            'Tap the map to place the pin. Enter the street address in the checkout field.',
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: _selected,
                  zoom: 16,
                ),
                myLocationEnabled: true,
                myLocationButtonEnabled: true,
                markers: {
                  Marker(
                    markerId: const MarkerId('delivery'),
                    position: _selected,
                  ),
                },
                onTap: (point) => setState(() => _selected = point),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Pin: ${_selected.latitude.toStringAsFixed(5)}, ${_selected.longitude.toStringAsFixed(5)}',
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(
          context,
          DeliveryLocation(
            latitude: _selected.latitude,
            longitude: _selected.longitude,
          ),
        ),
        child: const Text('Use this location'),
      ),
    ],
  );
}
