// lib/screens/home_screen.dart
//
// Phase 2: catalog from JSON, search filter.
// Phase 3: covers stream from R2 via CachedNetworkImage; tapping a story
//          downloads its assets with a progress dialog before navigating.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../models/story.dart';
import '../services/story_service.dart';
import 'story_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _service = StoryService();
  final _searchController = TextEditingController();

  String _selectedLanguage = 'en';
  String _searchQuery = '';

  static const Map<String, String> _languageLabels = {
    'en': '🇺🇸 English',
    'es': '🇲🇽 Español',
  };

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ── Filter ─────────────────────────────────────────────────────────────────

  List<StoryMeta> _filter(List<StoryMeta> stories) {
    if (_searchQuery.isEmpty) return stories;
    final q = _searchQuery.toLowerCase();
    return stories.where((s) {
      final titleMatch =
          s.localizedTitle(_selectedLanguage).toLowerCase().contains(q);
      final tagMatch = s.tags.any((t) => t.toLowerCase().contains(q));
      return titleMatch || tagMatch;
    }).toList();
  }

  // ── Open story flow ───────────────────────────────────────────────────────

  Future<void> _openStory(StoryMeta meta) async {
    // Step 1: load story.json (fast, just metadata + page text)
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: Color(0xFF6B9FD4)),
      ),
    );

    Story story;
    try {
      story = await _service.loadStory(meta);
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load story: $e')),
      );
      return;
    }

    if (!mounted) return;
    Navigator.pop(context); // dismiss spinner

    // Step 2: prefetch assets (skipped automatically for bundled / web)
    final ok = await _prefetchWithDialog(story);
    if (!ok || !mounted) return;

    // Step 3: navigate
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StoryScreen(
          story: story,
          selectedLanguage: _selectedLanguage,
          service: _service,
        ),
      ),
    );
  }

  /// Shows a determinate progress dialog while assets download.
  /// Returns true if completed, false if cancelled or failed.
  Future<bool> _prefetchWithDialog(Story story) async {
    // Bundled or web: prefetch is instant (yields 1.0 immediately). Skip UI.
    if (story.meta.isBundled) return true;

    final progress = ValueNotifier<double>(0.0);
    final cancelled = ValueNotifier<bool>(false);

    // Run the prefetch in the background; the dialog watches `progress`.
    final completer = _runPrefetch(story, progress, cancelled);

    if (!mounted) return false;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _PrefetchDialog(
        title: story.localizedTitle(_selectedLanguage),
        progress: progress,
        onCancel: () {
          cancelled.value = true;
          Navigator.pop(ctx);
        },
      ),
    );

    final result = await completer;

    progress.dispose();
    cancelled.dispose();

    if (result is _PrefetchError && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download failed: ${result.message}')),
      );
      return false;
    }
    return result is _PrefetchSuccess;
  }

  Future<_PrefetchResult> _runPrefetch(
    Story story,
    ValueNotifier<double> progress,
    ValueNotifier<bool> cancelled,
  ) async {
    try {
      await for (final p in _service.prefetchStory(story, _selectedLanguage)) {
        if (cancelled.value) {
          return _PrefetchCancelled();
        }
        progress.value = p;
      }
      // Close the dialog if it's still open
      if (mounted && !cancelled.value) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      return _PrefetchSuccess();
    } catch (e) {
      if (mounted && !cancelled.value) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      return _PrefetchError(e.toString());
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F0),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          '📚 My Stories',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Color(0xFF3D2B1F),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: DropdownButton<String>(
              value: _selectedLanguage,
              underline: const SizedBox(),
              dropdownColor: const Color(0xFFFFF8F0),
              style: const TextStyle(color: Color(0xFF3D2B1F), fontSize: 14),
              items: _languageLabels.entries
                  .map((e) => DropdownMenuItem(
                        value: e.key,
                        child: Text(e.value),
                      ))
                  .toList(),
              onChanged: (lang) {
                if (lang != null) setState(() => _selectedLanguage = lang);
              },
            ),
          ),
        ],
      ),
      body: FutureBuilder<List<StoryMeta>>(
        future: _service.loadCatalog(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF6B9FD4)),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Could not load stories\n${snapshot.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF9E8872)),
              ),
            );
          }

          final all = snapshot.data!;
          final filtered = _filter(all);
          final freeStories = filtered.where((s) => s.isFree).toList();
          final paidStories = filtered.where((s) => !s.isFree).toList();

          return Column(
            children: [
              // ── Search bar ────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _searchQuery = v.trim()),
                  style: const TextStyle(
                    color: Color(0xFF3D2B1F),
                    fontSize: 15,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search by title or tag…',
                    hintStyle: const TextStyle(
                      color: Color(0xFFBBAA99),
                      fontSize: 15,
                    ),
                    prefixIcon: const Icon(
                      Icons.search,
                      color: Color(0xFF9E8872),
                      size: 20,
                    ),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close,
                                color: Color(0xFF9E8872), size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: const Color(0xFFEDE8E0),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),

              // ── Story list ────────────────────────────────────────────────
              Expanded(
                child: filtered.isEmpty
                    ? _EmptyState(query: _searchQuery)
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                        children: [
                          if (freeStories.isNotEmpty) ...[
                            _SectionLabel(
                              label:
                                  'Free ${freeStories.length == 1 ? "Story" : "Stories"}',
                            ),
                            const SizedBox(height: 12),
                            ...freeStories.map((meta) => Padding(
                                  padding: const EdgeInsets.only(bottom: 20),
                                  child: _StoryCard(
                                    meta: meta,
                                    selectedLanguage: _selectedLanguage,
                                    searchQuery: _searchQuery,
                                    service: _service,
                                    onTap: () => _openStory(meta),
                                  ),
                                )),
                          ],
                          if (paidStories.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            const _SectionLabel(label: 'More Stories'),
                            const SizedBox(height: 12),
                            ...paidStories.map((meta) => Padding(
                                  padding: const EdgeInsets.only(bottom: 20),
                                  child: _StoryCard(
                                    meta: meta,
                                    selectedLanguage: _selectedLanguage,
                                    searchQuery: _searchQuery,
                                    service: _service,
                                    onTap: () => _openStory(meta),
                                  ),
                                )),
                          ],
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Prefetch result types
// ─────────────────────────────────────────────────────────────────────────────

abstract class _PrefetchResult {}

class _PrefetchSuccess extends _PrefetchResult {}

class _PrefetchCancelled extends _PrefetchResult {}

class _PrefetchError extends _PrefetchResult {
  final String message;
  _PrefetchError(this.message);
}

// ─────────────────────────────────────────────────────────────────────────────
// Prefetch dialog — listens to a ValueNotifier<double>
// ─────────────────────────────────────────────────────────────────────────────

class _PrefetchDialog extends StatelessWidget {
  final String title;
  final ValueNotifier<double> progress;
  final VoidCallback onCancel;

  const _PrefetchDialog({
    required this.title,
    required this.progress,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFFFFF8F0),
      title: Text(
        'Opening $title…',
        style: const TextStyle(
          color: Color(0xFF3D2B1F),
          fontSize: 16,
          fontFamily: 'Georgia',
        ),
      ),
      content: ValueListenableBuilder<double>(
        valueListenable: progress,
        builder: (_, value, __) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(
              value: value,
              backgroundColor: const Color(0xFFEDE8E0),
              valueColor: const AlwaysStoppedAnimation(Color(0xFF6B9FD4)),
            ),
            const SizedBox(height: 12),
            Text(
              '${(value * 100).round()}%',
              style: const TextStyle(color: Color(0xFF9E8872)),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: onCancel,
          child: const Text(
            'Cancel',
            style: TextStyle(color: Color(0xFF9E8872)),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty state
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final String query;
  const _EmptyState({required this.query});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🔍', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 12),
          Text(
            'No stories found for "$query"',
            style: const TextStyle(color: Color(0xFF9E8872), fontSize: 15),
          ),
          const SizedBox(height: 6),
          const Text(
            'Try searching by tag — adventure, bedtime…',
            style: TextStyle(color: Color(0xFFBBAA99), fontSize: 13),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section label
// ─────────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: const TextStyle(
        fontSize: 13,
        color: Color(0xFF9E8872),
        letterSpacing: 1.4,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Story card — uses CachedNetworkImage for remote covers, Image.asset
// for bundled covers. The two paths share styling.
// ─────────────────────────────────────────────────────────────────────────────

class _StoryCard extends StatelessWidget {
  final StoryMeta meta;
  final String selectedLanguage;
  final String searchQuery;
  final StoryService service;
  final VoidCallback onTap;

  const _StoryCard({
    required this.meta,
    required this.selectedLanguage,
    required this.searchQuery,
    required this.service,
    required this.onTap,
  });

  Widget _coverFallback() {
    return Container(
      color: const Color(0xFF6B9FD4),
      child: const Icon(Icons.book, size: 60, color: Colors.white),
    );
  }

  Widget _buildCover() {
    if (meta.isBundled) {
      return Image.asset(
        service.resolveAssetPath(meta.coverPath),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _coverFallback(),
      );
    }
    return CachedNetworkImage(
      imageUrl: service.resolveUrl(meta.coverPath),
      fit: BoxFit.cover,
      placeholder: (_, __) => Container(
        color: const Color(0xFFEDE8E0),
        child: const Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Color(0xFF6B9FD4),
          ),
        ),
      ),
      errorWidget: (_, __, ___) => _coverFallback(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 200,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildCover(),

              // Gradient overlay for text legibility
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 100,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withOpacity(0.75),
                      ],
                    ),
                  ),
                ),
              ),

              // Title + chips
              Positioned(
                bottom: 12,
                left: 16,
                right: 60,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      meta.localizedTitle(selectedLanguage),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _Chip(
                          '${meta.ageMin}–${meta.ageMax} yrs',
                          highlight: false,
                        ),
                        const SizedBox(width: 6),
                        ...meta.tags.take(2).map((tag) => Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: _Chip(
                                tag,
                                highlight: searchQuery.isNotEmpty &&
                                    tag
                                        .toLowerCase()
                                        .contains(searchQuery.toLowerCase()),
                              ),
                            )),
                      ],
                    ),
                  ],
                ),
              ),

              // Free / lock badge
              Positioned(
                top: 12,
                right: 12,
                child: meta.isFree
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF4CAF50),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'FREE',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )
                    : Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(Icons.lock,
                            color: Colors.white70, size: 16),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tag chip
// ─────────────────────────────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  final String label;
  final bool highlight;

  const _Chip(this.label, {this.highlight = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: highlight ? const Color(0xFF6B9FD4) : Colors.white24,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }
}
