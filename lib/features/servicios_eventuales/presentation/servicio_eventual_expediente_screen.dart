import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show EstatusAplicacionPago, EstatusPago;
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/presentation/cuentas_por_cobrar/widgets/cuenta_por_cobrar_detalle_dialog.dart';
import 'package:riseg_one/features/finanzas/presentation/egresos/widgets/egreso_detalle_dialog.dart';
import 'package:riseg_one/features/finanzas/presentation/pagos/pagos_list_screen.dart' show formatoCentavosPago;
import 'package:riseg_one/features/organizacion/organizacion_providers.dart';
import 'package:riseg_one/features/personal/personal_providers.dart';
import 'package:riseg_one/features/personal/presentation/empleados/empleados_list_screen.dart'
    show empleadoNombreCompleto;

import '../data/tables/servicio_eventual_table.dart';
import '../domain/repositories/servicio_eventual_repository.dart';
import 'servicios_eventuales_controller.dart';
import 'package:riseg_one/features/finanzas/data/tables/cuenta_por_cobrar_table.dart'
    show EstatusCuentaPorCobrar;
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_vigencia_table.dart'
    show MetodoPagoCobro;

import '../data/tables/servicio_eventual_documento_fiscal_table.dart';
import '../domain/totales_venta_eventual.dart';
import 'widgets/servicio_eventual_cobro_dialogs.dart';
import 'widgets/eliminar_servicio_eventual_fisicamente_dialog.dart';
import 'widgets/servicio_eventual_anulacion_dialog.dart';
import 'widgets/servicio_eventual_dialogs.dart';
import 'widgets/servicio_eventual_labels.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');
final _formatoFechaHora = DateFormat('dd/MM/yyyy HH:mm');

/// Todo lo cargado de un eventual en una sola lectura — la pantalla
/// nunca dispara una consulta por renglón al construir.
class _Expediente {
  const _Expediente({
    required this.eventual,
    required this.participantes,
    required this.coberturas,
    required this.costos,
    required this.eventos,
    required this.totales,
    required this.nombresParticipante,
    required this.nombreSolicitante,
    required this.cuenta,
    required this.pagos,
    required this.documentos,
  });

  final ServicioEventualData eventual;
  final List<ServicioEventualParticipanteData> participantes;
  final List<ServicioEventualCoberturaData> coberturas;
  final List<ServicioEventualCostoData> costos;
  final List<ServicioEventualEventoData> eventos;
  final TotalesServicioEventual totales;
  final Map<String, String> nombresParticipante;
  final String nombreSolicitante;

  /// schemaVersion 88 — la cobranza del eventual. `cuenta` es `null`
  /// sólo para el histórico anterior a esta rebanada.
  final CuentaPorCobrarData? cuenta;
  final List<({AplicacionPagoData aplicacion, PagoData pago})> pagos;
  final List<ServicioEventualDocumentoFiscalData> documentos;

  /// El documento VIGENTE, si lo hay — los cancelados siguen en
  /// [documentos] como historia.
  ServicioEventualDocumentoFiscalData? get documentoVigente => documentos
      .where((d) => d.estatus == EstatusDocumentoFiscalEventual.registrado.name)
      .firstOrNull;

  /// Cobranza VIGENTE, no la resta de saldos: cancelar la Cuenta la
  /// deja en 0 y esa resta pasaría a afirmar que se cobró todo. Aquí
  /// no cuesta una consulta extra — [pagos] ya trae cada aplicación
  /// con su Pago.
  int get cobrado => pagos
      .where((p) =>
          p.aplicacion.estatus == EstatusAplicacionPago.aplicada.name &&
          p.pago.estatus != EstatusPago.cancelado.name)
      .fold(0, (suma, p) => suma + p.aplicacion.monto);
}

class ServicioEventualExpedienteScreen extends ConsumerStatefulWidget {
  const ServicioEventualExpedienteScreen({required this.servicioEventualId, super.key});

  final String servicioEventualId;

  @override
  ConsumerState<ServicioEventualExpedienteScreen> createState() => _ServicioEventualExpedienteScreenState();
}

class _ServicioEventualExpedienteScreenState extends ConsumerState<ServicioEventualExpedienteScreen> {
  _Expediente? _datos;
  var _cargando = true;
  var _tab = 0;

