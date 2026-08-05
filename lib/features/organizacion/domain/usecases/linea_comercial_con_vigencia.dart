import 'package:riseg_one/core/database/app_database.dart';

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

/// Clasifica las vigencias `activo` de una línea contra la fecha de hoy
/// (comparando solo año/mes/día, nunca hora) en "vigente" (a lo más una)
/// y "programadas" (orden ascendente por fecha de inicio) — pura función
/// de fechas, reutilizable por el repositorio y por las pruebas.
({ServicioLineaComercialVigenciaData? vigente, List<ServicioLineaComercialVigenciaData> programadas})
    clasificarVigencias(List<ServicioLineaComercialVigenciaData> vigenciasActivas, DateTime hoy) {
  DateTime soloFecha(DateTime dt) => DateTime(dt.year, dt.month, dt.day);
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
