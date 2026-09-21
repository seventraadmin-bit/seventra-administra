import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/personal_asignado_servicio.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');

/// Sección "Personal asignado" del expediente de Servicio (Etapa 5D) —
/// solo consulta. Toda acción (asignar/cambiar/retirar) se dispara
/// desde el expediente del Empleado, nunca desde aquí (Resolución
/// explícita de Marlon: "Personal sigue siendo el dueño de la
/// información del empleado"). Nunca duplica nombre/puesto/teléfono —
/// cada fila ya viene resuelta contra Empleado
/// (`ObtenerExpedienteServicioUseCase`).
class ServicioPersonalAsignadoSection extends StatelessWidget {
  const ServicioPersonalAsignadoSection({required this.personalVigente, required this.historialPersonal, super.key});

  final List<PersonalAsignadoServicio> personalVigente;

  /// Historial completo (vigente + cerrado) — se muestra debajo, sin
  /// repetir lo que ya aparece arriba como vigente.
  final List<PersonalAsignadoServicio> historialPersonal;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final historialCerrado = historialPersonal.where((p) => !p.vigente).toList();

    return RisegCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.servicioSeccionPersonalAsignado, style: AppTypography.heading3.copyWith(color: colors.textPrimary)),
          const SizedBox(height: AppSpacing.sm),
          if (personalVigente.isEmpty)
            Text(l10n.servicioPersonalAsignadoSinPersonal, style: AppTypography.body.copyWith(color: colors.textMuted))
          else
            RisegFieldGrid(
              children: [
                for (final p in personalVigente)
                  Text(
                    '${p.empleado.nombres} ${p.empleado.apellidoPaterno} — ${l10n.servicioPersonalAsignadoDesde(_formatoFecha.format(p.asignacion.fechaInicio))}'
                    '${p.asignacion.lineaComercialId == null ? ' · ${l10n.servicioPersonalAsignadoSinPerfil}' : ''}',
                  ),
              ],
            ),
          if (historialCerrado.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text(l10n.servicioSeccionHistorialPersonal, style: AppTypography.label),
            const SizedBox(height: AppSpacing.xs),
            RisegFieldGrid(
              children: [
                for (final p in historialCerrado)
                  Text(
                    '${p.empleado.nombres} ${p.empleado.apellidoPaterno} — '
                    '${_formatoFecha.format(p.asignacion.fechaInicio)} al ${_formatoFecha.format(p.asignacion.fechaTermino!)}',
                    style: AppTypography.body.copyWith(color: colors.textMuted),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