  @override
  void initState() {
    super.initState();
    Future.microtask(_cargar);
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final notifier = ref.read(serviciosEventualesControllerProvider.notifier);
    final eventual = await notifier.obtenerPorId(widget.servicioEventualId);
    if (eventual == null) {
      if (mounted) setState(() => _cargando = false);
      return;
    }

    final participantes = await notifier.listarParticipantes(eventual.id);
    final coberturas = await notifier.listarCoberturas(eventual.id);
    final costos = await notifier.listarCostos(eventual.id);
    final eventos = await notifier.listarEventos(eventual.id);
    final totales = await notifier.totales(eventual.id);
    final cuenta = await notifier.obtenerCuentaPorCobrar(eventual.id);
    final pagos = cuenta == null
        ? const <({AplicacionPagoData aplicacion, PagoData pago})>[]
        : await notifier.listarPagosDeLaCuenta(cuenta.id);
    final documentos = await notifier.listarDocumentosFiscales(eventual.id);

    // Los nombres de los empleados se resuelven EN LOTE: un evento con
    // veinte participantes no debe costar veinte consultas.
    final idsEmpleado = participantes.map((p) => p.empleadoId).whereType<String>().toList();
    final empleados = idsEmpleado.isEmpty
        ? const <EmpleadoData>[]
        : await ref.read(empleadoRepositoryProvider).listarPorIds(idsEmpleado);
    final porId = {for (final e in empleados) e.id: e};

    final nombres = <String, String>{
      for (final p in participantes)
        p.id: p.empleadoId != null
            ? (porId[p.empleadoId] == null ? p.empleadoId! : empleadoNombreCompleto(porId[p.empleadoId]!))
            : (p.nombreExterno ?? '—'),
    };

    var nombreSolicitante = eventual.solicitanteNombre ?? '—';
    if (eventual.clienteId != null) {
      final cliente = await ref.read(clienteRepositoryProvider).obtenerPorId(eventual.clienteId!);
      nombreSolicitante = cliente?.nombreComercial ?? '—';
    }

    if (!mounted) return;
    setState(() {
      _datos = _Expediente(
        eventual: eventual,
        participantes: participantes,
        coberturas: coberturas,
        costos: costos,
        eventos: eventos,
        totales: totales,
        nombresParticipante: nombres,
        nombreSolicitante: nombreSolicitante,
        cuenta: cuenta,
        pagos: pagos,
        documentos: documentos,
      );
      _cargando = false;
    });
  }

  Future<void> _eliminarFisicamente() async {
    final eventual = _datos?.eventual;
    if (eventual == null) return;
    final eliminado = await mostrarDialogoEliminarServicioEventualFisicamente(
      context,
      ref,
      eventual: eventual,
    );
    // El expediente que se estaba viendo ya no existe: quedarse en él
    // mostraría el estado de error de carga.
    if (eliminado && mounted) context.go('/comercial/eventuales');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (_cargando) return const Center(child: CircularProgressIndicator());
    final datos = _datos;
    if (datos == null) {
      return RisegEmptyState(
        icon: Icons.error_outline,
        title: l10n.serviciosEventualesCargaErrorTitulo,
        message: l10n.serviciosEventualesCargaErrorMensaje,
        primaryAction: RisegButton(
          label: l10n.servicioEventualDetalleVolver,
          onPressed: () => context.go('/comercial/eventuales'),
        ),
      );
    }

    final cancelado = datos.eventual.estatus == EstatusServicioEventual.cancelado.name;
    // Identidad estructural, nunca un permiso concedible ni el rol que
    // se muestra en pantalla — mismo criterio que el expediente de
    // Artículo y el de Deuda.
    final esMaestro = ref.watch(sesionControllerProvider)?.esMaestro ?? false;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RisegButton(
            label: l10n.servicioEventualDetalleVolver,
            icon: Icons.arrow_back,
            variant: RisegButtonVariant.ghost,
            size: RisegButtonSize.compact,
            onPressed: () => context.go('/comercial/eventuales'),
          ),
          const SizedBox(height: AppSpacing.sm),
          RisegSectionHeader(
            title: '${datos.eventual.folio} · ${datos.eventual.nombre}',
            description: datos.nombreSolicitante,
            // Lo destructivo y extraordinario va en el ⋯ del
            // encabezado, junto a la identidad del registro y nunca
            // como botón permanente — mismo patrón que Artículo
            // (Etapa 18). Se ofrece con el evento vigente Y cancelado:
            // un registro de prueba se borra justo después de
            // cancelarlo. El guardia real es `exigirMaestro` en la
            // fachada; esto sólo evita ofrecer lo que se rechazaría.
            secondaryAction: esMaestro
                ? RisegActionsMenu(
                    menuKey: const Key('servicio_eventual_expediente_menu_acciones'),
                    tooltip: l10n.servicioEventualMenuAcciones,
                    actions: [
                      RisegMenuAction(
                        key: const Key('servicio_eventual_boton_eliminar_fisicamente'),
                        label: l10n.servicioEventualAccionEliminarDefinitivamente,
                        icon: Icons.delete_forever_outlined,
                        destructive: true,
                        onTap: _eliminarFisicamente,
                      ),
                    ],
                  )
                : null,
            primaryAction: cancelado
                ? null
                : RisegButton(
                    key: const Key('servicio_eventual_boton_corregir'),
                    label: l10n.servicioEventualBotonCorregir,
                    variant: RisegButtonVariant.secondary,
                    onPressed: () async {
                      final guardado = await mostrarDialogoServicioEventual(
                        context,
                        ref,
                        existente: datos.eventual,
                      );
                      if (guardado) await _cargar();
                    },
                  ),
          ),
          const SizedBox(height: AppSpacing.md),
          RisegTabs(
            tabs: [
              RisegTabItem(label: l10n.servicioEventualTabResumen),
              RisegTabItem(label: l10n.servicioEventualTabParticipantes),
              RisegTabItem(label: l10n.servicioEventualTabCostos),
              RisegTabItem(label: l10n.servicioEventualTabCobro),
            ],
            selectedIndex: _tab,
            onChanged: (indice) => setState(() => _tab = indice),
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: switch (_tab) {
              1 => _Coberturas(datos: datos, onCambio: _cargar),
              2 => _Costos(datos: datos, onCambio: _cargar),
              3 => _Cobro(datos: datos, onCambio: _cargar),
              _ => _Resumen(datos: datos, onCambio: _cargar),
            },
          ),
        ],
      ),
    );
  }
}

