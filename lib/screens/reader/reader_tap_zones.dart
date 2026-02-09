import 'package:flutter/material.dart';

const bool kShowReaderTapZones = false;

class ReaderTapZones extends StatefulWidget {
  const ReaderTapZones({
    super.key,
    required this.child,
    this.onTapLeft,
    this.onTapCenter,
    this.onTapRight,
    this.sideFraction = 0.15,
    this.showOverlay = kShowReaderTapZones,
  });

  final Widget child;
  final VoidCallback? onTapLeft;
  final VoidCallback? onTapCenter;
  final VoidCallback? onTapRight;
  final double sideFraction;
  final bool showOverlay;

  @override
  State<ReaderTapZones> createState() => _ReaderTapZonesState();
}

class _ReaderTapZonesState extends State<ReaderTapZones> {
  Offset? _tapDownPosition;
  DateTime? _tapDownTime;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        _tapDownPosition = event.position;
        _tapDownTime = DateTime.now();
      },
      onPointerUp: (event) {
        _handleTap(event.position);
      },
      child: Stack(
        children: [
          widget.child,
          if (widget.showOverlay)
            const IgnorePointer(
              child: _ReaderTapZoneOverlay(),
            ),
        ],
      ),
    );
  }

  void _handleTap(Offset upPosition) {
    final downPosition = _tapDownPosition;
    final downTime = _tapDownTime;
    _tapDownPosition = null;
    _tapDownTime = null;
    if (downPosition == null || downTime == null) return;
    final distance = (upPosition - downPosition).distance;
    final elapsed = DateTime.now().difference(downTime);
    if (distance > 12 || elapsed.inMilliseconds > 280) return;

    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(upPosition);
    final width = box.size.width;
    if (width <= 0) return;

    final leftEdge = width * widget.sideFraction;
    final rightEdge = width * (1 - widget.sideFraction);
    if (local.dx < leftEdge) {
      widget.onTapLeft?.call();
    } else if (local.dx > rightEdge) {
      widget.onTapRight?.call();
    } else {
      widget.onTapCenter?.call();
    }
  }
}

class _ReaderTapZoneOverlay extends StatelessWidget {
  const _ReaderTapZoneOverlay();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.labelLarge?.copyWith(
      color: Colors.white.withOpacity(0.85),
      fontWeight: FontWeight.w600,
    );
    return Row(
      children: [
        Expanded(
          flex: 15,
          child: _ZoneBlock(
            color: Colors.red.withOpacity(0.12),
            label: '15%',
            labelStyle: labelStyle,
          ),
        ),
        Expanded(
          flex: 70,
          child: _ZoneBlock(
            color: Colors.green.withOpacity(0.10),
            label: '70%',
            labelStyle: labelStyle,
          ),
        ),
        Expanded(
          flex: 15,
          child: _ZoneBlock(
            color: Colors.blue.withOpacity(0.12),
            label: '15%',
            labelStyle: labelStyle,
          ),
        ),
      ],
    );
  }
}

class _ZoneBlock extends StatelessWidget {
  const _ZoneBlock({
    required this.color,
    required this.label,
    required this.labelStyle,
  });

  final Color color;
  final String label;
  final TextStyle? labelStyle;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        border: Border(
          right: BorderSide(
            color: Colors.white.withOpacity(0.22),
            width: 1,
          ),
        ),
      ),
      alignment: Alignment.center,
      child: Text(label, style: labelStyle),
    );
  }
}
