import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_linea_comercial_vigencia_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/linea_comercial_con_vigencia.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/obtener_historial_linea_comercial_usecase.dart';
import 'package:riseg_one/features/organizacion/presentation/shared/campo_consulta.dart';

import 'servicio_configuracion_comercial_section.dart' show formatoCentavos;

final _formatoFecha = DateFormat('dd/MM/yyyy');

/// Contenido del diálogo "Historial de la línea comercial" — bloques
/// compactos de pares etiqueta/valor (Etapa 4G.2, Resolución G: nunca
/// una tabla horizontal ancha, para mantener consistencia visual con el
/// resto de RISEG ONE), orden cronológico, incluyendo vigencias
/// canceladas (Resolución F). Solo de consulta salvo dos acciones por
/// fila: editar anotaciones (vigente/programada) y cancelar (solo
/// programada).
class ServicioHistorialLineaComercialContent extends StatelessWidget {
  const ServicioHistorialLineaComercialContent({
    required this.historial,
    required this.onEditarAnotaciones,
    required this.onCancelarProgramada,
    super.key,
  });

  final List<VigenciaHistorial> historial;
  final ValueChanged<VigenciaHistorial> onEditarAnotaciones;
  final ValueChanged<VigenciaHistorial> onCancelarProgramada;

  String _estadoLabel(AppLocalizations l10n, EstadoVigencia estado) {
    return switch (estado) {
      EstadoVigencia.vigente => l10n.servicioComercialEstadoVigente,
      EstadoVigencia.programada => l10n.servicioComercialEstadoProgramada,
      EstadoVigencia.historica => l10n.servicioComercialEstadoHistorica,
      EstadoVigencia.cancelada => l10n.servicioComercialEstadoCancelada,
    };
  }

  RisegStatusTone _estadoTono(EstadoVigencia estado) {
    return switch (estado) {
      EstadoVigencia.vigente => RisegStatusTone.success,
      EstadoVigencia.programada => RisegStatusTone.info,
      EstadoVigencia.historica => RisegStatusTone.neutral,
      EstadoVigencia.cancelada => RisegStatusTone.error,
    };
  }

  String _tratamientoIvaLabel(AppLocalizations l10n, String valor) {
    return switch (TratamientoIva.values.byName(valor)) {
      TratamientoIva.masIva => l10n.servicioComercialTratamientoIvaMasIva,
      TratamientoIva.ivaIncluido => l10n.servicioComercialTratamientoIvaIvaIncluido,
      TratamientoIva.noAplica => l10n.servicioComercialTratamientoIvaNoAplica,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    return SizedBox(
      width: double.maxFinite,
      height: 420,
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
                    child: Text('${fila.puestoNombre} · ${fila.modalidadTurnoNombre}', style: AppTypography.label),
                  ),
                  RisegStatusBadge(label: _estadoLabel(l10n, fila.estado), tone: _estadoTono(fila.estado)),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(child: CampoConsulta(label: l10n.servicioComercialColumnaCantidad, value: '${v.cantidadElementos}')),
                  Expanded(
                    child: CampoConsulta(label: l10n.servicioComercialColumnaPrecioUnitario, value: formatoCentavos(v.precioUnitario)),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              CampoConsulta(label: l10n.servicioComercialColumnaIva, value: _tratamientoIvaLabel(l10n, v.tratamientoIva)),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: CampoConsulta(
                      label: l10n.servicioComercialCampoFechaInicioVigencia,
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
              CampoConsulta(label: l10n.servicioComercialCampoDescripcion, value: v.descripcion),
              const SizedBox(height: AppSpacing.sm),
              CampoConsulta(label: l10n.servicioComercialCampoObservaciones, value: v.observaciones),
              const SizedBox(height: AppSpacing.sm),
              CampoConsulta(label: l10n.servicioComercialHistorialCampoCreadaEl, value: _formatoFecha.format(v.createdAt)),
              if (fila.estado == EstadoVigencia.vigente || fila.estado == EstadoVigencia.programada) ...[
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.xs,
                  children: [
                    RisegButton(
                      label: l10n.servicioComercialHistorialBotonEditarAnotaciones,
                      variant: RisegButtonVariant.ghost,
                      size: RisegButtonSize.compact,
                      onPressed: () => onEditarAnotaciones(fila),
                    ),
                    if (fila.estado == EstadoVigencia.programada)
                      RisegButton(
                        label: l10n.servicioComercialHistorialBotonCancelarProgramada,
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

/// Contenido del diálogo "Editar anotaciones" — solo descripción y
/// observaciones, nunca condiciones comerciales (Etapa 4G.2,
/// Resolución A).
class ServicioAnotacionesForm extends StatefulWidget {
  const ServicioAnotacionesForm({required this.vigencia, required this.onCambio, super.key});

  final VigenciaHistorial vigencia;
  final void Function(String? descripcion, String? observaciones) onCambio;

  @override
  State<ServicioAnotacionesForm> createState() => _ServicioAnotacionesFormState();
}

class _ServicioAnotacionesFormState extends State<ServicioAnotacionesForm> {
  late final _descripcionController = TextEditingController(text: widget.vigencia.vigencia.descripcion ?? '');
  late final _observacionesController = TextEditingController(text: widget.vigencia.vigencia.observaciones ?? '');

  @override
  void dispose() {
    _descripcionController.dispose();
    _observacionesController.dispose();
    super.dispose();
  }

  void _notificar() => widget.onCambio(_descripcionController.text, _observacionesController.text);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RisegTextField(
          label: l10n.servicioComercialCampoDescripcion,
          controller: _descripcionController,
          autofocus: true,
          onChanged: (_) => _notificar(),
        ),
        const SizedBox(height: AppSpacing.md),
        RisegTextField(
          label: l10n.servicioComercialCampoObservaciones,
          controller: _observacionesController,
          onChanged: (_) => _notificar(),
        ),
      ],
    );
  }
}
