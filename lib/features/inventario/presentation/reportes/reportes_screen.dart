import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/inventario/data/tables/asignacion_table.dart' show MotivoCierreAsignacion;
import 'package:riseg_one/features/inventario/domain/usecases/buscar_inventario_usecase.dart';

import '../articulos/articulos_list_screen.dart' show formatoCosto;
import '../asignaciones/widgets/cerrar_asignacion_dialog.dart' show motivoCierreLabel;
import '../asignaciones/widgets/historial_unidad_dialog.dart' show estatusAsignacionLabel, estatusAsignacionTono;
import '../movimiento_tipo_label.dart';
import 'reportes_controller.dart';
import 'reportes_state.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');

/// Reportes de Inventario (Etapa 7D) — cada sección es una consulta
/// derivada, nunca una tabla de resumen persistida (ver el doc comment
/// de `ReportesController`). Sin dashboards decorativos: tablas de
/// solo lectura + un buscador contextual, mismo criterio de densidad
/// que el resto del proyecto.
class ReportesScreen extends ConsumerStatefulWidget {
  const ReportesScreen({super.key});

  @override
  ConsumerState<ReportesScreen> createState() => _ReportesScreenState();
}

class _ReportesScreenState extends ConsumerState<ReportesScreen> {
  final _busquedaController = TextEditingController();

