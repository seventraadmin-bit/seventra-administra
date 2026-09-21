import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/organizacion/data/tables/cliente_portal_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_etapa_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_vigencia_table.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/catalogo_repository.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/calcular_fechas_cobro_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/configuracion_cobro_con_vigencia.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/configuracion_cobro_errors.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/configuracion_cobro_etapa_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/configuracion_cobro_validator.dart';

import 'configuracion_cobro_error_l10n.dart';

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

/// Nombre visible del tipo/propósito de un `ClientePortal` — mismo
/// criterio de literal-a-label que los demás enums de esta sección.
String tipoPortalClienteLabel(AppLocalizations l10n, TipoPortalCliente tipo) {
  return switch (tipo) {
    TipoPortalCliente.facturacion => l10n.clientePortalTipoFacturacion,
    TipoPortalCliente.proveedores => l10n.clientePortalTipoProveedores,
    TipoPortalCliente.pagos => l10n.clientePortalTipoPagos,
    TipoPortalCliente.otro => l10n.clientePortalTipoOtro,
  };
}

String _metodoLabel(AppLocalizations l10n, String valor) {
  return switch (MetodoPagoCobro.values.byName(valor)) {
    MetodoPagoCobro.pue => l10n.servicioCobroMetodoPue,
    MetodoPagoCobro.ppd => l10n.servicioCobroMetodoPpd,
    MetodoPagoCobro.noAplica => l10n.servicioCobroMetodoNoAplica,
  };
}

/// Nombre visible de una etapa de sistema (Etapa 15) — `procesamiento`
/// se conserva solo por compatibilidad histórica, nunca se ofrece en la
/// captura de una etapa nueva (ver `_tiposSistemaOfrecidos`).
String _etapaSistemaLabel(AppLocalizations l10n, TipoEventoCobro tipo) {
  return switch (tipo) {
    TipoEventoCobro.emision => l10n.servicioCobroEventoEmision,
    TipoEventoCobro.procesamiento => l10n.servicioCobroEventoProcesamiento,
    TipoEventoCobro.pagoEsperado => l10n.servicioCobroEventoPagoEsperado,
    TipoEventoCobro.complementoPago => l10n.servicioCobroEventoComplementoPago,
  };
}

/// Nombre visible de cualquier etapa — de sistema (vía l10n, nunca
/// editable) o personalizada (el texto libre capturado).
String etapaCobroNombre(AppLocalizations l10n, {String? tipoSistema, String? nombre}) {
  if (tipoSistema != null) return _etapaSistemaLabel(l10n, TipoEventoCobro.values.byName(tipoSistema));
  return nombre ?? '';
}

