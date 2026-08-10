import '../../data/tables/nomina_empleado_table.dart' show FuenteSueldoNomina;

/// Un periodo laboral de un Empleado (vigente o archivado) ya reducido a
/// un rango simple — ver `Empleado.fechaIngreso`/`fechaBaja` y
/// `EmpleadoPeriodoLaboral`. `fin == null` significa que sigue vigente
/// hoy (nunca ocurre para uno archivado).
class SegmentoLaboral {
  const SegmentoLaboral({required this.inicio, this.fin});

  final DateTime inicio;
  final DateTime? fin;
}

/// Un tramo de sueldo/bono ya resuelto contra su fuente — la lista
/// completa que recibe `calcularDiasPagablesEmpleado` debe cubrir
/// cronológicamente cualquier fecha dentro de los `segmentosLaborales`
/// que se le pasen junto con ella; rellenar los huecos con la fuente
/// administrativa (o excluir al Empleado si no hay ninguna fuente) es
/// responsabilidad de quien arma esta lista contra la base de datos, no
/// de esta función pura.
class IntervaloSueldo {
  const IntervaloSueldo({
    required this.inicio,
    this.fin,
    required this.fuente,
    this.servicioId,
    this.servicioNombre,
    this.turnoNombre,
    required this.sueldoMensual,
    required this.bonoMensual,
  });

  final DateTime inicio;
  final DateTime? fin;
  final FuenteSueldoNomina fuente;
  final String? servicioId;
  final String? servicioNombre;
  final String? turnoNombre;
  final int sueldoMensual;
  final int bonoMensual;
}

/// Un tramo ya calculado dentro de una Nómina — normalmente uno solo por
/// Empleado; más de uno cuando hay un cambio de Servicio/sueldo o un
/// hueco laboral (alta/baja/reingreso) dentro del mismo periodo.
class TramoCalculado {
  const TramoCalculado({
    required this.fechaInicio,
    required this.fechaFin,
    required this.diasReales,
    required this.fuente,
    this.servicioId,
    this.servicioNombre,
    this.turnoNombre,
    required this.sueldoMensual,
    required this.bonoMensual,
    required this.importeTramo,
  });

  final DateTime fechaInicio;
  final DateTime fechaFin;
  final int diasReales;
  final FuenteSueldoNomina fuente;
  final String? servicioId;
  final String? servicioNombre;
  final String? turnoNombre;
  final int sueldoMensual;
  final int bonoMensual;
  final int importeTramo;
}

/// Resultado completo del cálculo de un Empleado dentro de un periodo.
class CalculoDiasPagablesEmpleado {
  const CalculoDiasPagablesEmpleado({
    required this.diasPagables,
    required this.importeBase,
    required this.sueldoMensualUtilizado,
    required this.bonoDisponible,
    required this.puestoNombre,
    required this.tramos,
  });

  final int diasPagables;
  final int importeBase;

  /// Sueldo mensual del **último** tramo (el que cubre el último día
  /// pagable del periodo) — nunca un promedio. Es el valor que se
  /// muestra como "sueldo mensual utilizado" y la base de "pago por
  /// día" (`sueldoMensualUtilizado / 30`).
  final int sueldoMensualUtilizado;

  /// Bono del último tramo — nunca prorrateado entre tramos (Resolución
  /// explícita de Marlon). Quien genera la Nómina decide si lo propone
  /// (solo en la nómina del día 5 / segunda quincena) o lo deja en $0.
  final int bonoDisponible;

  final String? puestoNombre;
  final List<TramoCalculado> tramos;
}

/// Se lanza cuando algún día dentro de un segmento laboral pagable no
/// tiene ninguna fuente de sueldo que lo cubra (ni Servicio ni
/// administrativo configurado) — nunca se produce un tramo con sueldo
/// `0` en silencio.
class SueldoNoDisponibleException implements Exception {
  SueldoNoDisponibleException(this.fecha);
  final DateTime fecha;

