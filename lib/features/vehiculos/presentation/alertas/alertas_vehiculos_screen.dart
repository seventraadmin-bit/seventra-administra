import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';

import '../../domain/usecases/agrupar_documentos_vehiculo.dart';
import '../../domain/usecases/calcular_estado_vigencia_documento.dart';
import '../../vehiculos_providers.dart';
import '../vehiculo_labels.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');

/// Una fila de la pantalla de Alertas — el documento vigente de un
/// tipo, ya en estado `vencido`/`proximoAVencer`, con su Vehículo ya
/// resuelto.
class _AlertaDocumento {
  const _AlertaDocumento({required this.vehiculo, required this.documento, required this.estado});
  final VehiculoData vehiculo;
  final VehiculoDocumentoData documento;
  final EstadoVigenciaDocumento estado;
}

/// Alertas de documentos (Etapa 8C) — derivado en vivo, cero tablas de
/// resumen, mismo criterio que `ReportesScreen` (Inventario 7D).
/// Vehículos dados de baja quedan **excluidos** — un vehículo que ya no
/// opera no necesita seguir generando ruido de vencimientos (punto 10,
/// análisis explícito pedido por Marlon, decisión que él mismo ya
/// insinuó como preferida).
class AlertasVehiculosScreen extends ConsumerStatefulWidget {
  const AlertasVehiculosScreen({super.key});

  @override
  ConsumerState<AlertasVehiculosScreen> createState() => _AlertasVehiculosScreenState();
}

class _AlertasVehiculosScreenState extends ConsumerState<AlertasVehiculosScreen> {
  bool _cargando = true;
  List<_AlertaDocumento> _alertas = const [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final vehiculos = await ref.read(vehiculoRepositoryProvider).listar();
    final vehiculosPorId = {for (final v in vehiculos) v.id: v};
    final documentos = await ref.read(vehiculoDocumentoRepositoryProvider).listarTodos();

    final documentosPorVehiculo = <String, List<VehiculoDocumentoData>>{};
    for (final documento in documentos) {
      documentosPorVehiculo.putIfAbsent(documento.vehiculoId, () => []).add(documento);
    }

    final alertas = <_AlertaDocumento>[];
    documentosPorVehiculo.forEach((vehiculoId, documentosDelVehiculo) {
      final vehiculo = vehiculosPorId[vehiculoId];
      if (vehiculo == null || vehiculo.estatus == 'baja') return;

      for (final documento in documentosVigentesPorTipo(documentosDelVehiculo)) {
        final estado = calcularEstadoVigenciaDocumento(documento.fechaVencimiento);
        if (estado == EstadoVigenciaDocumento.vencido || estado == EstadoVigenciaDocumento.proximoAVencer) {
          alertas.add(_AlertaDocumento(vehiculo: vehiculo, documento: documento, estado: estado));
        }
      }
    });

    alertas.sort((a, b) {
      if (a.estado != b.estado) return a.estado == EstadoVigenciaDocumento.vencido ? -1 : 1;
      final fechaA = a.documento.fechaVencimiento;
      final fechaB = b.documento.fechaVencimiento;
      if (fechaA == null || fechaB == null) return 0;
      return fechaA.compareTo(fechaB);
    });

    if (!mounted) return;
    setState(() {
      _alertas = alertas;
      _cargando = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RisegSectionHeader(title: l10n.vehiculosAlertasTitulo),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: RisegTableBase<_AlertaDocumento>(
              loading: _cargando,
              rows: _alertas,
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
          ),
        ],
      ),
    );
  }
}
