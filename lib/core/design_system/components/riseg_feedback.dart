import 'package:flutter/material.dart';

import '../theme_context.dart';
import '../tokens/app_radius.dart';
import '../tokens/app_sizes.dart';
import '../tokens/app_spacing.dart';
import '../tokens/app_typography.dart';

/// Mensajes transitorios de éxito/error para operaciones rutinarias
/// (ej. guardar un formulario) — un `SnackBar` tematizado, no un
/// `RisegDialog` modal, porque interrumpir con un modal una confirmación
/// de guardado de todos los días sería más intrusivo de lo que amerita.
///
/// Deliberadamente no es todavía un componente del catálogo
/// `/dev/design-system` — vive aquí porque es infraestructura compartida
/// del Design System, pero se agrega una sección de catálogo solo si un
/// segundo módulo lo reutiliza (evita documentar algo con un único
/// consumidor real).
abstract final class RisegFeedback {
  static void showSuccess(BuildContext context, String message) {
    _show(
      context,
      message: message,
      background: context.colors.successBg,
      foreground: context.colors.success,
      icon: Icons.check_circle_outline,
    );
  }

  static void showError(BuildContext context, String message) {
    _show(
      context,
      message: message,
      background: context.colors.errorBg,
      foreground: context.colors.error,
      icon: Icons.error_outline,
    );
  }

  static void _show(
    BuildContext context, {
    required String message,
    required Color background,
    required Color foreground,
    required IconData icon,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: background,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdRadius),
        content: Semantics(
          liveRegion: true,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: foreground, size: AppSizes.iconMd),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(message, style: AppTypography.body.copyWith(color: foreground)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
