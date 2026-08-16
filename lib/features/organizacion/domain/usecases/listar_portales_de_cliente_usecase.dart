import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/cliente_portal_repository.dart';

/// Wrapper delgado sobre `ClientePortalRepository.listarPorCliente()` —
/// la UI nunca consulta el repositorio directamente, mismo motivo que
/// `ListarEntidadesFiscalesDeClienteUseCase`. Incluye activos y
/// archivados — un archivado debe seguir siendo encontrable para
/// reactivarlo; el filtrado a "solo activos" para el selector de
/// Configuración de cobro ocurre en la UI, no aquí.
class ListarPortalesDeClienteUseCase {
  ListarPortalesDeClienteUseCase(this._repository);

  final ClientePortalRepository _repository;

  Future<List<ClientePortalData>> ejecutar(String clienteId) => _repository.listarPorCliente(clienteId);
}
