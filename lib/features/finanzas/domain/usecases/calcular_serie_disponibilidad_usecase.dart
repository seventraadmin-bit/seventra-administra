import 'obtener_proyeccion_caja_usecase.dart';

/// Disponibilidad proyectada de un solo día (Etapa 19D) — nunca vuelve
/// a sumar `saldoActual`: es el saldo acumulado día a día a partir de
/// él.
class PuntoDisponibilidadDiaria {
  const PuntoDisponibilidadDiaria({
    required this.fecha,
    required this.saldo,
    required this.entradasDelDia,
    required this.salidasDelDia,
  });

  final DateTime fecha;
  final int saldo;
  final int entradasDelDia;
  final int salidasDelDia;
}

/// `saldo[fecha] = saldoActual + Σ entradas(compromiso.fecha <= fecha)
/// − Σ salidas(compromiso.fecha <= fecha)` (Etapa 19D, pedido §4) —
/// función PURA, sin repositorios: toma la MISMA `ProyeccionCaja` que
/// ya construyó `ObtenerProyeccionCajaUseCase` (Resumen y Planeación
/// financiera comparten esta única fuente, nunca recalculan por
/// separado). La serie siempre arranca en `hoy` — nunca hay "proyección
/// pasada"; si `hasta` es anterior a `hoy`, la serie queda vacía.
List<PuntoDisponibilidadDiaria> calcularSerieDisponibilidad({
  required DateTime hoy,
  required DateTime hasta,
  required int saldoActual,
  required List<CompromisoFinanciero> compromisos,
}) {
  final hoySinHora = DateTime(hoy.year, hoy.month, hoy.day);
  final hastaSinHora = DateTime(hasta.year, hasta.month, hasta.day);
  if (hastaSinHora.isBefore(hoySinHora)) return const [];

  final porDia = <DateTime, List<CompromisoFinanciero>>{};
  for (final c in compromisos) {
    final fechaSinHora = DateTime(c.fecha.year, c.fecha.month, c.fecha.day);
    if (fechaSinHora.isBefore(hoySinHora) || fechaSinHora.isAfter(hastaSinHora)) continue;
    porDia.putIfAbsent(fechaSinHora, () => []).add(c);
  }

  final totalDias = hastaSinHora.difference(hoySinHora).inDays;
  var saldoAcumulado = saldoActual;
  final puntos = <PuntoDisponibilidadDiaria>[];
  for (var i = 0; i <= totalDias; i++) {
    final fecha = hoySinHora.add(Duration(days: i));
    final delDia = porDia[fecha] ?? const <CompromisoFinanciero>[];
    final entradas = delDia.where((c) => c.tipo == TipoCompromiso.entrada).fold<int>(0, (s, c) => s + c.importe);
    final salidas = delDia.where((c) => c.tipo == TipoCompromiso.salida).fold<int>(0, (s, c) => s + c.importe);
    saldoAcumulado = saldoAcumulado + entradas - salidas;
    puntos.add(PuntoDisponibilidadDiaria(fecha: fecha, saldo: saldoAcumulado, entradasDelDia: entradas, salidasDelDia: salidas));
  }
  return puntos;
}

/// Punto de mínima disponibilidad de la serie — matemática pura (nunca
/// un score financiero, pedido §5): el primer día que alcanza el
/// mínimo, en orden cronológico.
PuntoDisponibilidadDiaria? encontrarMinimo(List<PuntoDisponibilidadDiaria> serie) {
  if (serie.isEmpty) return null;
  return serie.reduce((min, actual) => actual.saldo < min.saldo ? actual : min);
}

/// Un corte de semana CALENDARIO real (lunes–domingo), recortado a los
/// días que la serie realmente cubre — nunca un bloque fijo de 7 días
/// que ignore dónde empieza/termina el mes visible (pedido §7).
class ResumenSemanal {
  const ResumenSemanal({
    required this.inicio,
    required this.fin,
    required this.entradas,
    required this.salidas,
    required this.saldoFinal,
  });

  final DateTime inicio;
  final DateTime fin;
  final int entradas;
  final int salidas;
  final int saldoFinal;

  int get balance => entradas - salidas;
}

/// Agrupa una serie diaria ya calculada en semanas calendario reales.
/// Cada grupo usa como `inicio`/`fin` el primer/último día que la serie
/// realmente contiene para esa semana (nunca inventa días fuera de la
/// serie) — así una semana que cruza de un mes a otro, o que empieza a
/// mitad de la semana porque es el primer día de la serie, se muestra
/// exactamente como calendario real dicta.
List<ResumenSemanal> agruparPorSemanaCalendario(List<PuntoDisponibilidadDiaria> serie) {
  if (serie.isEmpty) return const [];

  final grupos = <DateTime, List<PuntoDisponibilidadDiaria>>{};
  for (final punto in serie) {
    final inicioSemanaIso = punto.fecha.subtract(Duration(days: punto.fecha.weekday - 1));
    grupos.putIfAbsent(inicioSemanaIso, () => []).add(punto);
  }

  final clavesOrdenadas = grupos.keys.toList()..sort();
  return [
    for (final clave in clavesOrdenadas)
      ResumenSemanal(
        inicio: grupos[clave]!.first.fecha,
        fin: grupos[clave]!.last.fecha,
        entradas: grupos[clave]!.fold<int>(0, (s, p) => s + p.entradasDelDia),
        salidas: grupos[clave]!.fold<int>(0, (s, p) => s + p.salidasDelDia),
        saldoFinal: grupos[clave]!.last.saldo,
      ),
  ];
}
