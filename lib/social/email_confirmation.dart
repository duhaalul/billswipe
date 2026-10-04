import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'backend.dart';

class EmailConfirmation extends StatefulWidget {
  const EmailConfirmation({
    super.key,
    required this.email,
    required this.onBack,
  });
  final String email;
  final VoidCallback onBack;
  @override
  State<EmailConfirmation> createState() => _EmailConfirmationState();
}

class _EmailConfirmationState extends State<EmailConfirmation> {
  final code = TextEditingController();
  bool busy = false;
  int cooldown = 0;
  Timer? timer;
  String? message;

  @override
  void dispose() {
    timer?.cancel();
    code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await action();
    } on AuthException catch (e) {
      if (mounted) {
        setState(
          () => message = e.code == 'otp_expired'
              ? 'Kode salah atau kedaluwarsa. Periksa kode terbaru atau kirim ulang.'
              : Backend.message(e),
        );
      }
    } catch (e) {
      if (mounted) setState(() => message = Backend.message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _verify() async {
    final token = code.text.trim();
    if (!RegExp(r'^\d{6,10}$').hasMatch(token)) {
      setState(() => message = 'Masukkan kode angka dari email Anda.');
      return;
    }
    await _run(() async {
      await Backend.client.auth.verifyOTP(
        email: widget.email,
        token: token,
        type: OtpType.email,
      );
    });
  }

  Future<void> _resend() => _run(() async {
    await Backend.client.auth.resend(type: OtpType.signup, email: widget.email);
    if (!mounted) return;
    code.clear();
    setState(() {
      cooldown = 60;
      message = 'Kode baru diminta. Periksa inbox dan spam.';
    });
    timer?.cancel();
    timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => cooldown--);
      if (cooldown <= 0) t.cancel();
    });
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Konfirmasi email'),
      leading: IconButton(
        onPressed: busy ? null : widget.onBack,
        icon: const Icon(Icons.arrow_back),
      ),
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(24),
          children: [
            const Icon(
              Icons.mark_email_read_outlined,
              size: 52,
              color: Color(0xFF007F76),
            ),
            const SizedBox(height: 20),
            Text(
              'Masukkan kode dari email untuk ${widget.email}',
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 12),
            const Text(
              'Gunakan kode dari email terbaru. Belum menerima kode? Periksa folder spam atau tekan Kirim ulang kode.',
            ),
            const SizedBox(height: 24),
            TextField(
              controller: code,
              enabled: !busy,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(10),
              ],
              decoration: const InputDecoration(labelText: 'Kode OTP'),
              onSubmitted: (_) {
                if (!busy) _verify();
              },
            ),
            const SizedBox(height: 16),
            if (message != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(message!),
              ),
            FilledButton(
              onPressed: busy ? null : _verify,
              child: Text(busy ? 'Memproses...' : 'Verifikasi email'),
            ),
            TextButton(
              onPressed: busy || cooldown > 0 ? null : _resend,
              child: Text(
                cooldown > 0
                    ? 'Kirim ulang dalam ${cooldown}s'
                    : 'Kirim ulang kode',
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
