// lib/widgets/book_spine_card.dart
//
// The redesigned story card. Three things distinguish it from a generic
// rounded image card:
//  1. Right-edge "page edges" gradient — the book-spine affordance
//  2. Press-down feedback choreographed through a single controller
//     (scale 1.0→1.05, shadow blur 12→24, top highlight 0→5%)
//  3. The cover image is wrapped in a Hero with a deterministic tag, so
//     the transition into the reader is anchored on the artwork itself

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../main.dart' show AppColors, AppRadius, AppDurations;
import '../models/story.dart';
import '../services/story_service.dart';

/// Deterministic Hero tag so the home screen and reader screen agree
/// without passing a tag explicitly.
String storyHeroTag(String storyId) => 'cover-$storyId';

class BookSpineCard extends StatefulWidget {
  final StoryMeta meta;
  final String selectedLanguage;
  final String searchQuery;
  final StoryService service;
  final VoidCallback onTap;

  /// If non-null, an "X MB" overlay is shown over the cover before download.
  /// Pass null for bundled stories or once the story has been downloaded.
  final int? downloadSizeMB;

  const BookSpineCard({
    super.key,
    required this.meta,
    required this.selectedLanguage,
    required this.searchQuery,
    required this.service,
    required this.onTap,
    this.downloadSizeMB,
  });

  @override
  State<BookSpineCard> createState() => _BookSpineCardState();
}

class _BookSpineCardState extends State<BookSpineCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press;

  @override
  void initState() {
    super.initState();
    _press = AnimationController(
      vsync: this,
      duration: AppDurations.press,
    );
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  void _setPressed(bool down) {
    if (down) {
      _press.forward();
    } else {
      _press.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _press,
        builder: (context, child) {
          final t = _press.value; // 0..1
          final scale = 1.0 + 0.05 * t;
          final shadowBlur = 12.0 + 12.0 * t;
          final shadowOpacity = 0.18 + 0.17 * t;

          return Transform.scale(
            scale: scale,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.card),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(shadowOpacity),
                    blurRadius: shadowBlur,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: child,
            ),
          );
        },
        child: Hero(
          tag: storyHeroTag(widget.meta.id),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.card),
            child: Stack(
              fit: StackFit.expand,
              children: [
                _buildCover(),
                _buildPageEdgeOverlay(),
                _buildPressHighlight(),
                _buildBottomScrim(),
                _buildTitleAndChips(),
                _buildBadge(),
                if (widget.downloadSizeMB != null) _buildDownloadOverlay(),
                if (!widget.meta.isFree) _buildLockTint(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Cover (asset or network) ──────────────────────────────────────────────

  Widget _buildCover() {
    if (widget.meta.isBundled) {
      return Image.asset(
        widget.service.resolveAssetPath(widget.meta.coverPath),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _coverFallback(),
      );
    }
    return CachedNetworkImage(
      imageUrl: widget.service.resolveUrl(widget.meta.coverPath),
      fit: BoxFit.cover,
      placeholder: (_, __) => Container(
        color: AppColors.creamShade,
        alignment: Alignment.center,
        child: const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.accent,
          ),
        ),
      ),
      errorWidget: (_, __, ___) => _coverFallback(),
    );
  }

  Widget _coverFallback() {
    return Container(
      color: AppColors.accent,
      alignment: Alignment.center,
      child: const Icon(Icons.menu_book_rounded,
          size: 48, color: Colors.white70),
    );
  }

  // ── Right-edge "pages" — the book-spine trick ─────────────────────────────
  // A narrow strip on the right with a light/dark gradient to suggest
  // stacked page edges. Costs nothing, sells the metaphor.

  Widget _buildPageEdgeOverlay() {
    return Positioned(
      right: 0,
      top: 0,
      bottom: 0,
      width: 10,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Colors.black.withOpacity(0.0),
                Colors.black.withOpacity(0.25),
                Colors.white.withOpacity(0.55),
                Colors.black.withOpacity(0.35),
              ],
              stops: const [0.0, 0.25, 0.65, 1.0],
            ),
          ),
        ),
      ),
    );
  }

  // ── Press feedback: subtle top highlight ──────────────────────────────────

  Widget _buildPressHighlight() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: 60,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _press,
          builder: (context, _) => DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withOpacity(0.05 * _press.value),
                  Colors.white.withOpacity(0.0),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Bottom dark gradient for title legibility ─────────────────────────────

  Widget _buildBottomScrim() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      height: 110,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.black.withOpacity(0.78),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Title and tag chips ───────────────────────────────────────────────────

  Widget _buildTitleAndChips() {
    return Positioned(
      bottom: 12,
      left: 14,
      right: 50,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.meta.localizedTitle(widget.selectedLanguage),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.bold,
              fontFamily: 'Georgia',
              shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              _Chip('${widget.meta.ageMin}–${widget.meta.ageMax}'),
              const SizedBox(width: 6),
              ...widget.meta.tags.take(2).map((tag) => Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _Chip(
                      tag,
                      highlight: widget.searchQuery.isNotEmpty &&
                          tag.toLowerCase().contains(
                              widget.searchQuery.toLowerCase()),
                    ),
                  )),
            ],
          ),
        ],
      ),
    );
  }

  // ── Free badge or lock glyph (right-side, top) ────────────────────────────
  // Softer than a green FREE badge — locked stories get a tiny lock,
  // free ones get nothing on the badge slot (cleaner; the absence of a
  // lock signals "available").

  Widget _buildBadge() {
    if (widget.meta.isFree) return const SizedBox.shrink();
    return Positioned(
      top: 10,
      right: 10,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: const Icon(Icons.lock_rounded,
            color: Colors.white70, size: 14),
      ),
    );
  }

  // ── Subtle desaturation tint for locked covers ────────────────────────────

  Widget _buildLockTint() {
    return Positioned.fill(
      child: IgnorePointer(
        child: ColoredBox(color: Colors.black.withOpacity(0.18)),
      ),
    );
  }

  // ── Download-size overlay (peq cuentos pattern) ───────────────────────────

  Widget _buildDownloadOverlay() {
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          color: Colors.black.withOpacity(0.35),
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(
                  color: Colors.white24,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.arrow_downward_rounded,
                    color: Colors.white, size: 28),
              ),
              const SizedBox(height: 8),
              Text(
                '${widget.downloadSizeMB} MB',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  letterSpacing: 0.5,
                  shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
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

class _Chip extends StatelessWidget {
  final String label;
  final bool highlight;
  const _Chip(this.label, {this.highlight = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: highlight ? AppColors.accent : Colors.white24,
        borderRadius: BorderRadius.circular(AppRadius.pill),
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
