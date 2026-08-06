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

/// Sección "Configuración comercial" de Servicio — una o varias líneas
/// comerciales, cada una mostrando su vigencia vigente (o, si todavía no
/// ha empezado, la programada más próxima) y las 3 acciones de historial
/// de la Etapa 4G.2 (Nueva vigencia, Cerrar línea, Historial).
class ServicioConfiguracionComercialSection extends StatelessWidget {
  const ServicioConfiguracionComercialSection({
    required this.lineas,
    required this.subtotalComercial,
    required this.ivaVariaPorLinea,
    required this.elementosComercialesVigentes,
    required this.elementosAutorizados,
    required this.elementosDifierenDeAutorizados,
    required this.proximaFechaProgramada,
    required this.deshabilitado,
    required this.onAgregarLinea,
    required this.onNuevaVigencia,
    required this.onCerrarLinea,
    required this.onVerHistorial,
    super.key,
  });

  final List<LineaComercialConVigencia> lineas;
  final int subtotalComercial;
  final bool ivaVariaPorLinea;
  final int elementosComercialesVigentes;
  final int elementosAutorizados;
  final bool elementosDifierenDeAutorizados;
  final DateTime? proximaFechaProgramada;
  final bool deshabilitado;
  final VoidCallback onAgregarLinea;
  final ValueChanged<LineaComercialConVigencia> onNuevaVigencia;
  final ValueChanged<LineaComercialConVigencia> onCerrarLinea;
  final ValueChanged<LineaComercialConVigencia> onVerHistorial;

  ServicioLineaComercialVigenciaData? _filaVisible(LineaComercialConVigencia l) =>
      l.vigenciaActual ?? (l.vigenciasProgramadas.isEmpty ? null : l.vigenciasProgramadas.first);

  String _tratamientoIvaLabel(AppLocalizations l10n, String valor) {
    return switch (TratamientoIva.values.byName(valor)) {
      TratamientoIva.masIva => l10n.servicioComercialTratamientoIvaMasIva,
      TratamientoIva.ivaIncluido => l10n.servicioComercialTratamientoIvaIvaIncluido,
      TratamientoIva.noAplica => l10n.servicioComercialTratamientoIvaNoAplica,
    };
  }

  Widget _estadoBadge(AppLocalizations l10n, LineaComercialConVigencia l) {
    if (l.vigenciaActual != null) {
      return RisegStatusBadge(label: l10n.servicioComercialEstadoVigente, tone: RisegStatusTone.success);
    }
    if (l.vigenciasProgramadas.isNotEmpty) {
      return RisegStatusBadge(label: l10n.servicioComercialEstadoProgramada, tone: RisegStatusTone.info);
    }
    return RisegStatusBadge(label: l10n.servicioComercialEstadoSinCondicionVigente, tone: RisegStatusTone.neutral);
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
                width: 150,
                cellBuilder: (l) => _estadoBadge(l10n, l),
              ),
            ],
            rows: lineas,
            actionsWidth: 140,
            rowActionsBuilder: (l) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: l10n.servicioComercialBotonNuevaVigencia,
                  icon: const Icon(Icons.update, size: 18),
                  visualDensity: VisualDensity.compact,
                  onPressed: deshabilitado ? null : () => onNuevaVigencia(l),
                ),
                IconButton(
                  tooltip: l.vigenciaActual == null
                      ? l10n.servicioComercialCerrarLineaBotonAyudaSinCondicion
                      : (l.vigenciasProgramadas.isNotEmpty
                          ? l10n.servicioComercialCerrarLineaBotonAyudaTieneProgramada
                          : l10n.servicioComercialBotonCerrarLinea),
                  icon: const Icon(Icons.block_outlined, size: 18),
                  visualDensity: VisualDensity.compact,
                  onPressed: deshabilitado || l.vigenciaActual == null || l.vigenciasProgramadas.isNotEmpty
                      ? null
                      : () => onCerrarLinea(l),
                ),
                IconButton(
                  tooltip: l10n.servicioComercialBotonHistorial,
                  icon: const Icon(Icons.history, size: 18),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => onVerHistorial(l),
                ),
              ],
            ),
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
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    l10n.servicioComercialElementosVigentesTitulo,
                    style: AppTypography.caption.copyWith(color: context.colors.textMuted),
                  ),
                  Text('$elementosComercialesVigentes', style: AppTypography.heading3),
                  if (elementosDifierenDeAutorizados) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      l10n.servicioComercialElementosDifierenAdvertencia(elementosAutorizados),
                      style: AppTypography.caption.copyWith(color: context.colors.warning),
                    ),
                  ],
                  if (proximaFechaProgramada != null) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      l10n.servicioComercialAvisoProgramadas(
                        lineas.fold(0, (acc, l) => acc + l.vigenciasProgramadas.length),
                        _formatoFecha.format(proximaFechaProgramada!),
                      ),
                      style: AppTypography.caption.copyWith(color: context.colors.info),
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
    this.valoresIniciales,
    super.key,
  });

  final List<PuestoData> puestos;
  final List<CatalogoItem> modalidadesTurno;
  final ValueChanged<LineaComercialBorrador> onCambio;

  /// Prellenar con la condición vigente actual al registrar una nueva
  /// vigencia (Etapa 4G.2) — normalmente solo 1-2 campos cambian. `null`
  /// en el alta (Etapa 4G.1), donde no hay nada que prellenar.
  /// Deliberadamente NO prellena `fechaInicioVigencia`/`fechaFinVigencia`
  /// — la fecha de una nueva vigencia siempre debe elegirse de forma
  /// explícita, nunca heredarse de la condición que reemplaza.
  final ServicioLineaComercialVigenciaData? valoresIniciales;

  @override
  State<ServicioLineaComercialForm> createState() => _ServicioLineaComercialFormState();
}

