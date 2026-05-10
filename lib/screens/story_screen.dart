// lib/screens/story_screen.dart
//
// Phase 3.5 redesign — landscape reader with:
//  • Three input channels (chevron, tap-zone, swipe) all triggering one
//    canned skew+slide page transition
//  • Tap zones gated by narration state; chevrons always live after 300ms
//  • Chrome auto-dims to 40% after 5s of no interaction
//  • Chapter index morphs out of the menu icon (OpenContainer)
//  • Resume position saved on every page change

import 'dart:async';
import 'package:animations/animations.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../main.dart' show AppColors, AppDurations, AppRadius;
import '../models/story.dart';
import '../services/resume_service.dart';
import '../services/story_service.dart';
import '../transitions/page_skew_transition.dart';
import '../widgets/book_spine_card.dart' show storyHeroTag;
import '../widgets/chapter_index_sheet.dart';

class StoryScreen extends StatefulWidget {
  final Story story;
  final String selectedLanguage;
  final StoryService service;
  final ResumeService resume;
  final int initialPage;

  const StoryScreen({
    super.key,
    required this.story,
    required this.selectedLanguage,
    required this.service,
    required this.resume,
    this.initialPage = 0,
  });

  @override
  State<StoryScreen> createState() => _StoryScreenState();
}

