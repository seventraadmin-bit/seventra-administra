import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/domain/contraparte_cobro.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/dashboard/presentation/dashboard_controller.dart';
import 'package:riseg_one/features/finanzas/data/tables/cuenta_por_cobrar_table.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cancelar_aplicacion_pago_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cancelar_cuenta_por_cobrar_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/complemento_pago_derivado.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cuenta_por_cobrar_antiguedad.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/quitar_reprogramacion_cobro_cuenta_por_cobrar_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/reprogramar_cobro_cuenta_por_cobrar_usecase.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_vigencia_table.dart';
import 'package:riseg_one/features/organizacion/presentation/agenda/widgets/agenda_detalle_dialog.dart';
import 'package:riseg_one/features/organizacion/presentation/shared/campo_consulta.dart';
import 'package:riseg_one/features/usuarios/usuarios_providers.dart';

import '../../../finanzas_providers.dart';
import '../../cuentas_financieras/cuentas_financieras_controller.dart';
import '../../pagos/pagos_controller.dart';
import '../../pagos/pagos_list_screen.dart' show formatoCentavosPago;
import '../../planeacion/planeacion_financiera_controller.dart';
import '../../resumen/resumen_financiero_controller.dart';
import '../../pagos/widgets/pago_detalle_dialog.dart';
import '../cuentas_por_cobrar_controller.dart';
import '../cuentas_por_cobrar_list_screen.dart' show formatoCentavosCuentaPorCobrar;
import 'corregir_cuenta_por_cobrar_dialog.dart';
import 'registrar_pago_aplicado_dialog.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');
final _formatoFechaHora = DateFormat('dd/MM/yyyy HH:mm');

/// Detalle de una Cuenta por cobrar (Etapa 4J.1) — snapshot
/// administrativo completo (Marlon: "no quiero depender de joins para
/// reconstruir el documento años después") más antigüedad derivada e
/// historial append-only, mismo criterio que `AgendaDetalleDialog`.
class CuentaPorCobrarDetalleDialog extends ConsumerStatefulWidget {
  const CuentaPorCobrarDetalleDialog({required this.cuentaPorCobrarId, super.key});

  final String cuentaPorCobrarId;

  @override
  ConsumerState<CuentaPorCobrarDetalleDialog> createState() => _CuentaPorCobrarDetalleDialogState();
}

class _CuentaPorCobrarDetalleDialogState extends ConsumerState<CuentaPorCobrarDetalleDialog> {
  CuentaPorCobrarData? _cuenta;
  List<CuentaPorCobrarEventoData> _eventos = const [];
  List<AplicacionPagoData> _aplicacionesPago = const [];
  final Map<String, String> _folioPagoPorAplicacion = {};
  bool _algunPagoConComplementoPendiente = false;
  String? _clienteNombre;
  Map<String, String> _usuariosPorId = const {};
  bool _cargando = true;
  bool _procesando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final notifier = ref.read(cuentasPorCobrarControllerProvider.notifier);
    final cuenta = await notifier.obtenerPorId(widget.cuentaPorCobrarId);
    final eventos = await notifier.listarEventos(widget.cuentaPorCobrarId);
    final aplicacionesPago =
        await ref.read(pagoRepositoryProvider).listarAplicacionesPorCuenta(widget.cuentaPorCobrarId);
    final usuarios = await ref.read(usuarioRepositoryProvider).listar();
    final usuariosPorId = {for (final u in usuarios) u.id: u.nombre};

    // La contraparte puede ser Cliente o Servicio Eventual: se
    // resuelve por el único camino que conoce los dos tipos, nunca
    // leyendo el id del cliente a mano.
    String? clienteNombre;
    if (cuenta != null) {
      final nombres = await ref.read(resolverNombresContraparteUseCaseProvider).paraCuentas([cuenta]);
      clienteNombre = nombres.de(contraparteDeCuenta(cuenta));
    }
    for (final aplicacion in aplicacionesPago) {
      if (_folioPagoPorAplicacion.containsKey(aplicacion.id)) continue;
      final pago = await ref.read(pagoRepositoryProvider).obtenerPorId(aplicacion.pagoId);
      if (pago != null) _folioPagoPorAplicacion[aplicacion.id] = pago.folioPago;
    }

