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

/// Todos los valores reales de `TipoMovimientoInventario` (ver el doc
/// comment de `movimientoTipoLabel`) — usados para construir el
/// filtro de Historial sin inventar ningún valor nuevo.
const _tiposMovimiento = [
  'entrada',
  'baja',
  'ajusteEntrada',
  'ajusteSalida',
  'salidaAsignacion',
  'entradaDevolucion',
  'salidaDano',
  'salidaPerdida',
];

/// Reportes de Inventario (Etapa 7D, evolución visual Etapa 18) — cada
/// sección es una consulta derivada, nunca una tabla de resumen
/// persistida (ver el doc comment de `ReportesController`). Sin
/// dashboards decorativos: resumen de KPIs sobre los mismos datos ya
/// cargados + tablas de solo lectura + un buscador contextual.
class ReportesScreen extends ConsumerStatefulWidget {
  const ReportesScreen({super.key});

  @override
  ConsumerState<ReportesScreen> createState() => _ReportesScreenState();
}

class _ReportesScreenState extends ConsumerState<ReportesScreen> {
  final _busquedaController = TextEditingController();
  final _existenciasBuscarController = TextEditingController();
  String _filtroExistencias = '';

  @override
  void dispose() {
    _busquedaController.dispose();
    _existenciasBuscarController.dispose();
    super.dispose();
  }

