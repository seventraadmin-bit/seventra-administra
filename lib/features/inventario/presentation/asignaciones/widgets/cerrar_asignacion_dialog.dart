import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/dashboard/presentation/dashboard_controller.dart';
import 'package:riseg_one/features/inventario/data/tables/asignacion_table.dart';
import 'package:riseg_one/features/inventario/domain/usecases/cerrar_asignacion_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/obtener_empleados_responsables_servicio_usecase.dart'
    show EmpleadoOpcion;
import 'package:riseg_one/features/inventario/inventario_providers.dart';
import 'package:riseg_one/features/inventario/presentation/articulos/articulos_controller.dart';

String motivoCierreLabel(AppLocalizations l10n, MotivoCierreAsignacion motivo) {
  return switch (motivo) {
    MotivoCierreAsignacion.desgaste => l10n.motivoCierreDesgaste,
    MotivoCierreAsignacion.dano => l10n.motivoCierreDano,
    MotivoCierreAsignacion.perdida => l10n.motivoCierrePerdida,
    MotivoCierreAsignacion.cambioTalla => l10n.motivoCierreCambioTalla,
    MotivoCierreAsignacion.defecto => l10n.motivoCierreDefecto,
    MotivoCierreAsignacion.bajaEmpleado => l10n.motivoCierreBajaEmpleado,
    MotivoCierreAsignacion.otro => l10n.motivoCierreOtro,
  };
}

/// Diálogo de cierre de una `Asignacion` (Etapa 7B) — cubre Devolución
/// y Reporte de daño/pérdida con el mismo caso de uso
/// (`CerrarAsignacionUseCase`); [motivosDisponibles] restringe el
/// picker según el botón de origen (Devolver vs. Reportar
/// daño/pérdida), sin duplicar el diálogo.
Future<bool> mostrarDialogoCerrarAsignacion(
  BuildContext context,
  WidgetRef ref, {
  required AsignacionData asignacion,
  required String titulo,
  required List<MotivoCierreAsignacion> motivosDisponibles,
  List<EmpleadoOpcion> empleadosParaResponsable = const [],
}) async {
  final l10n = AppLocalizations.of(context)!;
  final cerrarAsignacion = ref.read(cerrarAsignacionAutorizadoProvider);

  MotivoCierreAsignacion motivo = motivosDisponibles.first;
  bool? atribuibleAlEmpleado;
  bool generaDescuento = false;
  final observacionesCtrl = TextEditingController();
  final importeCtrl = TextEditingController();
  String? empleadoResponsableId = asignacion.empleadoId;
  DateTime? fechaCierre = DateTime.now();
  String? errorGeneral;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: titulo,
    confirmLabel: l10n.cerrarAsignacionBotonConfirmar,
    cancelLabel: l10n.cerrarAsignacionBotonCancelar,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        final disparaDanoPerdida = motivo.disparaDanoPerdida;
        return SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (motivosDisponibles.length > 1)
                RisegSelect<MotivoCierreAsignacion>(
                  label: l10n.cerrarAsignacionCampoMotivo,
                  value: motivo,
                  items: [
                    for (final m in motivosDisponibles) RisegSelectItem(value: m, label: motivoCierreLabel(l10n, m)),
                  ],
                  onChanged: (valor) => setState(() => motivo = valor ?? motivo),
                ),
              const SizedBox(height: AppSpacing.md),
              RisegDateField(
                label: l10n.cerrarAsignacionCampoFecha,
                value: fechaCierre,
                onChanged: (valor) => setState(() => fechaCierre = valor),
              ),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(label: l10n.cerrarAsignacionCampoObservaciones, controller: observacionesCtrl),
              if (disparaDanoPerdida) ...[
                const SizedBox(height: AppSpacing.md),
                RisegSelect<bool?>(
                  label: l10n.cerrarAsignacionCampoAtribuible,
                  value: atribuibleAlEmpleado,
                  items: [
                    RisegSelectItem(value: true, label: l10n.cerrarAsignacionSi),
                    RisegSelectItem(value: false, label: l10n.cerrarAsignacionNo),
                  ],
                  onChanged: (valor) => setState(() => atribuibleAlEmpleado = valor),
                ),
                const SizedBox(height: AppSpacing.md),
                RisegSelect<bool>(
                  label: l10n.cerrarAsignacionCampoGeneraDescuento,
                  value: generaDescuento,
                  items: [
                    RisegSelectItem(value: true, label: l10n.cerrarAsignacionSi),
                    RisegSelectItem(value: false, label: l10n.cerrarAsignacionNo),
                  ],
                  onChanged: (valor) => setState(() => generaDescuento = valor ?? false),
                ),
                if (generaDescuento) ...[
                  const SizedBox(height: AppSpacing.md),
                  RisegTextField(
                    label: l10n.cerrarAsignacionCampoImporteDescuento,
                    controller: importeCtrl,
                    keyboardType: TextInputType.number,
                  ),
                  if (empleadosParaResponsable.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.md),
                    RisegSelect<String?>(
                      label: l10n.cerrarAsignacionCampoResponsable,
                      value: empleadoResponsableId,
                      items: [for (final e in empleadosParaResponsable) RisegSelectItem(value: e.id, label: e.nombre)],
                      onChanged: (valor) => setState(() => empleadoResponsableId = valor),
                    ),
                  ],
                ],
              ],
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
      final importe = double.tryParse(importeCtrl.text.trim().replaceAll(',', ''));
      final resultado = await cerrarAsignacion(
        asignacionId: asignacion.id,
        motivo: motivo,
        fechaCierre: fechaCierre ?? DateTime.now(),
        observacionesCierre: observacionesCtrl.text.trim().isEmpty ? null : observacionesCtrl.text.trim(),
        atribuibleAlEmpleado: atribuibleAlEmpleado,
        generaDescuento: generaDescuento,
        importeDescuento: importe == null ? null : (importe * 100).round(),
        empleadoResponsableDescuentoId: empleadoResponsableId,
      );
      if (!context.mounted) return false;
      switch (resultado) {
        case CerrarAsignacionExitoso():
          // Mismo hallazgo que en `asignar_articulo_dialog.dart` — el
          // listado general de Inventario nunca se enteraba de un
          // cierre (devolución/daño/pérdida) porque este diálogo nunca
          // invalidaba `articulosControllerProvider`/`dashboardControllerProvider`.
          ref.invalidate(articulosControllerProvider);
          ref.invalidate(dashboardControllerProvider);
          RisegFeedback.showSuccess(context, l10n.cerrarAsignacionExito);
          return true;
        case CerrarAsignacionObservacionesRequeridas():
          errorGeneral = l10n.cerrarAsignacionErrorObservacionesRequeridas;
          return null;
        case CerrarAsignacionAtribucionRequerida():
          errorGeneral = l10n.cerrarAsignacionErrorAtribucionRequerida;
          return null;
        case CerrarAsignacionDescuentoInvalido():
          errorGeneral = l10n.cerrarAsignacionErrorDescuentoInvalido;
          return null;
        case CerrarAsignacionYaCerrada():
          errorGeneral = l10n.cerrarAsignacionErrorYaCerrada;
          return null;
        case CerrarAsignacionNoExiste():
        case CerrarAsignacionErrorInesperado():
          RisegFeedback.showError(context, l10n.cerrarAsignacionErrorInesperado);
          return false;
      }
    },
  );

  // Mismo hallazgo real que en `asignar_articulo_dialog.dart` — nunca
  // disponer controladores en el mismo frame en que se cierra la ruta.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    observacionesCtrl.dispose();
    importeCtrl.dispose();
  });

  return resultado ?? false;
}