class _StoryScreenState extends State<StoryScreen>
    with TickerProviderStateMixin {
  late int _currentPage;
  late String _lang;
  PageTurnDirection _lastDirection = PageTurnDirection.forward;

  bool _narrationEnabled = true;
  bool _audioPlaying = false; // currently playing narration
  bool _audioLoading = false;
  bool _tapZonesArmed = false; // becomes true after narration ends

  bool _chromeVisible = true; // true → 1.0 opacity, false → 0.4
  Timer? _chromeIdleTimer;

  // Chevron buttons gate: live 300ms after page load.
  bool _chevronsLive = false;
  Timer? _chevronArmTimer;

  // For the OpenContainer chapter sheet: which page was tapped (if any).
  int? _pendingJumpPage;

  // Pulse controller for the chevron "tap zones armed" cue.
  late final AnimationController _chevronPulse;

  // Swipe state — for the small "in-flight" tilt while dragging.
  double _dragDx = 0.0;

  final AudioPlayer _player = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPage;
    _lang = widget.selectedLanguage;

    _chevronPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _player.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() {
        _audioPlaying = false;
        _tapZonesArmed = true;
      });
      _chevronPulse.forward(from: 0).whenComplete(() => _chevronPulse.stop());
    });

    _onPageEntered();
  }

  @override
  void dispose() {
    _chromeIdleTimer?.cancel();
    _chevronArmTimer?.cancel();
    _chevronPulse.dispose();
    _player.dispose();
    super.dispose();
  }

  // ── Per-page lifecycle ────────────────────────────────────────────────────

  void _onPageEntered() {
    // Reset gates
    setState(() {
      _audioPlaying = false;
      _tapZonesArmed = false;
      _chevronsLive = false;
      _chromeVisible = true;
    });

    // Arm chevrons after a small delay (prevents stale-tap carryover)
    _chevronArmTimer?.cancel();
    _chevronArmTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _chevronsLive = true);
    });

    _scheduleChromeDim();
    _persistResume();

    if (_narrationEnabled) {
      _playCurrentPage();
    } else {
      // No narration — arm tap zones after a 1s dwell
      Timer(const Duration(seconds: 1), () {
        if (!mounted) return;
        setState(() => _tapZonesArmed = true);
        _chevronPulse.forward(from: 0).whenComplete(() => _chevronPulse.stop());
      });
    }

    // Clear resume marker if we landed on the last page
    if (_currentPage == widget.story.pages.length - 1) {
      widget.resume.clearForStory(widget.story.id);
    }
  }

  Future<void> _persistResume() async {
    if (_currentPage >= widget.story.pages.length - 1) return;
    await widget.resume.savePosition(
      storyId: widget.story.id,
      pageIndex: _currentPage,
      langCode: _lang,
    );
  }

  void _scheduleChromeDim() {
    _chromeIdleTimer?.cancel();
    _chromeIdleTimer = Timer(AppDurations.chromeIdle, () {
      if (mounted) setState(() => _chromeVisible = false);
    });
  }

  void _wakeChrome() {
    if (!_chromeVisible) {
      setState(() => _chromeVisible = true);
    }
    _scheduleChromeDim();
  }

  // ── Audio ─────────────────────────────────────────────────────────────────

  Future<void> _playCurrentPage() async {
    final content = widget.story.pages[_currentPage].localized(_lang);
    if (mounted) setState(() => _audioLoading = true);
    try {
      await _player.stop();
      if (widget.story.meta.isBundled) {
        await _player.play(AssetSource(content.audioPath));
      } else if (kIsWeb) {
        await _player
            .play(UrlSource(widget.service.resolveUrl(content.audioPath)));
      } else {
        final localPath =
            await widget.service.getAudioFilePath(content.audioPath);
        await _player.play(DeviceFileSource(localPath));
      }
      if (mounted) setState(() => _audioPlaying = true);
    } catch (e) {
      debugPrint('Audio error: $e');
      // If audio fails, arm tap zones anyway so the user isn't stuck
      if (mounted) setState(() => _tapZonesArmed = true);
    } finally {
      if (mounted) setState(() => _audioLoading = false);
    }
  }

  Future<void> _stopAudio() async {
    await _player.stop();
    if (mounted) setState(() => _audioPlaying = false);
  }

  void _toggleNarration() {
    _wakeChrome();
    setState(() => _narrationEnabled = !_narrationEnabled);
    if (_narrationEnabled) {
      _playCurrentPage();
    } else {
      _stopAudio();
      // Arm tap zones since narration is now off
      setState(() => _tapZonesArmed = true);
    }
  }

  // ── Page navigation ───────────────────────────────────────────────────────

  void _goToPage(int index, PageTurnDirection direction) {
    if (index < 0 || index >= widget.story.pages.length) return;
    if (index == _currentPage) return;
    _stopAudio();
    setState(() {
      _lastDirection = direction;
      _currentPage = index;
      _dragDx = 0.0;
    });
    _onPageEntered();
  }

  void _goNext() => _goToPage(_currentPage + 1, PageTurnDirection.forward);
  void _goPrev() => _goToPage(_currentPage - 1, PageTurnDirection.backward);

  void _goHome() {
    _stopAudio();
    Navigator.pop(context);
  }

  // ── Tap zone handler — gated by narration state ───────────────────────────

  void _onTapZone(bool isRight) {
    _wakeChrome();
    if (!_tapZonesArmed) return; // narration still playing, ignore
    if (isRight) {
      _goNext();
    } else {
      _goPrev();
    }
  }

  // ── Swipe handlers — threshold-based, with small in-flight tilt ───────────

  void _onPanUpdate(DragUpdateDetails d) {
    setState(() => _dragDx += d.delta.dx);
  }

  void _onPanEnd(DragEndDetails d) {
    final width = MediaQuery.of(context).size.width;
    final threshold = width * 0.30;
    final velocity = d.velocity.pixelsPerSecond.dx.abs();
    final committed = _dragDx.abs() > threshold || velocity > 800;

    _wakeChrome();
    if (committed) {
      if (_dragDx < 0) {
        _goNext();
      } else {
        _goPrev();
      }
    } else {
      // Snap back
      setState(() => _dragDx = 0.0);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final page = widget.story.pages[_currentPage];
    final content = page.localized(_lang);
    final isFirst = _currentPage == 0;
    final isLast = _currentPage == widget.story.pages.length - 1;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        // Catch all taps to wake chrome (in addition to anything else)
        behavior: HitTestBehavior.translucent,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        child: Stack(
          children: [
            // ── Image (full-bleed, behind everything) ─────────────────────
            Positioned.fill(
              child: AnimatedSwitcher(
                duration: AppDurations.pageTurn,
                transitionBuilder: PageSkewTransition.builder(_lastDirection),
                child: Transform.translate(
                  // Subtle in-flight tilt while dragging; resets on snap-back
                  offset: Offset(_dragDx * 0.15, 0),
                  child: _buildImage(page),
                ),
              ),
            ),

            // ── Tap zones (40% / 20% dead / 40%) ──────────────────────────
            Positioned.fill(
              child: Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () => _onTapZone(false),
                    ),
                  ),
                  const Spacer(flex: 2), // dead center
                  Expanded(
                    flex: 4,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () => _onTapZone(true),
                    ),
                  ),
                ],
              ),
            ),

            // ── Chevron overlays (vertical-centered) ──────────────────────
            Positioned(
              left: 8,
              top: 0,
              bottom: 0,
              child: Center(
                child: _ChevronButton(
                  icon: Icons.chevron_left_rounded,
                  enabled: _chevronsLive && !isFirst,
                  pulse: _chevronPulse,
                  onTap: _goPrev,
                ),
              ),
            ),
            Positioned(
              right: 8,
              top: 0,
              bottom: 0,
              child: Center(
                child: _ChevronButton(
                  icon: Icons.chevron_right_rounded,
                  enabled: _chevronsLive && !isLast,
                  pulse: _chevronPulse,
                  onTap: _goNext,
                ),
              ),
            ),

            // ── Bottom text panel (legibility scrim + caption) ────────────
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _CaptionBar(
                text: content.text,
                pageKey: _currentPage,
                isLast: isLast,
              ),
            ),

            // ── Chrome (top bar) — auto-dims after 5s ─────────────────────
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: AnimatedOpacity(
                  duration: AppDurations.chromeFade,
                  opacity: _chromeVisible ? 1.0 : 0.4,
                  child: _TopChrome(
                    pageNumber: _currentPage + 1,
                    pageCount: widget.story.pages.length,
                    narrationEnabled: _narrationEnabled,
                    audioLoading: _audioLoading,
                    onHome: _goHome,
                    onToggleNarration: _toggleNarration,
                    chapterIndexBuilder: _buildChapterIndexButton,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Image (asset / network) ───────────────────────────────────────────────

  Widget _buildImage(StoryPage page) {
    final hero = Hero(
      tag: _currentPage == widget.initialPage
          ? storyHeroTag(widget.story.id)
          : 'page-${widget.story.id}-$_currentPage',
      child: widget.story.meta.isBundled
          ? Image.asset(
              widget.service.resolveAssetPath(page.imagePath),
              key: ValueKey(_currentPage),
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (_, __, ___) => _imageFallback(),
            )
          : CachedNetworkImage(
              imageUrl: widget.service.resolveUrl(page.imagePath),
              key: ValueKey(_currentPage),
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              placeholder: (_, __) => Container(color: AppColors.dusk),
              errorWidget: (_, __, ___) => _imageFallback(),
            ),
    );
    return hero;
  }

  Widget _imageFallback() {
    return Container(
      color: AppColors.dusk,
      child: const Center(
        child:
            Icon(Icons.image_not_supported, color: Colors.white38, size: 48),
      ),
    );
  }

  // ── Chapter index button — wrapped in OpenContainer for the morph ─────────

  Widget _buildChapterIndexButton(BuildContext context) {
    return OpenContainer(
      transitionType: ContainerTransitionType.fadeThrough,
      transitionDuration: const Duration(milliseconds: 450),
      openColor: AppColors.dusk,
      closedColor: Colors.transparent,
      closedElevation: 0,
      openElevation: 0,
      closedShape: const CircleBorder(),
      closedBuilder: (context, openContainer) {
        return _ChromeButton(
          icon: Icons.grid_view_rounded,
          tooltip: 'Pages',
          onTap: () {
            _wakeChrome();
            openContainer();
          },
        );
      },
      openBuilder: (context, closeContainer) {
        return ChapterIndexSheet(
          story: widget.story,
          currentPage: _currentPage,
          service: widget.service,
          onSelect: (i) {
            _pendingJumpPage = i;
            closeContainer();
          },
          onClose: closeContainer,
        );
      },
      onClosed: (_) {
        if (_pendingJumpPage != null && mounted) {
          final target = _pendingJumpPage!;
          _pendingJumpPage = null;
          final dir = target > _currentPage
              ? PageTurnDirection.forward
              : PageTurnDirection.backward;
          _goToPage(target, dir);
        }
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Chevron button — pulses on activation, dim when inert
// ─────────────────────────────────────────────────────────────────────────────

class _ChevronButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final AnimationController pulse;
  final VoidCallback onTap;

  const _ChevronButton({
    required this.icon,
    required this.enabled,
    required this.pulse,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulse,
      builder: (context, _) {
        final pulseValue = pulse.value;
        // Single soft pulse on activation: 1.0 → 1.15 → 1.0
        final scale = 1.0 + 0.15 * (pulseValue * (1 - pulseValue) * 4);
        return Transform.scale(
          scale: scale,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: enabled ? 1.0 : 0.0,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: enabled ? onTap : null,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Icon(icon, color: Colors.white, size: 36),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Top chrome — home / page pill / chapter index / narration toggle
// ─────────────────────────────────────────────────────────────────────────────

class _TopChrome extends StatelessWidget {
  final int pageNumber;
  final int pageCount;
  final bool narrationEnabled;
  final bool audioLoading;
  final VoidCallback onHome;
  final VoidCallback onToggleNarration;
  final WidgetBuilder chapterIndexBuilder;

  const _TopChrome({
    required this.pageNumber,
    required this.pageCount,
    required this.narrationEnabled,
    required this.audioLoading,
    required this.onHome,
    required this.onToggleNarration,
    required this.chapterIndexBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Row(
        children: [
          _ChromeButton(
            icon: Icons.home_rounded,
            tooltip: 'Library',
            onTap: onHome,
          ),
          const SizedBox(width: 10),
          _PagePill(current: pageNumber, total: pageCount),
          const Spacer(),
          if (audioLoading)
            const Padding(
              padding: EdgeInsets.only(right: 10),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            ),
          _ChromeButton(
            icon: narrationEnabled
                ? Icons.volume_up_rounded
                : Icons.volume_off_rounded,
            tooltip: narrationEnabled ? 'Mute narration' : 'Unmute narration',
            highlight: narrationEnabled,
            onTap: onToggleNarration,
          ),
          const SizedBox(width: 10),
          chapterIndexBuilder(context),
        ],
      ),
    );
  }
}

// Chrome button — circular pill with soft drop shadow for legibility against
// any image background.

class _ChromeButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool highlight;
  final VoidCallback onTap;

  const _ChromeButton({
    required this.icon,
    required this.tooltip,
    this.highlight = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.25),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(
              icon,
              color: highlight ? AppColors.accent : AppColors.accentDark,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }
}

// Page pill — "1/44" style, sits next to the home button

class _PagePill extends StatelessWidget {
  final int current;
  final int total;
  const _PagePill({required this.current, required this.total});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        '$current / $total',
        style: const TextStyle(
          color: AppColors.accentDark,
          fontWeight: FontWeight.bold,
          fontFamily: 'Georgia',
          fontSize: 15,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Caption bar — bottom-anchored text panel
// ─────────────────────────────────────────────────────────────────────────────

class _CaptionBar extends StatelessWidget {
  final String text;
  final int pageKey;
  final bool isLast;

  const _CaptionBar({
    required this.text,
    required this.pageKey,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(60, 0, 60, 16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
          decoration: BoxDecoration(
            color: AppColors.cream,
            borderRadius: BorderRadius.circular(AppRadius.card),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            child: Column(
              key: ValueKey(pageKey),
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 17,
                    height: 1.5,
                    color: AppColors.ink,
                    fontFamily: 'Georgia',
                  ),
                ),
                if (isLast) ...[
                  const SizedBox(height: 8),
                  const Text(
                    '🌟 The End',
                    style: TextStyle(
                      color: AppColors.warmGold,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
