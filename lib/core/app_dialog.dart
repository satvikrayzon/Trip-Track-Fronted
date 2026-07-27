import 'package:flutter/material.dart';

import '../app/router/app_router.dart';

/// Confirmation dialog via GoRouter root navigator.
Future<bool> showAppConfirmDialog({
  required String title,
  required String message,
  String confirmLabel = 'OK',
  String cancelLabel = 'Cancel',
  bool destructive = false,
}) async {
  final ctx = rootNavigatorKey.currentContext;
  if (ctx == null) return false;

  final result = await showDialog<bool>(
    context: ctx,
    barrierDismissible: true,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(cancelLabel),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(
            confirmLabel,
            style: destructive
                ? const TextStyle(color: Colors.red)
                : null,
          ),
        ),
      ],
    ),
  );
  return result ?? false;
}
