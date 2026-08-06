import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_regla_evento_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_vigencia_table.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/catalogo_repository.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/calcular_fechas_cobro_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/configuracion_cobro_con_vigencia.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/configuracion_cobro_regla_evento_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/configuracion_cobro_validator.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');
const _calcularFechasCobro = CalcularFechasCobroUseCase();

String _tipoDocumentoLabel(AppLocalizations l10n, String valor) {
  return switch (TipoDocumentoCobro.values.byName(valor)) {
    TipoDocumentoCobro.cfdi => l10n.servicioCobroTipoDocumentoCfdi,
    TipoDocumentoCobro.reciboDePago => l10n.servicioCobroTipoDocumentoReciboDePago,
  };
}

String _agrupacionLabel(AppLocalizations l10n, String valor) {
  return switch (AgrupacionCobro.values.byName(valor)) {
    AgrupacionCobro.porServicio => l10n.servicioCobroAgrupacionPorServicio,
    AgrupacionCobro.porEntidadFiscal => l10n.servicioCobroAgrupacionPorEntidadFiscal,
    AgrupacionCobro.porCliente => l10n.servicioCobroAgrupacionPorCliente,
    AgrupacionCobro.manual => l10n.servicioCobroAgrupacionManual,
  };
}

String _metodoLabel(AppLocalizations l10n, String valor) {
  return switch (MetodoPagoCobro.values.byName(valor)) {
    MetodoPagoCobro.pue => l10n.servicioCobroMetodoPue,
    MetodoPagoCobro.ppd => l10n.servicioCobroMetodoPpd,
    MetodoPagoCobro.noAplica => l10n.servicioCobroMetodoNoAplica,
  };
}

String _eventoLabel(AppLocalizations l10n, TipoEventoCobro evento) {
  return switch (evento) {
    TipoEventoCobro.emision => l10n.servicioCobroEventoEmision,
    TipoEventoCobro.procesamiento => l10n.servicioCobroEventoProcesamiento,
    TipoEventoCobro.pagoEsperado => l10n.servicioCobroEventoPagoEsperado,
  };
}

String _tipoReglaLabel(AppLocalizations l10n, TipoReglaEvento tipo) {
  return switch (tipo) {
    TipoReglaEvento.diaFijoDelMes => l10n.servicioCobroReglaDiaFijoDelMes,
    TipoReglaEvento.diasHabilesDespuesDe => l10n.servicioCobroReglaDiasHabilesDespuesDe,
    TipoReglaEvento.nEsimoDiaSemanaDelMes => l10n.servicioCobroReglaNEsimoDiaSemanaDelMes,
    TipoReglaEvento.mismoDiaSemanaSiguienteA => l10n.servicioCobroReglaMismoDiaSemanaSiguienteA,
  };
}

String _mesRelativoLabel(AppLocalizations l10n, MesRelativoCobro mes) {
  return switch (mes) {
    MesRelativoCobro.actual => l10n.servicioCobroMesRelativoActual,
    MesRelativoCobro.siguiente => l10n.servicioCobroMesRelativoSiguiente,
  };
}

String _ordinalLabel(AppLocalizations l10n, OrdinalSemanaCobro ordinal) {
  return switch (ordinal) {
    OrdinalSemanaCobro.primero => l10n.servicioCobroOrdinalPrimero,
    OrdinalSemanaCobro.segundo => l10n.servicioCobroOrdinalSegundo,
    OrdinalSemanaCobro.tercero => l10n.servicioCobroOrdinalTercero,
    OrdinalSemanaCobro.cuarto => l10n.servicioCobroOrdinalCuarto,
    OrdinalSemanaCobro.ultimo => l10n.servicioCobroOrdinalUltimo,
  };
}

String _diaSemanaLabel(AppLocalizations l10n, DiaSemanaCobro dia) {
  return switch (dia) {
    DiaSemanaCobro.lunes => l10n.servicioCobroDiaSemanaLunes,
    DiaSemanaCobro.martes => l10n.servicioCobroDiaSemanaMartes,
    DiaSemanaCobro.miercoles => l10n.servicioCobroDiaSemanaMiercoles,
    DiaSemanaCobro.jueves => l10n.servicioCobroDiaSemanaJueves,
    DiaSemanaCobro.viernes => l10n.servicioCobroDiaSemanaViernes,
    DiaSemanaCobro.sabado => l10n.servicioCobroDiaSemanaSabado,
    DiaSemanaCobro.domingo => l10n.servicioCobroDiaSemanaDomingo,
  };
}

