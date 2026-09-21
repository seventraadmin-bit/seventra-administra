import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/cuenta_financiera_repository.dart';
import 'package:riseg_one/features/finanzas/presentation/egresos/widgets/egreso_detalle_dialog.dart';
import 'package:riseg_one/features/finanzas/presentation/ingresos/widgets/ingreso_detalle_dialog.dart';
import 'package:riseg_one/features/finanzas/presentation/planeacion/planeacion_financiera_controller.dart';
import 'package:riseg_one/features/finanzas/presentation/resumen/resumen_financiero_controller.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

import '../../finanzas_providers.dart';
import 'cuentas_financieras_controller.dart';
import 'cuentas_financieras_list_screen.dart' show cuentaFinancieraTipoLabel, formatoCentavosCuentaFinanciera;
import 'widgets/corregir_cuenta_financiera_dialog.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');

class _CampoConsultaCuentaFinanciera extends StatelessWidget {
  const _CampoConsultaCuentaFinanciera({required this.label, required this.value});

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

/// Expediente de una Cuenta financiera (Etapa 19C, Parte I) — historial
/// unificado de Ingreso/Egreso con saldo acumulado calculado en
/// memoria (nunca persistido, ver el doc comment de
/// `CuentaFinancieraRepository.listarMovimientos`), navegación real a
/// cada movimiento de origen.
class CuentaFinancieraExpedienteScreen extends ConsumerStatefulWidget {
  const CuentaFinancieraExpedienteScreen({required this.cuentaId, super.key});

  final String cuentaId;

  @override
  ConsumerState<CuentaFinancieraExpedienteScreen> createState() => _CuentaFinancieraExpedienteScreenState();
}

class _CuentaFinancieraExpedienteScreenState extends ConsumerState<CuentaFinancieraExpedienteScreen> {
  CuentaFinancieraData? _cuenta;
  List<MovimientoCuentaFinanciera> _movimientos = const [];
  int _saldo = 0;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final repo = ref.read(cuentaFinancieraRepositoryProvider);
    final cuenta = await repo.obtenerPorId(widget.cuentaId);
    final movimientos = cuenta == null ? <MovimientoCuentaFinanciera>[] : await repo.listarMovimientos(widget.cuentaId);
    final saldo = cuenta == null ? 0 : await repo.calcularSaldo(widget.cuentaId);
    if (!mounted) return;
    setState(() {
      _cuenta = cuenta;
      _movimientos = movimientos;
      _saldo = saldo;
      _cargando = false;
    });
  }

  Future<void> _corregir() async {
    final cuenta = _cuenta;
    if (cuenta == null) return;
    final corregida = await mostrarDialogoCorregirCuentaFinanciera(context, ref, cuenta: cuenta);
    if (corregida) {
      await _cargar();
      ref.invalidate(cuentasFinancierasControllerProvider);
    }
  }

  Future<void> _activarDesactivar() async {
    final cuenta = _cuenta;
    if (cuenta == null) return;
    final activa = cuenta.cicloVidaRegistro == 'activo';
    final resultado = activa
        ? await ref.read(desactivarCuentaFinancieraAutorizadoProvider)(cuenta.id)
        : await ref.read(activarCuentaFinancieraAutorizadoProvider)(cuenta.id);
    if (resultado != null) {
      await _cargar();
      // Activar/desactivar cambia qué cuentas cuenta
      // `ObtenerPosicionDeCajaUseCase` — el Resumen debe reflejarlo de
      // inmediato, no solo al volver a entrar a la pestaña.
      ref.invalidate(cuentasFinancierasControllerProvider);
      ref.invalidate(resumenFinancieroControllerProvider);
      ref.invalidate(planeacionFinancieraControllerProvider);
    }
  }

