import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_regla_evento_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/configuracion_cobro_con_vigencia.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/obtener_historial_configuracion_cobro_usecase.dart';
import 'package:riseg_one/features/organizacion/presentation/shared/campo_consulta.dart';

import 'servicio_configuracion_cobro_section.dart' show describirRegla;

final _formatoFecha = DateFormat('dd/MM/yyyy');

/// Contenido del diálogo "Historial de la Configuración de cobro" —
/// mismo criterio que `ServicioHistorialLineaComercialContent` (Etapa
/// 4G.2): bloques compactos de pares etiqueta/valor, orden cronológico,
/// incluyendo vigencias canceladas. Solo de consulta salvo dos acciones
/// por fila: editar observaciones (vigente/programada) y cancelar (solo
/// programada).
class ServicioHistorialConfiguracionCobroContent extends StatelessWidget {
  const ServicioHistorialConfiguracionCobroContent({
    required this.historial,
    required this.onEditarObservaciones,
    required this.onCancelarProgramada,
    super.key,
  });

  final List<VigenciaHistorialCobro> historial;
  final ValueChanged<VigenciaHistorialCobro> onEditarObservaciones;
  final ValueChanged<VigenciaHistorialCobro> onCancelarProgramada;

  String _estadoLabel(AppLocalizations l10n, EstadoVigenciaCobro estado) {
    return switch (estado) {
      EstadoVigenciaCobro.vigente => l10n.servicioComercialEstadoVigente,
      EstadoVigenciaCobro.programada => l10n.servicioComercialEstadoProgramada,
      EstadoVigenciaCobro.historica => l10n.servicioComercialEstadoHistorica,
      EstadoVigenciaCobro.cancelada => l10n.servicioComercialEstadoCancelada,
    };
  }

  RisegStatusTone _estadoTono(EstadoVigenciaCobro estado) {
    return switch (estado) {
      EstadoVigenciaCobro.vigente => RisegStatusTone.success,
      EstadoVigenciaCobro.programada => RisegStatusTone.info,
      EstadoVigenciaCobro.historica => RisegStatusTone.neutral,
      EstadoVigenciaCobro.cancelada => RisegStatusTone.error,
    };
  }

  String? _reglaDe(AppLocalizations l10n, List<ConfiguracionCobroReglaEventoData> reglas, TipoEventoCobro evento) {
    for (final r in reglas) {
      if (TipoEventoCobro.values.byName(r.tipoEvento) == evento) return describirRegla(l10n, r);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    return SizedBox(
      width: double.maxFinite,
      height: 460,
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: historial.length,
        separatorBuilder: (_, _) => Divider(height: AppSpacing.xl, color: colors.borderSubtle),
        itemBuilder: (context, index) {
          final fila = historial[index];
          final v = fila.vigencia;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(fila.frecuenciaNombre ?? '—', style: AppTypography.label),
                  ),
                  RisegStatusBadge(label: _estadoLabel(l10n, fila.estado), tone: _estadoTono(fila.estado)),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: CampoConsulta(
                      label: l10n.servicioCobroCampoFechaInicioVigencia,
                      value: _formatoFecha.format(v.fechaInicioVigencia),
                    ),
                  ),
                  Expanded(
                    child: CampoConsulta(
                      label: l10n.servicioComercialCampoFechaFinVigencia,
                      value: v.fechaFinVigencia == null ? null : _formatoFecha.format(v.fechaFinVigencia!),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              CampoConsulta(
                label: l10n.servicioCobroReglaEmisionTitulo,
                value: _reglaDe(l10n, fila.reglasEventos, TipoEventoCobro.emision),
              ),
              const SizedBox(height: AppSpacing.sm),
              CampoConsulta(
                label: l10n.servicioCobroReglaProcesamientoTitulo,
                value: _reglaDe(l10n, fila.reglasEventos, TipoEventoCobro.procesamiento),
              ),
              const SizedBox(height: AppSpacing.sm),
              CampoConsulta(
                label: l10n.servicioCobroReglaPagoTitulo,
                value: _reglaDe(l10n, fila.reglasEventos, TipoEventoCobro.pagoEsperado),
              ),
              const SizedBox(height: AppSpacing.sm),
              CampoConsulta(label: l10n.servicioCobroCampoObservaciones, value: v.observaciones),
              const SizedBox(height: AppSpacing.sm),
              CampoConsulta(label: l10n.servicioCobroHistorialCampoCreadaEl, value: _formatoFecha.format(v.createdAt)),
              if (fila.estado == EstadoVigenciaCobro.vigente || fila.estado == EstadoVigenciaCobro.programada) ...[
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.xs,
                  children: [
                    RisegButton(
                      label: l10n.servicioCobroHistorialBotonEditarObservaciones,
                      variant: RisegButtonVariant.ghost,
                      size: RisegButtonSize.compact,
                      onPressed: () => onEditarObservaciones(fila),
                    ),
                    if (fila.estado == EstadoVigenciaCobro.programada)
                      RisegButton(
                        label: l10n.servicioCobroHistorialBotonCancelarProgramada,
                        variant: RisegButtonVariant.ghost,
                        size: RisegButtonSize.compact,
                        onPressed: () => onCancelarProgramada(fila),
                      ),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Contenido del diálogo "Editar observaciones" — solo `observaciones`,
/// nunca condiciones de cobro (Configuración de cobro no tiene un campo
/// `descripcion` propio como línea comercial).
class ServicioObservacionesConfiguracionCobroForm extends StatefulWidget {
  const ServicioObservacionesConfiguracionCobroForm({required this.vigencia, required this.onCambio, super.key});

  final VigenciaHistorialCobro vigencia;
  final ValueChanged<String?> onCambio;

  @override
  State<ServicioObservacionesConfiguracionCobroForm> createState() => _ServicioObservacionesConfiguracionCobroFormState();
}

class _ServicioObservacionesConfiguracionCobroFormState extends State<ServicioObservacionesConfiguracionCobroForm> {
  late final _observacionesController = TextEditingController(text: widget.vigencia.vigencia.observaciones ?? '');

  @override
  void dispose() {
    _observacionesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RisegTextField(
          label: l10n.servicioCobroCampoObservaciones,
          controller: _observacionesController,
          autofocus: true,
          onChanged: (valor) => widget.onCambio(valor),
        ),
      ],
    );
  }
}
