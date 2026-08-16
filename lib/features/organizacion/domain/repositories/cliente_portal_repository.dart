import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';

import '../usecases/eliminar_cliente_portal_fisicamente_usecase.dart';

abstract interface class ClientePortalRepository {
  Future<ClientePortalData> crear(ClientePortalCompanion datos);

  Future<ClientePortalData?> obtenerPorId(String id);

  /// Todos los portales del Cliente — activos **y** archivados: uno
  /// archivado debe seguir siendo encontrable para reactivarlo o para
  /// resolver una referencia histórica (`ConfiguracionCobroVigencia`/
  /// `DocumentoPorEmitir`).
  Future<List<ClientePortalData>> listarPorCliente(String clienteId);

  Future<ClientePortalData> actualizar({required String id, required ClientePortalCompanion cambios});

  Future<ClientePortalData> cambiarCicloVida({required String id, required CicloVidaRegistro nuevo});

  /// Eliminación física extraordinaria (Etapa 11D) — rechazada si el
  /// portal está referenciado por alguna `ConfiguracionCobroVigencia` o
  /// `DocumentoPorEmitir` (el histórico debe seguir siendo resoluble).
  /// Ver el doc comment de `ClientePortalRepositoryImpl.eliminarFisicamente`
  /// para las condiciones exactas.
  Future<EliminarClientePortalFisicamenteResultado> eliminarFisicamente({
    required String id,
    required String motivo,
    String? actorUsuarioId,
  });
}
