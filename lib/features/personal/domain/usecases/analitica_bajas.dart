import 'package:riseg_one/features/personal/data/tables/empleado_table.dart' show MotivoBajaEmpleado;

import 'construir_eventos_baja.dart';

/// Periodo seleccionado para la analítica de Bajas (Etapa 15).
enum PeriodoAnaliticaBajas { esteMes, ultimos3Meses, esteAnio, personalizado }

/// Resuelve [periodo] a un rango de fechas concreto — función pura.
/// `personalizado` requiere [inicioPersonalizado]/[finPersonalizado]
/// explícitos (nunca inventa un rango si faltan).
({DateTime inicio, DateTime fin}) resolverRangoPeriodoBajas(
  PeriodoAnaliticaBajas periodo, {
  DateTime? hoy,
  DateTime? inicioPersonalizado,
  DateTime? finPersonalizado,
}) {
  final ahora = hoy ?? DateTime.now();
  return switch (periodo) {
    PeriodoAnaliticaBajas.esteMes => (inicio: DateTime(ahora.year, ahora.month, 1), fin: DateTime(ahora.year, ahora.month + 1, 0)),
    PeriodoAnaliticaBajas.ultimos3Meses => (inicio: DateTime(ahora.year, ahora.month - 2, 1), fin: DateTime(ahora.year, ahora.month + 1, 0)),
    PeriodoAnaliticaBajas.esteAnio => (inicio: DateTime(ahora.year, 1, 1), fin: DateTime(ahora.year, 12, 31)),
    PeriodoAnaliticaBajas.personalizado =>
      (inicio: inicioPersonalizado ?? DateTime(ahora.year, ahora.month, 1), fin: finPersonalizado ?? ahora),
  };
}

bool _fechaEnRango(DateTime fecha, DateTime inicio, DateTime fin) {
  final dia = DateTime(fecha.year, fecha.month, fecha.day);
  return !dia.isBefore(DateTime(inicio.year, inicio.month, inicio.day)) && !dia.isAfter(DateTime(fin.year, fin.month, fin.day));
}

List<BajaEvento> filtrarEventosPorRango(List<BajaEvento> eventos, DateTime inicio, DateTime fin) {
  return eventos.where((e) => _fechaEnRango(e.fechaBaja, inicio, fin)).toList();
}

/// Un mes con su conteo de bajas — para la gráfica "Bajas por mes".
class BajasPorMes {
  const BajasPorMes({required this.anio, required this.mes, required this.cantidad});
  final int anio;
  final int mes;
  final int cantidad;
}

/// Cuenta bajas por mes dentro de `[inicio, fin]` — SIEMPRE incluye
/// todos los meses del rango, aunque tengan 0 bajas (nunca omite un mes
/// silenciosamente, para que la gráfica no distorsione la escala).
List<BajasPorMes> calcularBajasPorMes(List<BajaEvento> eventosDelPeriodo, DateTime inicio, DateTime fin) {
  final conteos = <String, int>{};
  var cursor = DateTime(inicio.year, inicio.month, 1);
  final limite = DateTime(fin.year, fin.month, 1);
  while (!cursor.isAfter(limite)) {
    conteos['${cursor.year}-${cursor.month}'] = 0;
    cursor = DateTime(cursor.year, cursor.month + 1, 1);
  }
  for (final e in eventosDelPeriodo) {
    final clave = '${e.fechaBaja.year}-${e.fechaBaja.month}';
    if (conteos.containsKey(clave)) conteos[clave] = conteos[clave]! + 1;
  }

  final resultado = <BajasPorMes>[];
  cursor = DateTime(inicio.year, inicio.month, 1);
  while (!cursor.isAfter(limite)) {
    resultado.add(BajasPorMes(anio: cursor.year, mes: cursor.month, cantidad: conteos['${cursor.year}-${cursor.month}']!));
    cursor = DateTime(cursor.year, cursor.month + 1, 1);
  }
  return resultado;
}

/// Un motivo de baja con su conteo/porcentaje — SIEMPRE del catálogo
/// estructurado (`MotivoBajaEmpleado`), nunca del texto libre de
/// observaciones.
class MotivoBajaConteo {
  const MotivoBajaConteo({required this.motivo, required this.cantidad, required this.porcentaje});
  final MotivoBajaEmpleado motivo;
  final int cantidad;
  final double porcentaje;
}

