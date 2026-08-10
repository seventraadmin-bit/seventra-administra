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

  TextColumn get imei => text().nullable()();

  TextColumn get numeroTelefonico => text().nullable()();

  @override
  Set<Column> get primaryKey => {unidadId};
}
