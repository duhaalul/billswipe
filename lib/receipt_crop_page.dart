import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class ReceiptCropPage extends StatefulWidget {
  const ReceiptCropPage({super.key, required this.bytes});
  final Uint8List bytes;
  @override
  State<ReceiptCropPage> createState() => _ReceiptCropPageState();
}

class _ReceiptCropPageState extends State<ReceiptCropPage> {
  final controller = CropController();
  bool busy = false;
  bool ready = false;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Potong struk'),
      leading: IconButton(
        tooltip: 'Batal',
        icon: const Icon(Icons.close),
        onPressed: () => Navigator.pop(context),
      ),
    ),
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: Crop(
              image: widget.bytes,
              controller: controller,
              progressIndicator: const Center(
                child: CircularProgressIndicator(),
              ),
              onStatusChanged: (status) {
                if (mounted) setState(() => ready = status == CropStatus.ready);
              },
              onCropped: (result) {
                if (!mounted) return;
                switch (result) {
                  case CropSuccess(:final croppedImage):
                    Navigator.pop(context, croppedImage);
                  case CropFailure():
                    setState(() => busy = false);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Gambar tidak dapat dipotong. Gunakan foto utuh atau pilih JPG/PNG.',
                        ),
                      ),
                    );
                }
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.pop(context, widget.bytes),
                  child: const Text('Gunakan foto utuh'),
                ),
                FilledButton.icon(
                  onPressed: !ready || busy
                      ? null
                      : () {
                          setState(() => busy = true);
                          controller.crop();
                        },
                  icon: const Icon(Icons.check),
                  label: Text(busy ? 'Memotong...' : 'Selesai'),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