  @override
  String toString() => 'SueldoNoDisponibleException: sin fuente de sueldo para el $fecha';
}

DateTime _soloFecha(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

int _diasReales(DateTime inicio, DateTime fin) => fin.difference(inicio).inDays + 1;

/// Calcula días pagables, importe base y tramos de un Empleado dentro de
/// un periodo de Nómina — algoritmo central de la Etapa 6C.
///
/// Primero determina la cobertura **laboral** (ignorando Servicio/
/// sueldo, solo `segmentosLaborales`):
///
/// - **Cobertura completa** (un único segmento que cubre el periodo
///   completo, sin huecos): `diasPagables` es siempre 15, en ambas
///   quincenas — incluso en un mes de 31 días, donde la segunda
///   quincena tiene 16 días reales. El importe de cada tramo de sueldo
///   se reparte por **peso proporcional** de días reales sobre los días
///   reales del periodo completo (`sueldoMensual × diasRealesTramo /
///   (2 × diasRealesPeriodo)`), nunca por días reales fijos — así la
///   suma nunca puede superar el equivalente de 15 días de sueldo, sin
///   importar cuántos tramos haya (bug real que Marlon detectó en un
///   borrador anterior: un cambio de Servicio a mitad de una segunda
///   quincena de 31 días no debe convertirla en "16 días pagados").
///   Con un solo tramo, la fórmula se reduce exactamente a
///   `sueldoMensual / 2`.
/// - **Cobertura parcial** (alta/baja/reingreso dentro del periodo, o
///   más de un segmento laboral): `diasPagables` es la suma de días
///   reales de cada tramo; el importe usa `sueldoMensual × diasReales /
///   30` sin ponderación — el criterio original, sin cambios.
///
/// `intervalosSueldo` debe cubrir cronológicamente cualquier fecha
/// dentro de los `segmentosLaborales` ya recortados al periodo — un
/// hueco sin cobertura lanza `SueldoNoDisponibleException`.
CalculoDiasPagablesEmpleado calcularDiasPagablesEmpleado({
  required List<SegmentoLaboral> segmentosLaborales,
  required List<IntervaloSueldo> intervalosSueldo,
  required DateTime periodoInicio,
  required DateTime periodoFin,
  String? puestoNombre,
}) {
  final inicioPeriodo = _soloFecha(periodoInicio);
  final finPeriodo = _soloFecha(periodoFin);

  final segmentosClip = <SegmentoLaboral>[];
  for (final seg in segmentosLaborales) {
    final segInicio = _soloFecha(seg.inicio);
    final segFin = seg.fin == null ? finPeriodo : _soloFecha(seg.fin!);
    final inicio = segInicio.isAfter(inicioPeriodo) ? segInicio : inicioPeriodo;
    final fin = segFin.isBefore(finPeriodo) ? segFin : finPeriodo;
    if (inicio.isAfter(fin)) continue;
    segmentosClip.add(SegmentoLaboral(inicio: inicio, fin: fin));
  }
  segmentosClip.sort((a, b) => a.inicio.compareTo(b.inicio));

  if (segmentosClip.isEmpty) {
    return CalculoDiasPagablesEmpleado(
      diasPagables: 0,
      importeBase: 0,
      sueldoMensualUtilizado: 0,
      bonoDisponible: 0,
      puestoNombre: puestoNombre,
      tramos: const [],
    );
  }

  final coberturaCompleta = segmentosClip.length == 1 &&
      !segmentosClip.first.inicio.isAfter(inicioPeriodo) &&
      !segmentosClip.first.fin!.isBefore(finPeriodo);

  final diasRealesPeriodoCompleto = _diasReales(inicioPeriodo, finPeriodo);

  final tramos = <TramoCalculado>[];
  for (final seg in segmentosClip) {
    for (final intervalo in _tramosDeIntervalos(intervalosSueldo, seg.inicio, seg.fin!)) {
      // `_tramosDeIntervalos` siempre devuelve piezas ya recortadas con
      // `fin` concreto — el tipo se mantiene nullable solo porque
      // reutiliza `IntervaloSueldo` (cuyo `fin` sí puede ser abierto en
      // la entrada).
      final finTramo = intervalo.fin!;
      final diasReales = _diasReales(intervalo.inicio, finTramo);
      final importe = coberturaCompleta
          ? (intervalo.sueldoMensual * diasReales / (2 * diasRealesPeriodoCompleto)).round()
          : (intervalo.sueldoMensual * diasReales / 30).round();
      tramos.add(
        TramoCalculado(
          fechaInicio: intervalo.inicio,
          fechaFin: finTramo,
          diasReales: diasReales,
          fuente: intervalo.fuente,
          servicioId: intervalo.servicioId,
          servicioNombre: intervalo.servicioNombre,
          turnoNombre: intervalo.turnoNombre,
          sueldoMensual: intervalo.sueldoMensual,
          bonoMensual: intervalo.bonoMensual,
          importeTramo: importe,
        ),
      );
    }
  }

  final diasPagables = coberturaCompleta ? 15 : tramos.fold<int>(0, (s, t) => s + t.diasReales);
  final importeBase = tramos.fold<int>(0, (s, t) => s + t.importeTramo);
  final ultimo = tramos.last;

  return CalculoDiasPagablesEmpleado(
    diasPagables: diasPagables,
    importeBase: importeBase,
    sueldoMensualUtilizado: ultimo.sueldoMensual,
    bonoDisponible: ultimo.bonoMensual,
    puestoNombre: puestoNombre,
    tramos: tramos,
  );
}

/// Recorta `intervalosSueldo` (ordenados, sin traslape) contra
/// `[inicio, fin]`, devolviendo los pedazos ya recortados en orden
/// cronológico. Lanza `SueldoNoDisponibleException` si algún día de ese
/// rango no queda cubierto por ningún intervalo.
List<IntervaloSueldo> _tramosDeIntervalos(List<IntervaloSueldo> intervalosSueldo, DateTime inicio, DateTime fin) {
  final ordenados = [...intervalosSueldo]..sort((a, b) => a.inicio.compareTo(b.inicio));
  final resultado = <IntervaloSueldo>[];
  var cursor = inicio;

  for (final intervalo in ordenados) {
    final intInicio = _soloFecha(intervalo.inicio);
    final intFin = intervalo.fin == null ? fin : _soloFecha(intervalo.fin!);
    if (intFin.isBefore(cursor) || intInicio.isAfter(fin)) continue;

    final trozoInicio = intInicio.isAfter(cursor) ? intInicio : cursor;
    if (trozoInicio.isAfter(cursor)) {
      // Hueco entre `cursor` y el inicio de este intervalo — sin fuente.
      throw SueldoNoDisponibleException(cursor);
    }
    final trozoFin = intFin.isBefore(fin) ? intFin : fin;
    if (trozoFin.isBefore(trozoInicio)) continue;

    resultado.add(
      IntervaloSueldo(
        inicio: trozoInicio,
        fin: trozoFin,
        fuente: intervalo.fuente,
        servicioId: intervalo.servicioId,
        servicioNombre: intervalo.servicioNombre,
        turnoNombre: intervalo.turnoNombre,
        sueldoMensual: intervalo.sueldoMensual,
        bonoMensual: intervalo.bonoMensual,
      ),
    );
    cursor = trozoFin.add(const Duration(days: 1));
    if (cursor.isAfter(fin)) break;
  }

  // Si el cursor no llegó a rebasar `fin`, quedó un hueco al final del
  // rango sin ningún intervalo que lo cubriera.
  if (!cursor.isAfter(fin)) {
    throw SueldoNoDisponibleException(cursor);
  }

  return resultado;
}