String _tipoReglaLabel(AppLocalizations l10n, TipoReglaEvento tipo) {
  return switch (tipo) {
    TipoReglaEvento.diaFijoDelMes => l10n.servicioCobroReglaDiaFijoDelMes,
    TipoReglaEvento.diasHabilesDespuesDe => l10n.servicioCobroReglaDiasHabilesDespuesDe,
    TipoReglaEvento.diasCalendarioDespuesDe => l10n.servicioCobroReglaDiasCalendarioDespuesDe,
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

/// Nombre del origen de una etapa (otra etapa de la misma vigencia, o
/// el origen virtual Cierre de periodo) — usado tanto por
/// `describirEtapa` como por el selector de referencia del formulario.
String _origenLabel(
  AppLocalizations l10n,
  List<ConfiguracionCobroEtapaData> todas, {
  required bool referenciaCierrePeriodo,
  String? etapaReferenciaId,
}) {
  if (referenciaCierrePeriodo) return l10n.servicioCobroOrigenCierrePeriodo;
  if (etapaReferenciaId == null) return '—';
  final referida = todas.where((e) => e.id == etapaReferenciaId).firstOrNull;
  if (referida == null) return '—';
  return etapaCobroNombre(l10n, tipoSistema: referida.tipoSistema, nombre: referida.nombre);
}

/// Describe una etapa en una sola línea legible — usado tanto para una
/// etapa ya persistida (consulta, historial) como para el estado de un
/// `EtapaCobroFormRow` todavía en captura (`EtapaEditState.aVistaPrevia`,
/// Etapa 15). Por eso `tipoRegla` no nulo **no** implica que los demás
/// campos de esa regla ya estén capturados — el usuario puede elegir
/// "Día fijo del mes" y todavía no haber tocado "Mes relativo": cada
/// `case` valida sus propios campos obligatorios (mismo criterio que
/// `ConfiguracionCobroEtapaValidator._validarRegla`) antes de leerlos,
/// nunca asume que ya están completos (hallazgo real de Marlon —
/// "Null check operator used on a null value" al capturar Emisión en
/// una Configuración de cobro nueva, con la regla elegida pero su mes
/// relativo todavía sin seleccionar). `todas` es la lista completa de
/// etapas de la misma vigencia (o del mismo lote en captura), para
/// resolver el nombre de la etapa referenciada.
String describirEtapaCobro(AppLocalizations l10n, ConfiguracionCobroEtapaData etapa, List<ConfiguracionCobroEtapaData> todas) {
  if (etapa.tipoRegla == null) return l10n.servicioCobroReglaPendiente;
  final tipo = TipoReglaEvento.values.byName(etapa.tipoRegla!);
  switch (tipo) {
    case TipoReglaEvento.diaFijoDelMes:
      if (etapa.mesRelativo == null || etapa.diaDelMes == null) return l10n.servicioCobroReglaPendiente;
      final mes = _mesRelativoLabel(l10n, MesRelativoCobro.values.byName(etapa.mesRelativo!));
      return '${l10n.servicioCobroCampoDiaDelMes} ${etapa.diaDelMes} — $mes';
    case TipoReglaEvento.nEsimoDiaSemanaDelMes:
      if (etapa.mesRelativo == null || etapa.diaSemana == null || etapa.ordinalSemana == null) {
        return l10n.servicioCobroReglaPendiente;
      }
      final mes = _mesRelativoLabel(l10n, MesRelativoCobro.values.byName(etapa.mesRelativo!));
      final ordinal = _ordinalLabel(l10n, OrdinalSemanaCobro.values.byName(etapa.ordinalSemana!));
      final dia = _diaSemanaLabel(l10n, DiaSemanaCobro.values.byName(etapa.diaSemana!));
      return '$ordinal $dia — $mes';
    case TipoReglaEvento.diasHabilesDespuesDe:
      if (etapa.offsetDias == null) return l10n.servicioCobroReglaPendiente;
      final origen = _origenLabel(
        l10n,
        todas,
        referenciaCierrePeriodo: etapa.referenciaCierrePeriodo,
        etapaReferenciaId: etapa.etapaReferenciaId,
      );
      return '${etapa.offsetDias} ${l10n.servicioCobroCampoOffsetDiasHabiles} — $origen';
    case TipoReglaEvento.diasCalendarioDespuesDe:
      if (etapa.offsetDias == null) return l10n.servicioCobroReglaPendiente;
      final origen = _origenLabel(
        l10n,
        todas,
        referenciaCierrePeriodo: etapa.referenciaCierrePeriodo,
        etapaReferenciaId: etapa.etapaReferenciaId,
      );
      if (etapa.offsetDias == 0) return '${l10n.servicioCobroEtapaMismoDia} — $origen';
      return '${etapa.offsetDias} ${l10n.servicioCobroCampoOffsetDiasCalendario} — $origen';
    case TipoReglaEvento.mismoDiaSemanaSiguienteA:
      if (etapa.diaSemana == null) return l10n.servicioCobroReglaPendiente;
      final dia = _diaSemanaLabel(l10n, DiaSemanaCobro.values.byName(etapa.diaSemana!));
      final origen = _origenLabel(
        l10n,
        todas,
        referenciaCierrePeriodo: etapa.referenciaCierrePeriodo,
        etapaReferenciaId: etapa.etapaReferenciaId,
      );
      return '$dia siguiente — $origen';
  }
}

/// Sección "Configuración de cobro" de Servicio — 1:1, así que se
/// muestra como una ficha resumen (no una tabla) con la vigencia
/// vigente (o, si todavía no ha empezado, la programada más próxima).
/// Desde la Etapa 15, el flujo posterior a la emisión se muestra como
/// una secuencia visual compacta (Cierre de periodo → Emisión →
/// etapa → etapa → ...) en vez de listar cada regla como bloque de
/// texto vertical — cada etapa resume su regla en una sola línea.
class ServicioConfiguracionCobroSection extends StatelessWidget {
  const ServicioConfiguracionCobroSection({
    required this.configuracionCobro,
    required this.deshabilitado,
    required this.onAgregar,
    required this.onCorregir,
    required this.onNuevaVigencia,
    required this.onCerrar,
    required this.onVerHistorial,
    super.key,
  });

  final ConfiguracionCobroConVigencia? configuracionCobro;
  final bool deshabilitado;
  final VoidCallback onAgregar;
  final VoidCallback onCorregir;
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

  /// Un eslabón de la secuencia visual — nombre + resumen de su regla
  /// en una sola línea compacta, nunca el bloque de texto vertical de
  /// antes.
  Widget _eslabon(BuildContext context, String nombre, String resumen) {
    final colors = context.colors;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(nombre, style: AppTypography.label.copyWith(color: colors.textPrimary)),
          Text(resumen, style: AppTypography.caption.copyWith(color: colors.textMuted)),
        ],
      ),
    );
  }

  Widget _flecha(BuildContext context) =>
      Padding(padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs), child: Icon(Icons.arrow_forward, size: 16, color: context.colors.textMuted));

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final configuracion = configuracionCobro;
    final fila = configuracion == null ? null : _filaVisible(configuracion);

    List<FechaEtapaCalculada>? fechas;
    if (configuracion != null && fila != null) {
      final mesInicioPeriodo = mesInicioDelPeriodoActual(diaInicioPeriodo: fila.diaInicioPeriodo, hoy: DateTime.now());
      final limites = calcularLimitesPeriodo(diaInicioPeriodo: fila.diaInicioPeriodo, mesInicioPeriodo: mesInicioPeriodo);
      fechas = _calcularFechasCobro.ejecutar(etapas: configuracion.etapas, mesInicioPeriodo: mesInicioPeriodo, periodoFin: limites.periodoFin);
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
          Text(l10n.servicioCobroSeccionFlujoTitulo, style: AppTypography.label.copyWith(color: colors.textMuted)),
          const SizedBox(height: AppSpacing.sm),
          RisegCard(
            variant: RisegCardVariant.subtle,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _eslabon(context, l10n.servicioCobroOrigenCierrePeriodo, ''),
                  for (final etapa in configuracion.etapas) ...[
                    _flecha(context),
                    _eslabon(
                      context,
                      etapaCobroNombre(l10n, tipoSistema: etapa.tipoSistema, nombre: etapa.nombre),
                      describirEtapaCobro(l10n, etapa, configuracion.etapas),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (fechas != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(l10n.servicioCobroFechasCalculadasTitulo, style: AppTypography.label.copyWith(color: colors.textMuted)),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xl,
              runSpacing: AppSpacing.sm,
              children: [
                for (final f in fechas)
                  if (f.fecha != null)
                    _dato(
                      context,
                      etapaCobroNombre(l10n, tipoSistema: f.tipoSistema, nombre: f.nombre),
                      _formatoFecha.format(f.fecha!),
                    ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              if (configuracion.esCorregible)
                RisegButton(
                  key: const Key('servicio_cobro_boton_corregir'),
                  label: l10n.servicioCobroBotonCorregir,
                  variant: RisegButtonVariant.ghost,
                  size: RisegButtonSize.compact,
                  onPressed: deshabilitado ? null : onCorregir,
                ),
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

/// Estado de edición de una etapa dentro del formulario — mezcla lo que
/// ya existía en la base de datos (si se está corrigiendo/registrando
/// nueva vigencia sobre una configuración con historia previa) con lo
/// que el usuario cambia en pantalla. `id` es estable dentro del lote
/// (generado aquí si es una etapa nueva) para que las referencias entre
/// etapas hermanas se puedan resolver antes de guardar.
class EtapaEditState {
  EtapaEditState({
    String? id,
    this.tipoSistema,
    String nombreInicial = '',
    required this.orden,
    this.tipoRegla,
    this.mesRelativo,
    int? diaDelMes,
    this.ordinalSemana,
    this.diaSemana,
    int? offsetDias,
    this.etapaReferenciaId,
    this.referenciaCierrePeriodo = false,
    this.expandido = false,
  })  : id = id ?? const Uuid().v4(),
        nombreCtrl = TextEditingController(text: nombreInicial),
        diaDelMesCtrl = TextEditingController(text: diaDelMes?.toString() ?? ''),
        offsetDiasCtrl = TextEditingController(text: offsetDias?.toString() ?? '');

  factory EtapaEditState.desdeExistente(ConfiguracionCobroEtapaData e) => EtapaEditState(
        id: e.id,
        tipoSistema: e.tipoSistema == null ? null : TipoEventoCobro.values.byName(e.tipoSistema!),
        nombreInicial: e.nombre ?? '',
        orden: e.orden,
        tipoRegla: e.tipoRegla == null ? null : TipoReglaEvento.values.byName(e.tipoRegla!),
        mesRelativo: e.mesRelativo == null ? null : MesRelativoCobro.values.byName(e.mesRelativo!),
        diaDelMes: e.diaDelMes,
        ordinalSemana: e.ordinalSemana == null ? null : OrdinalSemanaCobro.values.byName(e.ordinalSemana!),
        diaSemana: e.diaSemana == null ? null : DiaSemanaCobro.values.byName(e.diaSemana!),
        offsetDias: e.offsetDias,
        etapaReferenciaId: e.etapaReferenciaId,
        referenciaCierrePeriodo: e.referenciaCierrePeriodo,
      );

  final String id;
  TipoEventoCobro? tipoSistema;
  final TextEditingController nombreCtrl;
  int orden;
  TipoReglaEvento? tipoRegla;
  MesRelativoCobro? mesRelativo;
  final TextEditingController diaDelMesCtrl;
  OrdinalSemanaCobro? ordinalSemana;
  DiaSemanaCobro? diaSemana;
  final TextEditingController offsetDiasCtrl;
  String? etapaReferenciaId;
  bool referenciaCierrePeriodo;
  bool expandido = false;

  /// Emisión es obligatoria y no removible (Etapa 15) — la única etapa
  /// de sistema que la UI nunca deja quitar.
  bool get removible => tipoSistema != TipoEventoCobro.emision;

  String nombreVisible(AppLocalizations l10n) => etapaCobroNombre(l10n, tipoSistema: tipoSistema?.name, nombre: nombreCtrl.text);

  /// Vista de solo lectura equivalente a la fila real — usada
  /// únicamente para reutilizar `describirEtapaCobro` sobre el estado
  /// del formulario todavía no guardado (nunca se persiste).
  ConfiguracionCobroEtapaData aVistaPrevia() => ConfiguracionCobroEtapaData(
        id: id,
        configuracionCobroVigenciaId: '',
        tipoSistema: tipoSistema?.name,
        nombre: nombreCtrl.text,
        orden: orden,
        tipoRegla: tipoRegla?.name,
        mesRelativo: mesRelativo?.name,
        diaDelMes: int.tryParse(diaDelMesCtrl.text.trim()),
        ordinalSemana: ordinalSemana?.name,
        diaSemana: diaSemana?.name,
        offsetDias: int.tryParse(offsetDiasCtrl.text.trim()),
        etapaReferenciaId: referenciaCierrePeriodo ? null : etapaReferenciaId,
        referenciaCierrePeriodo: referenciaCierrePeriodo,
      );

  EtapaCobroBorrador aBorrador() => EtapaCobroBorrador(
        id: id,
        tipoSistema: tipoSistema,
        nombre: tipoSistema == null ? nombreCtrl.text.trim() : null,
        orden: orden,
        tipoRegla: tipoRegla,
        mesRelativo: mesRelativo,
        diaDelMes: int.tryParse(diaDelMesCtrl.text.trim()),
        ordinalSemana: ordinalSemana,
        diaSemana: diaSemana,
        offsetDias: int.tryParse(offsetDiasCtrl.text.trim()),
        etapaReferenciaId: referenciaCierrePeriodo ? null : etapaReferenciaId,
        referenciaCierrePeriodo: referenciaCierrePeriodo,
      );

  void dispose() {
    nombreCtrl.dispose();
    diaDelMesCtrl.dispose();
    offsetDiasCtrl.dispose();
  }
}

/// Una fila de la secuencia editable — encabezado compacto (nombre +
/// resumen + reordenar/quitar) siempre visible; el formulario completo
/// de la regla solo se muestra si `etapa.expandido`. `origenes` son las
/// demás etapas del lote actual, para el selector "Depende de".
class EtapaCobroFormRow extends StatefulWidget {
  const EtapaCobroFormRow({
    required this.etapa,
    required this.origenes,
    required this.onCambio,
    required this.onQuitar,
    required this.onSubir,
    required this.onBajar,
    super.key,
  });

  final EtapaEditState etapa;
  final List<EtapaEditState> origenes;
  final VoidCallback onCambio;
  final VoidCallback? onQuitar;
  final VoidCallback? onSubir;
  final VoidCallback? onBajar;

  @override
  State<EtapaCobroFormRow> createState() => _EtapaCobroFormRowState();
}

class _EtapaCobroFormRowState extends State<EtapaCobroFormRow> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final etapa = widget.etapa;
    final esSistema = etapa.tipoSistema != null;

    return RisegCard(
      key: Key('etapa_cobro_fila_${etapa.id}'),
      variant: RisegCardVariant.subtle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => etapa.expandido = !etapa.expandido),
            child: Row(
              children: [
                Icon(etapa.expandido ? Icons.expand_less : Icons.expand_more, size: 20, color: colors.textMuted),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        esSistema ? etapa.nombreVisible(l10n) : (etapa.nombreCtrl.text.isEmpty ? l10n.servicioCobroCampoNombreEtapa : etapa.nombreCtrl.text),
                        style: AppTypography.label.copyWith(color: colors.textPrimary),
                      ),
                      Text(
                        describirEtapaCobro(l10n, etapa.aVistaPrevia(), [for (final o in widget.origenes) o.aVistaPrevia()]),
                        style: AppTypography.caption.copyWith(color: colors.textMuted),
                      ),
                    ],
                  ),
                ),
                if (widget.onSubir != null)
                  IconButton(
                    key: Key('etapa_cobro_boton_subir_${etapa.id}'),
                    tooltip: l10n.servicioCobroBotonSubirEtapa,
                    icon: const Icon(Icons.arrow_upward, size: 18),
                    visualDensity: VisualDensity.compact,
                    onPressed: widget.onSubir,
                  ),
                if (widget.onBajar != null)
                  IconButton(
                    key: Key('etapa_cobro_boton_bajar_${etapa.id}'),
                    tooltip: l10n.servicioCobroBotonBajarEtapa,
                    icon: const Icon(Icons.arrow_downward, size: 18),
                    visualDensity: VisualDensity.compact,
                    onPressed: widget.onBajar,
                  ),
                if (widget.onQuitar != null)
                  IconButton(
                    key: Key('etapa_cobro_boton_quitar_${etapa.id}'),
                    tooltip: l10n.servicioCobroBotonQuitarEtapa,
                    icon: const Icon(Icons.close, size: 18),
                    visualDensity: VisualDensity.compact,
                    onPressed: widget.onQuitar,
                  ),
              ],
            ),
          ),
          if (etapa.expandido) ...[
            const SizedBox(height: AppSpacing.sm),
            if (!esSistema) ...[
              RisegTextField(
                label: l10n.servicioCobroCampoNombreEtapa,
                controller: etapa.nombreCtrl,
                onChanged: (_) => widget.onCambio(),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            RisegSelect<TipoReglaEvento>(
              label: l10n.servicioCobroCampoTipoRegla,
              value: etapa.tipoRegla,
              items: [for (final t in TipoReglaEvento.values) RisegSelectItem(value: t, label: _tipoReglaLabel(l10n, t))],
              onChanged: (valor) {
                setState(() => etapa.tipoRegla = valor);
                widget.onCambio();
              },
            ),
            if (etapa.tipoRegla == TipoReglaEvento.diaFijoDelMes || etapa.tipoRegla == TipoReglaEvento.nEsimoDiaSemanaDelMes) ...[
              const SizedBox(height: AppSpacing.sm),
              RisegSelect<MesRelativoCobro>(
                label: l10n.servicioCobroCampoMesRelativo,
                value: etapa.mesRelativo,
                items: [
                  RisegSelectItem(value: MesRelativoCobro.actual, label: l10n.servicioCobroMesRelativoActual),
                  RisegSelectItem(value: MesRelativoCobro.siguiente, label: l10n.servicioCobroMesRelativoSiguiente),
                ],
                onChanged: (valor) {
                  setState(() => etapa.mesRelativo = valor);
                  widget.onCambio();
                },
              ),
            ],
            if (etapa.tipoRegla == TipoReglaEvento.diaFijoDelMes) ...[
              const SizedBox(height: AppSpacing.sm),
              RisegTextField(
                label: l10n.servicioCobroCampoDiaDelMes,
                controller: etapa.diaDelMesCtrl,
                keyboardType: TextInputType.number,
                onChanged: (_) => widget.onCambio(),
              ),
            ],
            if (etapa.tipoRegla == TipoReglaEvento.nEsimoDiaSemanaDelMes || etapa.tipoRegla == TipoReglaEvento.mismoDiaSemanaSiguienteA) ...[
              const SizedBox(height: AppSpacing.sm),
              RisegSelect<DiaSemanaCobro>(
                label: l10n.servicioCobroCampoDiaSemana,
                value: etapa.diaSemana,
                items: [for (final d in DiaSemanaCobro.values) RisegSelectItem(value: d, label: _diaSemanaLabel(l10n, d))],
                onChanged: (valor) {
                  setState(() => etapa.diaSemana = valor);
                  widget.onCambio();
                },
              ),
            ],
            if (etapa.tipoRegla == TipoReglaEvento.nEsimoDiaSemanaDelMes) ...[
              const SizedBox(height: AppSpacing.sm),
              RisegSelect<OrdinalSemanaCobro>(
                label: l10n.servicioCobroCampoOrdinalSemana,
                value: etapa.ordinalSemana,
                items: [for (final o in OrdinalSemanaCobro.values) RisegSelectItem(value: o, label: _ordinalLabel(l10n, o))],
                onChanged: (valor) {
                  setState(() => etapa.ordinalSemana = valor);
                  widget.onCambio();
                },
              ),
            ],
            if (etapa.tipoRegla == TipoReglaEvento.diasHabilesDespuesDe || etapa.tipoRegla == TipoReglaEvento.diasCalendarioDespuesDe) ...[
              const SizedBox(height: AppSpacing.sm),
              RisegTextField(
                label: etapa.tipoRegla == TipoReglaEvento.diasHabilesDespuesDe
                    ? l10n.servicioCobroCampoOffsetDiasHabiles
                    : l10n.servicioCobroCampoOffsetDiasCalendario,
                controller: etapa.offsetDiasCtrl,
                keyboardType: TextInputType.number,
                onChanged: (_) => widget.onCambio(),
              ),
            ],
            if (etapa.tipoRegla == TipoReglaEvento.diasHabilesDespuesDe ||
                etapa.tipoRegla == TipoReglaEvento.diasCalendarioDespuesDe ||
                etapa.tipoRegla == TipoReglaEvento.mismoDiaSemanaSiguienteA) ...[
              const SizedBox(height: AppSpacing.sm),
              RisegSelect<String>(
                label: l10n.servicioCobroCampoEventoReferencia,
                value: etapa.referenciaCierrePeriodo ? _origenCierrePeriodoValor : etapa.etapaReferenciaId,
                items: [
                  RisegSelectItem(value: _origenCierrePeriodoValor, label: l10n.servicioCobroOrigenCierrePeriodo),
                  for (final o in widget.origenes.where((o) => o.id != etapa.id))
                    RisegSelectItem(value: o.id, label: o.nombreVisible(l10n)),
                ],
                onChanged: (valor) {
                  setState(() {
                    if (valor == _origenCierrePeriodoValor) {
                      etapa.referenciaCierrePeriodo = true;
                      etapa.etapaReferenciaId = null;
                    } else {
                      etapa.referenciaCierrePeriodo = false;
                      etapa.etapaReferenciaId = valor;
                    }
                  });
                  widget.onCambio();
                },
              ),
            ],
          ],
        ],
      ),
    );
  }
}

