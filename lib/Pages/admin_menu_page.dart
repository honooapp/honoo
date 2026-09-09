import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:honoo/Services/admin_service.dart';
import 'package:honoo/Services/supabase_provider.dart';
import 'package:honoo/Utility/honoo_colors.dart';
import 'package:honoo/Widgets/honoo_dialogs.dart';
import 'package:honoo/Widgets/honoo_scaffold.dart';
import 'package:honoo/Widgets/loading_spinner.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'home_page.dart';
import 'admin_moon_search_page.dart';

class AdminMenuPage extends StatefulWidget {
  const AdminMenuPage({super.key});

  @override
  State<AdminMenuPage> createState() => _AdminMenuPageState();
}

class _AdminMenuPageState extends State<AdminMenuPage>
    with WidgetsBindingObserver {
  final TextEditingController _emailController = TextEditingController();
  final AdminService _adminService = AdminService();
  late final Future<bool> _adminCheck;
  bool _invitingAll = false;
  bool _invitingEmail = false;
  bool _loadingEmails = false;
  bool _loadingStats = false;
  bool _statsRefreshPending = false;
  Map<String, dynamic>? _snapshot;
  String? _statsError;
  Timer? _statsDebounce;

  List<String> _emailHints = const [];
  Map<DateTime, int> _visits = const {};
  Map<String, int> _moonCounts = const {'honoo': 0, 'hinoo': 0};
  Map<String, int> _dailyCounts = const {
    'chest_honoo': 0,
    'chest_hinoo': 0,
    'moon_honoo': 0,
    'moon_hinoo': 0,
    'reply_honoo': 0,
    'reply_hinoo': 0,
  };
  Timer? _statsRefreshTimer;
  RealtimeChannel? _statsChannel;
  bool _loadingPendingInvites = false;
  List<Map<String, dynamic>> _pendingInvites = const [];
  final Set<String> _reviewingInviteIds = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _adminCheck = _adminService.isCurrentUserAdmin();
    _adminCheck.then((isAdmin) {
      if (mounted && isAdmin) {
        _loadEmailHints();
        _loadStatistics();
        _loadPendingInvites();
        _subscribeStats();
        _statsRefreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
          _loadStatistics();
          _loadPendingInvites();
        });
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _statsDebounce?.cancel();
    _statsRefreshTimer?.cancel();
    _statsChannel?.unsubscribe();
    _emailController.dispose();
    super.dispose();
  }

  void _subscribeStats() {
    if (_statsChannel != null) return;
    _statsChannel = SupabaseProvider.client.channel('admin-stats');
    _statsChannel!
        .on(
          RealtimeListenTypes.postgresChanges,
          ChannelFilter(
            event: '*',
            schema: 'public',
            table: 'admin_stats_signal',
          ),
          (dynamic _, [dynamic __]) {
            if (!mounted || _statsDebounce?.isActive == true) return;
            _statsDebounce = Timer(const Duration(milliseconds: 300), () {
              if (!mounted) return;
              _loadStatistics();
              _loadPendingInvites();
            });
          },
        )
        .subscribe((status, [error]) {
          if (mounted && status == 'SUBSCRIBED') {
            _loadStatistics();
          }
        });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _statsChannel != null) {
      _loadStatistics();
    }
  }

  Future<void> _loadStatistics() async {
    if (!mounted) return;
    if (_loadingStats) {
      _statsRefreshPending = true;
      return;
    }
    setState(() => _loadingStats = true);
    try {
      final snapshot = await _adminService.fetchStatistics();
      if (!mounted) return;
      final counts = Map<String, int>.from(
        (snapshot['daily'] as Map).map(
          (key, value) => MapEntry(key, (value as num).toInt()),
        ),
      );
      final visits = <DateTime, int>{};
      for (final entry in (snapshot['visits'] as Map).entries) {
        visits[DateTime.parse(entry.key as String)] = (entry.value as num)
            .toInt();
      }
      setState(() {
        _snapshot = snapshot;
        _dailyCounts = counts;
        _moonCounts = {
          'honoo': counts['moon_honoo'] ?? 0,
          'hinoo': counts['moon_hinoo'] ?? 0,
        };
        _visits = visits;
        _statsError = null;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _statsError =
              'Aggiornamento non riuscito. I dati precedenti potrebbero non essere attuali.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loadingStats = false);
        if (_statsRefreshPending) {
          _statsRefreshPending = false;
          unawaited(_loadStatistics());
        }
      }
    }
  }

  Future<void> _loadPendingInvites() async {
    if (_loadingPendingInvites) return;
    setState(() => _loadingPendingInvites = true);
    try {
      final list = await _adminService.fetchPendingInvites(newestFirst: true);
      if (!mounted) return;
      setState(() => _pendingInvites = list);
    } finally {
      if (mounted) setState(() => _loadingPendingInvites = false);
    }
  }

  Future<void> _reviewHouseRequest(String inviteId, bool approved) async {
    if (inviteId.isEmpty || _reviewingInviteIds.contains(inviteId)) return;
    setState(() => _reviewingInviteIds.add(inviteId));
    try {
      final updated = await _adminService.reviewHouseRequest(
        inviteId: inviteId,
        approved: approved,
      );
      if (!mounted) return;
      showHonooToast(
        context,
        message: updated
            ? (approved ? 'Richiesta approvata.' : 'Richiesta rifiutata.')
            : 'Richiesta già gestita.',
      );
      await _loadPendingInvites();
    } catch (e) {
      if (!mounted) return;
      showHonooToast(context, message: 'Errore autorizzazione: $e');
    } finally {
      if (mounted) setState(() => _reviewingInviteIds.remove(inviteId));
    }
  }

  Future<void> _loadEmailHints() async {
    if (_loadingEmails) return;
    setState(() => _loadingEmails = true);
    try {
      final emails = await _adminService.fetchUserEmails();
      if (!mounted) return;
      setState(() => _emailHints = emails);
    } finally {
      if (mounted) setState(() => _loadingEmails = false);
    }
  }

  Future<void> _inviteAll() async {
    if (_invitingAll) return;
    setState(() => _invitingAll = true);
    try {
      final user = SupabaseProvider.client.auth.currentUser;
      if (user == null) {
        throw Exception('Utente non autenticato.');
      }
      final users = await _adminService.fetchAllUsersWithEmails();
      final count = await _adminService.inviteUsers(
        adminUid: user.id,
        userIds: users.map((u) => u.authUserId).toList(),
        userEmails: {
          for (final u in users)
            if ((u.email ?? '').isNotEmpty) u.authUserId: u.email!,
        },
      );
      if (!mounted) return;
      final message = count == 0
          ? 'Nessun nuovo invito da inviare.'
          : 'Inviti inviati: $count.';
      showHonooToast(context, message: message);
    } catch (e) {
      if (!mounted) return;
      showHonooToast(context, message: 'Errore inviti: $e');
    } finally {
      if (mounted) setState(() => _invitingAll = false);
    }
  }

  Future<void> _inviteByEmail() async {
    if (_invitingEmail) return;
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      showHonooToast(context, message: 'Inserisci una email.');
      return;
    }
    setState(() => _invitingEmail = true);
    try {
      final user = SupabaseProvider.client.auth.currentUser;
      if (user == null) {
        throw Exception('Utente non autenticato.');
      }
      final target = await _adminService.findUserByEmail(email);
      if (target == null) {
        final inserted = await _adminService.inviteByEmailOnly(
          adminUid: user.id,
          email: email,
        );
        if (!mounted) return;
        showHonooToast(
          context,
          message: inserted ? 'Invito inviato.' : 'Invito già presente.',
        );
        return;
      }
      final hasCasa = await _adminService.hasCasaForUser(target.authUserId);
      if (hasCasa) {
        if (!mounted) return;
        showHonooToast(context, message: 'Utente già con casa.');
        return;
      }
      final inserted = await _adminService.inviteUsers(
        adminUid: user.id,
        userIds: [target.authUserId],
        userEmails: {
          if ((target.email ?? '').isNotEmpty) target.authUserId: target.email!,
        },
      );
      if (!mounted) return;
      if (inserted == 0) {
        showHonooToast(context, message: 'Invito già presente.');
      } else {
        showHonooToast(context, message: 'Invito inviato.');
      }
    } catch (e) {
      if (!mounted) return;
      showHonooToast(context, message: 'Errore invito: $e');
    } finally {
      if (mounted) setState(() => _invitingEmail = false);
    }
  }

  void _redirectHome() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomePage()),
      (route) => false,
    );
  }

  String _formatTimestamp(String value) {
    final date = DateTime.parse(value).toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year} ${two(date.hour)}:${two(date.minute)}:${two(date.second)}';
  }

  @override
  Widget build(BuildContext context) {
    final inputDecoration = InputDecoration(
      hintText: 'Email utente',
      hintStyle: GoogleFonts.lora(color: Colors.white70, fontSize: 16),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.08),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Colors.white24),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Colors.white24),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Colors.white60),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
    );

    return FutureBuilder<bool>(
      future: _adminCheck,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const HonooScaffold(
            body: Center(child: LoadingSpinner(color: Colors.white)),
          );
        }

        final isAdmin = snapshot.data == true;
        if (!isAdmin) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _redirectHome();
          });
          return const SizedBox.shrink();
        }

        return HonooScaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_pendingInvites.isNotEmpty) ...[
                      Text(
                        'Richieste di casa',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.arvo(
                          color: HonooColor.onBackground,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ..._pendingInvites.map((row) {
                        final String inviteId = (row['id']?.toString() ?? '')
                            .trim();
                        final String email = (row['email']?.toString() ?? '')
                            .trim();
                        final String userId = (row['user_id']?.toString() ?? '')
                            .trim();
                        final String label = email.isNotEmpty
                            ? email
                            : (userId.isNotEmpty ? userId : 'Richiesta');
                        final String when =
                            (row['created_at']?.toString() ?? '');
                        final bool reviewing = _reviewingInviteIds.contains(
                          inviteId,
                        );
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.07),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  '$label — $when',
                                  style: GoogleFonts.lora(
                                    color: HonooColor.onBackground.withValues(
                                      alpha: 0.9,
                                    ),
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    TextButton(
                                      onPressed: reviewing
                                          ? null
                                          : () => _reviewHouseRequest(
                                              inviteId,
                                              false,
                                            ),
                                      child: const Text('Rifiuta'),
                                    ),
                                    const SizedBox(width: 8),
                                    ElevatedButton(
                                      onPressed: reviewing
                                          ? null
                                          : () => _reviewHouseRequest(
                                              inviteId,
                                              true,
                                            ),
                                      child: reviewing
                                          ? const LoadingSpinner(
                                              size: 18,
                                              color: Colors.black,
                                            )
                                          : const Text('Approva'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                      const SizedBox(height: 20),
                    ],
                    const SizedBox(height: 24),
                    Text(
                      'Menu Admin',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.arvo(
                        color: HonooColor.onBackground,
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Invita gli utenti a creare la loro casa.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.lora(
                        color: HonooColor.onBackground.withValues(alpha: 0.8),
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 32),
                    // Ricerca Luna (admin)
                    ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const AdminMoonSearchPage(),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        'Cerca su Luna (admin)',
                        style: GoogleFonts.libreFranklin(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton(
                      onPressed: _invitingAll ? null : _inviteAll,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: _invitingAll
                          ? const LoadingSpinner(color: Colors.black)
                          : Text(
                              'Invita tutti gli utenti',
                              style: GoogleFonts.libreFranklin(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                    const SizedBox(height: 32),
                    Text(
                      'Invita un utente per email',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.arvo(
                        color: HonooColor.onBackground,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Autocomplete<String>(
                      optionsBuilder: (value) {
                        if (value.text.trim().isEmpty) {
                          return const Iterable<String>.empty();
                        }
                        final query = value.text.toLowerCase();
                        return _emailHints.where(
                          (email) => email.toLowerCase().contains(query),
                        );
                      },
                      onSelected: (selection) {
                        _emailController.text = selection;
                      },
                      fieldViewBuilder:
                          (
                            context,
                            textController,
                            focusNode,
                            onFieldSubmitted,
                          ) {
                            if (textController.text != _emailController.text) {
                              textController.text = _emailController.text;
                              textController.selection =
                                  TextSelection.collapsed(
                                    offset: textController.text.length,
                                  );
                            }
                            return TextField(
                              controller: textController,
                              focusNode: focusNode,
                              keyboardType: TextInputType.emailAddress,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.lora(
                                color: Colors.white,
                                fontSize: 16,
                              ),
                              cursorColor: Colors.white,
                              decoration: inputDecoration.copyWith(
                                suffixIcon: _loadingEmails
                                    ? const Padding(
                                        padding: EdgeInsets.all(12),
                                        child: LoadingSpinner(
                                          size: 16,
                                          color: Colors.white,
                                        ),
                                      )
                                    : null,
                              ),
                              onChanged: (value) {
                                _emailController.text = value;
                              },
                            );
                          },
                      optionsViewBuilder: (context, onSelected, options) {
                        return Align(
                          alignment: Alignment.topCenter,
                          child: Material(
                            color: Colors.black.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(12),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                maxHeight: 220,
                                maxWidth: 420,
                              ),
                              child: ListView.builder(
                                padding: const EdgeInsets.all(8),
                                itemCount: options.length,
                                itemBuilder: (context, index) {
                                  final option = options.elementAt(index);
                                  return ListTile(
                                    dense: true,
                                    title: Text(
                                      option,
                                      style: GoogleFonts.lora(
                                        color: Colors.white,
                                        fontSize: 14,
                                      ),
                                    ),
                                    onTap: () => onSelected(option),
                                  );
                                },
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _invitingEmail ? null : _inviteByEmail,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: _invitingEmail
                          ? const LoadingSpinner(color: Colors.black)
                          : Text(
                              'Invita utente',
                              style: GoogleFonts.libreFranklin(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                    const SizedBox(height: 32),
                    if (_statsError != null)
                      Text(
                        _statsError!,
                        style: const TextStyle(color: Colors.orange),
                      ),
                    if (_snapshot == null && _loadingStats)
                      const Center(child: LoadingSpinner(color: Colors.white)),
                    if (_snapshot != null) ...[
                      _RollingCount(
                        label: 'Utenti attivi (ultimi 2 minuti)',
                        count: (_snapshot!['active_users'] as num).toInt(),
                      ),
                      _RollingCount(
                        label: 'Utenti registrati',
                        count: (_snapshot!['registered_users'] as num).toInt(),
                      ),
                      _RollingCount(
                        label: 'Case',
                        count: (_snapshot!['houses'] as num).toInt(),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Accessi autenticati alla home',
                        style: TextStyle(color: Colors.white),
                      ),
                      Text(
                        'Rilevati dal ${_formatTimestamp(_snapshot!['tracking_started_at'] as String)}. Amministratori esclusi.',
                        style: const TextStyle(color: Colors.white70),
                      ),
                      _VisitsSummary(
                        visits: _visits,
                        today: DateTime.parse(_snapshot!['today'] as String),
                        trackingStartedAt: DateTime.parse(
                          _snapshot!['tracking_started_date'] as String,
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Luna oggi',
                        style: TextStyle(color: Colors.white),
                      ),
                      _MoonCountsSummary(counts: _moonCounts),
                      const SizedBox(height: 24),
                      const Text(
                        'Creazioni e invii di oggi (Europe/Rome)',
                        style: TextStyle(color: Colors.white),
                      ),
                      _DailyCountsSummary(counts: _dailyCounts),
                      const Text(
                        'Admin e copie salvate dalla Luna esclusi. Le attività eliminate prima della nuova rilevazione non sono ricostruibili.',
                        style: TextStyle(color: Colors.white70),
                      ),
                      Text(
                        'Ultimo aggiornamento: ${_formatTimestamp(_snapshot!['generated_at'] as String)}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _VisitsSummary extends StatelessWidget {
  const _VisitsSummary({
    required this.visits,
    required this.today,
    required this.trackingStartedAt,
  });

  final Map<DateTime, int> visits;
  final DateTime today;
  final DateTime trackingStartedAt;

  @override
  Widget build(BuildContext context) {
    final DateTime day0 = DateTime(today.year, today.month, today.day);
    final DateTime day1 = day0.subtract(const Duration(days: 1));
    final DateTime day2 = day0.subtract(const Duration(days: 2));

    // A pre-tracking day is unknown, not a day with zero visits.
    Widget row(String label, DateTime day) {
      if (day.isBefore(trackingStartedAt)) {
        return Text(
          '$label: non disponibile',
          style: const TextStyle(color: Colors.white70),
        );
      }
      return _VisitRow(label: label, count: visits[day] ?? 0);
    }

    final rows = [
      row('Oggi', day0),
      row('Ieri', day1),
      row("L'altro ieri", day2),
    ];

    return Column(children: rows);
  }
}

class _VisitRow extends StatelessWidget {
  const _VisitRow({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        '$label: $count',
        textAlign: TextAlign.center,
        style: GoogleFonts.lora(
          color: HonooColor.onBackground.withValues(alpha: 0.85),
          fontSize: 16,
        ),
      ),
    );
  }
}

class _MoonCountsSummary extends StatelessWidget {
  const _MoonCountsSummary({required this.counts});

  final Map<String, int> counts;

  @override
  Widget build(BuildContext context) {
    final honoo = counts['honoo'] ?? 0;
    final hinoo = counts['hinoo'] ?? 0;
    return Column(
      children: [
        _RollingCount(label: 'honoo', count: honoo),
        _RollingCount(label: 'hinoo', count: hinoo),
      ],
    );
  }
}

class _RollingCount extends StatelessWidget {
  const _RollingCount({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Text(
              '$label: ',
              style: GoogleFonts.lora(
                color: HonooColor.onBackground.withValues(alpha: 0.85),
                fontSize: 16,
              ),
            ),
          ),
          _RollingNumber(value: count),
        ],
      ),
    );
  }
}

class _RollingNumber extends StatelessWidget {
  const _RollingNumber({required this.value});

  final int value;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      transitionBuilder: (child, animation) {
        final offset = Tween<Offset>(
          begin: const Offset(0, -0.6),
          end: Offset.zero,
        ).animate(animation);
        return ClipRect(
          child: SlideTransition(position: offset, child: child),
        );
      },
      child: Text(
        '$value',
        key: ValueKey(value),
        style: GoogleFonts.libreFranklin(
          color: HonooColor.onBackground,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _DailyCountsSummary extends StatelessWidget {
  const _DailyCountsSummary({required this.counts});

  final Map<String, int> counts;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _RollingCount(
          label: 'honoo creati nello scrigno',
          count: counts['chest_honoo'] ?? 0,
        ),
        _RollingCount(
          label: 'hinoo creati nello scrigno',
          count: counts['chest_hinoo'] ?? 0,
        ),
        _RollingCount(
          label: 'honoo inviati sulla Luna',
          count: counts['moon_honoo'] ?? 0,
        ),
        _RollingCount(
          label: 'hinoo inviati sulla Luna',
          count: counts['moon_hinoo'] ?? 0,
        ),
        _RollingCount(
          label: 'honoo in risposta',
          count: counts['reply_honoo'] ?? 0,
        ),
        _RollingCount(
          label: 'hinoo in risposta',
          count: counts['reply_hinoo'] ?? 0,
        ),
      ],
    );
  }
}
