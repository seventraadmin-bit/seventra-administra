import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:go_router/go_router.dart';

import 'package:riseg_one/app/shell/shell_permissions.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/core/permissions/modulos_permiso.dart';
import 'package:riseg_one/features/finanzas/presentation/deudas_credito/deudas_credito_list_screen.dart'
    show formatoCentavosDeuda;

import '../../domain/usecases/buscar_auditoria_usecase.dart';
import 'package:riseg_one/features/servicios_eventuales/presentation/widgets/servicio_eventual_labels.dart'
    show servicioEventualEventoLabel;
import '../../domain/usecases/destino_auditoria.dart';
import '../../usuarios_providers.dart' show permissionServiceProvider;
import '../sesion_controller.dart';
import '../widgets/permiso_labels.dart';
import 'auditoria_controller.dart';

final _formatoFechaHora = DateFormat('dd/MM/yyyy HH:mm');

/// Pantalla central de Auditoría (Etapa 11D) — dentro de Configuración,
/// junto a Usuarios. Fecha/hora | Usuario | Módulo | Acción | Registro |
/// Motivo, con filtros por usuario/módulo/acción/rango de fechas y
/// detalle bajo demanda (nunca JSON crudo en la tabla principal).
class AuditoriaScreen extends ConsumerWidget {
  const AuditoriaScreen({super.key});

  /// Etiqueta de módulo que también entiende los códigos que existen
  /// solo en Auditoría (`tiempoExtra`, `boveda`) y que por eso no están
  /// en `modulosPermiso` — ver `modulosSoloAuditoria`.
  String _moduloLabel(AppLocalizations l10n, String codigo) {
    return switch (codigo) {
      'tiempoExtra' => l10n.auditoriaModuloTiempoExtra,
      'boveda' => l10n.auditoriaModuloBoveda,
      _ => moduloPermisoLabel(l10n, codigo),
    };
  }

  /// ¿Puede este usuario ABRIR el origen? Se resuelve con el mismo
  /// mecanismo del router — nunca con `auditoria.ver`, que solo abre
  /// esta pantalla. Ver un evento y poder entrar a donde ocurrió son
  /// facultades distintas, y esta función es la que impide que la
  /// primera se convierta en atajo de la segunda.
  bool _puedeNavegar(WidgetRef ref, DestinoAuditoria destino) {
    if (destino.exigeMaestro) {
      return ref.read(sesionControllerProvider)?.esMaestro ?? false;
    }
    final permisos = permisosQueAbrenRuta(destino.ruta);
    if (permisos.isEmpty) return true;
    final servicio = ref.read(permissionServiceProvider);
    return permisos.any(servicio.hasCode);
  }

  /// Origen funcional de un cargo/ajuste de tarjeta, para que la acción
  /// diga de dónde vino el dinero sin confundirse con el evento de
  /// negocio del módulo que lo originó.
  String _origenCargoLabel(AppLocalizations l10n, String origen) {
    return switch (origen) {
      'compra' => l10n.moduleCompras,
      'tiempoExtra' => l10n.auditoriaModuloTiempoExtra,
      'tiempoExtraCosto' => l10n.auditoriaOrigenCargoTiempoExtraCosto,
      'egreso' => l10n.permisoModuloEgresos,
      'vehiculo' => l10n.moduleVehiculos,
      'positivo' => l10n.auditoriaAjusteTarjetaPositivo,
      'negativo' => l10n.auditoriaAjusteTarjetaNegativo,
      _ => origen,
    };
  }

  /// Un valor de cambio, formateado como moneda cuando la proyección lo
  /// marcó como importe en centavos (`CambioAuditoria.esImporte`).
  String _valorCambio(String? valor, bool esImporte) {
    if (valor == null) return '—';
    if (!esImporte) return valor;
    final centavos = int.tryParse(valor);
    return centavos == null ? valor : formatoCentavosDeuda(centavos);
  }

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

  /// Igual que [_accionLabel] pero con acceso a l10n — necesario para
  /// las acciones de Deudas, que codifican su origen funcional.
  /// [modulo] acota las traducciones que sólo valen dentro de un
  /// dominio: `corregido`, `creado` o `cancelado` son nombres que
  /// varios módulos comparten, y traducirlos sin saber de cuál vienen
  /// pondría la etiqueta de uno en los eventos de otro. `null` cuando
  /// no hay contexto (el filtro, que lista acciones de todos).
  String _accionLabelCompleta(AppLocalizations l10n, String accion, {String? modulo}) {
    if (modulo == 'serviciosEventuales') {
      final eventual = servicioEventualEventoLabel(l10n, accion);
      if (eventual != accion) return eventual;
    }
    if (accion.startsWith('cargoTarjeta:')) {
      final origen = accion.substring('cargoTarjeta:'.length);
      return l10n.auditoriaAccionCargoTarjetaPor(_origenCargoLabel(l10n, origen));
    }
    if (accion.startsWith('ajusteTarjeta:')) {
      final origen = accion.substring('ajusteTarjeta:'.length);
      return l10n.auditoriaAccionAjusteTarjetaPor(_origenCargoLabel(l10n, origen));
    }
    // Por qué se cerró una asignación de línea: baja de la línea o baja
    // del empleado son hechos distintos y deben leerse distinto.
    if (accion.startsWith('asignacionCerrada:')) {
      final motivo = accion.substring('asignacionCerrada:'.length);
      return l10n.auditoriaAccionAsignacionCerradaPor(
        switch (motivo) {
          'bajaLinea' => l10n.auditoriaMotivoCierreBajaLinea,
          'bajaEmpleado' => l10n.auditoriaMotivoCierreBajaEmpleado,
          'cambioResponsable' => l10n.auditoriaMotivoCierreCambioResponsable,
          'liberacion' => l10n.auditoriaMotivoCierreLiberacion,
          _ => motivo,
        },
      );
    }
    if (accion == 'correccionPago:positivo') return l10n.auditoriaAccionCorreccionPagoPositivo;
    if (accion == 'correccionPago:negativo') return l10n.auditoriaAccionCorreccionPagoNegativo;
    return _accionLabel(accion);
  }

