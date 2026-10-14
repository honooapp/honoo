import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:honoo/Services/supabase_provider.dart';
import 'package:honoo/Services/home_service.dart';
import 'package:honoo/Utility/app_logger.dart';
import 'package:honoo/Utility/honoo_colors.dart';
import 'package:honoo/Utility/reply_notification_signal.dart';
import '../Widgets/honoo_app_title.dart';
import 'placeholder_page.dart';

// Widgets riutilizzabili
import '../Widgets/sea_footer_bar.dart';
import '../Widgets/luna_fissa.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.homeService = const HomeService()});

  final HomeService homeService;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  int _replyCount = 0;
  Timer? _replyRefreshTimer;
  bool _visitRecorded = false;
  int _replyLoadGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadReplyCount();
      _recordVisit();
    });
    _replyRefreshTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _loadReplyCount(),
    );
    ReplyNotificationSignal.revision.addListener(_loadReplyCount);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _replyRefreshTimer?.cancel();
    ReplyNotificationSignal.revision.removeListener(_loadReplyCount);
    super.dispose();
  }

  Future<void> _loadReplyCount() async {
    final generation = ++_replyLoadGeneration;
    final user = SupabaseProvider.client.auth.currentUser;
    if (user == null) {
      if (mounted && _replyCount != 0) setState(() => _replyCount = 0);
      return;
    }
    try {
      final count = await widget.homeService.fetchUnreadReplyCount(user.id);
      if (!mounted || generation != _replyLoadGeneration) return;
      if (count != _replyCount) {
        setState(() => _replyCount = count);
      }
    } catch (error, stackTrace) {
      AppLogger.warning(
        'Impossibile aggiornare il contatore risposte',
        scope: 'HomePage',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadReplyCount();
  }

  Future<void> _recordVisit() async {
    if (_visitRecorded) return;
    _visitRecorded = true;
    try {
      await widget.homeService.recordVisit();
    } catch (error, stackTrace) {
      AppLogger.warning(
        'Impossibile registrare la visita',
        scope: 'HomePage',
        error: error,
        stackTrace: stackTrace,
      );
      _visitRecorded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('home_screen_root'),
      backgroundColor: HonooColor.background,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final double maxWidth = constraints.maxWidth;
          final bool isPhone = maxWidth < 600;
          final double contentWidth = isPhone ? maxWidth : maxWidth * 0.5;

          return Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.none,
            children: [
              // CONTENUTO PRINCIPALE
              Column(
                children: [
                  SizedBox(
                    height: 52,
                    child: HonooAppTitle(
                      onTap: () {
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(
                            builder: (_) => const PlaceholderPage(),
                          ),
                          (route) => false,
                        );
                      },
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: contentWidth),
                        child: const Padding(
                          padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                          child: _HomeIntro(),
                        ),
                      ),
                    ),
                  ),

                  // FOOTER sostituito col widget riutilizzabile
                  SeaFooterBar(replyCount: _replyCount, showHouseEntry: true),
                ],
              ),

              // 🌙 LUNA FISSA (riutilizzabile ovunque)
              const LunaFissa(showAdminEntry: true),
            ],
          );
        },
      ),
    );
  }
}

class _HomeIntro extends StatelessWidget {
  const _HomeIntro();

  static const double _designWidth = 360;
  static const double _bottleIconSize = 42;
  static const double _moonIconSize = 28;
  static const double _islandIconSize = 55;
  static const double _bottleIconVerticalOffset = 9;
  static const double _moonIconVerticalOffset = 1;
  static const double _islandIconVerticalOffset = 17;
  static const double _islandFollowupTextVerticalOffset = -2;

  @override
  Widget build(BuildContext context) {
    final regularStyle = GoogleFonts.arvo(
      color: HonooColor.onBackground,
      fontSize: 18,
      height: 1.22,
      fontWeight: FontWeight.w400,
    );

    return FittedBox(
      key: const Key('home_intro_fitted'),
      fit: BoxFit.scaleDown,
      alignment: Alignment.topCenter,
      child: SizedBox(
        width: _designWidth,
        child: Text.rich(
          TextSpan(
            style: regularStyle,
            children: [
              TextSpan(
                text: 'Ti regaliamo la Luna\nPer sempre\n\n',
                style: regularStyle.copyWith(fontWeight: FontWeight.w700),
              ),
              const TextSpan(
                text:
                    'Niente è per sempre\n'
                    'E nessuno può regalarti la Luna\n\n'
                    'È vero. Ma non per i poeti\n\n'
                    'Vuoi essere un poeta di honoo?\n\n'
                    'Scegli',
              ),
              const WidgetSpan(
                child: SizedBox(key: Key('home_bottle_leading_gap'), width: 8),
              ),
              _inlineAction(
                key: const Key('home_inline_bottle'),
                asset: 'assets/icons/bottle.svg',
                size: _bottleIconSize,
                verticalOffset: _bottleIconVerticalOffset,
                tooltip: 'Scrivi',
                onPressed: () => SeaFooterBar.openComposer(context),
              ),
              const TextSpan(text: '\n\nOppure'),
              const WidgetSpan(
                child: SizedBox(key: Key('home_moon_leading_gap'), width: 8),
              ),
              _inlineAction(
                key: const Key('home_inline_moon'),
                asset: 'assets/icons/moon.svg',
                size: _moonIconSize,
                verticalOffset: _moonIconVerticalOffset,
                tooltip: 'Vai sulla Luna',
                onPressed: () => LunaFissa.openMoon(context),
              ),
              const TextSpan(text: '\ne guarda le vite degli altri\n\nO'),
              const WidgetSpan(
                child: SizedBox(key: Key('home_island_leading_gap'), width: 8),
              ),
              _inlineAction(
                key: const Key('home_inline_island'),
                asset: 'assets/icons/isoladellestorie/island.svg',
                size: _islandIconSize,
                verticalOffset: _islandIconVerticalOffset,
                tooltip: "Vai all'Isola delle Storie",
                onPressed: () => SeaFooterBar.openIsland(context),
                tint: HonooColor.onBackground,
              ),
              const TextSpan(text: '\n'),
              WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: Transform.translate(
                  key: const Key('home_island_followup_text_offset'),
                  offset: const Offset(0, _islandFollowupTextVerticalOffset),
                  child: Text(
                    'e viaggia nelle tue storie',
                    key: const Key('home_island_followup_text'),
                    style: regularStyle,
                  ),
                ),
              ),
              const TextSpan(text: '\n\nO'),
              const WidgetSpan(
                child: SizedBox(key: Key('home_honoo_leading_gap'), width: 8),
              ),
              WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: HonooAppTitle(
                  key: const Key('home_inline_honoo'),
                  fontSize: 23,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const PlaceholderPage(),
                      ),
                    );
                  },
                ),
              ),
              const TextSpan(text: '\ne vedi tutto'),
            ],
          ),
          key: const Key('home_intro_text'),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  static WidgetSpan _inlineAction({
    required Key key,
    required String asset,
    required double size,
    double verticalOffset = 0,
    required String tooltip,
    required VoidCallback onPressed,
    Color? tint,
  }) {
    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: Transform.translate(
        offset: Offset(0, verticalOffset),
        child: IconButton(
          key: key,
          constraints: BoxConstraints.tightFor(width: size, height: size),
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          tooltip: tooltip,
          onPressed: onPressed,
          icon: SvgPicture.asset(
            asset,
            width: size,
            height: size,
            colorFilter: tint == null
                ? null
                : ColorFilter.mode(tint, BlendMode.srcIn),
          ),
        ),
      ),
    );
  }
}
