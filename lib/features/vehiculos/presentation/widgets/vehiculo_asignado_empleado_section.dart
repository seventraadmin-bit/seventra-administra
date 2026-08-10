import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';

import '../../vehiculos_providers.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');

/// Sección "Vehículo asignado" para el expediente de un Empleado
/// (Etapa 8B) — autocontenida (carga y estado propios), mismo criterio
/// de aislamiento que `InventarioAsignadoServicioSection` (Inventario
/// 7B): no toca `EmpleadoExpedienteController`. Solo consulta/acceso —
/// asignar/cambiar/retirar viven únicamente en el expediente del
/// Vehículo (instrucción explícita de Marlon: "no reconstruir
/// Vehículos dentro de Personal").
class VehiculoAsignadoEmpleadoSection extends ConsumerStatefulWidget {
  const VehiculoAsignadoEmpleadoSection({required this.empleadoId, super.key});

  final String empleadoId;

  @override
  ConsumerState<VehiculoAsignadoEmpleadoSection> createState() => _VehiculoAsignadoEmpleadoSectionState();
}

class _VehiculoAsignadoEmpleadoSectionState extends ConsumerState<VehiculoAsignadoEmpleadoSection> {
  bool _cargando = true;
  AsignacionVehiculoData? _asignacion;
  VehiculoData? _vehiculo;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final asignacion =
        await ref.read(asignacionVehiculoRepositoryProvider).obtenerActivaPorEmpleado(widget.empleadoId);
    final vehiculo =
        asignacion == null ? null : await ref.read(vehiculoRepositoryProvider).obtenerPorId(asignacion.vehiculoId);
    if (!mounted) return;
    setState(() {
      _asignacion = asignacion;
      _vehiculo = vehiculo;
      _cargando = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.vehiculoAsignadoSeccionTitulo, style: AppTypography.label),
        const SizedBox(height: AppSpacing.xs),
        if (_cargando)
          const Padding(padding: EdgeInsets.symmetric(vertical: AppSpacing.md), child: Center(child: CircularProgressIndicator()))
        else if (_asignacion == null || _vehiculo == null)
          Text(l10n.vehiculoAsignadoVacio, style: AppTypography.body.copyWith(color: colors.textMuted))
        else
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${_vehiculo!.marca} ${_vehiculo!.modelo}', style: AppTypography.body),
                    if (_vehiculo!.placas != null)
                      Text(_vehiculo!.placas!, style: AppTypography.caption.copyWith(color: colors.textMuted)),
                    Text(
                      '${l10n.vehiculoAsignadoDesde} ${_formatoFecha.format(_asignacion!.fechaInicio)}',
                      style: AppTypography.caption.copyWith(color: colors.textMuted),
                    ),
                  ],
                ),
              ),
              RisegButton(
                label: l10n.vehiculoAsignadoBotonVerExpediente,
                variant: RisegButtonVariant.ghost,
                size: RisegButtonSize.compact,
                onPressed: () => context.go('/vehiculos/${_vehiculo!.id}'),
              ),
            ],
          ),
      ],
    );
  }
}
