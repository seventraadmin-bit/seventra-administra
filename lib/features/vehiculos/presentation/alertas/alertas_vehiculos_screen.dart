import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';

import '../../domain/usecases/agrupar_documentos_vehiculo.dart';
import '../../domain/usecases/calcular_estado_vigencia_documento.dart';
import '../../domain/usecases/calcular_proximo_mantenimiento.dart';
import '../../vehiculos_providers.dart';
import '../vehiculo_labels.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');

/// Una fila de la sección Documentos — el documento vigente de un tipo,
/// ya en estado `vencido`/`proximoAVencer`, con su Vehículo resuelto.
class _AlertaDocumento {
  const _AlertaDocumento({required this.vehiculo, required this.documento, required this.estado});
  final VehiculoData vehiculo;
  final VehiculoDocumentoData documento;
  final EstadoVigenciaDocumento estado;
}

/// Una fila de la sección Mantenimiento — el próximo mantenimiento
/// derivado de un Vehículo, ya en estado `proximo`/`vencido`.
class _AlertaMantenimiento {
  const _AlertaMantenimiento({required this.vehiculo, required this.proximo});
  final VehiculoData vehiculo;
  final ProximoMantenimientoVehiculo proximo;
}

/// Alertas operativas de Vehículos (Etapas 8C+8D) — derivado en vivo,
/// cero tablas de resumen, mismo criterio que `ReportesScreen`
/// (Inventario 7D). Combina documentos por vencer y mantenimiento
/// próximo/vencido (punto 10 de la Etapa 8D), más un resumen de
/// vehículos en mantenimiento/fuera de servicio. Vehículos dados de baja
/// quedan **excluidos** de todo — un vehículo que ya no opera no
/// necesita seguir generando ruido operativo (punto 10 de 8C, reafirmado
/// en el punto 15 de 8D).
class AlertasVehiculosScreen extends ConsumerStatefulWidget {
  const AlertasVehiculosScreen({super.key});

  @override
  ConsumerState<AlertasVehiculosScreen> createState() => _AlertasVehiculosScreenState();
}

class _AlertasVehiculosScreenState extends ConsumerState<AlertasVehiculosScreen> {
  bool _cargando = true;
  List<_AlertaDocumento> _alertasDocumentos = const [];
  List<_AlertaMantenimiento> _alertasMantenimiento = const [];
  int _enMantenimiento = 0;
  int _fueraDeServicio = 0;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final vehiculos = await ref.read(vehiculoRepositoryProvider).listar();
    final documentos = await ref.read(vehiculoDocumentoRepositoryProvider).listarTodos();
    final mantenimientos = await ref.read(vehiculoMantenimientoRepositoryProvider).listarTodos();
    final kilometrajes = await ref.read(vehiculoKilometrajeRepositoryProvider).listarTodos();

    final documentosPorVehiculo = <String, List<VehiculoDocumentoData>>{};
    for (final documento in documentos) {
      documentosPorVehiculo.putIfAbsent(documento.vehiculoId, () => []).add(documento);
    }

    final mantenimientosPorVehiculo = <String, List<VehiculoMantenimientoData>>{};
    for (final registro in mantenimientos) {
      mantenimientosPorVehiculo.putIfAbsent(registro.vehiculoId, () => []).add(registro);
    }
    // `kilometrajes` no viene ordenado por Vehículo — se agrupa y solo se
    // conserva la lectura más reciente de cada uno (mismo criterio que
    // `VehiculoKilometrajeRepositoryImpl.obtenerActual`, aquí derivado en
    // memoria para evitar N+1).
    final kilometrajeActualPorVehiculo = <String, int>{};
    for (final lectura in kilometrajes) {
      final actual = kilometrajeActualPorVehiculo[lectura.vehiculoId];
      if (actual == null) kilometrajeActualPorVehiculo[lectura.vehiculoId] = lectura.kilometraje;
    }

    final alertasDocumentos = <_AlertaDocumento>[];
    final alertasMantenimiento = <_AlertaMantenimiento>[];
    var enMantenimiento = 0;
    var fueraDeServicio = 0;

    for (final vehiculo in vehiculos) {
      if (vehiculo.estatus == 'enMantenimiento') enMantenimiento++;
      if (vehiculo.estatus == 'fueraDeServicio') fueraDeServicio++;
      if (vehiculo.estatus == 'baja') continue;

      final documentosDelVehiculo = documentosPorVehiculo[vehiculo.id];
      if (documentosDelVehiculo != null) {
        for (final documento in documentosVigentesPorTipo(documentosDelVehiculo)) {
          final estado = calcularEstadoVigenciaDocumento(documento.fechaVencimiento);
          if (estado == EstadoVigenciaDocumento.vencido || estado == EstadoVigenciaDocumento.proximoAVencer) {
            alertasDocumentos.add(_AlertaDocumento(vehiculo: vehiculo, documento: documento, estado: estado));
          }
        }
      }

      final mantenimientosDelVehiculo = mantenimientosPorVehiculo[vehiculo.id];
      if (mantenimientosDelVehiculo != null) {
        // Mismo orden que `listarPorVehiculo` (desc por fecha) — la
        // fuente masiva no lo garantiza, así que se ordena aquí.
        mantenimientosDelVehiculo.sort((a, b) => b.fecha.compareTo(a.fecha));
        final proximo = calcularProximoMantenimiento(mantenimientosDelVehiculo, kilometrajeActualPorVehiculo[vehiculo.id]);
        if (proximo != null &&
            (proximo.estado == EstadoProximoMantenimiento.proximo || proximo.estado == EstadoProximoMantenimiento.vencido)) {
          alertasMantenimiento.add(_AlertaMantenimiento(vehiculo: vehiculo, proximo: proximo));
        }
      }
    }

