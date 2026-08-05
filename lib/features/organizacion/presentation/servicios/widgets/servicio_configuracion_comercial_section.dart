import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_linea_comercial_vigencia_table.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/catalogo_repository.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/linea_comercial_con_vigencia.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/linea_comercial_validator.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');
final _formatoMoneda = NumberFormat.currency(locale: 'es_MX', symbol: r'$');

String formatoCentavos(int centavos) => _formatoMoneda.format(centavos / 100);

/// Sección "Configuración comercial" de Servicio (Etapa 4G.1) — una o
/// varias líneas comerciales, cada una mostrando su vigencia vigente (o,
/// si todavía no ha empezado, la programada más próxima). Sin acciones
/// de edición-por-vigencia ni cierre todavía (Etapa 4G.2) — esta primera
/// entrega es alta + consulta.
class ServicioConfiguracionComercialSection extends StatelessWidget {
  const ServicioConfiguracionComercialSection({
    required this.lineas,
    required this.subtotalComercial,
    required this.ivaVariaPorLinea,
    required this.deshabilitado,
    required this.onAgregarLinea,
    super.key,
  });

  final List<LineaComercialConVigencia> lineas;
  final int subtotalComercial;
  final bool ivaVariaPorLinea;
  final bool deshabilitado;
  final VoidCallback onAgregarLinea;

  ServicioLineaComercialVigenciaData? _filaVisible(LineaComercialConVigencia l) =>
      l.vigenciaActual ?? (l.vigenciasProgramadas.isEmpty ? null : l.vigenciasProgramadas.first);

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

    return RisegFormSection(
      title: l10n.servicioSeccionConfiguracionComercialTitulo,
      children: [
        if (lineas.isEmpty)
          Text(l10n.servicioComercialSinLineas)
        else
          RisegTableBase<LineaComercialConVigencia>(
            columns: [
              RisegColumn(
                label: l10n.servicioComercialColumnaPuesto,
                cellBuilder: (l) => Text(l.puestoNombre),
              ),
              RisegColumn(
                label: l10n.servicioComercialColumnaTurno,
                cellBuilder: (l) => Text(l.modalidadTurnoNombre),
              ),
              RisegColumn(
                label: l10n.servicioComercialColumnaCantidad,
                alignment: TextAlign.right,
                width: 90,
                cellBuilder: (l) => Text('${_filaVisible(l)?.cantidadElementos ?? '—'}'),
              ),
              RisegColumn(
                label: l10n.servicioComercialColumnaPrecioUnitario,
                alignment: TextAlign.right,
                width: 130,
                cellBuilder: (l) {
                  final fila = _filaVisible(l);
                  return Text(fila == null ? '—' : formatoCentavos(fila.precioUnitario));
                },
              ),
              RisegColumn(
                label: l10n.servicioComercialColumnaIva,
                width: 110,
                cellBuilder: (l) {
                  final fila = _filaVisible(l);
                  return Text(fila == null ? '—' : _tratamientoIvaLabel(l10n, fila.tratamientoIva));
                },
              ),
              RisegColumn(
                label: l10n.servicioComercialColumnaSubtotal,
                alignment: TextAlign.right,
                width: 130,
                cellBuilder: (l) => Text(formatoCentavos(l.subtotal)),
              ),
              RisegColumn(
                label: l10n.servicioComercialColumnaVigenciaDesde,
                width: 110,
                cellBuilder: (l) {
                  final fila = _filaVisible(l);
                  return Text(fila == null ? '—' : _formatoFecha.format(fila.fechaInicioVigencia));
                },
              ),
              RisegColumn(
                label: l10n.servicioComercialColumnaEstado,
                width: 110,
                cellBuilder: (l) => RisegStatusBadge(
                  label: l.vigenciaActual != null
                      ? l10n.servicioComercialEstadoVigente
                      : l10n.servicioComercialEstadoProgramada,
                  tone: l.vigenciaActual != null ? RisegStatusTone.success : RisegStatusTone.info,
                ),
              ),
            ],
            rows: lineas,
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.servicioComercialSubtotalTitulo, style: AppTypography.caption.copyWith(color: context.colors.textMuted)),
                  Text(formatoCentavos(subtotalComercial), style: AppTypography.heading3),
                  if (ivaVariaPorLinea) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      l10n.servicioComercialIvaPorLineaAviso,
                      style: AppTypography.caption.copyWith(color: context.colors.textMuted),
                    ),
                  ],
                ],
              ),
            ),
            RisegButton(
              key: const Key('servicio_boton_agregar_linea_comercial'),
              label: l10n.servicioComercialBotonAgregarLinea,
              variant: RisegButtonVariant.secondary,
              size: RisegButtonSize.compact,
              onPressed: deshabilitado ? null : onAgregarLinea,
            ),
          ],
        ),
      ],
    );
  }
}

