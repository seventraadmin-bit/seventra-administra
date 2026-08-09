import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/personal/domain/usecases/adjuntar_documento_empleado_usecase.dart';

import '../../../personal_providers.dart';

String categoriaDocumentoEmpleadoLabel(AppLocalizations l10n, String valor) {
  return switch (CategoriaDocumentoEmpleado.values.byName(valor)) {
    CategoriaDocumentoEmpleado.ine => l10n.categoriaDocumentoEmpleadoIne,
    CategoriaDocumentoEmpleado.curp => l10n.categoriaDocumentoEmpleadoCurp,
    CategoriaDocumentoEmpleado.rfc => l10n.categoriaDocumentoEmpleadoRfc,
    CategoriaDocumentoEmpleado.actaNacimiento => l10n.categoriaDocumentoEmpleadoActaNacimiento,
    CategoriaDocumentoEmpleado.comprobanteDomicilio => l10n.categoriaDocumentoEmpleadoComprobanteDomicilio,
    CategoriaDocumentoEmpleado.nss => l10n.categoriaDocumentoEmpleadoNss,
    CategoriaDocumentoEmpleado.cartilla => l10n.categoriaDocumentoEmpleadoCartilla,
    CategoriaDocumentoEmpleado.licencia => l10n.categoriaDocumentoEmpleadoLicencia,
    CategoriaDocumentoEmpleado.certificado => l10n.categoriaDocumentoEmpleadoCertificado,
    CategoriaDocumentoEmpleado.constancia => l10n.categoriaDocumentoEmpleadoConstancia,
    CategoriaDocumentoEmpleado.contrato => l10n.categoriaDocumentoEmpleadoContrato,
    CategoriaDocumentoEmpleado.perfilPsicologico => l10n.categoriaDocumentoEmpleadoPerfilPsicologico,
    CategoriaDocumentoEmpleado.estudioSocioeconomico => l10n.categoriaDocumentoEmpleadoEstudioSocioeconomico,
    CategoriaDocumentoEmpleado.antidoping => l10n.categoriaDocumentoEmpleadoAntidoping,
    CategoriaDocumentoEmpleado.otro => l10n.categoriaDocumentoEmpleadoOtro,
  };
}

/// Diálogo "Adjuntar documento" del expediente del Empleado (Etapa 5A)
/// — primero pide la categoría, luego abre el selector de archivo del
/// sistema operativo.
///
/// Devuelve `true` si el documento se adjuntó correctamente.
Future<bool> mostrarDialogoAdjuntarDocumentoEmpleado(BuildContext context, WidgetRef ref, String empleadoId) async {
  final l10n = AppLocalizations.of(context)!;
  CategoriaDocumentoEmpleado categoria = CategoriaDocumentoEmpleado.otro;

  final confirmado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.adjuntarDocumentoEmpleadoDialogoTitulo,
    confirmLabel: l10n.adjuntarDocumentoEmpleadoBotonContinuar,
    cancelLabel: l10n.adjuntarDocumentoEmpleadoBotonCancelar,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        return RisegSelect<CategoriaDocumentoEmpleado>(
          label: l10n.adjuntarDocumentoEmpleadoCampoCategoria,
          value: categoria,
          items: [
            for (final c in CategoriaDocumentoEmpleado.values)
              RisegSelectItem(value: c, label: categoriaDocumentoEmpleadoLabel(l10n, c.name)),
          ],
          onChanged: (valor) => setState(() => categoria = valor ?? categoria),
        );
      },
    ),
    onConfirm: () async => true,
  );
  if (confirmado != true) return false;
  if (!context.mounted) return false;

  final seleccion = await FilePicker.platform.pickFiles();
  final archivo = seleccion?.files.singleOrNull;
  if (archivo?.path == null) return false;
  if (!context.mounted) return false;

  final resultado = await ref.read(adjuntarDocumentoEmpleadoUseCaseProvider).ejecutar(
        empleadoId: empleadoId,
        categoria: categoria,
        sourceFilePath: archivo!.path!,
        originalFileName: archivo.name,
        mimeType: 'application/octet-stream',
      );

  if (!context.mounted) return false;

  switch (resultado) {
    case AdjuntarDocumentoEmpleadoExitoso():
      RisegFeedback.showSuccess(context, l10n.adjuntarDocumentoEmpleadoExito);
      return true;
    case AdjuntarDocumentoEmpleadoNoExiste():
    case AdjuntarDocumentoEmpleadoErrorInesperado():
      RisegFeedback.showError(context, l10n.adjuntarDocumentoEmpleadoErrorInesperado);
      return false;
  }
}
