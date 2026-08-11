import 'package:riseg_one/core/database/app_database.dart';

/// Quién correspondía a una línea telefónica en el momento en que se
/// registró una recarga (Etapa 9C, punto 3) — resuelto por rango de
/// fecha contra `AsignacionLineaTelefonica`, **nunca** guardado en
/// `RecargaLineaTelefonica`: ese historial ya existe y está bien
/// formado (nunca se edita, siempre cierra-y-abre), así que duplicarlo
/// aquí sería el mismo tipo de dato redundante que el proyecto evita en
/// todos sus ledgers derivados.
class DestinoHistoricoRecarga {
  const DestinoHistoricoRecarga({this.empleadoId, this.servicioId});

  final String? empleadoId;
  final String? servicioId;
}

/// Recargas prepago de una línea telefónica (Etapa 9C) — ver el doc
/// comment de `RecargaLineaTelefonica` para el criterio de diseño
/// completo. Sin Egreso automático: Telefonía registra únicamente el
/// contexto operativo, Finanzas sigue siendo la única fuente de
/// movimientos de dinero reales.
abstract interface class RecargaLineaTelefonicaRepository {
  Future<RecargaLineaTelefonicaData?> obtenerPorId(String recargaLineaTelefonicaId);

  /// Historial completo de una línea, orden descendente por `fecha` —
  /// el primero es siempre "la última recarga".
  Future<List<RecargaLineaTelefonicaData>> listarPorLinea(String lineaTelefonicaId);

  /// Suma de `importe` de todas las recargas de una línea.
  Future<int> totalPorLinea(String lineaTelefonicaId);

  /// La recarga más reciente de cada línea que tiene al menos una,
  /// resuelto en una sola consulta masiva (evita N+1) — usado por el
  /// listado de líneas, mismo criterio que
  /// `LineaTelefonicaPlanRepository.listarVigentes` (retirada en esta
  /// misma etapa, pero el criterio de "consulta masiva para el
  /// listado" se conserva).
  Future<Map<String, RecargaLineaTelefonicaData>> obtenerUltimasPorTodasLasLineas();

  /// A quién correspondía la línea el día de esta recarga — `null` si
  /// la línea nunca tuvo una asignación vigente en esa fecha (recarga
  /// hecha mientras la línea estaba sin asignar). Ver el doc comment de
  /// [DestinoHistoricoRecarga].
  Future<DestinoHistoricoRecarga?> obtenerDestinoHistorico(String recargaLineaTelefonicaId);

  /// Gasto total en recargas atribuible a un Empleado — deriva, para
  /// cada recarga en el rango, a quién correspondía su línea *en ese
  /// momento* (no la asignación actual). Un cambio posterior de
  /// asignación nunca reescribe a quién correspondió una recarga ya
  /// registrada.
  Future<int> totalPorEmpleado(String empleadoId, {DateTime? desde, DateTime? hasta});

  /// Análogo a [totalPorEmpleado], para un Servicio.
  Future<int> totalPorServicio(String servicioId, {DateTime? desde, DateTime? hasta});

  /// Gasto total de Telefonía en un rango de fechas (todas las líneas).
  Future<int> totalPorRango({DateTime? desde, DateTime? hasta});

  Future<RecargaLineaTelefonicaData> registrar({
    required String lineaTelefonicaId,
    required DateTime fecha,
    required int importe,
    String? observaciones,
  });

  /// Comprobante opcional de una recarga puntual — nunca obligatorio
  /// (Marlon: "únicamente si realmente aporta valor").
  Future<AttachmentData> adjuntarComprobante({
    required String recargaLineaTelefonicaId,
    required String originalFileName,
    required String storedFileName,
    required String path,
    required String mimeType,
    required int sizeBytes,
  });
}
