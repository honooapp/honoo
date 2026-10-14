import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../Utility/inline_text_formatting.dart';

class WidthLimitedMultilineField extends StatefulWidget {
  const WidthLimitedMultilineField({
    super.key,
    required this.controller,
    this.focusNode,
    required this.style,
    required this.maxLines,
    required this.maxCharsPerLine,
    this.horizontalPadding = EdgeInsets.zero,
    this.minLines,
    this.decoration,
    this.onChanged,
    this.preInputFormatters,
    this.additionalInputFormatters,
    this.keyboardType = TextInputType.multiline,
    this.textInputAction = TextInputAction.newline,
    this.autofocus = false,
    this.readOnly = false,
    this.expands = true,
    this.scrollPhysics,
    this.textCapitalization = TextCapitalization.none,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.autofillHints,
    this.enabled,
    this.hardConstraints,
    this.onEditingComplete,
    this.onSubmitted,
    this.cursorColor,
    this.cursorWidth,
    this.cursorRadius,
    this.scrollPadding,
    this.allowFontShrink = false,
    this.centerTextVertically = true,
    this.enableInlineFormatting = false,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final TextStyle style;
  final int maxLines;
  final int maxCharsPerLine;
  final EdgeInsets horizontalPadding;
  final int? minLines;
  final InputDecoration? decoration;
  final VoidCallback? onChanged;
  final List<TextInputFormatter>? preInputFormatters;
  final List<TextInputFormatter>? additionalInputFormatters;
  final TextInputType keyboardType;
  final TextInputAction textInputAction;
  final bool autofocus;
  final bool readOnly;
  final bool expands;
  final ScrollPhysics? scrollPhysics;
  final TextCapitalization textCapitalization;
  final bool autocorrect;
  final bool enableSuggestions;
  final Iterable<String>? autofillHints;
  final bool? enabled;
  final BoxConstraints? hardConstraints;
  final VoidCallback? onEditingComplete;
  final ValueChanged<String>? onSubmitted;
  final Color? cursorColor;
  final double? cursorWidth;
  final Radius? cursorRadius;
  final EdgeInsets? scrollPadding;
  final bool allowFontShrink;
  final bool centerTextVertically;
  final bool enableInlineFormatting;

  @override
  State<WidthLimitedMultilineField> createState() =>
      _WidthLimitedMultilineFieldState();
}

class _WidthLimitedMultilineFieldState
    extends State<WidthLimitedMultilineField> {
  final ScrollController _scrollController = ScrollController();
  double? _lastPadTop;
  bool _pendingScroll = true;

  late double _baseFontSize;
  late double _currentFontSize;
  static const double _minFontSizeAbs = 12;
  static const double _minFactor = 0.7;

  double get _minFontSize =>
      math.max(_minFontSizeAbs, _baseFontSize * _minFactor);

  @override
  void initState() {
    super.initState();
    _baseFontSize = widget.style.fontSize ?? 18;
    _currentFontSize = _baseFontSize;
    widget.controller.addListener(_handleControllerChange);
  }

  @override
  void didUpdateWidget(WidthLimitedMultilineField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerChange);
      widget.controller.addListener(_handleControllerChange);
      _pendingScroll = true;
    }
    if (oldWidget.style.fontSize != widget.style.fontSize &&
        widget.style.fontSize != null) {
      _baseFontSize = widget.style.fontSize!;
      // se cambiano stile/tema, riallinea il font corrente
      _currentFontSize = _currentFontSize.clamp(_minFontSize, _baseFontSize);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChange);
    _scrollController.dispose();
    super.dispose();
  }

  void _handleControllerChange() {
    widget.onChanged?.call();
    if (mounted) {
      setState(() {
        _pendingScroll = true;
      });
    } else {
      _pendingScroll = true;
    }
  }

