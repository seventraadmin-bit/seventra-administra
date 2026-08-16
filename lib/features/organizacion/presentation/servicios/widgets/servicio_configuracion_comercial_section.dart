import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_linea_comercial_vigencia_table.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/catalogo_repository.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/linea_comercial_con_vigencia.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/linea_comercial_validator.dart';
import 'package:riseg_one/features/organizacion/presentation/sucursales/sucursal_expediente_form_controllers.dart'
    show HorarioControllers, HorarioDiaControlador;

final _formatoFecha = DateFormat('dd/MM/yyyy');
final _formatoMoneda = NumberFormat.currency(locale: 'es_MX', symbol: r'$');

String formatoCentavos(int centavos) => _formatoMoneda.format(centavos / 100);

/// Sección "Configuración comercial" de Servicio — una o varias líneas
/// comerciales, cada una mostrando su vigencia vigente (o, si todavía no
/// ha empezado, la programada más próxima) y sus acciones consolidadas
/// en un menú ⋮ (Etapa 15: por espacio de fila, a diferencia de un
/// encabezado, aquí sí se consolida todo — "Corregir" (solo si
/// `esCorregible`, arregla un error de captura sin dejar rastro) y
/// "Nueva vigencia" (siempre disponible, registra una condición real
/// distinta a partir de una fecha) NO son mutuamente excluyentes: una
/// línea recién creada puede necesitar cualquiera de las dos — más
/// "Cerrar línea", "Historial" y, solo Maestro, "Eliminar físicamente".
///
/// El menú ⋮ en sí **nunca** se oculta ni desaparece — `esCorregible`
/// solo decide cuáles acciones puntuales aparecen dentro de él (Etapa
/// 15, hallazgo real de Marlon: una línea con historia real, como
/// MORGAN, debe seguir teniendo forma de administrarse). "Eliminar
/// físicamente" tampoco se precondiciona a `esCorregible` — el caso de
/// uso (`ServicioComercialRepositoryImpl.eliminarFisicamente`) ya
/// rechaza con un mensaje claro cuando hay historia real; la UI no debe
/// adelantarse a esa decisión ocultando la opción.
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
    required this.esMaestro,
    required this.onAgregarLinea,
    required this.onCorregir,
    required this.onNuevaVigencia,
    required this.onCerrarLinea,
    required this.onVerHistorial,
    required this.onEliminarFisicamente,
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
  final bool esMaestro;
  final VoidCallback onAgregarLinea;
  final ValueChanged<LineaComercialConVigencia> onCorregir;
  final ValueChanged<LineaComercialConVigencia> onNuevaVigencia;
  final ValueChanged<LineaComercialConVigencia> onCerrarLinea;
  final ValueChanged<LineaComercialConVigencia> onVerHistorial;
  final ValueChanged<LineaComercialConVigencia> onEliminarFisicamente;

  ServicioLineaComercialVigenciaData? _filaVisible(LineaComercialConVigencia l) =>
      l.vigenciaActual ?? (l.vigenciasProgramadas.isEmpty ? null : l.vigenciasProgramadas.first);

  static const _letrasDia = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];

  static String _formatoHoraMinutos(int minutos) {
    final h = (minutos ~/ 60).toString().padLeft(2, '0');
    final m = (minutos % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  /// Resumen corto del horario personalizado de la vigencia mostrada —
  /// "L-V 20:00–07:00 · S-D 16:00–07:00". Vacío si la línea no tiene
  /// horario personalizado capturado (cualquier otra modalidad de
  /// turno).
  String _resumenHorarioCorto(LineaComercialConVigencia l) {
    final tramos = agruparHorarioPersonalizado(l.horarioVigenciaMostrada);
    if (tramos.isEmpty) return '';
    return tramos
        .map((t) {
          final dias = t.diaDesde == t.diaHasta ? _letrasDia[t.diaDesde] : '${_letrasDia[t.diaDesde]}-${_letrasDia[t.diaHasta]}';
          return '$dias ${_formatoHoraMinutos(t.horaInicioMinutos)}–${_formatoHoraMinutos(t.horaFinMinutos)}';
        })
        .join(' · ');
  }

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
                cellBuilder: (l) {
                  final resumen = _resumenHorarioCorto(l);
                  if (resumen.isEmpty) return Text(l.modalidadTurnoNombre);
                  return Tooltip(
                    message: resumen,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(l.modalidadTurnoNombre),
                        Text(
                          resumen,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.caption.copyWith(color: context.colors.textMuted),
                        ),
                      ],
                    ),
                  );
                },
              ),
              RisegColumn(
                label: l10n.servicioComercialColumnaCantidad,
                alignment: TextAlign.right,
                width: 70,
                cellBuilder: (l) => Text('${_filaVisible(l)?.cantidadElementos ?? '—'}'),
              ),
              RisegColumn(
                label: l10n.servicioComercialColumnaPrecioUnitario,
                alignment: TextAlign.right,
                width: 95,
                cellBuilder: (l) {
                  final fila = _filaVisible(l);
                  return Text(fila == null ? '—' : formatoCentavos(fila.precioUnitario));
                },
              ),
              // Sueldo/bono de referencia (Etapa 15, rediseño de
              // "Condiciones de Personal") — cada línea es un perfil
              // distinto con su propia condición salarial; sin estas dos
              // columnas, dos líneas con el mismo puesto pero sueldos
              // distintos (o el mismo puesto en turnos distintos) eran
              // indistinguibles de un vistazo en la tabla.
              RisegColumn(
                label: l10n.servicioComercialColumnaSueldoReferencia,
                alignment: TextAlign.right,
                width: 90,
                cellBuilder: (l) {
                  final fila = _filaVisible(l);
                  final sueldo = fila?.sueldoMensualReferenciaPersonal;
                  return Text(sueldo == null ? '—' : formatoCentavos(sueldo));
                },
              ),
              RisegColumn(
                label: l10n.servicioComercialColumnaBonoReferencia,
                alignment: TextAlign.right,
                width: 80,
                cellBuilder: (l) {
                  final fila = _filaVisible(l);
                  final bono = fila?.bonoMensualReferenciaPersonal;
                  return Text(bono == null ? '—' : formatoCentavos(bono));
                },
              ),
              RisegColumn(
                label: l10n.servicioComercialColumnaIva,
                width: 85,
                cellBuilder: (l) {
                  final fila = _filaVisible(l);
                  return Text(fila == null ? '—' : _tratamientoIvaLabel(l10n, fila.tratamientoIva));
                },
              ),
              RisegColumn(
                label: l10n.servicioComercialColumnaSubtotal,
                alignment: TextAlign.right,
                width: 100,
                cellBuilder: (l) => Text(formatoCentavos(l.subtotal)),
              ),
              RisegColumn(
                label: l10n.servicioComercialColumnaVigenciaDesde,
                width: 85,
                cellBuilder: (l) {
                  final fila = _filaVisible(l);
                  return Text(fila == null ? '—' : _formatoFecha.format(fila.fechaInicioVigencia));
                },
              ),
              RisegColumn(
                label: l10n.servicioComercialColumnaEstado,
                width: 100,
                cellBuilder: (l) => _estadoBadge(l10n, l),
              ),
            ],
            rows: lineas,
            actionsWidth: 56,
            rowActionsBuilder: (l) => RisegActionsMenu(
              menuKey: Key('servicio_comercial_linea_menu_${l.linea.id}'),
              actions: [
                if (l.esCorregible)
                  RisegMenuAction(
                    label: l10n.servicioComercialBotonCorregir,
                    icon: Icons.edit_outlined,
                    onTap: deshabilitado ? null : () => onCorregir(l),
                  ),
                RisegMenuAction(
                  label: l10n.servicioComercialBotonNuevaVigencia,
                  icon: Icons.update,
                  onTap: deshabilitado ? null : () => onNuevaVigencia(l),
                ),
                RisegMenuAction(
                  label: l10n.servicioComercialBotonCerrarLinea,
                  icon: Icons.block_outlined,
                  onTap: deshabilitado || l.vigenciaActual == null || l.vigenciasProgramadas.isNotEmpty
                      ? null
                      : () => onCerrarLinea(l),
                ),
                RisegMenuAction(
                  label: l10n.servicioComercialBotonHistorial,
                  icon: Icons.history,
                  onTap: () => onVerHistorial(l),
                ),
                // Sin condicionar a `esCorregible`: la elegibilidad real
                // (línea con exactamente 1 vigencia y sin documentos de
                // Agenda generados) ya la decide
                // `ServicioComercialRepositoryImpl.eliminarFisicamente`,
                // que rechaza con un mensaje claro cuando no aplica — la
                // UI no debe ocultar la opción de antemano.
                if (esMaestro)
                  RisegMenuAction(
                    label: l10n.eliminacionFisicaAccionMenu,
                    icon: Icons.delete_forever_outlined,
                    destructive: true,
                    onTap: () => onEliminarFisicamente(l),
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
        const SizedBox(height: AppSpacing.xxs),
        // Línea completa, nunca dentro del `Row` de arriba — un texto
        // sin ancho fijo como sibling de `RisegButton` forzaba el ancho
        // intrínseco de esa columna y producía overflow horizontal en
        // pantallas reducidas (hallazgo real, Etapa 15).
        Text(
          l10n.servicioComercialAyudaAgregarLinea,
          style: AppTypography.caption.copyWith(color: context.colors.textMuted),
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
    this.precargarFechas = false,
    this.horarioInicial = const [],
    super.key,
  });

  final List<PuestoData> puestos;
  final List<CatalogoItem> modalidadesTurno;
  final ValueChanged<LineaComercialBorrador> onCambio;

  /// Prellenar con la condición vigente actual al registrar una nueva
  /// vigencia (Etapa 4G.2) — normalmente solo 1-2 campos cambian, o al
  /// corregir un error de captura (Etapa 15). `null` en el alta (Etapa
  /// 4G.1), donde no hay nada que prellenar.
  final ServicioLineaComercialVigenciaData? valoresIniciales;

  /// `false` por defecto: "Nueva vigencia" deliberadamente NO prellena
  /// `fechaInicioVigencia`/`fechaFinVigencia` aunque [valoresIniciales]
  /// no sea nulo — la fecha de una nueva vigencia siempre debe elegirse
  /// de forma explícita, nunca heredarse de la condición que reemplaza
  /// (Etapa 4G.2, Resolución H). "Corregir" (Etapa 15) es la única
  /// excepción: ahí sí se corrige un error de captura en la fecha
  /// misma, así que pasa `true` para precargarla igual que el resto de
  /// los campos.
  final bool precargarFechas;

  /// Horario personalizado de [valoresIniciales] (Etapa 15) — el
  /// llamador ya lo resolvió vía
  /// `ServicioComercialRepository.obtenerHorario`. Se precarga siempre
  /// que exista, tanto en "Corregir" (edita el horario real) como en
  /// "Nueva vigencia" (lo copia como punto de partida editable, sin
  /// alterar la vigencia histórica de la que vino — mismo criterio que
  /// el resto de los campos en Nueva vigencia).
  final List<ServicioLineaComercialVigenciaHorarioData> horarioInicial;

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

  // Condiciones de personal de referencia de este perfil (Etapa 15,
  // rediseño de "Condiciones de Personal") — opcionales, mismo criterio
  // que precio (texto en pesos, se convierte a centavos al notificar),
  // pero a diferencia de precio nunca son obligatorias.
  late final _sueldoController = TextEditingController(
    text: _centavosAPesosTexto(widget.valoresIniciales?.sueldoMensualReferenciaPersonal),
  );
  late final _bonoController = TextEditingController(
    text: _centavosAPesosTexto(widget.valoresIniciales?.bonoMensualReferenciaPersonal),
  );

  // Horario personalizado (Etapa 15, "Modalidad de turno:
  // Personalizado") — mismo modelo de estado que Sucursal
  // (`HorarioControllers`), reutilizado en vez de duplicado; solo se
  // envía en `_notificar` cuando la modalidad elegida es Personalizado.
  final HorarioControllers _horarioControllers = HorarioControllers();

  static String _centavosAPesosTexto(int? centavos) => centavos == null ? '' : (centavos / 100).toStringAsFixed(2);

  static TimeOfDay _minutosATimeOfDay(int minutos) => TimeOfDay(hour: minutos ~/ 60, minute: minutos % 60);

  @override
  void initState() {
    super.initState();
    _puestoId = widget.valoresIniciales?.puestoId;
    _modalidadTurnoId = widget.valoresIniciales?.modalidadTurnoId;
    _tratamientoIva =
        widget.valoresIniciales == null ? null : TratamientoIva.values.byName(widget.valoresIniciales!.tratamientoIva);
    if (widget.precargarFechas) {
      _fechaInicioVigencia = widget.valoresIniciales?.fechaInicioVigencia;
      _fechaFinVigencia = widget.valoresIniciales?.fechaFinVigencia;
    }
    for (final fila in widget.horarioInicial) {
      final dia = _horarioControllers.dias[fila.diaSemana];
      dia.abierto = fila.activo;
      if (dia.abierto) {
        dia.horaInicio = _minutosATimeOfDay(fila.horaInicio);
        dia.horaFin = _minutosATimeOfDay(fila.horaFin);
      }
    }
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
    _sueldoController.dispose();
    _bonoController.dispose();
    super.dispose();
  }

  int? _pesosTextoACentavos(String texto) {
    final limpio = texto.trim().replaceAll(',', '');
    if (limpio.isEmpty) return null;
    final valor = double.tryParse(limpio);
    if (valor == null) return null;
    return (valor * 100).round();
  }

  int? _precioEnCentavos() => _pesosTextoACentavos(_precioController.text);

  bool get _esModalidadPersonalizada => _modalidadTurnoId == SeedIds.modalidadTurnoPersonalizado;

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
        sueldoMensualReferenciaPersonal: _pesosTextoACentavos(_sueldoController.text),
        bonoMensualReferenciaPersonal: _pesosTextoACentavos(_bonoController.text),
        horario: _esModalidadPersonalizada ? _horarioControllers.capturar() : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.servicioComercialSeccionDatosComercialesTitulo, style: AppTypography.label.copyWith(color: colors.textMuted)),
        const SizedBox(height: AppSpacing.xs),
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
        if (_esModalidadPersonalizada) ...[
          const SizedBox(height: AppSpacing.md),
          _horarioPersonalizadoSection(l10n, colors),
        ],
        const SizedBox(height: AppSpacing.md),
        RisegTextField(
          label: l10n.servicioComercialCampoCantidadElementos,
          controller: _cantidadController,
          keyboardType: TextInputType.number,
          helperText: l10n.servicioComercialCampoCantidadElementosAyuda,
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
        const SizedBox(height: AppSpacing.lg),
        Text(l10n.servicioSeccionCondicionesPersonalTitulo, style: AppTypography.label.copyWith(color: colors.textMuted)),
        const SizedBox(height: AppSpacing.xs),
        RisegTextField(
          label: l10n.servicioCampoSueldoReferencia,
          controller: _sueldoController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => _notificar(),
        ),
        const SizedBox(height: AppSpacing.md),
        RisegTextField(
          label: l10n.servicioCampoBonoReferencia,
          controller: _bonoController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => _notificar(),
        ),
        const SizedBox(height: AppSpacing.lg),
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

  static String _nombreDia(AppLocalizations l10n, int diaSemana) {
    return switch (diaSemana) {
      0 => l10n.horarioDiaLunes,
      1 => l10n.horarioDiaMartes,
      2 => l10n.horarioDiaMiercoles,
      3 => l10n.horarioDiaJueves,
      4 => l10n.horarioDiaViernes,
      5 => l10n.horarioDiaSabado,
      _ => l10n.horarioDiaDomingo,
    };
  }

  /// Sección "Horario personalizado" (Etapa 15) — 7 filas fijas, visible
  /// únicamente cuando la modalidad elegida es Personalizado. Al
  /// desactivar "Trabaja" en un día, sus campos de hora se deshabilitan
  /// y ese día queda como descanso — nunca se le pide capturar horas
  /// (ni se le exige limpiarlas: `HorarioDiaControlador` simplemente dejó
  /// de reportarlas mientras `abierto == false`).
  Widget _horarioPersonalizadoSection(AppLocalizations l10n, AppColorScheme colors) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(color: colors.surfaceSunken, borderRadius: AppRadius.mdRadius),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.servicioComercialHorarioPersonalizadoTitulo, style: AppTypography.label.copyWith(color: colors.textMuted)),
          const SizedBox(height: AppSpacing.sm),
          for (var dia = 0; dia < 7; dia++) _filaHorarioDia(l10n, colors, dia),
        ],
      ),
    );
  }

  Widget _filaHorarioDia(AppLocalizations l10n, AppColorScheme colors, int diaSemana) {
    final HorarioDiaControlador dia = _horarioControllers.dias[diaSemana];

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(_nombreDia(l10n, diaSemana), style: AppTypography.body.copyWith(color: colors.textPrimary)),
              ),
              Text(l10n.servicioComercialHorarioTrabaja, style: AppTypography.caption.copyWith(color: colors.textMuted)),
              Switch(
                value: dia.abierto,
                onChanged: (valor) => setState(() {
                  dia.abierto = valor;
                  _notificar();
                }),
              ),
            ],
          ),
          if (dia.abierto)
            Row(
              children: [
                Expanded(
                  child: RisegTimeField(
                    label: l10n.servicioComercialHorarioCampoEntrada,
                    value: dia.horaInicio,
                    onChanged: (valor) => setState(() {
                      dia.horaInicio = valor;
                      _notificar();
                    }),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: RisegTimeField(
                    label: l10n.servicioComercialHorarioCampoSalida,
                    value: dia.horaFin,
                    onChanged: (valor) => setState(() {
                      dia.horaFin = valor;
                      _notificar();
                    }),
                  ),
                ),
              ],
            ),
        ],
      ),
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
