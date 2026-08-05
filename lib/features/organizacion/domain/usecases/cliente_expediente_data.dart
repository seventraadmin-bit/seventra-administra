import 'package:riseg_one/core/database/app_database.dart';

/// Vista compuesta del expediente de Cliente comercial — el Cliente
/// junto con su dirección de referencia (si existe) y sus Contactos
/// activos. Entidades fiscales se agrega a esta misma vista en la
/// Etapa 4E.2 — no antes.
class ClienteExpedienteData {
  const ClienteExpedienteData({
    required this.cliente,
    this.direccionReferencia,
    this.contactos = const [],
  });

  final ClienteData cliente;
  final DireccionData? direccionReferencia;
  final List<ContactoData> contactos;
}