class _Resumen extends ConsumerWidget {
  const _Resumen({required this.datos, required this.onCambio});

  final _Expediente datos;
  final Future<void> Function() onCambio;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final eventual = datos.eventual;

    // El TOTAL de la venta, con IVA cuando aplica — el mismo número
    // que la Cuenta por cobrar, nunca el importe capturado a secas.
    final totalesVenta = calcularTotalesVentaEventual(
      importeAcordado: eventual.importeAcordado,
      tratamientoIva: TratamientoIva.values.byName(eventual.tratamientoIva),
    );
    final resultado = totalesVenta.total - datos.totales.costoComprometido;
    final cancelado = eventual.estatus == EstatusServicioEventual.cancelado.name;

    final finalizado = eventual.estatus == EstatusServicioEventual.finalizado.name;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              SizedBox(
                width: 210,
                child: RisegStatCard(
                  dense: true,
                  label: l10n.serviciosEventualesKpiVenta,
                  value: formatoCentavosPago(totalesVenta.total),
                  icon: Icons.sell_outlined,
                ),
              ),
              SizedBox(
                width: 210,
                child: RisegStatCard(
                  dense: true,
                  label: l10n.servicioEventualResumenCostoComprometido,
                  value: formatoCentavosPago(datos.totales.costoComprometido),
                  icon: Icons.assignment_outlined,
                ),
              ),
              SizedBox(
                width: 210,
                child: RisegStatCard(
                  dense: true,
                  label: l10n.servicioEventualResumenResultado,
                  value: formatoCentavosPago(resultado),
                  icon: Icons.trending_up,
                ),
              ),
              // schemaVersion 88 — ahora sí hay cobranza que mostrar, y
              // es una cifra real, no un cero de relleno.
              SizedBox(
                width: 210,
                child: RisegStatCard(
                  dense: true,
                  label: l10n.servicioEventualCobroCobrado,
                  value: formatoCentavosPago(datos.cobrado),
                  icon: Icons.savings_outlined,
                ),
              ),
              SizedBox(
                width: 210,
                child: RisegStatCard(
                  dense: true,
                  label: l10n.servicioEventualCobroPendiente,
                  value: formatoCentavosPago(datos.cuenta?.saldoPendiente ?? 0),
                  icon: Icons.hourglass_bottom_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          RisegCard(
            child: RisegFieldGrid(
              children: [
                _campo(context, l10n.servicioEventualCampoSolicitante, datos.nombreSolicitante),
                // El desglose del precio acordado, donde se puede leer
                // con calma — arriba sólo va el total.
                _campo(
                  context,
                  l10n.servicioEventualCampoTratamientoIva,
                  _tratamientoIvaLabel(l10n, eventual.tratamientoIva),
                ),
                _campo(
                  context,
                  l10n.servicioEventualDesgloseSubtotal,
                  formatoCentavosPago(totalesVenta.subtotal),
                ),
                if (totalesVenta.iva > 0)
                  _campo(context, l10n.servicioEventualDesgloseIva, formatoCentavosPago(totalesVenta.iva)),
                _campo(
                  context,
                  l10n.servicioEventualResumenCostoPagado,
                  formatoCentavosPago(datos.totales.costoPagado),
                ),
                _campo(context, l10n.servicioEventualCampoInicio, _formatoFechaHora.format(eventual.fechaHoraInicio)),
                _campo(context, l10n.servicioEventualCampoFin, _formatoFechaHora.format(eventual.fechaHoraFin)),
                _campo(context, l10n.servicioEventualCampoUbicacion, eventual.ubicacion ?? '—'),
                _campo(context, l10n.servicioEventualCampoRequiereFactura, eventual.requiereFactura ? l10n.servicioEventualValorSi : l10n.servicioEventualValorNo),
                _campo(context, l10n.servicioEventualCampoEstatus, servicioEventualEstatusLabel(l10n, eventual.estatus)),
                if (eventual.notas != null)
                  _campo(context, l10n.servicioEventualCampoNotas, eventual.notas!),
                if (eventual.motivoCancelacion != null)
                  _campo(context, l10n.servicioEventualCampoMotivoCancelacion, eventual.motivoCancelacion!),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Sin acciones vigentes no se dibuja nada: un contenedor de
          // acciones vacío entre la ficha y el Historial prometía algo
          // que no estaba.
          if (!cancelado) ...[
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                if (!finalizado)
                  RisegButton(
                    key: const Key('servicio_eventual_boton_finalizar'),
                    label: l10n.servicioEventualBotonFinalizar,
                    variant: RisegButtonVariant.secondary,
                    onPressed: () async {
                      await ref.read(serviciosEventualesControllerProvider.notifier).finalizar(eventual.id);
                      await onCambio();
                    },
                  ),
                RisegButton(
                  key: const Key('servicio_eventual_boton_cancelar'),
                  label: l10n.servicioEventualBotonCancelar,
                  variant: RisegButtonVariant.ghost,
                  // Ya no es un simple "¿seguro?": cancelar el evento
                  // anula la venta, así que el diálogo enumera primero
                  // qué dinero vuelve y qué gasto real se queda.
                  onPressed: () async {
                    final anulada = await mostrarDialogoAnularServicioEventual(
                      context,
                      ref,
                      servicioEventualId: eventual.id,
                    );
                    if (anulada) await onCambio();
                  },
                ),
              ],
            ),
          ],
          // El historial deja de ser una quinta pestaña: es contexto
          // del evento, no una sección aparte con la que competir.
          const SizedBox(height: AppSpacing.lg),
          RisegSectionHeader(title: l10n.servicioEventualTabHistorialSeccion),
          const SizedBox(height: AppSpacing.sm),
          _Historial(eventos: datos.eventos, enLinea: true),
        ],
      ),
    );
  }
}

