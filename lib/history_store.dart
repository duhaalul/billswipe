import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'bill.dart';

class HistoryEntry {
  HistoryEntry(this.bill, this.savedAt);
  final Bill bill;
  final DateTime savedAt;
  Map<String, dynamic> toJson() => {
    'bill': bill.toJson(),
    'savedAt': savedAt.toIso8601String(),
  };
  factory HistoryEntry.fromJson(Map<String, dynamic> value) => HistoryEntry(
    Bill.decode(jsonEncode(value['bill'])),
    DateTime.parse(value['savedAt'] as String),
  );
}

class HistoryStore {
  HistoryStore(this.accountId);
  final String? accountId;
  String get key => 'billswipe.history.${accountId ?? 'offline'}';
  static Future<void> _queue = Future.value();

  Future<List<HistoryEntry>> read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return [];
    final entries = (jsonDecode(raw) as List)
        .map((e) => HistoryEntry.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    entries.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return entries;
  }

  Future<void> save(Bill bill) {
    if (bill.items.isEmpty) return Future.value();
    final snapshot = Bill.decode(bill.encode());
    final operation = _queue.then((_) async {
      final entries = await read();
      entries.removeWhere((e) => e.bill.id == snapshot.id);
      entries.insert(0, HistoryEntry(snapshot, DateTime.now()));
      final prefs = await SharedPreferences.getInstance();
      final saved = await prefs.setString(
        key,
        jsonEncode(entries.map((e) => e.toJson()).toList()),
      );
      if (!saved) throw StateError('History could not be saved');
    });
    _queue = operation.then<void>((_) {}, onError: (Object e, StackTrace s) {});
    return operation;
  }
}