  void _scheduleScroll(double padTop) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      if (padTop > 0) {
        if (_scrollController.position.pixels != 0) {
          _scrollController.jumpTo(0);
        }
      } else {
        final double maxExtent = _scrollController.position.maxScrollExtent;
        if ((_scrollController.position.pixels - maxExtent).abs() > 0.5) {
          _scrollController.jumpTo(maxExtent);
        }
      }
    });
  }

  /// misura la larghezza di UNA riga con il font corrente
  double _measureLineWidth(String line) {
    line = InlineTextFormatting.visibleText(line);
    if (line.isEmpty) return 0.0;

    final painter = TextPainter(
      text: TextSpan(
        text: line,
        style: widget.style.copyWith(fontSize: _currentFontSize),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();

    return painter.width;
  }

  void _maybeGrowFont(double maxWidth, String fullText) {
    if (!widget.allowFontShrink) return;
    // chiamata quando cancelli: se il testo è diventato "corto", torna verso il font base
    if (fullText.isEmpty) {
      if (_currentFontSize != _baseFontSize) {
        setState(() => _currentFontSize = _baseFontSize);
      }
      return;
    }

    // se il testo è molto sotto al limite caratteri → torna al font base
    if (InlineTextFormatting.visibleLength(fullText) <
            widget.maxCharsPerLine ~/ 2 &&
        _currentFontSize < _baseFontSize) {
      setState(() => _currentFontSize = _baseFontSize);
    }
  }

  /// formatter che gestisce LIMITE caratteri + larghezza + font dinamico
  TextInputFormatter _createWidthLimitFormatter(double maxWidth) {
    return TextInputFormatter.withFunction((oldValue, newValue) {
      if (oldValue.text == newValue.text) return newValue;

      final bool isDeletion = newValue.text.length < oldValue.text.length;
      if (isDeletion) {
        // mai bloccare il backspace
        if (widget.allowFontShrink) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _maybeGrowFont(maxWidth, newValue.text);
          });
        }
        return newValue;
      }

      // Limite righe inserite manualmente
      final lines = newValue.text.split('\n');
      if (lines.length > widget.maxLines) {
        return oldValue;
      }

      for (final line in lines) {
        // 1) limite caratteri rigido (conta i caratteri visivi)
        if (InlineTextFormatting.visibleLength(line) > widget.maxCharsPerLine) {
          return oldValue;
        }

        // 2) controllo larghezza fisica
        final lineWidth = _measureLineWidth(line);
        if (lineWidth > maxWidth) {
          // se posso, riduco il font e ACCETTO il carattere
          if (widget.allowFontShrink && _currentFontSize > _minFontSize) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              setState(() {
                _currentFontSize = (_currentFontSize - 1).clamp(
                  _minFontSize,
                  _baseFontSize,
                );
              });
            });
            return newValue; // permetti il carattere, poi ridisegni più piccolo
          }

          // font già al minimo → blocco l'input
          return oldValue;
        }
      }

      return newValue;
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget field = LayoutBuilder(
      builder: (context, constraints) {
        final double maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 0;
        final double maxHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : 0;

        final String textForLayout = widget.controller.text.isEmpty
            ? ' '
            : InlineTextFormatting.visibleText(widget.controller.text);
        final double usableWidth = math.max(
          1,
          maxWidth - widget.horizontalPadding.horizontal,
        );

        final textStyle = widget.style.copyWith(fontSize: _currentFontSize);

        final TextPainter painter = TextPainter(
          text: TextSpan(text: textForLayout, style: textStyle),
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
          maxLines: widget.maxLines,
        )..layout(minWidth: 0, maxWidth: usableWidth);

        double textHeight = painter.size.height;
        if (textHeight <= 0) {
          final double baseLineHeight =
              (textStyle.height ?? 1.0) * (textStyle.fontSize ?? 16);
          textHeight = baseLineHeight;
        }

        double padTop = 0;
        if (widget.centerTextVertically &&
            maxHeight.isFinite &&
            maxHeight > 0) {
          padTop = math.max(0, (maxHeight - textHeight) / 2);
        }

        final bool shouldAdjust =
            _pendingScroll ||
            _lastPadTop == null ||
            (padTop - _lastPadTop!).abs() > 0.5;
        if (shouldAdjust) {
          _scheduleScroll(padTop);
          _pendingScroll = false;
          _lastPadTop = padTop;
        }

        final InputDecoration baseDecoration =
            widget.decoration ?? const InputDecoration();
        final EdgeInsets contentPadding = EdgeInsets.only(
          top: padTop,
          left: widget.horizontalPadding.left,
          right: widget.horizontalPadding.right,
          bottom: widget.horizontalPadding.bottom,
        );

        final InputDecoration effectiveDecoration = baseDecoration.copyWith(
          isDense: true,
          contentPadding: contentPadding,
        );

        final bool expands = widget.expands;
        final int? effectiveMaxLines = expands ? null : widget.maxLines;
        final int? effectiveMinLines = expands ? null : widget.minLines;

        final List<TextInputFormatter> allFormatters = [
          if (widget.enableInlineFormatting)
            const InlineFormattingShortcutTextInputFormatter(),
          ...?widget.preInputFormatters,
          _createWidthLimitFormatter(usableWidth),
          ...?widget.additionalInputFormatters,
        ];

        final textField = TextField(
          controller: widget.controller,
          focusNode: widget.focusNode,
          style: textStyle,
          cursorColor: widget.cursorColor,
          cursorWidth: widget.cursorWidth ?? 2,
          cursorRadius: widget.cursorRadius,
          keyboardType: widget.keyboardType,
          textInputAction: widget.textInputAction,
          textCapitalization: widget.textCapitalization,
          autocorrect: widget.autocorrect,
          enableSuggestions: widget.enableSuggestions,
          autofocus: widget.autofocus,
          readOnly: widget.readOnly,
          enabled: widget.enabled,
          expands: expands,
          minLines: effectiveMinLines,
          maxLines: effectiveMaxLines,
          textAlign: TextAlign.center,
          textAlignVertical: TextAlignVertical.top,
          inputFormatters: allFormatters,
          scrollPadding:
              widget.scrollPadding ?? const EdgeInsets.only(bottom: 24),
          scrollController: _scrollController,
          scrollPhysics: widget.scrollPhysics ?? const ClampingScrollPhysics(),
          decoration: effectiveDecoration,
          onEditingComplete: widget.onEditingComplete,
          onSubmitted: widget.onSubmitted,
          autofillHints: widget.autofillHints,
          contextMenuBuilder: (context, editableText) {
            final items = editableText.contextMenuButtonItems
                .where((item) => item.type != ContextMenuButtonType.paste)
                .toList();
            if (!widget.readOnly && widget.enabled != false) {
              // Read the clipboard on the user's gesture, including browsers
              // that cannot report clipboard availability ahead of time.
              items.add(
                ContextMenuButtonItem(
                  type: ContextMenuButtonType.paste,
                  label: 'Incolla',
                  onPressed: () =>
                      editableText.pasteText(SelectionChangedCause.toolbar),
                ),
              );
            }
            return AdaptiveTextSelectionToolbar.buttonItems(
              anchors: editableText.contextMenuAnchors,
              buttonItems: items,
            );
          },
        );
        if (!widget.enableInlineFormatting ||
            widget.readOnly ||
            widget.enabled == false) {
          return textField;
        }
        return Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: _handleFormattingKey,
          child: textField,
        );
      },
    );

    if (widget.hardConstraints != null) {
      field = ConstrainedBox(
        constraints: widget.hardConstraints!,
        child: field,
      );
    }

    return field;
  }

  KeyEventResult _handleFormattingKey(FocusNode node, KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isMetaPressed ||
        keyboard.isAltPressed) {
      return KeyEventResult.ignored;
    }

    final style = switch (event.logicalKey) {
      LogicalKeyboardKey.keyC => InlineTextStyle.italic,
      LogicalKeyboardKey.keyB => InlineTextStyle.bold,
      _ => null,
    };
    if (style == null || widget.controller.selection.isCollapsed) {
      return KeyEventResult.ignored;
    }

    if (event is KeyDownEvent) _toggleFormat(style);
    return KeyEventResult.handled;
  }

  void _toggleFormat(InlineTextStyle style) {
    final updated = InlineTextFormatting.toggle(widget.controller.value, style);
    if (updated == widget.controller.value) return;
    widget.controller.value = updated;
    widget.focusNode?.requestFocus();
  }
}
