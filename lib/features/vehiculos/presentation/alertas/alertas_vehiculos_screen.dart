import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/design_system/design_system.dart';

import '../../domain/usecases/calcular_proximo_mantenimiento.dart';
import '../../domain/usecases/obtener_alertas_vehiculos_usecase.dart';
import '../../vehiculos_providers.dart';
import '../vehiculo_labels.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');

/// Alertas operativas de Vehículos (Etapas 8C+8D) — derivado en vivo,
/// cero tablas de resumen, mismo criterio que `ReportesScreen`
/// (Inventario 7D). Combina documentos por vencer y mantenimiento
/// próximo/vencido (punto 10 de la Etapa 8D), más un resumen de
/// vehículos en mantenimiento/fuera de servicio. Vehículos dados de baja
/// quedan **excluidos** de todo — un vehículo que ya no opera no
/// necesita seguir generando ruido operativo (punto 10 de 8C, reafirmado
/// en el punto 15 de 8D). La orquestación vive en
/// `ObtenerAlertasVehiculosUseCase` (Etapa 12C) — compartida con el
/// bloque de Vehículos en Reportes generales, esta pantalla solo
/// presenta el resultado.
class AlertasVehiculosScreen extends ConsumerStatefulWidget {
  const AlertasVehiculosScreen({super.key});

  @override
  ConsumerState<AlertasVehiculosScreen> createState() => _AlertasVehiculosScreenState();
}

class _AlertasVehiculosScreenState extends ConsumerState<AlertasVehiculosScreen> {
  bool _cargando = true;
  List<AlertaDocumentoVehiculo> _alertasDocumentos = const [];
  List<AlertaMantenimientoVehiculo> _alertasMantenimiento = const [];
  int _enMantenimiento = 0;
  int _fueraDeServicio = 0;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final resumen = await ref.read(obtenerAlertasVehiculosUseCaseProvider).ejecutar();

    if (!mounted) return;
    setState(() {
      _alertasDocumentos = resumen.alertasDocumentos;
      _alertasMantenimiento = resumen.alertasMantenimiento;
      _enMantenimiento = resumen.vehiculosPorEstatus['enMantenimiento'] ?? 0;
      _fueraDeServicio = resumen.vehiculosPorEstatus['fueraDeServicio'] ?? 0;
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
          RisegTableBase<AlertaDocumentoVehiculo>(
            rows: _alertasDocumentos,
            onRowTap: (a) => context.go('/vehiculos/flotilla/${a.vehiculo.id}'),
            emptyState: RisegEmptyState(title: l10n.vehiculosAlertasVacio, message: ''),
            columns: [
              RisegColumn<AlertaDocumentoVehiculo>(
                label: l10n.vehiculosAlertasColumnaVehiculo,
                cellBuilder: (a) => Text('${a.vehiculo.codigo} · ${a.vehiculo.marca} ${a.vehiculo.modelo}'),
              ),
              RisegColumn<AlertaDocumentoVehiculo>(
                label: l10n.vehiculosAlertasColumnaDocumento,
                cellBuilder: (a) => Text(tipoDocumentoVehiculoLabel(l10n, a.documento)),
              ),
              RisegColumn<AlertaDocumentoVehiculo>(
                label: l10n.vehiculosAlertasColumnaEstado,
                width: 150,
                cellBuilder: (a) => RisegStatusBadge(
                  label: estadoVigenciaDocumentoLabel(l10n, a.estado),
                  tone: estadoVigenciaDocumentoTono(a.estado),
                ),
              ),
              RisegColumn<AlertaDocumentoVehiculo>(
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
          RisegTableBase<AlertaMantenimientoVehiculo>(
            rows: _alertasMantenimiento,
            onRowTap: (a) => context.go('/vehiculos/flotilla/${a.vehiculo.id}'),
            emptyState: RisegEmptyState(title: l10n.vehiculosAlertasMantenimientoVacio, message: ''),
            columns: [
              RisegColumn<AlertaMantenimientoVehiculo>(
                label: l10n.vehiculosAlertasColumnaVehiculo,
                cellBuilder: (a) => Text('${a.vehiculo.codigo} · ${a.vehiculo.marca} ${a.vehiculo.modelo}'),
              ),
              RisegColumn<AlertaMantenimientoVehiculo>(
                label: l10n.vehiculosAlertasColumnaProximoMantenimiento,
                cellBuilder: (a) => Text(_proximoLabel(l10n, a.proximo)),
              ),
              RisegColumn<AlertaMantenimientoVehiculo>(
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
