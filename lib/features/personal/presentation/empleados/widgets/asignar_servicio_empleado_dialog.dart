import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/linea_comercial_con_vigencia.dart';
import 'package:riseg_one/features/personal/domain/usecases/asignar_empleado_servicio_usecase.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

import '../../../../organizacion/organizacion_providers.dart';
import '../../../personal_providers.dart';
import 'crear_empleado_dialog.dart' show centavosDesdeTexto;
import 'sueldo_acordado_fields.dart';

/// Diálogo "Asignar a servicio" (Etapa 5D) — solo cuando el Empleado no
/// tiene una asignación vigente. Registra Servicio/Perfil comercial/
/// Turno/Fecha de inicio/Observaciones, nada de horarios/incidencias
/// (fuera de alcance explícito).
///
/// Devuelve `true` si se registró correctamente.
Future<bool> mostrarDialogoAsignarServicioEmpleado(BuildContext context, WidgetRef ref, EmpleadoData empleado) async {
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
      .where((item) => item.servicio.estatus == EstatusServicio.activo.name)
      .toList();
  final modalidadesTurno = await ref.read(catalogoRepositoryProvider).listarModalidadesTurno();
  if (!context.mounted) return false;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.asignarServicioEmpleadoDialogoTitulo,
    confirmLabel: l10n.asignarServicioEmpleadoBotonConfirmar,
    cancelLabel: l10n.asignarServicioEmpleadoBotonCancelar,
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
              label: l10n.empleadoCampoServicio,
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
              label: l10n.empleadoCampoFechaInicioAsignacion,
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
      // `RisegDialog.showForm` solo mantiene el diálogo abierto cuando
      // `onConfirm` devuelve `null` — un `false` (aunque parezca "no
      // válido") lo cierra de inmediato, descartando el error de campo
      // antes de mostrarlo. Todo error corregible in situ debe devolver
      // `null`; `false` queda reservado para los casos que ya muestran
      // su propio aviso (`RisegFeedback.showError`) y cierran a propósito.
      if (servicioId == null) {
        errorServicio = l10n.empleadoCampoServicio;
        return null;
      }
      if (fecha == null) {
        errorFecha = l10n.empleadoCampoFechaInicioAsignacion;
        return null;
      }

      final resultado = await ref.read(asignarEmpleadoServicioUseCaseProvider).ejecutar(
            empleadoId: empleado.id,
            servicioId: servicioId!,
            fechaInicio: fecha!,
            turnoId: turnoId,
            lineaComercialId: lineaComercialId,
            observaciones: observacionesController.text,
            sueldoMensual: centavosDesdeTexto(sueldoController.text),
            bonoMensual: centavosDesdeTexto(bonoController.text),
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          );

      if (!context.mounted) return null;

      switch (resultado) {
        case AsignarEmpleadoServicioExitoso():
          RisegFeedback.showSuccess(context, l10n.asignarServicioEmpleadoExito);
          return true;
        case AsignarEmpleadoServicioEmpleadoNoExiste():
        case AsignarEmpleadoServicioEmpleadoNoActivo():
        case AsignarEmpleadoServicioYaTieneAsignacionVigente():
        case AsignarEmpleadoServicioErrorInesperado():
          RisegFeedback.showError(context, l10n.asignarServicioEmpleadoErrorInesperado);
          return false;
        case AsignarEmpleadoServicioSueldoRequerido():
          errorSueldo = l10n.empleadoErrorSueldoRequerido;
          return null;
        case AsignarEmpleadoServicioSueldoInvalido():
          errorSueldo = l10n.empleadoErrorSueldoAcordadoInvalido;
          return null;
        case AsignarEmpleadoServicioBonoInvalido():
          errorBono = l10n.empleadoErrorBonoAcordadoInvalido;
          return null;
        case AsignarEmpleadoServicioServicioNoExiste():
        case AsignarEmpleadoServicioServicioNoActivo():
          errorServicio = l10n.empleadoErrorServicioNoActivo;
          return null;
        case AsignarEmpleadoServicioLineaComercialRequerida():
          errorLinea = l10n.empleadoErrorLineaComercialRequerida;
          return null;
        case AsignarEmpleadoServicioLineaComercialInvalida():
          errorLinea = l10n.empleadoErrorLineaComercialInvalida;
          return null;
        case AsignarEmpleadoServicioFechaInvalida():
          errorFecha = l10n.asignarServicioEmpleadoErrorFechaInvalida;
          return null;
      }
    },
  );

  // Deferred: el diálogo sigue montado unos instantes durante su
  // animación de salida — liberar los controllers de inmediato puede
  // reproducir el crash "A TextEditingController was used after being
  // disposed" (mismo criterio que `crear_empleado_dialog.dart`, Etapa
  // 5D.1), y este diálogo ahora también intercambia condicionalmente
  // los campos de sueldo/bono acordado según la línea comercial
  // elegida.
  unawaited(
    Future.delayed(const Duration(milliseconds: 300), () {
      observacionesController.dispose();
      sueldoController.dispose();
      bonoController.dispose();
    }),
  );
  return resultado ?? false;
}
