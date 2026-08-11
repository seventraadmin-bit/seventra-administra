import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_asignacion_usecase.dart';
import 'package:riseg_one/features/inventario/inventario_providers.dart';

import '../../telefonia_providers.dart';

/// Diálogo "Asignar equipo" (Etapa 9D) — entrega la unidad ya conocida
/// del expediente del equipo a un Empleado o Servicio. A diferencia de
/// `mostrarDialogoAsignarArticulo` (Inventario, Etapa 7B — que fija el
/// destino y deja elegir el artículo/unidad), aquí el artículo/unidad ya
/// están fijos y lo que se captura es el destino; delega exactamente en
/// el mismo `CrearAsignacionUseCase`/`AsignacionRepository.crear` que
/// usa Inventario, sin lógica de negocio nueva.
Future<bool> mostrarDialogoAsignarEquipoTelefonico(
  BuildContext context,
  WidgetRef ref, {
  required String articuloId,
  required String unidadId,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final crearAsignacion = ref.read(crearAsignacionAutorizadoProvider);
  final opciones = ref.read(obtenerOpcionesAsignacionLineaTelefonicaUseCaseProvider);

  final empleados = await opciones.obtenerEmpleados();
  final servicios = await opciones.obtenerServicios();
  if (!context.mounted) return false;

  String destinoTipo = 'empleado';
  String? empleadoId;
  String? servicioId;
  DateTime fechaEntrega = DateTime.now();
  final condicionCtrl = TextEditingController();
  final observacionesCtrl = TextEditingController();
  String? errorGeneral;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.equipoTelefonicoAsignarDialogoTitulo,
    confirmLabel: l10n.equipoTelefonicoAsignarBotonConfirmar,
    cancelLabel: l10n.equipoTelefonicoConfigurarBotonCancelar,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        return SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RisegSelect<String>(
                label: l10n.equipoTelefonicoAsignarCampoDestinoTipo,
                value: destinoTipo,
                items: [
                  RisegSelectItem(value: 'empleado', label: l10n.equipoTelefonicoAsignarOpcionEmpleado),
                  RisegSelectItem(value: 'servicio', label: l10n.equipoTelefonicoAsignarOpcionServicio),
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
                  label: l10n.equipoTelefonicoAsignarCampoEmpleado,
                  value: empleadoId,
                  items: [for (final e in empleados) RisegSelectItem(value: e.id, label: e.nombre)],
                  onChanged: (valor) => setState(() => empleadoId = valor),
                )
              else
                RisegSelect<String?>(
                  label: l10n.equipoTelefonicoAsignarCampoServicio,
                  value: servicioId,
                  items: [for (final s in servicios) RisegSelectItem(value: s.id, label: s.nombre)],
                  onChanged: (valor) => setState(() => servicioId = valor),
                ),
              const SizedBox(height: AppSpacing.md),
              RisegDateField(
                label: l10n.equipoTelefonicoAsignarCampoFecha,
                value: fechaEntrega,
                onChanged: (valor) => setState(() => fechaEntrega = valor),
              ),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(label: l10n.equipoTelefonicoAsignarCampoCondicion, controller: condicionCtrl),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(label: l10n.equipoTelefonicoAsignarCampoObservaciones, controller: observacionesCtrl),
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
        errorGeneral = l10n.equipoTelefonicoAsignarErrorDestinoInvalido;
        return null;
      }
      final resultado = await crearAsignacion(
        articuloId: articuloId,
        unidadId: unidadId,
        cantidad: 1,
        empleadoId: destinoTipo == 'empleado' ? empleadoId : null,
        servicioId: destinoTipo == 'servicio' ? servicioId : null,
        fechaEntrega: fechaEntrega,
        condicionEntrega: condicionCtrl.text.trim().isEmpty ? null : condicionCtrl.text.trim(),
        observaciones: observacionesCtrl.text.trim().isEmpty ? null : observacionesCtrl.text.trim(),
      );
      if (!context.mounted) return false;
      switch (resultado) {
        case CrearAsignacionExitoso():
          RisegFeedback.showSuccess(context, l10n.equipoTelefonicoAsignarExito);
          return true;
        case CrearAsignacionDestinoInvalido():
          errorGeneral = l10n.equipoTelefonicoAsignarErrorDestinoInvalido;
          return null;
        case CrearAsignacionUnidadNoDisponible():
          errorGeneral = l10n.equipoTelefonicoAsignarErrorUnidadNoDisponible;
          return null;
        case CrearAsignacionVarianteInvalida():
        case CrearAsignacionUnidadInvalida():
        case CrearAsignacionCantidadInvalida():
        case CrearAsignacionSobrepasaDisponible():
        case CrearAsignacionArticuloNoExiste():
        case CrearAsignacionErrorInesperado():
          RisegFeedback.showError(context, l10n.equipoTelefonicoConfigurarErrorInesperado);
          return false;
      }
    },
  );

  WidgetsBinding.instance.addPostFrameCallback((_) {
    condicionCtrl.dispose();
    observacionesCtrl.dispose();
  });
  return resultado ?? false;
}
