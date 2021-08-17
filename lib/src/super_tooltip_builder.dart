import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:super_tooltip/src/bubble_shape.dart';
import 'package:super_tooltip/src/close_object.dart';
import 'package:super_tooltip/src/super_tooltip_background.dart';
import 'package:super_tooltip/super_tooltip.dart';

import 'extensions.dart';
import 'models/super_tooltip.model.dart';
import 'pop_up_balloon_layout_delegate.dart';

typedef TipCallback = void Function();

typedef TargetBuilder = Widget Function(BuildContext, ShowHandler, TipCallback);

/// provide the key if you wish to override the default widget context
typedef ShowHandler = void Function({
  OverlayState? overlay,
  GlobalKey? key,
});

class SuperTooltipBuilder extends StatefulWidget {
  SuperTooltipBuilder({
    required Key key,
    required this.targetBuilder,
    required this.tooltip,
  }) : super(key: key);

  final TargetBuilder targetBuilder;
  final SuperTooltip tooltip;

  @override
  _SuperTooltipBuilderState createState() => _SuperTooltipBuilderState();
}

class _SuperTooltipBuilderState extends State<SuperTooltipBuilder> {
  OverlayEntry? _overlayEntry;
  late final LayerLink _layerLink;
  var _isShowing = false;

  @override
  void initState() {
    super.initState();
    _layerLink = LayerLink();
  }

  void _remove() async {
    if (!_isShowing) return;
    if (widget.tooltip.onClose != null) {
      widget.tooltip.onClose!();
    }
    final entry = _overlayEntry;
    if (entry != null) entry.remove();

    _isShowing = false;
  }

  Widget _superTooltip(
    Offset targetCenter,
    Size? size,
  ) =>
      _SuperTooltip(
        tooltip: widget.tooltip,
        targetCenter: targetCenter,
        targetSize: size,
        close: _remove,
      );

  void _show(
    BuildContext targetContext, {
    OverlayState? overlay,

    /// a key may be provided to override the default widget context
    GlobalKey? key,
  }) async {
    var _context = targetContext;
    if (key != null) {
      if (key.currentWidget != null) {
        assert(false, 'The key must be assigned to a widget');
        return;
      }
      _context = key.currentContext!;
    }
    if (_isShowing) return;

    final renderBox = _context.findRenderObject() as RenderBox;
    final _overlay = overlay ??= Overlay.of(_context);
    final overlayRenderBox = _overlay!.context.findRenderObject() as RenderBox?;

    final _targetCenter = renderBox.localToGlobal(
        renderBox.size.center(Offset.zero),
        ancestor: overlayRenderBox);
    final size = renderBox.size;

    final offsetToTarget = Offset(
      -_targetCenter.dx + size.width / 2,
      -_targetCenter.dy + size.height / 2,
    );

    final entry = _overlayEntry = OverlayEntry(
      builder: (context) => CompositedTransformFollower(
        link: _layerLink,
        showWhenUnlinked: false,
        offset: offsetToTarget,
        child: _superTooltip(
          _targetCenter,
          size,
        ),
      ),
    );

    _overlay.insert(entry);
    _isShowing = true;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // If the tooltip is open we don't pop the page on a backbutton press
        // but close the ToolTip
        if (_isShowing) {
          _remove();
          return false;
        }
        return true;
      },
      child: CompositedTransformTarget(
        link: _layerLink,
        child: widget.targetBuilder(
          context,
          ({overlay, key}) => _show(context, overlay: overlay, key: key),
          _remove,
        ),
      ),
    );
  }
}

typedef OnCloseAnimated = void Function(Future<void>);

class _SuperTooltip extends StatefulWidget {
  _SuperTooltip({
    Key? key,
    required this.tooltip,
    required this.targetCenter,
    required this.targetSize,
    required this.close,
  }) : super(key: key);

  final SuperTooltip tooltip;
  final Offset targetCenter;
  final Size? targetSize;
  final OnCloseCallback close;

  @override
  __SuperTooltipState createState() => __SuperTooltipState();
}

class __SuperTooltipState extends State<_SuperTooltip> {
  late double opacity;
  final _animatedDuration = const Duration(milliseconds: 400);

