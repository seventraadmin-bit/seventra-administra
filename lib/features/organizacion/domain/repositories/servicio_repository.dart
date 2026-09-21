import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_table.dart';

import '../shared/direccion_input.dart';
import '../usecases/eliminar_servicio_fisicamente_usecase.dart';

/// Fila de Servicio ya acompañada del nombre de su Cliente y de su Tipo
/// de Servicio — lo que necesita el listado sin que la UI tenga que
/// resolver esas dos relaciones por su cuenta (mismo motivo que
/// `EntidadFiscalConDomicilio`).
class ServicioListItem {
  const ServicioListItem({
    required this.servicio,
    required this.clienteNombre,
    required this.tipoServicioNombre,
    this.clienteLogoAttachmentId,
    this.municipioAlcaldia,
    this.estado,
  });

  final ServicioData servicio;
  final String clienteNombre;
  final String tipoServicioNombre;

  /// Logo del Cliente dueño de este Servicio (Etapa 16, evolución
  /// visual) — mismo logo que ya se ve en el listado de Clientes,
  /// nunca una segunda copia. Resolver la ruta real en disco es
  /// responsabilidad del llamador (consulta en lote, ver
  /// `ServiciosListController`), igual que en Clientes.
  final String? clienteLogoAttachmentId;

  /// Municipio/Alcaldía y Estado de la Dirección operativa del
  /// Servicio (`Direccion.servicioId`, real 1:1) — `null` cuando el
  /// Servicio no tiene ninguna Dirección operativa capturada todavía;
  /// nunca inventada a partir del nombre del Servicio.
  final String? municipioAlcaldia;
  final String? estado;
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
  /// `motivo`/`actorUsuarioId` alimentan la bitácora del Servicio.
  Future<ServicioData> actualizar({
    required String id,
    required ServicioCompanion cambios,
    String? motivo,
    String? actorUsuarioId,
  });

  Future<ServicioData> cambiarEstatus({
    required String id,
    required EstatusServicio nuevo,
    DateTime? fechaTermino,
    String? motivo,
    String? actorUsuarioId,
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
  Future<ServicioData> asignarEntidadFiscal({
    required String servicioId,
    required String? entidadFiscalId,
    String? motivo,
    String? actorUsuarioId,
  });

  /// `contactoId == null` quita la asignación. Nunca valida pertenencia
  /// ni estado — eso vive en `AsignarResponsableClienteUseCase`.
  Future<ServicioData> asignarResponsableCliente({
    required String servicioId,
    required String? contactoId,
    String? actorUsuarioId,
  });

  /// `sucursalId == null` quita la asignación. Nunca valida estado —
  /// eso vive en `AsignarSucursalAdministrativaUseCase`.
  Future<ServicioData> asignarSucursalAdministrativa({
    required String servicioId,
    required String? sucursalId,
    String? actorUsuarioId,
  });

  /// Texto libre transitorio — sin validación de dominio más allá de
  /// recorte/`vacío→null` (ver `GuardarResponsableInternoUseCase`).
  Future<ServicioData> guardarResponsableInterno({
    required String servicioId,
    required String? texto,
    String? actorUsuarioId,
  });

  /// Eliminación física extraordinaria (Etapa 15, mismo patrón que la
  /// Etapa 11D) — ver el doc comment de la implementación para las
  /// condiciones exactas.
  Future<EliminarServicioFisicamenteResultado> eliminarFisicamente({
    required String servicioId,
    required String motivo,
    String? actorUsuarioId,
  });
}
