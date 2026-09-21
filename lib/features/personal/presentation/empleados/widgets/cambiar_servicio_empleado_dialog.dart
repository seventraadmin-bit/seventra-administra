import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/linea_comercial_con_vigencia.dart';
import 'package:riseg_one/features/personal/domain/usecases/cambiar_servicio_empleado_usecase.dart';

import '../../../../organizacion/organizacion_providers.dart';
import '../../../personal_providers.dart';
import 'crear_empleado_dialog.dart' show centavosDesdeTexto;
import 'sueldo_acordado_fields.dart';

/// Diálogo "Cambiar de servicio" (Etapa 5D) — solo cuando el Empleado
/// tiene una asignación vigente. Cierra la asignación anterior (motivo
/// automático `cambioServicio`) y crea la nueva en una sola transacción
/// — el usuario nunca tiene que retirar primero y asignar después
/// (Resolución explícita de Marlon).
///
/// Devuelve `true` si se registró correctamente.
Future<bool> mostrarDialogoCambiarServicioEmpleado(
  BuildContext context,
  WidgetRef ref,
  EmpleadoData empleado,
  String servicioActualId,
) async {
  final l10n = AppLocalizations.of(context)!;

  String? servicioId;
  String? lineaComercialId;
  String? turnoId;
  DateTime? fecha = DateTime.now();
  final observacionesController = TextEditingController();
  final sueldoController = TextEditingController();
  final bonoController = TextEditingController();
  String? errorServicio;
  String? errorLinea;
  String? errorFecha;
  String? errorSueldo;
  String? errorBono;
  List<LineaComercialConVigencia> lineasDelServicio = [];

  final servicios = (await ref.read(servicioRepositoryProvider).listar())
      .where((item) => item.servicio.estatus == EstatusServicio.activo.name && item.servicio.id != servicioActualId)
      .toList();
  final modalidadesTurno = await ref.read(catalogoRepositoryProvider).listarModalidadesTurno();
  if (!context.mounted) return false;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.cambiarServicioEmpleadoDialogoTitulo,
    confirmLabel: l10n.cambiarServicioEmpleadoBotonConfirmar,
    cancelLabel: l10n.cambiarServicioEmpleadoBotonCancelar,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        Future<void> elegirServicio(String? valor) async {
          final lineas = valor == null ? <LineaComercialConVigencia>[] : await ref.read(servicioComercialRepositoryProvider).listarLineas(valor);
          setState(() {
            servicioId = valor;
            lineasDelServicio = lineas;
            lineaComercialId = null;
            errorServicio = null;
            errorLinea = null;
            errorSueldo = null;
            errorBono = null;
            precargarSueldoAcordado(linea: null, sueldoController: sueldoController, bonoController: bonoController);
          });
        }

        void elegirLinea(String? valor) {
          final linea = buscarLineaComercialPorId(lineasDelServicio, valor);
          setState(() {
            lineaComercialId = valor;
            errorLinea = null;
            errorSueldo = null;
            errorBono = null;
            if (linea?.vigenciaActual != null) turnoId = linea!.vigenciaActual!.modalidadTurnoId;
            precargarSueldoAcordado(linea: linea, sueldoController: sueldoController, bonoController: bonoController);
          });
        }

        final lineasVigentes = lineasDelServicio.where((l) => l.vigenciaActual != null).toList();
        final lineaElegida = buscarLineaComercialPorId(lineasDelServicio, lineaComercialId);

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RisegSelect<String?>(
              label: l10n.empleadoCampoServicioNuevo,
              value: servicioId,
              errorText: errorServicio,
              items: [
                for (final item in servicios) RisegSelectItem(value: item.servicio.id, label: item.servicio.nombre),
              ],
              onChanged: (valor) => elegirServicio(valor),
            ),
            if (servicioId != null && lineasVigentes.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              RisegSelect<String?>(
                label: l10n.empleadoCampoLineaComercial,
                value: lineaComercialId,
                errorText: errorLinea,
                items: [
                  for (final l in lineasVigentes) RisegSelectItem(value: l.linea.id, label: etiquetaLineaComercial(l10n, l)),
                ],
                onChanged: elegirLinea,
              ),
              if (lineaElegida?.vigenciaActual != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  l10n.empleadoLineaComercialCapacidad(
                    lineaElegida!.asignadosVigentes,
                    lineaElegida.vigenciaActual!.cantidadElementos,
                  ),
                  style: AppTypography.caption.copyWith(color: context.colors.textMuted),
                ),
                if (lineaElegida.capacidadExcedida) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    l10n.empleadoLineaComercialCapacidadExcedidaAdviso,
                    style: AppTypography.caption.copyWith(color: context.colors.warning),
                  ),
                ],
              ],
            ],
            const SizedBox(height: AppSpacing.md),
            RisegSelect<String?>(
              label: l10n.empleadoCampoTurno,
              value: turnoId,
              items: [
                RisegSelectItem(value: null, label: l10n.empleadoCampoSinAsignar),
                for (final m in modalidadesTurno) RisegSelectItem(value: m.id, label: m.nombre),
              ],
              onChanged: (valor) => setState(() => turnoId = valor),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegDateField(
              label: l10n.empleadoCampoFechaCambioServicio,
              value: fecha,
              errorText: errorFecha,
              onChanged: (valor) => setState(() {
                fecha = valor;
                errorFecha = null;
              }),
            ),
            if (servicioId != null) ...[
              const SizedBox(height: AppSpacing.md),
              SueldoAcordadoFields(
                linea: lineaElegida,
                sueldoController: sueldoController,
                bonoController: bonoController,
                errorSueldo: errorSueldo,
                errorBono: errorBono,
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            RisegTextField(label: l10n.empleadoCampoObservaciones, controller: observacionesController),
          ],
        );
      },
    ),
    onConfirm: () async {
      // Mismo criterio que `asignar_servicio_empleado_dialog.dart`:
      // `showForm` solo mantiene el diálogo abierto cuando `onConfirm`
      // devuelve `null`; todo error corregible in situ debe devolver
      // `null`, nunca `false`.
      if (servicioId == null) {
        errorServicio = l10n.empleadoCampoServicioNuevo;
        return null;
      }
      if (fecha == null) {
        errorFecha = l10n.empleadoCampoFechaCambioServicio;
        return null;
      }

      final resultado = await ref.read(cambiarServicioEmpleadoAutorizadoProvider)(
            empleadoId: empleado.id,
            nuevoServicioId: servicioId!,
            fecha: fecha!,
            turnoId: turnoId,
            lineaComercialId: lineaComercialId,
            observaciones: observacionesController.text,
            sueldoMensual: centavosDesdeTexto(sueldoController.text),
            bonoMensual: centavosDesdeTexto(bonoController.text),
          );

      if (!context.mounted) return null;

      switch (resultado) {
        case CambiarServicioEmpleadoExitoso():
          RisegFeedback.showSuccess(context, l10n.cambiarServicioEmpleadoExito);
          return true;
        case CambiarServicioEmpleadoEmpleadoNoExiste():
        case CambiarServicioEmpleadoNoTieneAsignacionVigente():
        case CambiarServicioEmpleadoErrorInesperado():
          RisegFeedback.showError(context, l10n.cambiarServicioEmpleadoErrorInesperado);
          return false;
        case CambiarServicioEmpleadoSueldoRequerido():
          errorSueldo = l10n.empleadoErrorSueldoRequerido;
          return null;
        case CambiarServicioEmpleadoSueldoInvalido():
          errorSueldo = l10n.empleadoErrorSueldoAcordadoInvalido;
          return null;
        case CambiarServicioEmpleadoBonoInvalido():
          errorBono = l10n.empleadoErrorBonoAcordadoInvalido;
          return null;
        case CambiarServicioEmpleadoServicioNoExiste():
        case CambiarServicioEmpleadoServicioNoActivo():
        case CambiarServicioEmpleadoMismoServicio():
          errorServicio = l10n.empleadoErrorServicioNoActivo;
          return null;
        case CambiarServicioEmpleadoLineaComercialRequerida():
          errorLinea = l10n.empleadoErrorLineaComercialRequerida;
          return null;
        case CambiarServicioEmpleadoLineaComercialInvalida():
          errorLinea = l10n.empleadoErrorLineaComercialInvalida;
          return null;
        case CambiarServicioEmpleadoFechaInvalida():
          errorFecha = l10n.cambiarServicioEmpleadoErrorFechaInvalida;
          return null;
      }
    },
  );

  // Liberar aquí es seguro: `RisegDialog.showForm` no devuelve
  // hasta que la ruta del diálogo terminó de cerrarse (ver su
  // documentación). Antes sí hacía falta aplazarlo 300 ms, y ese
  // aplazamiento dejaba un Timer vivo después de desmontar el árbol.
  observacionesController.dispose();
  sueldoController.dispose();
  bonoController.dispose();
  return resultado ?? false;
}
