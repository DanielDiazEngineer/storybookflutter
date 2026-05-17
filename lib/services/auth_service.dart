// lib/services/auth_service.dart
//
// Anonymous-first auth. Every app launch ensures there's a signed-in
// user; if none exists, we create an anonymous one. The UID is stable
// across launches (FirebaseAuth caches the token locally) and survives
// app updates. It's lost on uninstall or "clear data" — acceptable for
// anonymous users since they haven't committed any cloud data yet.
//
// On first-launch-with-no-network, anonymous sign-in fails. We swallow
// the error so the app still opens — the user can read bundled content,
// and we'll retry the sign-in on the next progress write attempt.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authState => _auth.authStateChanges();

  /// Returns the current user, signing in anonymously if needed.
  /// Returns null only if we're offline on a first-ever launch.
  Future<User?> ensureSignedIn() async {
    final existing = _auth.currentUser;
    if (existing != null) {
      debugPrint('Auth: existing user ${existing.uid} '
          '(anon: ${existing.isAnonymous})');
      return existing;
    }
    try {
      final credential = await _auth.signInAnonymously();
      debugPrint('Auth: signed in anonymously as ${credential.user!.uid}');
      return credential.user;
    } catch (e) {
      debugPrint('Auth: anonymous sign-in failed: $e');
      return null;
    }
  }
}
