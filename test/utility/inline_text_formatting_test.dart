import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honoo/Utility/inline_text_formatting.dart';
import 'package:honoo/Widgets/width_limited_multiline_field.dart';

void main() {
  test('applica e rimuove corsivo sulla selezione', () {
    const value = TextEditingValue(
      text: 'Una parola qui',
      selection: TextSelection(baseOffset: 4, extentOffset: 10),
    );

    final formatted = InlineTextFormatting.toggle(
      value,
      InlineTextStyle.italic,
    );
    expect(
      formatted.text,
      'Una ${InlineTextFormatting.italicMarker}parola'
      '${InlineTextFormatting.italicMarker} qui',
    );
    expect(InlineTextFormatting.visibleText(formatted.text), value.text);

    final restored = InlineTextFormatting.toggle(
      formatted,
      InlineTextStyle.italic,
    );
    expect(restored.text, value.text);
    expect(restored.selection, value.selection);
  });

  test('corsivo e grassetto possono essere combinati', () {
    const value = TextEditingValue(
      text: 'parola',
      selection: TextSelection(baseOffset: 0, extentOffset: 6),
    );
    final italic = InlineTextFormatting.toggle(value, InlineTextStyle.italic);
    final both = InlineTextFormatting.toggle(italic, InlineTextStyle.bold);

    final visibleSpans = InlineTextFormatting.spans(
      both.text,
      style: const TextStyle(fontWeight: FontWeight.w400),
    ).whereType<TextSpan>().where((span) => span.text == 'parola').toList();

    expect(visibleSpans, hasLength(1));
    expect(visibleSpans.single.style?.fontStyle, FontStyle.italic);
    expect(visibleSpans.single.style?.fontWeight, FontWeight.bold);
  });

  test('il limite caratteri ignora i marcatori invisibili', () {
    const formatter = VisibleLengthLimitingTextInputFormatter(6);
    const formatted = TextEditingValue(
      text:
          '${InlineTextFormatting.boldMarker}parola'
          '${InlineTextFormatting.boldMarker}',
    );

    expect(
      formatter.formatEditUpdate(TextEditingValue.empty, formatted),
      formatted,
    );
    expect(
      formatter.formatEditUpdate(
        formatted,
        TextEditingValue(text: '${formatted.text}!'),
      ),
      formatted,
    );
  });

  test('la tastiera virtuale interpreta C e B sulla selezione', () {
    const formatter = InlineFormattingShortcutTextInputFormatter();
    const selected = TextEditingValue(
      text: 'Una parola',
      selection: TextSelection(baseOffset: 4, extentOffset: 10),
    );

    final italic = formatter.formatEditUpdate(
      selected,
      const TextEditingValue(
        text: 'Una c',
        selection: TextSelection.collapsed(offset: 5),
      ),
    );
    expect(italic.text, contains(InlineTextFormatting.italicMarker));
    expect(InlineTextFormatting.visibleText(italic.text), selected.text);

    final replacement = italic.text.replaceRange(
      italic.selection.start,
      italic.selection.end,
      'B',
    );
    final both = formatter.formatEditUpdate(
      italic,
      TextEditingValue(
        text: replacement,
        selection: TextSelection.collapsed(offset: italic.selection.start + 1),
      ),
    );
    expect(both.text, contains(InlineTextFormatting.boldMarker));
    expect(InlineTextFormatting.visibleText(both.text), selected.text);
  });

  for (final maxLines in [5, 20]) {
    testWidgets(
      'Incolla inserisce e sostituisce testo rispettando $maxLines righe',
      (tester) async {
        final controller = TextEditingController(text: 'Ciao Luna');
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 400,
                height: 300,
                child: WidthLimitedMultilineField(
                  controller: controller,
                  style: const TextStyle(fontSize: 18),
                  maxLines: maxLines,
                  maxCharsPerLine: 32,
                  enableInlineFormatting: true,
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.byType(TextField));
        await tester.pump();
        controller.selection = const TextSelection(
          baseOffset: 5,
          extentOffset: 9,
        );
        final editable = tester.state<EditableTextState>(
          find.byType(EditableText),
        );
        final field = tester.widget<TextField>(find.byType(TextField));
        final toolbar =
            field.contextMenuBuilder!(
                  tester.element(find.byType(TextField)),
                  editable,
                )
                as AdaptiveTextSelectionToolbar;
        final paste = toolbar.buttonItems!.singleWhere(
          (item) => item.label == 'Incolla',
        );
        var clipboardText = 'Isola';
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.getData')
              return {'text': clipboardText};
            if (call.method == 'Clipboard.hasStrings') return {'value': true};
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        paste.onPressed!();
        await tester.pump();
        expect(controller.text, 'Ciao Isola');
        clipboardText = List.filled(maxLines + 1, 'riga').join('\n');
        paste.onPressed!();
        await tester.pump();
        expect(controller.text, 'Ciao Isola');
      },
    );
  }

  testWidgets('i tasti C e B formattano la selezione', (tester) async {
    final controller = FormattedTextEditingController(text: 'Una parola');
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 160,
            child: WidthLimitedMultilineField(
              controller: controller,
              focusNode: focusNode,
              style: const TextStyle(fontSize: 18),
              maxLines: 5,
              maxCharsPerLine: 32,
              enableInlineFormatting: true,
            ),
          ),
        ),
      ),
    );

    focusNode.requestFocus();
    await tester.pump();
    controller.selection = const TextSelection(baseOffset: 4, extentOffset: 10);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.pump();
    expect(controller.text, contains(InlineTextFormatting.italicMarker));

    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.pump();
    expect(controller.text, contains(InlineTextFormatting.boldMarker));
    expect(InlineTextFormatting.visibleText(controller.text), 'Una parola');
  });

  testWidgets('l input della tastiera virtuale formatta la selezione', (
    tester,
  ) async {
    final controller = FormattedTextEditingController(text: 'Una parola');
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 160,
            child: WidthLimitedMultilineField(
              controller: controller,
              focusNode: focusNode,
              style: const TextStyle(fontSize: 18),
              maxLines: 5,
              maxCharsPerLine: 32,
              enableInlineFormatting: true,
            ),
          ),
        ),
      ),
    );

    focusNode.requestFocus();
    await tester.pump();
    controller.selection = const TextSelection(baseOffset: 4, extentOffset: 10);
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'Una C',
        selection: TextSelection.collapsed(offset: 5),
      ),
    );
    await tester.pump();

    expect(controller.text, contains(InlineTextFormatting.italicMarker));
    expect(InlineTextFormatting.visibleText(controller.text), 'Una parola');
  });
}
