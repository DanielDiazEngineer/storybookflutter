
install flutter vscode extension ,  auto download sdk, set path, restart IDE
flutter pub get
flutter run -d chrome


switched just_audio: ^0.9.40      # audio playback
in favor of chrome testable.


Adding a second story from now on is purely a content job — zero Dart:

Drop folder assets/stories/sleepy_dragon/ with images, audio
Write story.json with pages (copy bunny's as a template)
Add one entry to catalog.json
Add 5 lines to pubspec.yaml


TODO temporary delay..


Future<List<StoryMeta>> loadCatalog() async {
  await Future.delayed(const Duration(seconds: 2)); // ← remove before shipping
  final raw = await rootBundle.loadString('assets/catalog.json');
  ...
}