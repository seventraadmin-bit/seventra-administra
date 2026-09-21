import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/domain/origen_financiero_gasto.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/calcular_fecha_tarjeta_usecase.dart' show creditoDisponibleTarjeta;

import '../deudas_credito/deudas_credito_list_screen.dart' show formatoCentavosDeuda;

/// Clave estable de una opción del selector — `null` es "sin
/// especificar", `'cuenta:<id>'` una `CuentaFinanciera`, `'tarjeta:<id>'`
/// una `Deuda` de tipo tarjeta. Se usa una clave de texto (y no el
/// propio [OrigenFinancieroGasto]) porque `RisegSelect` compara sus
/// valores por igualdad, y las clases selladas del dominio son
/// deliberadamente simples, sin `==`/`hashCode` — inventarles identidad
/// de valor solo para alimentar un dropdown sería el tipo de acoplamiento
/// UI→dominio que este proyecto evita.
typedef ClaveOrigenFinanciero = String;

const String _prefijoCuenta = 'cuenta:';
const String _prefijoTarjeta = 'tarjeta:';

/// Clave de selector correspondiente al origen que un `Egreso` ya tiene
/// persistido — `null` si no tiene ninguno ("sin especificar").
ClaveOrigenFinanciero? claveOrigenDeEgreso(EgresoData egreso) {
  if (egreso.deudaId != null) return '$_prefijoTarjeta${egreso.deudaId}';
  if (egreso.cuentaFinancieraId != null) return '$_prefijoCuenta${egreso.cuentaFinancieraId}';
  return null;
}

/// Clave de selector para un origen ya persistido en cualquier entidad
/// que use el par `cuentaFinancieraId`/`deudaId` — Compras, Tiempos
/// Extra y, desde la v80, el mantenimiento de Vehículos. Existe para que
/// los prefijos `cuenta:`/`tarjeta:` se armen en UN solo lugar: cada
/// pantalla que los concatenara a mano sería una forma más de
/// equivocarse.
ClaveOrigenFinanciero? claveOrigenDe({String? cuentaFinancieraId, String? deudaId}) {
  if (deudaId != null) return '$_prefijoTarjeta$deudaId';
  if (cuentaFinancieraId != null) return '$_prefijoCuenta$cuentaFinancieraId';
  return null;
}

/// Traduce la selección de la UI al tipo de dominio. `null` (sin
/// especificar) devuelve `null`, que es exactamente lo que
/// `RegistrarEgresoUseCase`/`CorregirEgresoUseCase` entienden como
/// "sin origen" — nunca un tercer caso.
OrigenFinancieroGasto? origenDesdeClave(ClaveOrigenFinanciero? clave) {
  if (clave == null) return null;
  if (clave.startsWith(_prefijoCuenta)) {
    return OrigenFinancieroCuenta(clave.substring(_prefijoCuenta.length));
  }
  if (clave.startsWith(_prefijoTarjeta)) {
    return OrigenFinancieroTarjeta(clave.substring(_prefijoTarjeta.length));
  }
  return null;
}

/// Mensaje al usuario para cada motivo por el que una TDC no puede
/// financiar un gasto — una sola traducción de [ErrorOrigenTarjeta],
/// compartida por el alta y la corrección (nunca dos textos distintos
/// para el mismo rechazo).
String mensajeErrorOrigenTarjeta(AppLocalizations l10n, ErrorOrigenTarjeta error, int? disponible) {
  return switch (error) {
    ErrorOrigenTarjeta.noEsTarjetaActiva => l10n.egresoErrorTarjetaNoActiva,
    ErrorOrigenTarjeta.sinLimiteConfigurado => l10n.egresoErrorTarjetaSinLimite,
    ErrorOrigenTarjeta.excedeLimite =>
      l10n.egresoErrorTarjetaExcedeLimite(disponible == null ? l10n.deudaTarjetaSinDato : formatoCentavosDeuda(disponible)),
  };
}

/// Selector único de "Origen financiero" de un gasto — Cuentas
/// financieras y Tarjetas de crédito en una sola lista agrupada (Etapa
/// "Origen financiero de Egresos manuales: Cuenta vs. TDC").
///
/// Un solo selector, y no "tipo de origen + selector dependiente"
/// (la otra forma que el pedido admitía) porque para el operador la
/// pregunta real es una sola —"¿de dónde salió?"— y la respuesta cabe
/// en una lista corta y completa: BBVA, Klar, TDC Konfío, TDC Clara.
/// Dos controles encadenados agregarían un paso sin agregar
/// información, justo lo que la filosofía de simplicidad del proyecto
/// evita.
///
/// Las tarjetas muestran su crédito disponible en la propia etiqueta,
/// derivado siempre de [creditoDisponibleTarjeta] — nunca una segunda
/// fórmula `límite - saldo` por fuera. Una tarjeta sin límite capturado
/// se ofrece igual (con "Sin dato"): quien valida de verdad es
/// `validarOrigenTarjeta` en el caso de uso, con un mensaje explícito,
/// nunca un ítem oculto sin explicación.
class RisegOrigenFinancieroSelect extends StatelessWidget {
  const RisegOrigenFinancieroSelect({
    required this.cuentas,
    required this.tarjetas,
    required this.value,
    required this.onChanged,
    this.errorText,
    super.key,
  });

  final List<CuentaFinancieraData> cuentas;
  final List<DeudaData> tarjetas;
  final ClaveOrigenFinanciero? value;
  final ValueChanged<ClaveOrigenFinanciero?> onChanged;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    // La opción actual puede apuntar a una tarjeta/cuenta que ya no
    // está en la lista (desactivada, o una TDC no activa que financió
    // el gasto en su momento). Sin este resguardo `RisegSelect` no
    // encontraría su `value` entre los ítems y quedaría en blanco,
    // borrando en silencio el origen real al confirmar.
    final claves = {
      for (final c in cuentas) '$_prefijoCuenta${c.id}',
      for (final t in tarjetas) '$_prefijoTarjeta${t.id}',
    };
    final valorHuerfano = value != null && !claves.contains(value);

    return RisegSelect<ClaveOrigenFinanciero?>(
      label: l10n.egresoCampoOrigenFinanciero,
      value: value,
      errorText: errorText,
      helperText: l10n.egresoOrigenFinancieroAyuda,
      items: [
        RisegSelectItem(value: null, label: l10n.egresoCampoSinAsignar),
        for (final c in cuentas) RisegSelectItem(value: '$_prefijoCuenta${c.id}', label: c.nombre),
        for (final t in tarjetas)
          RisegSelectItem(
            value: '$_prefijoTarjeta${t.id}',
            label: l10n.egresoOrigenTarjetaOpcion(t.nombre, _disponibleTexto(l10n, t)),
          ),
        if (valorHuerfano) RisegSelectItem(value: value, label: l10n.egresoOrigenFinancieroNoDisponible),
      ],
      onChanged: onChanged,
    );
  }

  String _disponibleTexto(AppLocalizations l10n, DeudaData tarjeta) {
    final disponible = creditoDisponibleTarjeta(limiteCredito: tarjeta.tarjetaLimiteCredito, saldoActual: tarjeta.saldoActual);
    return disponible == null ? l10n.deudaTarjetaSinDato : formatoCentavosDeuda(disponible);
  }
}
