import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show FormaPago;
import 'package:riseg_one/features/finanzas/domain/usecases/calcular_fecha_tarjeta_usecase.dart';
import 'package:riseg_one/features/finanzas/finanzas_providers.dart';
import 'package:riseg_one/features/finanzas/presentation/deudas_credito/deudas_credito_list_screen.dart'
    show formatoCentavosDeuda;

/// Catálogos necesarios para elegir el origen de pago de una recarga.
///
/// Se cargan UNA vez antes de abrir el diálogo — nunca por frame ni por
/// renglón. Ver §37: poder elegir la cuenta/tarjeta para pagar una
/// recarga no otorga `finanzas.ver`; es exactamente el mismo criterio
/// que ya aplica Tiempos Extra.
class OpcionesOrigenRecarga {
  const OpcionesOrigenRecarga({required this.cuentas, required this.tarjetas});

  final List<CuentaFinancieraData> cuentas;
  final List<DeudaData> tarjetas;
}

Future<OpcionesOrigenRecarga> cargarOpcionesOrigenRecarga(WidgetRef ref) async {
  final cuentas = await ref.read(cuentaFinancieraRepositoryProvider).listar(soloActivas: true);
  final tarjetas = await ref.read(deudaRepositoryProvider).listarTarjetasActivas();
  return OpcionesOrigenRecarga(cuentas: cuentas, tarjetas: tarjetas);
}

/// Qué eligió el usuario. `formaPago == tarjeta` es el discriminador,
/// exactamente igual que en Compras/Tiempos Extra/Egresos — nunca un
/// catálogo nuevo (§9).
class OrigenFinancieroRecarga {
  const OrigenFinancieroRecarga({
    this.formaPago = '',
    this.cuentaFinancieraId,
    this.deudaIdTarjeta,
  });

  final String formaPago;
  final String? cuentaFinancieraId;
  final String? deudaIdTarjeta;

  bool get esTarjeta => formaPago == FormaPago.tarjeta.name;
  bool get tieneFormaPago => formaPago.isNotEmpty;

  /// Mensaje a mostrar si falta algo, o `null` si está completo. El
  /// dominio vuelve a exigirlo — esto sólo evita un viaje inútil.
  String? errorFaltante(AppLocalizations l10n) {
    if (!tieneFormaPago) return l10n.recargaOrigenFinancieroRequerido;
    if (esTarjeta) return deudaIdTarjeta == null ? l10n.recargaTarjetaRequerida : null;
    return cuentaFinancieraId == null ? l10n.recargaCuentaRequerida : null;
  }

  OrigenFinancieroRecarga conFormaPago(String nueva) {
    // Cambiar de forma de pago limpia el origen anterior: nunca se
    // manda cuenta Y tarjeta a la vez.
    return OrigenFinancieroRecarga(formaPago: nueva);
  }

  OrigenFinancieroRecarga conCuenta(String? id) =>
      OrigenFinancieroRecarga(formaPago: formaPago, cuentaFinancieraId: id);

  OrigenFinancieroRecarga conTarjeta(String? id) =>
      OrigenFinancieroRecarga(formaPago: formaPago, deudaIdTarjeta: id);
}

/// Los campos de "Origen de pago" de una recarga — forma de pago y,
/// según ella, Cuenta de origen o Tarjeta. Mismo comportamiento y
/// mismas etiquetas que el selector de Tiempos Extra; se comparte entre
/// Registrar y Corregir para no tener dos formularios que diverjan.
List<Widget> camposOrigenFinancieroRecarga({
  required AppLocalizations l10n,
  required OpcionesOrigenRecarga opciones,
  required OrigenFinancieroRecarga seleccion,
  required ValueChanged<OrigenFinancieroRecarga> onCambio,
}) {
  return [
    RisegSelect<String>(
      key: const Key('recarga_campo_forma_pago'),
      label: l10n.recargaCampoOrigenPago,
      value: seleccion.tieneFormaPago ? seleccion.formaPago : null,
      items: [
        for (final f in FormaPago.values)
          RisegSelectItem(value: f.name, label: _formaPagoLabel(l10n, f)),
      ],
      onChanged: (valor) => onCambio(seleccion.conFormaPago(valor ?? '')),
    ),
    if (seleccion.tieneFormaPago) ...[
      const SizedBox(height: AppSpacing.md),
      if (seleccion.esTarjeta)
        RisegSelect<String?>(
          key: const Key('recarga_campo_tarjeta'),
          label: l10n.recargaCampoTarjeta,
          value: seleccion.deudaIdTarjeta,
          items: [
            for (final t in opciones.tarjetas)
              RisegSelectItem(value: t.id, label: '${t.nombre} · ${_disponible(l10n, t)}'),
          ],
          onChanged: (valor) => onCambio(seleccion.conTarjeta(valor)),
        )
      else
        RisegSelect<String?>(
          key: const Key('recarga_campo_cuenta'),
          label: l10n.recargaCampoCuentaOrigen,
          value: seleccion.cuentaFinancieraId,
          items: [for (final c in opciones.cuentas) RisegSelectItem(value: c.id, label: c.nombre)],
          onChanged: (valor) => onCambio(seleccion.conCuenta(valor)),
        ),
    ],
  ];
}

String _disponible(AppLocalizations l10n, DeudaData tarjeta) {
  final disponible =
      creditoDisponibleTarjeta(limiteCredito: tarjeta.tarjetaLimiteCredito, saldoActual: tarjeta.saldoActual);
  return disponible == null ? l10n.deudaTarjetaSinDato : formatoCentavosDeuda(disponible);
}

String _formaPagoLabel(AppLocalizations l10n, FormaPago forma) {
  return switch (forma) {
    FormaPago.efectivo => l10n.formaPagoEfectivo,
    FormaPago.transferencia => l10n.formaPagoTransferencia,
    FormaPago.cheque => l10n.formaPagoCheque,
    FormaPago.tarjeta => l10n.formaPagoTarjeta,
    FormaPago.otro => l10n.formaPagoOtro,
  };
}
