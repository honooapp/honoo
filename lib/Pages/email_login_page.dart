// email_login_page.dart
import 'package:flutter/material.dart';
import 'package:honoo/Widgets/loading_spinner.dart';
import 'package:honoo/Widgets/honoo_dialogs.dart';
import 'package:honoo/Services/supabase_provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:honoo/Utility/honoo_colors.dart';

import '../Widgets/honoo_scaffold.dart';
import 'email_verify_page.dart';

class EmailLoginPage extends StatefulWidget {
  final String? pendingHonooText;
  final String? pendingImageUrl;
  final Map<String, dynamic>? pendingHinooDraft;

  const EmailLoginPage({
    super.key,
    this.pendingHonooText,
    this.pendingImageUrl,
    this.pendingHinooDraft,
  });

  @override
  State<EmailLoginPage> createState() => _EmailLoginPageState();
}

class _EmailLoginPageState extends State<EmailLoginPage> {
  final TextEditingController _emailController = TextEditingController();
  bool _isLoading = false;

  Future<void> _sendOtp() async {
    setState(() => _isLoading = true);
    final email = _emailController.text.trim();

    if (email.isEmpty) {
      setState(() => _isLoading = false);
      if (!mounted) return;
      showHonooToast(context, message: 'Inserisci prima la tua email');
      return;
    }

    try {
      await SupabaseProvider.client.auth.signInWithOtp(email: email);

      if (!mounted) return;

      final ok = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (context) => EmailVerifyPage(
            email: email,
            pendingHonooText: widget.pendingHonooText,
            pendingImageUrl: widget.pendingImageUrl,
            pendingHinooDraft: widget.pendingHinooDraft,
          ),
        ),
      );

      if (!mounted) return;

      // Se login completato: chiudi anche EmailLoginPage e torna all'editor
      if (ok == true) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (!mounted) return;
      showHonooToast(context, message: 'Errore invio OTP: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inputDecoration = InputDecoration(
      hintText: 'Email',
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

    final button = ElevatedButton(
      onPressed: _isLoading ? null : _sendOtp,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 0,
      ),
      child: Text(
        _isLoading ? 'Invio in corso…' : 'Invia codice',
        style: GoogleFonts.libreFranklin(fontWeight: FontWeight.w600),
      ),
    );

    return HonooScaffold(
      showBack: true,
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 56),
                Text(
                  'Accedi con la tua email',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.arvo(
                    color: HonooColor.onBackground,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Ti invieremo un codice di verifica\n'
                  'Inserisci la tua email\ne premi “Invia codice”',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.lora(
                    color: HonooColor.onBackground.withValues(alpha: 0.8),
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 32),

                // ✅ EMAIL CENTRATA
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.lora(color: Colors.white, fontSize: 16),
                  cursorColor: Colors.white,
                  decoration: inputDecoration,
                ),

                const SizedBox(height: 24),
                _isLoading
                    ? const Center(child: LoadingSpinner(color: Colors.white))
                    : button,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
