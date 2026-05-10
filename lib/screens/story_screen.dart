// lib/screens/story_screen.dart
//
// Phase 3: images and audio resolve through StoryService.
//   - Bundled story  → Image.asset + AssetSource
//   - Remote (mobile) → CachedNetworkImage + DeviceFileSource (from disk cache)
//   - Remote (web)    → CachedNetworkImage + UrlSource (browser HTTP cache)

import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../models/story.dart';
import '../services/story_service.dart';

class StoryScreen extends StatefulWidget {
  final Story story;
  final String selectedLanguage;
  final StoryService service;

  const StoryScreen({
    super.key,
    required this.story,
    required this.selectedLanguage,
    required this.service,
  });

  @override
  State<StoryScreen> createState() => _StoryScreenState();
}

class _StoryScreenState extends State<StoryScreen> {
  int _currentPage = 0;
  bool _narrationEnabled = true;
  bool _audioLoading = false;
  late String _lang;

  final AudioPlayer _player = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _lang = widget.selectedLanguage;

    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() {});
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

    final content = widget.story.pages[_currentPage].localized(_lang);
    if (mounted) setState(() => _audioLoading = true);

    try {
      await _player.stop();

      if (widget.story.meta.isBundled) {
        // AssetSource expects path relative to assets/
        await _player.play(AssetSource(content.audioPath));
      } else if (kIsWeb) {
        // Web: stream directly, browser caches HTTP response
        await _player.play(
          UrlSource(widget.service.resolveUrl(content.audioPath)),
        );
      } else {
        // Mobile remote: ensure cached, then play from local file
        final localPath =
            await widget.service.getAudioFilePath(content.audioPath);
        await _player.play(DeviceFileSource(localPath));
      }
    } catch (e) {
      debugPrint('Audio error: $e');
    } finally {
      if (mounted) setState(() => _audioLoading = false);
    }
  }

  Future<void> _stopAudio() async {
    await _player.stop();
  }

  void _toggleNarration() {
    setState(() => _narrationEnabled = !_narrationEnabled);
    _narrationEnabled ? _playCurrentPage() : _stopAudio();
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
    _stopAudio().then((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  // ── Image widget ──────────────────────────────────────────────────────────

  Widget _buildImage(StoryPage page) {
    if (widget.story.meta.isBundled) {
      return Image.asset(
        widget.service.resolveAssetPath(page.imagePath),
        key: ValueKey(_currentPage),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) => _imageFallback(),
      );
    }
    return CachedNetworkImage(
      imageUrl: widget.service.resolveUrl(page.imagePath),
      key: ValueKey(_currentPage),
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      placeholder: (_, __) => Container(
        color: const Color(0xFF1A1A2E),
        child: const Center(
          child: CircularProgressIndicator(color: Color(0xFF6B9FD4)),
        ),
      ),
      errorWidget: (_, __, ___) => _imageFallback(),
    );
  }

  Widget _imageFallback() {
    return Container(
      color: const Color(0xFF1A1A2E),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.image_not_supported,
                color: Colors.white38, size: 48),
            const SizedBox(height: 8),
            Text(
              'Page ${_currentPage + 1} could not load',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white38, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final page = widget.story.pages[_currentPage];
    final content = page.localized(_lang);
    final isFirst = _currentPage == 0;
    final isLast = _currentPage == widget.story.pages.length - 1;
    final pageCount = widget.story.pages.length;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(
              title: widget.story.localizedTitle(_lang),
              narrationEnabled: _narrationEnabled,
              audioLoading: _audioLoading,
              onBack: _goBack,
              onToggleNarration: _toggleNarration,
            ),

            // ── Image with overlaid nav arrows ──────────────────────────────
            Expanded(
              flex: 6,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    transitionBuilder: (child, animation) =>
                        FadeTransition(opacity: animation, child: child),
                    child: _buildImage(page),
                  ),
                  Positioned(
                    left: 8,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: _OverlayNavButton(
                        icon: Icons.chevron_left,
                        onPressed: isFirst ? null : _goPrev,
                      ),
                    ),
                  ),
                  Positioned(
                    right: 8,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: _OverlayNavButton(
                        icon: Icons.chevron_right,
                        onPressed: isLast ? null : _goNext,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Text panel ──────────────────────────────────────────────────
            Expanded(
              flex: 3,
              child: Container(
                width: double.infinity,
                color: const Color(0xFFFFF8F0),
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Text(
                        content.text,
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
                    if (isLast) ...[
                      const SizedBox(height: 12),
                      const Text(
                        '🌟 The End',
                        style: TextStyle(
                          color: Color(0xFFE8A020),
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Overlay nav button
// ─────────────────────────────────────────────────────────────────────────────

class _OverlayNavButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;

  const _OverlayNavButton({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final isEnabled = onPressed != null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(40),
        splashColor: Colors.white30,
        highlightColor: Colors.white12,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isEnabled ? Colors.black45 : Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            color: isEnabled ? Colors.white : Colors.transparent,
            size: 36,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Top bar — adds a tiny audio-loading indicator next to the volume button
// ─────────────────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final String title;
  final bool narrationEnabled;
  final bool audioLoading;
  final VoidCallback onBack;
  final VoidCallback onToggleNarration;

  const _TopBar({
    required this.title,
    required this.narrationEnabled,
    required this.audioLoading,
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
          if (audioLoading)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF6B9FD4),
                ),
              ),
            ),
          IconButton(
            onPressed: onToggleNarration,
            icon: Icon(
              narrationEnabled ? Icons.volume_up : Icons.volume_off,
              color:
                  narrationEnabled ? const Color(0xFF6B9FD4) : Colors.white38,
              size: 24,
            ),
            tooltip:
                narrationEnabled ? 'Turn off narration' : 'Turn on narration',
          ),
        ],
      ),
    );
  }
}
