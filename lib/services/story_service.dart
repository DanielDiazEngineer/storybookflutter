// lib/services/story_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/story.dart';

class StoryService {
  late final String _r2BaseUrl = _readBaseUrl();

  /// Observable catalog. Home screen listens; updates fire when the
  /// background refresh discovers new content.
  final ValueNotifier<List<StoryMeta>?> catalog = ValueNotifier(null);

  /// The serialized catalog body currently reflected in [catalog].
  /// Used to detect "did anything change?" after a network refresh.
  String? _catalogBodyCache;

  /// Guard so concurrent loadCatalog() / refresh calls don't stack.
  bool _refreshing = false;

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

  // ── Catalog: stale-while-revalidate ───────────────────────────────────────
  //
  // 1. Disk cache (instant)  → publish + kick off refresh
  // 2. Bundled asset (instant fallback if no disk cache yet)
  // 3. Network refresh always runs in background; if its result differs
  //    from what we last published, we publish the new catalog AND
  //    invalidate all story.json caches (they may now be stale).

  Future<void> loadCatalog() async {
    if (catalog.value != null) {
      unawaited(_refreshFromNetwork());
      return;
    }

    // Disk cache first.
    final cachedBody = await _readCachedCatalogBody();
    if (cachedBody != null) {
      // Re-merge with current bundled in case an app update added bundled stories.
      final merged = await _mergeRemoteWithBundled(cachedBody);
      final parsed = _parseCatalog(merged);
      if (parsed != null) {
        _catalogBodyCache = merged;
        catalog.value = parsed;
        unawaited(_refreshFromNetwork());
        return;
      }
    }

    // Bundled fallback for the first ever launch.
    final bundledBody = await rootBundle.loadString('assets/catalog.json');
    final parsed = _parseCatalog(bundledBody);
    if (parsed != null) {
      _catalogBodyCache = bundledBody;
      catalog.value = parsed;
    }

    unawaited(_refreshFromNetwork());
  }

  Future<void> _refreshFromNetwork() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final remoteBody = await _fetchRemoteCatalogBody();
      if (remoteBody == null) return;

      final merged = await _mergeRemoteWithBundled(remoteBody);
      if (merged == _catalogBodyCache) return; // nothing changed

      final parsed = _parseCatalog(merged);
      if (parsed == null) return;

      await _writeCachedCatalogBody(merged);
      _catalogBodyCache = merged;
      catalog.value = parsed;

      // Catalog body changed → story.json caches are suspect.
      // (Asset caches are keyed by path; new paths in updated story.json
      // miss the cache automatically. Old assets are orphaned, swept later.)
      await _invalidateAllStoryJsonCaches();
    } catch (_) {
      // Background failure is silent. Next launch will retry.
    } finally {
      _refreshing = false;
    }
  }

  Future<String?> _fetchRemoteCatalogBody() async {
    try {
      final url = '$_r2BaseUrl/catalog.json';
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      return response.body;
    } catch (_) {
      return null;
    }
  }

  /// Remote-wins per story id, with bundled stories the remote forgot
  /// appended as a safety net. Returns a stable JSON string.
  Future<String> _mergeRemoteWithBundled(String remoteBody) async {
    final remote = jsonDecode(remoteBody) as Map<String, dynamic>;
    final remoteList = (remote['stories'] as List).cast<Map<String, dynamic>>();
    final remoteIds = remoteList.map((s) => s['id'] as String).toSet();

    final bundledBody = await rootBundle.loadString('assets/catalog.json');
    final bundled = jsonDecode(bundledBody) as Map<String, dynamic>;
    final bundledList =
        (bundled['stories'] as List).cast<Map<String, dynamic>>();

    final orphans = bundledList.where((s) => !remoteIds.contains(s['id']));

    return jsonEncode({
      'stories': [...remoteList, ...orphans],
    });
  }

  List<StoryMeta>? _parseCatalog(String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final list = json['stories'] as List;
      return list
          .map((item) => StoryMeta.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return null;
    }
  }

  // ── URL / asset path resolution ───────────────────────────────────────────

  String resolveUrl(String relativePath) => '$_r2BaseUrl/$relativePath';
  String resolveAssetPath(String relativePath) => 'assets/$relativePath';

  // ── Story loading (unchanged except: no more redundant loadCatalog) ───────

  Future<Story> loadStory(StoryMeta meta) async {
    final cached = await _readCachedStoryJson(meta.id);
    if (cached != null) return Story.fromJson(cached, meta);

    Map<String, dynamic>? json;
    try {
      final url = resolveUrl('stories/${meta.id}/story.json');
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        json = jsonDecode(response.body) as Map<String, dynamic>;
        await _writeCachedStoryJson(meta.id, response.body);
      }
    } catch (_) {}

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

  // ── Prefetch (unchanged) ──────────────────────────────────────────────────

  Stream<double> prefetchStory(Story story, String langCode) async* {
    if (story.meta.isBundled) {
      yield 1.0;
      return;
    }
    if (kIsWeb) {
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
    for (final relativePath in assets) {
      try {
        await _ensureCached(relativePath);
      } catch (e) {
        final isAudio = relativePath.contains('/audio/');
        if (!isAudio) rethrow;
      }
      done++;
      yield done / assets.length;
    }
  }

  // ── Audio path resolution (unchanged) ─────────────────────────────────────

  Future<String> getAudioFilePath(String relativePath) async {
    if (kIsWeb) return resolveUrl(relativePath);
    final file = await _ensureCached(relativePath);
    return file.path;
  }

  // ── Asset cache (unchanged) ───────────────────────────────────────────────

  Future<File> _cacheFileFor(String relativePath) async {
    if (kIsWeb) throw UnsupportedError('File cache not available on web');
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

  // ── Catalog disk cache ────────────────────────────────────────────────────

  Future<File> _catalogCacheFile() async {
    final dir = await getApplicationCacheDirectory();
    return File(p.join(dir.path, 'r2', 'catalog.json'));
  }

  Future<String?> _readCachedCatalogBody() async {
    if (kIsWeb) return null;
    try {
      final f = await _catalogCacheFile();
      if (!f.existsSync()) return null;
      return await f.readAsString();
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCachedCatalogBody(String body) async {
    if (kIsWeb) return;
    try {
      final f = await _catalogCacheFile();
      await f.parent.create(recursive: true);
      await f.writeAsString(body);
    } catch (_) {}
  }

  // ── Story.json cache (per-story) ──────────────────────────────────────────

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
    } catch (_) {}
  }

  /// Called when the catalog body changes. Wipes every cached story.json
  /// so the next story open re-fetches fresh content. Asset files
  /// (images, audio) are untouched — they're keyed by path, and the new
  /// story.json will reference new paths if content changed.
  Future<void> _invalidateAllStoryJsonCaches() async {
    if (kIsWeb) return;
    try {
      final dir = await getApplicationCacheDirectory();
      final r2Dir = Directory(p.join(dir.path, 'r2'));
      if (!r2Dir.existsSync()) return;
      await for (final entity in r2Dir.list()) {
        if (entity is File) {
          final name = p.basename(entity.path);
          if (name.startsWith('story_') && name.endsWith('.json')) {
            try {
              await entity.delete();
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
  }

  // ── Maintenance ───────────────────────────────────────────────────────────

  Future<void> clearCache() async {
    if (kIsWeb) return;
    final dir = await getApplicationCacheDirectory();
    final r2Dir = Directory(p.join(dir.path, 'r2'));
    if (r2Dir.existsSync()) await r2Dir.delete(recursive: true);
  }
}
