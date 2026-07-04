import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Shared friendly error state: icon + message + retry button.
/// [danger] controls styling — pass false for calm/neutral states that
/// aren't really errors (e.g. "no active shipment right now").
class AppErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final String title;
  final bool danger;

  const AppErrorView({
    super.key,
    required this.message,
    required this.onRetry,
    this.title = 'تعذر تحميل البيانات',
    this.danger = true,
  });

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppTheme.danger : Colors.grey.shade600;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                danger ? Icons.cloud_off_rounded : Icons.info_outline_rounded,
                size: 56,
                color: color,
              ),
            ),
            const SizedBox(height: 16),
            Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: Colors.black87)),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shimmering placeholder box for loading states, instead of a blank screen.
class AppSkeletonBox extends StatefulWidget {
  final double height;
  final double? width;
  final double borderRadius;

  const AppSkeletonBox({
    super.key,
    this.height = 16,
    this.width,
    this.borderRadius = 8,
  });

  @override
  State<AppSkeletonBox> createState() => _AppSkeletonBoxState();
}

class _AppSkeletonBoxState extends State<AppSkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);
  late final Animation<double> _opacity =
      Tween<double>(begin: 0.4, end: 1.0).animate(
    CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _opacity,
        child: Container(
          height: widget.height,
          width: widget.width,
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(widget.borderRadius),
          ),
        ),
      );
}