  @override
  void initState() {
    super.initState();
    opacity = 0;

    WidgetsBinding.instance?.addPostFrameCallback((_) async {
      await _updateVisibility(1);
    });
  }

  @override
  void dispose() {
    // TODO: test dispose method and removing tooltip
    _close(updateVis: false);
    super.dispose();
  }

  Future<void> _updateVisibility(double newOpacity) async {
    setState(() {
      opacity = newOpacity;
    });
    await Future.delayed(_animatedDuration);
  }

  void _close({bool updateVis = true}) async {
    if (updateVis) await _updateVisibility(0);
    widget.close();
  }

  @override
  Widget build(BuildContext context) {
    final relativePosition = widget.tooltip.tipContent.position;
    final closeObject = widget.tooltip.closeTipObject;
    final _wrapInSafeArea = relativePosition.hasSnaps;
    var contentPadding = EdgeInsets.zero;

    final absolutePosition = relativePosition.getPosition(
      widget.targetCenter,
      widget.targetSize,
    );

    final margin = closeObject.margin;
    if (closeObject.position.isInside) {
      var _contentRight = 0.0;
      final _contentTop = closeObject.height + margin.top + margin.bottom;

      /// Handling snap far away feature.
      if (relativePosition.snapsHorizontal &&
          !relativePosition.hasPreference &&
          (closeObject.position.isInside)) {
        _contentRight = closeObject.width;
      }

      contentPadding = EdgeInsets.fromLTRB(
        0,
        _contentTop,
        _contentRight,
        0,
      );
    } else if (relativePosition.hasSnaps &&
        (absolutePosition.direction.isUp ||
            absolutePosition.direction.isRight)) {
      contentPadding =
          EdgeInsets.only(top: closeObject.height + margin.bottom + margin.top);
    }

    Widget content = Material(
      type: MaterialType.transparency,
      child: Padding(
        padding: contentPadding,
        child: Container(
          child: _wrapInSafeArea
              ? SafeArea(
                  top: !absolutePosition.direction.isDown,
                  child: widget.tooltip.tipContent.child,
                )
              : widget.tooltip.tipContent.child,
        ),
      ),
    );

    final _content = widget.tooltip.tipContent;
    content = Container(
      margin: absolutePosition.direction
          .getMargin(widget.tooltip.arrowDecoration.distanceAway),
      clipBehavior: Clip.hardEdge,
      decoration: ShapeDecoration(
        shadows: widget.tooltip.boxShadow ??
            kElevationToShadow[widget.tooltip.elevation],
        shape: BubbleShape(
          backgroundColor: widget.tooltip.tipContent.backgroundColor,
          targetCenter: widget.targetCenter,
          borderDecoration: widget.tooltip.borderDecoration,
          arrowDecoration: widget.tooltip.arrowDecoration,
          position: absolutePosition,
        ),
      ),
      child: _content.blurBackground
          ? BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: _content.sigmaX,
                sigmaY: _content.sigmaY,
              ),
              child: content,
            )
          : content,
    );

    // TODO: expose the animation to the public
    return AnimatedOpacity(
      opacity: opacity,
      duration: widget.tooltip.animationDuration,
      curve: Curves.easeInOut,
      child: Center(
        child: Stack(
          children: [
            if (widget.tooltip.background != null)
              Positioned.fill(
                child: SuperTooltipBackground(
                  background: widget.tooltip.background!,
                  close: _close,
                  targetCenter: widget.targetCenter,
                ),
              ),
            Positioned.fill(
              child: CustomSingleChildLayout(
                delegate: PopupBalloonLayoutDelegate(
                  widget.tooltip,
                  direction: absolutePosition.direction,
                  position: absolutePosition,
                  targetCenter: widget.targetCenter,
                ),
                child: Stack(
                  fit: (relativePosition.hasSnaps &&
                          widget.tooltip.closeTipObject.position.isNone)
                      ? StackFit.expand
                      : StackFit.passthrough,
                  clipBehavior: Clip.none,
                  children: [
                    if (relativePosition.hasSnaps)
                      Positioned.fill(child: content)
                    else
                      content,
                    CloseObject(
                      widget.tooltip,
                      direction: absolutePosition.direction,
                      targetCenter: widget.targetCenter,
                      close: _close,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