class _ServicioLineaComercialFormState extends State<ServicioLineaComercialForm> {
  String? _puestoId;
  String? _modalidadTurnoId;
  late final _cantidadController = TextEditingController(
    text: widget.valoresIniciales == null ? '' : '${widget.valoresIniciales!.cantidadElementos}',
  );
  late final _precioController = TextEditingController(
    text: widget.valoresIniciales == null ? '' : (widget.valoresIniciales!.precioUnitario / 100).toStringAsFixed(2),
  );
  TratamientoIva? _tratamientoIva;
  DateTime? _fechaInicioVigencia;
  DateTime? _fechaFinVigencia;
  late final _descripcionController = TextEditingController(text: widget.valoresIniciales?.descripcion ?? '');
  late final _observacionesController = TextEditingController(text: widget.valoresIniciales?.observaciones ?? '');

  @override
  void initState() {
    super.initState();
    _puestoId = widget.valoresIniciales?.puestoId;
    _modalidadTurnoId = widget.valoresIniciales?.modalidadTurnoId;
    _tratamientoIva =
        widget.valoresIniciales == null ? null : TratamientoIva.values.byName(widget.valoresIniciales!.tratamientoIva);
    // Notifica de inmediato para que un envío sin tocar ningún campo
    // (caso raro, pero posible si solo cambia la fecha) ya lleve los
    // valores prellenados.
    WidgetsBinding.instance.addPostFrameCallback((_) => _notificar());
  }

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

/// Contenido del diálogo "Cerrar línea comercial" — una advertencia
/// explícita del efecto administrativo (nunca solo "termina una
/// vigencia", pedido expreso de Marlon) + la fecha efectiva de cierre,
/// que por defecto es hoy pero puede ajustarse.
class ServicioCerrarLineaForm extends StatefulWidget {
  const ServicioCerrarLineaForm({required this.onCambio, super.key});

  final ValueChanged<DateTime> onCambio;

  @override
  State<ServicioCerrarLineaForm> createState() => _ServicioCerrarLineaFormState();
}

class _ServicioCerrarLineaFormState extends State<ServicioCerrarLineaForm> {
  late DateTime _fechaEfectiva = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.onCambio(_fechaEfectiva));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(color: colors.warningBg, borderRadius: AppRadius.mdRadius),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber_outlined, size: 18, color: colors.warning),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  l10n.servicioComercialCerrarLineaAdvertencia,
                  style: AppTypography.body.copyWith(color: colors.warning),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        RisegDateField(
          label: l10n.servicioComercialCerrarLineaCampoFecha,
          value: _fechaEfectiva,
          onChanged: (valor) {
            setState(() => _fechaEfectiva = valor);
            widget.onCambio(valor);
          },
        ),
      ],
    );
  }
}
