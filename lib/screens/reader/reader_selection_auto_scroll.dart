import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class ReaderSelectionAutoScroll extends StatefulWidget {
  const ReaderSelectionAutoScroll({
    super.key,
    required this.child,
    required this.controller,
    required this.selectionActive,
    this.edgeExtent = 36,
  });

  final Widget child;
  final ScrollController? controller;
  final ValueListenable<bool> selectionActive;
  final double edgeExtent;

  @override
  State<ReaderSelectionAutoScroll> createState() =>
      _ReaderSelectionAutoScrollState();
}

class _ReaderSelectionAutoScrollState extends State<ReaderSelectionAutoScroll> {
  Timer? _scrollTimer;
  int? _activePointer;
  Offset? _lastPosition;
  double _scrollDelta = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.pointerRouter.addGlobalRoute(_handlePointerEvent);
    widget.selectionActive.addListener(_handleSelectionActiveChanged);
  }

  @override
  void didUpdateWidget(covariant ReaderSelectionAutoScroll oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectionActive != widget.selectionActive) {
      oldWidget.selectionActive.removeListener(_handleSelectionActiveChanged);
      widget.selectionActive.addListener(_handleSelectionActiveChanged);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.pointerRouter.removeGlobalRoute(_handlePointerEvent);
    widget.selectionActive.removeListener(_handleSelectionActiveChanged);
    _stopAutoScroll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }

  void _handleSelectionActiveChanged() {
    if (!widget.selectionActive.value) {
      _stopAutoScroll();
    }
  }

  void _handlePointerEvent(PointerEvent event) {
    if (!mounted) return;
    if (event is PointerDownEvent) {
      _activePointer = event.pointer;
      _lastPosition = event.position;
      _maybeUpdateScroll(event.position);
      return;
    }
    if (event.pointer != _activePointer) return;
    if (event is PointerMoveEvent) {
      _lastPosition = event.position;
      _maybeUpdateScroll(event.position);
      return;
    }
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      _activePointer = null;
      _lastPosition = null;
      _stopAutoScroll();
    }
  }

  void _maybeUpdateScroll(Offset globalPosition) {
    if (!widget.selectionActive.value) {
      _stopAutoScroll();
      return;
    }
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(globalPosition);
    final size = box.size;
    if (local.dx < 0 || local.dx > size.width) {
      _stopAutoScroll();
      return;
    }

    final edge = widget.edgeExtent;
    double? delta;
    if (local.dy < edge) {
      final factor = ((edge - local.dy) / edge).clamp(0.0, 1.0);
      delta = -_scrollSpeedFor(factor);
    } else if (local.dy > size.height - edge) {
      final factor =
          ((local.dy - (size.height - edge)) / edge).clamp(0.0, 1.0);
      delta = _scrollSpeedFor(factor);
    }

    if (delta == null || delta == 0) {
      _stopAutoScroll();
      return;
    }
    _scrollDelta = delta;
    _startAutoScroll();
  }

  double _scrollSpeedFor(double factor) {
    const minSpeed = 3.0;
    const maxSpeed = 16.0;
    return minSpeed + (maxSpeed - minSpeed) * factor;
  }

  void _startAutoScroll() {
    if (_scrollTimer != null) return;
    _scrollTimer = Timer.periodic(
      const Duration(milliseconds: 16),
      (_) => _tickAutoScroll(),
    );
  }

  void _stopAutoScroll() {
    _scrollTimer?.cancel();
    _scrollTimer = null;
  }

  void _tickAutoScroll() {
    final controller = widget.controller;
    if (controller == null || !controller.hasClients) return;
    final max = controller.position.maxScrollExtent;
    final min = controller.position.minScrollExtent;
    final current = controller.offset;
    final next = (current + _scrollDelta).clamp(min, max);
    if (next == current) {
      _stopAutoScroll();
      return;
    }
    controller.jumpTo(next);
  }
}