  List<ExistenciaResumen> _existenciasVisibles(ReportesState state) {
    if (_filtroExistencias.trim().isEmpty) return state.existencias;
    final consulta = _filtroExistencias.trim().toLowerCase();
    return state.existencias
        .where(
          (r) => r.articulo.nombre.toLowerCase().contains(consulta) || r.articulo.folio.toLowerCase().contains(consulta),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(reportesControllerProvider);
    final notifier = ref.read(reportesControllerProvider.notifier);
    final colors = context.colors;

    if (state.errorCarga != null && !state.cargando) {
      return RisegEmptyState(
        icon: Icons.error_outline,
        title: l10n.reportesCargaErrorTitulo,
        message: l10n.reportesCargaErrorMensaje,
        primaryAction: RisegButton(label: l10n.reportesBotonReintentar, onPressed: notifier.reintentarCarga),
      );
    }

    // Opciones del filtro de Artículo en Historial — sobre los mismos
    // Artículos ya resueltos en Existencias, nunca una consulta nueva.
    final articulosOrdenados = [...state.existencias]..sort((a, b) => a.articulo.nombre.compareTo(b.articulo.nombre));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RisegSectionHeader(title: l10n.reportesTitulo, description: l10n.reportesSubtitulo),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              SizedBox(
                width: 190,
                child: RisegStatCard(
                  dense: true,
                  label: l10n.reportesResumenDisponible,
                  value: '${state.resumenDisponible}',
                ),
              ),
              SizedBox(
                width: 190,
                child: RisegStatCard(dense: true, label: l10n.reportesResumenAsignado, value: '${state.resumenAsignado}'),
              ),
              SizedBox(
                width: 190,
                child: RisegStatCard(
                  dense: true,
                  label: l10n.reportesResumenEnProceso,
                  value: '${state.resumenEnProceso}',
                  deltaTone: state.resumenEnProceso > 0 ? RisegStatusTone.warning : null,
                ),
              ),
              SizedBox(
                width: 190,
                child: RisegStatCard(
                  dense: true,
                  label: l10n.reportesResumenDanadoPerdido,
                  value: '${state.resumenDanadoPerdido}',
                  deltaTone: state.resumenDanadoPerdido > 0 ? RisegStatusTone.warning : RisegStatusTone.success,
                ),
              ),
              SizedBox(
                width: 190,
                child: RisegStatCard(
                  dense: true,
                  label: l10n.reportesResumenAsignacionesVigentes,
                  value: '${state.resumenAsignacionesVigentes}',
                ),
              ),
              // Valor del inventario: solo cuando TODO artículo con
              // existencia real y sin variante tiene costo conocido —
              // ver el doc comment de `ReportesState.resumenValorInventario`.
              // Si falta cobertura, se omite en lugar de mostrar un
              // total engañoso; el costo promedio por artículo sigue
              // visible en la tabla de Existencias.
              if (state.resumenValorInventario != null)
                SizedBox(
                  width: 190,
                  child: RisegStatCard(
                    dense: true,
                    label: l10n.reportesResumenValorInventario,
                    value: formatoCosto(state.resumenValorInventario!),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
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
                SizedBox(
                  width: 260,
                  child: RisegSearchField(
                    hint: l10n.reportesExistenciasBuscar,
                    controller: _existenciasBuscarController,
                    onChanged: (valor) => setState(() => _filtroExistencias = valor),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                RisegTableBase<ExistenciaResumen>(
                  loading: state.cargando,
                  rows: _existenciasVisibles(state),
                  onRowTap: (r) => context.push('/inventario/articulos/${r.articulo.id}'),
                  emptyState: RisegEmptyState(title: l10n.reportesExistenciasVacio, message: ''),
                  columns: [
                    // Etapa 18: misma identidad fusionada Nombre+Folio
                    // usada en el listado de Artículos.
                    RisegColumn<ExistenciaResumen>(
                      label: l10n.reportesColumnaArticulo,
                      cellBuilder: (r) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(r.articulo.nombre, style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary)),
                          const SizedBox(height: 2),
                          Text(r.articulo.folio, style: AppTypography.caption.copyWith(color: colors.textMuted)),
                        ],
                      ),
                    ),
                    RisegColumn<ExistenciaResumen>(
                      label: l10n.reportesColumnaCategoria,
                      width: 150,
                      cellBuilder: (r) => Text(r.categoriaNombre),
                    ),
                    RisegColumn<ExistenciaResumen>(
                      label: l10n.reportesColumnaTotal,
                      width: 80,
                      alignment: TextAlign.right,
                      cellBuilder: (r) => Text(r.existencia.total.toString(), style: AppTypography.body.copyWith(color: colors.textMuted)),
                    ),
                    RisegColumn<ExistenciaResumen>(
                      label: l10n.reportesColumnaDisponible,
                      width: 100,
                      alignment: TextAlign.right,
                      cellBuilder: (r) {
                        final sinDisponibilidad = r.existencia.disponible == 0 && r.existencia.total > 0;
                        return Text(
                          r.existencia.disponible.toString(),
                          style: AppTypography.bodyStrong.copyWith(color: sinDisponibilidad ? colors.warning : colors.textPrimary),
                        );
                      },
                    ),
                    RisegColumn<ExistenciaResumen>(
                      label: l10n.reportesColumnaAsignado,
                      width: 100,
                      alignment: TextAlign.right,
                      cellBuilder: (r) => Text(r.existencia.asignado.toString()),
                    ),
                    RisegColumn<ExistenciaResumen>(
                      label: l10n.reportesColumnaEnProceso,
                      width: 110,
                      alignment: TextAlign.right,
                      cellBuilder: (r) => Text(r.existencia.enProceso.toString()),
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
                      cellBuilder: (r) => Text(
                        r.costoPromedio == null ? '—' : formatoCosto(r.costoPromedio!),
                        style: r.costoPromedio == null ? AppTypography.body.copyWith(color: colors.textMuted) : null,
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
                    // Etapa 18: Destino gana jerarquía — es la pregunta
                    // operativa real de esta sección ("¿quién lo tiene?").
                    RisegColumn<AsignacionResumenReporte>(
                      label: l10n.reportesColumnaDestino,
                      cellBuilder: (r) => Text(r.destino, style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary)),
                    ),
                    RisegColumn<AsignacionResumenReporte>(
                      label: l10n.reportesColumnaCantidad,
                      width: 90,
                      alignment: TextAlign.right,
                      cellBuilder: (r) => Text(r.asignacion.cantidad.toString()),
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
                  onRowTap: (r) => context.push('/personal/empleados/${r.descuento.empleadoId}'),
                  emptyState: RisegEmptyState(
                    title: l10n.reportesDescuentosPendientesVacioTitulo,
                    message: l10n.reportesDescuentosPendientesVacioMensaje,
                  ),
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
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 190,
                      child: RisegSelect<String?>(
                        label: l10n.reportesFiltroTipoMovimiento,
                        value: state.movimientoTipoFiltro,
                        items: [
                          RisegSelectItem(value: null, label: l10n.reportesFiltroTipoMovimientoTodos),
                          for (final tipo in _tiposMovimiento)
                            RisegSelectItem(value: tipo, label: movimientoTipoLabel(l10n, tipo)),
                        ],
                        onChanged: (valor) => notifier.filtrarMovimientos(tipo: valor, limpiarTipo: valor == null),
                      ),
                    ),
                    SizedBox(
                      width: 220,
                      child: RisegSelect<String?>(
                        label: l10n.reportesFiltroArticulo,
                        value: state.movimientoArticuloFiltro,
                        items: [
                          RisegSelectItem(value: null, label: l10n.reportesFiltroArticuloTodos),
                          for (final r in articulosOrdenados) RisegSelectItem(value: r.articulo.id, label: r.articulo.nombre),
                        ],
                        onChanged: (valor) => notifier.filtrarMovimientos(articuloId: valor, limpiarArticulo: valor == null),
                      ),
                    ),
                    RisegButton(
                      label: l10n.reportesLimpiarFiltros,
                      variant: RisegButtonVariant.ghost,
                      onPressed: state.hayFiltrosMovimientosActivos ? notifier.limpiarFiltrosMovimientos : null,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                RisegTableBase<MovimientoResumenReporte>(
                  loading: state.cargando,
                  rows: state.movimientosVisibles,
                  onRowTap: (r) => context.push('/inventario/articulos/${r.movimiento.articuloId}'),
                  emptyState: RisegEmptyState(
                    title: state.hayFiltrosMovimientosActivos ? l10n.reportesMovimientosVacioFiltrado : l10n.reportesMovimientosVacio,
                    message: '',
                  ),
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
                      cellBuilder: (r) => Text(r.articuloDetalle),
                    ),
                    RisegColumn<MovimientoResumenReporte>(
                      label: l10n.reportesColumnaCantidad,
                      width: 90,
                      alignment: TextAlign.right,
                      cellBuilder: (r) => Text(r.movimiento.cantidad.toString()),
                    ),
                    RisegColumn<MovimientoResumenReporte>(
                      label: l10n.reportesColumnaCosto,
                      width: 110,
                      alignment: TextAlign.right,
                      cellBuilder: (r) => Text(
                        r.movimiento.costoUnitario == null ? '—' : formatoCosto(r.movimiento.costoUnitario!),
                        style: r.movimiento.costoUnitario == null ? AppTypography.body.copyWith(color: colors.textMuted) : null,
                      ),
                    ),
                    RisegColumn<MovimientoResumenReporte>(
                      label: l10n.reportesColumnaUsuario,
                      width: 140,
                      cellBuilder: (r) => Text(r.actorNombre ?? '—'),
                    ),
                    RisegColumn<MovimientoResumenReporte>(
                      label: l10n.reportesColumnaObservaciones,
                      width: 200,
                      cellBuilder: (r) => Text(
                        (r.movimiento.observaciones ?? '').trim().isEmpty ? '—' : r.movimiento.observaciones!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.body.copyWith(color: colors.textMuted),
                      ),
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
      context.push('/personal/empleados/${asignacion.empleadoId}');
    } else if (asignacion.servicioId != null) {
      context.push('/comercial/servicios/${asignacion.servicioId}');
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
                  _fila(context, texto: '${a.folio} · ${a.nombre}', onTap: () => context.push('/inventario/articulos/${a.id}')),
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
                    onTap: () => context.push('/inventario/articulos/${u.articuloId}'),
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
                    onTap: () => context.push('/personal/empleados/${e.id}'),
                  ),
              ],
            ),
          if (resultado.servicios.isNotEmpty)
            _grupo(
              context,
              titulo: l10n.reportesBusquedaGrupoServicios,
              filas: [
                for (final s in resultado.servicios)
                  _fila(context, texto: '${s.codigo} · ${s.nombre}', onTap: () => context.push('/comercial/servicios/${s.id}')),
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
