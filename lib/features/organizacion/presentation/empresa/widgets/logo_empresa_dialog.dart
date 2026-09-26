import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/design_system/design_system.dart';

import '../../../domain/usecases/eliminar_logo_empresa_usecase.dart';
import '../../../domain/usecases/logo_empresa_validacion.dart';
import '../../../domain/usecases/registrar_logo_empresa_usecase.dart';
import '../empresa_expediente_controller.dart';

/// Diálogo "Logotipo de la empresa" (Etapa 5B.2).
///
/// Mismo marco y mismo recorrido que el logotipo de Cliente —vista previa,
/// reemplazar y quitar— porque es el mismo problema y no merece una pantalla
/// propia: cabe dentro del expediente.
///
/// El título dice **de la empresa** a propósito: aquí no se edita la marca de
/// Seventra Administra, que es del producto y no se configura.
Future<void> mostrarDialogoLogoEmpresa(
  BuildContext context,
  WidgetRef ref, {
  required String nombreComercial,
  required String? logoActualPath,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final seleccionada = ValueNotifier<String?>(null);

  await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.empresaLogoTitulo,
    confirmLabel: l10n.empresaLogoBotonGuardar,
    cancelLabel: l10n.empresaLogoBotonCancelar,
    contentBuilder: (_) => _FormularioLogoEmpresa(
      nombreComercial: nombreComercial,
      logoActualPath: logoActualPath,
      seleccionada: seleccionada,
      ref: ref,
    ),
    onConfirm: () async {
      final ruta = seleccionada.value;
      // Sin archivo elegido no hay nada que guardar; el diálogo sigue
      // abierto en vez de cerrarse sin hacer nada.
      if (ruta == null) return null;

      final archivo = File(ruta);
      final resultado = await ref
          .read(empresaExpedienteControllerProvider.notifier)
          .registrarLogo(sourceFilePath: ruta, originalFileName: archivo.uri.pathSegments.last);

      if (resultado is RegistrarLogoEmpresaExitoso) return true;
      if (context.mounted) RisegFeedback.showError(context, _mensajeDeError(l10n, resultado));
      return null;
    },
  );

  seleccionada.dispose();
}

/// Traduce el resultado a algo que explique **qué** pasó con el archivo.
String _mensajeDeError(AppLocalizations l10n, RegistrarLogoEmpresaResultado resultado) {
  return switch (resultado) {
    RegistrarLogoEmpresaArchivoInvalido(:final motivo) => switch (motivo) {
      LogoDemasiadoGrande(:final maximoBytes) => l10n.empresaLogoErrorDemasiadoGrande(maximoBytes ~/ (1024 * 1024)),
      LogoFormatoNoAceptado() => l10n.empresaLogoErrorFormato,
      LogoNoExiste() => l10n.empresaLogoErrorNoExiste,
      LogoIlegible() => l10n.empresaLogoErrorNoExiste,
      LogoAceptado() => l10n.empresaLogoErrorInesperado,
    },
    _ => l10n.empresaLogoErrorInesperado,
  };
}

class _FormularioLogoEmpresa extends StatefulWidget {
  const _FormularioLogoEmpresa({
    required this.nombreComercial,
    required this.logoActualPath,
    required this.seleccionada,
    required this.ref,
  });

  final String nombreComercial;
  final String? logoActualPath;
  final ValueNotifier<String?> seleccionada;
  final WidgetRef ref;

  @override
  State<_FormularioLogoEmpresa> createState() => _FormularioLogoEmpresaState();
}

class _FormularioLogoEmpresaState extends State<_FormularioLogoEmpresa> {
  bool _quitando = false;

  Future<void> _seleccionar() async {
    final seleccion = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      // El selector filtra por comodidad; la garantía real es la revisión
      // de la firma del archivo en el caso de uso.
      allowedExtensions: const ['png', 'jpg', 'jpeg'],
    );
    final archivo = seleccion?.files.singleOrNull;
    if (archivo?.path == null) return;
    widget.seleccionada.value = archivo!.path;
    if (mounted) setState(() {});
  }

  Future<void> _quitar() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmado = await RisegDialog.showConfirmation(
      context: context,
      title: l10n.empresaLogoQuitarTitulo,
      message: l10n.empresaLogoQuitarMensaje,
      confirmLabel: l10n.empresaLogoBotonQuitar,
      cancelLabel: l10n.empresaLogoBotonCancelar,
    );
    if (confirmado != true || !mounted) return;

    setState(() => _quitando = true);
    final resultado = await widget.ref.read(empresaExpedienteControllerProvider.notifier).quitarLogo();
    if (!mounted) return;

    if (resultado is EliminarLogoEmpresaExitoso) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _quitando = false);
      RisegFeedback.showError(context, l10n.empresaLogoErrorInesperado);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final rutaMostrada = widget.seleccionada.value ?? widget.logoActualPath;
    final existe = rutaMostrada != null && File(rutaMostrada).existsSync();
    final hayLogoVigente = widget.logoActualPath != null && File(widget.logoActualPath!).existsSync();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 160,
            height: 96,
            decoration: BoxDecoration(
              color: existe ? colors.surface : colors.accentSoftBg,
              borderRadius: AppRadius.mdRadius,
              border: Border.all(color: colors.borderSubtle),
            ),
            padding: const EdgeInsets.all(AppSpacing.xs),
            alignment: Alignment.center,
            // Sin logotipo se muestran las iniciales de la Empresa, nunca un
            // logotipo de reserva: el producto no supone quién es la Empresa.
            child: existe
                ? Image.file(File(rutaMostrada), fit: BoxFit.contain, key: const Key('empresa_logo_preview'))
                : Text(
                    inicialesDe(widget.nombreComercial),
                    key: const Key('empresa_logo_preview_iniciales'),
                    style: AppTypography.label.copyWith(color: colors.accentText, fontSize: 24),
                  ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(l10n.empresaLogoAyuda, style: AppTypography.caption.copyWith(color: colors.textMuted)),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            RisegButton(
              key: const Key('empresa_logo_boton_seleccionar'),
              label: hayLogoVigente ? l10n.empresaLogoBotonCambiar : l10n.empresaLogoBotonCargar,
              icon: Icons.image_outlined,
              variant: RisegButtonVariant.secondary,
              onPressed: _quitando ? null : _seleccionar,
            ),
            if (hayLogoVigente)
              RisegButton(
                key: const Key('empresa_logo_boton_quitar'),
                label: l10n.empresaLogoBotonQuitar,
                icon: Icons.delete_outline,
                variant: RisegButtonVariant.ghost,
                loading: _quitando,
                onPressed: _quitando ? null : _quitar,
              ),
          ],
        ),
      ],
    );
  }
}
