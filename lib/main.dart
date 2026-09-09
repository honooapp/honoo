import 'package:flutter/material.dart';
import 'dart:async';
import 'package:honoo/IsolaDelleStorie/Controller/exercise_controller.dart';
import 'package:sizer/sizer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'env/env.dart';
import 'Utility/app_logger.dart';
import 'Utility/app_diagnostics.dart';
import 'Controller/honoo_controller.dart';

import 'Pages/auth_gate.dart';
import 'Pages/chest_page.dart';
import 'Pages/email_login_page.dart';
import 'Utility/honoo_colors.dart';
import 'Widgets/global_invite_listener.dart';
import 'Widgets/global_reply_notification_listener.dart';
import 'Widgets/storiestorie_access_dialog.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppDiagnostics.installGlobalHandlers();
  try {
    final supabaseUrl = readEnv('SUPABASE_URL');
    final supabaseAnon = readEnv('SUPABASE_ANON_KEY');
    if (supabaseUrl.isEmpty || supabaseAnon.isEmpty) {
      throw 'SUPABASE_URL/SUPABASE_ANON_KEY non configurati';
    }
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnon,
    ).timeout(const Duration(seconds: 5));
    ExerciseController().init();
    runApp(const MyApp());
    unawaited(_refreshSessionInBackground());
  } catch (e) {
    AppDiagnostics.record(
      code: 'bootstrap_failed',
      scope: 'bootstrap',
      error: e,
    );
    runApp(_BootErrorApp(message: 'Errore inizializzazione: $e'));
  }
}

Future<void> _refreshSessionInBackground() async {
  try {
    await Supabase.instance.client.auth.refreshSession().timeout(
      const Duration(seconds: 5),
    );
  } catch (error, stackTrace) {
    AppLogger.warning(
      'Refresh iniziale della sessione non riuscito',
      scope: 'bootstrap',
      error: error,
      stackTrace: stackTrace,
    );
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  static final Uri _storieStorieNovelUri = Uri.parse(
    'https://docs.google.com/document/d/1JdXAggCLLIMFZBo_lD80JD7IoQpAXEQQdtiSOVKnrJA/edit?usp=drive_link',
  );

  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<AuthState>? _authSub;
  bool _handledStorieStorieContinuation = false;

  @override
  void initState() {
    super.initState();
    // Guard globale: se la sessione diventa nulla (refresh fallito/expired), torna al Placeholder.
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final session = data.session;
      if (!mounted) return;
      if (session == null) {
        HonooController().clearCache();
        _navigatorKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AuthGate()),
          (route) => false,
        );
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_continueToStorieStorieNovel());
    });
  }

  Future<void> _continueToStorieStorieNovel() async {
    if (_handledStorieStorieContinuation ||
        !isStorieStorieContinuation(Uri.base)) {
      return;
    }
    _handledStorieStorieContinuation = true;

    if (Supabase.instance.client.auth.currentUser == null) {
      final loggedIn = await _navigatorKey.currentState?.push<bool>(
        MaterialPageRoute(builder: (_) => const EmailLoginPage()),
      );
      if (loggedIn != true ||
          Supabase.instance.client.auth.currentUser == null) {
        return;
      }
    }

    if (!mounted) return;
    final context = _navigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    final continueToDrive = await showDialog<bool>(
      context: context,
      builder: (_) => const StorieStorieAccessDialog(),
    );
    if (continueToDrive != true) return;

    await launchUrl(_storieStorieNovelUri, webOnlyWindowName: '_self');
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Sizer(
      builder: (context, orientation, deviceType) {
        final Widget app = MaterialApp(
          navigatorKey: _navigatorKey,
          title: 'honoo',
          theme: ThemeData(
            tooltipTheme: TooltipThemeData(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [HonooColor.wave1, HonooColor.primary],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: const TextStyle(color: Colors.white),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
          home: const AuthGate(),
          routes: {'/chest': (context) => const ChestPage()},
        );
        return GlobalReplyNotificationListener(
          navigatorKey: _navigatorKey,
          enabled: !isStorieStorieContinuation(Uri.base),
          child: SafeArea(
            child: GlobalInviteListener(
              navigatorKey: _navigatorKey,
              enabled: true,
              child: app,
            ),
          ),
        );
      },
    );
  }
}

class _BootErrorApp extends StatelessWidget {
  const _BootErrorApp({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(message, textAlign: TextAlign.center),
          ),
        ),
      ),
    );
  }
}