  @override
  void dispose() {
    _busquedaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(reportesControllerProvider);
    final notifier = ref.read(reportesControllerProvider.notifier);

    if (state.errorCarga != null && !state.cargando) {
      return RisegEmptyState(
        icon: Icons.error_outline,
        title: l10n.reportesCargaErrorTitulo,
        message: l10n.reportesCargaErrorMensaje,
        primaryAction: RisegButton(label: l10n.reportesBotonReintentar, onPressed: notifier.reintentarCarga),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RisegSearchField(
            hint: l10n.reportesBusquedaEtiqueta,
            controller: _busquedaController,
            onChanged: (valor) {
              if (valor.trim().isEmpty) {
                notifier.limpiarBusqueda();
              } else {
                notifier.buscar(valor);
              }
            },
          ),
          if (state.consultaBusqueda.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            _ResultadosBusqueda(l10n: l10n, resultado: state.resultadoBusqueda),
          ],
          const SizedBox(height: AppSpacing.xl),
          RisegCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.reportesSeccionExistencias, style: AppTypography.heading3),
                const SizedBox(height: AppSpacing.sm),
                RisegTableBase<ExistenciaResumen>(
                  loading: state.cargando,
                  rows: state.existencias,
                  onRowTap: (r) => context.go('/inventario/articulos/${r.articulo.id}'),
                  emptyState: RisegEmptyState(title: l10n.reportesExistenciasVacio, message: ''),
                  columns: [
                    RisegColumn<ExistenciaResumen>(
                      label: l10n.reportesColumnaArticulo,
                      cellBuilder: (r) => Text(r.articulo.nombre),
                    ),
                    RisegColumn<ExistenciaResumen>(
                      label: l10n.reportesColumnaCategoria,
                      cellBuilder: (r) => Text(r.categoriaNombre),
                    ),
                    RisegColumn<ExistenciaResumen>(
                      label: l10n.reportesColumnaTotal,
                      width: 80,
                      alignment: TextAlign.right,
                      cellBuilder: (r) => Text(r.existencia.total.toString()),
                    ),
                    RisegColumn<ExistenciaResumen>(
                      label: l10n.reportesColumnaDisponible,
                      width: 100,
                      alignment: TextAlign.right,
                      cellBuilder: (r) => Text(r.existencia.disponible.toString()),
                    ),
                    RisegColumn<ExistenciaResumen>(
                      label: l10n.reportesColumnaAsignado,
                      width: 100,
                      alignment: TextAlign.right,
                      cellBuilder: (r) => Text(r.existencia.asignado.toString()),
                    ),
                    RisegColumn<ExistenciaResumen>(
                      label: l10n.reportesColumnaDanadoPerdido,
                      width: 120,
                      alignment: TextAlign.right,
                      cellBuilder: (r) => Text((r.existencia.danado + r.existencia.perdido).toString()),
                    ),
                    RisegColumn<ExistenciaResumen>(
                      label: l10n.reportesColumnaCostoPromedio,
                      width: 130,
                      alignment: TextAlign.right,
                      cellBuilder: (r) => Text(r.costoPromedio == null ? '—' : formatoCosto(r.costoPromedio!)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          RisegCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.reportesSeccionAsignacionesVigentes, style: AppTypography.heading3),
                const SizedBox(height: AppSpacing.sm),
                RisegTableBase<AsignacionResumenReporte>(
                  loading: state.cargando,
                  rows: state.asignacionesVigentes,
                  onRowTap: (r) => _irADestino(context, r.asignacion),
                  emptyState: RisegEmptyState(title: l10n.reportesAsignacionesVigentesVacio, message: ''),
                  columns: [
                    RisegColumn<AsignacionResumenReporte>(
                      label: l10n.reportesColumnaArticulo,
                      cellBuilder: (r) => Text(r.articuloDetalle),
                    ),
                    RisegColumn<AsignacionResumenReporte>(
                      label: l10n.reportesColumnaDestino,
                      cellBuilder: (r) => Text(r.destino),
                    ),
                    RisegColumn<AsignacionResumenReporte>(
                      label: l10n.reportesColumnaFechaEntrega,
                      width: 110,
                      cellBuilder: (r) => Text(_formatoFecha.format(r.asignacion.fechaEntrega)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          RisegCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.reportesSeccionDanadosPerdidos, style: AppTypography.heading3),
                const SizedBox(height: AppSpacing.sm),
                RisegTableBase<AsignacionResumenReporte>(
                  loading: state.cargando,
                  rows: state.danadosPerdidos,
                  onRowTap: (r) => _irADestino(context, r.asignacion),
                  emptyState: RisegEmptyState(title: l10n.reportesDanadosPerdidosVacio, message: ''),
                  columns: [
                    RisegColumn<AsignacionResumenReporte>(
                      label: l10n.reportesColumnaArticulo,
                      cellBuilder: (r) => Text(r.articuloDetalle),
                    ),
                    RisegColumn<AsignacionResumenReporte>(
                      label: l10n.reportesColumnaDestino,
                      cellBuilder: (r) => Text(r.destino),
                    ),
                    RisegColumn<AsignacionResumenReporte>(
                      label: l10n.reportesColumnaFechaCierre,
                      width: 110,
                      cellBuilder: (r) => Text(
                        r.asignacion.fechaCierre == null ? '—' : _formatoFecha.format(r.asignacion.fechaCierre!),
                      ),
                    ),
                    RisegColumn<AsignacionResumenReporte>(
                      label: l10n.reportesColumnaEstatus,
                      width: 120,
                      cellBuilder: (r) => RisegStatusBadge(
                        label: estatusAsignacionLabel(l10n, r.asignacion.estatus),
                        tone: estatusAsignacionTono(r.asignacion.estatus),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          RisegCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.reportesSeccionDescuentosPendientes, style: AppTypography.heading3),
                const SizedBox(height: AppSpacing.sm),
                RisegTableBase<DescuentoResumenReporte>(
                  loading: state.cargando,
                  rows: state.descuentosPendientes,
                  onRowTap: (r) => context.go('/personal/empleados/${r.descuento.empleadoId}'),
                  emptyState: RisegEmptyState(title: l10n.reportesDescuentosPendientesVacio, message: ''),
                  columns: [
                    RisegColumn<DescuentoResumenReporte>(
                      label: l10n.reportesColumnaEmpleado,
                      cellBuilder: (r) => Text(r.empleadoNombre),
                    ),
                    RisegColumn<DescuentoResumenReporte>(
                      label: l10n.reportesColumnaArticulo,
                      cellBuilder: (r) => Text(r.articuloDetalle),
                    ),
                    RisegColumn<DescuentoResumenReporte>(
                      label: l10n.reportesColumnaMotivo,
                      width: 130,
                      cellBuilder: (r) => Text(motivoCierreLabel(l10n, MotivoCierreAsignacion.values.byName(r.descuento.motivo))),
                    ),
                    RisegColumn<DescuentoResumenReporte>(
                      label: l10n.reportesColumnaImporte,
                      width: 110,
                      alignment: TextAlign.right,
                      cellBuilder: (r) => Text(formatoCosto(r.descuento.importe)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          RisegCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.reportesSeccionMovimientos, style: AppTypography.heading3),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  l10n.reportesMovimientosNota,
                  style: AppTypography.body.copyWith(color: context.colors.textMuted),
                ),
                const SizedBox(height: AppSpacing.sm),
                RisegTableBase<MovimientoResumenReporte>(
                  loading: state.cargando,
                  rows: state.movimientosRecientes,
                  onRowTap: (r) => context.go('/inventario/articulos/${r.movimiento.articuloId}'),
                  emptyState: RisegEmptyState(title: l10n.reportesMovimientosVacio, message: ''),
                  columns: [
                    RisegColumn<MovimientoResumenReporte>(
                      label: l10n.reportesColumnaFecha,
                      width: 100,
                      cellBuilder: (r) => Text(_formatoFecha.format(r.movimiento.fecha)),
                    ),
                    RisegColumn<MovimientoResumenReporte>(
                      label: l10n.reportesColumnaTipoMovimiento,
                      width: 140,
                      cellBuilder: (r) => Text(movimientoTipoLabel(l10n, r.movimiento.tipoMovimiento)),
                    ),
                    RisegColumn<MovimientoResumenReporte>(
                      label: l10n.reportesColumnaArticulo,
                      cellBuilder: (r) => Text(r.articuloNombre),
                    ),
                    RisegColumn<MovimientoResumenReporte>(
                      label: l10n.reportesColumnaCantidad,
                      width: 90,
                      alignment: TextAlign.right,
                      cellBuilder: (r) => Text(r.movimiento.cantidad.toString()),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _irADestino(BuildContext context, AsignacionData asignacion) {
    if (asignacion.empleadoId != null) {
      context.go('/personal/empleados/${asignacion.empleadoId}');
    } else if (asignacion.servicioId != null) {
      context.go('/comercial/servicios/${asignacion.servicioId}');
    }
  }
}

/// Panel de resultados agrupados por tipo — cada grupo se omite si
/// está vacío; toda la búsqueda se omite (ver `ReportesScreen`) cuando
/// no hay texto capturado.
class _ResultadosBusqueda extends StatelessWidget {
  const _ResultadosBusqueda({required this.l10n, required this.resultado});

  final AppLocalizations l10n;
  final ResultadoBusquedaInventario resultado;

  @override
  Widget build(BuildContext context) {
    if (resultado.vacio) {
      return RisegCard(
        variant: RisegCardVariant.subtle,
        child: Text(l10n.reportesBusquedaVacia, style: AppTypography.body.copyWith(color: context.colors.textMuted)),
      );
    }

    return RisegCard(
      variant: RisegCardVariant.subtle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (resultado.articulos.isNotEmpty)
            _grupo(
              context,
              titulo: l10n.reportesBusquedaGrupoArticulos,
              filas: [
                for (final a in resultado.articulos)
                  _fila(context, texto: '${a.folio} · ${a.nombre}', onTap: () => context.go('/inventario/articulos/${a.id}')),
              ],
            ),
          if (resultado.unidades.isNotEmpty)
            _grupo(
              context,
              titulo: l10n.reportesBusquedaGrupoUnidades,
              filas: [
                for (final u in resultado.unidades)
                  _fila(
                    context,
                    texto: '${u.codigo} · ${u.numeroSerie} · ${u.articuloNombre}',
                    onTap: () => context.go('/inventario/articulos/${u.articuloId}'),
                  ),
              ],
            ),
          if (resultado.empleados.isNotEmpty)
            _grupo(
              context,
              titulo: l10n.reportesBusquedaGrupoEmpleados,
              filas: [
                for (final e in resultado.empleados)
                  _fila(
                    context,
                    texto: '#${e.numeroEmpleado} · ${e.nombreCompleto}',
                    onTap: () => context.go('/personal/empleados/${e.id}'),
                  ),
              ],
            ),
          if (resultado.servicios.isNotEmpty)
            _grupo(
              context,
              titulo: l10n.reportesBusquedaGrupoServicios,
              filas: [
                for (final s in resultado.servicios)
                  _fila(context, texto: '${s.codigo} · ${s.nombre}', onTap: () => context.go('/comercial/servicios/${s.id}')),
              ],
            ),
        ],
      ),
    );
  }

  Widget _grupo(BuildContext context, {required String titulo, required List<Widget> filas}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: AppTypography.label.copyWith(color: context.colors.textMuted)),
          const SizedBox(height: AppSpacing.xxs),
          ...filas,
        ],
      ),
    );
  }

  Widget _fila(BuildContext context, {required String texto, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
        child: Text(texto, style: AppTypography.body),
      ),
    );
  }
}
