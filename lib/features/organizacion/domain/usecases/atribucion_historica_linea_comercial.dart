import 'package:riseg_one/core/database/app_database.dart';

/// Candidata de atribución: una línea comercial vigente hoy, con lo
/// mínimo necesario para decidir si una asignación histórica sin
/// perfil (`lineaComercialId == null`) le pertenece sin ambigüedad.
class LineaVigenteAtribuible {
  const LineaVigenteAtribuible({required this.lineaComercialId, required this.modalidadTurnoId});

  final String lineaComercialId;
  final String? modalidadTurnoId;
}

/// Resultado de atribuir las `AsignacionServicio` vigentes sin línea
/// (`lineaComercialId == null`) de UN Servicio a sus líneas comerciales
/// vigentes — corrección de compatibilidad histórica (Etapa 15: la
/// columna se volvió nullable exclusivamente para datos previos a esa
/// etapa, nunca se adivinó retroactivamente en su momento).
class AtribucionHistoricaLineas {
  const AtribucionHistoricaLineas({required this.atribuidasPorLinea, required this.ambiguas});

  /// `lineaComercialId` → cantidad de asignaciones históricas
  /// atribuidas a esa línea (a sumar sobre el conteo directo por
  /// `lineaComercialId` ya explícito).
  final Map<String, int> atribuidasPorLinea;

  /// Asignaciones que NO pudieron atribuirse sin ambigüedad — requieren
  /// regularización manual (Maestro) antes de contar hacia cualquier
  /// línea específica.
  final List<AsignacionServicioData> ambiguas;
}

/// Política de atribución histórica (bug real: Dashboard/Cobertura
/// ignoraba asignaciones vigentes con `lineaComercialId == null`,
/// reportándolas como `0/1` cuando en realidad sí cubrían la única
/// posición del Servicio).
///
/// Regla A — una sola línea vigente: cualquier asignación histórica
/// del mismo Servicio se atribuye a esa única línea sin ambigüedad (no
/// existe otra candidata posible).
///
/// Regla B — dos o más líneas vigentes: se atribuye SOLO si la
/// asignación tiene `turnoId` y ese turno coincide con la
/// `modalidadTurnoId` de EXACTAMENTE una línea vigente. Cualquier otro
/// caso (turno nulo, cero coincidencias, dos o más coincidencias) queda
/// en [AtribucionHistoricaLineas.ambiguas] — nunca se adivina.
///
/// Nunca escribe nada: es una función pura de lectura, usada tanto por
/// `ObtenerCoberturaOperativaUseCase`/`listarLineasEnFecha` (cálculo en
/// vivo) como por la UI que decide si mostrar "regularizar".
AtribucionHistoricaLineas atribuirAsignacionesHistoricas({
  required List<AsignacionServicioData> asignacionesSinLinea,
  required List<LineaVigenteAtribuible> lineasVigentes,
}) {
  if (asignacionesSinLinea.isEmpty || lineasVigentes.isEmpty) {
    return AtribucionHistoricaLineas(atribuidasPorLinea: const {}, ambiguas: asignacionesSinLinea);
  }

  if (lineasVigentes.length == 1) {
    return AtribucionHistoricaLineas(
      atribuidasPorLinea: {lineasVigentes.single.lineaComercialId: asignacionesSinLinea.length},
      ambiguas: const [],
    );
  }

  final atribuidas = <String, int>{};
  final ambiguas = <AsignacionServicioData>[];
  for (final asignacion in asignacionesSinLinea) {
    final turnoId = asignacion.turnoId;
    if (turnoId == null) {
      ambiguas.add(asignacion);
      continue;
    }
    final candidatas = lineasVigentes.where((l) => l.modalidadTurnoId == turnoId).toList();
    if (candidatas.length != 1) {
      ambiguas.add(asignacion);
      continue;
    }
    final id = candidatas.single.lineaComercialId;
    atribuidas[id] = (atribuidas[id] ?? 0) + 1;
  }
  return AtribucionHistoricaLineas(atribuidasPorLinea: atribuidas, ambiguas: ambiguas);
}
