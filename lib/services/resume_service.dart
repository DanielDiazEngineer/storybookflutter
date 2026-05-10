// lib/services/resume_service.dart
//
// Tracks where the reader left off in each story, so the home screen
// can surface a "Continue" hero card and re-entering a story can offer
// to resume vs. start over.
//
// Storage shape (shared_preferences):
//   resume.lastStoryId  → String?           — most recently read story
//   resume.{storyId}.page → int             — last page index in that story
//   resume.{storyId}.lang → String          — language used last time
//   resume.{storyId}.ts   → int (epoch ms)  — when it was saved
//
// Kept deliberately tiny: this is hot-path data, not analytics.

import 'package:shared_preferences/shared_preferences.dart';

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
  static const _kLastStoryId = 'resume.lastStoryId';
  static String _kPage(String id) => 'resume.$id.page';
  static String _kLang(String id) => 'resume.$id.lang';
  static String _kTs(String id) => 'resume.$id.ts';

  Future<void> savePosition({
    required String storyId,
    required int pageIndex,
    required String langCode,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastStoryId, storyId);
    await prefs.setInt(_kPage(storyId), pageIndex);
    await prefs.setString(_kLang(storyId), langCode);
    await prefs.setInt(_kTs(storyId), DateTime.now().millisecondsSinceEpoch);
  }

  Future<ResumeState?> getMostRecent() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_kLastStoryId);
    if (id == null) return null;
    return _read(prefs, id);
  }

  Future<ResumeState?> getForStory(String storyId) async {
    final prefs = await SharedPreferences.getInstance();
    return _read(prefs, storyId);
  }

  ResumeState? _read(SharedPreferences prefs, String storyId) {
    final page = prefs.getInt(_kPage(storyId));
    final lang = prefs.getString(_kLang(storyId));
    final ts = prefs.getInt(_kTs(storyId));
    if (page == null || lang == null || ts == null) return null;
    return ResumeState(
      storyId: storyId,
      pageIndex: page,
      langCode: lang,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(ts),
    );
  }

  /// Called when the reader reaches the last page or the user explicitly
  /// finishes a story — clears the resume marker for that story.
  Future<void> clearForStory(String storyId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPage(storyId));
    await prefs.remove(_kLang(storyId));
    await prefs.remove(_kTs(storyId));
    if (prefs.getString(_kLastStoryId) == storyId) {
      await prefs.remove(_kLastStoryId);
    }
  }
}
