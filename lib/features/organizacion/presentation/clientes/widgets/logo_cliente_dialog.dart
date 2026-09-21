import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/eliminar_logo_cliente_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/registrar_logo_cliente_usecase.dart';

import '../../../organizacion_providers.dart';

/// Diálogo "Logotipo del Cliente" (Etapa 16, evolución visual) — con
/// preview, reemplazar y quitar. A diferencia de la fotografía de
/// Empleado (tap-to-replace sin diálogo), el logo de Cliente se captura
/// en un formulario explícito (Resolución de Marlon: "tener preview
/// durante la captura"). Reutiliza `RisegDialog.showForm` (marco
/// compartido) — nunca un modal aislado a mano.
Future<bool> mostrarDialogoLogoCliente(BuildContext context, WidgetRef ref, ClienteData cliente) async {
  final l10n = AppLocalizations.of(context)!;

  AttachmentData? actual;
  if (cliente.logoAttachmentId != null) {
    actual = await ref.read(attachmentRepositoryProvider).obtenerPorId(cliente.logoAttachmentId!);
  }
  if (!context.mounted) return false;

  final rutaSeleccionada = ValueNotifier<String?>(null);
  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.clienteLogoTitulo,
    contentBuilder: (dialogContext) => _LogoClienteForm(
      logoActualPath: actual?.path,
      rutaSeleccionada: rutaSeleccionada,
      ref: ref,
      clienteId: cliente.id,
    ),
    confirmLabel: l10n.clienteLogoBotonGuardar,
    cancelLabel: l10n.clienteLogoBotonCancelar,
    onConfirm: () async {
      final ruta = rutaSeleccionada.value;
      if (ruta == null) return false;

      final archivo = File(ruta);
      final segmentos = archivo.path.split('.');
      final extension = segmentos.length > 1 ? segmentos.last : 'png';
      final res = await ref.read(registrarLogoClienteAutorizadoProvider)(
            clienteId: cliente.id,
            sourceFilePath: ruta,
            originalFileName: archivo.uri.pathSegments.last,
            mimeType: 'image/$extension',
          );

      if (res is RegistrarLogoClienteExitoso) return true;
      if (context.mounted) RisegFeedback.showError(context, l10n.clienteLogoErrorInesperado);
      return null;
    },
  );
  rutaSeleccionada.dispose();
  return resultado ?? false;
}

class _LogoClienteForm extends StatefulWidget {
  const _LogoClienteForm({
    required this.logoActualPath,
    required this.rutaSeleccionada,
    required this.ref,
    required this.clienteId,
  });

  final String? logoActualPath;
  final ValueNotifier<String?> rutaSeleccionada;
  final WidgetRef ref;
  final String clienteId;

  @override
  State<_LogoClienteForm> createState() => _LogoClienteFormState();
}

class _LogoClienteFormState extends State<_LogoClienteForm> {
  bool _quitando = false;

  Future<void> _seleccionar() async {
    final seleccion = await FilePicker.platform.pickFiles(type: FileType.image);
    final archivo = seleccion?.files.singleOrNull;
    if (archivo?.path == null) return;
    widget.rutaSeleccionada.value = archivo!.path;
    if (mounted) setState(() {});
  }

  Future<void> _quitar() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _quitando = true);
    final resultado = await widget.ref.read(eliminarLogoClienteAutorizadoProvider)(widget.clienteId);
    if (!mounted) return;
    if (resultado is EliminarLogoClienteExitoso) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _quitando = false);
      RisegFeedback.showError(context, l10n.clienteLogoErrorInesperado);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final rutaPreview = widget.rutaSeleccionada.value;
    final rutaMostrada = rutaPreview ?? widget.logoActualPath;
    final existeArchivo = rutaMostrada != null && File(rutaMostrada).existsSync();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              color: colors.surfaceSunken,
              borderRadius: AppRadius.mdRadius,
              border: Border.all(color: colors.borderSubtle),
            ),
            padding: const EdgeInsets.all(AppSpacing.sm),
            alignment: Alignment.center,
            child: existeArchivo
                ? Image.file(File(rutaMostrada), fit: BoxFit.contain)
                : Icon(Icons.image_outlined, size: 40, color: colors.textMuted),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Center(
          child: RisegButton(
            label: l10n.clienteLogoBotonSeleccionar,
            variant: RisegButtonVariant.secondary,
            onPressed: _seleccionar,
          ),
        ),
        if (rutaPreview == null && widget.logoActualPath != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Center(
            child: RisegButton(
              label: l10n.clienteLogoBotonQuitar,
              variant: RisegButtonVariant.ghost,
              loading: _quitando,
              onPressed: _quitar,
            ),
          ),
        ],
      ],
    );
  }
}
