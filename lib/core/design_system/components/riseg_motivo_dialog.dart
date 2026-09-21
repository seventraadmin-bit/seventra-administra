import 'package:flutter/material.dart';

import '../theme_context.dart';
import '../tokens/app_spacing.dart';
import '../tokens/app_typography.dart';
import 'riseg_dialog.dart';
import 'riseg_text_field.dart';

/// Pide el MOTIVO de una operación sensible y lo devuelve, o `null` si
/// se canceló.
///
/// Existe para que cada corrección, suspensión, terminación o archivo no
/// escriba su propio diálogo casi idéntico: el estándar de auditoría del
/// proyecto exige motivo en todas ellas, así que el diálogo es uno solo.
///
/// El campo es de una línea, como el resto de los campos del sistema
/// de diseño: un textarea alto es justo lo que desborda a 500px.
///
/// El campo vive en un `StatefulWidget` propio que posee y destruye su
/// `TextEditingController`. **No** se crea el controlador en la función
/// que llama para destruirlo tras el `await`: eso es un bug real y
/// reproducible de este proyecto — la transición de salida del diálogo
/// mantiene el campo montado un frame más y estalla con "A
/// TextEditingController was used after being disposed".
Future<String?> mostrarDialogoMotivo(
  BuildContext context, {
  required String titulo,
  required String etiquetaMotivo,
  required String confirmarLabel,
  required String cancelarLabel,
  required String errorMotivoRequerido,
  String? advertencia,
}) {
  // Lo captura el `onConfirm`; nunca se lee `.text` desde fuera.
  var motivo = '';
  var mostrarError = false;

  return RisegDialog.showForm<String>(
    context: context,
    title: titulo,
    confirmLabel: confirmarLabel,
    cancelLabel: cancelarLabel,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) => _FormularioMotivo(
        etiquetaMotivo: etiquetaMotivo,
        advertencia: advertencia,
        error: mostrarError ? errorMotivoRequerido : null,
        onMotivoChanged: (valor) {
          motivo = valor;
          if (mostrarError && valor.trim().isNotEmpty) setState(() => mostrarError = false);
        },
        onErrorPendiente: () => setState(() {}),
      ),
    ),
    onConfirm: () async {
      if (motivo.trim().isEmpty) {
        mostrarError = true;
        return null;
      }
      return motivo.trim();
    },
  );
}

class _FormularioMotivo extends StatefulWidget {
  const _FormularioMotivo({
    required this.etiquetaMotivo,
    required this.advertencia,
    required this.error,
    required this.onMotivoChanged,
    required this.onErrorPendiente,
  });

  final String etiquetaMotivo;
  final String? advertencia;
  final String? error;
  final ValueChanged<String> onMotivoChanged;
  final VoidCallback onErrorPendiente;

  @override
  State<_FormularioMotivo> createState() => _FormularioMotivoState();
}

class _FormularioMotivoState extends State<_FormularioMotivo> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    // Ancho acotado, no fijo: a 500px el diálogo tiene que caber sin
    // desbordar, y el campo de motivo es de 3 renglones como máximo.
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.advertencia != null) ...[
            Text(widget.advertencia!, style: AppTypography.body.copyWith(color: colors.textMuted)),
            const SizedBox(height: AppSpacing.md),
          ],
          RisegTextField(
            key: const Key('dialogo_motivo_campo'),
            label: widget.etiquetaMotivo,
            controller: _controller,
            autofocus: true,
            errorText: widget.error,
            onChanged: widget.onMotivoChanged,
          ),
        ],
      ),
    );
  }
}
