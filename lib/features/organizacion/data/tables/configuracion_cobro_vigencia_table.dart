import 'package:drift/drift.dart';

import '../../../../core/database/tables/audit_columns.dart';
import '../../../../core/database/tables/catalogos_tables.dart';
import 'configuracion_cobro_table.dart';
import 'entidad_fiscal_table.dart';

/// Tipo de documento con el que se cobra un Servicio.
enum TipoDocumentoCobro { cfdi, reciboDePago }

/// Cómo se agrupan varios Servicios en un mismo documento — siempre un
/// valor capturado explícitamente, nunca inferido por compartir Entidad
/// fiscal (Etapa 4H.1, regla explícita de Marlon).
enum AgrupacionCobro { porServicio, porEntidadFiscal, porCliente, manual }

/// Método de pago del CFDI — `noAplica` es el único valor válido cuando
/// `tipoDocumento == reciboDePago`.
enum MetodoPagoCobro { pue, ppd, noAplica }

/// Un período histórico de la Configuración de cobro de un Servicio —
/// documento, frecuencia, periodo, agrupación, método, Entidad fiscal y
/// los datos de contacto/entrega son versionados aquí, mismo criterio de
/// `ServicioLineaComercialVigencia`. Las reglas temporales de emisión/
/// procesamiento/pago esperado se agregan en la Etapa 4H.2 — esta etapa
/// solo captura qué se cobra y cómo, no cuándo exactamente.
///
/// `cicloVidaRegistro`/vigente-programada-histórica-cancelada: mismo
/// modelo exacto que `ServicioLineaComercialVigencia` — ver esa clase
/// para la explicación completa; no se repite aquí para no duplicar el
/// razonamiento.
class ConfiguracionCobroVigencia extends Table with AuditColumns {
  TextColumn get configuracionCobroId =>
      text().references(ConfiguracionCobro, #id, onDelete: KeyAction.restrict)();

  // Literales en vez de referencias a los enums — mismo motivo que
  // `AuditColumns.cicloVidaRegistro`.
  TextColumn get tipoDocumento => text()();

  TextColumn get frecuenciaId => text().references(TipoFrecuenciaCobro, #id, onDelete: KeyAction.restrict)();

  /// Día del mes (1-31) en que inicia el período de servicio que se
  /// factura — ej. 21 (Sportium, período 21-20) o 1 (mes calendario).
  IntColumn get diaInicioPeriodo => integer()();

  TextColumn get agrupacion => text()();

  TextColumn get metodo => text()();

  BoolColumn get requiereComplemento => boolean().withDefault(const Constant(false))();

  /// Obligatoria si `tipoDocumento == cfdi`, opcional si `reciboDePago`
  /// — validado en `ConfiguracionCobroValidator`, no aquí (requeriría
  /// una subconsulta condicional que SQLite no expresa como `CHECK`).
  TextColumn get entidadFiscalId =>
      text().nullable().references(EntidadFiscal, #id, onDelete: KeyAction.restrict)();

  // --- Portal del cliente (Etapa 4H.1) — estructura completa, no solo
  // texto libre. `portalContrasena` se guarda en texto plano: RIESGO
  // ACEPTADO Y DOCUMENTADO para esta etapa (confirmado explícitamente
  // por Marlon) — no existe todavía infraestructura de cifrado en el
  // proyecto. Debe cifrarse antes de que cualquier credencial real de
  // producción se capture aquí.
  TextColumn get portalNombre => text().nullable()();

  TextColumn get portalUrl => text().nullable()();

  TextColumn get portalUsuario => text().nullable()();

  TextColumn get portalContrasena => text().nullable()();

  TextColumn get portalObservaciones => text().nullable()();

  /// Texto libre transitorio — no existe todavía un catálogo de cuentas
  /// bancarias en el proyecto (mismo criterio que
  /// `Servicio.responsableInterno`: migrará a FK cuando ese catálogo
  /// exista, preservando el texto histórico).
  TextColumn get cuentaBancaria => text().nullable()();

  TextColumn get observaciones => text().nullable()();

  DateTimeColumn get fechaInicioVigencia => dateTime()();

  DateTimeColumn get fechaFinVigencia => dateTime().nullable()();

  @override
  List<String> get customConstraints => [
        'CHECK (dia_inicio_periodo BETWEEN 1 AND 31)',
        'CHECK (fecha_fin_vigencia IS NULL OR fecha_fin_vigencia >= fecha_inicio_vigencia)',
      ];
}
