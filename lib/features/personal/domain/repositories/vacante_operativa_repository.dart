import 'package:riseg_one/core/database/app_database.dart';

/// Bitácora del ciclo "posición cubierta → vacante → nuevamente
/// cubierta" (Etapa 15, rediseño del Dashboard gerencial) — ver el doc
/// comment completo de `VacanteOperativa` para el criterio de diseño.
abstract interface class VacanteOperativaRepository {
  /// Todas las vacantes `abierta`, orden ascendente por `fechaApertura`
  /// (la más antigua primero) — fuente de "1 vacante · 4 días" en el
  /// Dashboard.
  Future<List<VacanteOperativaData>> listarAbiertas();

  Future<List<VacanteOperativaData>> listarAbiertasPorServicio(String servicioId);

  /// Historial completo (abiertas + cubiertas) de una línea comercial,
  /// orden descendente por `fechaApertura`.
  Future<List<VacanteOperativaData>> listarPorLinea(String lineaComercialId);

  /// Vacantes cuya apertura y/o cobertura cayó dentro de
  /// `[rangoInicio, rangoFin]` — fuente de los eventos "vacante
  /// abierta"/"vacante cubierta" de la Actividad reciente (Parte N). Una
  /// fila cubierta dentro del rango cuya apertura fue anterior al rango
  /// aparece igual (su cobertura sí es un evento del periodo).
  Future<List<VacanteOperativaData>> listarRecientes({required DateTime rangoInicio, required DateTime rangoFin});

  /// Promedio de `fechaCobertura - fechaApertura` entre todas las
  /// vacantes `cubierta` (histórico completo, no acotado por periodo —
  /// mismo criterio "estado actual" que el resto del bloque Personal) —
  /// `null` cuando ninguna vacante se ha cubierto todavía (Etapa 15
  /// v1.1, Parte 4: "Personal necesita métricas útiles").
  Future<Duration?> promedioDuracionCobertura();

  /// Escritura cruda — sin validaciones de negocio. Reconcilia el
  /// número de vacantes `abierta` de [lineaComercialId] contra el
  /// déficit real (`requerido - cubierto`, nunca negativo): abre las
  /// que falten o cierra (marca `cubierta`) las que sobren, en orden
  /// FIFO por `fechaApertura`. [asignacionOrigenId]/[asignacionCoberturaId]
  /// solo se asocian a la primera fila abierta/cerrada en esta llamada
  /// (normalmente una sola, ya que cada evento real de
  /// `AsignacionServicio` mueve el déficit de a una unidad) — nunca se
  /// inventa una atribución para el resto. Idempotente: llamarlo con el
  /// mismo `requerido`/`cubierto` sin cambios no genera ni cierra nada.
  Future<void> sincronizarLinea({
    required String servicioId,
    required String lineaComercialId,
    required int requerido,
    required int cubierto,
    required DateTime fecha,
    required String motivoApertura,
    String? asignacionOrigenId,
    String? asignacionCoberturaId,
  });
}