const _origenCierrePeriodoValor = '__cierre_periodo__';

/// Contenido del diálogo de alta/nueva-vigencia de la Configuración de
/// cobro — captura las condiciones de la vigencia junto con su flujo
/// completo de etapas (Etapa 15: secuencia dinámica, no 3 formularios
/// fijos). `valoresIniciales`/`etapasIniciales` prellenan todo con la
/// vigencia actual al registrar una nueva vigencia o corregir; `null`
/// en el alta.
class ServicioConfiguracionCobroForm extends StatefulWidget {
  const ServicioConfiguracionCobroForm({
    required this.frecuencias,
    required this.entidadesFiscales,
    required this.contactos,
    required this.portales,
    required this.onCambio,
    this.valoresIniciales,
    this.etapasIniciales = const [],
    this.errores = const [],
    this.errorGeneral,
    super.key,
  });

  final List<CatalogoItem> frecuencias;
  final List<EntidadFiscalData> entidadesFiscales;

  /// Contactos del Cliente propietario del Servicio — fuente de verdad
  /// de los correos de envío (Etapa 15): solo los que ya tienen
  /// `correo` capturado se ofrecen en el selector múltiple; nunca se
  /// vuelve a pedir escribir uno ya registrado.
  final List<ContactoData> contactos;