  Future<void> _eliminarFisicamente() async {
    final l10n = AppLocalizations.of(context)!;
    final eliminado = await mostrarDialogoEliminarFisicamente(
      context,
      titulo: l10n.eliminarCuentaFinancieraFisicamenteDialogoTitulo,
      advertencia: l10n.eliminarCuentaFinancieraFisicamenteAdvertencia,
      eliminar: (motivo) async {
        final resultado = await ref.read(eliminarCuentaFinancieraFisicamenteAutorizadoProvider)(cuentaId: widget.cuentaId, motivo: motivo);
        return switch (resultado) {
          EliminarCuentaFinancieraFisicamenteExitoso() => ResultadoEliminacionFisica.exitoso,
          EliminarCuentaFinancieraFisicamenteNoExiste() => ResultadoEliminacionFisica.noExiste,
          EliminarCuentaFinancieraFisicamenteTieneDependencias() => ResultadoEliminacionFisica.tieneDependencias,
          EliminarCuentaFinancieraFisicamenteErrorInesperado() => ResultadoEliminacionFisica.errorInesperado,
        };
      },
    );
    if (eliminado) {
      ref.invalidate(cuentasFinancierasControllerProvider);
      ref.invalidate(resumenFinancieroControllerProvider);
      ref.invalidate(planeacionFinancieraControllerProvider);
      if (mounted) Navigator.of(context).maybePop();
    }
  }

