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

  Future<ClienteData> cambiarEstatus({required String id, required EstatusCliente nuevo});

  Future<DireccionData?> obtenerDireccionReferencia(String clienteId);

  /// Persiste datos generales + dirección de referencia en una sola
  /// transacción — mismo patrón que `SucursalRepository.guardarExpediente`.
  Future<ClienteExpedienteRaw> guardarExpediente({
    required String clienteId,
    required ClienteCompanion datosGenerales,
    required DireccionInput? direccionReferencia,
  });

  /// Si [datos] trae `esPrincipal = true`, retira esa marca de cualquier
  /// otro contacto del mismo Cliente y tipo dentro de la misma
  /// transacción — nunca puede quedar más de un principal activo por
  /// tipo (lo aplica también la base de datos vía el índice único
  /// parcial, pero el repositorio nunca depende únicamente de que la
  /// escritura falle: la resuelve explícitamente).
  Future<ContactoData> agregarContacto(ContactoCompanion datos);

  Future<ContactoData> actualizarContacto({required String id, required ContactoCompanion cambios});

  Future<ContactoData> archivarContacto(String id);

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
}
