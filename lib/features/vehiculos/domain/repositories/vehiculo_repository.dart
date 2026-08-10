import 'package:riseg_one/core/database/app_database.dart';

/// El expediente de la flotilla (Etapa 8A) — "qué vehículo es" y su
/// condición operativa. Asignaciones/kilometraje/documentos/
/// mantenimiento viven en repositorios propios de etapas futuras
/// (8B/8C/8D), mismo criterio de separación que Inventario.
abstract interface class VehiculoRepository {
  Future<VehiculoData?> obtenerPorId(String id);

  /// Para validar duplicados antes de insertar/corregir — nunca se
  /// depende de capturar la violación del índice único parcial
  /// (`idx_vehiculo_placas_unica`/`idx_vehiculo_vin_unico`), mismo
  /// criterio de "validar antes de escribir" que el resto del proyecto.
  Future<VehiculoData?> obtenerPorPlacas(String placas);

  Future<VehiculoData?> obtenerPorVin(String vin);

  /// Solo `cicloVidaRegistro == activo` salvo que se pida lo contrario
  /// — no confundir con `estatus`, que es la condición operativa (ver
  /// el doc comment de `Vehiculo`).
  Future<List<VehiculoData>> listar({bool soloActivos = true});

  Future<VehiculoData> crear({
    required String codigo,
    required String marca,
    required String modelo,
    int? anio,
    String? color,
    String? placas,
    String? vin,
    String? numeroMotor,
    required String tipoVehiculo,
    DateTime? fechaAdquisicion,
    int? costoAdquisicion,
    String? observaciones,
  });

  Future<VehiculoData> corregir({
    required String vehiculoId,
    String? marca,
    String? modelo,
    int? anio,
    String? color,
    String? placas,
    String? vin,
    String? numeroMotor,
    String? tipoVehiculo,
    DateTime? fechaAdquisicion,
    int? costoAdquisicion,
    String? observaciones,
    bool limpiarAnio = false,
    bool limpiarColor = false,
    bool limpiarPlacas = false,
    bool limpiarVin = false,
    bool limpiarNumeroMotor = false,
    bool limpiarFechaAdquisicion = false,
    bool limpiarCostoAdquisicion = false,
    bool limpiarObservaciones = false,
  });

  /// Cambia manualmente el estatus a `enMantenimiento`/`fueraDeServicio`/
  /// `disponible` — nunca a `asignado` (eso lo mantiene
  /// `AsignacionVehiculo`, Etapa 8B) ni a `baja` (usa [darDeBaja]).
  Future<VehiculoData> cambiarEstatus({required String vehiculoId, required String estatus});

  /// Baja terminal — estatus, fecha y motivo en una sola transacción.
  /// Desde la Etapa 8B también cierra la asignación vigente si existe;
  /// en 8A no hay ninguna que cerrar todavía.
  Future<VehiculoData> darDeBaja({
    required String vehiculoId,
    required DateTime fechaBaja,
    required String motivoBaja,
    String? observacionesBaja,
  });

  Future<AttachmentData> adjuntarDocumento({
    required String vehiculoId,
    String? categoria,
    required String originalFileName,
    required String storedFileName,
    required String path,
    required String mimeType,
    required int sizeBytes,
  });

  /// Reemplaza la fotografía vigente — mueve el puntero
  /// `fotografiaAttachmentId`; la anterior se archiva desde el caso de
  /// uso (mismo criterio que `ActualizarFotografiaEmpleadoUseCase`).
  Future<VehiculoData> actualizarFotografia({required String vehiculoId, required String attachmentId});
}