/// Describe una regla ya persistida en una sola línea legible — usado
/// tanto en consulta como en historial.
String describirRegla(AppLocalizations l10n, ConfiguracionCobroReglaEventoData regla) {
  final tipo = TipoReglaEvento.values.byName(regla.tipoRegla);
  switch (tipo) {
    case TipoReglaEvento.diaFijoDelMes:
      final mes = _mesRelativoLabel(l10n, MesRelativoCobro.values.byName(regla.mesRelativo!));
      return '${l10n.servicioCobroCampoDiaDelMes} ${regla.diaDelMes} — $mes';
    case TipoReglaEvento.nEsimoDiaSemanaDelMes:
      final mes = _mesRelativoLabel(l10n, MesRelativoCobro.values.byName(regla.mesRelativo!));
      final ordinal = _ordinalLabel(l10n, OrdinalSemanaCobro.values.byName(regla.ordinalSemana!));
      final dia = _diaSemanaLabel(l10n, DiaSemanaCobro.values.byName(regla.diaSemana!));
      return '$ordinal $dia — $mes';
    case TipoReglaEvento.diasHabilesDespuesDe:
      final ref = _eventoLabel(l10n, TipoEventoCobro.values.byName(regla.eventoReferencia!));
      return '${regla.offsetDiasHabiles} ${l10n.servicioCobroCampoOffsetDiasHabiles} — $ref';
    case TipoReglaEvento.mismoDiaSemanaSiguienteA:
      final dia = _diaSemanaLabel(l10n, DiaSemanaCobro.values.byName(regla.diaSemana!));
      final ref = _eventoLabel(l10n, TipoEventoCobro.values.byName(regla.eventoReferencia!));
      return '$dia siguiente — $ref';
  }
}

/// Sección "Configuración de cobro" de Servicio — 1:1, así que se
/// muestra como una ficha resumen (no una tabla) con la vigencia
/// vigente (o, si todavía no ha empezado, la programada más próxima).
/// Desde la Etapa 4H.2 incluye las reglas temporales, las fechas
/// calculadas del periodo actual, el badge Completa/Incompleta y el
/// ciclo completo de vigencias (nueva vigencia/cerrar/historial).
class ServicioConfiguracionCobroSection extends StatelessWidget {
  const ServicioConfiguracionCobroSection({
    required this.configuracionCobro,
    required this.deshabilitado,
    required this.onAgregar,
    required this.onNuevaVigencia,
    required this.onCerrar,
    required this.onVerHistorial,
    super.key,
  });

  final ConfiguracionCobroConVigencia? configuracionCobro;
  final bool deshabilitado;
  final VoidCallback onAgregar;
  final VoidCallback onNuevaVigencia;
  final VoidCallback onCerrar;
  final VoidCallback onVerHistorial;

  ConfiguracionCobroVigenciaData? _filaVisible(ConfiguracionCobroConVigencia c) =>
      c.vigenciaActual ?? (c.vigenciasProgramadas.isEmpty ? null : c.vigenciasProgramadas.first);

  Widget _estadoBadge(AppLocalizations l10n, ConfiguracionCobroConVigencia c) {
    if (c.vigenciaActual != null) {
      return RisegStatusBadge(label: l10n.servicioCobroEstadoVigente, tone: RisegStatusTone.success);
    }
    if (c.vigenciasProgramadas.isNotEmpty) {
      return RisegStatusBadge(label: l10n.servicioCobroEstadoProgramada, tone: RisegStatusTone.info);
    }
    return RisegStatusBadge(label: l10n.servicioCobroEstadoSinCondicionVigente, tone: RisegStatusTone.neutral);
  }

