import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart'; // ← replaces just_audio
import '../models/story.dart';

class StoryScreen extends StatefulWidget {
  final Story story;

  const StoryScreen({super.key, required this.story});

  @override
  State<StoryScreen> createState() => _StoryScreenState();
}

class _StoryScreenState extends State<StoryScreen> {
  int _currentPage = 0;
  bool _narrationEnabled = true;
  bool _isPlaying = false;

  final AudioPlayer _player = AudioPlayer();

  @override
  void initState() {
    super.initState();

    // Listen for playback completion
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _isPlaying = false);
    });

    _playCurrentPage();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  // ── Audio ──────────────────────────────────────────────────────────────────

  Future<void> _playCurrentPage() async {
    if (!_narrationEnabled) return;

    try {
      final page = widget.story.pages[_currentPage];
      await _player.stop();

      // audioplayers uses the path *inside* assets/ — strip the "assets/" prefix
      // e.g. "assets/stories/bunny_adventure/audio/page_01.mp3"
      //   →  "stories/bunny_adventure/audio/page_01.mp3"
      final assetPath = page.audioPath.replaceFirst('assets/', '');

      await _player.play(AssetSource(assetPath));
      if (mounted) setState(() => _isPlaying = true);
    } catch (e) {
      // Audio file might not exist yet during dev — fail silently
      debugPrint('Audio error: $e');
    }
  }

  Future<void> _stopAudio() async {
    await _player.stop();
    if (mounted) setState(() => _isPlaying = false);
  }

  void _toggleNarration() {
    setState(() => _narrationEnabled = !_narrationEnabled);
    if (_narrationEnabled) {
      _playCurrentPage();
    } else {
      _stopAudio();
    }
  }

  // ── Navigation ─────────────────────────────────────────────────────────────

  void _goToPage(int index) {
    if (index < 0 || index >= widget.story.pages.length) return;
    _stopAudio().then((_) {
      setState(() => _currentPage = index);
      _playCurrentPage();
    });
  }

  void _goNext() => _goToPage(_currentPage + 1);
  void _goPrev() => _goToPage(_currentPage - 1);

  void _goBack() {
    _stopAudio().then((_) => Navigator.pop(context));
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final page = widget.story.pages[_currentPage];
    final isFirst = _currentPage == 0;
    final isLast = _currentPage == widget.story.pages.length - 1;
    final pageCount = widget.story.pages.length;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar ──────────────────────────────────────────────────────
            _TopBar(
              title: widget.story.title,
              narrationEnabled: _narrationEnabled,
              onBack: _goBack,
              onToggleNarration: _toggleNarration,
            ),

            // ── Illustration ─────────────────────────────────────────────────
            Expanded(
              flex: 6,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: child,
                ),
                child: Image.asset(
                  page.imagePath,
                  key: ValueKey(_currentPage),
                  fit: BoxFit.contain,
                  width: double.infinity,
                  errorBuilder: (_, __, ___) => Container(
                    color: const Color(0xFF1A1A2E),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.image_not_supported,
                              color: Colors.white38, size: 48),
                          const SizedBox(height: 8),
                          Text(
                            'Page ${_currentPage + 1} image\n(add to assets/)',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // ── Text + page dots ─────────────────────────────────────────────
            Expanded(
              flex: 3,
              child: Container(
                width: double.infinity,
                color: const Color(0xFFFFF8F0),
                padding: const EdgeInsets.symmetric(
                    horizontal: 28, vertical: 20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Text(
                        page.text,
                        key: ValueKey(_currentPage),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 18,
                          height: 1.6,
                          color: Color(0xFF3D2B1F),
                          fontFamily: 'Georgia',
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(pageCount, (i) {
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: i == _currentPage ? 20 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: i == _currentPage
                                ? const Color(0xFF6B9FD4)
                                : const Color(0xFFCCBBAA),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        );
                      }),
                    ),
                  ],
                ),
              ),
            ),

            // ── Bottom nav ───────────────────────────────────────────────────
            _BottomNav(
              onPrev: isFirst ? null : _goPrev,
              onNext: isLast ? null : _goNext,
              isLast: isLast,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets (unchanged from Phase 1)
// ─────────────────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final String title;
  final bool narrationEnabled;
  final VoidCallback onBack;
  final VoidCallback onToggleNarration;

  const _TopBar({
    required this.title,
    required this.narrationEnabled,
    required this.onBack,
    required this.onToggleNarration,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      color: const Color(0xFF1A1A2E),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_ios_new,
                color: Colors.white, size: 20),
            tooltip: 'Back to menu',
          ),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            onPressed: onToggleNarration,
            icon: Icon(
              narrationEnabled ? Icons.volume_up : Icons.volume_off,
              color: narrationEnabled
                  ? const Color(0xFF6B9FD4)
                  : Colors.white38,
              size: 24,
            ),
            tooltip: narrationEnabled ? 'Turn off narration' : 'Turn on narration',
          ),
        ],
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final bool isLast;

  const _BottomNav({
    required this.onPrev,
    required this.onNext,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      color: const Color(0xFF1A1A2E),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _NavButton(
            icon: Icons.chevron_left,
            label: 'Prev',
            onPressed: onPrev,
          ),
          isLast
              ? const Text(
                  '🌟 The End',
                  style: TextStyle(
                    color: Color(0xFFFFD700),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                )
              : _NavButton(
                  icon: Icons.chevron_right,
                  label: 'Next',
                  onPressed: onNext,
                  reversed: true,
                ),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool reversed;

  const _NavButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.reversed = false,
  });

  @override
  Widget build(BuildContext context) {
    final isEnabled = onPressed != null;
    final color = isEnabled ? Colors.white : Colors.white24;

    final children = [
      Icon(icon, color: color, size: 28),
      const SizedBox(width: 4),
      Text(label,
          style: TextStyle(
              color: color, fontSize: 14, fontWeight: FontWeight.w500)),
    ];

    return GestureDetector(
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: reversed ? children.reversed.toList() : children,
        ),
      ),
    );
  }
}