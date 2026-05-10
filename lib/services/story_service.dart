// lib/services/story_service.dart
//
// Phase 3: stories stream from Cloudflare R2 on demand.
//          The catalog ships with the app. The bundled "free" story works
//          offline as a fallback. Everything else lives on R2.
// Phase 4: a second StoryService implementation will hit Firestore for the
//          catalog. The screen layer never changes — it always talks to
//          this class.

import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/story.dart';

class StoryService {
  late final String _r2BaseUrl = _readBaseUrl();
  List<StoryMeta>? _catalogCache;

  static String _readBaseUrl() {
    final raw = dotenv.maybeGet('R2_BASE_URL') ?? '';
    if (raw.isEmpty) {
      throw StateError(
        'R2_BASE_URL is not set. Make sure .env exists at the project '
        'root, is listed under flutter.assets in pubspec.yaml, and that '
        'main() calls dotenv.load() before runApp().',
      );
    }
    return raw.replaceAll(RegExp(r'/$'), '');
  }

  // ── Catalog ───────────────────────────────────────────────────────────────
  // Loads from bundled assets. Small, fast, always available.

  Future<List<StoryMeta>> loadCatalog() async {
    if (_catalogCache != null) return _catalogCache!;

    final raw = await rootBundle.loadString('assets/catalog.json');
    final json = jsonDecode(raw) as Map<String, dynamic>;

    final list = json['stories'] as List;
    _catalogCache = list
        .map((item) => StoryMeta.fromJson(item as Map<String, dynamic>))
        .toList();
    return _catalogCache!;
  }

  // ── URL / asset path resolution ───────────────────────────────────────────
  // Relative paths in JSON ("stories/foo/page_01.jpg") become either
  // a full R2 URL or a bundled asset path.

  String resolveUrl(String relativePath) => '$_r2BaseUrl/$relativePath';
  String resolveAssetPath(String relativePath) => 'assets/$relativePath';

  // ── Story loading ─────────────────────────────────────────────────────────
  // Tries cache → network → bundled fallback.

  Future<Story> loadStory(StoryMeta meta) async {
    await loadCatalog(); // ensure _r2BaseUrl is populated

    // 1. Cached story.json on disk?
    final cached = await _readCachedStoryJson(meta.id);
    if (cached != null) {
      return Story.fromJson(cached, meta);
    }

    // 2. Try network
    Map<String, dynamic>? json;
    try {
      final url = resolveUrl('stories/${meta.id}/story.json');
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        json = jsonDecode(response.body) as Map<String, dynamic>;
        await _writeCachedStoryJson(meta.id, response.body);
      }
    } catch (_) {
      // Fall through to bundled fallback
    }

    // 3. Bundled fallback (only for stories marked isBundled)
    if (json == null && meta.isBundled) {
      final raw =
          await rootBundle.loadString('assets/stories/${meta.id}/story.json');
      json = jsonDecode(raw) as Map<String, dynamic>;
    }

    if (json == null) {
      throw Exception(
          'Could not load story "${meta.id}" — no network and not bundled.');
    }

    return Story.fromJson(json, meta);
  }

  // ── Prefetch ──────────────────────────────────────────────────────────────
  // Downloads all images + audio for a story+language. Yields progress 0..1.
  // Bundled stories skip the network entirely. Web platform skips the file
  // cache (browser HTTP cache handles it).

  Stream<double> prefetchStory(Story story, String langCode) async* {
    if (story.meta.isBundled) {
      // Bundled assets are already on disk via rootBundle. Nothing to fetch.
      yield 1.0;
      return;
    }

    if (kIsWeb) {
      // On web we let the browser cache handle it. No prefetch needed —
      // images load via CachedNetworkImage, audio plays via UrlSource.
      yield 1.0;
      return;
    }

    final assets = <String>[];
    for (final page in story.pages) {
      assets.add(page.imagePath);
      assets.add(page.localized(langCode).audioPath);
    }

    var done = 0;
    yield 0.0;

    // for (final relativePath in assets) {
    //   await _ensureCached(relativePath);
    //   done++;
    //   yield done / assets.length;
    // }

    //TODO remove the dont fail on audio not found yet

    for (final relativePath in assets) {
      try {
        await _ensureCached(relativePath);
      } catch (e) {
        // Tolerate missing audio during development.
        // Images are still required.
        final isAudio = relativePath.contains('/audio/');
        if (!isAudio) rethrow;
        //debugPrint('⚠️ Skipping missing audio: $relativePath ($e)');
      }
      done++;
      yield done / assets.length;
    }
  }

  // ── Audio path resolution for the player ──────────────────────────────────
  // Returns either a local file path (mobile, cached) or a URL (web).
  // Bundled audio uses AssetSource directly — caller checks meta.isBundled.

  Future<String> getAudioFilePath(String relativePath) async {
    if (kIsWeb) {
      // Web: no filesystem; caller should use UrlSource with this URL
      return resolveUrl(relativePath);
    }
    final file = await _ensureCached(relativePath);
    return file.path;
  }

  // ── File cache (mobile only) ──────────────────────────────────────────────

  Future<File> _cacheFileFor(String relativePath) async {
    if (kIsWeb) {
      throw UnsupportedError('File cache not available on web');
    }
    final dir = await getApplicationCacheDirectory();
    final hash = sha1.convert(utf8.encode(relativePath)).toString();
    final ext = p.extension(relativePath);
    return File(p.join(dir.path, 'r2', '$hash$ext'));
  }

  Future<bool> isCached(String relativePath) async {
    if (kIsWeb) return false;
    final f = await _cacheFileFor(relativePath);
    return f.existsSync();
  }

  Future<File> _ensureCached(String relativePath) async {
    final file = await _cacheFileFor(relativePath);
    if (file.existsSync()) return file;
    await file.parent.create(recursive: true);

    final url = resolveUrl(relativePath);
    final response =
        await http.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch $url (HTTP ${response.statusCode})');
    }
    await file.writeAsBytes(response.bodyBytes);
    return file;
  }

  // ── story.json cache ──────────────────────────────────────────────────────

  Future<File> _storyJsonCacheFile(String storyId) async {
    final dir = await getApplicationCacheDirectory();
    return File(p.join(dir.path, 'r2', 'story_$storyId.json'));
  }

  Future<Map<String, dynamic>?> _readCachedStoryJson(String storyId) async {
    if (kIsWeb) return null;
    try {
      final file = await _storyJsonCacheFile(storyId);
      if (!file.existsSync()) return null;
      final raw = await file.readAsString();
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCachedStoryJson(String storyId, String body) async {
    if (kIsWeb) return;
    try {
      final file = await _storyJsonCacheFile(storyId);
      await file.parent.create(recursive: true);
      await file.writeAsString(body);
    } catch (_) {
      // Cache write failure is non-fatal; next load will refetch.
    }
  }

  // ── Maintenance ───────────────────────────────────────────────────────────

  Future<void> clearCache() async {
    if (kIsWeb) return;
    final dir = await getApplicationCacheDirectory();
    final r2Dir = Directory(p.join(dir.path, 'r2'));
    if (r2Dir.existsSync()) await r2Dir.delete(recursive: true);
  }
}