String _tratamientoIvaLabel(AppLocalizations l10n, String tratamiento) {
  return switch (TratamientoIva.values.byName(tratamiento)) {
    TratamientoIva.masIva => l10n.servicioComercialTratamientoIvaMasIva,
    TratamientoIva.ivaIncluido => l10n.servicioComercialTratamientoIvaIvaIncluido,
    TratamientoIva.noAplica => l10n.servicioComercialTratamientoIvaNoAplica,
  };
}

class _Coberturas extends ConsumerWidget {
  const _Coberturas({required this.datos, required this.onCambio});

  final _Expediente datos;
  final Future<void> Function() onCambio;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final notifier = ref.read(serviciosEventualesControllerProvider.notifier);
    final cancelado = datos.eventual.estatus == EstatusServicioEventual.cancelado.name;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!cancelado)
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              RisegButton(
                key: const Key('servicio_eventual_boton_agregar_participante'),
                label: l10n.servicioEventualBotonAgregarParticipante,
                icon: Icons.person_add_outlined,
                variant: RisegButtonVariant.secondary,
                size: RisegButtonSize.compact,
                onPressed: () async {
                  final guardado = await mostrarDialogoParticipante(
                    context,
                    ref,
                    servicioEventualId: datos.eventual.id,
                  );
                  if (guardado) await onCambio();
                },
              ),
              RisegButton(
                key: const Key('servicio_eventual_boton_agregar_cobertura'),
                label: l10n.servicioEventualBotonAgregarCobertura,
                icon: Icons.add,
                size: RisegButtonSize.compact,
                // Sin participantes no hay a quién asignarle la
                // cobertura: el botón se apaga en vez de abrir un
                // formulario imposible de guardar.
                onPressed: datos.participantes.isEmpty
                    ? null
                    : () async {
                        final guardado = await mostrarDialogoCobertura(
                          context,
                          ref,
                          servicioEventualId: datos.eventual.id,
                          participantes: datos.participantes,
                          nombresParticipante: datos.nombresParticipante,
                        );
                        if (guardado) await onCambio();
                      },
              ),
            ],
          ),
        const SizedBox(height: AppSpacing.md),
        Expanded(
          child: RisegTableBase<ServicioEventualCoberturaData>(
            rows: datos.coberturas,
            emptyState: RisegEmptyState(
              title: l10n.servicioEventualParticipantesVacioTitulo,
              message: l10n.servicioEventualParticipantesVacioMensaje,
            ),
            hoverColor: colors.accentSoftBg,
            rowVerticalPadding: AppSpacing.sm,
            actionsWidth: 56,
            rowActionsBuilder: (c) => RisegActionsMenu(
              actions: [
                if (c.estatus == EstatusEjecucionServicioEventual.programada.name && !cancelado) ...[
                  RisegMenuAction(
                    label: l10n.servicioEventualAccionPagar,
                    icon: Icons.payments_outlined,
                    onTap: () async {
                      final pagado = await mostrarDialogoPagarGastoEventual(
                        context,
                        ref,
                        monto: c.importeAcordado,
                        onPagar: ({
                          required String formaPago,
                          String? cuentaFinancieraId,
                          String? deudaIdTarjeta,
                        }) =>
                            notifier.pagarCobertura(
                          coberturaId: c.id,
                          formaPago: formaPago,
                          cuentaFinancieraId: cuentaFinancieraId,
                          deudaIdTarjeta: deudaIdTarjeta,
                        ),
                      );
                      if (pagado) await onCambio();
                    },
                  ),
                  RisegMenuAction(
                    label: l10n.servicioEventualAccionCorregir,
                    icon: Icons.edit_outlined,
                    onTap: () async {
                      final guardado = await mostrarDialogoCobertura(
                        context,
                        ref,
                        servicioEventualId: datos.eventual.id,
                        participantes: datos.participantes,
                        nombresParticipante: datos.nombresParticipante,
                        existente: c,
                      );
                      if (guardado) await onCambio();
                    },
                  ),
                  RisegMenuAction(
                    label: l10n.servicioEventualAccionCancelar,
                    icon: Icons.block_outlined,
                    onTap: () async {
                      final motivo = await mostrarDialogoMotivo(
                        context,
                        titulo: l10n.servicioEventualDialogoCancelarCoberturaTitulo,
                        etiquetaMotivo: l10n.servicioEventualCampoMotivo,
                        confirmarLabel: l10n.servicioEventualAccionCancelar,
                        cancelarLabel: l10n.compraBotonCancelarFormulario,
                        errorMotivoRequerido: l10n.servicioEventualErrorMotivoRequerido,
                      );
                      if (motivo == null) return;
                      await notifier.cancelarCobertura(coberturaId: c.id, motivo: motivo);
                      await onCambio();
                    },
                  ),
                ],
                // Revertir el pago sigue disponible aunque el evento
                // esté cancelado: el dinero salió de verdad y tiene que
                // poder devolverse.
                // §17 — al Egreso que este pago generó, por FK real
                // (`egresoId`), nunca buscándolo por monto ni por fecha.
                if (c.egresoId != null)
                  RisegMenuAction(
                    label: l10n.servicioEventualAccionVerEgreso,
                    icon: Icons.receipt_long_outlined,
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (_) => EgresoDetalleDialog(egresoId: c.egresoId!),
                    ),
                  ),
                if (c.estatus == EstatusEjecucionServicioEventual.pagada.name)
                  RisegMenuAction(
                    label: l10n.servicioEventualAccionRevertirPago,
                    icon: Icons.undo,
                    onTap: () async {
                      final motivo = await mostrarDialogoMotivo(
                        context,
                        titulo: l10n.servicioEventualDialogoRevertirPagoTitulo,
                        etiquetaMotivo: l10n.servicioEventualCampoMotivo,
                        confirmarLabel: l10n.servicioEventualAccionRevertirPago,
                        cancelarLabel: l10n.compraBotonCancelarFormulario,
                        errorMotivoRequerido: l10n.servicioEventualErrorMotivoRequerido,
                      );
                      if (motivo == null) return;
                      await notifier.revertirPagoCobertura(coberturaId: c.id, motivo: motivo);
                      await onCambio();
                    },
                  ),
              ],
            ),
            columns: [
              RisegColumn<ServicioEventualCoberturaData>(
                label: l10n.servicioEventualColumnaParticipante,
                cellBuilder: (c) => Text(
                  datos.nombresParticipante[c.participanteId] ?? '—',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              RisegColumn<ServicioEventualCoberturaData>(
                label: l10n.servicioEventualColumnaFecha,
                width: 110,
                cellBuilder: (c) => Text(_formatoFecha.format(c.fecha)),
              ),
              RisegColumn<ServicioEventualCoberturaData>(
                label: l10n.servicioEventualColumnaHorario,
                width: 190,
                cellBuilder: (c) => Text(
                  rangoHorarioServicioEventual(
                    l10n,
                    horaInicioMinutos: c.horaInicioMinutos,
                    horaFinMinutos: c.horaFinMinutos,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              RisegColumn<ServicioEventualCoberturaData>(
                label: l10n.servicioEventualColumnaImporte,
                width: 120,
                alignment: TextAlign.right,
                cellBuilder: (c) => Text(formatoCentavosPago(c.importeAcordado)),
              ),
              RisegColumn<ServicioEventualCoberturaData>(
                label: l10n.servicioEventualColumnaEstatus,
                width: 120,
                cellBuilder: (c) => RisegStatusBadge(
                  label: ejecucionServicioEventualLabel(l10n, c.estatus),
                  tone: ejecucionServicioEventualTono(c.estatus),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Costos extends ConsumerWidget {
  const _Costos({required this.datos, required this.onCambio});

  final _Expediente datos;
  final Future<void> Function() onCambio;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final notifier = ref.read(serviciosEventualesControllerProvider.notifier);
    final cancelado = datos.eventual.estatus == EstatusServicioEventual.cancelado.name;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!cancelado)
          RisegButton(
            key: const Key('servicio_eventual_boton_agregar_costo'),
            label: l10n.servicioEventualBotonAgregarCosto,
            icon: Icons.add,
            size: RisegButtonSize.compact,
            onPressed: () async {
              final guardado = await mostrarDialogoCosto(
                context,
                ref,
                servicioEventualId: datos.eventual.id,
              );
              if (guardado) await onCambio();
            },
          ),
        const SizedBox(height: AppSpacing.md),
        Expanded(
          child: RisegTableBase<ServicioEventualCostoData>(
            rows: datos.costos,
            emptyState: RisegEmptyState(
              title: l10n.servicioEventualCostosVacioTitulo,
              message: l10n.servicioEventualCostosVacioMensaje,
            ),
            hoverColor: colors.accentSoftBg,
            rowVerticalPadding: AppSpacing.sm,
            actionsWidth: 56,
            rowActionsBuilder: (c) => RisegActionsMenu(
              actions: [
                if (c.estatus == EstatusEjecucionServicioEventual.programada.name && !cancelado) ...[
                  RisegMenuAction(
                    label: l10n.servicioEventualAccionPagar,
                    icon: Icons.payments_outlined,
                    onTap: () async {
                      final pagado = await mostrarDialogoPagarGastoEventual(
                        context,
                        ref,
                        monto: c.monto,
                        onPagar: ({
                          required String formaPago,
                          String? cuentaFinancieraId,
                          String? deudaIdTarjeta,
                        }) =>
                            notifier.pagarCosto(
                          costoId: c.id,
                          formaPago: formaPago,
                          cuentaFinancieraId: cuentaFinancieraId,
                          deudaIdTarjeta: deudaIdTarjeta,
                        ),
                      );
                      if (pagado) await onCambio();
                    },
                  ),
                  RisegMenuAction(
                    label: l10n.servicioEventualAccionCorregir,
                    icon: Icons.edit_outlined,
                    onTap: () async {
                      final guardado = await mostrarDialogoCosto(
                        context,
                        ref,
                        servicioEventualId: datos.eventual.id,
                        existente: c,
                      );
                      if (guardado) await onCambio();
                    },
                  ),
                  RisegMenuAction(
                    label: l10n.servicioEventualAccionCancelar,
                    icon: Icons.block_outlined,
                    onTap: () async {
                      final motivo = await mostrarDialogoMotivo(
                        context,
                        titulo: l10n.servicioEventualDialogoCancelarCostoTitulo,
                        etiquetaMotivo: l10n.servicioEventualCampoMotivo,
                        confirmarLabel: l10n.servicioEventualAccionCancelar,
                        cancelarLabel: l10n.compraBotonCancelarFormulario,
                        errorMotivoRequerido: l10n.servicioEventualErrorMotivoRequerido,
                      );
                      if (motivo == null) return;
                      await notifier.cancelarCosto(costoId: c.id, motivo: motivo);
                      await onCambio();
                    },
                  ),
                ],
                // §17 — al Egreso que este pago generó, por FK real
                // (`egresoId`), nunca buscándolo por monto ni por fecha.
                if (c.egresoId != null)
                  RisegMenuAction(
                    label: l10n.servicioEventualAccionVerEgreso,
                    icon: Icons.receipt_long_outlined,
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (_) => EgresoDetalleDialog(egresoId: c.egresoId!),
                    ),
                  ),
                if (c.estatus == EstatusEjecucionServicioEventual.pagada.name)
                  RisegMenuAction(
                    label: l10n.servicioEventualAccionRevertirPago,
                    icon: Icons.undo,
                    onTap: () async {
                      final motivo = await mostrarDialogoMotivo(
                        context,
                        titulo: l10n.servicioEventualDialogoRevertirPagoTitulo,
                        etiquetaMotivo: l10n.servicioEventualCampoMotivo,
                        confirmarLabel: l10n.servicioEventualAccionRevertirPago,
                        cancelarLabel: l10n.compraBotonCancelarFormulario,
                        errorMotivoRequerido: l10n.servicioEventualErrorMotivoRequerido,
                      );
                      if (motivo == null) return;
                      await notifier.revertirPagoCosto(costoId: c.id, motivo: motivo);
                      await onCambio();
                    },
                  ),
              ],
            ),
            columns: [
              RisegColumn<ServicioEventualCostoData>(
                label: l10n.servicioEventualColumnaConcepto,
                cellBuilder: (c) => Text(c.concepto, overflow: TextOverflow.ellipsis),
              ),
              RisegColumn<ServicioEventualCostoData>(
                label: l10n.servicioEventualColumnaFecha,
                width: 110,
                cellBuilder: (c) => Text(_formatoFecha.format(c.fecha)),
              ),
              RisegColumn<ServicioEventualCostoData>(
                label: l10n.servicioEventualColumnaMonto,
                width: 120,
                alignment: TextAlign.right,
                cellBuilder: (c) => Text(formatoCentavosPago(c.monto)),
              ),
              RisegColumn<ServicioEventualCostoData>(
                label: l10n.servicioEventualColumnaEstatus,
                width: 120,
                cellBuilder: (c) => RisegStatusBadge(
                  label: ejecucionCostoServicioEventualLabel(l10n, c.estatus),
                  tone: ejecucionServicioEventualTono(c.estatus),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Historial extends StatelessWidget {
  const _Historial({required this.eventos, this.enLinea = false});

  final List<ServicioEventualEventoData> eventos;

  /// Dentro del Resumen ya hay un scroll padre: un `ListView` propio
  /// anidaría dos scrolls y el framework lo rechaza.
  final bool enLinea;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return ListView.separated(
      shrinkWrap: enLinea,
      physics: enLinea ? const NeverScrollableScrollPhysics() : null,
      itemCount: eventos.length,
      separatorBuilder: (_, __) => const Divider(height: AppSpacing.lg),
      itemBuilder: (_, i) {
        final evento = eventos[i];
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 140,
              child: Text(
                _formatoFechaHora.format(evento.fechaHora),
                style: AppTypography.caption.copyWith(color: colors.textMuted),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    servicioEventualEventoLabel(AppLocalizations.of(context)!, evento.tipoEvento),
                    style: AppTypography.bodyStrong,
                  ),
                  if (evento.observacion != null)
                    Text(
                      evento.observacion!,
                      style: AppTypography.caption.copyWith(color: colors.textMuted),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Etiqueta + valor en una fila — el mismo par que ya usan los otros
/// expedientes;  sólo decide en cuántas columnas caben.
Widget _campo(BuildContext context, String etiqueta, String valor) {
  final colors = context.colors;
  return Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 180, child: Text(etiqueta, style: AppTypography.label.copyWith(color: colors.textMuted))),
        Expanded(child: Text(valor, style: AppTypography.body)),
      ],
    ),
  );
}

/// Cobro y documento fiscal del eventual — una sola pestaña, no tres:
/// la deuda, lo cobrado y el CFDI son la misma conversación.
class _Cobro extends ConsumerWidget {
  const _Cobro({required this.datos, required this.onCambio});

  final _Expediente datos;
  final Future<void> Function() onCambio;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final notifier = ref.read(serviciosEventualesControllerProvider.notifier);
    final cuenta = datos.cuenta;
    final cancelado = datos.eventual.estatus == EstatusServicioEventual.cancelado.name;

    if (cuenta == null) {
      return RisegEmptyState(
        icon: Icons.receipt_long_outlined,
        title: l10n.servicioEventualCobroSinCuenta,
        message: l10n.servicioEventualCobroSinCuenta,
      );
    }

    final saldado = cuenta.saldoPendiente == 0;
    final documentoVigente = datos.documentoVigente;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RisegCard(
            child: RisegFieldGrid(
              children: [
                _campo(
                  context,
                  l10n.servicioEventualCobroTotalVenta,
                  formatoCentavosPago(cuenta.saldoOriginal),
                ),
                _campo(context, l10n.servicioEventualCobroCobrado, formatoCentavosPago(datos.cobrado)),
                _campo(
                  context,
                  l10n.servicioEventualCobroPendiente,
                  formatoCentavosPago(cuenta.saldoPendiente),
                ),
                _campo(context, l10n.servicioEventualCobroEstatus, _estatusCuentaLabel(l10n, cuenta.estatus)),
                _campo(
                  context,
                  l10n.servicioEventualCobroVencimiento,
                  cuenta.fechaVencimiento == null ? '—' : _formatoFecha.format(cuenta.fechaVencimiento!),
                ),
                _campo(context, l10n.servicioEventualCampoMetodoCobro, _metodoLabel(l10n, cuenta.metodo)),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              RisegButton(
                key: const Key('servicio_eventual_boton_ver_cuenta'),
                label: l10n.servicioEventualAccionVerCuenta,
                icon: Icons.request_quote_outlined,
                variant: RisegButtonVariant.ghost,
                size: RisegButtonSize.compact,
                // Eventual → CxC por FK real (`servicioEventualId`).
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => CuentaPorCobrarDetalleDialog(cuentaPorCobrarId: cuenta.id),
                ),
              ),
              RisegButton(
                key: const Key('servicio_eventual_boton_cobrar'),
                label: l10n.servicioEventualBotonRegistrarCobro,
                icon: Icons.payments_outlined,
                size: RisegButtonSize.compact,
                // Una cuenta saldada o cancelada no admite más cobros:
                // el botón se apaga en vez de abrir un diálogo que el
                // dominio va a rechazar.
                onPressed: saldado || cancelado
                    ? null
                    : () async {
                        final cobrado = await mostrarDialogoCobrarEventual(
                          context,
                          ref,
                          servicioEventualId: datos.eventual.id,
                          saldoPendiente: cuenta.saldoPendiente,
                        );
                        if (cobrado) await onCambio();
                      },
              ),
              if (datos.eventual.requiereFactura && documentoVigente == null && !cancelado)
                RisegButton(
                  key: const Key('servicio_eventual_boton_registrar_factura'),
                  label: l10n.servicioEventualBotonRegistrarFactura,
                  icon: Icons.description_outlined,
                  variant: RisegButtonVariant.secondary,
                  size: RisegButtonSize.compact,
                  onPressed: () async {
                    final guardado = await mostrarDialogoDocumentoFiscal(
                      context,
                      ref,
                      eventual: datos.eventual,
                    );
                    if (guardado) await onCambio();
                  },
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          RisegSectionHeader(title: l10n.servicioEventualSeccionPagos),
          const SizedBox(height: AppSpacing.sm),
          if (datos.pagos.isEmpty)
            RisegEmptyState(
              title: l10n.servicioEventualPagosVacioTitulo,
              message: l10n.servicioEventualPagosVacioMensaje,
            )
          else
            for (final fila in datos.pagos)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Row(
                  children: [
                    SizedBox(
                      width: 140,
                      child: Text(fila.pago.folioPago, style: AppTypography.caption.copyWith(color: colors.textMuted)),
                    ),
                    SizedBox(width: 110, child: Text(_formatoFecha.format(fila.pago.fechaPago))),
                    Expanded(child: Text(formatoCentavosPago(fila.aplicacion.monto))),
                    RisegStatusBadge(
                      label: fila.aplicacion.estatus,
                      tone: fila.aplicacion.estatus == 'aplicada'
                          ? RisegStatusTone.success
                          : RisegStatusTone.neutral,
                    ),
                  ],
                ),
              ),
          const SizedBox(height: AppSpacing.lg),
          RisegSectionHeader(title: l10n.servicioEventualSeccionDocumento),
          const SizedBox(height: AppSpacing.sm),
          if (!datos.eventual.requiereFactura)
            Text(
              l10n.servicioEventualDocumentoSinFactura,
              style: AppTypography.caption.copyWith(color: colors.textMuted),
            )
          else if (datos.documentos.isEmpty)
            RisegEmptyState(
              title: l10n.servicioEventualDocumentoVacioTitulo,
              message: l10n.servicioEventualDocumentoVacioMensaje,
            )
          else
            for (final documento in datos.documentos)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Row(
                  children: [
                    SizedBox(width: 140, child: Text(documento.folio, overflow: TextOverflow.ellipsis)),
                    SizedBox(width: 110, child: Text(_formatoFecha.format(documento.fechaEmision))),
                    SizedBox(width: 80, child: Text(_metodoLabel(l10n, documento.metodo))),
                    // El snapshot fiscal completo en una línea, no en
                    // tres columnas: a 500px una columna más desborda, y
                    // ellipsis conserva lo importante al frente.
                    Expanded(
                      child: Text(
                        [
                          documento.snapshotRazonSocial,
                          documento.snapshotRfc,
                          if (documento.snapshotCodigoPostalFiscal != null)
                            documento.snapshotCodigoPostalFiscal!,
                        ].join(' · '),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    RisegStatusBadge(
                      label: documento.estatus == EstatusDocumentoFiscalEventual.registrado.name
                          ? l10n.servicioEventualDocumentoEstatusRegistrado
                          : l10n.servicioEventualDocumentoEstatusCancelado,
                      tone: documento.estatus == EstatusDocumentoFiscalEventual.registrado.name
                          ? RisegStatusTone.success
                          : RisegStatusTone.neutral,
                    ),
                    if (documento.estatus == EstatusDocumentoFiscalEventual.registrado.name)
                      RisegActionsMenu(
                        actions: [
                          RisegMenuAction(
                            label: l10n.servicioEventualAccionCorregir,
                            icon: Icons.edit_outlined,
                            onTap: () async {
                              final guardado = await mostrarDialogoDocumentoFiscal(
                                context,
                                ref,
                                eventual: datos.eventual,
                                existente: documento,
                              );
                              if (guardado) await onCambio();
                            },
                          ),
                          RisegMenuAction(
                            label: l10n.servicioEventualAccionCancelar,
                            icon: Icons.block_outlined,
                            onTap: () async {
                              final motivo = await mostrarDialogoMotivo(
                                context,
                                titulo: l10n.servicioEventualDialogoCancelarFacturaTitulo,
                                etiquetaMotivo: l10n.servicioEventualCampoMotivo,
                                confirmarLabel: l10n.servicioEventualAccionCancelar,
                                cancelarLabel: l10n.compraBotonCancelarFormulario,
                                errorMotivoRequerido: l10n.servicioEventualErrorMotivoRequerido,
                              );
                              if (motivo == null) return;
                              await notifier.cancelarDocumentoFiscal(
                                documentoId: documento.id,
                                motivo: motivo,
                              );
                              await onCambio();
                            },
                          ),
                        ],
                      ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

String _estatusCuentaLabel(AppLocalizations l10n, String estatus) {
  return switch (EstatusCuentaPorCobrar.values.byName(estatus)) {
    EstatusCuentaPorCobrar.pendiente => l10n.cuentasPorCobrarEstatusPendiente,
    EstatusCuentaPorCobrar.parcial => l10n.cuentasPorCobrarEstatusParcial,
    EstatusCuentaPorCobrar.pagada => l10n.cuentasPorCobrarEstatusPagada,
    EstatusCuentaPorCobrar.cancelada => l10n.cuentasPorCobrarEstatusCancelada,
  };
}

String _metodoLabel(AppLocalizations l10n, String metodo) {
  return switch (MetodoPagoCobro.values.byName(metodo)) {
    MetodoPagoCobro.pue => 'PUE',
    MetodoPagoCobro.ppd => 'PPD',
    MetodoPagoCobro.noAplica => l10n.serviciosEventualesFiltroEstatusTodos,
  };
}

