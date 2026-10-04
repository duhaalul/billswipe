import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:file_selector/file_selector.dart' as files;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'bill.dart';
import 'history_store.dart';
import 'history_page.dart';
import 'receipt_parser.dart';
import 'input_dialog.dart';
import 'receipt_crop_page.dart';
import 'social/backend.dart';
import 'social/notifications.dart';
import 'social/push_service.dart';
import 'social/account_gate.dart';

import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Backend.initialize();
  if (Backend.ready) await PushService.initialize();
  runApp(const BillSwipeApp());
}

const ink = Color(0xFF153238);
const teal = Color(0xFF007F76);
const pale = Color(0xFFE8F4F0);

String rupiah(int amount) {
  final raw = amount.abs().toString();
  final groups = <String>[];
  for (var end = raw.length; end > 0; end -= 3) {
    groups.insert(0, raw.substring((end - 3).clamp(0, raw.length), end));
  }
  return '${amount < 0 ? '-' : ''}Rp${groups.join('.')}';
}

class BillSwipeApp extends StatelessWidget {
  const BillSwipeApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'BillSwipe',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFFF5F8F7),
      colorScheme: ColorScheme.fromSeed(seedColor: teal),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFF5F8F7),
        foregroundColor: ink,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    home: AccountGate(billBuilder: () => const BillHome()),
  );
}

class BillHome extends StatefulWidget {
  const BillHome({super.key, this.selectImage});
  final Future<XFile?> Function(ImageSource)? selectImage;
  @override
  State<BillHome> createState() => _BillHomeState();
}

class _BillHomeState extends State<BillHome> {
  Bill bill = Bill(
    items: [],
    people: [Person(id: 'host', name: 'Saya')],
  );
  int step = 0;
  int serial = 0;
  bool loading = true;
  bool scanning = false;
  String? qrisPath;
  Uint8List? qrisBytes;
  Uint8List? receiptBytes;
  bool sending = false;
  bool savingHistory = false;
  late final HistoryStore history = HistoryStore(Backend.userId);
  late final String storageSuffix = Backend.userId == null
      ? ''
      : '-${Backend.userId}';

  @override
  void initState() {
    super.initState();
    _restore();
  }

