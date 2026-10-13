import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../Entities/casa_share_mode.dart';
import '../Services/house_guests_service.dart';
import '../UI/hinoo_viewer.dart';
import '../UI/honoo_card.dart';
import '../Utility/honoo_colors.dart';
import '../Widgets/honoo_dialogs.dart';
import '../Widgets/loading_spinner.dart';

class HouseGuestsPage extends StatefulWidget {
  const HouseGuestsPage({super.key, required this.houseTag, this.service});
  final String houseTag;
  final HouseGuestsService? service;

  @override
  State<HouseGuestsPage> createState() => _HouseGuestsPageState();
}

class _HouseGuestsPageState extends State<HouseGuestsPage> {
  late final _service = widget.service ?? HouseGuestsService();
  List<HouseGuest> _guests = [];
  final Set<String> _saving = {};
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final guests = await _service.fetch(widget.houseTag);
      if (mounted) setState(() => _guests = guests);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle(HouseGuest guest, CasaShareMode mode) async {
    if (_saving.contains(guest.id)) return;
    final modes = {...guest.modes};
    if (!modes.add(mode)) modes.remove(mode);
    setState(() => _saving.add(guest.id));
    try {
      await _service.update(guest.id, modes);
      if (!mounted) return;
      setState(
        () => _guests = _guests
            .map((g) => g.id == guest.id ? g.withModes(modes) : g)
            .toList(),
      );
    } catch (_) {
      if (mounted) {
        showHonooToast(context, message: 'Permessi non salvati. Ritenta.');
      }
    } finally {
      if (mounted) setState(() => _saving.remove(guest.id));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: HonooColor.background,
    appBar: AppBar(
      title: const Text('ospiti'),
      backgroundColor: HonooColor.background,
      foregroundColor: Colors.white,
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: _loading
              ? const LoadingSpinner(color: Colors.white)
              : _failed
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Impossibile caricare gli ospiti.',
                      style: TextStyle(color: Colors.white),
                    ),
                    TextButton(onPressed: _load, child: const Text('Riprova')),
                  ],
                )
              : _guests.isEmpty
              ? const Text(
                  'Non hai ancora accolto ospiti.',
                  style: TextStyle(color: Colors.white),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _guests.length,
                  separatorBuilder: (_, _) =>
                      const Divider(color: Colors.white24, height: 32),
                  itemBuilder: (context, index) {
                    final guest = _guests[index];
                    return Row(
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: SizedBox(
                              width: 112,
                              height: 168,
                              child: Semantics(
                                label: guest.honoo != null
                                    ? 'honoo ricevuto'
                                    : 'hinoo ricevuto',
                                child: IgnorePointer(
                                  child: ClipRect(
                                    child: FittedBox(
                                      fit: BoxFit.contain,
                                      child: SizedBox(
                                        width: 360,
                                        height: 540,
                                        child: guest.honoo != null
                                            ? HonooCard(honoo: guest.honoo!)
                                            : guest.hinoo != null
                                            ? HinooViewer(
                                                draft: guest.hinoo!,
                                                maxWidth: 360,
                                                maxHeight: 540,
                                              )
                                            : const Center(
                                                child: Text(
                                                  'Contenuto non disponibile',
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        for (final mode in CasaShareMode.values)
                          Semantics(
                            selected: guest.modes.contains(mode),
                            button: true,
                            label:
                                '${mode.label}: ${guest.modes.contains(mode) ? "accesso dato" : "accesso non dato"}',
                            child: IconButton(
                              key: ValueKey('guest-${guest.id}-${mode.name}'),
                              tooltip:
                                  '${guest.modes.contains(mode) ? "Revoca" : "Consenti"}: ${mode.label}',
                              onPressed: _saving.contains(guest.id)
                                  ? null
                                  : () => _toggle(guest, mode),
                              iconSize: 36,
                              icon: Opacity(
                                opacity: guest.modes.contains(mode) ? 1 : 0.25,
                                child: SvgPicture.asset(
                                  switch (mode) {
                                    CasaShareMode.home =>
                                      'assets/icons/honoo_chest_blue.svg',
                                    CasaShareMode.moon =>
                                      'assets/icons/honoo_chest_white.svg',
                                    CasaShareMode.all =>
                                      'assets/icons/chest_home.svg',
                                  },
                                  width: 36,
                                  height: 36,
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
        ),
      ),
    ),
  );
}
