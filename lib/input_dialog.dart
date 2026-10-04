import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Controllers live for the entire dialog route, including its exit animation.
class InputDialog extends StatefulWidget {
  const InputDialog({
    super.key,
    required this.title,
    required this.labels,
    required this.values,
    this.numeric = const {},
    this.validate,
  });
  final String title;
  final List<String> labels;
  final List<String> values;
  final Set<int> numeric;
  final String? Function(List<String>)? validate;
  @override
  State<InputDialog> createState() => _InputDialogState();
}

class _InputDialogState extends State<InputDialog> {
  late final controllers = widget.values
      .map((v) => TextEditingController(text: v))
      .toList();
  String? error;
  @override
  void dispose() {
    for (final controller in controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    scrollable: true,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < controllers.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextField(
              controller: controllers[i],
              autofocus: i == 0,
              keyboardType: widget.numeric.contains(i)
                  ? TextInputType.number
                  : TextInputType.text,
              inputFormatters: widget.numeric.contains(i)
                  ? [FilteringTextInputFormatter.digitsOnly]
                  : null,
              decoration: InputDecoration(labelText: widget.labels[i]),
            ),
          ),
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Batal'),
      ),
      FilledButton(
        onPressed: () {
          final values = controllers.map((c) => c.text.trim()).toList();
          final problem = widget.validate?.call(values);
          if (problem != null) {
            setState(() => error = problem);
            return;
          }
          Navigator.pop(context, values);
        },
        child: const Text('Simpan'),
      ),
    ],
  );
}
