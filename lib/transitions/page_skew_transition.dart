// lib/transitions/page_skew_transition.dart
//
// Tier 2 page-turn transition: horizontal slide + perspective skew + soft
// scale. Reads as "the page is folding away" without the GPU/maintenance
// cost of a real shader-based curl. Honors MediaQuery.disableAnimations
// (reduce-motion) by collapsing to a plain crossfade.
//
// Usage:
//   AnimatedSwitcher(
//     duration: AppDurations.pageTurn,
//     transitionBuilder: PageSkewTransition.builder(direction),
//     child: ...keyed widget per page,
//   )

import 'package:flutter/material.dart';

enum PageTurnDirection { forward, backward }

class PageSkewTransition {
  PageSkewTransition._();

  /// Returns an AnimatedSwitcher transitionBuilder that produces a
  /// directional page-turn effect. Pass the *current* direction at the
  /// time the AnimatedSwitcher rebuilds.
  static AnimatedSwitcherTransitionBuilder builder(
    PageTurnDirection direction,
  ) {
    return (Widget child, Animation<double> animation) {
      return _SkewSlide(
        animation: animation,
        direction: direction,
        child: child,
      );
    };
  }
}

class _SkewSlide extends StatelessWidget {
  final Animation<double> animation;
  final PageTurnDirection direction;
  final Widget child;

  const _SkewSlide({
    required this.animation,
    required this.direction,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (reduceMotion) {
      return FadeTransition(opacity: animation, child: child);
    }

    // The animation runs 0→1 for entering pages. AnimatedSwitcher reverses
    // it for exiting pages (1→0), so the same builder handles both ends.
    final isEntering = animation.status == AnimationStatus.forward ||
        animation.status == AnimationStatus.completed;

    final dirSign = direction == PageTurnDirection.forward ? 1.0 : -1.0;

    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = animation.value; // 0..1
        // Slide: entering page comes in from +/-x, exiting page leaves to -/+x
        final slideX = isEntering ? (1.0 - t) * dirSign : -t * dirSign;
        // Skew: small perspective fold on the outgoing edge
        final skewY = isEntering ? -(1.0 - t) * 0.12 * dirSign : t * 0.12 * dirSign;
        // Scale: subtle depth cue
        final scale = isEntering ? 0.96 + 0.04 * t : 1.0 - 0.04 * t;

        // Build a perspective transform matrix with a small skew on Y.
        final m = Matrix4.identity()
          ..setEntry(3, 2, 0.0008) // perspective
          ..translate(slideX * MediaQuery.of(context).size.width * 0.6)
          ..scale(scale, scale)
          ..rotateY(skewY);

        return Transform(
          transform: m,
          alignment: direction == PageTurnDirection.forward
              ? Alignment.centerLeft
              : Alignment.centerRight,
          child: Opacity(
            opacity: isEntering ? t.clamp(0.0, 1.0) : (1.0 - t).clamp(0.0, 1.0),
            child: child,
          ),
        );
      },
    );
  }
}
