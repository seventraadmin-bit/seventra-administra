import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';

/// Una línea comercial ya resuelta contra la fecha de hoy: su vigencia
/// vigente (si alguna vigencia activa ya empezó y no ha terminado) y
/// cualquier vigencia programada a futuro (Etapa 4G.1, Resolución C —
/// una vigencia futura nunca sustituye de inmediato a la vigente).
/// `puestoNombre`/`modalidadTurnoNombre` corresponden a la vigencia
/// vigente cuando existe; si la línea solo tiene vigencias programadas
/// (recién creada con fecha futura), corresponden a la programada más
/// próxima, para que la tabla siempre pueda mostrar algo identificable.
class LineaComercialConVigencia {
  const LineaComercialConVigencia({
    required this.linea,
    required this.vigenciaActual,
    required this.vigenciasProgramadas,
    required this.puestoNombre,
    required this.modalidadTurnoNombre,
    required this.esCorregible,
    this.asignadosVigentes = 0,
    this.horarioVigenciaMostrada = const [],
  });

  final ServicioLineaComercialData linea;
  final ServicioLineaComercialVigenciaData? vigenciaActual;
  final List<ServicioLineaComercialVigenciaData> vigenciasProgramadas;
  final String puestoNombre;
  final String modalidadTurnoNombre;

  /// Horario personalizado (Etapa 15) de la vigencia mostrada
  /// (`vigenciaActual`, o la programada más próxima si no hay ninguna
  /// vigente — mismo criterio que `puestoNombre`/`modalidadTurnoNombre`)
  /// — vacío salvo que esa vigencia tenga `modalidadTurnoId` =
  /// Personalizado. Usado por la tabla de Configuración comercial para
  /// mostrar un resumen corto en la columna Turno.
  final List<ServicioLineaComercialVigenciaHorarioData> horarioVigenciaMostrada;

  /// `true` si la línea todavía es una simple captura sin historia real
  /// (Etapa 15) — su única vigencia, nunca pasó por "Nueva vigencia" ni
  /// generó un `DocumentoPorEmitirLinea`. Habilita "Corregir" (in-place)
  /// y "Eliminar físicamente" en vez de forzar "Nueva vigencia" para
  /// arreglar un simple error de captura.
  final bool esCorregible;

  /// Cuántas `AsignacionServicio` vigentes (`fechaTermino IS NULL`)
  /// apuntan hoy a esta línea (Etapa 15, rediseño de "Condiciones de
  /// Personal") — comparado contra `vigenciaActual.cantidadElementos`
  /// ("Asignados: X de Y") para advertir capacidad excedida, nunca para
  /// bloquear: el modelo de asignaciones todavía no distingue una
  /// suplencia/cobertura temporal de un puesto regular, así que un
  /// bloqueo absoluto sería una regla inventada, no una ya aprobada.
  final int asignadosVigentes;

  /// `true` si `asignadosVigentes` ya alcanzó o superó
  /// `cantidadElementos` de la vigencia vigente — `false` si la línea no
  /// tiene ninguna vigencia en efecto (nada que comparar).
  bool get capacidadExcedida =>
      vigenciaActual != null && asignadosVigentes >= vigenciaActual!.cantidadElementos;

  /// `cantidad × precio` de la vigencia vigente — 0 si la línea todavía
  /// no tiene ninguna vigencia en efecto (solo programadas a futuro).
  int get subtotal =>
      vigenciaActual == null ? 0 : vigenciaActual!.cantidadElementos * vigenciaActual!.precioUnitario;
}

