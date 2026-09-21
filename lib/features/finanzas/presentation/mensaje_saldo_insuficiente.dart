import 'package:flutter/widgets.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/design_system/design_system.dart';

import '../domain/politica_saldo_cuenta.dart';

final _formatoFechaCorte = DateFormat('dd/MM/yyyy');

/// El mismo formato monetario que usan todos los listados del proyecto.
/// Los diez módulos que pueden quedarse sin saldo declaraban por su
/// cuenta un `NumberFormat` idéntico; pedirlo en cada llamada era
/// duplicar justo lo que este archivo existe para centralizar.
final _formatoMoneda = NumberFormat.currency(locale: 'es_MX', symbol: r'$');

/// Formato canónico de importes para los mensajes de saldo.
String formatoImporteSaldo(int centavos) => _formatoMoneda.format(centavos / 100);

/// Traduce un [VeredictoSaldo] al texto que ve el usuario — **el único
/// lugar del proyecto donde se escribe esa traducción**.
///
/// Sin esto, los diez orígenes que pueden quedarse sin saldo acabarían
/// con diez redacciones ligeramente distintas del mismo rechazo, y
/// algunos seguirían diciendo "error inesperado" ante una situación
/// perfectamente esperada y accionable.
///
/// [soportaMulticuenta] cambia sólo la última línea: sugerir repartir el
/// pago entre varias cuentas sería una instrucción falsa en un flujo
/// cuya pantalla todavía no lo permite.
///
/// **La UI sólo presenta.** La regla vive en `PoliticaSaldoCuenta` y se
/// aplica en el embudo financiero; este archivo no decide nada.
String? mensajeDeVeredictoSaldo(
  AppLocalizations l10n,
  VeredictoSaldo veredicto, {
  String Function(int centavos) formatoImporte = formatoImporteSaldo,
  bool soportaMulticuenta = false,
}) {
  return switch (veredicto) {
    SaldoSuficiente() => null,
    SaldoInsuficiente(
      :final cuentaNombre,
      :final disponible,
      :final requerido,
      :final faltante,
    ) =>
      soportaMulticuenta
          ? l10n.saldoInsuficienteConMulticuenta(
              cuentaNombre,
              formatoImporte(disponible),
              formatoImporte(requerido),
              formatoImporte(faltante),
            )
          : l10n.saldoInsuficienteSinMulticuenta(
              cuentaNombre,
              formatoImporte(disponible),
              formatoImporte(requerido),
              formatoImporte(faltante),
            ),
    FechaAnteriorAlSaldoInicial(:final cuentaNombre, :final fechaSaldoInicial) =>
      l10n.saldoFechaAnteriorAlSaldoInicial(cuentaNombre, _formatoFechaCorte.format(fechaSaldoInicial)),
    CuentaNoDisponible() => l10n.saldoCuentaNoDisponible,
  };
}

/// El mismo mensaje a partir de la excepción que lanza el embudo.
String? mensajeDeErrorDeSaldo(
  AppLocalizations l10n,
  Object? error, {
  String Function(int centavos) formatoImporte = formatoImporteSaldo,
  bool soportaMulticuenta = false,
}) {
  if (error is SaldoInsuficienteException) {
    return mensajeDeVeredictoSaldo(
      l10n,
      error.veredicto,
      formatoImporte: formatoImporte,
      soportaMulticuenta: soportaMulticuenta,
    );
  }
  return null;
}

/// Ejecuta [accion] y, si el embudo financiero rechaza por saldo,
/// muestra el mensaje centralizado y devuelve `null`.
///
/// Es el **único** manejador de `SaldoInsuficienteException` en
/// presentación: los orígenes la dejan propagar (ya no la convierten en
/// un "error inesperado") y aquí se traduce una sola vez.
///
/// Devolver `null` encaja con el contrato de `RisegDialog.showForm`: el
/// formulario **sigue abierto**, con los datos capturados intactos, para
/// que el usuario elija otra cuenta sin volver a teclear todo.
Future<T?> ejecutarMostrandoSaldoInsuficiente<T>(
  BuildContext context,
  AppLocalizations l10n,
  Future<T> Function() accion, {
  String Function(int centavos) formatoImporte = formatoImporteSaldo,
  bool soportaMulticuenta = false,
}) async {
  try {
    return await accion();
  } on SaldoInsuficienteException catch (e) {
    final mensaje = mensajeDeVeredictoSaldo(
      l10n,
      e.veredicto,
      formatoImporte: formatoImporte,
      soportaMulticuenta: soportaMulticuenta,
    );
    if (context.mounted && mensaje != null) RisegFeedback.showError(context, mensaje);
    return null;
  }
}
