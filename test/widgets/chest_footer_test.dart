import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honoo/Entities/chest_item.dart';
import 'package:honoo/Entities/conversation_entry.dart';
import 'package:honoo/Entities/hinoo.dart';
import 'package:honoo/Entities/honoo.dart';
import 'package:honoo/Utility/honoo_colors.dart';
import 'package:honoo/Widgets/chest_footer.dart';

void main() {
  ChestItem honooItem(
    HonooType type, {
    bool isOnMoon = false,
    bool isFromMoonSaved = false,
    bool hasReplies = false,
    String? conversationId,
    String? ownerId,
  }) {
    final honoo =
        Honoo(
            1,
            'Test',
            '',
            '2026-01-01T00:00:00Z',
            '2026-01-01T00:00:00Z',
            ownerId ??
                (type == HonooType.answer ? 'another-user' : 'current-user'),
            type,
          )
          ..isOnMoon = isOnMoon
          ..isFromMoonSaved = isFromMoonSaved
          ..hasReplies = hasReplies
          ..conversationId = conversationId;
    return ChestItem.honoo(honoo, DateTime.utc(2026));
  }

  ChestItem hinooItem({
    bool isOnMoon = false,
    bool isFromMoonSaved = false,
    String ownerId = 'current-user',
    String? conversationId,
  }) => ChestItem.hinoo(
    ChestHinooItem(
      id: 'hinoo-1',
      draft: const HinooDraft(
        pages: [
          HinooSlide(backgroundImage: null, text: 'Test', isTextWhite: true),
        ],
      ),
      createdAt: DateTime.utc(2026),
      isFromMoonSaved: isFromMoonSaved,
      ownerId: ownerId,
      isOnMoon: isOnMoon,
      conversationId: conversationId,
    ),
  );

  Future<void> pumpFooter(
    WidgetTester tester, {
    required ChestItem? item,
    ValueChanged<Honoo>? onSendHonooToMoon,
    ValueChanged<Honoo>? onDeleteHonoo,
    ValueChanged<ChestHinooItem>? onSendHinooToMoon,
    ValueChanged<ChestHinooItem>? onDeleteHinoo,
    ConversationEntry? selectedConversationEntry,
    ValueChanged<ConversationEntry>? onReplyToConversationEntry,
    ValueChanged<ConversationEntry>? onSendConversationEntryToMoon,
    Color foregroundColor = HonooColor.onBackground,
    bool isAdmin = false,
    double width = 800,
    double iconSize = 40,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            child: SizedBox(
              width: width,
              child: ChestFooter(
                item: item,
                isAdmin: isAdmin,
                selectedConversationEntry: selectedConversationEntry,
                currentUserId: 'current-user',
                iconSize: iconSize,
                gap: 24,
                bottomPadding: 10,
                foregroundColor: foregroundColor,
                onHome: () {},
                onInfo: () {},
                onSendHonooToMoon: onSendHonooToMoon ?? (_) {},
                onReplyToHonoo: (_) {},
                onDeleteHonoo: onDeleteHonoo ?? (_) {},
                onSendHinooToMoon: onSendHinooToMoon ?? (_) {},
                onReplyToHinoo: (_) {},
                onDeleteHinoo: onDeleteHinoo ?? (_) {},
                onReplyToConversationEntry:
                    onReplyToConversationEntry ?? (ConversationEntry _) {},
                onSendConversationEntryToMoon:
                    onSendConversationEntryToMoon ?? (ConversationEntry _) {},
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('risposta senza selezione mantiene Rispondi', (tester) async {
    final item = honooItem(HonooType.answer);
    item.honoo!.dbId = 'legacy-answer';
    ConversationEntry? target;
    await pumpFooter(
      tester,
      item: item,
      onReplyToConversationEntry: (entry) => target = entry,
    );
    await tester.tap(find.byTooltip('Rispondi'));
    expect(target?.id, 'legacy-answer');
  });

  testWidgets('Rispondi usa il messaggio visibile e non la radice Luna', (
    tester,
  ) async {
    final root = honooItem(HonooType.personal, isFromMoonSaved: true);
    root.honoo!.dbId = 'moon-root';
    final reply = honooItem(HonooType.answer).honoo!..dbId = 'visible-reply';
    ConversationEntry? target;
    await pumpFooter(
      tester,
      item: root,
      selectedConversationEntry: ConversationEntry.honoo(reply),
      onReplyToConversationEntry: (entry) => target = entry,
    );
    await tester.tap(find.byTooltip('Rispondi'));
    expect(target?.id, 'visible-reply');
  });

  testWidgets(
    'le azioni restano ferme durante caricamento e cambio selezione',
    (tester) async {
      final item = honooItem(
        HonooType.personal,
        conversationId: 'conversation',
      );
      await pumpFooter(tester, item: item);
      final home = tester.getCenter(find.byTooltip('Home'));
      final info = tester.getCenter(find.byTooltip('Info'));
      expect(find.byTooltip('Cancella'), findsNothing);
      final reply = Honoo(
        0,
        'reply',
        '',
        '',
        '',
        'another-user',
        HonooType.answer,
      )..dbId = 'reply';
      await pumpFooter(
        tester,
        item: item,
        selectedConversationEntry: ConversationEntry.honoo(reply),
      );
      expect(find.byTooltip('Rispondi'), findsOneWidget);
      expect(tester.getCenter(find.byTooltip('Home')), home);
      expect(tester.getCenter(find.byTooltip('Info')), info);
      expect(find.byTooltip('Cancella'), findsNothing);
      await pumpFooter(tester, item: null);
      expect(tester.getCenter(find.byTooltip('Home')), home);
      expect(tester.getCenter(find.byTooltip('Info')), info);
      expect(find.byTooltip('Rispondi'), findsNothing);
    },
  );

  testWidgets('solo gli admin possono cancellare conversazioni Honoo e Hinoo', (
    tester,
  ) async {
    for (final item in [
      honooItem(HonooType.personal, conversationId: 'thread'),
      honooItem(HonooType.personal, hasReplies: true),
      hinooItem(conversationId: 'thread'),
    ]) {
      await pumpFooter(tester, item: item);
      expect(find.byTooltip('Cancella'), findsNothing);
      var deleted = false;
      await pumpFooter(
        tester,
        item: item,
        isAdmin: true,
        onDeleteHonoo: (_) => deleted = true,
        onDeleteHinoo: (_) => deleted = true,
      );
      await tester.tap(find.byTooltip('Cancella'));
      expect(deleted, isTrue);
    }
  });

  testWidgets('footer vuoto mostra subito Home e Info bianche', (tester) async {
    await pumpFooter(tester, item: null);

    expect(find.byTooltip('Home'), findsOneWidget);
    expect(find.byTooltip('Info'), findsOneWidget);
    expect(find.byType(IconButton), findsNWidgets(2));
    final icons = tester
        .widgetList<SvgPicture>(find.byType(SvgPicture))
        .toList();
    expect(icons.first.colorFilter, isNotNull);
    expect(icons.last.colorFilter, isNotNull);
  });

  testWidgets('tutte le azioni del footer seguono il colore di contrasto', (
    tester,
  ) async {
    await pumpFooter(tester, item: honooItem(HonooType.personal));

    final icons = tester
        .widgetList<SvgPicture>(find.byType(SvgPicture))
        .toList();
    expect(icons, hasLength(4));
    expect(icons[0].colorFilter, isNotNull); // Home
    expect(icons[1].colorFilter, isNotNull); // Info
    expect(
      icons[2].colorFilter,
      const ColorFilter.mode(HonooColor.onBackground, BlendMode.srcIn),
    ); // Luna
    expect(
      icons[3].colorFilter,
      const ColorFilter.mode(HonooColor.onBackground, BlendMode.srcIn),
    ); // Cancella
    expect(
      (icons[3].bytesLoader as SvgAssetLoader).assetName,
      'assets/Cestino.svg',
    );
  });

  testWidgets('un Honoo personale con risposte conserva l’azione Luna', (
    tester,
  ) async {
    await pumpFooter(
      tester,
      item: honooItem(HonooType.personal, hasReplies: true),
    );

    expect(find.byTooltip('Vedi risposte'), findsNothing);
    expect(find.byTooltip('Rispondi'), findsNothing);
    expect(find.byTooltip('Spedisci sulla Luna'), findsOneWidget);
    expect(find.byType(IconButton), findsNWidgets(3));
  });

  testWidgets('Honoo personale mostra Luna e Cancella e inoltra le azioni', (
    tester,
  ) async {
    var sent = false;
    var deleted = false;
    await pumpFooter(
      tester,
      item: honooItem(HonooType.personal),
      onSendHonooToMoon: (_) => sent = true,
      onDeleteHonoo: (_) => deleted = true,
    );

    expect(find.byType(IconButton), findsNWidgets(4));
    expect(find.byTooltip('Spedisci sulla Luna'), findsOneWidget);
    expect(find.byTooltip('Cancella'), findsOneWidget);
    await tester.tap(find.byTooltip('Spedisci sulla Luna'));
    await tester.tap(find.byTooltip('Cancella'));
    expect(sent, isTrue);
    expect(deleted, isTrue);
  });

  testWidgets('Hinoo personale mostra Luna e Cancella e inoltra le azioni', (
    tester,
  ) async {
    var sent = false;
    var deleted = false;
    await pumpFooter(
      tester,
      item: hinooItem(),
      onSendHinooToMoon: (_) => sent = true,
      onDeleteHinoo: (_) => deleted = true,
    );

    expect(find.byType(IconButton), findsNWidgets(4));
    await tester.tap(find.byTooltip('Spedisci sulla Luna'));
    await tester.tap(find.byTooltip('Cancella'));
    expect(sent, isTrue);
    expect(deleted, isTrue);
  });

  testWidgets('Honoo già sulla Luna continua a mostrare l’azione Luna', (
    tester,
  ) async {
    await pumpFooter(
      tester,
      item: honooItem(HonooType.personal, isOnMoon: true),
    );

    expect(find.byTooltip('Spedisci sulla Luna'), findsOneWidget);
    expect(find.byTooltip('Cancella'), findsOneWidget);
  });

  testWidgets('Honoo salvato dalla Luna non mostra l’azione Luna', (
    tester,
  ) async {
    await pumpFooter(
      tester,
      item: honooItem(HonooType.personal, isFromMoonSaved: true),
    );

    expect(find.byTooltip('Spedisci sulla Luna'), findsNothing);
    expect(find.byTooltip('Rispondi'), findsOneWidget);
  });

  testWidgets('Honoo personale di un altro utente non mostra Luna', (
    tester,
  ) async {
    await pumpFooter(
      tester,
      item: honooItem(HonooType.personal, ownerId: 'another-user'),
    );

    expect(find.byTooltip('Spedisci sulla Luna'), findsNothing);
  });

  testWidgets(
    'la selezione del padre della conversazione mostra una sola azione Luna',
    (tester) async {
      final item = honooItem(
        HonooType.personal,
        conversationId: 'conversation-1',
      );
      item.honoo!.dbId = 'root-1';
      item.honoo!.dbId ??= 'saved-root';
      final selectedEntry = ConversationEntry.honoo(item.honoo!);
      Honoo? publishedHonoo;

      await pumpFooter(
        tester,
        item: item,
        selectedConversationEntry: selectedEntry,
        onSendHonooToMoon: (honoo) => publishedHonoo = honoo,
      );

      expect(find.byTooltip('Spedisci sulla Luna'), findsOneWidget);
      expect(find.byTooltip('Rispondi'), findsOneWidget);
      await tester.tap(find.byTooltip('Spedisci sulla Luna'));
      expect(publishedHonoo, same(item.honoo));
    },
  );

  testWidgets(
    'una propria risposta Honoo mostra Luna e pubblica la selezione',
    (tester) async {
      final item = honooItem(
        HonooType.personal,
        conversationId: 'conversation-1',
      );
      item.honoo!.dbId = 'root-1';
      final reply =
          Honoo(
              2,
              'Risposta propria',
              '',
              '2026-01-01T01:00:00Z',
              '2026-01-01T01:00:00Z',
              'current-user',
              HonooType.answer,
            )
            ..dbId = 'reply-1'
            ..replyTo = 'root-1'
            ..conversationId = 'conversation-1';
      final selectedEntry = ConversationEntry.honoo(reply);
      ConversationEntry? publishedEntry;

      await pumpFooter(
        tester,
        item: item,
        selectedConversationEntry: selectedEntry,
        onSendConversationEntryToMoon: (entry) => publishedEntry = entry,
      );

      expect(find.byTooltip('Spedisci sulla Luna'), findsOneWidget);
      await tester.tap(find.byTooltip('Spedisci sulla Luna'));
      expect(publishedEntry, same(selectedEntry));
    },
  );

  testWidgets(
    'una propria risposta Hinoo mostra Luna e pubblica la selezione',
    (tester) async {
      final item = hinooItem(conversationId: 'conversation-1');
      const replyDraft = HinooDraft(
        pages: [
          HinooSlide(
            backgroundImage: null,
            text: 'Risposta propria',
            isTextWhite: true,
          ),
        ],
        type: HinooType.answer,
        recipientTag: 'destinatario',
        replyTo: 'root-1',
        conversationId: 'conversation-1',
      );
      final selectedEntry = ConversationEntry.hinoo(
        replyDraft,
        createdAt: DateTime.utc(2026, 1, 1, 1),
        ownerId: 'current-user',
        id: 'reply-hinoo-1',
      );
      ConversationEntry? publishedEntry;

      await pumpFooter(
        tester,
        item: item,
        selectedConversationEntry: selectedEntry,
        onSendConversationEntryToMoon: (entry) => publishedEntry = entry,
      );

      expect(find.byTooltip('Spedisci sulla Luna'), findsOneWidget);
      await tester.tap(find.byTooltip('Spedisci sulla Luna'));
      expect(publishedEntry, same(selectedEntry));
    },
  );

  testWidgets(
    'la conversazione dedicata mostra Rispondi bianco e inoltra la selezione',
    (tester) async {
      final honoo = honooItem(
        HonooType.answer,
        conversationId: 'conversation-1',
      ).honoo!;
      honoo.dbId = 'reply-1';
      final selectedEntry = ConversationEntry.honoo(honoo);
      ConversationEntry? repliedEntry;

      await pumpFooter(
        tester,
        item: null,
        selectedConversationEntry: selectedEntry,
        onReplyToConversationEntry: (entry) => repliedEntry = entry,
      );

      expect(find.byTooltip('Rispondi'), findsOneWidget);
      final replyIcon = tester.widget<SvgPicture>(
        find.descendant(
          of: find.byTooltip('Rispondi'),
          matching: find.byType(SvgPicture),
        ),
      );
      expect(
        replyIcon.colorFilter,
        const ColorFilter.mode(Colors.white, BlendMode.srcIn),
      );
      await tester.tap(find.byTooltip('Rispondi'));
      expect(repliedEntry, same(selectedEntry));
    },
  );

  testWidgets(
    'la selezione di un contenuto salvato dalla Luna non mostra Luna',
    (tester) async {
      final item = honooItem(
        HonooType.personal,
        isFromMoonSaved: true,
        conversationId: 'conversation-1',
      );
      item.honoo!.dbId ??= 'saved-root';
      final selectedEntry = ConversationEntry.honoo(item.honoo!);

      await pumpFooter(
        tester,
        item: item,
        selectedConversationEntry: selectedEntry,
      );

      expect(find.byTooltip('Spedisci sulla Luna'), findsNothing);
      expect(find.byTooltip('Rispondi'), findsOneWidget);
    },
  );

  testWidgets('non duplica Rispondi tra contenuto e selezione', (tester) async {
    final item = honooItem(
      HonooType.personal,
      isFromMoonSaved: true,
      conversationId: 'conversation-1',
    );
    item.honoo!.dbId = 'root-1';

    await pumpFooter(
      tester,
      item: item,
      selectedConversationEntry: ConversationEntry.honoo(item.honoo!),
    );

    expect(find.byTooltip('Rispondi'), findsOneWidget);
  });

  testWidgets('Rispondi usa il contrasto corrente anche sullo sfondo bianco', (
    tester,
  ) async {
    final item = honooItem(
      HonooType.personal,
      isFromMoonSaved: true,
      conversationId: 'conversation-1',
    );

    await pumpFooter(
      tester,
      item: item,
      foregroundColor: HonooColor.onTertiary,
    );

    final replyIcon = tester.widget<SvgPicture>(
      find.descendant(
        of: find.byTooltip('Rispondi'),
        matching: find.byType(SvgPicture),
      ),
    );
    expect(
      replyIcon.colorFilter,
      const ColorFilter.mode(HonooColor.onTertiary, BlendMode.srcIn),
    );
  });

  testWidgets('tutte le azioni restano visibili su una toolbar stretta', (
    tester,
  ) async {
    final item = honooItem(
      HonooType.personal,
      conversationId: 'conversation-1',
    );
    item.honoo!.dbId = 'root-1';

    await pumpFooter(
      tester,
      item: item,
      selectedConversationEntry: ConversationEntry.honoo(item.honoo!),
      width: 200,
      iconSize: 60,
    );

    expect(find.byType(IconButton), findsNWidgets(4));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Hinoo già sulla Luna continua a mostrare l’azione Luna', (
    tester,
  ) async {
    await pumpFooter(tester, item: hinooItem(isOnMoon: true));

    expect(find.byTooltip('Spedisci sulla Luna'), findsOneWidget);
    expect(find.byTooltip('Cancella'), findsOneWidget);
  });

  testWidgets('Hinoo salvato dalla Luna non mostra l’azione Luna', (
    tester,
  ) async {
    await pumpFooter(tester, item: hinooItem(isFromMoonSaved: true));

    expect(find.byTooltip('Spedisci sulla Luna'), findsNothing);
    expect(find.byTooltip('Rispondi'), findsOneWidget);
  });

  testWidgets('Hinoo personale di un altro utente non mostra Luna', (
    tester,
  ) async {
    await pumpFooter(tester, item: hinooItem(ownerId: 'another-user'));

    expect(find.byTooltip('Spedisci sulla Luna'), findsNothing);
  });

  testWidgets('contenuto ricevuto non permette la cancellazione agli utenti', (
    tester,
  ) async {
    await pumpFooter(tester, item: honooItem(HonooType.answer));

    expect(find.byType(IconButton), findsNWidgets(2));
    expect(find.byTooltip('Home'), findsOneWidget);
    expect(find.byTooltip('Info'), findsOneWidget);
    expect(find.byTooltip('Cancella'), findsNothing);
    expect(find.byTooltip('Spedisci sulla Luna'), findsNothing);
    expect(find.byTooltip('Rispondi'), findsNothing);
  });
}