/// Compara solo año/mes/día — una vigencia es cuestión de fechas de
/// calendario, nunca de hora exacta.
DateTime soloFecha(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

/// Clasifica las vigencias `activo` de una línea contra la fecha de hoy
/// en "vigente" (a lo más una) y "programadas" (orden ascendente por
/// fecha de inicio) — pura función de fechas, reutilizable por el
/// repositorio y por las pruebas. Nunca recibe vigencias `archivado`
/// (canceladas) — esas nunca participan en esta clasificación ni en
/// ningún cálculo comercial.
({ServicioLineaComercialVigenciaData? vigente, List<ServicioLineaComercialVigenciaData> programadas})
    clasificarVigencias(List<ServicioLineaComercialVigenciaData> vigenciasActivas, DateTime hoy) {
  final hoySinHora = soloFecha(hoy);

  ServicioLineaComercialVigenciaData? vigente;
  final programadas = <ServicioLineaComercialVigenciaData>[];

  for (final v in vigenciasActivas) {
    final inicio = soloFecha(v.fechaInicioVigencia);
    final fin = v.fechaFinVigencia == null ? null : soloFecha(v.fechaFinVigencia!);

    if (inicio.isAfter(hoySinHora)) {
      programadas.add(v);
      continue;
    }
    if (fin != null && fin.isBefore(hoySinHora)) {
      continue; // Ya terminó — histórica, aunque cicloVidaRegistro siga en 'activo'.
    }
    if (vigente == null || inicio.isAfter(soloFecha(vigente.fechaInicioVigencia))) {
      vigente = v;
    }
  }

  programadas.sort((a, b) => a.fechaInicioVigencia.compareTo(b.fechaInicioVigencia));
  return (vigente: vigente, programadas: programadas);
}

/// Los 4 estados que puede mostrar el historial de una línea comercial —
/// distinto del par vigente/programadas de arriba porque este sí incluye
/// las vigencias canceladas (Etapa 4G.2): la trazabilidad administrativa
/// es más importante que ocultarlas, aunque nunca participen en ningún
/// cálculo ni puedan reactivarse.
enum EstadoVigencia { vigente, programada, historica, cancelada }

/// Clasifica una vigencia individual para el historial — a diferencia de
/// [clasificarVigencias] (que decide cuál es LA vigente de un grupo),
/// esta função no necesita comparar contra otras vigencias de la misma
/// línea: el estado de cada fila es autosuficiente.
EstadoVigencia clasificarParaHistorial(ServicioLineaComercialVigenciaData vigencia, DateTime hoy) {
  if (vigencia.cicloVidaRegistro == CicloVidaRegistro.archivado.name) {
    return EstadoVigencia.cancelada;
  }

  final hoySinHora = soloFecha(hoy);
  final inicio = soloFecha(vigencia.fechaInicioVigencia);
  final fin = vigencia.fechaFinVigencia == null ? null : soloFecha(vigencia.fechaFinVigencia!);

  if (inicio.isAfter(hoySinHora)) return EstadoVigencia.programada;
  if (fin != null && fin.isBefore(hoySinHora)) return EstadoVigencia.historica;
  return EstadoVigencia.vigente;
}

/// Un tramo de días consecutivos (orden semanal 0=lunes...6=domingo) que
/// comparten exactamente el mismo horario — el bloque mínimo del resumen
/// corto del horario personalizado ("L-V 20:00–07:00").
class TramoHorarioPersonalizado {
  const TramoHorarioPersonalizado({
    required this.diaDesde,
    required this.diaHasta,
    required this.horaInicioMinutos,
    required this.horaFinMinutos,
  });

  final int diaDesde;
  final int diaHasta;
  final int horaInicioMinutos;
  final int horaFinMinutos;
}

/// Agrupa las filas de horario personalizado de una vigencia en tramos
/// de días consecutivos con el mismo horario — pura función de datos,
/// reutilizable por la columna Turno de la tabla (resumen corto) y por
/// cualquier tooltip/detalle. Los días de descanso (`activo == false`)
/// nunca generan tramo — quedan implícitos por ausencia, igual que en
/// el ejemplo "L-V 20:00–07:00 · S-D 16:00–07:00" (ningún día de
/// descanso en ese caso) tanto como en un esquema con días sueltos de
/// descanso salteados entre tramos de trabajo.
List<TramoHorarioPersonalizado> agruparHorarioPersonalizado(List<ServicioLineaComercialVigenciaHorarioData> filas) {
  final porDia = {for (final f in filas) f.diaSemana: f};
  final tramos = <TramoHorarioPersonalizado>[];

  int dia = 0;
  while (dia < 7) {
    final fila = porDia[dia];
    if (fila == null || !fila.activo) {
      dia++;
      continue;
    }
    var fin = dia;
    while (fin + 1 < 7) {
      final siguiente = porDia[fin + 1];
      if (siguiente == null ||
          !siguiente.activo ||
          siguiente.horaInicio != fila.horaInicio ||
          siguiente.horaFin != fila.horaFin) {
        break;
      }
      fin++;
    }
    tramos.add(
      TramoHorarioPersonalizado(diaDesde: dia, diaHasta: fin, horaInicioMinutos: fila.horaInicio, horaFinMinutos: fila.horaFin),
    );
    dia = fin + 1;
  }

  return tramos;
}
