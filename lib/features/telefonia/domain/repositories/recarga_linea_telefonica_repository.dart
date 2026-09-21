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

  /// Nombre legible de la CuentaFinanciera desde la que salió un Egreso
  /// automático — para el diff de auditoría, que muestra nombres y
  /// nunca UUIDs. `null` si el Egreso no existe o no tiene cuenta.
  Future<String?> nombreCuentaDeEgreso(String egresoId);

  /// Id de la CuentaFinanciera desde la que salió un Egreso automático
  /// — para precargar el selector al corregir. `null` si no aplica.
  Future<String?> cuentaDeEgreso(String egresoId);

  /// Ids de los Egresos generados automáticamente por recargas
  /// VIGENTES — fuente de `OrigenEgreso.telefonia` en la clasificación
  /// de Finanzas. Una recarga cancelada ya canceló su Egreso, así que
  /// no aparece en el listado de Egresos registrados.
  Future<List<String>> listarEgresoIds();

  /// La recarga a la que pertenece un Egreso automático, o `null` si
  /// ese Egreso no nació de una recarga. Es la relación REAL por FK —
  /// nunca se infiere por concepto, importe ni fecha.
  Future<RecargaLineaTelefonicaData?> obtenerPorEgresoId(String egresoId);

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

  /// Todas las recargas del rango, cada una ya con su
  /// [DestinoHistoricoRecarga] resuelto (`null` si la línea no tenía
  /// asignación vigente ese día) — Etapa 12C (Reportes): el desglose
  /// "recargas por Servicio/Empleado" que [totalPorEmpleado]/
  /// [totalPorServicio] no dan (esos solo suman para UN id conocido).
  /// Reutiliza exactamente el mismo mecanismo de resolución histórica
  /// (una sola carga de recargas + una sola carga de asignaciones, sin
  /// N+1), solo que devuelve el desglose en vez de un total ya sumado.
  Future<List<({RecargaLineaTelefonicaData recarga, DestinoHistoricoRecarga? destino})>> listarConDestinoEnRango({
    DateTime? desde,
    DateTime? hasta,
  });

  /// Registra la recarga Y su efecto financiero, atómicamente
  /// (schemaVersion 86): Cuenta → exactamente un Egreso automático;
  /// tarjeta → exactamente un `MovimientoDeuda` de cargo y JAMÁS un
  /// Egreso. Mismo patrón exacto que `CompraRepository.registrar` y
  /// `TiempoExtraRepository.crear` — nunca una cuarta arquitectura.
  Future<RecargaLineaTelefonicaData> registrar({
    required String lineaTelefonicaId,
    required DateTime fecha,
    required int importe,
    /// Cómo se pagó — mismo catálogo `FormaPago` de Compras/TEX/Egresos.
    required String formaPago,

    /// Origen cuando `formaPago != tarjeta`. Exactamente uno de este o
    /// [deudaIdTarjeta] se puebla; la invariante la impone el caso de uso.
    String? cuentaFinancieraId,

    /// Origen cuando `formaPago == tarjeta`.
    String? deudaIdTarjeta,
    String? observaciones,
    String? actorUsuarioId,
  });

  /// Corrige una recarga YA registrada (schemaVersion 81) — sobre la
  /// MISMA fila, nunca creando una "recarga sustituta": una recarga no
  /// tiene identidad contable propia que obligue a preservar la fila
  /// errónea (a diferencia de un Complemento de pago timbrado), y
  /// duplicarla inflaría todos los totalizadores del módulo.
  ///
  /// Escritura cruda, sin validaciones ni auditoría: el motivo y el
  /// evento los impone `CorregirRecargaLineaTelefonicaUseCase`.
  /// Corrige la recarga y **mueve su efecto financiero** a donde
  /// corresponda, atómicamente. Soporta las seis transiciones:
  /// Cuenta→misma Cuenta, Cuenta→otra Cuenta, TDC→misma TDC,
  /// TDC→otra TDC, Cuenta→TDC y TDC→Cuenta. Nunca deja dos efectos
  /// vivos ni ninguno.
  ///
  /// [motivo] viaja a la corrección del Egreso/cargo subyacente, no
  /// sólo a la bitácora de Telefonía.
  Future<RecargaLineaTelefonicaData> corregir({
    required String recargaLineaTelefonicaId,
    DateTime? fecha,
    int? importe,
    /// Cómo se pagó — mismo catálogo `FormaPago` de Compras/TEX/Egresos.
    required String formaPago,

    /// Origen cuando `formaPago != tarjeta`. Exactamente uno de este o
    /// [deudaIdTarjeta] se puebla; la invariante la impone el caso de uso.
    String? cuentaFinancieraId,

    /// Origen cuando `formaPago == tarjeta`.
    String? deudaIdTarjeta,
    String? observaciones,
    bool limpiarObservaciones = false,
    required String motivo,
    String? actorUsuarioId,
  });

  /// Anula una recarga conservando la fila (schemaVersion 81). Deja de
  /// sumar en TODOS los totalizadores, pero sigue en el historial con
  /// su motivo — un error de captura nunca obliga a borrar evidencia.
  /// Anula la recarga y revierte su efecto financiero exactamente una
  /// vez: cancela el Egreso automático (Cuenta) o revierte el cargo de
  /// la tarjeta (TDC). Nunca crea un Ingreso ni un segundo gasto. Una
  /// recarga legacy —sin origen financiero registrado— se cancela sin
  /// tocar ningún balance.
  Future<RecargaLineaTelefonicaData> cancelar({
    required String recargaLineaTelefonicaId,
    required String motivo,
    String? actorUsuarioId,
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
