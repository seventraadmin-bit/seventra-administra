import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/core/permissions/modulos_permiso.dart';

import '../../domain/usecases/buscar_auditoria_usecase.dart';
import '../widgets/permiso_labels.dart';
import 'auditoria_controller.dart';

final _formatoFechaHora = DateFormat('dd/MM/yyyy HH:mm');

/// Pantalla central de Auditoría (Etapa 11D) — dentro de Configuración,
/// junto a Usuarios. Fecha/hora | Usuario | Módulo | Acción | Registro |
/// Motivo, con filtros por usuario/módulo/acción/rango de fechas y
/// detalle bajo demanda (nunca JSON crudo en la tabla principal).
class AuditoriaScreen extends ConsumerWidget {
  const AuditoriaScreen({super.key});

  String _accionLabel(String accion) {
    // Las eliminaciones físicas codifican el tipo de entidad en la
    // propia acción (`'eliminacionFisica:vehiculo'`) — se separa aquí
    // para una etiqueta legible sin depender de un catálogo por módulo
    // (los valores de `accion` son heterogéneos entre dominios: tipos
    // de evento, tipos de movimiento, orígenes de kilometraje, etc.).
    if (accion.startsWith('eliminacionFisica:')) {
      return 'Eliminación física — ${accion.substring('eliminacionFisica:'.length)}';
    }
    return accion;
  }

  void _verDetalle(BuildContext context, AppLocalizations l10n, EventoAuditoria evento, String? nombreUsuario) {
    Map<String, dynamic>? detalle;
    if (evento.detalleJson != null) {
      try {
        detalle = jsonDecode(evento.detalleJson!) as Map<String, dynamic>;
      } catch (_) {
        detalle = null;
      }
    }

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.auditoriaDetalleDialogoTitulo),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${l10n.auditoriaColumnaFecha}: ${_formatoFechaHora.format(evento.fechaHora)}'),
                const SizedBox(height: AppSpacing.xs),
                Text('${l10n.auditoriaColumnaUsuario}: ${nombreUsuario ?? l10n.usuarioHistorialConfiguracionInicial}'),
                const SizedBox(height: AppSpacing.xs),
                Text('${l10n.auditoriaColumnaModulo}: ${moduloPermisoLabel(l10n, evento.modulo)}'),
                const SizedBox(height: AppSpacing.xs),
                Text('${l10n.auditoriaColumnaAccion}: ${_accionLabel(evento.accion)}'),
                const SizedBox(height: AppSpacing.xs),
                Text('${l10n.auditoriaColumnaRegistro}: ${evento.registroId}'),
                if (evento.motivo != null && evento.motivo!.trim().isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text('${l10n.auditoriaColumnaMotivo}: ${evento.motivo}'),
                ],
                if (detalle != null && detalle.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(l10n.auditoriaDetalleSeccionAdicional, style: AppTypography.label),
                  const SizedBox(height: AppSpacing.xs),
                  for (final entry in detalle.entries)
                    if (entry.value != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
                        child: Text('${entry.key}: ${entry.value}', style: AppTypography.caption),
                      ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: Text(l10n.vehiculoDocumentoHistorialBotonCerrar)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(auditoriaControllerProvider);
    final notifier = ref.read(auditoriaControllerProvider.notifier);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RisegSectionHeader(title: l10n.auditoriaTitulo),
          const SizedBox(height: AppSpacing.md),
          RisegCard(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: [
                  SizedBox(
                    width: 220,
                    child: RisegSelect<String?>(
                      label: l10n.auditoriaFiltroUsuario,
                      value: state.actorUsuarioId,
                      items: [
                        for (final u in state.usuarios) RisegSelectItem(value: u.id, label: u.nombre),
                      ],
                      onChanged: (valor) => notifier.aplicarFiltros(
                        actorUsuarioId: valor,
                        limpiarActorUsuarioId: valor == null,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 200,
                    child: RisegSelect<String?>(
                      label: l10n.auditoriaFiltroModulo,
                      value: state.modulo,
                      items: [
                        for (final m in modulosPermiso) RisegSelectItem(value: m.codigo, label: moduloPermisoLabel(l10n, m.codigo)),
                      ],
                      onChanged: (valor) => notifier.aplicarFiltros(modulo: valor, limpiarModulo: valor == null),
                    ),
                  ),
                  SizedBox(
                    width: 220,
                    child: RisegSelect<String?>(
                      label: l10n.auditoriaFiltroAccion,
                      value: state.accion,
                      items: [
                        for (final a in state.accionesDisponibles) RisegSelectItem(value: a, label: _accionLabel(a)),
                      ],
                      onChanged: (valor) => notifier.aplicarFiltros(accion: valor, limpiarAccion: valor == null),
                    ),
                  ),
                  SizedBox(
                    width: 160,
                    child: RisegDateField(
                      label: l10n.auditoriaFiltroDesde,
                      value: state.desde,
                      onChanged: (valor) => notifier.aplicarFiltros(desde: valor),
                    ),
                  ),
                  SizedBox(
                    width: 160,
                    child: RisegDateField(
                      label: l10n.auditoriaFiltroHasta,
                      value: state.hasta,
                      onChanged: (valor) => notifier.aplicarFiltros(hasta: valor),
                    ),
                  ),
                  RisegButton(
                    label: l10n.auditoriaFiltroLimpiar,
                    variant: RisegButtonVariant.ghost,
                    onPressed: notifier.limpiarFiltros,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: RisegTableBase<EventoAuditoria>(
              loading: state.cargando,
              rows: state.eventos,
              emptyState: RisegEmptyState(title: l10n.auditoriaVacioTitulo, message: ''),
              onRowTap: (evento) => _verDetalle(context, l10n, evento, state.nombreUsuario(evento.actorUsuarioId)),
              columns: [
                RisegColumn<EventoAuditoria>(
                  label: l10n.auditoriaColumnaFecha,
                  width: 150,
                  cellBuilder: (e) => Text(_formatoFechaHora.format(e.fechaHora)),
                ),
                RisegColumn<EventoAuditoria>(
                  label: l10n.auditoriaColumnaUsuario,
                  cellBuilder: (e) => Text(state.nombreUsuario(e.actorUsuarioId) ?? l10n.usuarioHistorialConfiguracionInicial),
                ),
                RisegColumn<EventoAuditoria>(
                  label: l10n.auditoriaColumnaModulo,
                  width: 140,
                  cellBuilder: (e) => Text(moduloPermisoLabel(l10n, e.modulo)),
                ),
                RisegColumn<EventoAuditoria>(
                  label: l10n.auditoriaColumnaAccion,
                  cellBuilder: (e) => Text(_accionLabel(e.accion), overflow: TextOverflow.ellipsis),
                ),
                RisegColumn<EventoAuditoria>(
                  label: l10n.auditoriaColumnaMotivo,
                  cellBuilder: (e) => Text(e.motivo ?? '—', overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
