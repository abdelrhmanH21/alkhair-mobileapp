import 'package:flutter/material.dart';
import '../di/service_locator.dart';
import '../theme/app_theme.dart';
import '../utils/connectivity_service.dart';

/// Shared friendly error state: icon + message + retry button.
/// [danger] controls styling — pass false for calm/neutral states that
/// aren't really errors (e.g. "no active shipment right now").
class AppErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final String title;
  final bool danger;
  /// When true, keeps this same error view on screen but shows a small
  /// inline spinner on the retry button instead of the caller blanking the
  /// whole section back to a loading skeleton — avoids a jarring
  /// disappear/reappear flicker when a retry just fails again.
  final bool isRetrying;

  const AppErrorView({
    super.key,
    required this.message,
    required this.onRetry,
    this.title = 'تعذر تحميل البيانات',
    this.danger = true,
    this.isRetrying = false,
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
              onPressed: isRetrying ? null : onRetry,
              icon: isRetrying
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
              label: Text(isRetrying ? 'جاري إعادة المحاولة...' : 'إعادة المحاولة'),
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

/// Calm (never red/danger) top-of-screen notice: "you're offline, what
/// you're looking at might be stale" — for screens that fell back to
/// [OfflineCacheService]'s last-known snapshot because the live refresh
/// failed. Deliberately styled like [AppErrorView]'s `danger: false` calm
/// state (grey icon, muted text, no alarming color) rather than the
/// `danger: true` red — being offline with a real cached answer on screen is
/// an expected, non-broken state, not an error.
///
/// Only rendered while [ConnectivityService] currently reports offline —
/// pass [show] as false once a screen's own fetch has confirmed the
/// currently-displayed data is fresh again, so the banner doesn't linger
/// simply because Wi-Fi happens to be off on an otherwise-idle screen with no
/// cached-fallback data being shown at all.
class OfflineDataBanner extends StatelessWidget {
  final bool show;
  const OfflineDataBanner({super.key, this.show = true});

  @override
  Widget build(BuildContext context) {
    if (!show) return const SizedBox.shrink();
    return StreamBuilder<bool>(
      stream: sl<ConnectivityService>().onStatusChanged,
      initialData: sl<ConnectivityService>().isOnline,
      builder: (context, snapshot) {
        if (snapshot.data ?? true) return const SizedBox.shrink();
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Row(
            children: [
              Icon(Icons.cloud_off_rounded, size: 18, color: Colors.grey.shade600),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'أنت غير متصل بالإنترنت — البيانات المعروضة قد لا تكون محدثة',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
