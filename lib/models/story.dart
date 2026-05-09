// lib/models/story.dart
// Phase 1.5: adds multi-language support to the data model.
// Images are language-agnostic. Text + audio are per language code (e.g. 'en', 'es').
// Phase 3+: audioPath will become a Cloudflare R2 URL instead of an asset path.

// ── Localized text + audio for one page in one language ──────────────────────

class LocalizedContent {
  final String text;
  final String audioPath;

  const LocalizedContent({
    required this.text,
    required this.audioPath,
  });
}

// ── One page of a story ───────────────────────────────────────────────────────

class StoryPage {
  final String imagePath;                       // shared across all languages
  final Map<String, LocalizedContent> content;  // 'en' → {text, audioPath}

  const StoryPage({
    required this.imagePath,
    required this.content,
  });

  /// Returns content for [langCode], falls back to English if not found.
  LocalizedContent localized(String langCode) =>
      content[langCode] ?? content['en']!;
}

// ── A full story ──────────────────────────────────────────────────────────────

class Story {
  final String id;
  final Map<String, String> title;    // {'en': 'The Bunny Adventure', 'es': '...'}
  final String coverPath;
  final List<String> availableLanguages;
  final int ageMin;
  final int ageMax;
  final bool isFree;
  final List<StoryPage> pages;

  const Story({
    required this.id,
    required this.title,
    required this.coverPath,
    required this.availableLanguages,
    required this.ageMin,
    required this.ageMax,
    required this.isFree,
    required this.pages,
  });

  /// Convenience getter so you can do story.localizedTitle('en')
  String localizedTitle(String langCode) =>
      title[langCode] ?? title['en']!;
}

// ── Bundled free story (hardcoded for Phase 1 / 1.5) ─────────────────────────
// Audio files go in:
//   assets/stories/bunny_adventure/en/audio/page_01.mp3
//   assets/stories/bunny_adventure/es/audio/page_01.mp3
// Images go in:
//   assets/stories/bunny_adventure/pages/page_01.jpg

const Story bundledStory = Story(
  id: 'bunny_adventure',
  title: {
    'en': 'The Bunny Adventure',
    'es': 'La Aventura del Conejito',
  },
  coverPath: 'assets/stories/bunny_adventure/cover.jpg',
  availableLanguages: ['en', 'es'],
  ageMin: 3,
  ageMax: 7,
  isFree: true,
  pages: [
    StoryPage(
      imagePath: 'assets/stories/bunny_adventure/pages/page_01.jpg',
      content: {
        'en': LocalizedContent(
          text: 'Once upon a time, a little bunny named Pip lived in a cozy burrow under an old oak tree.',
          audioPath: 'assets/stories/bunny_adventure/en/audio/page_01.mp3',
        ),
        'es': LocalizedContent(
          text: 'Había una vez un conejito llamado Pip que vivía en una acogedora madriguera bajo un viejo roble.',
          audioPath: 'assets/stories/bunny_adventure/es/audio/page_01.mp3',
        ),
      },
    ),
    StoryPage(
      imagePath: 'assets/stories/bunny_adventure/pages/page_02.jpg',
      content: {
        'en': LocalizedContent(
          text: 'One morning, Pip found a bright red door at the edge of the meadow that had never been there before.',
          audioPath: 'assets/stories/bunny_adventure/en/audio/page_02.mp3',
        ),
        'es': LocalizedContent(
          text: 'Una mañana, Pip encontró una puerta roja brillante al borde del prado que nunca antes había estado allí.',
          audioPath: 'assets/stories/bunny_adventure/es/audio/page_02.mp3',
        ),
      },
    ),
    StoryPage(
      imagePath: 'assets/stories/bunny_adventure/pages/page_03.jpg',
      content: {
        'en': LocalizedContent(
          text: 'Pip took a deep breath, turned the golden handle, and stepped into the most wonderful adventure of her life!',
          audioPath: 'assets/stories/bunny_adventure/en/audio/page_03.mp3',
        ),
        'es': LocalizedContent(
          text: '¡Pip respiró hondo, giró el picaporte dorado y entró en la aventura más maravillosa de su vida!',
          audioPath: 'assets/stories/bunny_adventure/es/audio/page_03.mp3',
        ),
      },
    ),
  ],
);
