import 'package:riseg_one/features/finanzas/presentation/mensaje_saldo_insuficiente.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/adjuntar_comprobante_recarga_linea_telefonica_usecase.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/registrar_recarga_linea_telefonica_usecase.dart';

import '../../telefonia_providers.dart';
import 'origen_financiero_recarga_campos.dart';

int? _centavosDesdeTexto(String texto) {
  final normalizado = texto.trim().replaceAll(',', '');
  if (normalizado.isEmpty) return null;
  final pesos = double.tryParse(normalizado);
  if (pesos == null) return null;
  return (pesos * 100).round();
}

/// Diálogo "Registrar recarga" (Etapa 9C) — línea, fecha, importe,
/// observaciones opcionales. El comprobante es opcional y se adjunta
/// después de crear el registro (mismo patrón de composición segura
/// que `registrar_mantenimiento_vehiculo_dialog.dart`, Etapa 8D).
/// Devuelve `true` si tuvo éxito.
Future<bool> mostrarDialogoRegistrarRecargaLineaTelefonica(
  BuildContext context,
  WidgetRef ref,
  String lineaTelefonicaId,
) async {
  final l10n = AppLocalizations.of(context)!;

  // Una recarga ES una salida de dinero: sin origen financiero no se
  // registra (§4). Los catálogos se cargan una sola vez, antes de abrir.
  final origen = await cargarOpcionesOrigenRecarga(ref);
  if (!context.mounted) return false;

  DateTime fecha = DateTime.now();
  final importeCtrl = TextEditingController();
  final observacionesCtrl = TextEditingController();
  var seleccion = const OrigenFinancieroRecarga();
  String? archivoPath;
  String? archivoNombre;
  String? errorGeneral;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.lineaTelefonicaRecargaDialogoTitulo,
    confirmLabel: l10n.lineaTelefonicaRecargaBotonGuardar,
    cancelLabel: l10n.lineaTelefonicaBotonCancelar,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        return SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RisegDateField(
                label: l10n.lineaTelefonicaRecargaCampoFecha,
                value: fecha,
                onChanged: (valor) => setState(() => fecha = valor),
              ),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(
                key: const Key('recarga_campo_importe'),
                label: l10n.lineaTelefonicaRecargaCampoImporte,
                controller: importeCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                autofocus: true,
              ),
              const SizedBox(height: AppSpacing.md),
              ...camposOrigenFinancieroRecarga(
                l10n: l10n,
                opciones: origen,
                seleccion: seleccion,
                onCambio: (valor) => setState(() => seleccion = valor),
              ),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(label: l10n.lineaTelefonicaRecargaCampoObservaciones, controller: observacionesCtrl),
              const SizedBox(height: AppSpacing.md),
              Text(l10n.lineaTelefonicaRecargaCampoComprobante, style: AppTypography.label),
              const SizedBox(height: AppSpacing.xs),
              if (archivoPath == null)
                RisegButton(
                  label: l10n.lineaTelefonicaRecargaBotonSeleccionarComprobante,
                  variant: RisegButtonVariant.secondary,
                  icon: Icons.attach_file,
                  onPressed: () async {
                    final seleccion = await FilePicker.platform.pickFiles();
                    final archivo = seleccion?.files.singleOrNull;
                    if (archivo?.path == null) return;
                    setState(() {
                      archivoPath = archivo!.path;
                      archivoNombre = archivo.name;
                    });
                  },
                )
              else
                Row(
                  children: [
                    Expanded(child: Text(archivoNombre ?? '', overflow: TextOverflow.ellipsis)),
                    RisegButton(
                      label: l10n.crearEmpleadoBotonQuitar,
                      variant: RisegButtonVariant.ghost,
                      onPressed: () => setState(() {
                        archivoPath = null;
                        archivoNombre = null;
                      }),
                    ),
                  ],
                ),
              if (errorGeneral != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(errorGeneral!, style: AppTypography.caption.copyWith(color: Theme.of(dialogContext).colorScheme.error)),
              ],
            ],
          ),
        );
      },
    ),
    onConfirm: () async {
      final importe = _centavosDesdeTexto(importeCtrl.text);
      if (importe == null || importe <= 0) {
        errorGeneral = l10n.lineaTelefonicaRecargaErrorImporteInvalido;
        return null;
      }
      final faltaOrigen = seleccion.errorFaltante(l10n);
      if (faltaOrigen != null) {
        errorGeneral = faltaOrigen;
        return null;
      }
      // Saldo insuficiente no es un "error inesperado": lo traduce el
      // mecanismo central y el formulario sigue abierto, con lo ya
      // capturado, para que el usuario elija otra cuenta.
      final registrado = await ejecutarMostrandoSaldoInsuficiente(
        context,
        l10n,
        () => ref.read(registrarRecargaLineaTelefonicaAutorizadoProvider)(
            lineaTelefonicaId: lineaTelefonicaId,
            fecha: fecha,
            importe: importe,
            formaPago: seleccion.formaPago,
            cuentaFinancieraId: seleccion.cuentaFinancieraId,
            deudaIdTarjeta: seleccion.deudaIdTarjeta,
            observaciones: observacionesCtrl.text,
          ),
      );
      if (registrado == null) return null;
      if (!context.mounted) return false;

      switch (registrado) {
        case RegistrarRecargaLineaTelefonicaImporteInvalido():
          errorGeneral = l10n.lineaTelefonicaRecargaErrorImporteInvalido;
          return null;
        case RegistrarRecargaLineaTelefonicaLineaDeBaja():
          errorGeneral = l10n.lineaTelefonicaRecargaErrorLineaDeBaja;
          return null;
        case RegistrarRecargaLineaTelefonicaOrigenFinancieroRequerido():
        case RegistrarRecargaLineaTelefonicaOrigenFinancieroAmbiguo():
          errorGeneral = l10n.recargaOrigenFinancieroRequerido;
          return null;
        case RegistrarRecargaLineaTelefonicaTarjetaInvalida():
          errorGeneral = l10n.recargaTarjetaInvalida;
          return null;
        case RegistrarRecargaLineaTelefonicaTarjetaSinLimiteConfigurado():
          errorGeneral = l10n.recargaTarjetaSinLimite;
          return null;
        case RegistrarRecargaLineaTelefonicaTarjetaExcedeLimite():
          errorGeneral = l10n.recargaTarjetaExcedeLimite;
          return null;
        case RegistrarRecargaLineaTelefonicaLineaNoExiste():
        case RegistrarRecargaLineaTelefonicaErrorInesperado():
          RisegFeedback.showError(context, l10n.lineaTelefonicaErrorInesperado);
          return false;
        case RegistrarRecargaLineaTelefonicaExitoso(:final recarga):
          if (archivoPath != null) {
            final adjuntado = await ref.read(adjuntarComprobanteRecargaLineaTelefonicaAutorizadoProvider)(
                  recargaLineaTelefonicaId: recarga.id,
                  sourceFilePath: archivoPath!,
                  originalFileName: archivoNombre!,
                  mimeType: 'application/octet-stream',
                );
            if (!context.mounted) return false;
            if (adjuntado is! AdjuntarComprobanteRecargaLineaTelefonicaExitoso) {
              RisegFeedback.showError(context, l10n.lineaTelefonicaErrorInesperado);
              return true;
            }
          }
          RisegFeedback.showSuccess(context, l10n.lineaTelefonicaRecargaGuardadoExito);
          return true;
      }
    },
  );

  WidgetsBinding.instance.addPostFrameCallback((_) {
    importeCtrl.dispose();
    observacionesCtrl.dispose();
  });
  return resultado ?? false;
}
