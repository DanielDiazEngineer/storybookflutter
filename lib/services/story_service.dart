// lib/services/story_service.dart
// Phase 2: loads stories from bundled JSON assets.
// Phase 4: this class gets a second implementation that hits Firestore.
//           HomeScreen and StoryScreen never need to change — they always
//           talk to StoryService, not to the data source directly.

import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/story.dart';

class StoryService {
  // ── Catalog ───────────────────────────────────────────────────────────────
  // Returns lightweight metadata for all stories — used to render
  // the home screen library. Fast: one small JSON file.

  Future<List<StoryMeta>> loadCatalog() async {
    final raw = await rootBundle.loadString('assets/catalog.json');
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final list = json['stories'] as List;
    return list
        .map((item) => StoryMeta.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  // ── Full story ────────────────────────────────────────────────────────────
  // Loads page data for one story. Called when the user taps a card.
  // Merges with StoryMeta so the Story object is self-contained.

  Future<Story> loadStory(StoryMeta meta) async {
    final path = 'assets/stories/${meta.id}/story.json';
    final raw = await rootBundle.loadString(path);
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return Story.fromJson(json, meta);
  }
}
