import 'package:drift/drift.dart';

import '../../../../core/database/tables/audit_columns.dart';
import '../../../../core/database/tables/catalogos_tables.dart';
import 'puesto_table.dart';
import 'servicio_linea_comercial_table.dart';

/// Cómo se relaciona el precio capturado con el IVA — solo una etiqueta
/// informativa en esta etapa: ningún monto de IVA se calcula todavía
/// (eso queda para la futura Configuración de cobro/Facturación).
enum TratamientoIva {
  /// El precio capturado es subtotal; el IVA se agrega aparte.
  masIva,

  /// El precio capturado ya contiene el IVA.
  ivaIncluido,

  /// No se calcula IVA — Servicios que se cobran mediante recibo.
  noAplica,
}

/// Un período histórico de condiciones comerciales de una
/// [ServicioLineaComercial] — puesto, cantidad, turno, precio y
/// tratamiento de IVA son versionados aquí, nunca actualizados in place
/// (Etapa 4G.1, Resolución A): un cambio en cualquiera de ellos, o en la
/// fecha de vigencia misma, cierra la fila vigente y crea una nueva.
/// `descripcion`/`observaciones` sí se editan sobre la misma fila —son
/// anotaciones, no condiciones comerciales.
///
/// `cicloVidaRegistro` no distingue "vigente" de "programada" — ambas
/// son `activo`; la diferencia es puramente de fecha, calculada en
/// tiempo de lectura contra `DateTime.now()` (Etapa 4G.1, Resolución C:
/// Marlon rechazó que una vigencia futura sustituya de inmediato a la
/// vigente). Solo `archivado` significa "cerrada" — ya sea porque una
/// vigencia posterior la reemplazó, o porque se cerró explícitamente sin
/// reemplazo. No existe un índice único que garantice "como mucho una
/// vigencia activa por línea": puede haber varias simultáneamente
/// (la vigente hoy + una o más programadas a futuro) — la ausencia de
/// solapamiento de rangos de fecha es una invariante de aplicación,
/// verificada por pruebas, no por SQLite (que no tiene restricciones de
/// exclusión de rango).
class ServicioLineaComercialVigencia extends Table with AuditColumns {
  TextColumn get lineaComercialId =>
      text().references(ServicioLineaComercial, #id, onDelete: KeyAction.restrict)();

  TextColumn get puestoId => text().references(Puesto, #id, onDelete: KeyAction.restrict)();

  TextColumn get modalidadTurnoId =>
      text().references(TipoModalidadTurno, #id, onDelete: KeyAction.restrict)();

  IntColumn get cantidadElementos => integer()();

  /// Precio mensual por elemento, en centavos — nunca `real`/`double`,
  /// para no arrastrar errores de redondeo de punto flotante en el
  /// primer campo monetario de todo el proyecto (precedente para la
  /// futura Fase Financiera).
  IntColumn get precioUnitario => integer()();

  // Literal en vez de referencia al enum: mismo motivo que
  // `AuditColumns.cicloVidaRegistro`.
  TextColumn get tratamientoIva => text()();

  TextColumn get descripcion => text().nullable()();

  DateTimeColumn get fechaInicioVigencia => dateTime()();

  DateTimeColumn get fechaFinVigencia => dateTime().nullable()();

  TextColumn get observaciones => text().nullable()();

  @override
  List<String> get customConstraints => [
        'CHECK (cantidad_elementos > 0)',
        'CHECK (precio_unitario > 0)',
        'CHECK (fecha_fin_vigencia IS NULL OR fecha_fin_vigencia >= fecha_inicio_vigencia)',
      ];
}
