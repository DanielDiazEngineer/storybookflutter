
install flutter vscode extension ,  auto download sdk, set path, restart IDE
flutter pub get
flutter run -d chrome
(while running on terminal)
r reload
R restart
q quit


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




Editing a typo in bunny2 page text: you also need to touch the catalog (e.g., add a lastUpdated field, or even just a trailing space/key reorder — anything that changes the bytes) so the diff fires. This is the one author-discipline cost. 

Re-recording bunny2 page 2 audio: upload page_02_v2.mp3, update story.json to reference the new path, touch the catalog. Old audio orphaned in cache, new audio fetched cleanly. 
