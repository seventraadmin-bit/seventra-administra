import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/organizacion/data/tables/cliente_table.dart';

import '../shared/direccion_input.dart';
import '../usecases/eliminar_cliente_fisicamente_usecase.dart';

/// Cliente comercial junto con su dirección de referencia resultante —
/// lo que devuelve `guardarExpediente` tras persistir ambas secciones en
/// una sola transacción (mismo patrón que `SucursalExpedienteRaw`).
class ClienteExpedienteRaw {
  const ClienteExpedienteRaw({required this.cliente, this.direccionReferencia});

  final ClienteData cliente;
  final DireccionData? direccionReferencia;
}

abstract interface class ClienteRepository {
  Future<ClienteData> crear(ClienteCompanion datos);

  Future<ClienteData?> obtenerPorId(String id);

  Future<List<ClienteData>> listarActivos();

  /// Nombre de TODOS los Clientes referenciados por [ids], en una sola
  /// consulta.
  ///
  /// Distinto de [listarActivos]: una Cuenta por cobrar de un Cliente
  /// suspendido sigue existiendo y su nombre tiene que poder
  /// mostrarse. Existe para que Reportes resuelva cientos de
  /// referencias sin una consulta por fila.
  Future<Map<String, ClienteData>> listarPorIds(Iterable<String> ids);

  /// `motivo` y `actorUsuarioId` alimentan la bitácora del Cliente:
  /// suspender o terminar a un Cliente es un hecho comercial que tiene
  /// que poder explicarse después.
  Future<ClienteData> cambiarEstatus({
    required String id,
    required EstatusCliente nuevo,
    String? motivo,
    String? actorUsuarioId,
  });

  Future<DireccionData?> obtenerDireccionReferencia(String clienteId);

  /// Versión en lote de [obtenerDireccionReferencia] (Etapa 16, pasada
  /// visual de Comercial) — una sola consulta `WHERE cliente_id IN
  /// (...)` para resolver la ubicación de todos los Clientes del
  /// listado a la vez, nunca una consulta por tarjeta/fila. `ids` vacío
  /// devuelve `{}` sin tocar la base de datos.
  Future<Map<String, DireccionData>> listarDireccionesReferencia(List<String> clienteIds);

  /// Persiste datos generales + dirección de referencia en una sola
  /// transacción — mismo patrón que `SucursalRepository.guardarExpediente`.
  /// `motivo`/`actorUsuarioId` alimentan la bitácora del Cliente: una
  /// corrección sin autor ni explicación es justo lo que esta etapa
  /// deja de permitir.
  Future<ClienteExpedienteRaw> guardarExpediente({
    required String clienteId,
    required ClienteCompanion datosGenerales,
    String? motivo,
    String? actorUsuarioId,
    required DireccionInput? direccionReferencia,
  });

  /// Si [datos] trae `esPrincipal = true`, retira esa marca de cualquier
  /// otro contacto del mismo Cliente y tipo dentro de la misma
  /// transacción — nunca puede quedar más de un principal activo por
  /// tipo (lo aplica también la base de datos vía el índice único
  /// parcial, pero el repositorio nunca depende únicamente de que la
  /// escritura falle: la resuelve explícitamente).
  Future<ContactoData> agregarContacto(ContactoCompanion datos, {String? actorUsuarioId});

  /// Teléfono y correo llegan a la bitácora ENMASCARADOS.
  Future<ContactoData> actualizarContacto({
    required String id,
    required ContactoCompanion cambios,
    String? motivo,
    String? actorUsuarioId,
  });

  Future<ContactoData> archivarContacto(String id, {String? motivo, String? actorUsuarioId});

  Future<List<ContactoData>> obtenerContactos(String clienteId);

  /// A diferencia de `obtenerContactos` (que solo devuelve activos), este
  /// método no filtra por `cicloVidaRegistro` — lo necesita cualquier
  /// pantalla que deba seguir mostrando un Contacto ya asignado como
  /// responsable aunque después se haya archivado (ver
  /// `ServicioExpedienteScreen`, Etapa 4F.2).
  Future<ContactoData?> obtenerContactoPorId(String id);

  /// Eliminación física extraordinaria (Etapa 15, mismo patrón que la
  /// Etapa 11D) — ver el doc comment de la implementación para las
  /// condiciones exactas.
  Future<EliminarClienteFisicamenteResultado> eliminarFisicamente({
    required String clienteId,
    required String motivo,
    String? actorUsuarioId,
  });

  /// Crea el `Attachment` (categoría `logo`) y su fila de unión en
  /// `ClienteAttachment` en una sola operación — mismo patrón que
  /// `EmpleadoRepository.adjuntarDocumento` (Etapa 16, evolución
  /// visual). No mueve el puntero `logoAttachmentId` por sí solo — eso
  /// lo hace [actualizarLogo] a propósito, para que el llamador pueda
  /// archivar el logo anterior entre una llamada y la otra.
  Future<AttachmentData> adjuntarLogo({
    required String clienteId,
    required String originalFileName,
    required String storedFileName,
    required String path,
    required String mimeType,
    required int sizeBytes,
  });

  /// Mueve `Cliente.logoAttachmentId` al nuevo Attachment.
  Future<ClienteData> actualizarLogo({required String clienteId, required String attachmentId});

  /// Quita el logo vigente (`logoAttachmentId = NULL`) — el Attachment
  /// anterior se archiva aparte (nunca se borra), mismo criterio que un
  /// reemplazo. A diferencia de la fotografía de Empleado, el logo de
  /// Cliente sí puede quedar vacío explícitamente (Resolución de
  /// Marlon: "poder reemplazarse/eliminarse").
  Future<ClienteData> eliminarLogo(String clienteId);
}
