import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/inventario/domain/usecases/cambiar_responsable_asignacion_usecase.dart';
import 'package:riseg_one/features/inventario/inventario_providers.dart';

/// Diálogo "Cambiar responsable" (Etapa 9D, ajuste aprobado por
/// Marlon) — distinto de "Reemplazar" (`mostrarDialogoReemplazarAsignacion`,
/// que cambia el BIEN): aquí el bien se queda igual, solo cambia quién
/// es responsable de él. Delega en `CambiarResponsableAsignacionUseCase`
/// vía `cambiarResponsableAsignacionAutorizadoProvider` — nunca genera
/// una devolución/entrada de Inventario ni toca el estatus de la
/// unidad.
Future<bool> mostrarDialogoCambiarResponsableAsignacion(
  BuildContext context,
  WidgetRef ref, {
  required AsignacionData asignacion,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final opciones = ref.read(obtenerOpcionesResponsableAsignacionUseCaseProvider);
  final cambiarResponsable = ref.read(cambiarResponsableAsignacionAutorizadoProvider);

  final empleados = await opciones.obtenerEmpleados();
  final servicios = await opciones.obtenerServicios();
  if (!context.mounted) return false;

  String destinoTipo = asignacion.servicioId != null ? 'servicio' : 'empleado';
  String? empleadoId;
  String? servicioId;
  DateTime fecha = DateTime.now();
  final observacionesCtrl = TextEditingController();
  String? errorGeneral;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.cambiarResponsableAsignacionDialogoTitulo,
    confirmLabel: l10n.cambiarResponsableAsignacionBotonConfirmar,
    cancelLabel: l10n.cambiarResponsableAsignacionBotonCancelar,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        return SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RisegSelect<String>(
                label: l10n.cambiarResponsableAsignacionCampoDestinoTipo,
                value: destinoTipo,
                items: [
                  RisegSelectItem(value: 'empleado', label: l10n.cambiarResponsableAsignacionOpcionEmpleado),
                  RisegSelectItem(value: 'servicio', label: l10n.cambiarResponsableAsignacionOpcionServicio),
                ],
                onChanged: (valor) => setState(() {
                  destinoTipo = valor ?? destinoTipo;
                  empleadoId = null;
                  servicioId = null;
                }),
              ),
              const SizedBox(height: AppSpacing.md),
              if (destinoTipo == 'empleado')
                RisegSelect<String?>(
                  label: l10n.cambiarResponsableAsignacionCampoEmpleado,
                  value: empleadoId,
                  items: [for (final e in empleados) RisegSelectItem(value: e.id, label: e.nombre)],
                  onChanged: (valor) => setState(() => empleadoId = valor),
                )
              else
                RisegSelect<String?>(
                  label: l10n.cambiarResponsableAsignacionCampoServicio,
                  value: servicioId,
                  items: [for (final s in servicios) RisegSelectItem(value: s.id, label: s.nombre)],
                  onChanged: (valor) => setState(() => servicioId = valor),
                ),
              const SizedBox(height: AppSpacing.md),
              RisegDateField(
                label: l10n.cambiarResponsableAsignacionCampoFecha,
                value: fecha,
                onChanged: (valor) => setState(() => fecha = valor),
              ),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(label: l10n.cambiarResponsableAsignacionCampoObservaciones, controller: observacionesCtrl),
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
      if (destinoTipo == 'empleado' ? empleadoId == null : servicioId == null) {
        errorGeneral = l10n.cambiarResponsableAsignacionErrorDestinoInvalido;
        return null;
      }
      final resultado = await cambiarResponsable(
        asignacionId: asignacion.id,
        nuevoEmpleadoId: destinoTipo == 'empleado' ? empleadoId : null,
        nuevoServicioId: destinoTipo == 'servicio' ? servicioId : null,
        fecha: fecha,
        observaciones: observacionesCtrl.text.trim().isEmpty ? null : observacionesCtrl.text.trim(),
      );
      if (!context.mounted) return false;
      switch (resultado) {
        case CambiarResponsableAsignacionExitoso():
          RisegFeedback.showSuccess(context, l10n.cambiarResponsableAsignacionExito);
          return true;
        case CambiarResponsableAsignacionDestinoInvalido():
          errorGeneral = l10n.cambiarResponsableAsignacionErrorDestinoInvalido;
          return null;
        case CambiarResponsableAsignacionMismoResponsable():
          errorGeneral = l10n.cambiarResponsableAsignacionErrorMismoResponsable;
          return null;
        case CambiarResponsableAsignacionFechaInvalida():
          errorGeneral = l10n.cambiarResponsableAsignacionErrorFechaInvalida;
          return null;
        case CambiarResponsableAsignacionNoExiste():
        case CambiarResponsableAsignacionNoVigente():
        case CambiarResponsableAsignacionSoloUnidadesSerializadas():
        case CambiarResponsableAsignacionErrorInesperado():
          RisegFeedback.showError(context, l10n.cambiarResponsableAsignacionErrorInesperado);
          return false;
      }
    },
  );

  observacionesCtrl.dispose();
  return resultado ?? false;
}
