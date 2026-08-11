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

/// Sección "Línea telefónica" para el expediente de una unidad de
/// Inventario (Etapa 9B, punto 12) — solo consulta: "¿esta unidad tiene
/// línea asociada, cuál es, quién/qué Servicio la utiliza?". La unidad
/// sigue perteneciendo enteramente al dominio Inventario — este widget
/// es propio de Telefonía, montado aquí, mismo criterio exacto que
/// `LineaTelefonicaAsignadaEmpleadoSection`/`...ServicioSection`.
class LineaTelefonicaEnUnidadSection extends ConsumerStatefulWidget {
  const LineaTelefonicaEnUnidadSection({required this.unidadId, super.key});

  final String unidadId;

  @override
  ConsumerState<LineaTelefonicaEnUnidadSection> createState() => _LineaTelefonicaEnUnidadSectionState();
}

class _LineaTelefonicaEnUnidadSectionState extends ConsumerState<LineaTelefonicaEnUnidadSection> {
  bool _cargando = true;
  LineaTelefonicaEquipoData? _equipo;
  LineaTelefonicaData? _linea;
  String? _usadaPor;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final equipo = await ref.read(lineaTelefonicaEquipoRepositoryProvider).obtenerActualPorUnidad(widget.unidadId);
    final linea = equipo == null ? null : await ref.read(lineaTelefonicaRepositoryProvider).obtenerPorId(equipo.lineaTelefonicaId);

    String? usadaPor;
    if (linea != null) {
      final asignacion = await ref.read(asignacionLineaTelefonicaRepositoryProvider).obtenerActivaPorLinea(linea.id);
      if (asignacion != null) {
        final opciones = ref.read(obtenerOpcionesAsignacionLineaTelefonicaUseCaseProvider);
        if (asignacion.empleadoId != null) {
          final empleados = await opciones.obtenerEmpleados();
          usadaPor = empleados.where((e) => e.id == asignacion.empleadoId).firstOrNull?.nombre ?? asignacion.empleadoId;
        } else if (asignacion.servicioId != null) {
          final servicios = await opciones.obtenerServicios();
          usadaPor = servicios.where((s) => s.id == asignacion.servicioId).firstOrNull?.nombre ?? asignacion.servicioId;
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _equipo = equipo;
      _linea = linea;
      _usadaPor = usadaPor;
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
        Text(l10n.lineaTelefonicaEnUnidadSeccionTitulo, style: AppTypography.label),
        const SizedBox(height: AppSpacing.xs),
        if (_cargando)
          const Padding(padding: EdgeInsets.symmetric(vertical: AppSpacing.md), child: Center(child: CircularProgressIndicator()))
        else if (_equipo == null || _linea == null)
          Text(l10n.lineaTelefonicaEnUnidadVacio, style: AppTypography.body.copyWith(color: colors.textMuted))
        else
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_linea!.numero ?? _linea!.codigo, style: AppTypography.body),
                    Text(operadorLineaTelefonicaLabel(l10n, _linea!), style: AppTypography.caption.copyWith(color: colors.textMuted)),
                    if (_usadaPor != null)
                      Text(
                        '${l10n.lineaTelefonicaEnUnidadAsignadoA} $_usadaPor',
                        style: AppTypography.caption.copyWith(color: colors.textMuted),
                      ),
                    Text(
                      '${l10n.lineaTelefonicaAsociadaDesde} ${_formatoFecha.format(_equipo!.fechaInicio)}',
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
