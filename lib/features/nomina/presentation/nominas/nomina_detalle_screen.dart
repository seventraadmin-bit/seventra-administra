import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/dashboard/presentation/dashboard_controller.dart';
import 'package:riseg_one/features/descuentos_personal/presentation/descuentos_personal_controller.dart';
import 'package:riseg_one/features/finanzas/presentation/cuentas_financieras/cuentas_financieras_controller.dart';
import 'package:riseg_one/features/finanzas/presentation/egresos/egresos_controller.dart';
import 'package:riseg_one/features/finanzas/presentation/pagos/pagos_list_screen.dart' show formatoCentavosPago;
import 'package:riseg_one/features/finanzas/presentation/planeacion/planeacion_financiera_controller.dart';
import 'package:riseg_one/features/finanzas/presentation/resumen/resumen_financiero_controller.dart';
import 'package:riseg_one/features/nomina/data/tables/nomina_empleado_table.dart';
import 'package:riseg_one/features/nomina/data/tables/nomina_table.dart' show TipoPeriodoNomina;
import 'package:riseg_one/features/nomina/domain/usecases/actualizar_nomina_desde_personal_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/cerrar_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/generar_nomina_dispersion_pdf_usecase.dart';
import 'package:riseg_one/features/organizacion/organizacion_providers.dart' show attachmentRepositoryProvider;
import 'package:riseg_one/features/personal/personal_providers.dart' show empleadoRepositoryProvider;
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import 'package:riseg_one/features/usuarios/usuarios_providers.dart' show permissionServiceProvider;

import '../../nomina_providers.dart';
import 'nominas_controller.dart';
import 'nominas_list_screen.dart' show nominaEstatusLabel, nominaEstatusTono;
import 'widgets/cancelar_nomina_dialog.dart';
import 'widgets/eliminar_cadena_prueba_nomina_dialog.dart';
import 'widgets/eliminar_nomina_fisicamente_dialog.dart';
import 'widgets/generar_nomina_dialog.dart' show nominaTipoPeriodoLabel;
import 'widgets/pago_nomina_detalle_dialog.dart';
import 'widgets/registrar_pago_nomina_dialog.dart';
import 'widgets/renglon_nomina_detalle_dialog.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');
const _mesesLargos = [
  'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
  'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
];

/// "{tipo de periodo} · {Mes largo} {año}" (Etapa 17) — solo para la
/// cabecera del expediente, más legible que el "{año}-{mes}" numérico
/// que conserva el listado (`periodoNominaTexto`, sin cambios: filas
/// escaneadas rápido se benefician del formato compacto).
String _periodoNominaLargoTexto(AppLocalizations l10n, NominaData nomina) {
  return '${nominaTipoPeriodoLabel(l10n, TipoPeriodoNomina.values.byName(nomina.tipoPeriodo))} · '
      '${_mesesLargos[nomina.mes - 1]} ${nomina.anio}';
}

String nominaEstatusPagoLabel(AppLocalizations l10n, String valor) {
  return switch (EstatusPagoNominaEmpleado.values.byName(valor)) {
    EstatusPagoNominaEmpleado.pendiente => l10n.nominaEstatusPagoPendiente,
    EstatusPagoNominaEmpleado.parcial => l10n.nominaEstatusPagoParcial,
    EstatusPagoNominaEmpleado.pagado => l10n.nominaEstatusPagoPagado,
  };
}

RisegStatusTone nominaEstatusPagoTono(String valor) {
  return switch (EstatusPagoNominaEmpleado.values.byName(valor)) {
    EstatusPagoNominaEmpleado.pendiente => RisegStatusTone.neutral,
    EstatusPagoNominaEmpleado.parcial => RisegStatusTone.warning,
    EstatusPagoNominaEmpleado.pagado => RisegStatusTone.success,
  };
}

/// Detalle de una Nómina (Etapa 6C) — el listado principal por Empleado,
/// con exactamente las columnas que pidió Marlon: No. empleado, nombre,
/// Servicio, días, base, percepciones, deducciones, total, Fiscal, No
/// fiscal, estado. Deliberadamente sin replicar el Excel como tabla
/// horizontal gigantesca — banco/CLABE/cálculo/tramos/movimientos viven
/// en el detalle de cada renglón (`RenglonNominaDetalleDialog`).
class NominaDetalleScreen extends ConsumerStatefulWidget {
  const NominaDetalleScreen({required this.nominaId, super.key});

