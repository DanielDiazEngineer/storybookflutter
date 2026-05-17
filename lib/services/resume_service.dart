// lib/services/resume_service.dart
//
// Tracks where the reader left off in each story. Backed by Firestore
// at /users/{uid}/progress/{storyId}. Public interface unchanged from
// the SharedPreferences-backed Phase 3 version, so screens consume it
// identically.
//
// Doc shape:
//   lastPage: int
//   langCode: 'en' | 'es'
//   lastReadAt: serverTimestamp
//   completed: bool
//   completedAt: serverTimestamp?   (only when completed == true)
//
// Finishing a story sets completed=true rather than deleting the doc.
// The progress data persists for later features (completion badges,
// reading-history view). The "continue" card filters completed out.
//
// Firestore offline persistence is on by default — reads and writes
// work offline and sync when connectivity returns.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class ResumeState {
  final String storyId;
  final int pageIndex;
  final String langCode;
  final DateTime updatedAt;

  const ResumeState({
    required this.storyId,
    required this.pageIndex,
    required this.langCode,
    required this.updatedAt,
  });
}

class ResumeService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>>? _progressCollection() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return _db.collection('users').doc(user.uid).collection('progress');
  }

  Future<void> savePosition({
    required String storyId,
    required int pageIndex,
    required String langCode,
  }) async {
    final col = _progressCollection();
    if (col == null) return;
    try {
      await col.doc(storyId).set({
        'lastPage': pageIndex,
        'langCode': langCode,
        'lastReadAt': FieldValue.serverTimestamp(),
        'completed': false,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('ResumeService: savePosition failed: $e');
    }
  }

  /// The most recently read, not-yet-completed story.
  Future<ResumeState?> getMostRecent() async {
    final col = _progressCollection();
    if (col == null) return null;
    try {
      final snap = await col
          .where('completed', isEqualTo: false)
          .orderBy('lastReadAt', descending: true)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return null;
      return _docToState(snap.docs.first);
    } catch (e) {
      debugPrint('ResumeService: getMostRecent failed: $e');
      return null;
    }
  }

  /// Progress for a specific story. Returns null for completed stories so
  /// the reader starts fresh next time.
  Future<ResumeState?> getForStory(String storyId) async {
    final col = _progressCollection();
    if (col == null) return null;
    try {
      final doc = await col.doc(storyId).get();
      if (!doc.exists) return null;
      final data = doc.data();
      if (data == null || data['completed'] == true) return null;
      return _docToState(doc);
    } catch (e) {
      debugPrint('ResumeService: getForStory failed: $e');
      return null;
    }
  }

  ResumeState? _docToState(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) return null;
    final page = data['lastPage'] as int?;
    final lang = data['langCode'] as String?;
    final ts = (data['lastReadAt'] as Timestamp?)?.toDate();
    if (page == null || lang == null || ts == null) return null;
    return ResumeState(
      storyId: doc.id,
      pageIndex: page,
      langCode: lang,
      updatedAt: ts,
    );
  }

  /// Called when the user finishes a story. Marks completed=true; the doc
  /// stays for badges/history. The "continue" card excludes completed
  /// docs via the query in [getMostRecent].
  Future<void> clearForStory(String storyId) async {
    final col = _progressCollection();
    if (col == null) return;
    try {
      await col.doc(storyId).set({
        'completed': true,
        'completedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('ResumeService: clearForStory failed: $e');
    }
  }
}