    alertasDocumentos.sort((a, b) {
      if (a.estado != b.estado) return a.estado == EstadoVigenciaDocumento.vencido ? -1 : 1;
      final fechaA = a.documento.fechaVencimiento;
      final fechaB = b.documento.fechaVencimiento;
      if (fechaA == null || fechaB == null) return 0;
      return fechaA.compareTo(fechaB);
    });
    alertasMantenimiento.sort((a, b) {
      if (a.proximo.estado != b.proximo.estado) {
        return a.proximo.estado == EstadoProximoMantenimiento.vencido ? -1 : 1;
      }
      return 0;
    });

    if (!mounted) return;
    setState(() {
      _alertasDocumentos = alertasDocumentos;
      _alertasMantenimiento = alertasMantenimiento;
      _enMantenimiento = enMantenimiento;
      _fueraDeServicio = fueraDeServicio;
      _cargando = false;
    });
  }

  String _proximoLabel(AppLocalizations l10n, ProximoMantenimientoVehiculo proximo) {
    final partes = <String>[
      if (proximo.fecha != null) _formatoFecha.format(proximo.fecha!),
      if (proximo.kilometraje != null) '${proximo.kilometraje} km',
    ];
    return partes.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RisegSectionHeader(title: l10n.vehiculosAlertasTitulo),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              RisegStatusBadge(label: '${l10n.vehiculosAlertasResumenEnMantenimiento}: $_enMantenimiento', tone: RisegStatusTone.warning),
              RisegStatusBadge(label: '${l10n.vehiculosAlertasResumenFueraDeServicio}: $_fueraDeServicio', tone: RisegStatusTone.warning),
              RisegStatusBadge(
                label:
                    '${l10n.vehiculosAlertasResumenMantenimientoProximo}: ${_alertasMantenimiento.where((a) => a.proximo.estado == EstadoProximoMantenimiento.proximo).length}',
                tone: RisegStatusTone.warning,
              ),
              RisegStatusBadge(
                label:
                    '${l10n.vehiculosAlertasResumenMantenimientoVencido}: ${_alertasMantenimiento.where((a) => a.proximo.estado == EstadoProximoMantenimiento.vencido).length}',
                tone: RisegStatusTone.error,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(l10n.vehiculosAlertasSeccionDocumentos, style: AppTypography.heading3),
          const SizedBox(height: AppSpacing.sm),
          RisegTableBase<_AlertaDocumento>(
            rows: _alertasDocumentos,
            onRowTap: (a) => context.go('/vehiculos/flotilla/${a.vehiculo.id}'),
            emptyState: RisegEmptyState(title: l10n.vehiculosAlertasVacio, message: ''),
            columns: [
              RisegColumn<_AlertaDocumento>(
                label: l10n.vehiculosAlertasColumnaVehiculo,
                cellBuilder: (a) => Text('${a.vehiculo.codigo} · ${a.vehiculo.marca} ${a.vehiculo.modelo}'),
              ),
              RisegColumn<_AlertaDocumento>(
                label: l10n.vehiculosAlertasColumnaDocumento,
                cellBuilder: (a) => Text(tipoDocumentoVehiculoLabel(l10n, a.documento)),
              ),
              RisegColumn<_AlertaDocumento>(
                label: l10n.vehiculosAlertasColumnaEstado,
                width: 150,
                cellBuilder: (a) => RisegStatusBadge(
                  label: estadoVigenciaDocumentoLabel(l10n, a.estado),
                  tone: estadoVigenciaDocumentoTono(a.estado),
                ),
              ),
              RisegColumn<_AlertaDocumento>(
                label: l10n.vehiculosAlertasColumnaVencimiento,
                width: 120,
                cellBuilder: (a) => Text(
                  a.documento.fechaVencimiento == null ? '—' : _formatoFecha.format(a.documento.fechaVencimiento!),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(l10n.vehiculosAlertasSeccionMantenimiento, style: AppTypography.heading3),
          const SizedBox(height: AppSpacing.sm),
          RisegTableBase<_AlertaMantenimiento>(
            rows: _alertasMantenimiento,
            onRowTap: (a) => context.go('/vehiculos/flotilla/${a.vehiculo.id}'),
            emptyState: RisegEmptyState(title: l10n.vehiculosAlertasMantenimientoVacio, message: ''),
            columns: [
              RisegColumn<_AlertaMantenimiento>(
                label: l10n.vehiculosAlertasColumnaVehiculo,
                cellBuilder: (a) => Text('${a.vehiculo.codigo} · ${a.vehiculo.marca} ${a.vehiculo.modelo}'),
              ),
              RisegColumn<_AlertaMantenimiento>(
                label: l10n.vehiculosAlertasColumnaProximoMantenimiento,
                cellBuilder: (a) => Text(_proximoLabel(l10n, a.proximo)),
              ),
              RisegColumn<_AlertaMantenimiento>(
                label: l10n.vehiculosAlertasColumnaEstado,
                width: 150,
                cellBuilder: (a) => RisegStatusBadge(
                  label: estadoProximoMantenimientoLabel(l10n, a.proximo.estado),
                  tone: estadoProximoMantenimientoTono(a.proximo.estado),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
