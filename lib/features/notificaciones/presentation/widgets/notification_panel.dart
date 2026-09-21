import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/design_system/design_system.dart';

import '../../domain/usecases/resultado_notificacion.dart';
import '../notificaciones_controller.dart';

const _maximoFilasPorGrupo = 5;

/// Panel de notificaciones agrupadas (Etapa 14B) — mismo lenguaje
/// visual que `GlobalSearchResultsList` (Búsqueda global, 14A) por
/// consistencia: un solo patrón de overlay en todo el proyecto. Un
/// grupo se omite por completo si llegó en `null` (sin autorización)
/// o vacío (autorizado, nada pendiente) — nunca un encabezado sin
/// filas.
class NotificationPanel extends ConsumerWidget {
  const NotificationPanel({required this.onSelect, super.key});

  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(notificacionesControllerProvider);

    if (state.cargando && state.resultados == null) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.md),
        child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }

    final resultados = state.resultados;
    if (resultados == null || resultados.total == 0) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Text(l10n.notificacionesSinPendientes),
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 420),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _grupo(l10n.notificacionesGrupoVerificacion, Icons.fact_check_outlined, resultados.verificacionVehiculos),
            _grupo(l10n.notificacionesGrupoTenenciaRefrendo, Icons.receipt_long_outlined, resultados.tenenciaRefrendoVehiculos),
            _grupo(l10n.notificacionesGrupoDocumentosPorEmitir, Icons.description_outlined, resultados.documentosPorEmitir),
            _grupo(l10n.notificacionesGrupoCxcProxima, Icons.schedule_outlined, resultados.cxcProximasAVencer),
            _grupo(l10n.notificacionesGrupoCxcVencida, Icons.error_outline, resultados.cxcVencidas),
            _grupo(l10n.notificacionesGrupoPagosRecientes, Icons.payments_outlined, resultados.pagosRecientes),
            // Séptima categoría — obligación fiscal derivada de un Pago
            // real, nunca de una fecha del calendario comercial.
            _grupo(
              l10n.notificacionesComplementosPendientesTitulo,
              Icons.request_page_outlined,
              resultados.complementosPendientes,
            ),
          ],
        ),
      ),
    );
  }

  Widget _grupo(String titulo, IconData icono, List<ResultadoNotificacion>? items) {
    if (items == null || items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xxs),
          child: Text(titulo.toUpperCase(), style: AppTypography.label),
        ),
        for (final item in items.take(_maximoFilasPorGrupo))
          InkWell(
            onTap: () => onSelect(item.ruta),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
              child: Row(
                children: [
                  Icon(icono, size: 18, color: item.urgente ? Colors.red : Colors.orange),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.titulo, overflow: TextOverflow.ellipsis),
                        Text(item.subtitulo, style: AppTypography.caption, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
