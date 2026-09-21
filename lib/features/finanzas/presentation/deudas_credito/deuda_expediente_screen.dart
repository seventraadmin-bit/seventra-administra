import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/dashboard/presentation/dashboard_controller.dart';
import 'package:riseg_one/features/finanzas/data/tables/deuda_table.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/deuda_repository.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/calcular_fecha_tarjeta_usecase.dart';
import 'package:riseg_one/features/finanzas/presentation/egresos/egresos_controller.dart';
import 'package:riseg_one/features/finanzas/presentation/egresos/widgets/egreso_detalle_dialog.dart';
import 'package:riseg_one/features/finanzas/presentation/planeacion/planeacion_financiera_controller.dart';
import 'package:riseg_one/features/finanzas/presentation/resumen/resumen_financiero_controller.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import 'package:riseg_one/features/usuarios/usuarios_providers.dart';

import '../../finanzas_providers.dart';
import '../cuentas_financieras/cuentas_financieras_controller.dart';
import 'deudas_credito_controller.dart';
import 'deudas_credito_list_screen.dart' show deudaEstatusLabel, deudaEstatusTono, deudaTipoLabel, formatoCentavosDeuda;
import 'widgets/cancelar_deuda_dialog.dart';
import 'widgets/cancelar_pago_deuda_dialog.dart';
import 'widgets/corregir_pago_deuda_dialog.dart';
import 'widgets/editar_deuda_dialog.dart';
import 'widgets/registrar_pago_deuda_dialog.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');

String _movimientoTipoLabel(AppLocalizations l10n, String tipo) {
  return switch (TipoMovimientoDeuda.values.byName(tipo)) {
    TipoMovimientoDeuda.altaInicial => l10n.movimientoDeudaAltaInicial,
    TipoMovimientoDeuda.cargoCompra => l10n.movimientoDeudaCargoCompra,
    TipoMovimientoDeuda.pago => l10n.movimientoDeudaPago,
    TipoMovimientoDeuda.ajustePositivo => l10n.movimientoDeudaAjustePositivo,
    TipoMovimientoDeuda.ajusteNegativo => l10n.movimientoDeudaAjusteNegativo,
    TipoMovimientoDeuda.cancelacion => l10n.movimientoDeudaCancelacion,
    TipoMovimientoDeuda.reversionPago => l10n.movimientoDeudaReversionPago,
  };
}

/// Cargo/pago/saldo de un `MovimientoDeuda` en las columnas del
/// historial (Etapa 19B) — `cargoCompra`/`ajustePositivo`/`altaInicial`
/// aumentan saldo (columna Cargo); `pago`/`ajusteNegativo`/
/// `cancelacion` lo reducen (columna Pago). Puramente derivado de
/// `tipo`, nunca una columna nueva en la tabla.
/// `reversionPago` (Etapa 9) también aumenta el saldo — deshace un pago
/// —, así que va en la columna Cargo junto con los demás.
bool _esCargo(String tipo) => tipo == TipoMovimientoDeuda.altaInicial.name ||
    tipo == TipoMovimientoDeuda.cargoCompra.name ||
    tipo == TipoMovimientoDeuda.ajustePositivo.name ||
    tipo == TipoMovimientoDeuda.reversionPago.name;