  /// Portales del Cliente propietario del Servicio (Etapa 15) — activos
  /// y archivados; el formulario filtra a solo activos para el
  /// selector (mismo criterio que `entidadesFiscales` en
  /// `servicio_expediente_screen.dart`).
  final List<ClientePortalData> portales;
  final void Function(ConfiguracionCobroBorrador borrador, List<EtapaCobroBorrador> etapas) onCambio;
  final ConfiguracionCobroVigenciaData? valoresIniciales;
  final List<ConfiguracionCobroEtapaData> etapasIniciales;

  /// Errores del último intento de guardar (Etapa 15) — `RisegDialog`
  /// reconstruye este formulario con el mismo `contentBuilder` en cada
  /// intento, así que el llamador pasa aquí lo que devolvió el caso de
  /// uso para que cada campo muestre su propio `errorText` específico,
  /// en vez del mensaje genérico único que se mostraba antes.
  final List<ErrorConfiguracionCobro> errores;

  /// Error que no pertenece a ningún campo — reglas de las etapas, o un
  /// fallo al persistir. Se muestra DENTRO del formulario, arriba de
  /// todo, y el diálogo permanece abierto con la captura intacta (mismo
  /// criterio que el alta de usuario). Antes, un fallo al guardar
  /// cerraba el diálogo y tiraba todo lo capturado, dejando solo un
  /// snackbar genérico — así se reportó el caso MORGAN ATLACOMULCO.
  final String? errorGeneral;

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
  String? _clientePortalId;
  late final _cuentaBancariaController = TextEditingController();
  late final _observacionesController = TextEditingController();
  late final _nuevoCorreoController = TextEditingController();
  late List<String> _correos;