    // Cierre de cobranza (Etapa 4J.3): revisa, para cada aplicación
    // activa, si el Pago de origen ya tiene su Complemento vigente —
    // basta con que uno solo siga pendiente para que la Cuenta no
    // cuente como fiscalmente cerrada.
    var algunPendiente = false;
    for (final aplicacion in aplicacionesPago) {
      if (EstatusAplicacionPago.values.byName(aplicacion.estatus) != EstatusAplicacionPago.aplicada) continue;
      // Histórico completo del Pago (schemaVersion 79): sólo un
      // Complemento VIGENTE cierra la obligación; varios cancelados no.
      final complementos = await ref.read(complementoPagoRepositoryProvider).listarPorPagoId(aplicacion.pagoId);
      if (complementoPendiente(requiereComplemento: true, complementosDelPago: complementos)) {
        algunPendiente = true;
        break;
      }
    }

    if (!mounted) return;
    setState(() {
      _cuenta = cuenta;
      _eventos = eventos;
      _aplicacionesPago = aplicacionesPago;
      _algunPagoConComplementoPendiente = algunPendiente;
      _clienteNombre = clienteNombre;
      _usuariosPorId = usuariosPorId;
      _cargando = false;
    });
  }

  String _tipoDocumentoLabel(AppLocalizations l10n, String valor) {
    return switch (TipoDocumentoCobro.values.byName(valor)) {
      TipoDocumentoCobro.cfdi => l10n.servicioCobroTipoDocumentoCfdi,
      TipoDocumentoCobro.reciboDePago => l10n.servicioCobroTipoDocumentoReciboDePago,
    };
  }

  String _metodoLabel(AppLocalizations l10n, String valor) {
    return switch (MetodoPagoCobro.values.byName(valor)) {
      MetodoPagoCobro.pue => l10n.servicioCobroMetodoPue,
      MetodoPagoCobro.ppd => l10n.servicioCobroMetodoPpd,
      MetodoPagoCobro.noAplica => l10n.servicioCobroMetodoNoAplica,
    };
  }

  String _estatusLabel(AppLocalizations l10n, String estatus) {
    return switch (EstatusCuentaPorCobrar.values.byName(estatus)) {
      EstatusCuentaPorCobrar.pendiente => l10n.cuentasPorCobrarEstatusPendiente,
      EstatusCuentaPorCobrar.parcial => l10n.cuentasPorCobrarEstatusParcial,
      EstatusCuentaPorCobrar.pagada => l10n.cuentasPorCobrarEstatusPagada,
      EstatusCuentaPorCobrar.cancelada => l10n.cuentasPorCobrarEstatusCancelada,
    };
  }

  RisegStatusTone _estatusTono(String estatus) {
    return switch (EstatusCuentaPorCobrar.values.byName(estatus)) {
      EstatusCuentaPorCobrar.pendiente => RisegStatusTone.info,
      EstatusCuentaPorCobrar.parcial => RisegStatusTone.warning,
      EstatusCuentaPorCobrar.pagada => RisegStatusTone.success,
      EstatusCuentaPorCobrar.cancelada => RisegStatusTone.neutral,
    };
  }

  String _antiguedadLabel(AppLocalizations l10n, RangoAntiguedadCuentaPorCobrar rango) {
    return switch (rango) {
      RangoAntiguedadCuentaPorCobrar.alCorriente => l10n.cuentaPorCobrarDetalleAntiguedadAlCorriente,
      RangoAntiguedadCuentaPorCobrar.dias0a30 => l10n.cuentaPorCobrarDetalleAntiguedad0a30,
      RangoAntiguedadCuentaPorCobrar.dias31a60 => l10n.cuentaPorCobrarDetalleAntiguedad31a60,
      RangoAntiguedadCuentaPorCobrar.dias61a90 => l10n.cuentaPorCobrarDetalleAntiguedad61a90,
      RangoAntiguedadCuentaPorCobrar.dias90Mas => l10n.cuentaPorCobrarDetalleAntiguedad90Mas,
    };
  }

  String _eventoLabel(AppLocalizations l10n, String tipoEvento) {
    return switch (TipoEventoCuentaPorCobrar.values.byName(tipoEvento)) {
      TipoEventoCuentaPorCobrar.creada => l10n.cuentaPorCobrarDetalleHistorialEventoCreada,
      TipoEventoCuentaPorCobrar.fechaVencimientoDefinida =>
        l10n.cuentaPorCobrarDetalleHistorialEventoFechaVencimientoDefinida,
      TipoEventoCuentaPorCobrar.pagoAplicado => l10n.cuentaPorCobrarDetalleHistorialEventoPagoAplicado,
      TipoEventoCuentaPorCobrar.pagoAplicacionCancelada =>
        l10n.cuentaPorCobrarDetalleHistorialEventoPagoAplicacionCancelada,
      TipoEventoCuentaPorCobrar.fechaCobroReprogramada => l10n.cuentaPorCobrarDetalleHistorialEventoFechaCobroReprogramada,
      TipoEventoCuentaPorCobrar.corregida => l10n.cuentaPorCobrarDetalleHistorialEventoCorregida,
      TipoEventoCuentaPorCobrar.cancelada => l10n.cuentaPorCobrarDetalleHistorialEventoCancelada,
    };
  }

  Future<void> _corregir() async {
    final actualizo = await mostrarDialogoCorregirCuentaPorCobrar(context, ref, _cuenta!);
    if (actualizo) await _cargar();
  }

  Future<void> _verEventual() async {
    // Por FK real (la columna servicioEventualId de la cuenta), nunca por
    // texto. La ruta es la del expediente del eventual.
    final id = _cuenta!.servicioEventualId!;
    Navigator.of(context).pop();
    context.go('/comercial/eventuales/$id');
  }

  Future<void> _verDocumento() async {
    await showDialog<void>(
      context: context,
      // Sólo se llega aquí desde una cuenta con documento — la acción
      // está oculta para las de origen eventual (ver `_puedeVerAgenda`).
      builder: (_) => AgendaDetalleDialog(documentoPorEmitirId: _cuenta!.documentoPorEmitirId!),
    );
  }

  Future<void> _reprogramar() async {
    final l10n = AppLocalizations.of(context)!;
    DateTime? nuevaFecha = _cuenta?.fechaCobroReprogramada;
    final motivoController = TextEditingController();
    String? errorGeneral;

    final confirmado = await RisegDialog.showForm<bool>(
      context: context,
      title: l10n.cuentaPorCobrarReprogramarDialogoTitulo,
      confirmLabel: l10n.cuentaPorCobrarReprogramarBotonConfirmar,
      cancelLabel: l10n.cuentaPorCobrarReprogramarBotonCancelar,
      contentBuilder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RisegDateField(
                label: l10n.cuentaPorCobrarReprogramarCampoFecha,
                value: nuevaFecha,
                onChanged: (valor) => setState(() => nuevaFecha = valor),
              ),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(label: l10n.cuentaPorCobrarReprogramarCampoMotivo, controller: motivoController),
              if (errorGeneral != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  errorGeneral!,
                  style: AppTypography.caption.copyWith(color: Theme.of(dialogContext).colorScheme.error),
                ),
              ],
            ],
          );
        },
      ),
      onConfirm: () async {
        if (nuevaFecha == null) {
          errorGeneral = l10n.cuentaPorCobrarReprogramarErrorFechaRequerida;
          return null;
        }
        final motivo = motivoController.text.trim();
        if (motivo.isEmpty) {
          errorGeneral = l10n.cuentaPorCobrarReprogramarErrorMotivoRequerido;
          return null;
        }
        final resultado = await ref.read(cuentasPorCobrarControllerProvider.notifier).reprogramarCobro(
              cuentaPorCobrarId: widget.cuentaPorCobrarId,
              fechaCobroReprogramada: nuevaFecha,
              motivo: motivo,
            );
        if (!context.mounted) return false;
        switch (resultado) {
          case ReprogramarCobroCuentaPorCobrarExitoso():
            RisegFeedback.showSuccess(context, l10n.cuentaPorCobrarReprogramarExito);
            return true;
          case ReprogramarCobroCuentaPorCobrarMotivoRequerido():
            errorGeneral = l10n.cuentaPorCobrarReprogramarErrorMotivoRequerido;
            return null;
          case ReprogramarCobroCuentaPorCobrarNoExiste():
          case ReprogramarCobroCuentaPorCobrarCancelada():
          case ReprogramarCobroCuentaPorCobrarErrorInesperado():
            RisegFeedback.showError(context, l10n.cuentaPorCobrarReprogramarErrorInesperado);
            return false;
        }
      },
    );

    motivoController.dispose();
    if (confirmado == true) await _cargar();
  }

  Future<void> _quitarReprogramacion() async {
    final l10n = AppLocalizations.of(context)!;
    final motivoController = TextEditingController();
    final confirmado = await RisegDialog.showForm<bool>(
      context: context,
      title: l10n.cuentaPorCobrarQuitarReprogramacionConfirmacionTitulo,
      confirmLabel: l10n.cuentaPorCobrarQuitarReprogramacionConfirmacionConfirmar,
      cancelLabel: l10n.cuentaPorCobrarQuitarReprogramacionConfirmacionCancelar,
      contentBuilder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.cuentaPorCobrarQuitarReprogramacionConfirmacionMensaje, style: AppTypography.body),
          const SizedBox(height: AppSpacing.md),
          RisegTextField(label: l10n.pagoMotivoCampo, controller: motivoController, autofocus: true),
        ],
      ),
      onConfirm: () async => true,
    );
    if (confirmado != true) {
      WidgetsBinding.instance.addPostFrameCallback((_) => motivoController.dispose());
      return;
    }
    final motivo = motivoController.text.trim();
    WidgetsBinding.instance.addPostFrameCallback((_) => motivoController.dispose());
    if (!mounted) return;

    final resultado = await ref
        .read(cuentasPorCobrarControllerProvider.notifier)
        .quitarReprogramacion(cuentaPorCobrarId: widget.cuentaPorCobrarId, motivo: motivo);
    if (!mounted) return;

    switch (resultado) {
      case QuitarReprogramacionCobroCuentaPorCobrarExitoso():
        RisegFeedback.showSuccess(context, l10n.cuentaPorCobrarQuitarReprogramacionExito);
        await _cargar();
      case QuitarReprogramacionCobroCuentaPorCobrarSinReprogramacion():
        RisegFeedback.showError(context, l10n.cuentaPorCobrarQuitarReprogramacionErrorSinReprogramacion);
      case QuitarReprogramacionCobroCuentaPorCobrarMotivoRequerido():
      case QuitarReprogramacionCobroCuentaPorCobrarNoExiste():
      case QuitarReprogramacionCobroCuentaPorCobrarErrorInesperado():
        RisegFeedback.showError(context, l10n.cuentaPorCobrarQuitarReprogramacionErrorInesperado);
    }
  }

  Future<void> _cancelarCuenta() async {
    final l10n = AppLocalizations.of(context)!;
    final motivoController = TextEditingController();
    final confirmado = await RisegDialog.showForm<bool>(
      context: context,
      title: l10n.cuentaPorCobrarCancelarConfirmacionTitulo,
      confirmLabel: l10n.cuentaPorCobrarCancelarConfirmacionConfirmar,
      cancelLabel: l10n.cuentaPorCobrarCancelarConfirmacionCancelar,
      contentBuilder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.cuentaPorCobrarCancelarConfirmacionMensaje, style: AppTypography.body),
          const SizedBox(height: AppSpacing.md),
          RisegTextField(label: l10n.pagoMotivoCampo, controller: motivoController, autofocus: true),
        ],
      ),
      onConfirm: () async => true,
    );
    if (confirmado != true) {
      WidgetsBinding.instance.addPostFrameCallback((_) => motivoController.dispose());
      return;
    }
    final motivo = motivoController.text.trim();
    WidgetsBinding.instance.addPostFrameCallback((_) => motivoController.dispose());
    if (!mounted) return;

    setState(() => _procesando = true);
    final resultado = await ref
        .read(cuentasPorCobrarControllerProvider.notifier)
        .cancelar(cuentaPorCobrarId: widget.cuentaPorCobrarId, motivo: motivo);
    if (!mounted) return;
    setState(() => _procesando = false);

    switch (resultado) {
      case CancelarCuentaPorCobrarExitoso():
        RisegFeedback.showSuccess(context, l10n.cuentaPorCobrarCancelarExito);
        await _cargar();
      case CancelarCuentaPorCobrarTieneAplicacionesActivas(:final cantidad):
        RisegFeedback.showError(context, l10n.cuentaPorCobrarCancelarErrorTieneAplicaciones(cantidad));
      case CancelarCuentaPorCobrarYaCancelada():
      case CancelarCuentaPorCobrarMotivoRequerido():
      case CancelarCuentaPorCobrarNoExiste():
      case CancelarCuentaPorCobrarErrorInesperado():
        RisegFeedback.showError(context, l10n.cuentaPorCobrarCancelarErrorInesperado);
    }
  }

  Future<void> _registrarPago() async {
    final actualizo = await mostrarDialogoRegistrarPagoAplicado(
      context,
      ref,
      cuentaPorCobrarId: widget.cuentaPorCobrarId,
      saldoPendiente: _cuenta!.saldoPendiente,
    );
    if (actualizo) {
      await _cargar();
      // `_cargar()` solo repuebla el estado local de este diálogo (por
      // eso el saldo ya se veía correcto de inmediato) — el LISTADO
      // (`cuentasPorCobrarControllerProvider`) es un provider aparte que
      // nunca se enteraba de este pago, y quedaba con el estatus previo
      // hasta que su `autoDispose` se disparaba por otro motivo (Etapa
      // 15, mismo hallazgo real ya corregido en Clientes/Agenda).
      ref.invalidate(cuentasPorCobrarControllerProvider);
      // El pago aplicado genera un Ingreso automático (Etapa 4K.1) —
      // afecta directamente el resumen de Ingresos del Dashboard, y
      // reduce `saldoPendiente` — cambia "Por cobrar"/"Próximos
      // compromisos" del Resumen financiero y la Planeación (Etapa
      // 19C/19D).
      ref.invalidate(dashboardControllerProvider);
      ref.invalidate(resumenFinancieroControllerProvider);
      ref.invalidate(planeacionFinancieraControllerProvider);
      // Auditoría integral 19A-19D: el Ingreso automático puede llevar
      // la Cuenta financiera elegida en el diálogo — su saldo derivado
      // cambia y nunca se avisaba.
      ref.invalidate(cuentasFinancierasControllerProvider);
    }
  }

  Future<void> _verPago(AplicacionPagoData aplicacion) async {
    await showDialog<void>(context: context, builder: (_) => PagoDetalleDialog(pagoId: aplicacion.pagoId));
    await _cargar();
  }

  Future<void> _cancelarAplicacionPago(AplicacionPagoData aplicacion) async {
    final l10n = AppLocalizations.of(context)!;
    final motivoController = TextEditingController();
    final confirmado = await RisegDialog.showForm<bool>(
      context: context,
      title: l10n.cancelarAplicacionPagoConfirmacionTitulo,
      confirmLabel: l10n.cancelarAplicacionPagoConfirmacionConfirmar,
      cancelLabel: l10n.cancelarAplicacionPagoConfirmacionCancelar,
      contentBuilder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.cancelarAplicacionPagoConfirmacionMensaje, style: AppTypography.body),
          const SizedBox(height: AppSpacing.md),
          RisegTextField(label: l10n.pagoMotivoCampo, controller: motivoController, autofocus: true),
        ],
      ),
      onConfirm: () async => true,
    );
    // Diferido con `addPostFrameCallback` (nunca síncrono aquí) — el
    // diálogo de confirmación sigue en su transición de cierre cuando
    // este `await` regresa, y su `RisegTextField` todavía usa
    // `motivoController` en esos últimos frames; destruirlo antes
    // produce "A TextEditingController was used after being disposed"
    // (Etapa 15, mismo hallazgo real que en `egreso_detalle_dialog.dart`
    // — mismo patrón ya probado en `riseg_eliminar_fisicamente_dialog.dart:86`).
    if (confirmado != true) {
      WidgetsBinding.instance.addPostFrameCallback((_) => motivoController.dispose());
      return;
    }
    final motivo = motivoController.text.trim();
    WidgetsBinding.instance.addPostFrameCallback((_) => motivoController.dispose());
    if (!mounted) return;

    setState(() => _procesando = true);
    // Etapa 0 (auditoría de consistencia transversal — corrección de un
    // hueco real de autorización): antes llamaba al use case crudo, sin
    // ningún `autorizarUseCase` en la cadena, aunque la MISMA operación
    // invocada desde Pagos sí estaba gateada (`finanzas.archivar`) —
    // reutiliza ese mismo método ya autorizado en vez de duplicar el
    // wrapper.
    final resultado = await ref
        .read(pagosControllerProvider.notifier)
        .cancelarAplicacion(aplicacionPagoId: aplicacion.id, motivo: motivo);
    if (!mounted) return;
    setState(() => _procesando = false);

    switch (resultado) {
      case CancelarAplicacionPagoExitoso():
        RisegFeedback.showSuccess(context, l10n.cancelarAplicacionPagoExito);
        await _cargar();
        ref.invalidate(cuentasPorCobrarControllerProvider);
        // Cancelar la aplicación revierte el Ingreso automático que
        // generó — mismo motivo que en `_registrarPago`.
        ref.invalidate(dashboardControllerProvider);
        ref.invalidate(resumenFinancieroControllerProvider);
        ref.invalidate(planeacionFinancieraControllerProvider);
      case CancelarAplicacionPagoNoExiste():
      case CancelarAplicacionPagoYaCancelada():
      case CancelarAplicacionPagoErrorInesperado():
        RisegFeedback.showError(context, l10n.cancelarAplicacionPagoErrorInesperado);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final hoy = DateTime.now();

    Widget content;
    if (_cargando) {
      content = const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()));
    } else if (_cuenta == null) {
      content = Text(l10n.cuentasPorCobrarListadoCargaErrorMensaje);
    } else {
      final c = _cuenta!;
      final esCfdi = TipoDocumentoCobro.values.byName(c.tipoDocumento) == TipoDocumentoCobro.cfdi;
      final rango = calcularRangoAntiguedad(c, hoy);
      final cancelada = EstatusCuentaPorCobrar.values.byName(c.estatus) == EstatusCuentaPorCobrar.cancelada;
      final tieneAplicacionesActivas = _aplicacionesPago
          .any((a) => EstatusAplicacionPago.values.byName(a.estatus) == EstatusAplicacionPago.aplicada);

      content = SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                SizedBox(
                  width: 300,
                  child: CampoConsulta(
                    label: l10n.cuentasPorCobrarColumnaCliente,
                    value: _clienteNombre ?? '—',
                  ),
                ),
                RisegButton(
                  key: const Key('cuenta_por_cobrar_boton_ver_cliente'),
                  label: l10n.cuentaPorCobrarDetalleBotonVerCliente,
                  variant: RisegButtonVariant.ghost,
                  size: RisegButtonSize.compact,
                  onPressed: () {
                    Navigator.of(context).pop();
                    context.push('/comercial/clientes/${c.clienteId}');
                  },
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            // Los badges de estatus viven en su propio `Wrap`, nunca en
            // el mismo Row que el nombre del Cliente + botón: con un
            // nombre largo y el badge "Cierre de cobranza pendiente
            // (falta Complemento)" (el más largo de los dos posibles),
            // la suma de anchos fijos superaba el ancho fijo del
            // diálogo (560) y exprimía el `Expanded` del Cliente a
            // ~0px, forzando su texto a partirse letra por letra —
            // error visual real encontrado en producción.
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                RisegStatusBadge(label: _estatusLabel(l10n, c.estatus), tone: _estatusTono(c.estatus)),
                if (cuentaRequiereComplemento(c))
                  RisegStatusBadge(
                    label: cierreCobranzaCompleto(cuenta: c, algunPagoConComplementoPendiente: _algunPagoConComplementoPendiente)
                        ? l10n.cuentaPorCobrarDetalleCierreCobranzaCompleto
                        : l10n.cuentaPorCobrarDetalleCierreCobranzaPendiente,
                    tone: cierreCobranzaCompleto(cuenta: c, algunPagoConComplementoPendiente: _algunPagoConComplementoPendiente)
                        ? RisegStatusTone.success
                        : RisegStatusTone.warning,
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: CampoConsulta(
                    label: l10n.cuentaPorCobrarDetalleCampoFolioDocumento,
                    value: c.folioDocumento,
                  ),
                ),
                if (esCfdi)
                  Expanded(
                    child: CampoConsulta(label: l10n.cuentaPorCobrarDetalleCampoUuid, value: c.uuid),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: CampoConsulta(
                    label: l10n.cuentaPorCobrarDetalleCampoTipoDocumento,
                    value: _tipoDocumentoLabel(l10n, c.tipoDocumento),
                  ),
                ),
                Expanded(
                  child: CampoConsulta(
                    label: l10n.cuentaPorCobrarDetalleCampoMetodo,
                    value: _metodoLabel(l10n, c.metodo),
                  ),
                ),
              ],
            ),
            // Mismo criterio que la ficha de Configuración de cobro
            // (`servicioCobroRequiereComplementoAviso`): solo aparece
            // cuando aplica, nunca un "No" ambiguo.
            if (c.requiereComplemento) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                l10n.cuentaPorCobrarDetalleCampoRequiereComplemento,
                style: AppTypography.caption.copyWith(color: colors.info),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: CampoConsulta(
                    label: l10n.cuentaPorCobrarDetalleCampoFechaEmisionReal,
                    value: _formatoFecha.format(c.fechaEmisionReal),
                  ),
                ),
                Expanded(
                  child: CampoConsulta(
                    label: l10n.cuentaPorCobrarDetalleCampoImporteEmitido,
                    value: formatoCentavosCuentaPorCobrar(c.importeEmitido),
                  ),
                ),
                Expanded(
                  child: CampoConsulta(label: l10n.cuentaPorCobrarDetalleCampoMoneda, value: c.moneda),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: CampoConsulta(
                    label: l10n.cuentaPorCobrarDetalleCampoSaldoOriginal,
                    value: formatoCentavosCuentaPorCobrar(c.saldoOriginal),
                  ),
                ),
                Expanded(
                  child: CampoConsulta(
                    label: l10n.cuentaPorCobrarDetalleCampoSaldoPendiente,
                    value: formatoCentavosCuentaPorCobrar(c.saldoPendiente),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: CampoConsulta(
                    label: l10n.cuentaPorCobrarDetalleCampoVencimiento,
                    value: c.fechaVencimiento == null
                        ? l10n.cuentasPorCobrarSinVencimiento
                        : _formatoFecha.format(c.fechaVencimiento!),
                  ),
                ),
                Expanded(
                  child: CampoConsulta(
                    label: l10n.cuentaPorCobrarDetalleCampoAntiguedad,
                    value: _antiguedadLabel(l10n, rango),
                  ),
                ),
              ],
            ),
            // Sección 11 del pedido (Etapa 7): la fecha reprogramada
            // nunca se mostraba en el expediente — solo vivía en la
            // pantalla de Planeación. Nunca sustituye el renglón de
            // arriba (fecha contractual, siempre visible tal cual).
            const SizedBox(height: AppSpacing.sm),
            CampoConsulta(
              label: l10n.cuentaPorCobrarDetalleCampoFechaCobroReprogramada,
              value: c.fechaCobroReprogramada == null
                  ? l10n.cuentaPorCobrarDetalleSinFechaCobroReprogramada
                  : _formatoFecha.format(c.fechaCobroReprogramada!),
            ),
            if (c.observaciones != null && c.observaciones!.trim().isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              CampoConsulta(label: l10n.agendaDetalleCampoObservaciones, value: c.observaciones),
            ],
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.cuentaPorCobrarDetalleSeccionPagos,
                    style: AppTypography.heading3.copyWith(color: colors.textPrimary),
                  ),
                ),
                if (EstatusCuentaPorCobrar.values.byName(c.estatus) != EstatusCuentaPorCobrar.pagada)
                  RisegButton(
                    label: l10n.cuentaPorCobrarDetalleBotonRegistrarPago,
                    variant: RisegButtonVariant.ghost,
                    onPressed: _registrarPago,
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            if (_aplicacionesPago.isEmpty)
              Text(
                l10n.cuentaPorCobrarDetallePagosSinPagos,
                style: AppTypography.body.copyWith(color: colors.textMuted),
              )
            else
              for (final aplicacion in _aplicacionesPago)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(_folioPagoPorAplicacion[aplicacion.id] ?? aplicacion.pagoId),
                          ),
                          SizedBox(width: 110, child: Text(formatoCentavosPago(aplicacion.monto))),
                          SizedBox(
                            width: 100,
                            child: RisegStatusBadge(
                              label: EstatusAplicacionPago.values.byName(aplicacion.estatus) ==
                                      EstatusAplicacionPago.aplicada
                                  ? l10n.aplicacionPagoEstatusAplicada
                                  : l10n.aplicacionPagoEstatusCancelada,
                              tone: EstatusAplicacionPago.values.byName(aplicacion.estatus) ==
                                      EstatusAplicacionPago.aplicada
                                  ? RisegStatusTone.success
                                  : RisegStatusTone.neutral,
                            ),
                          ),
                        ],
                      ),
                      Wrap(
                        spacing: AppSpacing.xs,
                        runSpacing: AppSpacing.xs,
                        children: [
                          RisegButton(
                            label: l10n.pagoDetalleDialogoTitulo,
                            variant: RisegButtonVariant.ghost,
                            onPressed: () => _verPago(aplicacion),
                          ),
                          if (EstatusAplicacionPago.values.byName(aplicacion.estatus) == EstatusAplicacionPago.aplicada)
                            RisegButton(
                              label: l10n.cuentaPorCobrarDetalleBotonCancelarAplicacion,
                              variant: RisegButtonVariant.ghost,
                              loading: _procesando,
                              onPressed: () => _cancelarAplicacionPago(aplicacion),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
            const SizedBox(height: AppSpacing.md),
            Text(
              l10n.cuentaPorCobrarDetalleSeccionHistorial,
              style: AppTypography.heading3.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: AppSpacing.xs),
            if (_eventos.isEmpty)
              Text(
                l10n.cuentaPorCobrarDetalleHistorialSinEventos,
                style: AppTypography.body.copyWith(color: colors.textMuted),
              )
            else
              for (final evento in _eventos)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            _formatoFechaHora.format(evento.fechaHora),
                            style: AppTypography.caption.copyWith(color: colors.textMuted),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Expanded(
                            child: Text(
                              _eventoLabel(l10n, evento.tipoEvento),
                              style: AppTypography.label,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      if (evento.actorUsuarioId != null)
                        Text(
                          '${l10n.cuentaPorCobrarDetalleHistorialCampoActor}: '
                          '${_usuariosPorId[evento.actorUsuarioId] ?? evento.actorUsuarioId}',
                          style: AppTypography.caption.copyWith(color: colors.textMuted),
                        ),
                      if (evento.observacion != null && evento.observacion!.trim().isNotEmpty)
                        Text(evento.observacion!, style: AppTypography.body.copyWith(color: colors.textMuted)),
                    ],
                  ),
                ),
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                // schemaVersion 87: una cuenta de origen eventual no
                // tiene documento que abrir. Se oculta la acción en vez
                // de dejarla fallar.
                if (_cuenta!.documentoPorEmitirId != null)
                  RisegButton(
                    key: const Key('cuenta_por_cobrar_boton_ver_documento'),
                    label: l10n.cuentaPorCobrarDetalleBotonVerDocumento,
                    variant: RisegButtonVariant.ghost,
                    onPressed: _verDocumento,
                  ),
                // schemaVersion 88 — la cuenta de un eventual sí tiene
                // a dónde llevar: su expediente.
                if (_cuenta!.servicioEventualId != null)
                  RisegButton(
                    key: const Key('cuenta_por_cobrar_boton_ver_eventual'),
                    label: l10n.cuentaPorCobrarDetalleBotonVerEventual,
                    variant: RisegButtonVariant.ghost,
                    onPressed: _verEventual,
                  ),
                if (!cancelada) ...[
                  RisegButton(
                    key: const Key('cuenta_por_cobrar_boton_corregir'),
                    label: l10n.cuentaPorCobrarDetalleBotonCorregir,
                    variant: RisegButtonVariant.secondary,
                    onPressed: _corregir,
                  ),
                  RisegButton(
                    key: const Key('cuenta_por_cobrar_boton_reprogramar'),
                    label: l10n.cuentaPorCobrarDetalleBotonReprogramar,
                    variant: RisegButtonVariant.secondary,
                    onPressed: _reprogramar,
                  ),
                  if (c.fechaCobroReprogramada != null)
                    RisegButton(
                      key: const Key('cuenta_por_cobrar_boton_quitar_reprogramacion'),
                      label: l10n.cuentaPorCobrarDetalleBotonQuitarReprogramacion,
                      variant: RisegButtonVariant.ghost,
                      onPressed: _quitarReprogramacion,
                    ),
                  if (!tieneAplicacionesActivas)
                    RisegButton(
                      key: const Key('cuenta_por_cobrar_boton_cancelar'),
                      label: l10n.cuentaPorCobrarDetalleBotonCancelar,
                      variant: RisegButtonVariant.danger,
                      loading: _procesando,
                      onPressed: _cancelarCuenta,
                    ),
                ],
              ],
            ),
          ],
        ),
      );
    }

    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // `Expanded` + `ellipsis` — mismo patrón ya aplicado
                    // en `agenda_detalle_dialog.dart` (Etapa 15): sin
                    // esto, el título largo desbordaba junto al botón
                    // de cerrar ("BOTTOM OVERFLOWED" horizontal real).
                    Expanded(
                      child: Text(
                        l10n.cuentaPorCobrarDetalleDialogoTitulo,
                        style: AppTypography.heading2.copyWith(color: colors.textPrimary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                content,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