  Future<void> _verMovimiento(MovimientoCuentaFinanciera m) async {
    if (m.esIngreso) {
      await showDialog<void>(context: context, builder: (_) => IngresoDetalleDialog(ingresoId: m.origenId));
    } else {
      await showDialog<void>(context: context, builder: (_) => EgresoDetalleDialog(egresoId: m.origenId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    ref.listen(cuentasFinancierasControllerProvider, (previous, next) {
      if (previous != null) _cargar();
    });

    if (_cargando) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final cuenta = _cuenta;
    if (cuenta == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.cuentasFinancierasListadoTitulo)),
        body: RisegEmptyState(
          icon: Icons.error_outline,
          title: l10n.cuentasFinancierasListadoCargaErrorTitulo,
          message: l10n.cuentasFinancierasListadoCargaErrorMensaje,
        ),
      );
    }

    final esMaestro = ref.watch(sesionControllerProvider)?.esMaestro ?? false;
    final activa = cuenta.cicloVidaRegistro == 'activo';
    var saldoAcumulado = cuenta.saldoInicial;
    final filas = <(MovimientoCuentaFinanciera movimiento, int saldoAcumulado)>[];
    for (final m in _movimientos) {
      saldoAcumulado = saldoAcumulado + m.entrada - m.salida;
      filas.add((m, saldoAcumulado));
    }

    return Scaffold(
      appBar: AppBar(title: Text(cuenta.nombre)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RisegSectionHeader(
                  title: cuenta.nombre,
                  description: '${cuenta.codigo} · ${cuentaFinancieraTipoLabel(l10n, cuenta.tipo)}',
                  primaryAction: Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      RisegStatusBadge(
                        label: activa ? l10n.cuentaFinancieraEstatusActiva : l10n.cuentaFinancieraEstatusInactiva,
                        tone: activa ? RisegStatusTone.success : RisegStatusTone.neutral,
                      ),
                      RisegButton(label: l10n.editarDeudaBotonConfirmar, variant: RisegButtonVariant.secondary, onPressed: _corregir),
                      RisegActionsMenu(
                        menuKey: const Key('cuenta_financiera_expediente_menu_acciones'),
                        actions: [
                          RisegMenuAction(
                            label: activa ? l10n.cuentaFinancieraBotonDesactivar : l10n.cuentaFinancieraBotonActivar,
                            icon: activa ? Icons.pause_circle_outlined : Icons.play_circle_outline,
                            onTap: _activarDesactivar,
                          ),
                          if (esMaestro)
                            RisegMenuAction(
                              key: const Key('cuenta_financiera_expediente_boton_eliminar_fisicamente'),
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
                    final columnas = constraints.maxWidth < AppBreakpoints.compact ? 2 : 3;
                    final ancho = (constraints.maxWidth - (AppSpacing.md * (columnas - 1))) / columnas;
                    final tarjetas = [
                      RisegStatCard(label: l10n.registrarCuentaFinancieraCampoSaldoInicial, value: formatoCentavosCuentaFinanciera(cuenta.saldoInicial), dense: true),
                      RisegStatCard(
                        label: l10n.cuentasFinancierasColumnaSaldo,
                        value: formatoCentavosCuentaFinanciera(_saldo),
                        dense: true,
                        deltaTone: _saldo >= 0 ? RisegStatusTone.success : RisegStatusTone.warning,
                      ),
                      RisegStatCard(label: l10n.registrarCuentaFinancieraCampoFechaSaldoInicial, value: _formatoFecha.format(cuenta.fechaSaldoInicial), dense: true),
                    ];
                    return Wrap(
                      spacing: AppSpacing.md,
                      runSpacing: AppSpacing.md,
                      children: [for (final t in tarjetas) SizedBox(width: ancho, child: t)],
                    );
                  },
                ),
                const SizedBox(height: AppSpacing.lg),
                RisegCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.cuentaFinancieraSeccionDatos, style: AppTypography.heading3.copyWith(color: colors.textPrimary)),
                      const SizedBox(height: AppSpacing.sm),
                      RisegFieldGrid(
                        children: [
                          _CampoConsultaCuentaFinanciera(label: l10n.registrarCuentaFinancieraCampoUltimosDigitos, value: cuenta.ultimosDigitos),
                          _CampoConsultaCuentaFinanciera(label: l10n.registrarCuentaFinancieraCampoObservaciones, value: cuenta.observaciones),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                RisegCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.cuentaFinancieraSeccionHistorial, style: AppTypography.heading3.copyWith(color: colors.textPrimary)),
                      const SizedBox(height: AppSpacing.sm),
                      RisegTableBase<(MovimientoCuentaFinanciera, int)>(
                        rows: filas,
                        emptyState: Text(l10n.cuentaFinancieraHistorialVacio, style: AppTypography.body.copyWith(color: colors.textMuted)),
                        rowActionsBuilder: (fila) => RisegButton(
                          label: l10n.deudaBotonVerEgreso,
                          variant: RisegButtonVariant.ghost,
                          size: RisegButtonSize.compact,
                          onPressed: () => _verMovimiento(fila.$1),
                        ),
                        actionsWidth: 100,
                        columns: [
                          RisegColumn<(MovimientoCuentaFinanciera, int)>(
                            label: l10n.deudaHistorialColumnaFecha,
                            width: 100,
                            cellBuilder: (f) => Text(_formatoFecha.format(f.$1.fecha)),
                          ),
                          RisegColumn<(MovimientoCuentaFinanciera, int)>(
                            label: l10n.cuentaFinancieraHistorialColumnaMovimiento,
                            cellBuilder: (f) => Text(f.$1.concepto, overflow: TextOverflow.ellipsis),
                          ),
                          RisegColumn<(MovimientoCuentaFinanciera, int)>(
                            label: l10n.cuentaFinancieraHistorialColumnaReferencia,
                            width: 120,
                            cellBuilder: (f) => Text(f.$1.referencia, overflow: TextOverflow.ellipsis),
                          ),
                          RisegColumn<(MovimientoCuentaFinanciera, int)>(
                            label: l10n.cuentaFinancieraHistorialColumnaEntrada,
                            alignment: TextAlign.right,
                            width: 110,
                            cellBuilder: (f) => Text(f.$1.entrada > 0 ? formatoCentavosCuentaFinanciera(f.$1.entrada) : '—'),
                          ),
                          RisegColumn<(MovimientoCuentaFinanciera, int)>(
                            label: l10n.cuentaFinancieraHistorialColumnaSalida,
                            alignment: TextAlign.right,
                            width: 110,
                            cellBuilder: (f) => Text(f.$1.salida > 0 ? formatoCentavosCuentaFinanciera(f.$1.salida) : '—'),
                          ),
                          RisegColumn<(MovimientoCuentaFinanciera, int)>(
                            label: l10n.cuentaFinancieraHistorialColumnaSaldoAcumulado,
                            alignment: TextAlign.right,
                            width: 130,
                            cellBuilder: (f) => Text(formatoCentavosCuentaFinanciera(f.$2), style: AppTypography.bodyStrong),
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
}