  late List<EtapaEditState> _etapas;

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
      _clientePortalId = inicial.clientePortalId;
      _cuentaBancariaController.text = inicial.cuentaBancaria ?? '';
      _observacionesController.text = inicial.observaciones ?? '';
      // Nota deliberada: `fechaInicioVigencia` nunca se prellena — la
      // fecha de una nueva vigencia siempre debe elegirse de forma
      // explícita (mismo criterio que Configuración comercial).
    }

    _etapas = [for (final e in widget.etapasIniciales) EtapaEditState.desdeExistente(e)]
      ..sort((a, b) => a.orden.compareTo(b.orden));
    // Emisión siempre presente y nunca removible (Etapa 15) — si la
    // vigencia inicial no traía ninguna (alta nueva), se agrega aquí.
    if (!_etapas.any((e) => e.tipoSistema == TipoEventoCobro.emision)) {
      _etapas.insert(0, EtapaEditState(tipoSistema: TipoEventoCobro.emision, orden: 0, expandido: true));
      _reordenar();
    }

    // Preselección automática (Etapa 15, requisito explícito de Marlon):
    // con exactamente un portal activo, se usa sin pedir que el usuario
    // lo elija — nunca se sobreescribe un `clientePortalId` ya capturado
    // (edición/corrección de una vigencia existente).
    if (_clientePortalId == null && _portalesActivos.length == 1) {
      _clientePortalId = _portalesActivos.single.id;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => _notificar());
  }

  List<ClientePortalData> get _portalesActivos =>
      widget.portales.where((p) => p.cicloVidaRegistro == CicloVidaRegistro.activo.name).toList();

  @override
  void dispose() {
    _diaInicioPeriodoController.dispose();
    _cuentaBancariaController.dispose();
    _observacionesController.dispose();
    _nuevoCorreoController.dispose();
    for (final e in _etapas) {
      e.dispose();
    }
    super.dispose();
  }

  void _reordenar() {
    for (var i = 0; i < _etapas.length; i++) {
      _etapas[i].orden = i;
    }
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
        clientePortalId: _clientePortalId,
        cuentaBancaria: _cuentaBancariaController.text,
        observaciones: _observacionesController.text,
        correos: List.unmodifiable(_correos),
      ),
      [for (final e in _etapas) e.aBorrador()],
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

  /// Contactos del Cliente con `correo` capturado — la fuente del
  /// selector múltiple (Etapa 15). Nunca se vuelve a pedir escribir a
  /// mano un correo que ya vive en un Contacto.
  List<ContactoData> get _contactosConCorreo =>
      widget.contactos.where((c) => c.correo != null && c.correo!.isNotEmpty).toList();

  void _alternarCorreoContacto(String correo, bool seleccionado) {
    setState(() {
      if (seleccionado) {
        if (!_correos.contains(correo)) _correos.add(correo);
      } else {
        _correos.remove(correo);
      }
    });
    _notificar();
  }

  /// Tipos de sistema que todavía tiene sentido ofrecer al agregar una
  /// etapa nueva — Emisión ya está forzada (única, no removible) y
  /// `procesamiento` es exclusivamente de compatibilidad histórica
  /// (nunca se ofrece en captura nueva, ver `TipoEventoCobro`); el resto
  /// se ofrece solo si esta vigencia todavía no lo tiene (a lo más una
  /// etapa por `tipoSistema`, mismo criterio que
  /// `ConfiguracionCobroEtapaValidator`).
  /// `complementoPago` se retira de la captura NUEVA (decisión ② de
  /// Marlon, etapa "Complemento dependiente del Pago real"): era una
  /// fecha de calendario calculada desde el inicio del periodo, sin
  /// ninguna relación con el Pago que realmente origina la obligación
  /// fiscal. La única fuente de verdad es
  /// `Pago + AplicacionPago + CuentaPorCobrar PPD + ComplementoPago`
  /// (ver `complemento_pago_derivado.dart`).
  ///
  /// El enum, las filas y los hitos históricos se CONSERVAN intactos —
  /// significaron una fecha que en su momento se configuró así, y siguen
  /// siendo evidencia de eso. `_etapaSistemaLabel` la sigue resolviendo,
  /// de modo que una vigencia antigua que la tenga se abre y se
  /// renderiza igual que siempre; simplemente ya no se puede agregar.
  static const _tiposSistemaRetirados = {
    TipoEventoCobro.emision, // ya está forzada, única y no removible
    TipoEventoCobro.procesamiento, // compatibilidad histórica
    TipoEventoCobro.complementoPago, // deja de ser fuente de verdad
  };

  List<TipoEventoCobro> get _tiposSistemaOfrecidos => [
        for (final t in TipoEventoCobro.values)
          if (!_tiposSistemaRetirados.contains(t) && !_etapas.any((e) => e.tipoSistema == t)) t,
      ];

  void _agregarEtapa({TipoEventoCobro? tipoSistema}) {
    setState(() {
      _etapas.add(EtapaEditState(tipoSistema: tipoSistema, orden: _etapas.length, expandido: true));
    });
    _notificar();
  }

  void _quitarEtapa(EtapaEditState etapa) {
    setState(() {
      _etapas.remove(etapa);
      etapa.dispose();
      _reordenar();
    });
    _notificar();
  }

  void _mover(int indice, int delta) {
    final destino = indice + delta;
    if (destino < 0 || destino >= _etapas.length) return;
    setState(() {
      final etapa = _etapas.removeAt(indice);
      _etapas.insert(destino, etapa);
      _reordenar();
    });
    _notificar();
  }

  String? _errorDe(CampoConfiguracionCobro campo) {
    final error = errorParaCampoConfiguracionCobroForm(widget.errores, campo);
    if (error == null) return null;
    return mensajeErrorConfiguracionCobro(AppLocalizations.of(context)!, error);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    // Recibo de pago no usa método SAT — fijarlo automáticamente en vez
    // de solo validarlo al guardar hace imposible volver a capturar el
    // error real de Residencial Tikal (Etapa 15): antes el formulario
    // dejaba elegir PUE/PPD sin importar el tipo de documento.
    final metodoBloqueado = _tipoDocumento == TipoDocumentoCobro.reciboDePago;
    // PPD exige complemento — igual, se fija en vez de solo rechazarlo.
    final complementoBloqueado = _metodo == MetodoPagoCobro.ppd;
    // …y ningún otro método lo admite: la obligación fiscal sólo existe
    // en PPD (`cuentaRequiereComplemento`). Con PUE/No aplica el control
    // queda apagado y explicado, en vez de dejar capturar un `true`
    // inerte.
    final complementoNoAplica = _metodo != null && _metodo != MetodoPagoCobro.ppd;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.errorGeneral != null) ...[
          RisegCard(
            key: const Key('configuracion_cobro_error_general'),
            variant: RisegCardVariant.subtle,
            child: Row(
              children: [
                Icon(Icons.error_outline, size: 20, color: colors.error),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    widget.errorGeneral!,
                    style: AppTypography.body.copyWith(color: colors.error),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        RisegSelect<TipoDocumentoCobro>(
          label: l10n.servicioCobroCampoTipoDocumento,
          value: _tipoDocumento,
          errorText: _errorDe(CampoConfiguracionCobro.tipoDocumento),
          items: [
            RisegSelectItem(value: TipoDocumentoCobro.cfdi, label: l10n.servicioCobroTipoDocumentoCfdi),
            RisegSelectItem(value: TipoDocumentoCobro.reciboDePago, label: l10n.servicioCobroTipoDocumentoReciboDePago),
          ],
          onChanged: (valor) {
            setState(() {
              _tipoDocumento = valor;
              if (valor == TipoDocumentoCobro.reciboDePago) _metodo = MetodoPagoCobro.noAplica;
            });
            _notificar();
          },
        ),
        const SizedBox(height: AppSpacing.md),
        RisegSelect<String>(
          label: l10n.servicioCobroCampoFrecuencia,
          value: _frecuenciaId,
          errorText: _errorDe(CampoConfiguracionCobro.frecuencia),
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
          errorText: _errorDe(CampoConfiguracionCobro.diaInicioPeriodo),
          onChanged: (_) => _notificar(),
        ),
        const SizedBox(height: AppSpacing.md),
        RisegSelect<AgrupacionCobro>(
          label: l10n.servicioCobroCampoAgrupacion,
          value: _agrupacion,
          errorText: _errorDe(CampoConfiguracionCobro.agrupacion),
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
          enabled: !metodoBloqueado,
          errorText: _errorDe(CampoConfiguracionCobro.metodo),
          helperText: metodoBloqueado ? l10n.servicioCobroAyudaMetodoBloqueadoRecibo : null,
          items: [
            RisegSelectItem(value: MetodoPagoCobro.pue, label: l10n.servicioCobroMetodoPue),
            RisegSelectItem(value: MetodoPagoCobro.ppd, label: l10n.servicioCobroMetodoPpd),
            RisegSelectItem(value: MetodoPagoCobro.noAplica, label: l10n.servicioCobroMetodoNoAplica),
          ],
          onChanged: (valor) {
            setState(() {
              _metodo = valor;
              // Sólo PPD genera obligación de Complemento. PPD la fuerza;
              // cualquier otro método la apaga — antes PUE dejaba el
              // switch encendido y se guardaba un `true` que el resto del
              // sistema ignoraba (ver `ConfiguracionCobroValidator`).
              if (valor == MetodoPagoCobro.ppd) {
                _requiereComplemento = true;
              } else {
                _requiereComplemento = false;
              }
            });
            _notificar();
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l10n.servicioCobroCampoRequiereComplemento, style: AppTypography.body.copyWith(color: colors.textPrimary)),
                  if (complementoNoAplica)
                    Text(
                      l10n.servicioCobroAyudaComplementoSoloPpd,
                      style: AppTypography.caption.copyWith(color: colors.textMuted),
                    ),
                ],
              ),
            ),
            Switch(
              key: const Key('servicio_cobro_switch_requiere_complemento'),
              value: _requiereComplemento,
              // Apagado en ambos extremos: PPD lo exige, el resto no lo
              // admite. Sólo queda editable si aún no se eligió método.
              onChanged: complementoBloqueado || complementoNoAplica
                  ? null
                  : (valor) {
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
          errorText: _errorDe(CampoConfiguracionCobro.entidadFiscal),
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
          errorText: _errorDe(CampoConfiguracionCobro.fechaInicioVigencia),
          onChanged: (valor) {
            setState(() => _fechaInicioVigencia = valor);
            _notificar();
          },
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(l10n.servicioCobroSeccionFlujoTitulo, style: AppTypography.label.copyWith(color: colors.textMuted)),
        const SizedBox(height: AppSpacing.xs),
        for (var i = 0; i < _etapas.length; i++) ...[
          EtapaCobroFormRow(
            key: ValueKey(_etapas[i].id),
            etapa: _etapas[i],
            origenes: _etapas,
            onCambio: _notificar,
            onQuitar: _etapas[i].removible ? () => _quitarEtapa(_etapas[i]) : null,
            onSubir: i == 0 ? null : () => _mover(i, -1),
            onBajar: i == _etapas.length - 1 ? null : () => _mover(i, 1),
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            // Pago esperado/Complemento de pago son etapas de sistema
            // con significado propio para CxC/Agenda (compatibilidad
            // legacy vía `fechaDeEtapaSistema`) — se ofrecen aparte de
            // "Agregar etapa" (siempre personalizada) para que una
            // Configuración de cobro nueva pueda seguir capturando
            // "Pago esperado" tal como lo hacía el modelo fijo anterior.
            for (final tipo in _tiposSistemaOfrecidos)
              RisegButton(
                key: Key('servicio_cobro_boton_agregar_etapa_sistema_${tipo.name}'),
                label: _etapaSistemaLabel(l10n, tipo),
                variant: RisegButtonVariant.secondary,
                size: RisegButtonSize.compact,
                icon: Icons.add,
                onPressed: () => _agregarEtapa(tipoSistema: tipo),
              ),
            RisegButton(
              key: const Key('servicio_cobro_boton_agregar_etapa'),
              label: l10n.servicioCobroBotonAgregarEtapa,
              variant: RisegButtonVariant.secondary,
              size: RisegButtonSize.compact,
              icon: Icons.add,
              onPressed: () => _agregarEtapa(),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(l10n.servicioCobroSeccionPortalTitulo, style: AppTypography.label.copyWith(color: colors.textMuted)),
        const SizedBox(height: AppSpacing.xs),
        Builder(builder: (context) {
          final activos = _portalesActivos;
          if (activos.isEmpty) {
            return Text(
              key: const Key('servicio_cobro_sin_portal'),
              l10n.servicioCobroSinPortalConfigurado,
              style: AppTypography.caption.copyWith(color: colors.textMuted),
            );
          }
          final seleccionado = activos.where((p) => p.id == _clientePortalId).firstOrNull;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (activos.length == 1)
                Text(
                  key: const Key('servicio_cobro_portal_unico'),
                  '${activos.single.nombre} (${tipoPortalClienteLabel(l10n, TipoPortalCliente.values.byName(activos.single.tipo))})',
                  style: AppTypography.body.copyWith(color: colors.textPrimary),
                )
              else
                RisegSelect<String>(
                  key: const Key('servicio_cobro_selector_portal'),
                  label: l10n.servicioCobroCampoPortal,
                  value: _clientePortalId,
                  errorText: _errorDe(CampoConfiguracionCobro.clientePortal),
                  items: [
                    for (final p in activos)
                      RisegSelectItem(value: p.id, label: '${p.nombre} (${tipoPortalClienteLabel(l10n, TipoPortalCliente.values.byName(p.tipo))})'),
                  ],
                  onChanged: (valor) {
                    setState(() => _clientePortalId = valor);
                    _notificar();
                  },
                ),
              if (seleccionado != null && (seleccionado.url != null || seleccionado.usuario != null)) ...[
                const SizedBox(height: AppSpacing.xs),
                if (seleccionado.url != null)
                  Text('${l10n.servicioCobroCampoPortalUrl}: ${seleccionado.url}', style: AppTypography.caption.copyWith(color: colors.textMuted)),
                if (seleccionado.usuario != null)
                  Text('${l10n.servicioCobroCampoPortalUsuario}: ${seleccionado.usuario}', style: AppTypography.caption.copyWith(color: colors.textMuted)),
              ],
            ],
          );
        }),
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
        const SizedBox(height: AppSpacing.sm),
        Text(l10n.servicioCobroSeccionCorreosContactosTitulo, style: AppTypography.body.copyWith(color: colors.textPrimary)),
        const SizedBox(height: AppSpacing.xs),
        if (_contactosConCorreo.isEmpty)
          Text(l10n.servicioCobroSinContactosConCorreo, style: AppTypography.caption.copyWith(color: colors.textMuted))
        else
          Column(
            children: [
              for (final contacto in _contactosConCorreo)
                CheckboxListTile(
                  key: Key('servicio_cobro_correo_contacto_${contacto.id}'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _correos.contains(contacto.correo),
                  title: Text(
                    contacto.puesto == null || contacto.puesto!.isEmpty ? contacto.nombre : '${contacto.nombre} — ${contacto.puesto}',
                    style: AppTypography.body.copyWith(color: colors.textPrimary),
                  ),
                  subtitle: Text(contacto.correo!, style: AppTypography.caption.copyWith(color: colors.textMuted)),
                  onChanged: (marcado) => _alternarCorreoContacto(contacto.correo!, marcado ?? false),
                ),
            ],
          ),
        const SizedBox(height: AppSpacing.sm),
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
        const SizedBox(height: AppSpacing.sm),
        Text(l10n.servicioCobroCampoOtroCorreoTitulo, style: AppTypography.caption.copyWith(color: colors.textMuted)),
        const SizedBox(height: AppSpacing.xs),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: RisegTextField(
                key: const Key('servicio_cobro_campo_otro_correo'),
                label: l10n.servicioCobroCampoNuevoCorreo,
                controller: _nuevoCorreoController,
                keyboardType: TextInputType.emailAddress,
                onChanged: (_) {},
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            RisegButton(
              key: const Key('servicio_cobro_boton_agregar_otro_correo'),
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
