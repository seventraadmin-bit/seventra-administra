import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dashboard/presentation/dashboard_controller.dart';
import 'cuentas_financieras/cuentas_financieras_controller.dart';
import 'deudas_credito/deudas_credito_controller.dart';
import 'egresos/egresos_controller.dart';
import 'ingresos/ingresos_controller.dart';
import 'planeacion/planeacion_financiera_controller.dart';
import 'resumen/resumen_financiero_controller.dart';

/// **La única lista de consumidores financieros del proyecto.**
///
/// Antes existía como método privado, ligeramente distinto, en tres
/// controladores (Egresos, Servicios Eventuales, Telefonía), y cada
/// módulo nuevo inventaba la suya: así nació el fallo real en que
/// corregir el origen de un Egreso dejaba "Caja y bancos" del Dashboard
/// mostrando el importe viejo. Una lista compartida es lo que impide
/// que el próximo flujo financiero nazca con una cuarta versión.
///
/// Se invalida **después** de que la mutación ya está persistida, nunca
/// antes: un provider reconstruido a mitad de la escritura leería el
/// estado intermedio.
extension InvalidacionFinanciera on Ref {
  /// Todo lo que depende del saldo de las cuentas.
  ///
  /// [tocaDeudas] existe porque no toda mutación financiera cambia una
  /// Deuda: un gasto pagado desde cuenta no la toca, y invalidar por
  /// costumbre sólo provoca recargas inútiles. Se pasa `true` cuando la
  /// operación crea, paga, corrige o revierte un `MovimientoDeuda`
  /// —gasto con TDC, pago de tarjeta, cancelación de cualquiera de los
  /// dos—, y se deja en `false` en el resto.
  /// [omitir] existe por una regla de Riverpod, no por gusto: un
  /// provider no puede invalidarse a sí mismo. El controlador de
  /// Egresos, que es quien más llama a esto, tiene que excluirse —
  /// ya se recarga solo tras su propia mutación.
  void invalidarConsumidoresFinancieros({
    bool tocaDeudas = false,
    Set<ProviderOrFamily> omitir = const {},
  }) {
    final objetivos = <ProviderOrFamily>[
      dashboardControllerProvider,
      resumenFinancieroControllerProvider,
      planeacionFinancieraControllerProvider,
      cuentasFinancierasControllerProvider,
      egresosControllerProvider,
      ingresosControllerProvider,
      if (tocaDeudas) deudasCreditoControllerProvider,
    ];
    for (final objetivo in objetivos) {
      if (!omitir.contains(objetivo)) invalidate(objetivo);
    }
  }
}
