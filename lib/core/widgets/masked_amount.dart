import 'package:flutter/material.dart';
import '../security/sensitive_reveal_controller.dart';

/// Placeholder shown in place of a masked figure.
const String kMaskedAmountText = '••••••';

/// Tells the user what happened after a reveal attempt. Nothing for
/// success/cancel/"already open"; a dialog (not a fleeting snackbar) for the
/// no-screen-lock case since it's a security notice they should actually read.
Future<void> requestRevealWithFeedback(BuildContext context, SensitiveRevealController controller) async {
  final messenger = ScaffoldMessenger.of(context);
  final result = await controller.requestReveal();
  if (!context.mounted) return;

  switch (result) {
    case RevealResult.revealed:
    case RevealResult.canceled:
    case RevealResult.ignored:
      return;
    case RevealResult.revealedUnprotected:
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('جهازك غير محمي بقفل'),
          content: const Text(
            'لا يوجد على هذا الجهاز بصمة أو Face ID أو رمز قفل للشاشة، لذلك تم عرض المبلغ بدون تحقق. '
            'ننصحك بتفعيل قفل الشاشة من إعدادات الجهاز لحماية مستحقاتك.',
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('حسنًا'))],
        ),
      );
    case RevealResult.denied:
      messenger.showSnackBar(const SnackBar(content: Text('لم يتم التحقق من هويتك. حاول مرة أخرى.')));
    case RevealResult.lockedOut:
      messenger.showSnackBar(const SnackBar(
        content: Text('تم إيقاف التحقق مؤقتًا بسبب كثرة المحاولات. حاول لاحقًا أو افتح قفل الجهاز أولًا.'),
      ));
    case RevealResult.error:
      messenger.showSnackBar(const SnackBar(content: Text('تعذر التحقق من هويتك الآن. حاول مرة أخرى.')));
  }
}

/// Lock / unlock icon: locked → tapping asks for biometric/PIN; revealed →
/// tapping re-masks immediately.
class RevealLockButton extends StatelessWidget {
  final SensitiveRevealController controller;
  final Color? color;
  final double size;
  const RevealLockButton({super.key, required this.controller, this.color, this.size = 22});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (controller.isAuthenticating) {
          return SizedBox(
            width: size,
            height: size,
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            ),
          );
        }
        final revealed = controller.isRevealed;
        return IconButton(
          key: const ValueKey('reveal-lock-button'),
          icon: Icon(revealed ? Icons.lock_open_rounded : Icons.lock_rounded, color: color, size: size),
          tooltip: revealed ? 'إخفاء' : 'إظهار (يتطلب التحقق)',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          onPressed: () => revealed ? controller.lock() : requestRevealWithFeedback(context, controller),
        );
      },
    );
  }
}

/// A money/quantity figure that renders [text] only while [controller] is
/// revealed, and [kMaskedAmountText] otherwise. Tapping the masked text also
/// starts the reveal, not just the lock icon.
class MaskedAmount extends StatelessWidget {
  final SensitiveRevealController controller;
  final String text;
  final TextStyle? style;

  /// Style while masked. Pass a neutral one when [style] carries a
  /// positive/negative colour — that colour would leak the figure's sign.
  final TextStyle? maskedStyle;
  const MaskedAmount({super.key, required this.controller, required this.text, this.style, this.maskedStyle});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (controller.isRevealed) return Text(text, style: style);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => requestRevealWithFeedback(context, controller),
          child: Text(kMaskedAmountText, style: maskedStyle ?? style),
        );
      },
    );
  }
}
