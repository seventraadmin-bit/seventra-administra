import 'package:flutter/material.dart';

import '../theme_context.dart';
import '../tokens/app_radius.dart';
import '../tokens/app_shadows.dart';
import '../tokens/app_spacing.dart';
import '../tokens/app_typography.dart';
import 'riseg_button.dart';

/// Diálogos de RISEG ONE.
///
/// Se usan como métodos estáticos (`RisegDialog.showConfirmation(...)`),
/// no como un widget que se instancie directo — cada variante arma su
/// propio contenido y lo entrega a `showDialog`, que ya resuelve la
/// barrera, el foco atrapado dentro del diálogo y Escape-para-cerrar a
/// nivel de ruta (independiente de qué widget se renderice adentro).
/// Deliberadamente sin API de "constructor de formularios": `showForm`
/// solo aloja el widget que el llamador construya.
abstract final class RisegDialog {
  /// Confirmación simple de dos acciones. Si [onConfirm] no se da, la
  /// acción primaria cierra el diálogo de inmediato con `true`. Si se da
  /// (ej. una llamada a un repositorio), el diálogo se queda abierto,
  /// muestra el botón primario en estado `loading` y bloquea ambas
  /// acciones hasta que resuelva, y solo entonces cierra con `true`.
  static Future<bool?> showConfirmation({
    required BuildContext context,
    required String title,
    required String message,
    required String confirmLabel,
    required String cancelLabel,
    bool destructive = false,
    Future<void> Function()? onConfirm,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => _RisegConfirmationDialog(
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        destructive: destructive,
        onConfirm: onConfirm,
      ),
    );
  }

  /// Informativo de una sola acción (solo "entendido"/"cerrar").
  static Future<void> showInformational({
    required BuildContext context,
    required String title,
    required String message,
    required String dismissLabel,
  }) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => _RisegInfoDialog(title: title, message: message, dismissLabel: dismissLabel),
    );
  }

  /// Aloja un formulario arbitrario ([contentBuilder]) dentro del mismo
  /// marco visual. [onConfirm] es responsable de validar/guardar; mientras
  /// esté pendiente, ambas acciones quedan bloqueadas y la primaria pasa a
  /// `loading`. El foco inicial del contenido del formulario queda a
  /// cargo de lo que `contentBuilder` entregue (ej. un campo con
  /// `autofocus: true`) — el diálogo no puede saber cuál es "el primer
  /// campo" de un formulario que no construye él mismo.
  static Future<T?> showForm<T>({
    required BuildContext context,
    required String title,
    required WidgetBuilder contentBuilder,
    required String confirmLabel,
    required String cancelLabel,
    Future<T?> Function()? onConfirm,
  }) {
    return showDialog<T>(
      context: context,
      builder: (dialogContext) => _RisegFormDialog<T>(
        title: title,
        contentBuilder: contentBuilder,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        onConfirm: onConfirm,
      ),
    );
  }
}

/// Marco visual compartido por las tres variantes — título, contenido y
/// acciones sobre los tokens de RISEG ONE. Sin elevación de Material (la
/// app ya no usa `elevation`, ver `AppTheme`): la sombra es la de
/// `AppShadows.dialog`, igual que cualquier otra capa flotante.
class _RisegDialogShell extends StatelessWidget {
  const _RisegDialogShell({required this.title, required this.content, required this.actions});

  final String title;
  final Widget content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final brightness = Theme.of(context).brightness;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.xl),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: AppRadius.lgRadius,
            boxShadow: AppShadows.dialog(brightness),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTypography.heading2.copyWith(color: colors.textPrimary)),
              const SizedBox(height: AppSpacing.sm),
              // `Flexible` + scroll: la mayoría de los formularios caben
              // sin desbordar, pero uno con muchos campos (ej.
              // Configuración de cobro, Etapa 4H.1) no debe romper el
              // layout — se vuelve desplazable en vez de desbordar.
              Flexible(child: SingleChildScrollView(child: content)),
              const SizedBox(height: AppSpacing.lg),
              // `Wrap` (no `Row`) — con textos de botón largos (algo común
              // en español) dos acciones pueden no caber en el ancho fijo
              // del diálogo; en vez de desbordar, la segunda pasa a una
              // nueva línea.
              Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: actions,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RisegConfirmationDialog extends StatefulWidget {
  const _RisegConfirmationDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.destructive,
    required this.onConfirm,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final bool destructive;
  final Future<void> Function()? onConfirm;

  @override
  State<_RisegConfirmationDialog> createState() => _RisegConfirmationDialogState();
}

class _RisegConfirmationDialogState extends State<_RisegConfirmationDialog> {
  bool _loading = false;

  Future<void> _handleConfirm() async {
    if (widget.onConfirm == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() => _loading = true);
    await widget.onConfirm!();
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Foco inicial en "cancelar" cuando la acción es destructiva — Enter
    // por reflejo no debe disparar un borrado. En el resto de los casos,
    // el foco inicial va en la acción primaria.
    return _RisegDialogShell(
      title: widget.title,
      content: Text(widget.message, style: AppTypography.body.copyWith(color: colors.textMuted)),
      actions: [
        RisegButton(
          label: widget.cancelLabel,
          variant: RisegButtonVariant.ghost,
          onPressed: _loading ? null : () => Navigator.of(context).pop(false),
        ),
        RisegButton(
          label: widget.confirmLabel,
          variant: widget.destructive ? RisegButtonVariant.danger : RisegButtonVariant.primary,
          loading: _loading,
          onPressed: _handleConfirm,
        ),
      ],
    );
  }
}

class _RisegInfoDialog extends StatelessWidget {
  const _RisegInfoDialog({required this.title, required this.message, required this.dismissLabel});

  final String title;
  final String message;
  final String dismissLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return _RisegDialogShell(
      title: title,
      content: Text(message, style: AppTypography.body.copyWith(color: colors.textMuted)),
      actions: [
        RisegButton(
          label: dismissLabel,
          variant: RisegButtonVariant.primary,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

class _RisegFormDialog<T> extends StatefulWidget {
  const _RisegFormDialog({
    required this.title,
    required this.contentBuilder,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.onConfirm,
  });

  final String title;
  final WidgetBuilder contentBuilder;
  final String confirmLabel;
  final String cancelLabel;
  final Future<T?> Function()? onConfirm;

  @override
  State<_RisegFormDialog<T>> createState() => _RisegFormDialogState<T>();
}

class _RisegFormDialogState<T> extends State<_RisegFormDialog<T>> {
  bool _loading = false;

  Future<void> _handleConfirm() async {
    if (widget.onConfirm == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _loading = true);
    final result = await widget.onConfirm!();
    if (mounted) Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return _RisegDialogShell(
      title: widget.title,
      content: IgnorePointer(ignoring: _loading, child: widget.contentBuilder(context)),
      actions: [
        RisegButton(
          label: widget.cancelLabel,
          variant: RisegButtonVariant.ghost,
          onPressed: _loading ? null : () => Navigator.of(context).pop(),
        ),
        RisegButton(
          label: widget.confirmLabel,
          variant: RisegButtonVariant.primary,
          loading: _loading,
          onPressed: _handleConfirm,
        ),
      ],
    );
  }
}
