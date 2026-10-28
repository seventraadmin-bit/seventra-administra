import 'package:riseg_one/features/finanzas/presentation/mensaje_saldo_insuficiente.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show FormaPago;
import 'package:riseg_one/features/finanzas/finanzas_providers.dart' show cuentaFinancieraRepositoryProvider;
import 'package:riseg_one/features/finanzas/presentation/pagos/pagos_list_screen.dart'
    show formaPagoLabel, formatoCentavosPago;
import 'package:riseg_one/features/personal/personal_providers.dart';
import 'package:riseg_one/features/personal/presentation/empleados/empleados_list_screen.dart'
    show empleadoNombreCompleto;

import '../../domain/usecases/generar_plan_cuotas.dart';
import '../../domain/usecases/registrar_descuento_programado_usecase.dart';
import '../../domain/usecases/sugerir_primera_fecha_descuento.dart';
import '../descuentos_personal_controller.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');

enum _FormaRecuperacion { unico, parcialidades }

/// Eje independiente de [tipo] (Etapa "Cierre del ciclo financiero de
/// Descuentos Programados") — la SEÑAL real de si hubo un desembolso es
/// esto, nunca el valor de `tipo` (catálogo abierto). `tipo` solo
/// prellena un valor inicial razonable (préstamo→entrega,
/// botas→recuperación), siempre editable por el operador.
enum _OrigenObligacion { entregaDinero, recuperacionConcepto }

/// Costo sugerido de un par de botas (Etapa 15, Resolución explícita de
/// Marlon) — solo prellena el diálogo, NUNCA una regla de dominio
/// forzada: el importe/número de cuotas quedan editables antes de
/// confirmar.
const costoBotasSugeridoDefault = 70000;
const numeroParcialidadesSugeridoBotas = 2;

int? _centavosDesdeTexto(String texto) {
  final normalizado = texto.trim().replaceAll(',', '');
  if (normalizado.isEmpty) return null;
  final pesos = double.tryParse(normalizado);
  if (pesos == null) return null;
  return (pesos * 100).round();
}

