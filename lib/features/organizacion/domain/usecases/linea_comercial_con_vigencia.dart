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
  });

  final ServicioLineaComercialData linea;
  final ServicioLineaComercialVigenciaData? vigenciaActual;
  final List<ServicioLineaComercialVigenciaData> vigenciasProgramadas;
  final String puestoNombre;
  final String modalidadTurnoNombre;

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
