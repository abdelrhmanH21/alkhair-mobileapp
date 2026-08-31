import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/theme/app_theme.dart';

/// Shared camera/gallery photo-attachment control — used by both the
/// mandatory proof-of-expense photo (تسجيل مصروف) and the optional
/// تسجيل ملاحظة attachment, so the pick-and-preview UX stays identical
/// between the two. [required] only controls the label/error copy shown
/// here; the actual submit-blocking enforcement stays in each form's own
/// _submit(), since this widget has no concept of "form submitted yet".
class PhotoAttachmentField extends StatelessWidget {
  final File? photo;
  final ValueChanged<File?> onChanged;
  final bool required;
  final bool showRequiredError;

  const PhotoAttachmentField({
    super.key,
    required this.photo,
    required this.onChanged,
    this.required = false,
    this.showRequiredError = false,
  });

  static Future<File?> _pick(BuildContext context) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('التقاط صورة'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('اختيار من المعرض'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return null;
    try {
      // imageQuality compresses client-side — keeps a phone-camera photo
      // comfortably under the backend's 5MB cap (ComplaintController::
      // store()/DelegateExpenseController::store()'s `max:5120`) without a
      // separate explicit size check, unlike ComplainPage.tsx's web upload
      // (a raw <input type=file> has no built-in compression, hence that
      // page's own client-side MAX_PHOTO_BYTES guard instead).
      final picked = await ImagePicker().pickImage(source: source, imageQuality: 70);
      return picked == null ? null : File(picked.path);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذّر الوصول إلى الكاميرا/المعرض.')),
        );
      }
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = required ? 'إرفاق صورة إثبات المصروف *' : 'إرفاق صورة (اختياري)';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (photo == null)
          OutlinedButton.icon(
            onPressed: () async {
              final picked = await _pick(context);
              if (picked != null) onChanged(picked);
            },
            icon: const Icon(Icons.add_a_photo_outlined, size: 18),
            label: Text(label),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
              foregroundColor: showRequiredError ? AppTheme.danger : null,
              side: showRequiredError ? const BorderSide(color: AppTheme.danger) : null,
            ),
          )
        else
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(photo!, width: 56, height: 56, fit: BoxFit.cover),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextButton.icon(
                  onPressed: () async {
                    final picked = await _pick(context);
                    if (picked != null) onChanged(picked);
                  },
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('تغيير الصورة'),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: AppTheme.danger),
                onPressed: () => onChanged(null),
              ),
            ],
          ),
        if (showRequiredError && photo == null)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'يجب إرفاق صورة إثبات المصروف',
              style: TextStyle(color: AppTheme.danger, fontSize: 12),
            ),
          ),
      ],
    );
  }
}