  final String nominaId;

  @override
  ConsumerState<NominaDetalleScreen> createState() => _NominaDetalleScreenState();
}

class _NominaDetalleScreenState extends ConsumerState<NominaDetalleScreen> {
  NominaData? _nomina;
  List<NominaEmpleadoData> _renglones = const [];
  List<PagoNominaData> _pagos = const [];
  Set<String> _idsRequierenRevision = const {};

  /// Fotografía vigente del Empleado por `empleadoId` (Etapa 16,
  /// evolución visual) — `NominaEmpleadoData` es un snapshot puro
  /// (nombre/servicio/turno al momento de generar, ver el doc comment
  /// de esa tabla) y nunca tuvo columna de fotografía; esto SÍ es una
  /// consulta nueva, deliberadamente en LOTE (una sola vez, vía
  /// `listarPorIds`/`obtenerPorIds`, nunca una por renglón) — la foto
  /// es identidad visual del Empleado hoy, no parte del snapshot
  /// histórico de la Nómina.
  Map<String, String> _fotografiaPathPorEmpleadoId = const {};
  bool _cargando = true;
  bool _procesando = false;
  bool _bloqueadaEliminacionNormal = false;
  bool _generandoDispersionPdf = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final notifier = ref.read(nominasControllerProvider.notifier);
    final nomina = await notifier.obtenerPorId(widget.nominaId);
    final renglones = nomina == null ? <NominaEmpleadoData>[] : await notifier.listarEmpleados(widget.nominaId);
    // Re-evaluado contra el estado actual de Personal — no puede
    // derivarse solo de las columnas ya guardadas del renglón (ver el
    // doc comment de `EvaluarRenglonesRequierenRevisionUseCase`).
    final requierenRevision =
        nomina == null ? const <NominaEmpleadoData>[] : await notifier.renglonesQueRequierenRevision(widget.nominaId);
    final pagos = nomina == null ? const <PagoNominaData>[] : await notifier.listarPagos(widget.nominaId);

    final empleadoIds = {for (final r in renglones) r.empleadoId}.toList();
    final empleados = await ref.read(empleadoRepositoryProvider).listarPorIds(empleadoIds);
    final fotografiaIds = [
      for (final e in empleados)
        if (e.fotografiaAttachmentId != null) e.fotografiaAttachmentId!,
    ];
    final fotografias = await ref.read(attachmentRepositoryProvider).obtenerPorIds(fotografiaIds);
    final fotografiaPorAttachmentId = {for (final f in fotografias) f.id: f.path};
    final fotografiaPathPorEmpleadoId = {
      for (final e in empleados)
        if (e.fotografiaAttachmentId != null && fotografiaPorAttachmentId.containsKey(e.fotografiaAttachmentId))
          e.id: fotografiaPorAttachmentId[e.fotografiaAttachmentId]!,
    };

    // Solo relevante para el Usuario Maestro — determina si se ofrece
    // "Eliminar cadena de prueba" como alternativa (Etapa 15): esa
    // acción NUNCA se muestra si la eliminación física normal todavía
    // es posible (ver el doc comment de
    // `mostrarDialogoEliminarCadenaPruebaNomina`).
    final esMaestro = ref.read(sesionControllerProvider)?.esMaestro ?? false;
    final bloqueadaNormal = (esMaestro && nomina != null)
        ? (await ref.read(nominaRepositoryProvider).obtenerResumenEliminacionFisica(widget.nominaId)).bloqueado
        : false;

