// lib/widgets/chapter_index_sheet.dart
//
// The chapter index — modal grid of page thumbnails. Tap a thumbnail to
// jump to that page. Current page is marked with a numbered ribbon and
// a stronger border. Adjacent pages cascade in with a 50ms stagger when
// the sheet opens.
//
// The expand-from-button morph is wired in home/story_screen via the
// `animations` package's OpenContainer; this widget is the destination.
//
// Honors reduce-motion: cascade collapses to a single fade.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../main.dart' show AppColors, AppRadius;
import '../models/story.dart';
import '../services/story_service.dart';

class ChapterIndexSheet extends StatefulWidget {
  final Story story;
  final int currentPage;
  final StoryService service;
  final void Function(int pageIndex) onSelect;
  final VoidCallback onClose;

  const ChapterIndexSheet({
    super.key,
    required this.story,
    required this.currentPage,
    required this.service,
    required this.onSelect,
    required this.onClose,
  });

  @override
  State<ChapterIndexSheet> createState() => _ChapterIndexSheetState();
}

class _ChapterIndexSheetState extends State<ChapterIndexSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _cascade;

  @override
  void initState() {
    super.initState();
    _cascade = AnimationController(
      vsync: this,
      duration: Duration(
        milliseconds: 250 + 50 * widget.story.pages.length.clamp(0, 12),
      ),
    )..forward();
  }

  @override
  void dispose() {
    _cascade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final size = MediaQuery.of(context).size;
    final isTablet = size.shortestSide >= 600;
    final cols = isTablet ? 4 : 3;

    return Material(
      color: AppColors.dusk.withOpacity(0.92),
      child: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(60, 16, 60, 16),
              child: GridView.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  childAspectRatio: 16 / 9,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                ),
                itemCount: widget.story.pages.length,
                itemBuilder: (context, i) => _buildThumb(i, reduceMotion),
              ),
            ),
            // Close button (top-left, matches peq cuentos pattern)
            Positioned(
              top: 8,
              left: 8,
              child: _CloseButton(onTap: widget.onClose),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThumb(int i, bool reduceMotion) {
    final page = widget.story.pages[i];
    final isCurrent = i == widget.currentPage;

    final start = (i / widget.story.pages.length).clamp(0.0, 0.7);
    final end = (start + 0.4).clamp(0.0, 1.0);
    final cascadeAnim = reduceMotion
        ? const AlwaysStoppedAnimation(1.0)
        : CurvedAnimation(
            parent: _cascade,
            curve: Interval(start, end, curve: Curves.easeOut),
          );

    return AnimatedBuilder(
      animation: cascadeAnim,
      builder: (context, child) {
        return Opacity(
          opacity: cascadeAnim.value,
          child: Transform.translate(
            offset: Offset(0, (1 - cascadeAnim.value) * 12),
            child: Transform.scale(
              scale: 0.94 + 0.06 * cascadeAnim.value,
              child: child,
            ),
          ),
        );
      },
      child: GestureDetector(
        onTap: () => widget.onSelect(i),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.card * 0.6),
              child: _buildThumbImage(page),
            ),
            if (!isCurrent)
              Positioned.fill(
                child: IgnorePointer(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.card * 0.6),
                    child: ColoredBox(color: Colors.black.withOpacity(0.45)),
                  ),
                ),
              ),
            if (isCurrent)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius:
                          BorderRadius.circular(AppRadius.card * 0.6),
                      border: Border.all(color: Colors.white, width: 3),
                    ),
                  ),
                ),
              ),
            // Numbered ribbon (top-left)
            Positioned(top: 0, left: 8, child: _Ribbon(number: i + 1)),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbImage(StoryPage page) {
    if (widget.story.meta.isBundled) {
      return Image.asset(
        widget.service.resolveAssetPath(page.imagePath),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _imageFallback(),
      );
    }
    return CachedNetworkImage(
      imageUrl: widget.service.resolveUrl(page.imagePath),
      fit: BoxFit.cover,
      placeholder: (_, __) => Container(color: AppColors.dusk),
      errorWidget: (_, __, ___) => _imageFallback(),
    );
  }

  Widget _imageFallback() {
    return Container(color: AppColors.dusk);
  }
}

// ── Ribbon ──────────────────────────────────────────────────────────────────

class _Ribbon extends StatelessWidget {
  final int number;
  const _Ribbon({required this.number});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: const BoxDecoration(
        color: AppColors.accent,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(2),
          bottomRight: Radius.circular(2),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Text(
          '$number',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 13,
            fontFamily: 'Georgia',
          ),
        ),
      ),
    );
  }
}

// ── Close button ────────────────────────────────────────────────────────────

class _CloseButton extends StatelessWidget {
  final VoidCallback onTap;
  const _CloseButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: Container(
          width: 44,
          height: 44,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.close_rounded,
              color: AppColors.accent, size: 24),
        ),
      ),
    );
  }
}