/// Fila superior de KPIs para una tarjeta de crédito (Etapa "tarjeta
/// revolvente") — reemplaza la fila genérica de deuda fija
/// (Importe original/Pagado/Vencimiento no aplican a una línea
/// revolvente). Usa [creditoDisponibleTarjeta] como única fuente de
/// verdad, la misma que el listado y el use case de Compras.
List<Widget> _tarjetasKpiTdc(AppLocalizations l10n, DeudaData deuda) {
  final limite = deuda.tarjetaLimiteCredito;
  final disponible = creditoDisponibleTarjeta(limiteCredito: limite, saldoActual: deuda.saldoActual);
  final utilizacion = limite == null || limite == 0 ? null : (deuda.saldoActual / limite * 100).clamp(0, 100);

  return [
    RisegStatCard(
      label: l10n.deudasCreditoColumnaSaldoActual,
      value: formatoCentavosDeuda(deuda.saldoActual),
      dense: true,
      deltaTone: deuda.saldoActual > 0 ? RisegStatusTone.warning : RisegStatusTone.success,
    ),
    RisegStatCard(label: l10n.deudaTarjetaLimite, value: limite == null ? l10n.deudaTarjetaSinDato : formatoCentavosDeuda(limite), dense: true),
    RisegStatCard(
      label: l10n.deudaTarjetaCreditoDisponible,
      value: disponible == null ? l10n.deudaTarjetaSinDato : formatoCentavosDeuda(disponible),
      dense: true,
    ),
    RisegStatCard(
      label: l10n.deudaTarjetaPorcentajeUtilizacion,
      value: utilizacion == null ? l10n.deudaTarjetaSinDato : '${utilizacion.round()}%',
      dense: true,
      deltaTone: utilizacion == null
          ? null
          : (utilizacion >= 80 ? RisegStatusTone.error : (utilizacion >= 50 ? RisegStatusTone.warning : RisegStatusTone.success)),
    ),
  ];
}

/// Etiqueta legible del tratamiento de IVA (tri-state: no especificado/
/// sin IVA/con IVA) — reutilizada para la tasa variable y para el CAT,
/// nunca una segunda lógica de formato.
String _formatoIva(AppLocalizations l10n, bool? incluyeIva) {
  if (incluyeIva == null) return l10n.registrarDeudaIvaNoEspecificado;
  return incluyeIva ? l10n.registrarDeudaIvaConIva : l10n.registrarDeudaIvaSinIva;
}

/// Formatea la tasa ordinaria de una TDC según su [TipoTasaTarjeta] —
/// `fija` reutiliza `tasaInteres` tal cual (mismo criterio que deuda
/// fija); `variable` nunca se colapsa a un solo porcentaje, siempre
/// muestra referencia + diferencial + tratamiento de IVA (caso real:
/// Konfío Empresarial, "TIIE 28 días + 60 puntos porcentuales + IVA").
/// `null` cuando no se ha capturado nada — nunca se inventa "0%".
String? _formatoTasaTarjeta(AppLocalizations l10n, DeudaData deuda) {
  if (deuda.tarjetaTipoTasa == TipoTasaTarjeta.variable.name) {
    final referencia = deuda.tarjetaTasaReferencia;
    final diferencial = deuda.tarjetaTasaDiferencial;
    if (referencia == null && diferencial == null) return null;
    final partes = <String>[
      if (referencia != null) referencia,
      if (diferencial != null) '$diferencial ${l10n.deudaTarjetaPuntosPorcentuales}',
    ];
    var texto = partes.join(' + ');
    if (deuda.tarjetaTasaMasIva == true) texto = '$texto ${l10n.deudaTarjetaMasIvaTexto}';
    return texto;
  }
  return deuda.tasaInteres == null ? null : '${deuda.tasaInteres}%';
}

/// Formatea el CAT — concepto regulatorio DISTINTO de la tasa
/// ordinaria (caso real: Konfío Empresarial declara CAT 105.7% sin IVA
/// junto con una tasa ordinaria variable TIIE + 60 puntos — nunca se
/// confunden ni se promedian).
String? _formatoCat(AppLocalizations l10n, DeudaData deuda) {
  final cat = deuda.tarjetaCat;
  if (cat == null) return null;
  return '$cat% (${_formatoIva(l10n, deuda.tarjetaCatIncluyeIva)})';
}

/// Expediente de una Deuda (Etapa 19) — una sola pantalla desplazable
/// con secciones, sin pestañas internas (mismo criterio que
/// `CompraExpedienteScreen`/`LineaTelefonicaExpedienteScreen`).
class DeudaExpedienteScreen extends ConsumerStatefulWidget {
  const DeudaExpedienteScreen({required this.deudaId, super.key});

  final String deudaId;

  @override
  ConsumerState<DeudaExpedienteScreen> createState() => _DeudaExpedienteScreenState();
}

