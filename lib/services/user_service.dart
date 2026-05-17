// lib/services/user_service.dart
//
// Owns /users/{uid}. Idempotent — ensureProfileExists() is safe to call
// on every launch. Writes only happen when the doc is missing.
//
// Defaults are intentional: anonymous users get a usable profile from
// day one so the rest of the app can read .preferredLanguage etc.
// without null-checking. When they later upgrade via linkWithCredential
// (Step 5), we'll flip isAnonymous → false and let them set displayName.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/user_profile.dart';

class UserService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _docFor(String uid) =>
      _db.collection('users').doc(uid);

  /// Reads the current user's profile doc; creates a default one if missing.
  /// No-ops if no user is signed in (offline first launch).
  Future<UserProfile?> ensureProfileExists() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint('UserService: no signed-in user; skipping profile init');
      return null;
    }

    final ref = _docFor(user.uid);
    try {
      final snap = await ref.get();
      if (snap.exists) {
        debugPrint('UserService: profile exists for ${user.uid}');
        return UserProfile.fromFirestore(snap);
      }

      final profile = UserProfile(
        uid: user.uid,
        displayName: null,
        createdAt: DateTime.now(),
        isAnonymous: user.isAnonymous,
        preferredLanguage: 'en',
        narrationEnabled: true,
        favoriteStoryIds: const [],
      );
      await ref.set(profile.toFirestore());
      debugPrint('UserService: created profile for ${user.uid}');
      return profile;
    } catch (e) {
      debugPrint('UserService: profile init failed: $e');
      return null;
    }
  }

  Future<UserProfile?> getProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    final snap = await _docFor(user.uid).get();
    if (!snap.exists) return null;
    return UserProfile.fromFirestore(snap);
  }

  Future<void> updateLanguage(String langCode) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await _docFor(user.uid).update({'preferredLanguage': langCode});
  }

  Future<void> updateNarrationEnabled(bool enabled) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await _docFor(user.uid).update({'narrationEnabled': enabled});
  }
}
