// lib/screens/home_screen.dart

import 'package:flutter/material.dart';
import '../models/story.dart';
import 'story_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Default language. Phase 4: load this from user's saved preference.
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
          // Language picker — top right
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: DropdownButton<String>(
              value: _selectedLanguage,
              underline: const SizedBox(),
              dropdownColor: const Color(0xFFFFF8F0),
              style: const TextStyle(
                color: Color(0xFF3D2B1F),
                fontSize: 14,
              ),
              items: _languageLabels.entries.map((e) {
                return DropdownMenuItem(
                  value: e.key,
                  child: Text(e.value),
                );
              }).toList(),
              onChanged: (lang) {
                if (lang != null) setState(() => _selectedLanguage = lang);
              },
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Free Story',
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF9E8872),
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            _StoryCard(
              story: bundledStory,
              selectedLanguage: _selectedLanguage,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _StoryCard extends StatelessWidget {
  final Story story;
  final String selectedLanguage;

  const _StoryCard({
    required this.story,
    required this.selectedLanguage,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => StoryScreen(
              story: story,
              selectedLanguage: selectedLanguage, // ← passed through
            ),
          ),
        );
      },
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
                story.coverPath,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: const Color(0xFF6B9FD4),
                  child: const Icon(Icons.book, size: 60, color: Colors.white),
                ),
              ),
              // Gradient overlay at bottom
              Positioned(
                bottom: 0, left: 0, right: 0,
                child: Container(
                  height: 80,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withOpacity(0.7),
                      ],
                    ),
                  ),
                ),
              ),
              // Title — uses localizedTitle() from new model
              Positioned(
                bottom: 16,
                left: 16,
                child: Text(
                  story.localizedTitle(selectedLanguage),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
                  ),
                ),
              ),
              // FREE badge
              Positioned(
                top: 12, right: 12,
                child: Container(
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
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