  String _id() => '${DateTime.now().microsecondsSinceEpoch}-${serial++}';
  void _notice(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
  void _change(VoidCallback callback) {
    setState(callback);
    _save();
  }

  Future<void> _restore() async {
    if (Backend.userId != null) {
      try {
        final profile = await Backend.client
            .from('profiles')
            .select('qris_path')
            .eq('id', Backend.userId!)
            .maybeSingle();
        final path = profile?['qris_path'] as String?;
        if (path != null) {
          qrisBytes = await Backend.client.storage.from('qris').download(path);
        }
      } catch (e) {
        debugPrint('Could not restore account QRIS: ${Backend.message(e)}');
      }
      if (!mounted) return;
    }
    if (kIsWeb) {
      setState(() => loading = false);
      return;
    }
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/bill$storageSuffix.json');
      if (await file.exists()) bill = Bill.decode(await file.readAsString());
      final qris = File('${dir.path}/qris$storageSuffix.png');
      if (await qris.exists()) qrisPath = qris.path;
    } catch (_) {
      /* Start with an empty bill if an old save is unreadable. */
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _save() async {
    if (kIsWeb) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      await File('${dir.path}/bill$storageSuffix.json')
          .writeAsString(bill.encode(), flush: true);
    } catch (_) {
      if (mounted) _notice('Tagihan belum dapat disimpan di perangkat.');
    }
  }

  Future<XFile?> _selectImage(ImageSource source) {
    if (widget.selectImage != null) return widget.selectImage!(source);
    if (kIsWeb) {
      return files.openFile(
        acceptedTypeGroups: const [
          files.XTypeGroup(
            label: 'Gambar',
            extensions: ['png', 'jpg', 'jpeg', 'webp'],
            mimeTypes: ['image/png', 'image/jpeg', 'image/webp'],
          ),
        ],
      );
    }
    return ImagePicker().pickImage(
      source: source,
      maxWidth: 2400,
      imageQuality: 95,
    );
  }

  Future<void> _scan(ImageSource source) async {
    if (scanning) return;
    setState(() => scanning = true);
    try {
      final photo = await _selectImage(source);
      if (photo == null || !mounted) return;
      if (kIsWeb) {
        final bytes = await photo.readAsBytes();
        if (!mounted) return;
        setState(() {
          receiptBytes = bytes;
          step = 1;
        });
        _notice('Gambar berhasil dibuka. Di Chrome, isi item secara manual.');
        return;
      }
      final bytes = await photo.readAsBytes();
      if (!mounted) return;
      final cropped = await Navigator.of(context).push<Uint8List>(
        MaterialPageRoute(builder: (_) => ReceiptCropPage(bytes: bytes)),
      );
      if (cropped == null) return;
      final dir = await getTemporaryDirectory();
      final croppedFile = File('${dir.path}/receipt-${_id()}.png');
      await croppedFile.writeAsBytes(cropped, flush: true);
      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      try {
        final text = await recognizer.processImage(
          InputImage.fromFilePath(croppedFile.path),
        );
        final parsed = parseReceipt(text.text);
        if (!mounted) return;
        _change(() {
          bill.items.addAll(
            parsed.items.map(
              (item) => BillItem(id: _id(), name: item.name, price: item.price),
            ),
          );
          bill.tax += parsed.tax;
          bill.service += parsed.service;
          bill.discount += parsed.discount;
          step = 1;
        });
        _notice(
          parsed.items.isEmpty
              ? 'Item belum terbaca. Tambahkan secara manual.'
              : '${parsed.items.length} item terbaca. Periksa hasilnya.',
        );
      } finally {
        await recognizer.close();
        if (await croppedFile.exists()) await croppedFile.delete();
      }
    } catch (error, stack) {
      debugPrint('Receipt import failed: $error\n$stack');
      if (mounted) {
        _notice(
          kIsWeb
              ? 'Gambar gagal dibuka. Pilih file JPG atau PNG yang tersimpan di komputer.'
              : 'Pemindaian gagal. Coba foto JPG/PNG atau isi item manual.',
        );
      }
    } finally {
      if (mounted) setState(() => scanning = false);
    }
  }

  Future<void> _editItem([BillItem? item]) async {
    final values = await showDialog<List<String>>(
      context: context,
      builder: (_) => InputDialog(
        title: item == null ? 'Tambah item' : 'Edit item',
        labels: const ['Nama item', 'Harga total (Rp)'],
        values: [item?.name ?? '', item?.price.toString() ?? ''],
        numeric: const {1},
        validate: (v) => v[0].isEmpty || (int.tryParse(v[1]) ?? 0) <= 0
            ? 'Isi nama dan harga lebih dari nol.'
            : null,
      ),
    );
    if (!mounted || values == null) return;
    _change(() {
      if (item == null) {
        bill.items.add(
          BillItem(id: _id(), name: values[0], price: int.parse(values[1])),
        );
      } else {
        item.name = values[0];
        item.price = int.parse(values[1]);
      }
    });
  }

  Future<void> _editCharges() async {
    final values = await showDialog<List<String>>(
      context: context,
      builder: (_) => InputDialog(
        title: 'Pajak dan biaya',
        labels: const ['Pajak (Rp)', 'Layanan (Rp)', 'Diskon (Rp)'],
        values: [
          bill.tax.toString(),
          bill.service.toString(),
          bill.discount.toString(),
        ],
        numeric: const {0, 1, 2},
        validate: (v) {
          final n = v.map((s) => int.tryParse(s) ?? 0).toList();
          return n[2] > bill.subtotal + n[0] + n[1]
              ? 'Diskon melebihi total tagihan.'
              : null;
        },
      ),
    );
    if (!mounted || values == null) return;
    _change(() {
      bill.tax = int.tryParse(values[0]) ?? 0;
      bill.service = int.tryParse(values[1]) ?? 0;
      bill.discount = int.tryParse(values[2]) ?? 0;
    });
  }

  Future<void> _addPerson() async {
    final values = await showDialog<List<String>>(
      context: context,
      builder: (_) => InputDialog(
        title: 'Tambah orang',
        labels: const ['Nama panggilan'],
        values: const [''],
        validate: (v) {
          if (v[0].isEmpty) return 'Isi nama terlebih dahulu.';
          return bill.people.any(
                (p) => p.name.toLowerCase() == v[0].toLowerCase(),
              )
              ? 'Nama sudah ada.'
              : null;
        },
      ),
    );
    if (!mounted || values == null) return;
    _change(() => bill.people.add(Person(id: _id(), name: values[0])));
  }

  Future<void> _pickQris() async {
    try {
      final image = await _selectImage(ImageSource.gallery);
      if (image == null) return;
      final bytes = await image.readAsBytes();
      if (Backend.userId != null) {
        final path = '${Backend.userId}/qris';
        final mime = bytes.length > 3 && bytes[0] == 0x89
            ? 'image/png'
            : bytes.length > 3 && bytes[0] == 0xff
            ? 'image/jpeg'
            : 'image/webp';
        await Backend.client.storage
            .from('qris')
            .uploadBinary(
              path,
              bytes,
              fileOptions: FileOptions(
                upsert: true,
                contentType: mime,
                cacheControl: '0',
              ),
            );
        await Backend.client
            .from('profiles')
            .update({'qris_path': path})
            .eq('id', Backend.userId!);
      }
      if (kIsWeb) {
        if (mounted) setState(() => qrisBytes = bytes);
        return;
      }
      final dir = await getApplicationDocumentsDirectory();
      final target = File('${dir.path}/qris$storageSuffix.png');
      await File(image.path).copy(target.path);
      if (mounted) {
        setState(() {
          qrisPath = target.path;
          qrisBytes = bytes;
        });
      }
    } catch (_) {
      if (mounted) _notice('Gambar QRIS gagal disimpan.');
    }
  }

  Future<void> _chooseFriend() async {
    try {
      final friends = (await Backend.connections())
          .where((f) => f['status'] == 'accepted')
          .toList();
      if (!mounted) return;
      if (friends.isEmpty) {
        _notice('Tambahkan teman dan tunggu persetujuannya terlebih dahulu.');
        return;
      }
      final selected = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final friend in friends)
                ListTile(
                  title: Text(friend['display_name'] as String),
                  onTap: () => Navigator.pop(ctx, friend),
                ),
            ],
          ),
        ),
      );
      if (!mounted || selected == null) return;
      if (bill.people.any((p) => p.accountId == selected['user_id'])) {
        _notice('Teman ini sudah ada dalam tagihan.');
        return;
      }
      _change(
        () => bill.people.add(
          Person(
            id: _id(),
            name: selected['display_name'] as String,
            accountId: selected['user_id'] as String,
          ),
        ),
      );
    } catch (e) {
      if (mounted) _notice(Backend.message(e));
    }
  }

  Future<void> _sendRequest(PersonTotal entry) async {
    if (sending || entry.person.accountId == null) return;
    setState(() => sending = true);
    try {
      await history.save(bill);
      await Backend.client.rpc(
        'request_payment',
        params: {
          'friend_id': entry.person.accountId,
          'amount_rupiah': entry.total,
          'description': bill.title,
          'reference': bill.id,
        },
      );
      if (mounted) _notice('Tagihan terkirim ke akun ${entry.person.name}.');
    } catch (e) {
      if (mounted) _notice(Backend.message(e));
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> _newBill() async {
    if (savingHistory || loading || sending) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mulai tagihan baru?'),
        content: const Text(
          'Pembagian saat ini akan disimpan ke riwayat sebelum memulai tagihan baru.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Mulai baru'),
          ),
        ],
      ),
    );
    if (ok == true) {
      if (!await _archiveBill() || !mounted) return;
      _change(() {
        bill = Bill(
          items: [],
          people: [Person(id: 'host', name: 'Saya')],
        );
        step = 0;
        receiptBytes = null;
      });
    }
  }

  Future<bool> _archiveBill({bool notify = false}) async {
    if (savingHistory) return false;
    setState(() => savingHistory = true);
    try {
      await history.save(bill);
      if (mounted && notify) _notice('Pembagian disimpan ke riwayat.');
      return true;
    } catch (_) {
      if (mounted) {
        _notice(
          'Riwayat gagal disimpan. Tagihan saat ini tetap tersedia; coba lagi.',
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => savingHistory = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Image.asset(
        'assets/billswipe-logo.png',
        height: 42,
        fit: BoxFit.contain,
      ),
      actions: [
        if (Backend.userId != null) const NotificationBell(),
        IconButton(
          tooltip: 'Riwayat',
          icon: const Icon(Icons.history),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => HistoryPage(store: history),
            ),
          ),
        ),
        IconButton(
          onPressed: _showQrisSettings,
          tooltip: 'QRIS saya',
          icon: const Icon(Icons.qr_code_2_rounded),
        ),
        IconButton(
          onPressed: _newBill,
          tooltip: 'Tagihan baru',
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: Row(
                    children: [
                      for (var i = 0; i < 4; i++)
                        Expanded(
                          child: Container(
                            height: 5,
                            margin: const EdgeInsets.only(right: 5),
                            decoration: BoxDecoration(
                              color: i <= step ? teal : const Color(0xFFD9E5E0),
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: IndexedStack(
                    index: step,
                    children: [
                      _scanView(),
                      _reviewView(),
                      _assignView(),
                      _resultView(),
                    ],
                  ),
                ),
              ],
            ),
          ),
  );

  Widget _heading(String title, String subtitle) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(
          fontSize: 27,
          fontWeight: FontWeight.w800,
          color: ink,
        ),
      ),
      const SizedBox(height: 5),
      Text(
        subtitle,
        style: const TextStyle(fontSize: 15, color: Color(0xFF657C78)),
      ),
    ],
  );

  Widget _scanView() => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      const SizedBox(height: 18),
      _heading(
        'Struknya siap?',
        'Foto struk, cek hasilnya, lalu bagi setiap item.',
      ),
      const SizedBox(height: 26),
      Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: ink,
          borderRadius: BorderRadius.circular(26),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.document_scanner_rounded,
              color: Color(0xFFA2E7D5),
              size: 44,
            ),
            const SizedBox(height: 22),
            const Text(
              'Pindai struk',
              style: TextStyle(
                color: Colors.white,
                fontSize: 23,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 7),
            const Text(
              kIsWeb
                  ? 'Mode uji Chrome: unggah foto sebagai acuan, lalu isi item manual. OCR otomatis tersedia di Android/iOS. Data sesi hilang saat halaman dimuat ulang.'
                  : 'Teks dikenali di ponsel. Anda dapat mengoreksi hasilnya.',
              style: TextStyle(color: Color(0xFFBCD0CD), fontSize: 15),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: scanning
                  ? null
                  : () => _scan(
                      kIsWeb ? ImageSource.gallery : ImageSource.camera,
                    ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFA2E7D5),
                foregroundColor: ink,
                minimumSize: const Size.fromHeight(52),
              ),
              icon: const Icon(Icons.camera_alt_rounded),
              label: Text(
                scanning
                    ? 'Membaca struk...'
                    : kIsWeb
                    ? 'Pilih foto struk'
                    : 'Buka kamera',
              ),
            ),
            TextButton.icon(
              onPressed: scanning ? null : () => _scan(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Pilih dari galeri'),
              style: TextButton.styleFrom(foregroundColor: Colors.white),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      OutlinedButton.icon(
        onPressed: () => setState(() => step = 1),
        icon: const Icon(Icons.edit_note_rounded),
        label: Text(
          bill.items.isEmpty
              ? 'Isi item manual'
              : 'Lanjutkan tagihan tersimpan',
        ),
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
      ),
      const SizedBox(height: 18),
      const Text(
        'Tip: foto di tempat terang dan potong hanya area struk.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Color(0xFF6A7D7A)),
      ),
    ],
  );

  Widget _reviewView() => Column(
    children: [
      Expanded(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _heading('Periksa item', 'Koreksi nama dan harga sebelum membagi.'),
            const SizedBox(height: 18),
            if (receiptBytes != null) ...[
              Image.memory(
                receiptBytes!,
                height: 280,
                fit: BoxFit.contain,
                errorBuilder: (_, error, stack) => const Text(
                  'Format gambar tidak didukung. Pilih JPG atau PNG.',
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Gunakan foto di atas sebagai acuan. OCR otomatis belum tersedia di Chrome.',
              ),
              const SizedBox(height: 12),
            ],
            if (bill.items.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Belum ada item. Tambahkan manual atau pindai struk.',
                  ),
                ),
              ),
            for (final item in bill.items)
              Card(
                elevation: 0,
                color: Colors.white,
                child: ListTile(
                  title: Text(item.name),
                  subtitle: Text(rupiah(item.price)),
                  trailing: PopupMenuButton<String>(
                    onSelected: (choice) {
                      if (choice == 'edit') _editItem(item);
                      if (choice == 'delete') {
                        _change(() => bill.items.remove(item));
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(value: 'delete', child: Text('Hapus')),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _editItem(),
              icon: const Icon(Icons.add),
              label: const Text('Tambah item'),
            ),
            const SizedBox(height: 16),
            _summary(),
            TextButton(
              onPressed: _editCharges,
              child: const Text('Edit pajak, layanan & diskon'),
            ),
          ],
        ),
      ),
      _footer(
        () => setState(() => step = 0),
        bill.items.isEmpty ? null : () => setState(() => step = 2),
        'Bagikan item',
      ),
    ],
  );

  Widget _assignView() => Column(
    children: [
      Expanded(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _heading('Siapa pesan apa?', 'Pilih pemilik untuk setiap item.'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: pale,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                '${bill.items.length - bill.unclaimed} dari ${bill.items.length} item dibagikan',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 14),
            for (final item in bill.items)
              Card(
                elevation: 0,
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 7,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(rupiah(item.price)),
                          ],
                        ),
                      ),
                      DropdownButton<String?>(
                        value: item.ownerId,
                        hint: const Text('Pilih'),
                        underline: const SizedBox(),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('Belum'),
                          ),
                          for (final person in bill.people)
                            DropdownMenuItem<String?>(
                              value: person.id,
                              child: Text(person.name),
                            ),
                        ],
                        onChanged: (id) => _change(() => item.ownerId = id),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 9),
            OutlinedButton.icon(
              onPressed: _addPerson,
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Tambah orang'),
            ),
            if (Backend.userId != null)
              FilledButton.icon(
                onPressed: _chooseFriend,
                icon: const Icon(Icons.people_alt_outlined),
                label: const Text('Pilih dari teman'),
              ),
            Wrap(
              spacing: 7,
              children: [
                for (final person in bill.people)
                  InputChip(
                    label: Text(person.name),
                    onDeleted: person.id == 'host'
                        ? null
                        : () => _change(() {
                            for (final item in bill.items) {
                              if (item.ownerId == person.id) {
                                item.ownerId = null;
                              }
                            }
                            bill.people.remove(person);
                          }),
                  ),
              ],
            ),
          ],
        ),
      ),
      _footer(
        () => setState(() => step = 1),
        bill.unclaimed > 0 ? null : () => setState(() => step = 3),
        'Lihat hasil',
      ),
    ],
  );

  Widget _resultView() {
    final totals = calculateTotals(bill);
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _heading(
                'Tagihan selesai',
                'Setiap orang membayar sesuai itemnya.',
              ),
              const SizedBox(height: 16),
              _summary(),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: savingHistory || bill.items.isEmpty
                    ? null
                    : () => _archiveBill(notify: true),
                icon: const Icon(Icons.history),
                label: Text(
                  savingHistory ? 'Menyimpan...' : 'Simpan ke riwayat',
                ),
              ),
              const SizedBox(height: 14),
              for (final entry in totals)
                Card(
                  elevation: 0,
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(17),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: pale,
                              child: Text(
                                entry.person.name.substring(0, 1).toUpperCase(),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                entry.person.name,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Text(
                              rupiah(entry.total),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: teal,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _line('Item', entry.subtotal),
                        if (bill.tax > 0) _line('Pajak', entry.tax),
                        if (bill.service > 0) _line('Layanan', entry.service),
                        if (bill.discount > 0) _line('Diskon', -entry.discount),
                        if (entry.person.id != 'host')
                          TextButton.icon(
                            onPressed: () => _showPayment(entry),
                            icon: const Icon(Icons.qr_code_2_rounded),
                            label: const Text('Instruksi bayar'),
                          ),
                        if (Backend.userId != null &&
                            entry.person.accountId != null)
                          FilledButton.icon(
                            onPressed: sending || entry.total <= 0
                                ? null
                                : () => _sendRequest(entry),
                            icon: const Icon(Icons.send_outlined),
                            label: Text(
                              sending
                                  ? 'Mengirim...'
                                  : 'Kirim tagihan ke teman',
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                'Total bagian: ${rupiah(totals.fold(0, (int sum, e) => sum + e.total))}',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        _footer(() => setState(() => step = 2), _newBill, 'Tagihan baru'),
      ],
    );
  }

  Widget _line(String label, int value) => Padding(
    padding: const EdgeInsets.only(top: 5),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(color: Color(0xFF657C78))),
        ),
        Text(rupiah(value)),
      ],
    ),
  );

  Widget _summary() => Container(
    padding: const EdgeInsets.all(17),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      children: [
        _line('Subtotal', bill.subtotal),
        _line('Pajak', bill.tax),
        _line('Layanan', bill.service),
        _line('Diskon', -bill.discount),
        const Divider(height: 23),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Total tagihan',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
              ),
            ),
            Text(
              rupiah(bill.total),
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 20,
                color: teal,
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _footer(VoidCallback back, VoidCallback? next, String label) =>
      Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE2EAE7))),
        ),
        child: Row(
          children: [
            OutlinedButton(onPressed: back, child: const Text('Kembali')),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: next,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
                child: Text(label),
              ),
            ),
          ],
        ),
      );

  Widget _qrisImage(double height) {
    if (qrisBytes != null) {
      return Image.memory(
        qrisBytes!,
        height: height,
        errorBuilder: (_, error, stack) => const Text('Gambar tidak tersedia'),
      );
    }
    return Image.file(
      File(qrisPath!),
      height: height,
      errorBuilder: (_, error, stack) => const Text('Gambar tidak tersedia'),
    );
  }

  void _showQrisSettings() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'QRIS saya',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              'Simpan gambar QRIS statis milik Anda untuk layar pembayaran.',
            ),
            const SizedBox(height: 16),
            if (qrisBytes != null || qrisPath != null) _qrisImage(220),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () async {
                Navigator.pop(sheet);
                await _pickQris();
              },
              icon: const Icon(Icons.upload_rounded),
              label: Text(
                qrisBytes == null && qrisPath == null
                    ? 'Pilih gambar QRIS'
                    : 'Ganti QRIS',
              ),
            ),
          ],
        ),
      ),
    ),
  );

  void _showPayment(PersonTotal entry) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Tagihan ${entry.person.name}',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              rupiah(entry.total),
              style: const TextStyle(
                fontSize: 31,
                fontWeight: FontWeight.w800,
                color: teal,
              ),
            ),
            const SizedBox(height: 16),
            if (qrisBytes != null || qrisPath != null)
              _qrisImage(240)
            else
              const Text('Tambahkan QRIS melalui ikon di kanan atas.'),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(text: entry.total.toString()),
                );
                if (sheet.mounted) Navigator.pop(sheet);
                if (mounted) _notice('Nominal disalin.');
              },
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Salin nominal'),
            ),
          ],
        ),
      ),
    ),
  );
}