class _DeudaExpedienteScreenState extends ConsumerState<DeudaExpedienteScreen> {
  DeudaData? _deuda;
  List<MovimientoDeudaData> _movimientos = const [];

  /// Estado derivado de cada pago del historial (Etapa 9), resuelto una
  /// sola vez al cargar — nunca dentro del `cellBuilder` de la tabla,
  /// que se reconstruye en cada frame.
  Map<int, EstadoPagoDeuda> _estadoPorPago = const {};

  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final repo = ref.read(deudaRepositoryProvider);
    final deuda = await repo.obtenerPorId(widget.deudaId);
    final movimientos = deuda == null ? <MovimientoDeudaData>[] : await repo.listarMovimientos(widget.deudaId);

    final estados = <int, EstadoPagoDeuda>{};
    for (final m in movimientos.where((m) => m.tipo == TipoMovimientoDeuda.pago.name)) {
      estados[m.id] = await repo.obtenerEstadoPago(m.id);
    }

    if (!mounted) return;
    setState(() {
      _deuda = deuda;
      _movimientos = movimientos;
      _estadoPorPago = estados;
      _cargando = false;
    });
  }

  Future<void> _registrarPago() async {
    final deuda = _deuda;
    if (deuda == null) return;
    final registrado = await mostrarDialogoRegistrarPagoDeuda(context, ref, deuda: deuda);
    if (registrado) {
      await _cargar();
      // Bug real corregido: un pago crea un Egreso real y cambia
      // saldo/estatus, pero `_cargar()` solo repuebla el estado LOCAL
      // de esta pantalla — el listado de Deudas, Egresos y el Resumen
      // financiero son providers aparte que nunca se enteraban de este
      // pago (mismo hallazgo ya corregido en Cuentas por cobrar/
      // Inventario). El Egreso nuevo también afecta la serie
      // financiera del Dashboard.
      ref.invalidate(deudasCreditoControllerProvider);
      ref.invalidate(egresosControllerProvider);
      ref.invalidate(resumenFinancieroControllerProvider);
      ref.invalidate(planeacionFinancieraControllerProvider);
      ref.invalidate(dashboardControllerProvider);
      // Etapa 19C: el Egreso del pago puede llevar una Cuenta
      // financiera — su saldo derivado cambió.
      ref.invalidate(cuentasFinancierasControllerProvider);
    }
  }

  /// Consumidores reales de una corrección/cancelación de pago
  /// (Etapa 9) — los mismos que ya invalidaba registrar un pago: un
  /// pago corregido mueve saldo de Deuda, Egreso, Caja y bancos,
  /// Resumen, Planeación y Dashboard, y en una TDC además el crédito
  /// disponible (que el Dashboard deriva del `saldoActual` ya
  /// invalidado). Compras y Tiempos Extra NO se invalidan: esta
  /// operación jamás toca sus cargos.
  void _invalidarConsumidoresDePago() {
    ref.invalidate(deudasCreditoControllerProvider);
    ref.invalidate(egresosControllerProvider);
    ref.invalidate(resumenFinancieroControllerProvider);
    ref.invalidate(planeacionFinancieraControllerProvider);
    ref.invalidate(dashboardControllerProvider);
    ref.invalidate(cuentasFinancierasControllerProvider);
  }

  Future<void> _corregirPago(MovimientoDeudaData pago) async {
    final deuda = _deuda;
    final estado = _estadoPorPago[pago.id];
    if (deuda == null || estado == null) return;
    final corregido = await mostrarDialogoCorregirPagoDeuda(
      context,
      ref,
      deuda: deuda,
      pago: pago,
      importeNeto: estado.importeNeto,
    );
    if (corregido) {
      await _cargar();
      _invalidarConsumidoresDePago();
    }
  }

  Future<void> _cancelarPago(MovimientoDeudaData pago) async {
    final estado = _estadoPorPago[pago.id];
    if (estado == null) return;
    final cancelado = await mostrarDialogoCancelarPagoDeuda(
      context,
      ref,
      pago: pago,
      importeNeto: estado.importeNeto,
    );
    if (cancelado) {
      await _cargar();
      _invalidarConsumidoresDePago();
    }
  }

  Future<void> _editar() async {
    final deuda = _deuda;
    if (deuda == null) return;
    final editado = await mostrarDialogoEditarDeuda(context, ref, deuda: deuda);
    if (editado) {
      await _cargar();
      // El listado muestra nombre/acreedor/vencimiento — mismo bug de
      // provider stale que el pago, ver el comentario de _registrarPago.
      ref.invalidate(deudasCreditoControllerProvider);
      // Etapa 19D, punto 17 del pedido: corregir puede cambiar
      // `pagoProgramado`/`fechaVencimiento`/`tarjetaDiaPago` — cambia
      // qué compromisos muestran el Resumen y la Planeación financiera.
      ref.invalidate(resumenFinancieroControllerProvider);
      ref.invalidate(planeacionFinancieraControllerProvider);
      // Etapa 20 (hueco real encontrado): `tarjetaLimiteCredito`/
      // `tarjetaDiaPago` son exactamente los campos que determinan la
      // alerta de tarjeta del Dashboard — sin esto quedaba stale hasta
      // un cambio de pestaña ajeno.
      ref.invalidate(dashboardControllerProvider);
    }
  }

  Future<void> _cancelar() async {
    final cancelado = await mostrarDialogoCancelarDeuda(context, ref, deudaId: widget.deudaId);
    if (cancelado) {
      await _cargar();
      // Cancelar zera el saldo — afecta el listado y "Deuda financiera
      // total" del Resumen (as-of-hoy). Sin Egreso involucrado, así
      // que Egresos no necesita invalidarse aquí.
      ref.invalidate(deudasCreditoControllerProvider);
      ref.invalidate(resumenFinancieroControllerProvider);
      ref.invalidate(planeacionFinancieraControllerProvider);
      // Etapa 20 (hueco real encontrado): `saldoActual == 0` saca la
      // tarjeta de `alertas.tarjetasEnAlerta` — sin esto, una tarjeta
      // recién cancelada seguía apareciendo en "Requiere atención".
      ref.invalidate(dashboardControllerProvider);
    }
  }

  Future<void> _eliminarFisicamente() async {
    final l10n = AppLocalizations.of(context)!;
    final eliminado = await mostrarDialogoEliminarFisicamente(
      context,
      titulo: l10n.eliminarDeudaFisicamenteDialogoTitulo,
      advertencia: l10n.eliminarDeudaFisicamenteAdvertencia,
      eliminar: (motivo) async {
        final resultado = await ref.read(eliminarDeudaFisicamenteAutorizadoProvider)(deudaId: widget.deudaId, motivo: motivo);
        return switch (resultado) {
          EliminarDeudaFisicamenteExitoso() => ResultadoEliminacionFisica.exitoso,
          EliminarDeudaFisicamenteNoExiste() => ResultadoEliminacionFisica.noExiste,
          EliminarDeudaFisicamenteTieneDependencias() => ResultadoEliminacionFisica.tieneDependencias,
          EliminarDeudaFisicamenteErrorInesperado() => ResultadoEliminacionFisica.errorInesperado,
        };
      },
    );
    if (eliminado) {
      // La Deuda y cualquier Egreso que sus pagos hayan generado
      // desaparecen por completo — los 4 providers cruzados deben
      // refrescarse, igual que en _registrarPago.
      ref.invalidate(deudasCreditoControllerProvider);
      ref.invalidate(egresosControllerProvider);
      ref.invalidate(resumenFinancieroControllerProvider);
      ref.invalidate(planeacionFinancieraControllerProvider);
      ref.invalidate(dashboardControllerProvider);
      ref.invalidate(cuentasFinancierasControllerProvider);
      if (mounted) Navigator.of(context).maybePop();
    }
  }

  Future<void> _verEgreso(String egresoId) async {
    await showDialog<void>(context: context, builder: (_) => EgresoDetalleDialog(egresoId: egresoId));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    // Etapa 19B — este expediente mantiene su propio estado local
    // (nunca `ref.watch` directo, ver `_cargar()`), así que una Compra
    // con tarjeta registrada desde OTRA pantalla (ej. Registrar
    // compra, empujada encima de esta con `push`) nunca lo entera por
    // sí sola. `deudasCreditoControllerProvider` ya se invalidaba desde
    // `ComprasController` — faltaba escucharlo aquí para refrescar sin
    // que el usuario tenga que salir y volver a entrar.
    ref.listen(deudasCreditoControllerProvider, (previous, next) {
      if (previous != null) _cargar();
    });

    if (_cargando) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final deuda = _deuda;
    if (deuda == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.deudasCreditoListadoTitulo)),
        body: RisegEmptyState(
          icon: Icons.error_outline,
          title: l10n.deudasCreditoListadoCargaErrorTitulo,
          message: l10n.deudasCreditoListadoCargaErrorMensaje,
        ),
      );
    }

    final esMaestro = ref.watch(sesionControllerProvider)?.esMaestro ?? false;
    // Etapa 9 — las acciones por pago se ocultan sin permiso (el
    // guardia real vive igual en `autorizarUseCase`, esto solo evita
    // ofrecer lo que se va a rechazar). `hasCode` ya contempla el
    // bypass del Maestro.
    final permisos = ref.watch(permissionServiceProvider);
    final puedeCorregirPago = permisos.hasCode('deudas.corregirPago');
    final puedeCancelarPago = permisos.hasCode('deudas.cancelarPago');
    final esTarjeta = deuda.tipo == TipoDeuda.tarjetaCredito.name;
    final activa = deuda.estatus == EstatusDeuda.activa.name;
    // "Pagado" se deriva SIEMPRE de los movimientos tipo pago, nunca de
    // `importeOriginal - saldoActual` — esa resta deja de significar
    // "lo pagado" en cuanto exista un ajuste (Etapa 19B).
    final totalPagado = _movimientos
        .where((m) => m.tipo == TipoMovimientoDeuda.pago.name)
        .fold<int>(0, (acc, m) => acc + m.importe);

    return Scaffold(
      appBar: AppBar(title: Text(deuda.nombre)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RisegSectionHeader(
                  title: deuda.nombre,
                  description: '${deuda.folio} · ${deudaTipoLabel(l10n, deuda.tipo)}'
                      '${deuda.acreedor == null ? '' : ' · ${deuda.acreedor}'}',
                  primaryAction: Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      RisegStatusBadge(label: deudaEstatusLabel(l10n, deuda.estatus), tone: deudaEstatusTono(deuda.estatus)),
                      RisegButton(
                        label: l10n.deudasCreditoBotonRegistrarPago,
                        onPressed: activa ? _registrarPago : null,
                      ),
                      RisegButton(label: l10n.editarDeudaBotonConfirmar, variant: RisegButtonVariant.secondary, onPressed: _editar),
                      RisegActionsMenu(
                        menuKey: const Key('deuda_expediente_menu_acciones'),
                        actions: [
                          if (activa)
                            RisegMenuAction(
                              label: l10n.cancelarDeudaDialogoTitulo,
                              icon: Icons.block_outlined,
                              destructive: true,
                              onTap: _cancelar,
                            ),
                          if (esMaestro)
                            RisegMenuAction(
                              key: const Key('deuda_expediente_boton_eliminar_fisicamente'),
                              label: l10n.eliminacionFisicaBotonConfirmar,
                              icon: Icons.delete_forever_outlined,
                              destructive: true,
                              onTap: _eliminarFisicamente,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columnas = constraints.maxWidth < AppBreakpoints.compact ? 2 : 4;
                    final ancho = (constraints.maxWidth - (AppSpacing.md * (columnas - 1))) / columnas;
                    final tarjetas = esTarjeta
                        ? _tarjetasKpiTdc(l10n, deuda)
                        : [
                            RisegStatCard(
                              label: l10n.deudasCreditoColumnaImporteOriginal,
                              value: deuda.importeOriginal == null ? l10n.deudaTarjetaSinDato : formatoCentavosDeuda(deuda.importeOriginal!),
                              dense: true,
                            ),
                            RisegStatCard(label: l10n.deudasCreditoColumnaPagado, value: formatoCentavosDeuda(totalPagado), dense: true),
                            RisegStatCard(
                              label: l10n.deudasCreditoColumnaSaldoActual,
                              value: formatoCentavosDeuda(deuda.saldoActual),
                              dense: true,
                              deltaTone: deuda.saldoActual > 0 ? RisegStatusTone.warning : RisegStatusTone.success,
                            ),
                            RisegStatCard(
                              label: l10n.deudasCreditoColumnaVencimiento,
                              value: deuda.fechaVencimiento == null ? l10n.deudasCreditoSinVencimiento : _formatoFecha.format(deuda.fechaVencimiento!),
                              dense: true,
                            ),
                          ];
                    return Wrap(
                      spacing: AppSpacing.md,
                      runSpacing: AppSpacing.md,
                      children: [for (final t in tarjetas) SizedBox(width: ancho, child: t)],
                    );
                  },
                ),
                if (esTarjeta) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _TarjetaCreditoCard(deuda: deuda),
                ],
                const SizedBox(height: AppSpacing.lg),
                RisegCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.deudaSeccionInformacionFinanciera, style: AppTypography.heading3.copyWith(color: colors.textPrimary)),
                      const SizedBox(height: AppSpacing.sm),
                      RisegFieldGrid(
                        children: [
                          CampoConsultaDeuda(
                            label: l10n.registrarDeudaCampoFechaOrigen,
                            value: deuda.fechaOrigen == null ? null : _formatoFecha.format(deuda.fechaOrigen!),
                          ),
                          if (!esTarjeta) ...[
                            CampoConsultaDeuda(
                              label: l10n.registrarDeudaCampoPagoProgramado,
                              value: deuda.pagoProgramado == null ? null : formatoCentavosDeuda(deuda.pagoProgramado!),
                            ),
                            CampoConsultaDeuda(
                              label: l10n.registrarDeudaCampoPeriodicidad,
                              value: deuda.periodicidad == null ? null : _periodicidadLabel(l10n, deuda.periodicidad!),
                            ),
                          ],
                          if (!esTarjeta)
                            CampoConsultaDeuda(
                              label: l10n.registrarDeudaCampoTasaInteres,
                              value: deuda.tasaInteres == null ? null : '${deuda.tasaInteres}%',
                            )
                          else
                            CampoConsultaDeuda(
                              label: deuda.tarjetaTipoTasa == TipoTasaTarjeta.variable.name
                                  ? l10n.deudaTarjetaTasaVariableEtiqueta
                                  : l10n.registrarDeudaCampoTasaOrdinariaAnual,
                              value: _formatoTasaTarjeta(l10n, deuda),
                            ),
                          if (esTarjeta && deuda.tarjetaCat != null)
                            CampoConsultaDeuda(label: l10n.deudaTarjetaCat, value: _formatoCat(l10n, deuda)),
                          CampoConsultaDeuda(label: l10n.registrarDeudaCampoReferencia, value: deuda.referencia),
                        ],
                      ),
                      if (deuda.observaciones != null && deuda.observaciones!.trim().isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Text(l10n.registrarDeudaCampoObservaciones, style: AppTypography.label),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(deuda.observaciones!, style: AppTypography.body.copyWith(color: colors.textMuted)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                RisegCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.deudaSeccionHistorial, style: AppTypography.heading3.copyWith(color: colors.textPrimary)),
                      const SizedBox(height: AppSpacing.sm),
                      RisegTableBase<MovimientoDeudaData>(
                        rows: _movimientos,
                        emptyState: Text(l10n.deudaHistorialVacio, style: AppTypography.body.copyWith(color: colors.textMuted)),
                        rowActionsBuilder: (m) {
                          // Etapa 9 — un PAGO ofrece, además de "Ver
                          // egreso", corregirse y cancelarse desde aquí:
                          // su origen es la Deuda, nunca el Egreso que
                          // generó (que Finanzas bloquea a propósito).
                          // Un pago ya cancelado no muestra ninguna de
                          // las dos: no hay acción válida sobre él.
                          final estado = _estadoPorPago[m.id];
                          if (estado != null && !estado.cancelado && deuda.estatus == EstatusDeuda.activa.name) {
                            return Wrap(
                              spacing: AppSpacing.xxs,
                              children: [
                                if (m.egresoId != null)
                                  RisegButton(
                                    label: l10n.deudaBotonVerEgreso,
                                    variant: RisegButtonVariant.ghost,
                                    size: RisegButtonSize.compact,
                                    onPressed: () => _verEgreso(m.egresoId!),
                                  ),
                                if (puedeCorregirPago)
                                  RisegButton(
                                    label: l10n.corregirPagoDeudaBotonAccion,
                                    variant: RisegButtonVariant.ghost,
                                    size: RisegButtonSize.compact,
                                    onPressed: () => _corregirPago(m),
                                  ),
                                if (puedeCancelarPago)
                                  RisegButton(
                                    label: l10n.cancelarPagoDeudaBotonAccion,
                                    variant: RisegButtonVariant.ghost,
                                    size: RisegButtonSize.compact,
                                    onPressed: () => _cancelarPago(m),
                                  ),
                              ],
                            );
                          }
                          if (m.egresoId != null) {
                            return RisegButton(
                              label: l10n.deudaBotonVerEgreso,
                              variant: RisegButtonVariant.ghost,
                              size: RisegButtonSize.compact,
                              onPressed: () => _verEgreso(m.egresoId!),
                            );
                          }
                          // Etapa "Origen financiero de Egresos
                          // manuales": un cargo originado por un gasto
                          // manual pagado con esta tarjeta. `egresoId`
                          // (el Egreso que un PAGO genera) sigue nulo
                          // aquí — el vínculo es `egresoGastoId`, en la
                          // dirección contraria. Mismo botón: para el
                          // operador, ambos llevan al Egreso relevante.
                          if (m.egresoGastoId != null) {
                            return RisegButton(
                              label: l10n.deudaBotonVerEgreso,
                              variant: RisegButtonVariant.ghost,
                              size: RisegButtonSize.compact,
                              onPressed: () => _verEgreso(m.egresoGastoId!),
                            );
                          }
                          if (m.compraId != null) {
                            return RisegButton(
                              label: l10n.deudaBotonVerCompra,
                              variant: RisegButtonVariant.ghost,
                              size: RisegButtonSize.compact,
                              onPressed: () => context.push('/compras/${m.compraId}'),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                        actionsWidth: 120,
                        columns: [
                          RisegColumn<MovimientoDeudaData>(
                            label: l10n.deudaHistorialColumnaFecha,
                            width: 100,
                            cellBuilder: (m) => Text(_formatoFecha.format(m.fecha)),
                          ),
                          RisegColumn<MovimientoDeudaData>(
                            label: l10n.deudaHistorialColumnaTipo,
                            width: 120,
                            cellBuilder: (m) => Text(_movimientoTipoLabel(l10n, m.tipo)),
                          ),
                          RisegColumn<MovimientoDeudaData>(
                            label: l10n.deudaHistorialColumnaConcepto,
                            cellBuilder: (m) => Text(m.observaciones ?? '—', overflow: TextOverflow.ellipsis),
                          ),
                          RisegColumn<MovimientoDeudaData>(
                            label: l10n.deudaHistorialColumnaCargo,
                            alignment: TextAlign.right,
                            width: 110,
                            cellBuilder: (m) => Text(_esCargo(m.tipo) ? formatoCentavosDeuda(m.importe) : '—'),
                          ),
                          RisegColumn<MovimientoDeudaData>(
                            label: l10n.deudaHistorialColumnaPago,
                            alignment: TextAlign.right,
                            width: 110,
                            cellBuilder: (m) => Text(_esCargo(m.tipo) ? '—' : formatoCentavosDeuda(m.importe)),
                          ),
                          RisegColumn<MovimientoDeudaData>(
                            label: l10n.deudaHistorialColumnaSaldo,
                            alignment: TextAlign.right,
                            width: 110,
                            cellBuilder: (m) => Text(formatoCentavosDeuda(m.saldoPosterior), style: AppTypography.bodyStrong),
                          ),
                          // Etapa 9 — estado del pago: cancelado, o
                          // cuántas correcciones acumula. Vacío para
                          // todo lo que no sea un pago.
                          RisegColumn<MovimientoDeudaData>(
                            label: l10n.deudaHistorialColumnaEstado,
                            width: 130,
                            cellBuilder: (m) {
                              final estado = _estadoPorPago[m.id];
                              if (estado == null) return const Text('—');
                              if (estado.cancelado) {
                                return RisegStatusBadge(
                                  label: l10n.deudaPagoEstatusCancelado,
                                  tone: RisegStatusTone.error,
                                );
                              }
                              if (estado.correcciones > 0) {
                                return Text(
                                  l10n.deudaPagoCorregidoVeces(estado.correcciones),
                                  style: AppTypography.caption.copyWith(color: colors.textMuted),
                                );
                              }
                              return const Text('—');
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _periodicidadLabel(AppLocalizations l10n, String periodicidad) {
    return switch (PeriodicidadDeuda.values.byName(periodicidad)) {
      PeriodicidadDeuda.mensual => l10n.registrarDeudaPeriodicidadMensual,
      PeriodicidadDeuda.quincenal => l10n.registrarDeudaPeriodicidadQuincenal,
      PeriodicidadDeuda.semanal => l10n.registrarDeudaPeriodicidadSemanal,
      PeriodicidadDeuda.anual => l10n.registrarDeudaPeriodicidadAnual,
    };
  }
}

/// Tarjeta compacta de tarjeta de crédito empresarial (Etapa 19) —
/// todas las métricas derivadas se calculan aquí, nunca persistidas
/// (mismo criterio que `estaVencida` en Cuentas por cobrar).
class _TarjetaCreditoCard extends StatelessWidget {
  const _TarjetaCreditoCard({required this.deuda});

  final DeudaData deuda;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    final hoy = DateTime.now();
    final fechaCorte = deuda.tarjetaDiaCorte == null ? null : proximaOcurrenciaDiaDelMes(deuda.tarjetaDiaCorte!, hoy);
    // Única fuente de verdad (`proximaFechaPagoDeuda`) — la misma que
    // usan el listado y su KPI "Próximos vencimientos", nunca una
    // segunda implementación aquí.
    final fechaPago = proximaFechaPagoDeuda(deuda, hoy);

    return RisegCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  deuda.tarjetaUltimosDigitos == null ? deuda.nombre : '${deuda.nombre} •••• ${deuda.tarjetaUltimosDigitos}',
                  style: AppTypography.heading3.copyWith(color: colors.textPrimary),
                ),
              ),
              RisegStatusBadge(label: deudaEstatusLabel(l10n, deuda.estatus), tone: deudaEstatusTono(deuda.estatus)),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          RisegFieldGrid(
            children: [
              CampoConsultaDeuda(label: l10n.deudaTarjetaFechaCorte, value: fechaCorte == null ? null : _formatoFecha.format(fechaCorte)),
              CampoConsultaDeuda(label: l10n.deudaTarjetaFechaPago, value: fechaPago == null ? null : _formatoFecha.format(fechaPago)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Campo de solo lectura — mismo criterio que `CampoConsulta` de
/// Organización, reimplementado aquí para no introducir una
/// dependencia cruzada de Finanzas hacia Organización solo por este
/// widget de presentación pura.
class CampoConsultaDeuda extends StatelessWidget {
  const CampoConsultaDeuda({required this.label, required this.value, super.key});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: AppTypography.caption.copyWith(color: colors.textMuted)),
        const SizedBox(height: 2),
        Text(value ?? '-', style: AppTypography.body),
      ],
    );
  }
}
