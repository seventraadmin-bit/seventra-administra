import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_table.dart';

import '../shared/direccion_input.dart';

/// Fila de Servicio ya acompañada del nombre de su Cliente y de su Tipo
/// de Servicio — lo que necesita el listado sin que la UI tenga que
/// resolver esas dos relaciones por su cuenta (mismo motivo que
/// `EntidadFiscalConDomicilio`).
class ServicioListItem {
  const ServicioListItem({
    required this.servicio,
    required this.clienteNombre,
    required this.tipoServicioNombre,
  });

  final ServicioData servicio;
  final String clienteNombre;
  final String tipoServicioNombre;
}

/// Transacción que compone 2 escrituras (Servicio + nodo raíz de
/// Ubicación) como una sola unidad atómica. Desde la Etapa 4F.1 ya no
/// incluye la Dirección operativa: un Servicio cotizado puede existir
/// sin ella — se captura por separado desde el expediente (Etapa 4F.2).
///
/// Recibe los códigos visibles ya generados por el llamador (mismo
/// principio que `SucursalRepository`).
abstract interface class ServicioRepository {
  Future<ServicioData> crear({
    required String codigoServicio,
    required String clienteId,
    required String nombre,
    required String tipoServicioId,
    required DateTime fechaInicio,
    required String codigoUbicacionRaiz,
    DateTime? fechaTermino,
    String? observaciones,
  });

  Future<ServicioData?> obtenerPorId(String id);

  Future<List<ServicioListItem>> listar();

  /// Nunca acepta `clienteId` en `cambios` — la relación con el Cliente
  /// es inmutable después de creada (ver `ActualizarServicioUseCase`).
  Future<ServicioData> actualizar({required String id, required ServicioCompanion cambios});

  Future<ServicioData> cambiarEstatus({
    required String id,
    required EstatusServicio nuevo,
    DateTime? fechaTermino,
  });

  /// `true` si existe una Dirección operativa (`tipo_direccion =
  /// 'operativa'`, arco `servicio_id`) activa para este Servicio —
  /// consulta pura, no depende de que exista todavía una UI de captura
  /// (esa es de la Etapa 4F.2). Usada por `CambiarEstatusServicioUseCase`
  /// para bloquear la transición a `activo`.
  Future<bool> tieneDireccionOperativaActiva(String servicioId);

  /// La Dirección operativa activa de este Servicio, si existe — para
  /// mostrarla en el expediente (Etapa 4F.2).
  Future<DireccionData?> obtenerDireccionOperativa(String servicioId);

  /// Captura/edita/limpia la Dirección operativa — mismo patrón de
  /// upsert que `EntidadFiscalRepository.guardarDomicilioFiscal`: busca
  /// la fila existente sin importar `cicloVidaRegistro` (a lo más una,
  /// garantizado por el `UNIQUE` real de `servicio_id`), reactiva y
  /// actualiza si existe, inserta solo si nunca existió — nunca un
  /// segundo `INSERT`, que además violaría ese `UNIQUE`. `input == null`
  /// archiva la existente (si había alguna) sin borrarla físicamente.
  Future<DireccionData?> guardarDireccionOperativa(String servicioId, DireccionInput? input);

  /// `entidadFiscalId == null` quita la asignación. Nunca valida
  /// pertenencia al mismo Cliente ni estado activo — eso vive en
  /// `AsignarEntidadFiscalAServicioUseCase`.
  Future<ServicioData> asignarEntidadFiscal({required String servicioId, required String? entidadFiscalId});

  /// `contactoId == null` quita la asignación. Nunca valida pertenencia
  /// ni estado — eso vive en `AsignarResponsableClienteUseCase`.
  Future<ServicioData> asignarResponsableCliente({required String servicioId, required String? contactoId});

  /// `sucursalId == null` quita la asignación. Nunca valida estado —
  /// eso vive en `AsignarSucursalAdministrativaUseCase`.
  Future<ServicioData> asignarSucursalAdministrativa({required String servicioId, required String? sucursalId});

  /// Texto libre transitorio — sin validación de dominio más allá de
  /// recorte/`vacío→null` (ver `GuardarResponsableInternoUseCase`).
  Future<ServicioData> guardarResponsableInterno({required String servicioId, required String? texto});

  /// Sueldo/bono mensual de referencia (Etapa 6B) — escritura cruda, sin
  /// validaciones de negocio (ver `GuardarSueldoReferenciaServicioUseCase`).
  Future<ServicioData> guardarSueldoReferencia({
    required String servicioId,
    required int? sueldoMensualReferenciaPersonal,
    required int? bonoMensualReferenciaPersonal,
  });
}
