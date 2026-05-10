// lib/screens/home_screen.dart
//
// Phase 3.5 redesign:
//  - Landscape locked (orientation forced in main.dart)
//  - Single sorted list: Continue card (if resume) → free → bundled → locked
//  - Filter chips replace the search bar (small library, scroll is fine)
//  - BookSpineCard everywhere; Hero anchored on the cover image
//  - Top-right: language toggle pill only

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../main.dart' show AppColors, AppRadius;
import '../models/story.dart';
import '../services/resume_service.dart';
import '../services/story_service.dart';
import '../widgets/book_spine_card.dart';
import 'story_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _service = StoryService();
  final _resume = ResumeService();

  String _selectedLanguage = 'en';
  String? _activeTag; // null = "All"

  static const Map<String, String> _languageLabels = {
    'es': '🇲🇽 Español',
    'en': '🇺🇸 English',

    //TODO ADD MORE LANGAUGES
    //   'fr': '🇫🇷 Français',
    // 'pt': '🇧🇷 Português',
  };

  Future<List<StoryMeta>>? _catalogFuture;
  Future<ResumeState?>? _resumeFuture;

  @override
  void initState() {
    super.initState();
    _catalogFuture = _service.loadCatalog();
    _resumeFuture = _resume.getMostRecent();
  }

  // ── Sort: continue's story first, then free, then bundled, then locked ────

  List<StoryMeta> _sortAndFilter(List<StoryMeta> all, ResumeState? resume) {
    final filtered = _activeTag == null
        ? all
        : all.where((s) => s.tags.contains(_activeTag)).toList();

    int rank(StoryMeta m) {
      if (resume != null && m.id == resume.storyId) return 0;
      if (m.isFree) return 1;
      if (m.isBundled) return 2;
      return 3;
    }

    filtered.sort((a, b) => rank(a).compareTo(rank(b)));
    return filtered;
  }

  Set<String> _allTags(List<StoryMeta> stories) {
    final set = <String>{};
    for (final s in stories) {
      set.addAll(s.tags);
    }
    return set;
  }

  // ── Story open flow ───────────────────────────────────────────────────────

  Future<void> _openStory(StoryMeta meta, {int? startPage}) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: AppColors.accent),
      ),
    );

    Story story;
    try {
      story = await _service.loadStory(meta);
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      _showSnack('Could not load story: $e');
      return;
    }
    if (!mounted) return;
    Navigator.pop(context);

    final ok = await _prefetchWithDialog(story);
    if (!ok || !mounted) return;

    // If no startPage explicitly given, look up resume state.
    int initialPage = startPage ?? 0;
    if (startPage == null) {
      final r = await _resume.getForStory(meta.id);
      if (r != null && r.pageIndex > 0 && r.pageIndex < story.pages.length) {
        // Offer resume vs. start over only if they're meaningfully apart
        if (!mounted) return;
        final resumeChoice = await _askResumeOrRestart(story, r);
        if (resumeChoice == null) return; // user dismissed
        initialPage = resumeChoice;
      }
    }

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StoryScreen(
          story: story,
          selectedLanguage: _selectedLanguage,
          service: _service,
          resume: _resume,
          initialPage: initialPage,
        ),
      ),
    );

    // Refresh resume after returning so the home Continue card updates.
    if (mounted) {
      setState(() {
        _resumeFuture = _resume.getMostRecent();
      });
    }
  }

  Future<int?> _askResumeOrRestart(Story story, ResumeState r) async {
    return showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cream,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.card)),
        title: Text(
          story.localizedTitle(_selectedLanguage),
          style: const TextStyle(color: AppColors.ink, fontFamily: 'Georgia'),
        ),
        content: Text(
          'Continue from page ${r.pageIndex + 1} or start from the beginning?',
          style:
              const TextStyle(color: AppColors.inkSoft, fontFamily: 'Georgia'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 0),
            child: const Text('Start over',
                style: TextStyle(color: AppColors.inkSoft)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
            onPressed: () => Navigator.pop(ctx, r.pageIndex),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  Future<bool> _prefetchWithDialog(Story story) async {
    if (story.meta.isBundled) return true;

    final progress = ValueNotifier<double>(0.0);
    final cancelled = ValueNotifier<bool>(false);
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
      _showSnack('Download failed: ${result.message}');
      return false;
    }
    return result is _PrefetchSuccess;
  }

  Future<_PrefetchResult> _runPrefetch(Story story,
      ValueNotifier<double> progress, ValueNotifier<bool> cancelled) async {
    try {
      await for (final p in _service.prefetchStory(story, _selectedLanguage)) {
        if (cancelled.value) return _PrefetchCancelled();
        progress.value = p;
      }
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

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isTablet = size.shortestSide >= 600;
    final cols = isTablet ? 3 : 2;

    return Scaffold(
      backgroundColor: AppColors.cream,
      body: SafeArea(
        child: FutureBuilder<List<StoryMeta>>(
          future: _catalogFuture,
          builder: (context, catalogSnap) {
            if (catalogSnap.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.accent),
              );
            }
            if (catalogSnap.hasError) {
              return Center(
                child: Text(
                  'Could not load stories\n${catalogSnap.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.inkSoft),
                ),
              );
            }

            final all = catalogSnap.data!;

            return FutureBuilder<ResumeState?>(
              future: _resumeFuture,
              builder: (context, resumeSnap) {
                final resume = resumeSnap.data;
                final visible = _sortAndFilter(all, resume);
                final tags = _allTags(all).toList()..sort();

                return CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(child: _buildTopBar()),
                    SliverToBoxAdapter(
                      child: _buildFilterChips(tags),
                    ),
                    if (resume != null)
                      SliverToBoxAdapter(
                        child: _buildContinueCard(all, resume),
                      ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      sliver: SliverGrid(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: cols,
                          childAspectRatio: 16 / 11,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, i) {
                            final meta = visible[i];
                            return BookSpineCard(
                              meta: meta,
                              selectedLanguage: _selectedLanguage,
                              searchQuery: '',
                              service: _service,
                              onTap: () => _openStory(meta),
                            );
                          },
                          childCount: visible.length,
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  // ── Top bar ───────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 16, 4),
      child: Row(
        children: [
          const Text(
            'Storybook',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: AppColors.ink,
              fontFamily: 'Georgia',
            ),
          ),
          const Spacer(),
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: AppColors.creamShade,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedLanguage,
                icon: const Icon(Icons.expand_more_rounded,
                    color: AppColors.ink, size: 20),
                dropdownColor: AppColors.cream,
                borderRadius: BorderRadius.circular(AppRadius.card),
                style: const TextStyle(
                  color: AppColors.ink,
                  fontFamily: 'Georgia',
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
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
          ),
        ],
      ),
    );
  }

  // ── Filter chips ──────────────────────────────────────────────────────────

  Widget _buildFilterChips(List<String> tags) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          _filterChip('All', _activeTag == null, () {
            setState(() => _activeTag = null);
          }),
          ...tags.map((t) => _filterChip(
                _capitalize(t),
                _activeTag == t,
                () => setState(() => _activeTag = t),
              )),
        ],
      ),
    );
  }

  Widget _filterChip(String label, bool active, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: active ? AppColors.accent : AppColors.creamShade,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                label,
                style: TextStyle(
                  color: active ? Colors.white : AppColors.ink,
                  fontWeight: active ? FontWeight.bold : FontWeight.normal,
                  fontSize: 14,
                  fontFamily: 'Georgia',
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Continue card (hero slot) ─────────────────────────────────────────────

  Widget _buildContinueCard(List<StoryMeta> all, ResumeState resume) {
    final meta = all.firstWhere(
      (m) => m.id == resume.storyId,
      orElse: () => all.first,
    );
    if (meta.id != resume.storyId) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.card),
          onTap: () => _openStory(meta, startPage: resume.pageIndex),
          child: Container(
            height: 110,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.card),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.12),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.card),
              child: Row(
                children: [
                  // Cover thumbnail
                  AspectRatio(
                    aspectRatio: 16 / 11,
                    child: Hero(
                      // Different tag from the grid card to avoid Hero collision
                      tag: 'continue-${meta.id}',
                      child: _coverThumb(meta),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      color: AppColors.creamShade,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            'Continue reading',
                            style: TextStyle(
                              fontSize: 12,
                              letterSpacing: 1.2,
                              color: AppColors.inkSoft,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            meta.localizedTitle(_selectedLanguage),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.ink,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Georgia',
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Page ${resume.pageIndex + 1}',
                            style: const TextStyle(
                              color: AppColors.inkSoft,
                              fontSize: 13,
                              fontFamily: 'Georgia',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                        color: AppColors.accent,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.play_arrow_rounded,
                          color: Colors.white, size: 28),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _coverThumb(StoryMeta meta) {
    if (meta.isBundled) {
      return Image.asset(
        _service.resolveAssetPath(meta.coverPath),
        fit: BoxFit.cover,
      );
    }
    return CachedNetworkImage(
      imageUrl: _service.resolveUrl(meta.coverPath),
      fit: BoxFit.cover,
      placeholder: (_, __) => Container(color: AppColors.creamShade),
      errorWidget: (_, __, ___) => Container(color: AppColors.accent),
    );
  }

  static String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}

// ─────────────────────────────────────────────────────────────────────────────
// Prefetch dialog (preserved from previous implementation)
// ─────────────────────────────────────────────────────────────────────────────

abstract class _PrefetchResult {}

class _PrefetchSuccess extends _PrefetchResult {}

class _PrefetchCancelled extends _PrefetchResult {}

class _PrefetchError extends _PrefetchResult {
  final String message;
  _PrefetchError(this.message);
}

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
      backgroundColor: AppColors.cream,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card)),
      title: Text(
        'Opening $title…',
        style: const TextStyle(
            color: AppColors.ink, fontSize: 16, fontFamily: 'Georgia'),
      ),
      content: ValueListenableBuilder<double>(
        valueListenable: progress,
        builder: (_, value, __) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: LinearProgressIndicator(
                value: value,
                minHeight: 8,
                backgroundColor: AppColors.creamShade,
                valueColor: const AlwaysStoppedAnimation(AppColors.accent),
              ),
            ),
            const SizedBox(height: 12),
            Text('${(value * 100).round()}%',
                style: const TextStyle(color: AppColors.inkSoft)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: onCancel,
          child:
              const Text('Cancel', style: TextStyle(color: AppColors.inkSoft)),
        ),
      ],
    );
  }
}