List<MotivoBajaConteo> calcularMotivosBaja(List<BajaEvento> eventos) {
  if (eventos.isEmpty) return const [];
  final conteos = <MotivoBajaEmpleado, int>{};
  for (final e in eventos) {
    final motivo = MotivoBajaEmpleado.values.byName(e.motivoBaja);
    conteos[motivo] = (conteos[motivo] ?? 0) + 1;
  }
  final resultado = [
    for (final entrada in conteos.entries)
      MotivoBajaConteo(motivo: entrada.key, cantidad: entrada.value, porcentaje: entrada.value / eventos.length * 100),
  ];
  resultado.sort((a, b) => b.cantidad.compareTo(a.cantidad));
  return resultado;
}

/// Segmento de permanencia al momento de la baja.
enum SegmentoPermanencia { menos30Dias, uno3Meses, tres6Meses, seis12Meses, masDeUnAnio }

class SegmentoPermanenciaConteo {
  const SegmentoPermanenciaConteo({required this.segmento, required this.cantidad, required this.porcentaje});
  final SegmentoPermanencia segmento;
  final int cantidad;
  final double porcentaje;
}

/// Segmento de permanencia de un solo evento — expuesto para filtros
/// de tabla (Etapa 15), misma clasificación que
/// [calcularSegmentosPermanencia] usa para las estadísticas agregadas.
SegmentoPermanencia segmentoPermanenciaDeEvento(BajaEvento evento) => _segmentoDe(evento.permanenciaDias);

SegmentoPermanencia _segmentoDe(int dias) {
  if (dias < 30) return SegmentoPermanencia.menos30Dias;
  if (dias < 90) return SegmentoPermanencia.uno3Meses;
  if (dias < 180) return SegmentoPermanencia.tres6Meses;
  if (dias < 365) return SegmentoPermanencia.seis12Meses;
  return SegmentoPermanencia.masDeUnAnio;
}

List<SegmentoPermanenciaConteo> calcularSegmentosPermanencia(List<BajaEvento> eventos) {
  if (eventos.isEmpty) return const [];
  final conteos = <SegmentoPermanencia, int>{for (final s in SegmentoPermanencia.values) s: 0};
  for (final e in eventos) {
    final segmento = _segmentoDe(e.permanenciaDias);
    conteos[segmento] = conteos[segmento]! + 1;
  }
  return [
    for (final s in SegmentoPermanencia.values)
      SegmentoPermanenciaConteo(segmento: s, cantidad: conteos[s]!, porcentaje: conteos[s]! / eventos.length * 100),
  ];
}

/// Una fila de "Servicios con mayor rotación" — SOLO construida a
/// partir de `BajaEvento.servicioNombre` (el snapshot al momento EXACTO
/// de esa baja), nunca del Servicio actual del Empleado.
class ServicioRotacion {
  const ServicioRotacion({required this.servicioNombre, required this.cantidad, required this.permanenciaPromedioDias, required this.motivoPrincipal});
  final String servicioNombre;
  final int cantidad;
  final double permanenciaPromedioDias;
  final MotivoBajaEmpleado motivoPrincipal;
}

/// Ordenado por cantidad de bajas descendente — excluye eventos sin
/// `servicioNombre` (Empleados puramente administrativos, sin
/// Servicio operativo al momento de la baja).
List<ServicioRotacion> calcularServiciosConMayorRotacion(List<BajaEvento> eventos) {
  final porServicio = <String, List<BajaEvento>>{};
  for (final e in eventos) {
    final servicio = e.servicioNombre;
    if (servicio == null || servicio.trim().isEmpty) continue;
    (porServicio[servicio] ??= []).add(e);
  }

  final resultado = <ServicioRotacion>[];
  for (final entrada in porServicio.entries) {
    final eventosServicio = entrada.value;
    final permanenciaPromedio = eventosServicio.fold<int>(0, (s, e) => s + e.permanenciaDias) / eventosServicio.length;
    final motivos = calcularMotivosBaja(eventosServicio);
    resultado.add(
      ServicioRotacion(
        servicioNombre: entrada.key,
        cantidad: eventosServicio.length,
        permanenciaPromedioDias: permanenciaPromedio,
        motivoPrincipal: motivos.first.motivo,
      ),
    );
  }
  resultado.sort((a, b) => b.cantidad.compareTo(a.cantidad));
  return resultado;
}

/// Eventos de rotación temprana (< 30 días laborados) — para la alerta
/// específica del pedido.
List<BajaEvento> filtrarRotacionTemprana(List<BajaEvento> eventos) {
  return eventos.where((e) => e.esRotacionTemprana).toList();
}

/// Permanencia promedio del conjunto, en días — `0` si la lista está
/// vacía (el llamador decide cómo mostrarlo, nunca división por cero
/// silenciosa aquí).
double calcularPermanenciaPromedioDias(List<BajaEvento> eventos) {
  if (eventos.isEmpty) return 0;
  return eventos.fold<int>(0, (s, e) => s + e.permanenciaDias) / eventos.length;
}