/// Contenido del diálogo de alta de una línea comercial — captura las 8
/// condiciones de su primera vigencia (Etapa 4G.1, Resolución A: solo
/// estos campos abren una vigencia nueva más adelante en la Etapa 4G.2;
/// aquí es simplemente la primera). El precio se captura en pesos con
/// decimales y se convierte a centavos al notificar — el dominio nunca
/// ve `double`.
class ServicioLineaComercialForm extends StatefulWidget {
  const ServicioLineaComercialForm({
    required this.puestos,
    required this.modalidadesTurno,
    required this.onCambio,
    super.key,
  });

  final List<PuestoData> puestos;
  final List<CatalogoItem> modalidadesTurno;
  final ValueChanged<LineaComercialBorrador> onCambio;

  @override
  State<ServicioLineaComercialForm> createState() => _ServicioLineaComercialFormState();
}

class _ServicioLineaComercialFormState extends State<ServicioLineaComercialForm> {
  String? _puestoId;
  String? _modalidadTurnoId;
  final _cantidadController = TextEditingController();
  final _precioController = TextEditingController();
  TratamientoIva? _tratamientoIva;
  DateTime? _fechaInicioVigencia;
  DateTime? _fechaFinVigencia;
  final _descripcionController = TextEditingController();
  final _observacionesController = TextEditingController();

  @override
  void dispose() {
    _cantidadController.dispose();
    _precioController.dispose();
    _descripcionController.dispose();
    _observacionesController.dispose();
    super.dispose();
  }

  int? _precioEnCentavos() {
    final texto = _precioController.text.trim().replaceAll(',', '');
    if (texto.isEmpty) return null;
    final valor = double.tryParse(texto);
    if (valor == null) return null;
    return (valor * 100).round();
  }

  void _notificar() {
    widget.onCambio(
      LineaComercialBorrador(
        puestoId: _puestoId ?? '',
        modalidadTurnoId: _modalidadTurnoId ?? '',
        cantidadElementos: int.tryParse(_cantidadController.text.trim()),
        precioUnitario: _precioEnCentavos(),
        tratamientoIva: _tratamientoIva,
        fechaInicioVigencia: _fechaInicioVigencia,
        fechaFinVigencia: _fechaFinVigencia,
        descripcion: _descripcionController.text,
        observaciones: _observacionesController.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RisegSelect<String>(
          label: l10n.servicioComercialCampoPuesto,
          value: _puestoId,
          items: [for (final p in widget.puestos) RisegSelectItem(value: p.id, label: p.nombre)],
          onChanged: (valor) {
            setState(() => _puestoId = valor);
            _notificar();
          },
        ),
        const SizedBox(height: AppSpacing.md),
        RisegSelect<String>(
          label: l10n.servicioComercialCampoModalidadTurno,
          value: _modalidadTurnoId,
          items: [for (final m in widget.modalidadesTurno) RisegSelectItem(value: m.id, label: m.nombre)],
          onChanged: (valor) {
            setState(() => _modalidadTurnoId = valor);
            _notificar();
          },
        ),
        const SizedBox(height: AppSpacing.md),
        RisegTextField(
          label: l10n.servicioComercialCampoCantidadElementos,
          controller: _cantidadController,
          keyboardType: TextInputType.number,
          onChanged: (_) => _notificar(),
        ),
        const SizedBox(height: AppSpacing.md),
        RisegTextField(
          label: l10n.servicioComercialCampoPrecioUnitario,
          controller: _precioController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => _notificar(),
        ),
        const SizedBox(height: AppSpacing.md),
        RisegSelect<TratamientoIva>(
          label: l10n.servicioComercialCampoTratamientoIva,
          value: _tratamientoIva,
          items: [
            RisegSelectItem(value: TratamientoIva.masIva, label: l10n.servicioComercialTratamientoIvaMasIva),
            RisegSelectItem(value: TratamientoIva.ivaIncluido, label: l10n.servicioComercialTratamientoIvaIvaIncluido),
            RisegSelectItem(value: TratamientoIva.noAplica, label: l10n.servicioComercialTratamientoIvaNoAplica),
          ],
          onChanged: (valor) {
            setState(() => _tratamientoIva = valor);
            _notificar();
          },
        ),
        const SizedBox(height: AppSpacing.md),
        RisegDateField(
          label: l10n.servicioComercialCampoFechaInicioVigencia,
          value: _fechaInicioVigencia,
          onChanged: (valor) {
            setState(() => _fechaInicioVigencia = valor);
            _notificar();
          },
        ),
        const SizedBox(height: AppSpacing.md),
        RisegDateField(
          label: l10n.servicioComercialCampoFechaFinVigencia,
          value: _fechaFinVigencia,
          onChanged: (valor) {
            setState(() => _fechaFinVigencia = valor);
            _notificar();
          },
        ),
        const SizedBox(height: AppSpacing.md),
        RisegTextField(
          label: l10n.servicioComercialCampoDescripcion,
          controller: _descripcionController,
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
