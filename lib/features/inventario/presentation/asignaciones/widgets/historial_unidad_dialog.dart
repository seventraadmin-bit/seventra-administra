import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/inventario/inventario_providers.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');

String estatusAsignacionLabel(AppLocalizations l10n, String estatus) {
  return switch (estatus) {
    'activa' => l10n.estatusAsignacionActiva,
    'devuelta' => l10n.estatusAsignacionDevuelta,
    'danada' => l10n.estatusAsignacionDanada,
    'perdida' => l10n.estatusAsignacionPerdida,
    _ => estatus,
  };
}

RisegStatusTone estatusAsignacionTono(String estatus) {
  return switch (estatus) {
    'activa' => RisegStatusTone.info,
    'devuelta' => RisegStatusTone.success,
    'danada' => RisegStatusTone.warning,
    'perdida' => RisegStatusTone.error,
    _ => RisegStatusTone.neutral,
  };
}

/// Historial de una unidad serializada (Etapa 7B) — "quién la tiene"
/// (la activa, si existe) y "dónde estuvo antes", consultado desde el
/// expediente del Artículo. Solo lectura.
Future<void> mostrarDialogoHistorialUnidad(BuildContext context, WidgetRef ref, ArticuloUnidadData unidad) async {
  final l10n = AppLocalizations.of(context)!;
  final asignaciones = await ref.read(asignacionRepositoryProvider).listarPorUnidad(unidad.id);
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('${l10n.asignacionSeccionHistorial} — ${unidad.codigo}'),
      content: SizedBox(
        width: 420,
        child: asignaciones.isEmpty
            ? Text(l10n.asignacionHistorialVacio)
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final a in asignaciones)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${a.empleadoId ?? a.servicioId ?? '—'} · ${_formatoFecha.format(a.fechaEntrega)}'
                              '${a.fechaCierre == null ? '' : ' – ${_formatoFecha.format(a.fechaCierre!)}'}',
                            ),
                          ),
                          RisegStatusBadge(label: estatusAsignacionLabel(l10n, a.estatus), tone: estatusAsignacionTono(a.estatus)),
                        ],
                      ),
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: Text(l10n.cerrarAsignacionBotonCancelar)),
      ],
    ),
  );
}
