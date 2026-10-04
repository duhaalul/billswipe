import 'package:flutter/material.dart';

import 'bill.dart';
import 'history_store.dart';
import 'social/backend.dart';

String historyMoney(int amount) {
  final digits = amount.abs().toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (m) => '${m[1]}.',
  );
  return '${amount < 0 ? '-' : ''}Rp$digits';
}

String historyDate(DateTime value) {
  final d = value.toLocal();
  return '${d.day}/${d.month}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

String paymentStatus(String status) => switch (status) {
  'paid' => 'Terbayar',
  'pending' => 'Menunggu pembayaran',
  'expired' => 'Kedaluwarsa',
  'cancelled' => 'Dibatalkan',
  _ => 'Status belum tersedia',
};

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key, required this.store});
  final HistoryStore store;
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<HistoryEntry> entries = [];
  List<Map<String, dynamic>> payments = [];
  bool loading = true;
  String? localError, onlineError;
  String filter = 'all';
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    List<HistoryEntry> next = [];
    List<Map<String, dynamic>> remote = [];
    String? localFailure, remoteFailure;
    try {
      next = await widget.store.read();
    } catch (_) {
      localFailure = 'Riwayat perangkat belum bisa dibaca. Coba muat ulang.';
    }
    if (widget.store.accountId != null) {
      try {
        var offset = 0;
        while (true) {
          final page = await Backend.client
              .from('payment_requests')
              .select(
                '*, sender_profile:profiles!payment_requests_sender_fkey(display_name), recipient_profile:profiles!payment_requests_recipient_fkey(display_name)',
              )
              .order('created_at', ascending: false)
              .order('id')
              .range(offset, offset + 199);
          remote.addAll(List<Map<String, dynamic>>.from(page));
          if (page.length < 200) break;
          offset += page.length;
        }
      } catch (_) {
        remoteFailure = 'Status tagihan online belum bisa dimuat. Periksa internet lalu muat ulang.';
      }
    }
    if (!mounted) return;
    setState(() {
      entries = next;
      payments = remote;
      localError = localFailure;
      onlineError = remoteFailure;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Riwayat'),
        actions: [
          IconButton(
            tooltip: 'Muat ulang',
            onPressed: loading
                ? null
                : () {
                    setState(() => loading = true);
                    _load();
                  },
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: const TabBar(
          tabs: [
            Tab(text: 'Pembagian'),
            Tab(text: 'Tagihan teman'),
          ],
        ),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              children: [
                RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    children: [
                      const Text(
                        'Tersimpan di perangkat ini, terpisah untuk setiap akun. Menyimpan ulang memperbarui pembagian yang sama.',
                      ),
                      const SizedBox(height: 12),
                      if (localError != null) Text(localError!),
                      if (localError == null && entries.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'Belum ada riwayat. Simpan dari halaman hasil pembagian.',
                          ),
                        ),
                      for (final e in entries)
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.receipt_long),
                            title: Text(e.bill.title),
                            subtitle: Text(
                              '${historyDate(e.savedAt)}\n${e.bill.items.length} item • ${e.bill.people.length} peserta${e.bill.unclaimed > 0 ? ' • Belum selesai dibagi' : ''}',
                            ),
                            isThreeLine: true,
                            trailing: Text(historyMoney(e.bill.total)),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => _HistoryDetail(entry: e),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                _payments(),
              ],
            ),
    ),
  );
  Widget _payments() {
    final uid = widget.store.accountId;
    if (uid == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Masuk ke akun untuk memantau tagihan teman.'),
        ),
      );
    }
    if (onlineError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(onlineError!),
        ),
      );
    }
    final rows = payments
        .where(
          (r) =>
              filter == 'all' ||
              (filter == 'sent' && r['sender'] == uid) ||
              (filter == 'received' && r['recipient'] == uid) ||
              r['status'] == filter,
        )
        .toList();
    final pendingSent = payments
        .where((r) => r['sender'] == uid && r['status'] == 'pending')
        .fold<int>(0, (s, r) => s + (r['amount'] as num).toInt());
    final pendingReceived = payments
        .where((r) => r['recipient'] == uid && r['status'] == 'pending')
        .fold<int>(0, (s, r) => s + (r['amount'] as num).toInt());
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Menunggu dari teman: ${historyMoney(pendingSent)}'),
                  const SizedBox(height: 8),
                  Text('Tagihan untuk Anda: ${historyMoney(pendingReceived)}'),
                ],
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Status berasal dari server. Pembayaran lewat QRIS statis belum dikonfirmasi otomatis.',
            ),
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final item in {
                'all': 'Semua',
                'sent': 'Dikirim',
                'received': 'Diterima',
                'pending': 'Menunggu',
                'paid': 'Terbayar',
                'expired': 'Kedaluwarsa',
                'cancelled': 'Dibatalkan',
              }.entries)
                ChoiceChip(
                  label: Text(item.value),
                  selected: filter == item.key,
                  onSelected: (_) => setState(() => filter = item.key),
                ),
            ],
          ),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Tidak ada tagihan pada filter ini.'),
            ),
          for (final r in rows)
            Card(
              child: ListTile(
                leading: Icon(
                  r['sender'] == uid ? Icons.north_east : Icons.south_west,
                ),
                title: Text(
                  '${r['note']} • ${historyMoney((r['amount'] as num).toInt())}',
                ),
                subtitle: Text(
                  '${r['sender'] == uid ? 'Kepada ${(r['recipient_profile'] as Map?)?['display_name'] ?? 'teman'}' : 'Dari ${(r['sender_profile'] as Map?)?['display_name'] ?? 'teman'}'}\n${paymentStatus(r['status'] as String)}\n${historyDate(DateTime.parse(r['created_at'] as String))}',
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _HistoryDetail extends StatelessWidget {
  const _HistoryDetail({required this.entry});
  final HistoryEntry entry;
  @override
  Widget build(BuildContext context) {
    final bill = entry.bill;
    return Scaffold(
      appBar: AppBar(title: Text(bill.title)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Disimpan ${historyDate(entry.savedAt)}'),
          Text(
            historyMoney(bill.total),
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          Text(
            'Subtotal ${historyMoney(bill.subtotal)} • Pajak ${historyMoney(bill.tax)}\nLayanan ${historyMoney(bill.service)} • Diskon ${historyMoney(bill.discount)}',
          ),
          if (bill.unclaimed > 0) Text('${bill.unclaimed} item belum dibagi.'),
          const SizedBox(height: 20),
          const Text(
            'Bagian tiap peserta',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          for (final total in calculateTotals(bill))
            Card(
              child: ExpansionTile(
                title: Text(total.person.name),
                subtitle: Text(historyMoney(total.total)),
                children: [
                  for (final item in bill.items.where(
                    (i) => i.ownerId == total.person.id,
                  ))
                    ListTile(
                      title: Text(item.name),
                      trailing: Text(historyMoney(item.price)),
                    ),
                  ListTile(
                    title: const Text('Pajak / layanan / diskon'),
                    subtitle: Text(
                      '${historyMoney(total.tax)} / ${historyMoney(total.service)} / ${historyMoney(total.discount)}',
                    ),
                  ),
                ],
              ),
            ),
          if (bill.unclaimed > 0) ...[
            const Text('Belum dibagi'),
            for (final item in bill.items.where((i) => i.ownerId == null))
              ListTile(
                title: Text(item.name),
                trailing: Text(historyMoney(item.price)),
              ),
          ],
        ],
      ),
    );
  }
}
