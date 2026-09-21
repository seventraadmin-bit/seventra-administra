
import '../plantilla_personal.dart';
import '../repositories/asignacion_servicio_repository.dart';
import '../repositories/empleado_repository.dart';

/// Un ciclo laboral completo de un empleado — la unidad real sobre la
/// que se reconstruye cualquier periodo pasado.
///
/// El modelo guarda los ciclos en DOS lugares por diseño (Etapa 5C), y
/// su UNIÓN es el historial completo, sin pérdida:
///  - el ciclo VIGENTE vive en `Empleado` (`fechaIngreso`/`fechaBaja`);
///  - los ciclos CERRADOS se archivan en `EmpleadoPeriodoLaboral`, y
///    solo al momento de un Reingreso.
///
/// Por eso una baja sin reingreso posterior NO tiene fila archivada:
/// sigue siendo el ciclo vigente del empleado, ya terminado. Contarla
/// solo desde `EmpleadoPeriodoLaboral` perdería todas las bajas
/// definitivas — que en la instalación real son el 100% de ellas.
class CicloLaboral {
  const CicloLaboral({
    required this.empleadoId,
    required this.inicio,
    this.fin,
  });

  final String empleadoId;
  final DateTime inicio;

  /// `null` = sigue abierto.
  final DateTime? fin;

  bool activoEn(DateTime corte) => !inicio.isAfter(corte) && (fin == null || fin!.isAfter(corte));
}

/// Rotación de una plantilla en un periodo (Etapa "Plantilla operativa
/// vs. administrativa").
class RotacionPlantilla {
  const RotacionPlantilla({
    required this.activosInicio,
    required this.activosCierre,
    required this.altas,
    required this.bajas,
    required this.reingresos,
  });

  final int activosInicio;
  final int activosCierre;
  final int altas;
  final int bajas;

  /// Altas que reabren un ciclo de alguien que ya había trabajado
  /// antes. Cuentan como alta del periodo (son un ciclo nuevo), y se
  /// exponen aparte porque señalan algo distinto de una contratación
  /// nueva.
  final int reingresos;

  /// `(activos al inicio + activos al cierre) / 2`. `double` a
  /// propósito: nunca se trunca el valor con el que se divide.
  double get plantillaPromedio => (activosInicio + activosCierre) / 2;

  /// `bajas / plantillaPromedio × 100`. `null` cuando la plantilla
  /// promedio es 0 — con plantilla vacía la rotación no está definida,
  /// y devolver `0` fingiría "cero rotación".
  ///
  /// Sin redondear: la UI decide cuántos decimales muestra (13.8%),
  /// pero internamente se conserva 13.793103448275861…
  double? get porcentaje => plantillaPromedio == 0 ? null : bajas / plantillaPromedio * 100;
}

/// Rotación reconstruida sobre ciclos laborales REALES, nunca sobre el
/// estado actual de los empleados (Etapa "Plantilla operativa vs.
/// administrativa", punto 9 del pedido).
///
/// Pedir agosto de 2026 reconstruye agosto de 2026: quién estaba activo
/// el día 1, quién el día 31, cuántos entraron y cuántos salieron EN
/// ESE mes — aunque hoy ninguno de ellos siga en la empresa.
///
/// **Solo rotación OPERATIVA**, deliberadamente. La pertenencia
/// operativa a una fecha pasada se reconstruye por FK real:
/// `AsignacionServicio` guarda `fechaInicio`/`fechaTermino`, así que
/// "¿tenía Servicio vigente el día X?" tiene respuesta exacta. La
/// pertenencia ADMINISTRATIVA no: `Empleado.sucursalId` es un puntero
/// plano sin vigencia (resolución explícita de Marlon en la Etapa 6A,
/// "no quiero crear una estructura de vigencias de Sucursal solo para
/// esto"), así que a una fecha pasada solo se conoce la sucursal ACTUAL.
/// Calcular rotación administrativa histórica con ese dato sería
/// atribuir el presente al pasado — exactamente lo que el punto 9
/// prohíbe. Se reporta como limitación en vez de aproximarse.
class ObtenerRotacionPersonalUseCase {
  ObtenerRotacionPersonalUseCase(this._empleadoRepository, this._asignacionServicioRepository);

  final EmpleadoRepository _empleadoRepository;
  final AsignacionServicioRepository _asignacionServicioRepository;

