import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Shared SnackBar helper so every failure/success message across the app
/// gets the same, readable duration instead of Flutter's easy-to-miss
/// default, and so a rapid second message cleanly replaces the first
/// instead of the two overlapping/fighting for the same slot.
class AppSnackbar {
  static const Duration _duration = Duration(seconds: 5);

  static void showError(BuildContext context, String message) {
    _show(context, message, AppTheme.danger);
  }

  static void showSuccess(BuildContext context, String message) {
    _show(context, message, AppTheme.secondary);
  }

  static void showInfo(BuildContext context, String message, {Color? color}) {
    _show(context, message, color ?? Colors.grey.shade700);
  }

  static void _show(BuildContext context, String message, Color backgroundColor) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: backgroundColor,
      duration: _duration,
    ));
  }
}
