import 'package:drift/drift.dart';

import '../../../../core/database/tables/audit_columns.dart';
import '../../../usuarios/data/tables/usuario_table.dart';
import 'pago_table.dart';

enum EstatusComplementoPago { registrado, cancelado }

/// Tipos de evento del historial de un Complemento de pago
/// (`ComplementoPagoEvento`) — mismo criterio append-only que
/// `PagoEvento`/`CuentaPorCobrarEvento`.
enum TipoEventoComplementoPago { registrado, corregido, cancelado, archivoAdjuntado }

/// Categoría de un adjunto de `ComplementoPago` (Etapa 4J.3) — mismo
/// criterio que `CategoriaAdjuntoDocumentoPorEmitir`: un complemento
/// real siempre trae PDF y XML, sin categoría "otro" porque, a
/// diferencia del comprobante de un Pago, aquí sí hay exactamente dos
/// tipos de archivo esperados.
enum CategoriaAdjuntoComplementoPago { pdf, xml }

/// Complemento de pago (CFDI de Recepción de Pagos) registrado
/// administrativamente (Etapa 4J.3) — nunca generado ni timbrado por
/// el sistema, solo se deja constancia de uno ya emitido externamente
/// (mismo criterio que `DocumentoPorEmitir.registrarEmision`).
///
/// Relación con `Pago`: **un Pago tiene N Complementos históricos, pero
/// a lo más UNO vigente (`estatus == 'registrado'`) a la vez**
/// (schemaVersion 79).
///
/// Hasta la v78 `pagoId` era `UNIQUE`, lo que expresaba un 1:1 estricto.
/// Eso dejaba un callejón sin salida real: cancelar un Complemento
/// reactiva la obligación fiscal (`complementoPendiente` vuelve a
/// `true`) pero era imposible registrar el sustituto, porque la fila
/// cancelada seguía ocupando el único lugar disponible. El Pago quedaba
/// pendiente para siempre.
///
/// El invariante correcto no es "una fila por Pago" sino "un
/// Complemento VIGENTE por Pago", y eso es exactamente un índice único
/// **parcial** (`complemento_pago_vigente_por_pago`). Las filas
/// canceladas quedan fuera del índice, así que se acumulan sin
/// estorbar — y nunca se borran ni se reusan: son evidencia de un CFDI
/// que existió y se canceló.
///
/// Un Pago que liquida varias Cuentas por cobrar PPD-con-complemento se
/// sigue reportando en UN Complemento vigente: las Cuentas cubiertas se
/// obtienen por las `AplicacionPago` de ese mismo Pago, sin tabla de
/// relación adicional (sigue sin haber N:M Complemento↔CxC).
///
/// `uuid`/`montoTotal` nunca son editables una vez registrados
/// (Resolución de Marlon, igual que en `Pago`): un error se corrige
/// cancelando y registrando un Complemento nuevo, nunca editando —
/// justamente el ciclo que la v79 vuelve posible.
@TableIndex.sql(
  "CREATE UNIQUE INDEX complemento_pago_vigente_por_pago "
  "ON complemento_pago (pago_id) WHERE estatus = 'registrado'",
)
class ComplementoPago extends Table with AuditColumns {
  TextColumn get pagoId => text().references(Pago, #id, onDelete: KeyAction.restrict)();

  /// UUID del complemento en sí (CFDI distinto al de la factura
  /// original) — se valida formato/longitud estándar y unicidad, pero
  /// deliberadamente nunca la versión (Resolución de Marlon: "no
  /// quiero acoplar el sistema a una versión específica del UUID
  /// emitido por el PAC").
  TextColumn get uuid => text().unique()();

  TextColumn get serieFiscal => text().nullable()();

  TextColumn get folioFiscal => text().nullable()();

  /// Fecha real de timbrado externo — nunca sustituye `createdAt`
  /// (Resolución de Marlon: la fecha de timbrado nunca reemplaza la
  /// fecha de registro administrativo, que ya provee `AuditColumns`).
  DateTimeColumn get fechaTimbrado => dateTime()();

  IntColumn get montoTotal => integer()();

  TextColumn get estatus => text().withDefault(const Constant('registrado'))();

  TextColumn get motivoCancelacion => text().nullable()();

  TextColumn get observaciones => text().nullable()();

  @override
  List<String> get customConstraints => ['CHECK (monto_total > 0)'];
}

/// Historial administrativo de un Complemento de pago (Etapa 4J.3) —
/// tabla de solo inserción, mismo criterio exacto que `PagoEvento`.
class ComplementoPagoEvento extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get complementoPagoId =>
      text().references(ComplementoPago, #id, onDelete: KeyAction.cascade)();

  DateTimeColumn get fechaHora => dateTime()();

  TextColumn get tipoEvento => text()();

  TextColumn get estadoAnterior => text().nullable()();

  TextColumn get estadoNuevo => text().nullable()();

  TextColumn get observacion => text().nullable()();

  /// **Legacy (Etapa 11D)** — nunca se pobló con un valor real; se
  /// conserva la columna físicamente por seguridad de migración pero
  /// ningún código desde 11D en adelante la lee ni la escribe. La única
  /// fuente funcional de "quién" es `actorUsuarioId`.
  TextColumn get actor => text().nullable()();

  TextColumn get actorUsuarioId => text().nullable().references(Usuario, #id, onDelete: KeyAction.setNull)();

  TextColumn get datosRelevantes => text().nullable()();
}
