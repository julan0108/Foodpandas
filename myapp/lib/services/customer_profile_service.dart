import 'package:cloud_firestore/cloud_firestore.dart';

class CustomerProfile {
  const CustomerProfile({
    required this.email,
    required this.displayName,
    required this.phone,
    required this.deliveryAddress,
  });

  final String email;
  final String displayName;
  final String phone;
  final String deliveryAddress;
}

abstract interface class CustomerProfileService {
  Future<CustomerProfile?> getProfile(String uid);
  Future<void> saveProfile(String uid, CustomerProfile profile);
}

class FirebaseCustomerProfileService implements CustomerProfileService {
  FirebaseCustomerProfileService({FirebaseFirestore? firestore})
    : _configuredFirestore = firestore;

  final FirebaseFirestore? _configuredFirestore;
  FirebaseFirestore get _firestore =>
      _configuredFirestore ?? FirebaseFirestore.instance;

  @override
  Future<CustomerProfile?> getProfile(String uid) async {
    try {
      final snapshot = await _firestore.collection('users').doc(uid).get();
      final row = snapshot.data();
      if (row == null) return null;
      return CustomerProfile(
        email: _stringField(row, 'email'),
        displayName: _stringField(row, 'displayName'),
        phone: _stringField(row, 'phone'),
        deliveryAddress: _stringField(row, 'deliveryAddress'),
      );
    } on FirebaseException catch (error) {
      throw CustomerProfileFailure(
        'Could not load your Firebase profile (${error.code}): ${error.message ?? 'database request failed'}.',
      );
    }
  }

  @override
  Future<void> saveProfile(String uid, CustomerProfile profile) async {
    try {
      await _firestore.collection('users').doc(uid).set({
        'email': profile.email,
        'displayName': profile.displayName,
        'phone': profile.phone,
        'deliveryAddress': profile.deliveryAddress,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } on FirebaseException catch (error) {
      throw CustomerProfileFailure(
        'Could not save your Firebase profile (${error.code}): ${error.message ?? 'database request failed'}.',
      );
    }
  }

  String _stringField(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value is! String) {
      throw CustomerProfileFailure(
        'Your Firebase profile has an invalid "$key" field.',
      );
    }
    return value;
  }
}

class CustomerProfileFailure implements Exception {
  const CustomerProfileFailure(this.message);

  final String message;

  @override
  String toString() => message;
}
