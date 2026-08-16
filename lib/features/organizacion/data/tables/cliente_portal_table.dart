import 'package:drift/drift.dart';

import '../../../../core/database/tables/audit_columns.dart';
import 'cliente_table.dart';

/// Tipo/propósito de un portal del Cliente (Etapa 15) — clasificación
/// simple para distinguir accesos cuando el Cliente tiene varios
/// portales. Deliberadamente un enum cerrado, no un catálogo editable:
/// son pocos valores estables, no datos de negocio que cambien con el
/// tiempo (mismo criterio que otros enums literales del proyecto).
enum TipoPortalCliente { facturacion, proveedores, pagos, otro }

/// Portal de acceso de un Cliente (Etapa 15) — única fuente de verdad
/// nueva para nombre/URL/usuario/contraseña/observaciones de portal.
/// Reemplaza la captura duplicada que antes vivía repetida en cada
/// `ConfiguracionCobroVigencia` (`portalNombre`/`portalUrl`/
/// `portalUsuario`/`portalContrasena`/`portalObservaciones`, ahora
/// legacy — ver el doc comment de esas columnas). Un Cliente puede
/// tener cero, uno o varios portales; cada Configuración de cobro solo
/// referencia cuál usa (`ConfiguracionCobroVigencia.clientePortalId`),
/// nunca vuelve a capturar sus datos — mismo patrón exacto que
/// `EntidadFiscal` (N:1 con Cliente, sin campo de estatus propio, solo
/// `cicloVidaRegistro` activo/archivado; acciones "Archivar/Reactivar").
///
/// `contrasenaCifrada` es el único lugar del proyecto (junto con
/// `BovedaCredencial.secretoCifrado`/`EquipoTelefonicoCredencial.contrasenaCifrada`)
/// donde se guarda esta contraseña — siempre cifrada con
/// `CredentialCipher` (AES-256-GCM, la misma infraestructura que ya
/// protege Bóveda y Telefonía), NUNCA en texto plano. Formato
/// autodescriptivo `'aesgcm$1$<ivBase64>$<ciphertextBase64>'` — ver
/// `CredentialCipher` para el detalle completo.
class ClientePortal extends Table with AuditColumns {
  TextColumn get clienteId => text().references(Cliente, #id, onDelete: KeyAction.restrict)();

  TextColumn get nombre => text()();

  // Literal en vez de referencia al enum — mismo motivo que
  // `AuditColumns.cicloVidaRegistro`.
  TextColumn get tipo => text()();

  TextColumn get url => text().nullable()();

  TextColumn get usuario => text().nullable()();

  TextColumn get contrasenaCifrada => text().nullable()();

  TextColumn get observaciones => text().nullable()();
}