    if (!mounted) return;
    setState(() {
      _nomina = nomina;
      _renglones = renglones;
      _idsRequierenRevision = requierenRevision.map((r) => r.id).toSet();
      _pagos = pagos;
      _fotografiaPathPorEmpleadoId = fotografiaPathPorEmpleadoId;
      _bloqueadaEliminacionNormal = bloqueadaNormal;
      _cargando = false;
    });
  }

  Future<void> _abrirRegistrarPago() async {
    // Se pasan TODOS los renglones (Etapa 15, tabla interactiva de
    // dispersión) — no solo pendientes/parciales, para que los ya
    // `pagado` se muestren en verde y bloqueados en vez de
    // desaparecer de la tabla.
    final huboCambio = await showDialog<bool>(
      context: context,
      builder: (_) => RegistrarPagoNominaDialog(nominaId: widget.nominaId, renglones: _renglones),
    );
    if (huboCambio == true) {
      await _cargar();
      // Un lote de pago genera un Egreso real (y puede llevar una
      // Cuenta financiera, Etapa 19C) — Egresos/Cuentas
      // financieras/Resumen/Dashboard son providers ajenos que nunca
      // se enteran sin invalidar aquí (mismo hallazgo ya corregido
      // para Deudas/Compras/Ingresos/Egresos manuales).
      ref.invalidate(egresosControllerProvider);
      ref.invalidate(cuentasFinancierasControllerProvider);
      ref.invalidate(resumenFinancieroControllerProvider);
      ref.invalidate(planeacionFinancieraControllerProvider);
      ref.invalidate(dashboardControllerProvider);
    }
  }

  Future<void> _abrirPago(PagoNominaData pago) async {
    final cambio = await showDialog<bool>(context: context, builder: (_) => PagoNominaDetalleDialog(pagoNominaId: pago.id));
    if (cambio == true) await _cargar();
  }

  Future<void> _abrirRenglon(NominaEmpleadoData renglon) async {
    final cambio = await showDialog<bool>(
      context: context,
      builder: (_) => RenglonNominaDetalleDialog(nominaEmpleadoId: renglon.id, nominaCerrada: _nomina!.estatus != 'borrador'),
    );
    if (cambio == true) await _cargar();
  }

  Future<void> _actualizarDesdePersonal() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _procesando = true);
    final resultado = await ref.read(nominasControllerProvider.notifier).actualizarDesdePersonal(widget.nominaId);
    if (!mounted) return;
    setState(() => _procesando = false);

    switch (resultado) {
      case ActualizarNominaDesdePersonalExitoso(
          renglonesNuevos: final nuevos,
          renglonesActualizados: final actualizados,
          renglonesEliminados: final eliminados,
        ):
        // Pedido explícito: el usuario no podía saber, con solo "Nómina
        // actualizada", si un préstamo recién registrado realmente se
        // incorporó — el conteo real (nuevos/actualizados/eliminados)
        // ya lo devolvía el caso de uso, pero no se mostraba.
        RisegFeedback.showSuccess(
          context,
          l10n.actualizarNominaExitoConteo(nuevos, actualizados, eliminados),
        );
        await _cargar();
      case ActualizarNominaDesdePersonalNoExiste():
      case ActualizarNominaDesdePersonalErrorInesperado():
        RisegFeedback.showError(context, l10n.actualizarNominaErrorInesperado);
      case ActualizarNominaDesdePersonalNominaCerrada():
        RisegFeedback.showError(context, l10n.actualizarNominaNominaCerrada);
    }
  }

  Future<void> _cerrar() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmado = await RisegDialog.showConfirmation(
      context: context,
      title: l10n.cerrarNominaConfirmacionTitulo,
      message: l10n.cerrarNominaConfirmacionMensaje,
      confirmLabel: l10n.cerrarNominaConfirmacionConfirmar,
      cancelLabel: l10n.cerrarNominaConfirmacionCancelar,
    );
    if (confirmado != true || !mounted) return;

    setState(() => _procesando = true);
    final resultado = await ref.read(nominasControllerProvider.notifier).cerrar(widget.nominaId);
    if (!mounted) return;
    setState(() => _procesando = false);

    switch (resultado) {
      case CerrarNominaExitoso():
        RisegFeedback.showSuccess(context, l10n.cerrarNominaExito);
        await _cargar();
      case CerrarNominaSinEmpleados():
        RisegFeedback.showError(context, l10n.cerrarNominaSinEmpleados);
      case CerrarNominaDistribucionPendiente():
        RisegFeedback.showError(context, l10n.cerrarNominaDistribucionPendiente);
      case CerrarNominaDescuentosInventarioPendientes():
        RisegFeedback.showError(context, l10n.cerrarNominaDescuentosInventarioPendientes);
      case CerrarNominaDescuentosProgramadosPendientes():
        RisegFeedback.showError(context, l10n.cerrarNominaDescuentosProgramadosPendientes);
      case CerrarNominaRequiereRevision():
        RisegFeedback.showError(context, l10n.cerrarNominaRequiereRevision);
      case CerrarNominaYaCerrada():
        RisegFeedback.showError(context, l10n.cerrarNominaYaCerrada);
      case CerrarNominaNoExiste():
      case CerrarNominaErrorInesperado():
        RisegFeedback.showError(context, l10n.cerrarNominaErrorInesperado);
    }
  }

  Future<void> _generarDispersionPdf() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _generandoDispersionPdf = true);

    // Fallback si Empresa no tiene logotipo propio configurado: el
    // mismo asset oficial que ya usa el resto de la app (mismo
    // criterio que `AgendaDetalleDialog._generarReciboPdf`). El use
    // case es dominio puro y no conoce `rootBundle`, así que se
    // resuelve aquí, en la UI.
    Uint8List? logoFallbackBytes;
    try {
      final datosLogo = await rootBundle.load('assets/images/logo.png');
      logoFallbackBytes = datosLogo.buffer.asUint8List();
    } catch (_) {
      // Sin logotipo de respaldo disponible — el PDF se genera sin
      // logo, nunca se bloquea la generación por esto.
    }

    final resultado = await ref.read(nominasControllerProvider.notifier).generarDispersionPdf(
          widget.nominaId,
          logoFallbackBytes: logoFallbackBytes,
        );
    if (!mounted) return;
    setState(() => _generandoDispersionPdf = false);

    switch (resultado) {
      case GenerarNominaDispersionPdfExitoso():
        RisegFeedback.showSuccess(context, l10n.nominaDispersionPdfExito);
      case GenerarNominaDispersionPdfSinEmpleados():
        RisegFeedback.showError(context, l10n.nominaDispersionPdfSinEmpleados);
      case GenerarNominaDispersionPdfNominaEnBorrador():
      case GenerarNominaDispersionPdfNoExiste():
      case GenerarNominaDispersionPdfErrorInesperado():
        RisegFeedback.showError(context, l10n.nominaDispersionPdfError);
    }
  }

  Future<void> _cancelarNomina() async {
    final cancelada = await mostrarDialogoCancelarNomina(context, ref, widget.nominaId);
    if (!cancelada) return;
    ref.invalidate(nominasControllerProvider);
    ref.invalidate(descuentosPersonalControllerProvider);
    ref.invalidate(dashboardControllerProvider);
    if (mounted) context.pop();
  }

  Future<void> _eliminarFisicamente() async {
    final eliminada = await mostrarDialogoEliminarNominaFisicamente(context, ref, widget.nominaId);
    if (!eliminada) return;
    // Igual que en Compras: la eliminación pasa por
    // `eliminarNominaFisicamenteAutorizadoProvider` directo, nunca por
    // `NominasController` — esta pantalla es responsable de invalidar
    // el listado de Nóminas. También libera cuotas de Descuentos al
    // Personal (Etapa 15) — invalidar su controlador global para que
    // no se quede con saldos/estatus obsoletos.
    ref.invalidate(nominasControllerProvider);
    ref.invalidate(descuentosPersonalControllerProvider);
    // Etapa 4 (hallazgo real de auditoría): sin esto, borrar una
    // Nómina que era la "Próxima nómina" del Dashboard dejaba una
    // entrada fantasma hasta que algo ajeno invalidara el provider.
    ref.invalidate(dashboardControllerProvider);
    if (mounted) context.pop();
  }

  Future<void> _eliminarCadenaPrueba() async {
    final eliminada = await mostrarDialogoEliminarCadenaPruebaNomina(context, ref, widget.nominaId);
    if (!eliminada) return;
    ref.invalidate(nominasControllerProvider);
    ref.invalidate(descuentosPersonalControllerProvider);
    // Etapa 4: esta acción SÍ alcanza una Nómina Cerrada/Pagada —
    // mismo motivo que `_eliminarFisicamente` arriba.
    ref.invalidate(dashboardControllerProvider);
    if (mounted) context.pop();
  }

  // Etapa 17 — resumen real del expediente, agregado en memoria sobre
  // `_renglones`/`_pagos` YA cargados en bloque (`_cargar`): cero
  // consultas nuevas. Percepciones/Deducciones usan la MISMA fórmula
  // que ya usan las columnas de la tabla (nunca una segunda regla).
  int get _totalPercepciones => _renglones.fold(0, (s, r) => s + r.importeBase + r.bono + r.tiempoExtra);
  int get _totalDeducciones => _renglones.fold(0, (s, r) => s + r.prestamo + r.descuentoPorFaltas + r.otrosDescuentos);

  /// Suma de `totalAPagar` — el MISMO valor que ya usa la columna
  /// "Neto" de la tabla de abajo (nunca una segunda fórmula): a
  /// diferencia de `_totalPercepciones - _totalDeducciones`, este total
  /// sí refleja los descuentos de Inventario/Programados cuando
  /// existen (esa resta no está desglosada en ninguna de las dos
  /// tarjetas de arriba).
  int get _totalNeto => _renglones.fold(0, (s, r) => s + r.totalAPagar);

  /// Suma de `PagoNomina.montoTotal` con `estatus == registrado` — el
  /// dinero YA dispersado para esta Nómina, distinto del Neto total
  /// (`totalAPagar` agregado), que existe desde que la Nómina se
  /// genera aunque nada se haya pagado todavía.
  int get _totalPagado => _pagos.where((p) => p.estatus == 'registrado').fold(0, (s, p) => s + p.montoTotal);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final nomina = _nomina;

    if (_cargando) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (nomina == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.nominaDetalleCargaErrorTitulo)),
        body: RisegEmptyState(icon: Icons.error_outline, title: l10n.nominaDetalleCargaErrorTitulo, message: l10n.nominaDetalleCargaErrorMensaje),
      );
    }

    final esBorrador = nomina.estatus == 'borrador';
    final colors = context.colors;
    final hayRenglonesRequierenRevision = _idsRequierenRevision.isNotEmpty;
    final esMaestro = ref.watch(sesionControllerProvider)?.esMaestro ?? false;
    // Etapa 4 — Sección 9: solo Borrador o Cerrada-sin-pagos tienen una
    // salida controlada real (`CancelarNominaUseCase` ya lo revalida
    // por su cuenta) — nunca Cerrada-con-pagos ni Pagada.
    final puedeCancelarNomina =
        ref.read(permissionServiceProvider).hasCode('nomina.cancelar') && (esBorrador || (nomina.estatus == 'cerrada' && _pagos.isEmpty));

    return Scaffold(
      appBar: AppBar(title: Text(nomina.folio)),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Etapa 17: cabecera de expediente — periodo con mes largo
            // ("1ª quincena · Agosto 2026"), folio + fecha de pago en
            // una línea secundaria muted, badge de estatus. Las
            // acciones destructivas/excepcionales de Maestro (antes
            // botones rojos permanentes junto al badge) se mueven a un
            // menú ⋯ — mismas llamadas/autorización exactas.
            Text(_periodoNominaLargoTexto(l10n, nomina), style: AppTypography.heading2.copyWith(color: colors.textPrimary)),
            const SizedBox(height: 2),
            Text(
              '${nomina.folio} · ${l10n.nominaDetalleCampoFechaPago(_formatoFecha.format(nomina.fechaPagoOrdinaria))}',
              style: AppTypography.body.copyWith(color: colors.textMuted),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                RisegStatusBadge(label: nominaEstatusLabel(l10n, nomina.estatus), tone: nominaEstatusTono(nomina.estatus)),
                if (esBorrador) ...[
                  RisegButton(
                    label: l10n.nominaDetalleBotonActualizarDesdePersonal,
                    variant: RisegButtonVariant.secondary,
                    loading: _procesando,
                    onPressed: _actualizarDesdePersonal,
                  ),
                  RisegButton(
                    label: l10n.nominaDetalleBotonCerrar,
                    variant: RisegButtonVariant.primary,
                    loading: _procesando,
                    onPressed: _cerrar,
                  ),
                ],
                if (esMaestro || puedeCancelarNomina)
                  RisegActionsMenu(
                    menuKey: const Key('nomina_detalle_menu_acciones'),
                    actions: [
                      // Etapa 4 — visible para cualquiera con
                      // `nomina.cancelar`, no solo Maestro (a
                      // diferencia de las dos acciones de abajo).
                      if (puedeCancelarNomina)
                        RisegMenuAction(
                          key: const Key('nomina_detalle_boton_cancelar'),
                          label: l10n.nominaCancelarAccionMenu,
                          icon: Icons.cancel_outlined,
                          destructive: true,
                          onTap: _cancelarNomina,
                        ),
                      if (esMaestro) ...[
                        RisegMenuAction(
                          label: l10n.eliminacionFisicaAccionMenu,
                          icon: Icons.delete_forever_outlined,
                          destructive: true,
                          onTap: _eliminarFisicamente,
                        ),
                        // Alternativa (Etapa 15) — solo ofrecida cuando
                        // la eliminación física normal ya está
                        // bloqueada (Nómina Cerrada/Pagada, o con
                        // PagoNomina), y únicamente si el usuario
                        // confirma explícitamente en el diálogo que se
                        // trata de datos de prueba/error.
                        if (_bloqueadaEliminacionNormal)
                          RisegMenuAction(
                            key: const Key('nomina_detalle_boton_eliminar_cadena_prueba'),
                            label: l10n.nominaCadenaPruebaBoton,
                            icon: Icons.delete_forever_outlined,
                            destructive: true,
                            onTap: _eliminarCadenaPrueba,
                          ),
                      ],
                    ],
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                SizedBox(
                  width: 170,
                  child: RisegStatCard(dense: true, label: l10n.nominaDetalleResumenEmpleados, value: '${_renglones.length}'),
                ),
                SizedBox(
                  width: 170,
                  child: RisegStatCard(
                    dense: true,
                    label: l10n.nominaDetalleResumenPercepciones,
                    value: formatoCentavosPago(_totalPercepciones),
                  ),
                ),
                SizedBox(
                  width: 170,
                  child: RisegStatCard(
                    dense: true,
                    label: l10n.nominaDetalleResumenDeducciones,
                    value: formatoCentavosPago(_totalDeducciones),
                  ),
                ),
                SizedBox(
                  width: 170,
                  child: RisegStatCard(
                    dense: true,
                    label: l10n.nominaDetalleResumenNeto,
                    value: formatoCentavosPago(_totalNeto),
                  ),
                ),
                SizedBox(
                  width: 170,
                  child: RisegStatCard(dense: true, label: l10n.nominaDetalleResumenTotalPagado, value: formatoCentavosPago(_totalPagado)),
                ),
              ],
            ),
            if (hayRenglonesRequierenRevision) ...[
              const SizedBox(height: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(color: colors.errorBg, borderRadius: AppRadius.mdRadius),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_outlined, color: colors.error, size: AppSizes.iconSm),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(l10n.nominaDetalleBannerRequiereRevision, style: AppTypography.body.copyWith(color: colors.error)),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            Expanded(
              child: RisegTableBase<NominaEmpleadoData>(
                rows: _renglones,
                onRowTap: _abrirRenglon,
                emptyState: RisegEmptyState(title: l10n.nominaDetalleVacioTitulo, message: l10n.nominaDetalleVacioMensaje),
                hoverColor: colors.accentSoftBg,
                rowVerticalPadding: AppSpacing.sm + AppSpacing.xxs,
                rowActionsBuilder: (_) => Icon(Icons.chevron_right, size: AppSizes.iconMd, color: colors.textMuted),
                actionsWidth: 40,
                columns: [
                  // Etapa 16, evolución visual: "No. empleado" + "Nombre"
                  // se fusionan en una sola identidad visual (mismo
                  // `RisegEntityIdentity` de "Plantilla activa") — la
                  // fotografía es la del Empleado HOY (identidad visual),
                  // nunca parte del snapshot histórico de este renglón.
                  RisegColumn<NominaEmpleadoData>(
                    label: l10n.nominaDetalleColumnaNombre,
                    cellBuilder: (r) => RisegEntityIdentity(
                      primario: r.nombreCompleto,
                      secundario: l10n.personalActivoNumeroEmpleado(r.numeroEmpleado),
                      imagenPath: _fotografiaPathPorEmpleadoId[r.empleadoId],
                    ),
                  ),
                  RisegColumn<NominaEmpleadoData>(
                    label: l10n.nominaDetalleColumnaServicio,
                    cellBuilder: (r) => Text(r.servicioNombre ?? ''),
                  ),
                  RisegColumn<NominaEmpleadoData>(
                    label: l10n.nominaDetalleColumnaDias,
                    width: 70,
                    alignment: TextAlign.right,
                    cellBuilder: (r) => Text(r.diasPagables.toString()),
                  ),
                  RisegColumn<NominaEmpleadoData>(
                    label: l10n.nominaDetalleColumnaPercepciones,
                    width: 120,
                    alignment: TextAlign.right,
                    cellBuilder: (r) => Text(formatoCentavosPago(r.importeBase + r.bono + r.tiempoExtra)),
                  ),
                  RisegColumn<NominaEmpleadoData>(
                    label: l10n.nominaDetalleColumnaDeducciones,
                    width: 120,
                    alignment: TextAlign.right,
                    cellBuilder: (r) => Text(formatoCentavosPago(r.prestamo + r.descuentoPorFaltas + r.otrosDescuentos)),
                  ),
                  // Etapa 17: se retiran Base/Fiscal/No fiscal de la
                  // tabla principal (demasiadas columnas monetarias
                  // simultáneas) — el desglose completo, incluida la
                  // distribución Fiscal/No fiscal, sigue disponible al
                  // abrir el renglón (`RenglonNominaDetalleDialog`, ya
                  // lo mostraba). "Neto" es el mismo `totalAPagar`.
                  RisegColumn<NominaEmpleadoData>(
                    label: l10n.nominaDetalleColumnaNeto,
                    width: 120,
                    alignment: TextAlign.right,
                    cellBuilder: (r) => Text(
                      formatoCentavosPago(r.totalAPagar),
                      style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary),
                    ),
                  ),
                  RisegColumn<NominaEmpleadoData>(
                    label: l10n.nominaDetalleColumnaEstado,
                    width: 150,
                    cellBuilder: (r) {
                      if (_idsRequierenRevision.contains(r.id)) {
                        return Tooltip(
                          message: l10n.nominaDetalleRequiereRevisionTooltip,
                          child: RisegStatusBadge(label: l10n.nominaDetalleEstadoRequiereRevision, tone: RisegStatusTone.error),
                        );
                      }
                      return RisegStatusBadge(
                        label: nominaEstatusPagoLabel(l10n, r.estatusPago),
                        tone: r.distribucionPendienteRevision ? RisegStatusTone.error : nominaEstatusPagoTono(r.estatusPago),
                      );
                    },
                  ),
                ],
              ),
            ),
            if (!esBorrador) ...[
              const SizedBox(height: AppSpacing.lg),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.xs,
                children: [
                  Text(l10n.nominaDetalleSeccionPagos, style: AppTypography.heading3.copyWith(color: colors.textPrimary)),
                  Wrap(
                    spacing: AppSpacing.xs,
                    children: [
                      RisegButton(
                        label: l10n.nominaDispersionPdfBoton,
                        variant: RisegButtonVariant.secondary,
                        loading: _generandoDispersionPdf,
                        onPressed: _generarDispersionPdf,
                      ),
                      if (nomina.estatus == 'cerrada')
                        RisegButton(
                          label: l10n.nominaDetalleBotonRegistrarPago,
                          variant: RisegButtonVariant.secondary,
                          onPressed: _abrirRegistrarPago,
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                height: 220,
                child: RisegTableBase<PagoNominaData>(
                  rows: _pagos,
                  onRowTap: _abrirPago,
                  emptyState: RisegEmptyState(title: l10n.nominaDetalleSeccionPagos, message: l10n.nominaDetallePagosVacio),
                  hoverColor: colors.accentSoftBg,
                  rowActionsBuilder: (_) => Icon(Icons.chevron_right, size: AppSizes.iconMd, color: colors.textMuted),
                  actionsWidth: 40,
                  columns: [
                    RisegColumn<PagoNominaData>(
                      label: l10n.nominaDetallePagosColumnaFolio,
                      width: 130,
                      cellBuilder: (p) => Text(p.folioPagoNomina),
                    ),
                    RisegColumn<PagoNominaData>(
                      label: l10n.nominaDetallePagosColumnaFecha,
                      width: 110,
                      cellBuilder: (p) => Text(_formatoFecha.format(p.fechaPago)),
                    ),
                    RisegColumn<PagoNominaData>(
                      label: l10n.nominaDetallePagosColumnaMonto,
                      width: 130,
                      alignment: TextAlign.right,
                      cellBuilder: (p) => Text(formatoCentavosPago(p.montoTotal)),
                    ),
                    RisegColumn<PagoNominaData>(
                      label: l10n.nominaDetallePagosColumnaEstatus,
                      width: 130,
                      cellBuilder: (p) => RisegStatusBadge(label: pagoNominaEstatusLabel(l10n, p.estatus), tone: pagoNominaEstatusTono(p.estatus)),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
