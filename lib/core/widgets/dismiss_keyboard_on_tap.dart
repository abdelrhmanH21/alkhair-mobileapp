import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Closes the keyboard (unfocuses the text field) on any tap that doesn't
/// land on an editable text field — anywhere in the app, including inside
/// scroll views, cards, list tiles, bottom sheets and dialogs.
///
/// Why the previous version (a root GestureDetector.onTap) didn't work on
/// real devices although its widget tests passed: a GestureDetector only
/// fires if its TapGestureRecognizer WINS the gesture arena, and on real
/// screens it rarely did:
///  1. Any tappable widget under the finger (Card/InkWell, ListTile,
///     buttons, dropdowns — most of every delegate/admin screen) has its
///     own tap recognizer, which wins; the root onTap never runs.
///  2. Inside a scroll view, a real finger moves a few pixels during a tap.
///     Android reports its own touch slop (~8 dp) to Flutter, so the
///     scrollable's drag recognizer accepts after 8 dp while the tap
///     recognizer tolerates 18 dp: a normal 8–18 dp wobble is a "drag",
///     and the tap is lost. Widget tests use the 18 dp default for both
///     and a zero-movement tap, so they never hit this.
///
/// This version listens to raw pointer events with a [Listener], which
/// sees every pointer regardless of who wins the arena, and treats
/// down→up within [kTouchSlop] and [kLongPressTimeout] as a tap. On such a
/// tap it unfocuses — unless the tap hit an editable text field (that
/// field takes focus itself), the focused field has a text selection (so
/// selecting/copying keeps working), or the tap hit a [KeepKeyboardOnTap]
/// area. Nothing is consumed: buttons still fire,
/// scrolling still scrolls, and text selection is untouched.
///
/// Mounted once at the root (AlKhairApp's MaterialApp.builder), so it also
/// covers every route, bottom sheet and dialog.
class DismissKeyboardOnTap extends StatefulWidget {
  final Widget child;
  const DismissKeyboardOnTap({super.key, required this.child});

  @override
  State<DismissKeyboardOnTap> createState() => _DismissKeyboardOnTapState();
}

class _DismissKeyboardOnTapState extends State<DismissKeyboardOnTap> {
  int? _pointer;
  Offset _downPosition = Offset.zero;
  bool _isTap = false;
  // Held past kLongPressTimeout → a long press, not a tap. A timer rather
  // than event timestamps, which synthetic/injected events may leave at 0.
  Timer? _longPressTimer;

  @override
  void dispose() {
    _longPressTimer?.cancel();
    super.dispose();
  }

  void _onDown(PointerDownEvent e) {
    if (_pointer != null) {
      // A second finger: this is a pinch/multi-touch, not a tap.
      _isTap = false;
      return;
    }
    if (e.kind == PointerDeviceKind.mouse && e.buttons != kPrimaryMouseButton) return;
    _pointer = e.pointer;
    _downPosition = e.position;
    _isTap = true;
    _longPressTimer?.cancel();
    _longPressTimer = Timer(kLongPressTimeout, () => _isTap = false);
  }

  void _onMove(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    if ((e.position - _downPosition).distance > kTouchSlop) _isTap = false;
  }

  void _onUp(PointerUpEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    _longPressTimer?.cancel();
    if (_isTap) _maybeUnfocus(e.position, e.viewId);
  }

  void _onCancel(PointerCancelEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    _longPressTimer?.cancel();
  }

  void _maybeUnfocus(Offset position, int viewId) {
    final focus = FocusManager.instance.primaryFocus;
    final focusContext = focus?.context;
    if (focus == null || focusContext == null) return;
    final editable = focusContext.findAncestorStateOfType<EditableTextState>();
    if (editable == null) return; // only text input owns the keyboard

    // Mid-selection in the focused field (handles + copy toolbar showing):
    // leave it alone — the tap only clears the selection, as usual.
    if (!editable.textEditingValue.selection.isCollapsed) return;

    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(result, position, viewId);
    for (final entry in result.path) {
      final target = entry.target;
      if (target is RenderEditable || target is _RenderKeepKeyboard) return;
    }
    focus.unfocus();
  }

  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _onDown,
        onPointerMove: _onMove,
        onPointerUp: _onUp,
        onPointerCancel: _onCancel,
        child: widget.child,
      );
}

/// Marks an area where a tap must NOT close the keyboard (e.g. the "تم"
/// bar handles that itself, or a control that edits the focused field).
class KeepKeyboardOnTap extends SingleChildRenderObjectWidget {
  const KeepKeyboardOnTap({super.key, super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderKeepKeyboard();
}

class _RenderKeepKeyboard extends RenderProxyBox {}

/// iOS's number / phone pads have no return key, so a numeric field could
/// only be left by tapping elsewhere. While such a field is focused and the
/// keyboard is up, this shows a slim "تم" bar on top of the keyboard. The
/// app content is told the keyboard is that much taller (viewInsets), so
/// the bar never covers the focused field. Android number pads have their
/// own done key, so it is iOS-only.
class NumericKeyboardDoneBar extends StatefulWidget {
  final Widget child;
  const NumericKeyboardDoneBar({super.key, required this.child});

  static const double height = 44;

  @override
  State<NumericKeyboardDoneBar> createState() => _NumericKeyboardDoneBarState();
}

class _NumericKeyboardDoneBarState extends State<NumericKeyboardDoneBar> {
  bool _numericFocused = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_onFocusChanged);
    _numericFocused = _computeNumericFocused();
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocusChanged);
    super.dispose();
  }

  void _onFocusChanged() {
    final value = _computeNumericFocused();
    if (value != _numericFocused && mounted) setState(() => _numericFocused = value);
  }

  static bool _computeNumericFocused() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return false;
    final editable = context.findAncestorWidgetOfExactType<EditableText>();
    if (editable == null || editable.readOnly) return false;
    final index = editable.keyboardType.index;
    return index == TextInputType.number.index || index == TextInputType.phone.index;
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboardUp = media.viewInsets.bottom > 0;
    final show = _numericFocused && keyboardUp && defaultTargetPlatform == TargetPlatform.iOS;
    if (!show) return widget.child;
    return Stack(
      children: [
        MediaQuery(
          data: media.copyWith(
            viewInsets: media.viewInsets.copyWith(bottom: media.viewInsets.bottom + NumericKeyboardDoneBar.height),
          ),
          child: widget.child,
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: media.viewInsets.bottom,
          height: NumericKeyboardDoneBar.height,
          child: KeepKeyboardOnTap(
            child: Material(
              key: const Key('numeric-done-bar'),
              color: const Color(0xFFF1F1F3),
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  onPressed: () => FocusManager.instance.primaryFocus?.unfocus(),
                  child: const Text('تم', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