  Widget _dato(BuildContext context, String etiqueta, String valor) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(etiqueta, style: AppTypography.caption.copyWith(color: colors.textMuted)),
        Text(valor, style: AppTypography.body.copyWith(color: colors.textPrimary)),
      ],
    );
  }

  String _reglaOEtiqueta(AppLocalizations l10n, List<ConfiguracionCobroReglaEventoData> reglas, TipoEventoCobro evento, String pendiente) {
    for (final r in reglas) {
      if (TipoEventoCobro.values.byName(r.tipoEvento) == evento) return describirRegla(l10n, r);
    }
    return pendiente;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final configuracion = configuracionCobro;
    final fila = configuracion == null ? null : _filaVisible(configuracion);

    FechasCobroCalculadas? fechas;
    if (configuracion != null && fila != null) {
      final mesInicioPeriodo = mesInicioDelPeriodoActual(diaInicioPeriodo: fila.diaInicioPeriodo, hoy: DateTime.now());
      fechas = _calcularFechasCobro.ejecutar(reglas: configuracion.reglasEventos, mesInicioPeriodo: mesInicioPeriodo);
    }

    return RisegFormSection(
      title: l10n.servicioSeccionConfiguracionCobroTitulo,
      children: [
        if (configuracion == null || fila == null)
          Text(l10n.servicioCobroSinConfiguracion)
        else ...[
          Wrap(
            spacing: AppSpacing.xl,
            runSpacing: AppSpacing.md,
            children: [
              _dato(context, l10n.servicioCobroColumnaTipoDocumento, _tipoDocumentoLabel(l10n, fila.tipoDocumento)),
              _dato(context, l10n.servicioCobroColumnaFrecuencia, configuracion.frecuenciaNombre ?? '—'),
              _dato(context, l10n.servicioCobroColumnaAgrupacion, _agrupacionLabel(l10n, fila.agrupacion)),
              _dato(context, l10n.servicioCobroColumnaMetodo, _metodoLabel(l10n, fila.metodo)),
              _dato(
                context,
                l10n.servicioCobroColumnaEntidadFiscal,
                configuracion.entidadFiscalRazonSocial ?? l10n.servicioCobroSinEntidadFiscal,
              ),
              _dato(context, l10n.servicioCobroColumnaVigenteDesde, _formatoFecha.format(fila.fechaInicioVigencia)),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(l10n.servicioCobroColumnaEstado, style: AppTypography.caption.copyWith(color: colors.textMuted)),
                      const SizedBox(width: AppSpacing.xs),
                      RisegStatusBadge(
                        label: configuracion.estaCompleta ? l10n.servicioCobroBadgeCompleta : l10n.servicioCobroBadgeIncompleta,
                        tone: configuracion.estaCompleta ? RisegStatusTone.success : RisegStatusTone.warning,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  _estadoBadge(l10n, configuracion),
                ],
              ),
            ],
          ),
          if (fila.requiereComplemento) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(l10n.servicioCobroRequiereComplementoAviso, style: AppTypography.caption.copyWith(color: colors.info)),
          ],
          const SizedBox(height: AppSpacing.md),
          Text(l10n.servicioCobroSeccionReglasTitulo, style: AppTypography.label.copyWith(color: colors.textMuted)),
          const SizedBox(height: AppSpacing.xs),
          _dato(
            context,
            l10n.servicioCobroReglaEmisionTitulo,
            _reglaOEtiqueta(l10n, configuracion.reglasEventos, TipoEventoCobro.emision, l10n.servicioCobroReglaPendiente),
          ),
          const SizedBox(height: AppSpacing.xs),
          _dato(
            context,
            l10n.servicioCobroReglaProcesamientoTitulo,
            _reglaOEtiqueta(l10n, configuracion.reglasEventos, TipoEventoCobro.procesamiento, l10n.servicioCobroReglaNoAplicaOPendiente),
          ),
          const SizedBox(height: AppSpacing.xs),
          _dato(
            context,
            l10n.servicioCobroReglaPagoTitulo,
            _reglaOEtiqueta(l10n, configuracion.reglasEventos, TipoEventoCobro.pagoEsperado, l10n.servicioCobroReglaPendiente),
          ),
          if (fechas != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(l10n.servicioCobroFechasCalculadasTitulo, style: AppTypography.label.copyWith(color: colors.textMuted)),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xl,
              runSpacing: AppSpacing.sm,
              children: [
                _dato(
                  context,
                  l10n.servicioCobroFechaEmisionCalculada,
                  fechas.fechaEmision == null ? '—' : _formatoFecha.format(fechas.fechaEmision!),
                ),
                _dato(
                  context,
                  l10n.servicioCobroFechaProcesamientoCalculada,
                  fechas.fechaProcesamiento == null ? '—' : _formatoFecha.format(fechas.fechaProcesamiento!),
                ),
                _dato(
                  context,
                  l10n.servicioCobroFechaPagoCalculada,
                  fechas.fechaPagoEsperado == null ? '—' : _formatoFecha.format(fechas.fechaPagoEsperado!),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              RisegButton(
                label: l10n.servicioCobroBotonNuevaVigencia,
                variant: RisegButtonVariant.ghost,
                size: RisegButtonSize.compact,
                onPressed: deshabilitado ? null : onNuevaVigencia,
              ),
              RisegButton(
                label: l10n.servicioCobroBotonCerrarConfiguracion,
                variant: RisegButtonVariant.ghost,
                size: RisegButtonSize.compact,
                onPressed: deshabilitado || configuracion.vigenciaActual == null ? null : onCerrar,
              ),
              RisegButton(
                label: l10n.servicioCobroBotonHistorial,
                variant: RisegButtonVariant.ghost,
                size: RisegButtonSize.compact,
                onPressed: onVerHistorial,
              ),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        Align(
          alignment: Alignment.centerRight,
          child: RisegButton(
            key: const Key('servicio_boton_agregar_configuracion_cobro'),
            label: l10n.servicioCobroBotonAgregar,
            variant: RisegButtonVariant.secondary,
            size: RisegButtonSize.compact,
            onPressed: deshabilitado || configuracion != null ? null : onAgregar,
          ),
        ),
      ],
    );
  }
}

/// Captura una regla de evento para un [tipoEvento] fijo — reutilizado 3
/// veces (Emisión/Procesamiento/Pago esperado) dentro del mismo
/// formulario. `eventosReferenciaPermitidos` acota el selector de
/// `eventoReferencia` a las combinaciones válidas (Emisión: ninguno;
/// Procesamiento: solo Emisión; Pago esperado: Emisión o Procesamiento).
class _ReglaEventoForm extends StatefulWidget {
  const _ReglaEventoForm({
    required this.titulo,
    required this.tipoEvento,
    required this.eventosReferenciaPermitidos,
    required this.onCambio,
    this.valorInicial,
  });

  final String titulo;
  final TipoEventoCobro tipoEvento;
  final List<TipoEventoCobro> eventosReferenciaPermitidos;
  final ValueChanged<ReglaEventoBorrador> onCambio;
  final ConfiguracionCobroReglaEventoData? valorInicial;

  @override
  State<_ReglaEventoForm> createState() => _ReglaEventoFormState();
}

class _ReglaEventoFormState extends State<_ReglaEventoForm> {
  TipoReglaEvento? _tipoRegla;
  MesRelativoCobro? _mesRelativo;
  late final _diaDelMesController = TextEditingController();
  OrdinalSemanaCobro? _ordinalSemana;
  DiaSemanaCobro? _diaSemana;
  late final _offsetDiasHabilesController = TextEditingController();
  TipoEventoCobro? _eventoReferencia;

  @override
  void initState() {
    super.initState();
    final inicial = widget.valorInicial;
    if (inicial != null) {
      _tipoRegla = TipoReglaEvento.values.byName(inicial.tipoRegla);
      _mesRelativo = inicial.mesRelativo == null ? null : MesRelativoCobro.values.byName(inicial.mesRelativo!);
      _diaDelMesController.text = inicial.diaDelMes?.toString() ?? '';
      _ordinalSemana = inicial.ordinalSemana == null ? null : OrdinalSemanaCobro.values.byName(inicial.ordinalSemana!);
      _diaSemana = inicial.diaSemana == null ? null : DiaSemanaCobro.values.byName(inicial.diaSemana!);
      _offsetDiasHabilesController.text = inicial.offsetDiasHabiles?.toString() ?? '';
      _eventoReferencia = inicial.eventoReferencia == null ? null : TipoEventoCobro.values.byName(inicial.eventoReferencia!);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _notificar());
  }

  @override
  void dispose() {
    _diaDelMesController.dispose();
    _offsetDiasHabilesController.dispose();
    super.dispose();
  }

  void _notificar() {
    widget.onCambio(
      ReglaEventoBorrador(
        tipoEvento: widget.tipoEvento,
        tipoRegla: _tipoRegla,
        mesRelativo: _mesRelativo,
        diaDelMes: int.tryParse(_diaDelMesController.text.trim()),
        ordinalSemana: _ordinalSemana,
        diaSemana: _diaSemana,
        offsetDiasHabiles: int.tryParse(_offsetDiasHabilesController.text.trim()),
        eventoReferencia: _eventoReferencia,
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
        Text(widget.titulo, style: AppTypography.label.copyWith(color: colors.textMuted)),
        const SizedBox(height: AppSpacing.xs),
        RisegSelect<TipoReglaEvento>(
          label: l10n.servicioCobroCampoTipoRegla,
          value: _tipoRegla,
          items: [
            for (final t in TipoReglaEvento.values) RisegSelectItem(value: t, label: _tipoReglaLabel(l10n, t)),
          ],
          onChanged: (valor) {
            setState(() => _tipoRegla = valor);
            _notificar();
          },
        ),
        if (_tipoRegla == TipoReglaEvento.diaFijoDelMes || _tipoRegla == TipoReglaEvento.nEsimoDiaSemanaDelMes) ...[
          const SizedBox(height: AppSpacing.sm),
          RisegSelect<MesRelativoCobro>(
            label: l10n.servicioCobroCampoMesRelativo,
            value: _mesRelativo,
            items: [
              RisegSelectItem(value: MesRelativoCobro.actual, label: l10n.servicioCobroMesRelativoActual),
              RisegSelectItem(value: MesRelativoCobro.siguiente, label: l10n.servicioCobroMesRelativoSiguiente),
            ],
            onChanged: (valor) {
              setState(() => _mesRelativo = valor);
              _notificar();
            },
          ),
        ],
        if (_tipoRegla == TipoReglaEvento.diaFijoDelMes) ...[
          const SizedBox(height: AppSpacing.sm),
          RisegTextField(
            label: l10n.servicioCobroCampoDiaDelMes,
            controller: _diaDelMesController,
            keyboardType: TextInputType.number,
            onChanged: (_) => _notificar(),
          ),
        ],
        if (_tipoRegla == TipoReglaEvento.nEsimoDiaSemanaDelMes || _tipoRegla == TipoReglaEvento.mismoDiaSemanaSiguienteA) ...[
          const SizedBox(height: AppSpacing.sm),
          RisegSelect<DiaSemanaCobro>(
            label: l10n.servicioCobroCampoDiaSemana,
            value: _diaSemana,
            items: [
              for (final d in DiaSemanaCobro.values) RisegSelectItem(value: d, label: _diaSemanaLabel(l10n, d)),
            ],
            onChanged: (valor) {
              setState(() => _diaSemana = valor);
              _notificar();
            },
          ),
        ],
        if (_tipoRegla == TipoReglaEvento.nEsimoDiaSemanaDelMes) ...[
          const SizedBox(height: AppSpacing.sm),
          RisegSelect<OrdinalSemanaCobro>(
            label: l10n.servicioCobroCampoOrdinalSemana,
            value: _ordinalSemana,
            items: [
              for (final o in OrdinalSemanaCobro.values) RisegSelectItem(value: o, label: _ordinalLabel(l10n, o)),
            ],
            onChanged: (valor) {
              setState(() => _ordinalSemana = valor);
              _notificar();
            },
          ),
        ],
        if (_tipoRegla == TipoReglaEvento.diasHabilesDespuesDe) ...[
          const SizedBox(height: AppSpacing.sm),
          RisegTextField(
            label: l10n.servicioCobroCampoOffsetDiasHabiles,
            controller: _offsetDiasHabilesController,
            keyboardType: TextInputType.number,
            onChanged: (_) => _notificar(),
          ),
        ],
        if (_tipoRegla == TipoReglaEvento.diasHabilesDespuesDe || _tipoRegla == TipoReglaEvento.mismoDiaSemanaSiguienteA) ...[
          const SizedBox(height: AppSpacing.sm),
          RisegSelect<TipoEventoCobro>(
            label: l10n.servicioCobroCampoEventoReferencia,
            value: _eventoReferencia,
            items: [
              for (final e in widget.eventosReferenciaPermitidos) RisegSelectItem(value: e, label: _eventoLabel(l10n, e)),
            ],
            onChanged: (valor) {
              setState(() => _eventoReferencia = valor);
              _notificar();
            },
          ),
        ],
      ],
    );
  }
}

/// Contenido del diálogo de alta/nueva-vigencia de la Configuración de
/// cobro — captura las condiciones de la vigencia junto con sus 3
/// reglas temporales (Etapa 4H.2). `valoresIniciales` prellena todo con
/// la vigencia actual al registrar una nueva vigencia; `null` en el
/// alta, donde no hay nada que prellenar (mismo criterio que
/// `ServicioLineaComercialForm`).
class ServicioConfiguracionCobroForm extends StatefulWidget {
  const ServicioConfiguracionCobroForm({
    required this.frecuencias,
    required this.entidadesFiscales,
    required this.onCambio,
    this.valoresIniciales,
    this.reglasIniciales = const [],
    super.key,
  });

  final List<CatalogoItem> frecuencias;
  final List<EntidadFiscalData> entidadesFiscales;
  final void Function(ConfiguracionCobroBorrador borrador, List<ReglaEventoBorrador> reglas) onCambio;
  final ConfiguracionCobroVigenciaData? valoresIniciales;
  final List<ConfiguracionCobroReglaEventoData> reglasIniciales;

  @override
  State<ServicioConfiguracionCobroForm> createState() => _ServicioConfiguracionCobroFormState();
}

class _ServicioConfiguracionCobroFormState extends State<ServicioConfiguracionCobroForm> {
  TipoDocumentoCobro? _tipoDocumento;
  String? _frecuenciaId;
  late final _diaInicioPeriodoController = TextEditingController();
  AgrupacionCobro? _agrupacion;
  MetodoPagoCobro? _metodo;
  bool _requiereComplemento = false;
  String? _entidadFiscalId;
  DateTime? _fechaInicioVigencia;
  late final _portalNombreController = TextEditingController();
  late final _portalUrlController = TextEditingController();
  late final _portalUsuarioController = TextEditingController();
  late final _portalContrasenaController = TextEditingController();
  late final _portalObservacionesController = TextEditingController();
  late final _cuentaBancariaController = TextEditingController();
  late final _observacionesController = TextEditingController();
  late final _nuevoCorreoController = TextEditingController();
  late List<String> _correos;

  ReglaEventoBorrador _reglaEmision = const ReglaEventoBorrador(tipoEvento: TipoEventoCobro.emision);
  ReglaEventoBorrador _reglaProcesamiento = const ReglaEventoBorrador(tipoEvento: TipoEventoCobro.procesamiento);
  ReglaEventoBorrador _reglaPago = const ReglaEventoBorrador(tipoEvento: TipoEventoCobro.pagoEsperado);

  ConfiguracionCobroReglaEventoData? _reglaInicialDe(TipoEventoCobro evento) {
    for (final r in widget.reglasIniciales) {
      if (TipoEventoCobro.values.byName(r.tipoEvento) == evento) return r;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    final inicial = widget.valoresIniciales;
    _correos = [];
    if (inicial != null) {
      _tipoDocumento = TipoDocumentoCobro.values.byName(inicial.tipoDocumento);
      _frecuenciaId = inicial.frecuenciaId;
      _diaInicioPeriodoController.text = '${inicial.diaInicioPeriodo}';
      _agrupacion = AgrupacionCobro.values.byName(inicial.agrupacion);
      _metodo = MetodoPagoCobro.values.byName(inicial.metodo);
      _requiereComplemento = inicial.requiereComplemento;
      _entidadFiscalId = inicial.entidadFiscalId;
      _portalNombreController.text = inicial.portalNombre ?? '';
      _portalUrlController.text = inicial.portalUrl ?? '';
      _portalUsuarioController.text = inicial.portalUsuario ?? '';
      _portalContrasenaController.text = inicial.portalContrasena ?? '';
      _portalObservacionesController.text = inicial.portalObservaciones ?? '';
      _cuentaBancariaController.text = inicial.cuentaBancaria ?? '';
      _observacionesController.text = inicial.observaciones ?? '';
      // Nota deliberada: `fechaInicioVigencia` nunca se prellena — la
      // fecha de una nueva vigencia siempre debe elegirse de forma
      // explícita (mismo criterio que Configuración comercial).
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _notificar());
  }

  @override
  void dispose() {
    _diaInicioPeriodoController.dispose();
    _portalNombreController.dispose();
    _portalUrlController.dispose();
    _portalUsuarioController.dispose();
    _portalContrasenaController.dispose();
    _portalObservacionesController.dispose();
    _cuentaBancariaController.dispose();
    _observacionesController.dispose();
    _nuevoCorreoController.dispose();
    super.dispose();
  }

  void _notificar() {
    widget.onCambio(
      ConfiguracionCobroBorrador(
        tipoDocumento: _tipoDocumento,
        frecuenciaId: _frecuenciaId ?? '',
        diaInicioPeriodo: int.tryParse(_diaInicioPeriodoController.text.trim()),
        agrupacion: _agrupacion,
        metodo: _metodo,
        requiereComplemento: _requiereComplemento,
        fechaInicioVigencia: _fechaInicioVigencia,
        entidadFiscalId: _entidadFiscalId,
        portalNombre: _portalNombreController.text,
        portalUrl: _portalUrlController.text,
        portalUsuario: _portalUsuarioController.text,
        portalContrasena: _portalContrasenaController.text,
        portalObservaciones: _portalObservacionesController.text,
        cuentaBancaria: _cuentaBancariaController.text,
        observaciones: _observacionesController.text,
        correos: List.unmodifiable(_correos),
      ),
      [_reglaEmision, _reglaProcesamiento, _reglaPago],
    );
  }

  void _agregarCorreo() {
    final correo = _nuevoCorreoController.text.trim();
    if (correo.isEmpty) return;
    setState(() {
      _correos.add(correo);
      _nuevoCorreoController.clear();
    });
    _notificar();
  }

  void _quitarCorreo(int indice) {
    setState(() => _correos.removeAt(indice));
    _notificar();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RisegSelect<TipoDocumentoCobro>(
          label: l10n.servicioCobroCampoTipoDocumento,
          value: _tipoDocumento,
          items: [
            RisegSelectItem(value: TipoDocumentoCobro.cfdi, label: l10n.servicioCobroTipoDocumentoCfdi),
            RisegSelectItem(value: TipoDocumentoCobro.reciboDePago, label: l10n.servicioCobroTipoDocumentoReciboDePago),
          ],
          onChanged: (valor) {
            setState(() => _tipoDocumento = valor);
            _notificar();
          },
        ),
        const SizedBox(height: AppSpacing.md),
        RisegSelect<String>(
          label: l10n.servicioCobroCampoFrecuencia,
          value: _frecuenciaId,
          items: [for (final f in widget.frecuencias) RisegSelectItem(value: f.id, label: f.nombre)],
          onChanged: (valor) {
            setState(() => _frecuenciaId = valor);
            _notificar();
          },
        ),
        const SizedBox(height: AppSpacing.md),
        RisegTextField(
          label: l10n.servicioCobroCampoDiaInicioPeriodo,
          controller: _diaInicioPeriodoController,
          keyboardType: TextInputType.number,
          onChanged: (_) => _notificar(),
        ),
        const SizedBox(height: AppSpacing.md),
        RisegSelect<AgrupacionCobro>(
          label: l10n.servicioCobroCampoAgrupacion,
          value: _agrupacion,
          items: [
            RisegSelectItem(value: AgrupacionCobro.porServicio, label: l10n.servicioCobroAgrupacionPorServicio),
            RisegSelectItem(value: AgrupacionCobro.porEntidadFiscal, label: l10n.servicioCobroAgrupacionPorEntidadFiscal),
            RisegSelectItem(value: AgrupacionCobro.porCliente, label: l10n.servicioCobroAgrupacionPorCliente),
            RisegSelectItem(value: AgrupacionCobro.manual, label: l10n.servicioCobroAgrupacionManual),
          ],
          onChanged: (valor) {
            setState(() => _agrupacion = valor);
            _notificar();
          },
        ),
        const SizedBox(height: AppSpacing.md),
        RisegSelect<MetodoPagoCobro>(
          label: l10n.servicioCobroCampoMetodo,
          value: _metodo,
          items: [
            RisegSelectItem(value: MetodoPagoCobro.pue, label: l10n.servicioCobroMetodoPue),
            RisegSelectItem(value: MetodoPagoCobro.ppd, label: l10n.servicioCobroMetodoPpd),
            RisegSelectItem(value: MetodoPagoCobro.noAplica, label: l10n.servicioCobroMetodoNoAplica),
          ],
          onChanged: (valor) {
            setState(() => _metodo = valor);
            _notificar();
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: Text(l10n.servicioCobroCampoRequiereComplemento, style: AppTypography.body.copyWith(color: colors.textPrimary)),
            ),
            Switch(
              value: _requiereComplemento,
              onChanged: (valor) {
                setState(() => _requiereComplemento = valor);
                _notificar();
              },
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        RisegSelect<String>(
          label: l10n.servicioCobroCampoEntidadFiscal,
          value: _entidadFiscalId,
          items: [for (final e in widget.entidadesFiscales) RisegSelectItem(value: e.id, label: e.razonSocial)],
          enabled: widget.entidadesFiscales.isNotEmpty,
          onChanged: (valor) {
            setState(() => _entidadFiscalId = valor);
            _notificar();
          },
        ),
        const SizedBox(height: AppSpacing.md),
        RisegDateField(
          label: l10n.servicioCobroCampoFechaInicioVigencia,
          value: _fechaInicioVigencia,
          onChanged: (valor) {
            setState(() => _fechaInicioVigencia = valor);
            _notificar();
          },
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(l10n.servicioCobroSeccionReglasTitulo, style: AppTypography.label.copyWith(color: colors.textMuted)),
        const SizedBox(height: AppSpacing.xs),
        _ReglaEventoForm(
          titulo: l10n.servicioCobroReglaEmisionTitulo,
          tipoEvento: TipoEventoCobro.emision,
          eventosReferenciaPermitidos: const [],
          valorInicial: _reglaInicialDe(TipoEventoCobro.emision),
          onCambio: (valor) {
            _reglaEmision = valor;
            _notificar();
          },
        ),
        const SizedBox(height: AppSpacing.md),
        _ReglaEventoForm(
          titulo: l10n.servicioCobroReglaProcesamientoTitulo,
          tipoEvento: TipoEventoCobro.procesamiento,
          eventosReferenciaPermitidos: const [TipoEventoCobro.emision],
          valorInicial: _reglaInicialDe(TipoEventoCobro.procesamiento),
          onCambio: (valor) {
            _reglaProcesamiento = valor;
            _notificar();
          },
        ),
        const SizedBox(height: AppSpacing.md),
        _ReglaEventoForm(
          titulo: l10n.servicioCobroReglaPagoTitulo,
          tipoEvento: TipoEventoCobro.pagoEsperado,
          eventosReferenciaPermitidos: const [TipoEventoCobro.emision, TipoEventoCobro.procesamiento],
          valorInicial: _reglaInicialDe(TipoEventoCobro.pagoEsperado),
          onCambio: (valor) {
            _reglaPago = valor;
            _notificar();
          },
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(l10n.servicioCobroSeccionPortalTitulo, style: AppTypography.label.copyWith(color: colors.textMuted)),
        const SizedBox(height: AppSpacing.xs),
        RisegTextField(
          label: l10n.servicioCobroCampoPortalNombre,
          controller: _portalNombreController,
          onChanged: (_) => _notificar(),
        ),
        const SizedBox(height: AppSpacing.md),
        RisegTextField(
          label: l10n.servicioCobroCampoPortalUrl,
          controller: _portalUrlController,
          onChanged: (_) => _notificar(),
        ),
        const SizedBox(height: AppSpacing.md),
        RisegTextField(
          label: l10n.servicioCobroCampoPortalUsuario,
          controller: _portalUsuarioController,
          onChanged: (_) => _notificar(),
        ),
        const SizedBox(height: AppSpacing.md),
        RisegTextField(
          label: l10n.servicioCobroCampoPortalContrasena,
          controller: _portalContrasenaController,
          obscureText: true,
          helperText: l10n.servicioCobroCampoPortalContrasenaAyuda,
          onChanged: (_) => _notificar(),
        ),
        const SizedBox(height: AppSpacing.md),
        RisegTextField(
          label: l10n.servicioCobroCampoPortalObservaciones,
          controller: _portalObservacionesController,
          onChanged: (_) => _notificar(),
        ),
        const SizedBox(height: AppSpacing.lg),
        RisegTextField(
          label: l10n.servicioCobroCampoCuentaBancaria,
          controller: _cuentaBancariaController,
          helperText: l10n.servicioCobroCampoCuentaBancariaAyuda,
          onChanged: (_) => _notificar(),
        ),
        const SizedBox(height: AppSpacing.md),
        RisegTextField(
          label: l10n.servicioCobroCampoObservaciones,
          controller: _observacionesController,
          onChanged: (_) => _notificar(),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(l10n.servicioCobroSeccionCorreosTitulo, style: AppTypography.label.copyWith(color: colors.textMuted)),
        const SizedBox(height: AppSpacing.xs),
        if (_correos.isEmpty)
          Text(l10n.servicioCobroSinCorreos, style: AppTypography.caption.copyWith(color: colors.textMuted))
        else
          Column(
            children: [
              for (var i = 0; i < _correos.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
                  child: Row(
                    children: [
                      Expanded(child: Text(_correos[i], style: AppTypography.body.copyWith(color: colors.textPrimary))),
                      IconButton(
                        tooltip: l10n.servicioCobroBotonQuitarCorreo,
                        icon: const Icon(Icons.close, size: 18),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _quitarCorreo(i),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: RisegTextField(
                label: l10n.servicioCobroCampoNuevoCorreo,
                controller: _nuevoCorreoController,
                keyboardType: TextInputType.emailAddress,
                onChanged: (_) {},
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            RisegButton(
              label: l10n.servicioCobroBotonAgregarCorreo,
              variant: RisegButtonVariant.secondary,
              size: RisegButtonSize.compact,
              onPressed: _agregarCorreo,
            ),
          ],
        ),
      ],
    );
  }
}

/// Contenido del diálogo "Cerrar Configuración de cobro" — mismo
/// criterio que `ServicioCerrarLineaForm` (Etapa 4G.2): advertencia
/// explícita del efecto administrativo + fecha efectiva de cierre.
class ServicioCerrarConfiguracionCobroForm extends StatefulWidget {
  const ServicioCerrarConfiguracionCobroForm({required this.onCambio, super.key});

  final ValueChanged<DateTime> onCambio;

  @override
  State<ServicioCerrarConfiguracionCobroForm> createState() => _ServicioCerrarConfiguracionCobroFormState();
}

class _ServicioCerrarConfiguracionCobroFormState extends State<ServicioCerrarConfiguracionCobroForm> {
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
                child: Text(l10n.servicioCobroCerrarAdvertencia, style: AppTypography.body.copyWith(color: colors.warning)),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        RisegDateField(
          label: l10n.servicioCobroCerrarCampoFecha,
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
