import 'package:firebase_auth/firebase_auth.dart';

class AuthUser {
  const AuthUser({
    required this.uid,
    required this.email,
    required this.emailVerified,
    required this.displayName,
  });

  final String uid;
  final String email;
  final bool emailVerified;
  final String displayName;
}

abstract interface class AuthService {
  AuthUser? get currentUser;
  Stream<AuthUser?> get authStateChanges;

  Future<AuthUser> register(String email, String password, String displayName);
  Future<AuthUser> signIn(String email, String password);
  Future<AuthUser> updateDisplayName(String displayName);
  Future<void> signOut();
  Future<void> sendVerificationEmail();
  Future<AuthUser> reloadCurrentUser();
  Future<void> sendPasswordResetEmail(String email);
}

class FirebaseAuthService implements AuthService {
  FirebaseAuth get _auth => FirebaseAuth.instance;

  AuthUser? _mapUser(User? user) {
    if (user == null) return null;
    return AuthUser(
      uid: user.uid,
      email: user.email ?? '',
      emailVerified: user.emailVerified,
      displayName: user.displayName ?? '',
    );
  }

  @override
  AuthUser? get currentUser => _mapUser(_auth.currentUser);

  @override
  Stream<AuthUser?> get authStateChanges =>
      _auth.authStateChanges().map(_mapUser);

  @override
  Future<AuthUser> register(
    String email,
    String password,
    String displayName,
  ) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = credential.user;
      if (user == null) {
        throw const AuthFailure('Account creation did not return a user.');
      }
      await user.updateDisplayName(displayName.trim());
      await user.reload();
      return _mapUser(_auth.currentUser)!;
    } on FirebaseAuthException catch (error) {
      throw AuthFailure(_authMessage(error));
    }
  }

  @override
  Future<AuthUser> updateDisplayName(String displayName) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw const AuthFailure('Please sign in again to update your profile.');
      }
      await user.updateDisplayName(displayName.trim());
      await user.reload();
      return _mapUser(_auth.currentUser)!;
    } on FirebaseAuthException catch (error) {
      throw AuthFailure(_authMessage(error));
    }
  }

  @override
  Future<AuthUser> signIn(String email, String password) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = credential.user;
      if (user == null) {
        throw const AuthFailure('Sign-in did not return a user.');
      }
      await user.reload();
      return _mapUser(_auth.currentUser)!;
    } on FirebaseAuthException catch (error) {
      throw AuthFailure(_authMessage(error));
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } on FirebaseAuthException catch (error) {
      throw AuthFailure(_authMessage(error));
    }
  }

  @override
  Future<void> sendVerificationEmail() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw const AuthFailure('Please sign in again to verify your email.');
      }
      await user.sendEmailVerification();
    } on FirebaseAuthException catch (error) {
      throw AuthFailure(_authMessage(error));
    }
  }

  @override
  Future<AuthUser> reloadCurrentUser() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw const AuthFailure('Your session ended. Please sign in again.');
      }
      await user.reload();
      final refreshedUser = _auth.currentUser;
      if (refreshedUser == null) {
        throw const AuthFailure('Your session ended. Please sign in again.');
      }
      return _mapUser(refreshedUser)!;
    } on FirebaseAuthException catch (error) {
      throw AuthFailure(_authMessage(error));
    }
  }

  @override
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (error) {
      throw AuthFailure(_authMessage(error));
    }
  }

  String _authMessage(FirebaseAuthException error) {
    final code = error.code.split('/').last.toLowerCase();
    switch (code) {
      case 'email-already-in-use':
        return 'An account already uses this email. Try signing in.';
      case 'invalid-credential':
      case 'invalid-login-credentials':
      case 'wrong-password':
      case 'user-not-found':
        return 'The email or password is incorrect.';
      case 'weak-password':
        return 'Choose a password with at least 6 characters.';
      case 'invalid-email':
        return 'Enter a valid email address.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait and try again.';
      case 'network-request-failed':
        return 'Could not connect. Check your internet connection.';
      case 'operation-not-allowed':
      case 'configuration-not-found':
        return 'Email/password sign-in is not enabled in Firebase.';
      case 'invalid-api-key':
      case 'api-key-not-valid':
        return 'Firebase rejected this app’s API key. Check lib/firebase_options.dart against the Firebase Web app configuration.';
      case 'app-not-authorized':
      case 'unauthorized-domain':
        return 'This app domain is not authorized for Firebase Authentication. Add the current hostname under Firebase Console → Authentication → Settings → Authorized domains.';
      case 'user-disabled':
        return 'This account has been disabled. Contact the app administrator.';
      case 'requires-recent-login':
        return 'Please sign out and sign in again, then retry this change.';
      case 'quota-exceeded':
        return 'Firebase Authentication has reached a usage limit. Try again later.';
      default:
        final safeCode = code.replaceAll(RegExp(r'[^a-z0-9_-]'), '').trim();
        final codePrefix = safeCode.length > 64
            ? safeCode.substring(0, 64)
            : safeCode;
        return codePrefix.isEmpty
            ? 'Firebase returned an authentication error without a code. Rebuild or refresh the app, then check Firebase Authentication configuration.'
            : 'Firebase Authentication error ($codePrefix). Check Firebase Authentication settings and share this code if the problem continues.';
    }
  }
}

class AuthFailure implements Exception {
  const AuthFailure(this.message);
  final String message;

  @override
  String toString() => message;
}