/// Diálogo "Registrar descuento" (Etapa 15) — préstamo o costo de
/// botas, con previsualización en vivo del plan de recuperación
/// (`generarPlanCuotas`, la misma función que se va a persistir).
Future<bool> mostrarDialogoRegistrarDescuentoProgramado(
  BuildContext context,
  WidgetRef ref, {
  String? empleadoIdPreseleccionado,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final empleados = await ref
      .read(empleadoRepositoryProvider)
      .listar(estatus: 'activo');
  final cuentasFinancieras = await ref.read(cuentaFinancieraRepositoryProvider).listar(soloActivas: true);
  if (!context.mounted) return false;

  String tipo = 'prestamo';
  String? empleadoId = empleadoIdPreseleccionado;
  final importeCtrl = TextEditingController();
  DateTime fechaRegistro = DateTime.now();
  _FormaRecuperacion forma = _FormaRecuperacion.parcialidades;
  final numeroCuotasCtrl = TextEditingController(text: '2');
  DateTime? fechaPrimeraCuota = sugerirPrimeraFechaDescuento(DateTime.now());
  final observacionesCtrl = TextEditingController();
  // Prellenado por `tipo`, siempre editable — nunca derivado en
  // silencio al confirmar (ver el doc comment de `_OrigenObligacion`).
  _OrigenObligacion origen = _OrigenObligacion.entregaDinero;
  String? cuentaFinancieraId;
  FormaPago formaPagoEgreso = FormaPago.transferencia;
  String? errorGeneral;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.registrarDescuentoProgramadoDialogoTitulo,
    confirmLabel: l10n.registrarDescuentoProgramadoBotonConfirmar,
    cancelLabel: l10n.registrarDescuentoProgramadoBotonCancelar,
    contentBuilder:
        (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setState) {
            final importe = _centavosDesdeTexto(importeCtrl.text);
            final numeroCuotas =
                forma == _FormaRecuperacion.unico
                    ? 1
                    : int.tryParse(numeroCuotasCtrl.text.trim());
            final plan =
                (importe != null &&
                        importe > 0 &&
                        numeroCuotas != null &&
                        numeroCuotas > 0 &&
                        fechaPrimeraCuota != null)
                    ? generarPlanCuotas(
                      importeOriginal: importe,
                      numeroCuotas: numeroCuotas,
                      fechaPrimera: fechaPrimeraCuota!,
                    )
                    : const <CuotaPlan>[];

            return SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RisegSelect<String>(
                      label: l10n.registrarDescuentoProgramadoCampoTipo,
                      value: tipo,
                      items: [
                        RisegSelectItem(
                          value: 'prestamo',
                          label: l10n.descuentosPersonalTipoPrestamo,
                        ),
                        RisegSelectItem(
                          value: 'botas',
                          label: l10n.descuentosPersonalTipoBotas,
                        ),
                      ],
                      onChanged:
                          (valor) => setState(() {
                            tipo = valor ?? tipo;
                            if (tipo == 'botas') {
                              if (importeCtrl.text.trim().isEmpty) {
                                importeCtrl.text = (costoBotasSugeridoDefault /
                                        100)
                                    .toStringAsFixed(2);
                              }
                              forma = _FormaRecuperacion.parcialidades;
                              numeroCuotasCtrl.text =
                                  '$numeroParcialidadesSugeridoBotas';
                              origen = _OrigenObligacion.recuperacionConcepto;
                            } else {
                              origen = _OrigenObligacion.entregaDinero;
                            }
                          }),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    RisegSelect<_OrigenObligacion>(
                      label: l10n.registrarDescuentoProgramadoCampoOrigenObligacion,
                      value: origen,
                      items: [
                        RisegSelectItem(
                          value: _OrigenObligacion.entregaDinero,
                          label: l10n.registrarDescuentoProgramadoOrigenEntregaDinero,
                        ),
                        RisegSelectItem(
                          value: _OrigenObligacion.recuperacionConcepto,
                          label: l10n.registrarDescuentoProgramadoOrigenRecuperacionConcepto,
                        ),
                      ],
                      onChanged: (valor) => setState(() => origen = valor ?? origen),
                    ),
                    if (origen == _OrigenObligacion.entregaDinero) ...[
                      const SizedBox(height: AppSpacing.md),
                      RisegSelect<String?>(
                        label: l10n.registrarDescuentoProgramadoCampoCuentaOrigen,
                        value: cuentaFinancieraId,
                        items: [
                          for (final c in cuentasFinancieras) RisegSelectItem(value: c.id, label: c.nombre),
                        ],
                        onChanged: (valor) => setState(() => cuentaFinancieraId = valor),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      RisegSelect<FormaPago>(
                        label: l10n.registrarDescuentoProgramadoCampoFormaPago,
                        value: formaPagoEgreso,
                        items: [
                          for (final f in FormaPago.values)
                            if (f != FormaPago.tarjeta) RisegSelectItem(value: f, label: formaPagoLabel(l10n, f.name)),
                        ],
                        onChanged: (valor) => setState(() => formaPagoEgreso = valor ?? formaPagoEgreso),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    RisegSelect<String?>(
                      label: l10n.registrarDescuentoProgramadoCampoEmpleado,
                      value: empleadoId,
                      items: [
                        for (final e in empleados)
                          RisegSelectItem(
                            value: e.id,
                            label: empleadoNombreCompleto(e),
                          ),
                      ],
                      onChanged: (valor) => setState(() => empleadoId = valor),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    RisegTextField(
                      label: l10n.registrarDescuentoProgramadoCampoImporte,
                      controller: importeCtrl,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    RisegDateField(
                      label: l10n.registrarDescuentoProgramadoCampoFecha,
                      value: fechaRegistro,
                      onChanged:
                          (valor) => setState(() => fechaRegistro = valor),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      l10n.registrarDescuentoProgramadoCampoFormaRecuperacion,
                      style: AppTypography.label,
                    ),
                    Row(
                      children: [
                        Radio<_FormaRecuperacion>(
                          value: _FormaRecuperacion.unico,
                          groupValue: forma,
                          onChanged:
                              (valor) => setState(() => forma = valor ?? forma),
                        ),
                        Text(l10n.registrarDescuentoProgramadoFormaUnico),
                        const SizedBox(width: AppSpacing.md),
                        Radio<_FormaRecuperacion>(
                          value: _FormaRecuperacion.parcialidades,
                          groupValue: forma,
                          onChanged:
                              (valor) => setState(() => forma = valor ?? forma),
                        ),
                        Text(
                          l10n.registrarDescuentoProgramadoFormaParcialidades,
                        ),
                      ],
                    ),
                    if (forma == _FormaRecuperacion.parcialidades) ...[
                      const SizedBox(height: AppSpacing.sm),
                      RisegTextField(
                        label:
                            l10n.registrarDescuentoProgramadoCampoNumeroCuotas,
                        controller: numeroCuotasCtrl,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setState(() {}),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    RisegDateField(
                      label: l10n.registrarDescuentoProgramadoCampoPrimeraFecha,
                      value: fechaPrimeraCuota,
                      onChanged:
                          (valor) => setState(() => fechaPrimeraCuota = valor),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    RisegTextField(
                      label:
                          l10n.registrarDescuentoProgramadoCampoObservaciones,
                      controller: observacionesCtrl,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      l10n.registrarDescuentoProgramadoSeccionPrevisualizacion,
                      style: AppTypography.label,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    if (plan.isEmpty)
                      Text(
                        l10n.registrarDescuentoProgramadoPrevisualizacionVacia,
                        style: AppTypography.caption,
                      )
                    else ...[
                      for (final cuota in plan)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  l10n.registrarDescuentoProgramadoPrevisualizacionCuota(
                                    cuota.numeroCuota,
                                    plan.length,
                                  ),
                                ),
                              ),
                              Text(_formatoFecha.format(cuota.fechaProgramada)),
                              const SizedBox(width: AppSpacing.md),
                              Text(formatoCentavosPago(cuota.importe)),
                            ],
                          ),
                        ),
                      const Divider(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            l10n.registrarDescuentoProgramadoPrevisualizacionTotal,
                            style: AppTypography.label,
                          ),
                          Text(
                            formatoCentavosPago(
                              plan.fold<int>(0, (s, c) => s + c.importe),
                            ),
                            style: AppTypography.label,
                          ),
                        ],
                      ),
                    ],
                    if (errorGeneral != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        errorGeneral!,
                        style: AppTypography.caption.copyWith(
                          color: Theme.of(dialogContext).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
    onConfirm: () async {
      final empleado = empleadoId;
      if (empleado == null) {
        errorGeneral = l10n.registrarDescuentoProgramadoErrorEmpleadoRequerido;
        return null;
      }
      final importe = _centavosDesdeTexto(importeCtrl.text);
      if (importe == null || importe <= 0) {
        errorGeneral = l10n.registrarDescuentoProgramadoErrorImporteInvalido;
        return null;
      }
      final numeroCuotas =
          forma == _FormaRecuperacion.unico
              ? 1
              : int.tryParse(numeroCuotasCtrl.text.trim());
      if (numeroCuotas == null || numeroCuotas <= 0) {
        errorGeneral =
            l10n.registrarDescuentoProgramadoErrorNumeroCuotasInvalido;
        return null;
      }
      if (fechaPrimeraCuota == null) {
        errorGeneral = l10n.registrarDescuentoProgramadoCampoPrimeraFecha;
        return null;
      }
      final esEntregaDinero = origen == _OrigenObligacion.entregaDinero;
      if (esEntregaDinero && cuentaFinancieraId == null) {
        errorGeneral = l10n.registrarDescuentoProgramadoErrorCuentaRequerida;
        return null;
      }

      // Saldo insuficiente no es un "error inesperado": lo traduce el
      // mecanismo central y el formulario sigue abierto, con lo ya
      // capturado, para que el usuario elija otra cuenta.
      final resultado = await ejecutarMostrandoSaldoInsuficiente(
        context,
        l10n,
        () => ref
          .read(descuentosPersonalControllerProvider.notifier)
          .registrar(
            empleadoId: empleado,
            tipo: tipo,
            fechaRegistro: fechaRegistro,
            importeOriginal: importe,
            numeroCuotas: numeroCuotas,
            fechaPrimeraCuota: fechaPrimeraCuota!,
            observaciones:
                observacionesCtrl.text.trim().isEmpty
                    ? null
                    : observacionesCtrl.text.trim(),
            esEntregaDinero: esEntregaDinero,
            cuentaFinancieraId: esEntregaDinero ? cuentaFinancieraId : null,
            formaPagoEgreso: esEntregaDinero ? formaPagoEgreso.name : null,
          ),
      );
      if (resultado == null) return null;
      if (!context.mounted) return false;

      switch (resultado) {
        case RegistrarDescuentoProgramadoExitoso():
          RisegFeedback.showSuccess(
            context,
            l10n.registrarDescuentoProgramadoExito,
          );
          return true;
        case RegistrarDescuentoProgramadoEmpleadoNoExiste():
        case RegistrarDescuentoProgramadoEmpleadoNoActivo():
          errorGeneral = l10n.registrarDescuentoProgramadoErrorEmpleadoNoActivo;
          return null;
        case RegistrarDescuentoProgramadoImporteInvalido():
          errorGeneral = l10n.registrarDescuentoProgramadoErrorImporteInvalido;
          return null;
        case RegistrarDescuentoProgramadoNumeroCuotasInvalido():
          errorGeneral =
              l10n.registrarDescuentoProgramadoErrorNumeroCuotasInvalido;
          return null;
        case RegistrarDescuentoProgramadoCuentaFinancieraRequerida():
          errorGeneral = l10n.registrarDescuentoProgramadoErrorCuentaRequerida;
          return null;
        case RegistrarDescuentoProgramadoErrorInesperado():
          RisegFeedback.showError(
            context,
            l10n.registrarDescuentoProgramadoErrorInesperado,
          );
          return false;
      }
    },
  );

  importeCtrl.dispose();
  numeroCuotasCtrl.dispose();
  observacionesCtrl.dispose();

  return resultado ?? false;
}
