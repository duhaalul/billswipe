import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class Backend {
  static bool ready = false;
  static SupabaseClient get client => Supabase.instance.client;
  static String? get userId => ready ? client.auth.currentUser?.id : null;

  static Future<void> initialize() async {
    const url = String.fromEnvironment('SUPABASE_URL');
    const key = String.fromEnvironment('SUPABASE_ANON_KEY');
    if (url.isEmpty || key.isEmpty) return;
    await Supabase.initialize(url: url, publishableKey: key);
    ready = true;
  }

  static Future<List<Map<String, dynamic>>> connections() async =>
      List<Map<String, dynamic>>.from(await client.rpc('social_connections'));

  static Future<void> googleLogin() async {
    await client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: kIsWeb
          ? Uri.base.origin
          : 'com.billswipe.billswipe://login-callback',
    );
  }

  static String message(Object error) {
    if (error is AuthException) return error.message;
    if (error is PostgrestException) return error.message;
    return 'Tidak dapat terhubung. Periksa internet lalu coba lagi.';
  }
}
