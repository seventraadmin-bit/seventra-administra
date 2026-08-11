import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';

import '../../telefonia_providers.dart';
import '../linea_telefonica_labels.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');

/// Sección "Telefonía" para el expediente de un Empleado (Etapa 9B) —
/// mismo patrón exacto que `VehiculoAsignadoEmpleadoSection`:
/// autocontenida (su propia carga, su propio estado), solo consulta —
/// asignar/cambiar/retirar vive únicamente en el módulo Telefonía
/// ("no reconstruir Telefonía dentro de Personal", punto 10 de 9B).
class LineaTelefonicaAsignadaEmpleadoSection extends ConsumerStatefulWidget {
  const LineaTelefonicaAsignadaEmpleadoSection({required this.empleadoId, super.key});

  final String empleadoId;

  @override
  ConsumerState<LineaTelefonicaAsignadaEmpleadoSection> createState() => _LineaTelefonicaAsignadaEmpleadoSectionState();
}

class _LineaTelefonicaAsignadaEmpleadoSectionState extends ConsumerState<LineaTelefonicaAsignadaEmpleadoSection> {
  bool _cargando = true;
  AsignacionLineaTelefonicaData? _asignacion;
  LineaTelefonicaData? _linea;
  String? _equipoDescripcion;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final asignacion = await ref.read(asignacionLineaTelefonicaRepositoryProvider).obtenerActivaPorEmpleado(widget.empleadoId);
    final linea = asignacion == null ? null : await ref.read(lineaTelefonicaRepositoryProvider).obtenerPorId(asignacion.lineaTelefonicaId);

    String? equipoDescripcion;
    if (linea != null) {
      final equipo = await ref.read(lineaTelefonicaEquipoRepositoryProvider).obtenerActualPorLinea(linea.id);
      if (equipo != null) {
        final info = await ref.read(obtenerEquiposDisponiblesLineaTelefonicaUseCaseProvider).obtenerInfo(equipo.unidadId);
        equipoDescripcion = info?.descripcion;
      }
    }

    if (!mounted) return;
    setState(() {
      _asignacion = asignacion;
      _linea = linea;
      _equipoDescripcion = equipoDescripcion;
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
        Text(l10n.lineaTelefonicaAsociadaSeccionTitulo, style: AppTypography.label),
        const SizedBox(height: AppSpacing.xs),
        if (_cargando)
          const Padding(padding: EdgeInsets.symmetric(vertical: AppSpacing.md), child: Center(child: CircularProgressIndicator()))
        else if (_asignacion == null || _linea == null)
          Text(l10n.lineaTelefonicaAsociadaVacio, style: AppTypography.body.copyWith(color: colors.textMuted))
        else
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_linea!.numero ?? _linea!.codigo, style: AppTypography.body),
                    Text(operadorLineaTelefonicaLabel(l10n, _linea!), style: AppTypography.caption.copyWith(color: colors.textMuted)),
                    if (_equipoDescripcion != null)
                      Text(_equipoDescripcion!, style: AppTypography.caption.copyWith(color: colors.textMuted)),
                    Text(
                      '${l10n.lineaTelefonicaAsociadaDesde} ${_formatoFecha.format(_asignacion!.fechaInicio)}',
                      style: AppTypography.caption.copyWith(color: colors.textMuted),
                    ),
                  ],
                ),
              ),
              RisegButton(
                label: l10n.lineaTelefonicaAsociadaBotonVerExpediente,
                variant: RisegButtonVariant.ghost,
                size: RisegButtonSize.compact,
                onPressed: () => context.go('/telefonia/lineas/${_linea!.id}'),
              ),
            ],
          ),
      ],
    );
  }
}
