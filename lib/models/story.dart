// lib/models/story.dart

// Phase 1.5: adds multi-language support to the data model.
// Images are language-agnostic. Text + audio are per language code (e.g. 'en', 'es').
// Phase 3+: audioPath will become a Cloudflare R2 URL instead of an asset path.

// ── Localized text + audio

// Phase 2: adds fromJson constructors so stories load from JSON assets.
// Phase 4: same models, but StoryService will feed them from Firestore instead.

class LocalizedContent {
  final String text;
  final String audioPath;

  const LocalizedContent({required this.text, required this.audioPath});

  factory LocalizedContent.fromJson(Map<String, dynamic> json) {
    return LocalizedContent(
      text: json['text'] as String,
      audioPath: json['audioPath'] as String,
    );
  }
}

class StoryPage {
  final String imagePath;
  final Map<String, LocalizedContent> content;

  const StoryPage({required this.imagePath, required this.content});

  LocalizedContent localized(String langCode) =>
      content[langCode] ?? content['en']!;

  factory StoryPage.fromJson(Map<String, dynamic> json) {
    final rawContent = json['content'] as Map<String, dynamic>;
    return StoryPage(
      imagePath: json['imagePath'] as String,
      content: rawContent.map(
        (lang, value) => MapEntry(
          lang,
          LocalizedContent.fromJson(value as Map<String, dynamic>),
        ),
      ),
    );
  }
}

// Lightweight metadata — used on the home screen library grid.
// Loaded from catalog.json. No page data here.
class StoryMeta {
  final String id;
  final Map<String, String> title;
  final String coverPath;
  final List<String> availableLanguages;
  final int ageMin;
  final int ageMax;
  final bool isFree;
  final bool isBundled; // ← NEW
  final List<String> tags;
  final String? series;

  const StoryMeta({
    required this.id,
    required this.title,
    required this.coverPath,
    required this.availableLanguages,
    required this.ageMin,
    required this.ageMax,
    required this.isFree,
    required this.isBundled,
    required this.tags,
    this.series,
  });

  String localizedTitle(String langCode) => title[langCode] ?? title['en']!;

  factory StoryMeta.fromJson(Map<String, dynamic> json) {
    return StoryMeta(
      id: json['id'] as String,
      title: Map<String, String>.from(json['title'] as Map),
      coverPath: json['coverPath'] as String,
      availableLanguages: List<String>.from(json['availableLanguages'] as List),
      ageMin: json['ageMin'] as int,
      ageMax: json['ageMax'] as int,
      isFree: json['isFree'] as bool,
      isBundled: json['isBundled'] as bool? ?? false,
      tags: List<String>.from(json['tags'] as List),
      series: json['series'] as String?,
    );
  }
}

// Full story with pages — loaded from assets/stories/{id}/story.json
// when the user taps a story card.
class Story {
  final String id;
  final List<StoryPage> pages;
  final StoryMeta meta;

  const Story({required this.id, required this.pages, required this.meta});

  String localizedTitle(String langCode) => meta.localizedTitle(langCode);

  factory Story.fromJson(Map<String, dynamic> json, StoryMeta meta) {
    return Story(
      id: json['id'] as String,
      pages: (json['pages'] as List)
          .map((p) => StoryPage.fromJson(p as Map<String, dynamic>))
          .toList(),
      meta: meta,
    );
  }
}