  void _verDetalle(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    EventoAuditoria evento,
    String? nombreUsuario,
  ) {
    Map<String, dynamic>? detalle;
    if (evento.detalleJson != null) {
      try {
        detalle = jsonDecode(evento.detalleJson!) as Map<String, dynamic>;
      } catch (_) {
        detalle = null;
      }
    }

    final destino = destinoDeEvento(evento);

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
                Text('${l10n.auditoriaColumnaAccion}: ${_accionLabelCompleta(l10n, evento.accion, modulo: evento.modulo)}'),
                const SizedBox(height: AppSpacing.xs),
                Text('${l10n.auditoriaColumnaEntidad}: ${evento.entidadEtiqueta ?? evento.registroId}'),
                const SizedBox(height: AppSpacing.xs),
                Text('${l10n.auditoriaColumnaRegistro}: ${evento.registroId}'),
                // Importe: solo cuando el origen realmente mueve dinero.
                if (evento.importe != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text('${l10n.auditoriaDetalleImporte}: ${formatoCentavosDeuda(evento.importe!)}'),
                ],
                // Motivo: el bloque se OMITE cuando no hay uno. Nunca un
                // "Sin motivo" inventado — una creación o una revelación
                // de credencial simplemente no llevan motivo, y decir lo
                // contrario sería afirmar un dato que nadie capturó.
                if (evento.motivo != null && evento.motivo!.trim().isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text('${l10n.auditoriaColumnaMotivo}: ${evento.motivo}'),
                ],
                // Cambios: mismo estándar de presentación para los tres
                // formatos de origen (ver `CambioAuditoria`), sin
                // aplanar sus diferencias reales.
                if (evento.cambios.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(l10n.auditoriaDetalleSeccionCambios, style: AppTypography.label),
                  const SizedBox(height: AppSpacing.xs),
                  for (final cambio in evento.cambios)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
                      child: Text(
                        '${cambio.campo}: ${_valorCambio(cambio.antes, cambio.esImporte)} → '
                        '${_valorCambio(cambio.despues, cambio.esImporte)}',
                        style: AppTypography.caption,
                      ),
                    ),
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
          // "Ver origen" solo aparece si el usuario REALMENTE puede
          // entrar a esa ruta con sus propios permisos de módulo.
          if (destino != null && _puedeNavegar(ref, destino))
            TextButton(
              key: const Key('auditoria_ver_origen'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                context.push(destino.ruta);
              },
              child: Text(l10n.auditoriaDetalleBotonVerOrigen),
            ),
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
                        // Unión del catálogo de permisos + los códigos
                        // que solo existen en Auditoría: así Tiempo
                        // Extra y Bóveda se pueden filtrar sin inventar
                        // permisos `tiempoExtra.ver`/`boveda.ver`.
                        for (final codigo in [...modulosPermiso.map((m) => m.codigo), ...modulosSoloAuditoria])
                          RisegSelectItem(value: codigo, label: _moduloLabel(l10n, codigo)),
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
                        for (final a in state.accionesDisponibles)
                          RisegSelectItem(value: a, label: _accionLabelCompleta(l10n, a)),
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
              onRowTap: (evento) => _verDetalle(context, ref, l10n, evento, state.nombreUsuario(evento.actorUsuarioId)),
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
                  cellBuilder: (e) => Text(_moduloLabel(l10n, e.modulo), overflow: TextOverflow.ellipsis),
                ),
                RisegColumn<EventoAuditoria>(
                  label: l10n.auditoriaColumnaAccion,
                  cellBuilder: (e) =>
                      Text(_accionLabelCompleta(l10n, e.accion, modulo: e.modulo), overflow: TextOverflow.ellipsis),
                ),
                // Entidad: el nombre legible de lo afectado (folio,
                // código, nombre de credencial). Cae al id crudo solo
                // cuando el origen no tiene etiqueta natural.
                RisegColumn<EventoAuditoria>(
                  label: l10n.auditoriaColumnaEntidad,
                  cellBuilder: (e) => Text(e.entidadEtiqueta ?? e.registroId, overflow: TextOverflow.ellipsis),
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
