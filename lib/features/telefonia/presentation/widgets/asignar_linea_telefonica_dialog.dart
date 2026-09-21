import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/asignar_linea_telefonica_usecase.dart';

import '../../telefonia_providers.dart';
import 'coherencia_linea_equipo_mensajes.dart';

/// Diálogo "Asignar" (Etapa 9B) — entrega una línea sin destino a un
/// Empleado o a un Servicio.
///
/// Ya no ofrece "mover también el equipo asociado": Telefonía no mueve
/// la custodia. Si el equipo asociado está en manos de alguien, la
/// línea sólo puede ir a ESE destino, y el diálogo lo dice. Cuando la
/// operación resulta ser la corrección de una incoherencia histórica,
/// pide el motivo. Devuelve `true` si tuvo éxito.
Future<bool> mostrarDialogoAsignarLineaTelefonica(
  BuildContext context,
  WidgetRef ref,
  String lineaTelefonicaId,
) async {
  final l10n = AppLocalizations.of(context)!;
  final opciones = ref.read(obtenerOpcionesAsignacionLineaTelefonicaUseCaseProvider);

  final empleados = await opciones.obtenerEmpleados();
  final servicios = await opciones.obtenerServicios();
  final nombres = NombresDestinoTelefonia(
    {for (final e in empleados) e.id: e.nombre},
    {for (final s in servicios) s.id: s.nombre},
  );
  if (!context.mounted) return false;

  String destinoTipo = 'empleado';
  String? empleadoId;
  String? servicioId;
  DateTime fechaInicio = DateTime.now();
  final observacionesCtrl = TextEditingController();
  final motivoCtrl = TextEditingController();
  bool pideMotivo = false;
  String? errorGeneral;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.lineaTelefonicaAsignarDialogoTitulo,
    confirmLabel: l10n.lineaTelefonicaAsignarBotonConfirmar,
    cancelLabel: l10n.lineaTelefonicaBotonCancelar,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        return SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RisegSelect<String>(
                label: l10n.lineaTelefonicaAsignarCampoDestinoTipo,
                value: destinoTipo,
                items: [
                  RisegSelectItem(value: 'empleado', label: l10n.lineaTelefonicaAsignarOpcionEmpleado),
                  RisegSelectItem(value: 'servicio', label: l10n.lineaTelefonicaAsignarOpcionServicio),
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
                  label: l10n.lineaTelefonicaAsignarCampoEmpleado,
                  value: empleadoId,
                  items: [for (final e in empleados) RisegSelectItem(value: e.id, label: e.nombre)],
                  onChanged: (valor) => setState(() => empleadoId = valor),
                )
              else
                RisegSelect<String?>(
                  label: l10n.lineaTelefonicaAsignarCampoServicio,
                  value: servicioId,
                  items: [for (final s in servicios) RisegSelectItem(value: s.id, label: s.nombre)],
                  onChanged: (valor) => setState(() => servicioId = valor),
                ),
              const SizedBox(height: AppSpacing.md),
              RisegDateField(
                label: l10n.lineaTelefonicaAsignarCampoFechaInicio,
                value: fechaInicio,
                onChanged: (valor) => setState(() => fechaInicio = valor),
              ),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(label: l10n.lineaTelefonicaAsignarCampoObservaciones, controller: observacionesCtrl),
              if (pideMotivo) ...[
                const SizedBox(height: AppSpacing.md),
                RisegTextField(
                  key: const Key('linea_asignar_campo_motivo'),
                  label: l10n.lineaTelefonicaResolverInconsistenciaCampoMotivo,
                  controller: motivoCtrl,
                ),
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
      if (destinoTipo == 'empleado' ? empleadoId == null : servicioId == null) {
        errorGeneral = l10n.lineaTelefonicaAsignarErrorDestinoInvalido;
        return null;
      }
      final resultado = await ref.read(asignarLineaTelefonicaAutorizadoProvider)(
            lineaTelefonicaId: lineaTelefonicaId,
            empleadoId: destinoTipo == 'empleado' ? empleadoId : null,
            servicioId: destinoTipo == 'servicio' ? servicioId : null,
            fechaInicio: fechaInicio,
            observaciones: observacionesCtrl.text.trim().isEmpty ? null : observacionesCtrl.text.trim(),
            motivo: motivoCtrl.text,
          );
      if (!context.mounted) return false;
      switch (resultado) {
        case AsignarLineaTelefonicaExitoso():
          RisegFeedback.showSuccess(context, l10n.lineaTelefonicaAsignarExito);
          return true;
        case AsignarLineaTelefonicaDestinoInvalido():
          errorGeneral = l10n.lineaTelefonicaAsignarErrorDestinoInvalido;
          return null;
        case AsignarLineaTelefonicaYaAsignada():
          errorGeneral = l10n.lineaTelefonicaAsignarErrorYaAsignada;
          return null;
        case AsignarLineaTelefonicaLineaDeBaja():
          errorGeneral = l10n.lineaTelefonicaAsignarErrorLineaDeBaja;
          return null;
        case AsignarLineaTelefonicaIncoherenteConEquipo(:final coherencia):
          errorGeneral = mensajeIncoherenciaLineaEquipo(l10n, coherencia, nombres);
          return null;
        case AsignarLineaTelefonicaMotivoRequerido():
          // Se descubre aquí que la operación corrige una incoherencia
          // histórica: el campo aparece y se vuelve a confirmar.
          pideMotivo = true;
          errorGeneral = l10n.lineaTelefonicaCoherenciaMotivoRequerido;
          return null;
        case AsignarLineaTelefonicaNoExiste():
        case AsignarLineaTelefonicaErrorInesperado():
          RisegFeedback.showError(context, l10n.lineaTelefonicaErrorInesperado);
          return false;
      }
    },
  );

  WidgetsBinding.instance.addPostFrameCallback((_) {
    observacionesCtrl.dispose();
    motivoCtrl.dispose();
  });
  return resultado ?? false;
}
