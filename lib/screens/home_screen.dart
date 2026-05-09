// lib/screens/home_screen.dart
// Phase 2: loads catalog from JSON, renders story cards with tags + age range.

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
  String _selectedLanguage = 'en';

  static const Map<String, String> _languageLabels = {
    'en': '🇺🇸 English',
    'es': '🇲🇽 Español',
  };

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
                  .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
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
          // ── Loading ───────────────────────────────────────────────────────
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF6B9FD4)),
            );
          }

          // ── Error ─────────────────────────────────────────────────────────
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Could not load stories\n${snapshot.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF9E8872)),
              ),
            );
          }

          final stories = snapshot.data!;
          final freeStories = stories.where((s) => s.isFree).toList();
          final paidStories = stories.where((s) => !s.isFree).toList();

          // ── Library ───────────────────────────────────────────────────────
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (freeStories.isNotEmpty) ...[
                _SectionLabel(label: 'Free ${freeStories.length == 1 ? "Story" : "Stories"}'),
                const SizedBox(height: 12),
                ...freeStories.map((meta) => Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: _StoryCard(
                    meta: meta,
                    selectedLanguage: _selectedLanguage,
                    onTap: () => _openStory(meta),
                  ),
                )),
              ],
              if (paidStories.isNotEmpty) ...[
                const SizedBox(height: 8),
                _SectionLabel(label: 'More Stories'),
                const SizedBox(height: 12),
                ...paidStories.map((meta) => Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: _StoryCard(
                    meta: meta,
                    selectedLanguage: _selectedLanguage,
                    onTap: () => _openStory(meta),
                  ),
                )),
              ],
            ],
          );
        },
      ),
    );
  }

  // Load full story then navigate — shows a brief loading state
  void _openStory(StoryMeta meta) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: Color(0xFF6B9FD4)),
      ),
    );

    try {
      final story = await _service.loadStory(meta);
      if (!mounted) return;
      Navigator.pop(context); // dismiss loader
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => StoryScreen(
            story: story,
            selectedLanguage: _selectedLanguage,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load story: $e')),
      );
    }
  }
}

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

class _StoryCard extends StatelessWidget {
  final StoryMeta meta;
  final String selectedLanguage;
  final VoidCallback onTap;

  const _StoryCard({
    required this.meta,
    required this.selectedLanguage,
    required this.onTap,
  });

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
              // Cover image
              Image.asset(
                meta.coverPath,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: const Color(0xFF6B9FD4),
                  child: const Icon(Icons.book, size: 60, color: Colors.white),
                ),
              ),

              // Gradient overlay
              Positioned(
                bottom: 0, left: 0, right: 0,
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

              // Title + tags
              Positioned(
                bottom: 12, left: 16, right: 60,
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
                    // Age range + tags
                    Row(
                      children: [
                        _Chip('${meta.ageMin}–${meta.ageMax} yrs'),
                        const SizedBox(width: 6),
                        ...meta.tags.take(2).map((tag) => Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: _Chip(tag),
                        )),
                      ],
                    ),
                  ],
                ),
              ),

              // Badge: FREE or locked icon
              Positioned(
                top: 12, right: 12,
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

class _Chip extends StatelessWidget {
  final String label;
  const _Chip(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white24,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
        ),
      ),
    );
  }
}
