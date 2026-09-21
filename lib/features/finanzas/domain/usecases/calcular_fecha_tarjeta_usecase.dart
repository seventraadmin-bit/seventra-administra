import '../../../../core/database/app_database.dart';
import '../../data/tables/deuda_table.dart' show ReglaFechaLimitePagoTarjeta, TipoDeuda;

/// Próxima ocurrencia de un "día del mes" (`tarjetaDiaCorte`/
/// `tarjetaDiaPago`, entero 1-31, sin mes/año) ESTRICTAMENTE POSTERIOR
/// a [ancla] — generalización interna (Etapa "ciclo de TDC") que hace
/// posible anclar el cálculo a una fecha distinta de hoy (un
/// `tarjetaVencimientoCubiertoHasta` conciliado), sin duplicar la
/// lógica de recorte de mes. Si el mes de [ancla] tiene menos días que
/// [diaDelMes] (ej. 31 en febrero), se recorta al último día real de
/// ese mes — nunca se inventa una fecha inválida.
DateTime _proximaOcurrenciaDiaDelMesDespuesDe(int diaDelMes, DateTime ancla) {
  DateTime construir(int year, int month) {
    final ultimoDiaDelMes = DateTime(year, month + 1, 0).day;
    final dia = diaDelMes.clamp(1, ultimoDiaDelMes);
    return DateTime(year, month, dia);
  }

  final candidatoMesAncla = construir(ancla.year, ancla.month);
  if (candidatoMesAncla.isAfter(ancla)) return candidatoMesAncla;

  final siguienteMes = ancla.month == 12 ? DateTime(ancla.year + 1, 1) : DateTime(ancla.year, ancla.month + 1);
  return construir(siguienteMes.year, siguienteMes.month);
}

/// Etapa 19B — próxima ocurrencia de un "día del mes" (`tarjetaDiaCorte`/
/// `tarjetaDiaPago`, capturados como entero 1-31, sin mes/año) a partir
/// de [hoy]. Si [diaDelMes] ya pasó este mes, avanza al mes siguiente;
/// si el mes objetivo tiene menos días que [diaDelMes] (ej. 31 en
/// febrero), se recorta al último día real de ese mes — nunca se
/// inventa una fecha inválida. Puramente derivado, nunca persistido
/// (mismo criterio que el % de utilización de la tarjeta).
///
/// Implementada como [_proximaOcurrenciaDiaDelMesDespuesDe] anclada a
/// `hoy − 1 día` — "estrictamente posterior a ayer" equivale
/// exactamente a "hoy o después" en granularidad de día completo
/// (verificado contra todos los casos existentes, incluyendo cruce de
/// mes/año, sin ningún cambio de resultado).
DateTime proximaOcurrenciaDiaDelMes(int diaDelMes, DateTime hoy) {
  final hoySoloFecha = DateTime(hoy.year, hoy.month, hoy.day);
  return _proximaOcurrenciaDiaDelMesDespuesDe(diaDelMes, hoySoloFecha.subtract(const Duration(days: 1)));
}

/// Crédito disponible de una tarjeta — única fuente de verdad (Etapa
/// "tarjeta revolvente"): antes se reimplementaba de forma
/// independiente en 4 sitios (`límite - saldoActual`, uno de ellos con
/// un `?? 0` que rechazaba cualquier compra en una tarjeta sin límite
/// capturado). `null` cuando el límite todavía no se ha capturado —
/// nunca se asume `0` (eso significaría "sin crédito", que no es lo
/// mismo que "no sabemos el límite").
int? creditoDisponibleTarjeta({required int? limiteCredito, required int saldoActual}) {
  if (limiteCredito == null) return null;
  return limiteCredito - saldoActual;
}

/// Próxima fecha límite de pago con regla "N días naturales después del
/// corte", ESTRICTAMENTE POSTERIOR a [ancla] — generalización interna
/// (Etapa "ciclo de TDC"), mismo propósito que
/// [_proximaOcurrenciaDiaDelMesDespuesDe]. Se ubica el corte más
/// reciente respecto de [ancla] (o el de su mismo mes si ya ocurrió) y
/// se le suma [diasDespuesCorte]; si esa fecha límite no queda
/// estrictamente después de [ancla], se avanza un ciclo completo (el
/// corte del mes siguiente).
DateTime _proximaFechaDiasDespuesDeCorteDespuesDe({
  required int diaCorte,
  required int diasDespuesCorte,
  required DateTime ancla,
}) {
  DateTime construirCorte(int year, int month) {
    final ultimoDiaDelMes = DateTime(year, month + 1, 0).day;
    final dia = diaCorte.clamp(1, ultimoDiaDelMes);
    return DateTime(year, month, dia);
  }

  final corteEsteMes = construirCorte(ancla.year, ancla.month);

  final DateTime corteReciente;
  if (!corteEsteMes.isAfter(ancla)) {
    corteReciente = corteEsteMes;
  } else {
    final mesAnterior = ancla.month == 1 ? DateTime(ancla.year - 1, 12) : DateTime(ancla.year, ancla.month - 1);
    corteReciente = construirCorte(mesAnterior.year, mesAnterior.month);
  }

  var vencimiento = corteReciente.add(Duration(days: diasDespuesCorte));
  if (!vencimiento.isAfter(ancla)) {
    final siguienteMes =
        corteReciente.month == 12 ? DateTime(corteReciente.year + 1, 1) : DateTime(corteReciente.year, corteReciente.month + 1);
    vencimiento = construirCorte(siguienteMes.year, siguienteMes.month).add(Duration(days: diasDespuesCorte));
  }
  return vencimiento;
}

