// Data model for a single page of a story.
// Phase 1: everything hardcoded here.
// Phase 3+: this will be loaded from Firestore + R2 URLs.

class StoryPage {
  final String imagePath;   // asset path for the image
  final String audioPath;   // asset path for narration MP3
  final String text;        // the text shown on screen

  const StoryPage({
    required this.imagePath,
    required this.audioPath,
    required this.text,
  });
}

class Story {
  final String id;
  final String title;
  final String coverPath;
  final List<StoryPage> pages;

  const Story({
    required this.id,
    required this.title,
    required this.coverPath,
    required this.pages,
  });
}

// ── Hardcoded story data ──────────────────────────────────────────────────────
// Replace image/audio paths once you add real assets.
// Replace text with your actual story copy.

const Story bundledStory = Story(
  id: 'bunny_adventure',
  title: 'The Bunny Adventure',
  coverPath: 'assets/stories/bunny_adventure/cover.jpg',
  pages: [
    StoryPage(
      imagePath: 'assets/stories/bunny_adventure/pages/page_01.jpg',
      audioPath: 'assets/stories/bunny_adventure/audio/page_01.mp3',
      text: 'Once upon a time, a little bunny named Pip lived in a cozy burrow under an old oak tree.',
    ),
    StoryPage(
      imagePath: 'assets/stories/bunny_adventure/pages/page_02.jpg',
      audioPath: 'assets/stories/bunny_adventure/audio/page_02.mp3',
      text: 'One morning, Pip found a bright red door at the edge of the meadow that had never been there before.',
    ),
    StoryPage(
      imagePath: 'assets/stories/bunny_adventure/pages/page_03.jpg',
      audioPath: 'assets/stories/bunny_adventure/audio/page_03.mp3',
      text: 'Pip took a deep breath, turned the golden handle, and stepped into the most wonderful adventure of her life!',
    ),
  ],
);