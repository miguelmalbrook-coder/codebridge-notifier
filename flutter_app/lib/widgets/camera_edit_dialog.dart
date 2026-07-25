import 'package:flutter/material.dart';
import '../models/camera.dart';

/// Dialog for adding or editing a camera's alias + RTSP URL.
class CameraEditDialog extends StatefulWidget {
  final Camera? camera; // null = adding, non-null = editing

  const CameraEditDialog({super.key, this.camera});

  @override
  State<CameraEditDialog> createState() => _CameraEditDialogState();
}

class _CameraEditDialogState extends State<CameraEditDialog> {
  late final TextEditingController _aliasCtrl;
  late final TextEditingController _urlCtrl;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _aliasCtrl = TextEditingController(text: widget.camera?.alias ?? '');
    _urlCtrl = TextEditingController(text: widget.camera?.rtspUrl ?? '');
  }

  @override
  void dispose() {
    _aliasCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.camera != null;
    return AlertDialog(
      title: Text(isEditing ? 'Edit Camera' : 'Add Camera'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _aliasCtrl,
              decoration: const InputDecoration(
                labelText: 'Camera Alias',
                hintText: 'e.g. Front Door',
                prefixIcon: Icon(Icons.label_outline),
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Alias is required' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _urlCtrl,
              decoration: const InputDecoration(
                labelText: 'RTSP URL',
                hintText: 'rtsp://user:pass@host:554/stream',
                prefixIcon: Icon(Icons.link),
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'URL is required';
                if (!v.trim().startsWith('rtsp://') &&
                    !v.trim().startsWith('rtsps://')) {
                  return 'Must start with rtsp:// or rtsps://';
                }
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(isEditing ? 'Save' : 'Add'),
        ),
      ],
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(context, {
      'alias': _aliasCtrl.text.trim(),
      'url': _urlCtrl.text.trim(),
    });
  }
}
