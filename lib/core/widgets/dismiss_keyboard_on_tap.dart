import 'package:flutter/material.dart';

/// Wraps [child] so a tap anywhere that isn't already claimed by a more
/// specific gesture (a TextField requesting focus, a button's InkWell, ...)
/// dismisses the on-screen keyboard.
///
/// Android does this implicitly for any tap outside the focused field; iOS
/// does not, so without this a delegate/admin stuck with the keyboard open
/// over a form has no way to reach the bottom nav short of force-closing the
/// app. `HitTestBehavior.opaque` is what makes it fire on blank space that
/// has no widget of its own to hit-test against (empty Padding/SizedBox
/// gaps, the tail of a Column, ...) rather than only on painted content.
///
/// Mounted once in [AlKhairApp]'s [MaterialApp.builder], wrapping every
/// route the root [Navigator] shows — including bottom sheets and dialogs,
/// since those are pushed through that same Navigator's Overlay. A tap
/// lands here (and unfocuses) only once it has already fallen through
/// every descendant that would otherwise have claimed it, which is exactly
/// why this is safe to mount once at the root instead of once per Scaffold:
///   - a tap on a TextField/button is won by that widget's own recognizer
///     first, so this callback never fires and never fights it;
///   - a tap on blank space *inside* a bottom sheet/dialog still hits this
///     detector (the sheet/dialog content is a descendant of it), so the
///     keyboard is dismissed without the tap ever reaching the modal
///     barrier behind the sheet — the sheet itself stays open;
///   - a tap on the modal barrier itself (outside the sheet/dialog) is
///     unaffected — that's a separate widget lower in the stack and still
///     dismisses the sheet exactly as before.
class DismissKeyboardOnTap extends StatelessWidget {
  final Widget child;
  const DismissKeyboardOnTap({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.opaque,
      child: child,
    );
  }
}
