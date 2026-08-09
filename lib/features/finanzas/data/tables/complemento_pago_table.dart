import 'package:drift/drift.dart';

import '../../../../core/database/tables/audit_columns.dart';
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
/// Relación **1:1 con `Pago`** (`pagoId` único, decisión definitiva de
/// Marlon: "no quiero una relación N:M en esta etapa") — un Pago que
/// liquida varias Cuentas por cobrar PPD-con-complemento se reporta en
/// un único Complemento, ya que las Cuentas cubiertas se obtienen a
/// través de las `AplicacionPago` de ese mismo Pago, sin necesidad de
/// una tabla de relación adicional.
///
/// `uuid`/`montoTotal` nunca son editables una vez registrados
/// (Resolución de Marlon, igual que en `Pago`): un error se corrige
/// cancelando y registrando un Complemento nuevo, nunca editando.
class ComplementoPago extends Table with AuditColumns {
  TextColumn get pagoId => text().unique().references(Pago, #id, onDelete: KeyAction.restrict)();

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

  TextColumn get actor => text().nullable()();

  TextColumn get datosRelevantes => text().nullable()();
}