/// Próxima fecha límite de pago cuando la regla es "N días naturales
/// después del corte" — a diferencia de [proximaOcurrenciaDiaDelMes]
/// (una sola serie mensual), aquí la fecha límite es una serie mensual
/// DESPLAZADA [diasDespuesCorte] días respecto de la serie de cortes.
/// `DateTime.add`/la construcción explícita de mes/año ya manejan el
/// cruce de mes y de año (diciembre → enero) sin caso especial.
///
/// Implementada como [_proximaFechaDiasDespuesDeCorteDespuesDe] anclada
/// a `hoy − 1 día` — mismo criterio de equivalencia que
/// [proximaOcurrenciaDiaDelMes] (verificado sin cambio de resultado
/// contra todos los casos existentes).
DateTime proximaFechaDiasDespuesDeCorte({
  required int diaCorte,
  required int diasDespuesCorte,
  required DateTime hoy,
}) {
  final hoySoloFecha = DateTime(hoy.year, hoy.month, hoy.day);
  return _proximaFechaDiasDespuesDeCorteDespuesDe(
    diaCorte: diaCorte,
    diasDespuesCorte: diasDespuesCorte,
    ancla: hoySoloFecha.subtract(const Duration(days: 1)),
  );
}

/// Despacha según [ReglaFechaLimitePagoTarjeta] (Etapa "tarjeta
/// revolvente") — nunca una segunda lógica de cálculo por fuera de
/// [proximaOcurrenciaDiaDelMes]/[proximaFechaDiasDespuesDeCorte]. `null`
/// si faltan los datos que la regla elegida necesita (nunca se inventa
/// una fecha con datos incompletos).
///
/// [vencimientoCubiertoHasta] (Etapa "ciclo de TDC") — cuando se
/// provee, la próxima obligación se calcula como la menor ocurrencia
/// ESTRICTAMENTE POSTERIOR a esa fecha, en vez de "la primera >= hoy".
/// Puede devolver una fecha anterior a `hoy` — eso es exactamente
/// "vencida" (un ciclo cubierto viejo con ciclos saltados de por
/// medio), nunca se fuerza a avanzar hasta alcanzar `hoy`. `null`
/// (default) reproduce el comportamiento de siempre.
DateTime? proximaFechaLimitePago({
  required String? regla,
  int? diaFijo,
  int? diaCorte,
  int? diasDespuesCorte,
  required DateTime hoy,
  DateTime? vencimientoCubiertoHasta,
}) {
  final ancla = vencimientoCubiertoHasta != null
      ? DateTime(vencimientoCubiertoHasta.year, vencimientoCubiertoHasta.month, vencimientoCubiertoHasta.day)
      : DateTime(hoy.year, hoy.month, hoy.day).subtract(const Duration(days: 1));

  if (regla == ReglaFechaLimitePagoTarjeta.diaFijo.name) {
    return diaFijo == null ? null : _proximaOcurrenciaDiaDelMesDespuesDe(diaFijo, ancla);
  }
  if (regla == ReglaFechaLimitePagoTarjeta.diasDespuesDeCorte.name) {
    if (diaCorte == null || diasDespuesCorte == null) return null;
    return _proximaFechaDiasDespuesDeCorteDespuesDe(diaCorte: diaCorte, diasDespuesCorte: diasDespuesCorte, ancla: ancla);
  }
  return null;
}

/// Próxima fecha de pago de una `Deuda`, para cualquier tipo — única
/// fuente de verdad reutilizada por el listado de Deudas y crédito, su
/// KPI "Próximos vencimientos", el expediente y las alertas del
/// Dashboard (corrección real: tras volver `fechaVencimiento` nullable
/// para TDC, esas 4 pantallas seguían leyendo esa columna directo, o
/// reimplementaban su propio cálculo ignorando
/// `tarjetaReglaFechaPago`/`tarjetaDiasDespuesCorte` — nunca más de una
/// sola implementación).
///
/// Deuda fija (`tipo != tarjetaCredito`) usa `fechaVencimiento` tal
/// cual, sin cambios. Una tarjeta de crédito usa [proximaFechaLimitePago]
/// sobre su propia regla — nunca `fechaVencimiento`, que para una TDC
/// correctamente es siempre `null` desde la Etapa "tarjeta revolvente".
/// `null` si la configuración de la tarjeta está incompleta (nunca se
/// inventa una fecha) — nunca se persiste, se deriva en cada consulta
/// contra [hoy] para no quedar obsoleta.
DateTime? proximaFechaPagoDeuda(DeudaData deuda, DateTime hoy) {
  if (deuda.tipo != TipoDeuda.tarjetaCredito.name) return deuda.fechaVencimiento;
  return proximaFechaLimitePago(
    regla: deuda.tarjetaReglaFechaPago,
    diaFijo: deuda.tarjetaDiaPago,
    diaCorte: deuda.tarjetaDiaCorte,
    diasDespuesCorte: deuda.tarjetaDiasDespuesCorte,
    hoy: hoy,
    vencimientoCubiertoHasta: deuda.tarjetaVencimientoCubiertoHasta,
  );
}
