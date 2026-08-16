import 'package:drift/drift.dart';

import '../../../../core/database/tables/audit_columns.dart';
import '../../../../core/database/tables/catalogos_tables.dart';
import 'cliente_portal_table.dart';
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

  /// Qué portal del Cliente usa esta vigencia (Etapa 15) — referencia,
  /// nunca una copia (mismo patrón que `entidadFiscalId`): si el portal
  /// se edita después, esta vigencia sigue apuntando a la misma fila y
  /// ve el valor actual. `null` si el Cliente no tiene ningún portal
  /// configurado, o si esta vigencia simplemente no usa ninguno.
  TextColumn get clientePortalId =>
      text().nullable().references(ClientePortal, #id, onDelete: KeyAction.restrict)();

  // --- LEGACY (Etapa 4H.1, retirado en la Etapa 15) — portal del
  // cliente capturado directamente aquí, duplicado en cada vigencia.
  // Reemplazado por `clientePortalId` → `ClientePortal`. Estas 5
  // columnas se conservan en la base de datos por compatibilidad con
  // vigencias históricas ya capturadas (la migración a `schemaVersion`
  // 52 las copia a `ClientePortal`, cifrando `portalContrasena` en el
  // proceso, pero nunca las borra ni las vuelve a escribir) — ningún
  // flujo nuevo las lee ni las escribe. Candidatas a eliminarse en una
  // futura etapa de limpieza, una vez confirmado que ninguna pantalla
  // ni reporte las consulta más.
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
