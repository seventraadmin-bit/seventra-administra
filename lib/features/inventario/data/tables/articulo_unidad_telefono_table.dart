import 'package:drift/drift.dart';

import 'articulo_unidad_table.dart';

/// Datos exclusivos de una `ArticuloUnidad` que es un teléfono (Etapa
/// 7A) — tabla 1:1 opcional, mismo patrón exacto ya usado en el
/// proyecto para "dato específico de un subtipo, no de toda la tabla
/// genérica" (`FichaTecnicaEmpleado`, `ComplementoPago` 1:1 con
/// `Pago`). `ArticuloUnidad` se queda solo con los campos realmente
/// universales (serie, marca, modelo); si en el futuro otro tipo de
/// unidad necesita sus propios campos específicos (ej. un radio), se
/// agrega una tabla del mismo tipo — nunca se tocan las columnas ya
/// existentes.
class ArticuloUnidadTelefono extends Table {
  TextColumn get unidadId => text().references(ArticuloUnidad, #id, onDelete: KeyAction.cascade)();

  /// Etiquetado "IMEI 1" en la UI — el nombre de columna se conserva tal
  /// cual por compatibilidad de migración, no se renombra.
  TextColumn get imei => text().nullable()();

  /// "IMEI 2" (Etapa 9D) — dispositivos de doble SIM. Sin `UNIQUE` a
  /// nivel de base de datos (ver `ConfigurarEquipoTelefonicoUseCase`):
  /// la unicidad de IMEI se valida en la capa de aplicación porque
  /// "único cuando corresponda" admite excepciones reales (equipos de
  /// segunda mano/gris) que un índice duro bloquearía con un error
  /// críptico.
  TextColumn get imei2 => text().nullable()();

  /// **Deprecado como fuente de verdad desde la Etapa 9D** — el número
  /// mostrado en el expediente del equipo se deriva de la
  /// `LineaTelefonica` actualmente vinculada vía `LineaTelefonicaEquipo`
  /// (puede divergir de este valor). Se conserva la columna físicamente
  /// (nunca se borra ni se migra) por compatibilidad histórica.
  TextColumn get numeroTelefonico => text().nullable()();

  @override
  Set<Column> get primaryKey => {unidadId};
}
