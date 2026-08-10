import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';

/// Compara solo año/mes/día — mismo criterio que `soloFecha` en
/// `linea_comercial_con_vigencia.dart` (duplicado deliberadamente, no
/// compartido entre dominios — mismo precedente que `soloFechaCobro`).
DateTime soloFechaSueldo(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

/// Clasifica las vigencias `activo` de sueldo de una `AsignacionServicio`
/// contra la fecha de hoy en "vigente" (a lo más una) y "programadas"
/// (orden ascendente por fecha de inicio) — misma lógica exacta que
/// `clasificarVigencias` (Etapa 4G.1), aplicada a sueldo/bono en vez de
/// puesto/cantidad/precio.
({AsignacionServicioSueldoVigenciaData? vigente, List<AsignacionServicioSueldoVigenciaData> programadas})
    clasificarVigenciasSueldo(List<AsignacionServicioSueldoVigenciaData> vigenciasActivas, DateTime hoy) {
  final hoySinHora = soloFechaSueldo(hoy);

  AsignacionServicioSueldoVigenciaData? vigente;
  final programadas = <AsignacionServicioSueldoVigenciaData>[];

  for (final v in vigenciasActivas) {
    final inicio = soloFechaSueldo(v.fechaInicioVigencia);
    final fin = v.fechaFinVigencia == null ? null : soloFechaSueldo(v.fechaFinVigencia!);

    if (inicio.isAfter(hoySinHora)) {
      programadas.add(v);
      continue;
    }
    if (fin != null && fin.isBefore(hoySinHora)) {
      continue; // Ya terminó — histórica, aunque cicloVidaRegistro siga en 'activo'.
    }
    if (vigente == null || inicio.isAfter(soloFechaSueldo(vigente.fechaInicioVigencia))) {
      vigente = v;
    }
  }

  programadas.sort((a, b) => a.fechaInicioVigencia.compareTo(b.fechaInicioVigencia));
  return (vigente: vigente, programadas: programadas);
}

/// Mismos 4 estados que `EstadoVigencia` (línea comercial) — ver esa
/// definición para el criterio completo.
enum EstadoVigenciaSueldo { vigente, programada, historica, cancelada }

/// Clasifica una vigencia de sueldo individual para historial — misma
/// lógica que `clasificarParaHistorial`, aplicada a sueldo/bono.
EstadoVigenciaSueldo clasificarParaHistorialSueldo(AsignacionServicioSueldoVigenciaData vigencia, DateTime hoy) {
  if (vigencia.cicloVidaRegistro == CicloVidaRegistro.archivado.name) {
    return EstadoVigenciaSueldo.cancelada;
  }

  final hoySinHora = soloFechaSueldo(hoy);
  final inicio = soloFechaSueldo(vigencia.fechaInicioVigencia);
  final fin = vigencia.fechaFinVigencia == null ? null : soloFechaSueldo(vigencia.fechaFinVigencia!);

  if (inicio.isAfter(hoySinHora)) return EstadoVigenciaSueldo.programada;
  if (fin != null && fin.isBefore(hoySinHora)) return EstadoVigenciaSueldo.historica;
  return EstadoVigenciaSueldo.vigente;
}
