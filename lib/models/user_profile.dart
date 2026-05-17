// lib/models/user_profile.dart
//
// Account-level profile stored at /users/{uid} in Firestore.
// Reading progress lives in a subcollection — not on this doc — so the
// profile stays small and reads stay cheap.

import 'package:cloud_firestore/cloud_firestore.dart';

class UserProfile {
  final String uid;
  final String? displayName;
  final DateTime createdAt;
  final bool isAnonymous;
  final String preferredLanguage; // 'en' | 'es'
  final bool narrationEnabled;
  final List<String> favoriteStoryIds;

  const UserProfile({
    required this.uid,
    required this.displayName,
    required this.createdAt,
    required this.isAnonymous,
    required this.preferredLanguage,
    required this.narrationEnabled,
    required this.favoriteStoryIds,
  });

  factory UserProfile.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserProfile(
      uid: doc.id,
      displayName: data['displayName'] as String?,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      isAnonymous: data['isAnonymous'] as bool? ?? true,
      preferredLanguage: data['preferredLanguage'] as String? ?? 'en',
      narrationEnabled: data['narrationEnabled'] as bool? ?? true,
      favoriteStoryIds:
          List<String>.from(data['favoriteStoryIds'] as List? ?? const []),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'displayName': displayName,
        'createdAt': Timestamp.fromDate(createdAt),
        'isAnonymous': isAnonymous,
        'preferredLanguage': preferredLanguage,
        'narrationEnabled': narrationEnabled,
        'favoriteStoryIds': favoriteStoryIds,
      };
}
