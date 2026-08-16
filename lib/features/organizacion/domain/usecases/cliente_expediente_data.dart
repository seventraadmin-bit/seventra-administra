import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/entidad_fiscal_repository.dart';

/// Vista compuesta del expediente de Cliente comercial — el Cliente
/// junto con su dirección de referencia (si existe), sus Contactos
/// activos, sus Entidades fiscales (activas **y** archivadas — una
/// archivada debe seguir siendo visible para poder reactivarla) y sus
/// portales (Etapa 15, mismo criterio: activos y archivados).
class ClienteExpedienteData {
  const ClienteExpedienteData({
    required this.cliente,
    this.direccionReferencia,
    this.contactos = const [],
    this.entidadesFiscales = const [],
    this.portales = const [],
  });

  final ClienteData cliente;
  final DireccionData? direccionReferencia;
  final List<ContactoData> contactos;
  final List<EntidadFiscalConDomicilio> entidadesFiscales;
  final List<ClientePortalData> portales;
}
