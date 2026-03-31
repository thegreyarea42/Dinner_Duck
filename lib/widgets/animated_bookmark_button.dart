import 'package:flutter/material.dart';

/// A button that toggles a bookmark state with a scale animation.
class AnimatedBookmarkButton extends StatefulWidget {
  final bool isBookmarked;
  final VoidCallback onTap;
  const AnimatedBookmarkButton({super.key, required this.isBookmarked, required this.onTap});

  @override
  State<AnimatedBookmarkButton> createState() => _AnimatedBookmarkButtonState();
}

class _AnimatedBookmarkButtonState extends State<AnimatedBookmarkButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: const Duration(milliseconds: 300), vsync: this);
    _scaleAnimation = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.6), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.6, end: 1.0), weight: 50),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.bounceOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool disableMotion = MediaQuery.of(context).disableAnimations;

    return Semantics(
      label: widget.isBookmarked ? 'Remove from cookbook' : 'Save to cookbook',
      button: true,
      child: ScaleTransition(
        scale: disableMotion ? const AlwaysStoppedAnimation(1.0) : _scaleAnimation,
        child: IconButton(
          icon: Icon(
            widget.isBookmarked ? Icons.bookmark : Icons.bookmark_border,
            color: widget.isBookmarked ? Colors.orange : Colors.grey,
            size: 40,
          ),
          onPressed: () {
            if (!disableMotion) _controller.forward(from: 0);
            widget.onTap();
          },
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        ),
      ),
    );
  }
}
