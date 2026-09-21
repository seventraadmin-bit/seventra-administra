import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/organizacion/presentation/shared/campo_consulta.dart';
import 'package:riseg_one/features/personal/domain/usecases/construir_eventos_baja.dart';
import 'package:riseg_one/features/personal/presentation/empleados/widgets/motivo_baja_empleado_labels.dart' show motivoBajaEmpleadoLabel;

final _formatoFecha = DateFormat('dd/MM/yyyy');

/// "Detalle de baja" (Etapa 15) — resumen compacto de UN evento de
/// baja, nunca el expediente completo (ese tiene su propio botón "Ver
/// expediente").
Future<void> mostrarDialogoDetalleBaja(BuildContext context, BajaEvento evento) async {
  final l10n = AppLocalizations.of(context)!;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final colors = dialogContext.colors;
      final ciclo = evento.permanencia;
      return Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.bajaDetalleTitulo, style: AppTypography.heading2.copyWith(color: colors.textPrimary)),
                const SizedBox(height: AppSpacing.md),
                CampoConsulta(label: l10n.bajaDetalleEmpleado, value: '${evento.nombreCompleto} · No. ${evento.numeroEmpleado}'),
                const SizedBox(height: AppSpacing.sm),
                CampoConsulta(
                  label: l10n.bajaDetallePeriodo,
                  value: '${_formatoFecha.format(evento.fechaIngreso)} – ${_formatoFecha.format(evento.fechaBaja)}',
                ),
                const SizedBox(height: AppSpacing.sm),
                CampoConsulta(
                  label: l10n.bajaDetallePermanencia,
                  value: l10n.bajaDetallePermanenciaDetalle(ciclo.diasLaborados, ciclo.antiguedadAnios, ciclo.antiguedadMeses),
                ),
                const SizedBox(height: AppSpacing.sm),
                CampoConsulta(label: l10n.empleadosColumnaPuesto, value: evento.puestoNombre ?? '—'),
                const SizedBox(height: AppSpacing.sm),
                CampoConsulta(label: l10n.personalActivoColumnaServicio, value: evento.servicioNombre ?? '—'),
                const SizedBox(height: AppSpacing.sm),
                CampoConsulta(label: l10n.personalActivoColumnaTurno, value: evento.turnoNombre ?? '—'),
                const SizedBox(height: AppSpacing.sm),
                CampoConsulta(label: l10n.bajaDetalleMotivo, value: motivoBajaEmpleadoLabel(l10n, evento.motivoBaja)),
                if (evento.observacionesBaja != null && evento.observacionesBaja!.trim().isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  CampoConsulta(label: l10n.bajaDetalleObservaciones, value: evento.observacionesBaja),
                ],
                const SizedBox(height: AppSpacing.lg),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: AppSpacing.xs,
                  children: [
                    RisegButton(
                      label: l10n.bajaDetalleBotonVerExpediente,
                      variant: RisegButtonVariant.ghost,
                      onPressed: () {
                        Navigator.of(dialogContext).pop();
                        dialogContext.push('/personal/empleados/${evento.empleadoId}');
                      },
                    ),
                    RisegButton(
                      label: MaterialLocalizations.of(dialogContext).closeButtonLabel,
                      onPressed: () => Navigator.of(dialogContext).pop(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
