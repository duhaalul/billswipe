import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'backend.dart';
import 'push_service.dart';

class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key});
  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell>
    with WidgetsBindingObserver {
  int unread = 0;
  bool failed = false;
  RealtimeChannel? channel;
  int serial = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    final uid = Backend.userId;
    if (uid != null) {
      channel =
          Backend.client
              .channel('bell-$uid-${identityHashCode(this)}')
              .onPostgresChanges(
                event: PostgresChangeEvent.all,
                schema: 'public',
                table: 'notifications',
                filter: PostgresChangeFilter(
                  type: PostgresChangeFilterType.eq,
                  column: 'user_id',
                  value: uid,
                ),
                callback: (_) => _load(),
              )
            ..subscribe();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    if (Backend.userId == null) return;
    final request = ++serial;
    try {
      final count = await Backend.client
          .from('notifications')
          .count(CountOption.exact)
          .eq('is_read', false);
      if (mounted && request == serial) {
        setState(() {
          unread = count;
          failed = false;
        });
      }
    } catch (_) {
      if (mounted && request == serial) setState(() => failed = true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (channel != null) Backend.client.removeChannel(channel!);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: failed
        ? 'Notifikasi — muat ulang'
        : 'Notifikasi, $unread belum dibaca',
    icon: Badge(
      isLabelVisible: unread > 0 || failed,
      label: Text(
        failed
            ? '!'
            : unread > 99
            ? '99+'
            : '$unread',
      ),
      child: Icon(
        unread > 0 ? Icons.notifications_active : Icons.notifications_none,
      ),
    ),
    onPressed: () async {
      await Navigator.push(
        context,
        MaterialPageRoute<void>(builder: (_) => const NotificationsPage()),
      );
      _load();
    },
  );
}

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});
  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  List<Map<String, dynamic>> rows = [];
  bool loading = true, busy = false;
  String? error;
  RealtimeChannel? channel;
  @override
  void initState() {
    super.initState();
    _load();
    channel =
        Backend.client
            .channel('inbox-${identityHashCode(this)}')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'notifications',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'user_id',
                value: Backend.userId!,
              ),
              callback: (_) => _load(),
            )
          ..subscribe();
  }

  @override
  void dispose() {
    if (channel != null) Backend.client.removeChannel(channel!);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final result = await Backend.client
          .from('notifications')
          .select()
          .order('created_at', ascending: false)
          .limit(200);
      if (mounted) {
        setState(() {
          rows = List<Map<String, dynamic>>.from(result);
          error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Notifikasi belum bisa dimuat. Tarik layar untuk mencoba lagi.',
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _mark([String? id]) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      var query = Backend.client
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', Backend.userId!);
      if (id != null) {
        await query.eq('id', id);
      } else {
        await query.eq('is_read', false);
      }
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Belum berhasil menandai notifikasi. Coba lagi.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Notifikasi'),
      actions: [
        IconButton(
          tooltip: 'Tandai semua dibaca',
          icon: const Icon(Icons.done_all),
          onPressed: busy || rows.every((r) => r['is_read'] == true)
              ? null
              : () => _mark(),
        ),
      ],
    ),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.notifications_active_outlined),
                  label: const Text('Aktifkan notifikasi HP'),
                  onPressed: busy
                      ? null
                      : () async {
                          setState(() => busy = true);
                          try {
                            final message = await PushService.enable();
                            if (context.mounted) {
                              ScaffoldMessenger.of(
                                context,
                              ).showSnackBar(SnackBar(content: Text(message)));
                            }
                          } catch (_) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Perangkat belum bisa didaftarkan. Coba lagi nanti.',
                                  ),
                                ),
                              );
                            }
                          } finally {
                            if (mounted) setState(() => busy = false);
                          }
                        },
                ),
                const Text(
                  'Ketuk notifikasi untuk menandainya dibaca. Buka Teman & tagihan untuk merespons permintaan atau melihat tagihan.',
                ),
                const SizedBox(height: 12),
                if (error != null) Text(error!),
                if (error == null && rows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Belum ada notifikasi.'),
                  ),
                for (final row in rows)
                  Card(
                    color: row['is_read'] == true
                        ? null
                        : const Color(0xFFE8F4F0),
                    child: ListTile(
                      leading: Icon(
                        row['is_read'] == true
                            ? Icons.notifications_none
                            : Icons.notifications_active,
                        color: row['is_read'] == true
                            ? null
                            : const Color(0xFF007F76),
                      ),
                      title: Text(
                        row['title'] as String,
                        style: TextStyle(
                          fontWeight: row['is_read'] == true
                              ? FontWeight.normal
                              : FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(row['body'] as String),
                      trailing: row['is_read'] == true
                          ? null
                          : const Icon(
                              Icons.circle,
                              size: 10,
                              color: Color(0xFF007F76),
                            ),
                      onTap: busy ? null : () => _mark(row['id'] as String),
                    ),
                  ),
                if (rows.length == 200)
                  const Text('Menampilkan 200 notifikasi terbaru.'),
              ],
            ),
          ),
  );
}
