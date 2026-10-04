import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'backend.dart';
import 'social_page.dart';
import 'email_confirmation.dart';
import 'push_service.dart';
import 'notifications.dart';

class AccountGate extends StatefulWidget {
  const AccountGate({super.key, required this.billBuilder});
  final Widget Function() billBuilder;
  @override
  State<AccountGate> createState() => _AccountGateState();
}

class _AccountGateState extends State<AccountGate> {
  bool offline = false;
  int tab = 0;
  @override
  void initState() {
    super.initState();
    PushService.openedForUser.addListener(_openNotification);
    WidgetsBinding.instance.addPostFrameCallback((_) => _openNotification());
  }

  void _openNotification() {
    if (!mounted ||
        PushService.openedForUser.value == null ||
        PushService.openedForUser.value != Backend.userId) {
      return;
    }
    PushService.openedForUser.value = null;
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const NotificationsPage()));
  }

  @override
  void dispose() {
    PushService.openedForUser.removeListener(_openNotification);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!Backend.ready) return _content(false);
    return StreamBuilder<AuthState>(
      stream: Backend.client.auth.onAuthStateChange,
      builder: (_, snapshot) => _content(Backend.userId != null),
    );
  }

  Widget _content(bool signedIn) {
    if (!signedIn && !offline) {
      return LoginPage(onOffline: () => setState(() => offline = true));
    }
    if (!signedIn) {
      return Scaffold(
        body: widget.billBuilder(),
        bottomNavigationBar: SafeArea(
          child: TextButton(
            onPressed: () => setState(() => offline = false),
            child: const Text('Masuk untuk terhubung dengan teman'),
          ),
        ),
      );
    }
    return Scaffold(
      body: IndexedStack(
        index: tab,
        children: [
          KeyedSubtree(
            key: ValueKey(Backend.userId),
            child: widget.billBuilder(),
          ),
          const SocialPage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (value) => setState(() => tab = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.receipt_long), label: 'Split'),
          NavigationDestination(
            icon: Icon(Icons.people_alt_outlined),
            label: 'Teman & tagihan',
          ),
        ],
      ),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.onOffline});
  final VoidCallback onOffline;
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final email = TextEditingController();
  final password = TextEditingController();
  final name = TextEditingController();
  bool register = false;
  bool busy = false;
  String? message;
  String? confirmationEmail;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    name.dispose();
    super.dispose();
  }

  Future<void> _perform(Future<void> Function() action) async {
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => message = Backend.message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _submit() => _perform(() async {
    if (email.text.trim().isEmpty ||
        password.text.length < 8 ||
        (register && name.text.trim().isEmpty)) {
      setState(
        () => message =
            'Isi email, password minimal 8 karakter, dan nama jika mendaftar.',
      );
      return;
    }
    if (register) {
      final result = await Backend.client.auth.signUp(
        email: email.text.trim(),
        password: password.text,
        data: {'full_name': name.text.trim()},
      );
      if (mounted && result.session == null) {
        setState(() => confirmationEmail = email.text.trim());
      }
    } else {
      final loginEmail = email.text.trim();
      try {
        await Backend.client.auth.signInWithPassword(
          email: loginEmail,
          password: password.text,
        );
      } on AuthException catch (e) {
        if (e.code != 'email_not_confirmed') rethrow;
        if (mounted) {
          setState(() => confirmationEmail = loginEmail);
        }
      }
    }
  });
  @override
  Widget build(BuildContext context) => confirmationEmail != null
      ? EmailConfirmation(
          email: confirmationEmail!,
          onBack: () => setState(() => confirmationEmail = null),
        )
      : Scaffold(
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(24),
                  children: [
                    Image.asset('assets/billswipe-logo.png', height: 76),
                    const SizedBox(height: 20),
                    Text(
                      register ? 'Buat akun BillSwipe' : 'Masuk ke BillSwipe',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Terhubung dengan teman dan terima tagihan di satu tempat.',
                    ),
                    const SizedBox(height: 24),
                    OutlinedButton(
                      onPressed: Backend.ready && !busy
                          ? () => _perform(Backend.googleLogin)
                          : null,
                      child: const Text('Lanjutkan dengan Google'),
                    ),
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Center(child: Text('atau gunakan email')),
                    ),
                    if (register) ...[
                      TextField(
                        controller: name,
                        decoration: const InputDecoration(labelText: 'Nama'),
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(labelText: 'Email'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: password,
                      obscureText: true,
                      autofillHints: const [AutofillHints.password],
                      decoration: const InputDecoration(labelText: 'Password'),
                    ),
                    const SizedBox(height: 16),
                    if (!Backend.ready)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: Text(
                          'Layanan akun belum diaktifkan. Anda masih dapat membagi tagihan tanpa akun.',
                        ),
                      ),
                    if (message != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(message!),
                      ),
                    FilledButton(
                      onPressed: Backend.ready && !busy ? _submit : null,
                      child: Text(
                        busy
                            ? 'Memproses...'
                            : register
                            ? 'Daftar'
                            : 'Masuk',
                      ),
                    ),
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => setState(() {
                              register = !register;
                              message = null;
                            }),
                      child: Text(
                        register
                            ? 'Sudah punya akun? Masuk'
                            : 'Belum punya akun? Daftar',
                      ),
                    ),
                    TextButton(
                      onPressed: busy ? null : widget.onOffline,
                      child: const Text('Gunakan tanpa akun'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
}