  Future<RotacionPlantilla> ejecutarOperativa({
    required DateTime rangoInicio,
    required DateTime rangoFin,
  }) async {
    final todos = await _empleadoRepository.listar();
    final archivados = await _empleadoRepository.listarPeriodosLaboralesArchivadosPorEmpleados(
      todos.map((e) => e.id).toList(),
    );

    // Unión de ciclos: los archivados + el vigente de cada Empleado.
    final ciclos = <CicloLaboral>[];
    for (final empleado in todos) {
      for (final p in archivados[empleado.id] ?? const []) {
        ciclos.add(CicloLaboral(empleadoId: empleado.id, inicio: p.fechaIngreso, fin: p.fechaBaja));
      }
      ciclos.add(CicloLaboral(
        empleadoId: empleado.id,
        inicio: empleado.fechaIngreso,
        fin: empleado.fechaBaja,
      ));
    }

    // Cuántos ciclos previos tenía cada empleado al iniciar cada ciclo
    // — para distinguir un reingreso de una contratación nueva sin
    // fusionar ni borrar historial (la antigüedad nunca acumula, pero
    // los eventos siguen contando en SU periodo).
    final ciclosPorEmpleado = <String, List<CicloLaboral>>{};
    for (final c in ciclos) {
      (ciclosPorEmpleado[c.empleadoId] ??= []).add(c);
    }
    for (final lista in ciclosPorEmpleado.values) {
      lista.sort((a, b) => a.inicio.compareTo(b.inicio));
    }

    final operativos = await _empleadoIdsOperativosEnRango(rangoInicio: rangoInicio, rangoFin: rangoFin);
    bool esOperativo(String empleadoId) => operativos.contains(empleadoId);

    final activosInicio = ciclos
        .where((c) => c.activoEn(rangoInicio) && esOperativo(c.empleadoId))
        .map((c) => c.empleadoId)
        .toSet();
    final activosCierre = ciclos
        .where((c) => c.activoEn(rangoFin) && esOperativo(c.empleadoId))
        .map((c) => c.empleadoId)
        .toSet();

    var altas = 0;
    var bajas = 0;
    var reingresos = 0;
    for (final entrada in ciclosPorEmpleado.entries) {
      if (!esOperativo(entrada.key)) continue;
      for (var i = 0; i < entrada.value.length; i++) {
        final ciclo = entrada.value[i];
        if (_enRango(ciclo.inicio, rangoInicio, rangoFin)) {
          altas++;
          if (i > 0) reingresos++;
        }
        if (ciclo.fin != null && _enRango(ciclo.fin!, rangoInicio, rangoFin)) bajas++;
      }
    }

    return RotacionPlantilla(
      activosInicio: activosInicio.length,
      activosCierre: activosCierre.length,
      altas: altas,
      bajas: bajas,
      reingresos: reingresos,
    );
  }

  /// Empleados que fueron OPERATIVOS en algún momento del rango —
  /// resuelto por las vigencias reales de `AsignacionServicio`, nunca
  /// por quién tiene Servicio hoy.
  ///
  /// Se usa "tocó el rango" y no "el día exacto del corte" a propósito:
  /// alguien que causó baja a mitad del mes ya no tiene asignación
  /// vigente al cierre, y exigir vigencia en la fecha del corte lo
  /// borraría del cálculo justo cuando su baja es lo que se quiere
  /// medir.
  Future<Set<String>> _empleadoIdsOperativosEnRango({
    required DateTime rangoInicio,
    required DateTime rangoFin,
  }) async {
    final asignaciones = await _asignacionServicioRepository.listarTodas();
    return asignaciones
        .where((a) => !a.fechaInicio.isAfter(rangoFin) && (a.fechaTermino == null || !a.fechaTermino!.isBefore(rangoInicio)))
        .map((a) => a.empleadoId)
        .toSet();
  }

  bool _enRango(DateTime fecha, DateTime inicio, DateTime fin) =>
      !fecha.isBefore(inicio) && !fecha.isAfter(fin);
}

/// Antigüedad y permanencia de la plantilla (SNAPSHOT) — se calcula
/// siempre sobre el ciclo VIGENTE, así que un reingreso arranca de cero
/// y nunca acumula la antigüedad del ciclo anterior.
class AntiguedadPlantilla {
  const AntiguedadPlantilla({required this.promedio, required this.mediana});

  /// `null` cuando la plantilla está vacía.
  final Duration? promedio;
  final Duration? mediana;

  static AntiguedadPlantilla desde(List<ClasificacionEmpleado> clasificaciones, DateTime hoy) {
    final dias = clasificaciones.map((c) => hoy.difference(c.empleado.fechaIngreso).inDays).toList()..sort();
    if (dias.isEmpty) return const AntiguedadPlantilla(promedio: null, mediana: null);
    final suma = dias.fold<int>(0, (a, b) => a + b);
    final medio = dias.length ~/ 2;
    final mediana = dias.length.isOdd ? dias[medio] : ((dias[medio - 1] + dias[medio]) / 2).round();
    return AntiguedadPlantilla(
      promedio: Duration(days: suma ~/ dias.length),
      mediana: Duration(days: mediana),
    );
  }
}
