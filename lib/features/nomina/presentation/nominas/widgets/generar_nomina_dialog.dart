import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/presentation/pagos/pagos_list_screen.dart' show formatoCentavosPago;
import 'package:riseg_one/features/inventario/data/tables/asignacion_table.dart' show MotivoCierreAsignacion;
import 'package:riseg_one/features/inventario/inventario_providers.dart';
import 'package:riseg_one/features/inventario/presentation/asignaciones/widgets/cerrar_asignacion_dialog.dart' show motivoCierreLabel;
import 'package:riseg_one/features/nomina/data/tables/nomina_table.dart';
import 'package:riseg_one/features/nomina/domain/usecases/generar_nomina_usecase.dart';
import 'package:riseg_one/features/personal/personal_providers.dart';

import '../nominas_controller.dart';

String nominaTipoPeriodoLabel(AppLocalizations l10n, TipoPeriodoNomina tipo) {
  return switch (tipo) {
    TipoPeriodoNomina.primera => l10n.nominaTipoPeriodoPrimera,
    TipoPeriodoNomina.segunda => l10n.nominaTipoPeriodoSegunda,
  };
}

/// Diálogo "Generar nómina" (Etapa 6C) — pide año/mes/periodo y dispara
/// `GenerarNominaUseCase`. Nunca automático: siempre una acción
/// explícita del usuario (Resolución explícita de Marlon).
///
/// Etapa 15 (integración real con Nómina): antes de confirmar, muestra
/// los `DescuentoInventario` todavía `pendiente` que la generación
/// aplicará — nunca una sorpresa después. La lista no depende de
/// año/mes/tipo (un descuento pendiente aplica a la siguiente Nómina
/// que incluya a ese Empleado, sin importar el periodo elegido aquí).
///
/// Devuelve `true` si la generación tuvo éxito.
Future<bool> mostrarDialogoGenerarNomina(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context)!;
  final hoy = DateTime.now();
  int anio = hoy.year;
  int mes = hoy.month;
  TipoPeriodoNomina tipo = TipoPeriodoNomina.primera;

  final asignacionRepo = ref.read(asignacionRepositoryProvider);
  final empleadoRepo = ref.read(empleadoRepositoryProvider);
  final descuentosPendientes = await asignacionRepo.listarTodosDescuentosPendientes();
  final nombresPorEmpleado = <String, String>{};
  for (final d in descuentosPendientes) {
    if (nombresPorEmpleado.containsKey(d.empleadoId)) continue;
    final empleado = await empleadoRepo.obtenerPorId(d.empleadoId);
    if (empleado != null) {
      nombresPorEmpleado[d.empleadoId] = '${empleado.nombres} ${empleado.apellidoPaterno}';
    }
  }
  if (!context.mounted) return false;
  final totalDescuentosPendientes = descuentosPendientes.fold<int>(0, (s, d) => s + d.importe);

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.generarNominaDialogoTitulo,
    confirmLabel: l10n.generarNominaBotonConfirmar,
    cancelLabel: l10n.generarNominaBotonCancelar,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        return SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RisegSelect<int>(
                label: l10n.generarNominaCampoAnio,
                value: anio,
                items: [
                  for (var a = hoy.year - 1; a <= hoy.year + 1; a++) RisegSelectItem(value: a, label: a.toString()),
                ],
                onChanged: (valor) => setState(() => anio = valor ?? anio),
              ),
              const SizedBox(height: AppSpacing.md),
              RisegSelect<int>(
                label: l10n.generarNominaCampoMes,
                value: mes,
                items: [for (var m = 1; m <= 12; m++) RisegSelectItem(value: m, label: m.toString().padLeft(2, '0'))],
                onChanged: (valor) => setState(() => mes = valor ?? mes),
              ),
              const SizedBox(height: AppSpacing.md),
              RisegSelect<TipoPeriodoNomina>(
                label: l10n.generarNominaCampoTipoPeriodo,
                value: tipo,
                items: [
                  for (final t in TipoPeriodoNomina.values) RisegSelectItem(value: t, label: nominaTipoPeriodoLabel(l10n, t)),
                ],
                onChanged: (valor) => setState(() => tipo = valor ?? tipo),
              ),
              if (descuentosPendientes.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                Text(l10n.generarNominaDescuentosPendientesTitulo, style: AppTypography.label),
                const SizedBox(height: AppSpacing.xs),
                for (final d in descuentosPendientes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
                    child: Text(
                      '${nombresPorEmpleado[d.empleadoId] ?? '—'} — '
                      '${motivoCierreLabel(l10n, MotivoCierreAsignacion.values.byName(d.motivo))} — '
                      '${formatoCentavosPago(d.importe)}',
                      style: AppTypography.caption,
                    ),
                  ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  l10n.generarNominaDescuentosPendientesTotal(formatoCentavosPago(totalDescuentosPendientes)),
                  style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ],
          ),
        );
      },
    ),
    onConfirm: () async {
      final resultado = await ref.read(nominasControllerProvider.notifier).generar(anio: anio, mes: mes, tipo: tipo);
      if (!context.mounted) return false;

      switch (resultado) {
        case GenerarNominaExitoso(empleadosExcluidos: final excluidos):
          RisegFeedback.showSuccess(context, excluidos.isEmpty ? l10n.generarNominaExito : l10n.generarNominaExitoConExcluidos);
          return true;
        case GenerarNominaYaExiste():
          RisegFeedback.showError(context, l10n.generarNominaYaExiste);
          return false;
        case GenerarNominaSinEmpleados():
          RisegFeedback.showError(context, l10n.generarNominaSinEmpleados);
          return false;
        case GenerarNominaErrorInesperado():
          RisegFeedback.showError(context, l10n.generarNominaErrorInesperado);
          return false;
      }
    },
  );

  return resultado ?? false;
}
