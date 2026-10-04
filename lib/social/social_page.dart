import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../input_dialog.dart';
import 'backend.dart';
import 'notifications.dart';
import 'push_service.dart';

class SocialPage extends StatefulWidget {
  const SocialPage({super.key});
  @override
  State<SocialPage> createState() => _SocialPageState();
}

class _SocialPageState extends State<SocialPage> {
  Map<String, dynamic>? profile;
  List<Map<String, dynamic>> connections = [], notices = [], requests = [];
  RealtimeChannel? channel;
  String? error;
  bool busy = false;
  int loadSerial = 0;
  @override
  void initState() {
    super.initState();
    _load();
    channel = Backend.client.channel('account-${Backend.userId}');
    for (final table in ['friendships', 'notifications', 'payment_requests']) {
      channel!.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        callback: (_) => _load(),
      );
    }
    channel!.subscribe();
  }

  @override
  void dispose() {
    if (channel != null) Backend.client.removeChannel(channel!);
    super.dispose();
  }

  Future<void> _load() async {
    final serial = ++loadSerial;
    try {
      final own = await Backend.client
          .from('profiles')
          .select()
          .eq('id', Backend.userId!)
          .single();
      final friends = await Backend.connections();
      final notifications = await Backend.client
          .from('notifications')
          .select()
          .order('created_at', ascending: false)
          .limit(50);
      final bills = await Backend.client
          .from('payment_requests')
          .select(
            '*, sender_profile:profiles!payment_requests_sender_fkey(display_name,qris_path), recipient_profile:profiles!payment_requests_recipient_fkey(display_name)',
          )
          .order('created_at', ascending: false)
          .limit(50);
      if (!mounted || serial != loadSerial) return;
      setState(() {
        profile = own;
        connections = friends;
        notices = notifications;
        requests = bills;
        error = null;
      });
    } catch (e) {
      if (mounted && serial == loadSerial) {
        setState(() => error = Backend.message(e));
      }
    }
  }

  Future<void> _action(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
      if (mounted && Backend.userId != null) await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(Backend.message(e))));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _requestFriend() async {
    final result = await showDialog<List<String>>(
      context: context,
      builder: (_) => InputDialog(
        title: 'Tambah teman',
        labels: const ['Kode teman'],
        values: const [''],
        validate: (v) => v[0].isEmpty ? 'Isi kode teman.' : null,
      ),
    );
    if (!mounted || result == null) return;
    await _action(() async {
      await Backend.client.rpc('request_friend', params: {'code': result[0]});
    });
  }

  Future<void> _payment(Map<String, dynamic> request) async {
    final sender = request['sender_profile'] as Map<String, dynamic>?;
    final path = sender?['qris_path'] as String?;
    await _action(() async {
      final url = path == null
          ? null
          : await Backend.client.storage
                .from('qris')
                .createSignedUrl(path, 300);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Bayar ke ${sender?['display_name'] ?? 'teman'}',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Rp${request['amount']}',
                  style: const TextStyle(fontSize: 28),
                ),
                const SizedBox(height: 16),
                if (url != null)
                  Image.network(
                    url,
                    height: 260,
                    errorBuilder: (_, error, stack) =>
                        const Text('QRIS tidak dapat dimuat. Coba lagi.'),
                  )
                else
                  const Text('Teman belum mengunggah QRIS.'),
                const SizedBox(height: 12),
                const Text(
                  'Bayar melalui aplikasi bank atau dompet digital Anda. QRIS statis ini belum mendukung konfirmasi otomatis di BillSwipe.',
                ),
                TextButton.icon(
                  onPressed: () => Clipboard.setData(
                    ClipboardData(text: request['amount'].toString()),
                  ),
                  icon: const Icon(Icons.copy),
                  label: const Text('Salin nominal'),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Teman & tagihan'),
      actions: [
        const NotificationBell(),
        IconButton(
          tooltip: 'Muat ulang',
          onPressed: _load,
          icon: const Icon(Icons.refresh),
        ),
        IconButton(
          tooltip: 'Keluar akun',
          onPressed: busy
              ? null
              : () => _action(() async {
                  await PushService.unregister();
                  await Backend.client.auth.signOut();
                }),
          icon: const Icon(Icons.logout),
        ),
      ],
    ),
    body: RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (error != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(error!),
              ),
            ),
          if (profile == null && error == null) const LinearProgressIndicator(),
          if (profile != null) ...[
            Text(
              profile!['display_name'] as String,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Kode teman saya'),
              subtitle: SelectableText(profile!['friend_code'] as String),
              trailing: IconButton(
                tooltip: 'Salin kode',
                onPressed: () => Clipboard.setData(
                  ClipboardData(text: profile!['friend_code'] as String),
                ),
                icon: const Icon(Icons.copy),
              ),
            ),
          ],
          FilledButton.icon(
            onPressed: busy ? null : _requestFriend,
            icon: const Icon(Icons.person_add),
            label: const Text('Tambah teman dengan kode'),
          ),
          const SizedBox(height: 20),
          const Text(
            'Pertemanan',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          if (connections.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text(
                'Belum ada teman. Bagikan kode Anda atau masukkan kode teman.',
              ),
            ),
          for (final row in connections)
            Card(
              child: ListTile(
                title: Text(row['display_name'] as String),
                subtitle: Text(
                  row['status'] == 'accepted'
                      ? 'Teman'
                      : row['incoming'] == true
                      ? 'Ingin berteman dengan Anda'
                      : 'Menunggu persetujuan',
                ),
                trailing: row['status'] == 'pending' && row['incoming'] == true
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Tolak',
                            onPressed: busy
                                ? null
                                : () => _action(() async {
                                    await Backend.client.rpc(
                                      'respond_friend',
                                      params: {
                                        'request_id': row['request_id'],
                                        'accept_request': false,
                                      },
                                    );
                                  }),
                            icon: const Icon(Icons.close),
                          ),
                          IconButton(
                            tooltip: 'Terima',
                            onPressed: busy
                                ? null
                                : () => _action(() async {
                                    await Backend.client.rpc(
                                      'respond_friend',
                                      params: {
                                        'request_id': row['request_id'],
                                        'accept_request': true,
                                      },
                                    );
                                  }),
                            icon: const Icon(Icons.check),
                          ),
                        ],
                      )
                    : null,
              ),
            ),
          const SizedBox(height: 20),
          const Text(
            'Tagihan',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          if (requests.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text('Belum ada tagihan yang dikirim atau diterima.'),
            ),
          for (final row in requests)
            Card(
              child: ListTile(
                title: Text('${row['note']} • Rp${row['amount']}'),
                subtitle: Text(
                  '${row['sender'] == Backend.userId ? 'Kepada ${(row['recipient_profile'] as Map?)?['display_name'] ?? 'teman'}' : 'Dari ${(row['sender_profile'] as Map?)?['display_name'] ?? 'teman'}'}\n${row['status'] == 'paid' ? 'Terbayar' : 'Menunggu pembayaran'}',
                ),
                isThreeLine: true,
                trailing:
                    row['recipient'] == Backend.userId &&
                        row['status'] == 'pending'
                    ? TextButton(
                        onPressed: busy ? null : () => _payment(row),
                        child: const Text('Lihat QRIS'),
                      )
                    : null,
              ),
            ),
        ],
      ),
    ),
  );
}
