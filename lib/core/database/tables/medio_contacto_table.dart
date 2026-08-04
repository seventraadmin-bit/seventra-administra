import 'package:drift/drift.dart';

import 'audit_columns.dart';

/// Canal de contacto general (teléfono, correo, sitio web) de una Empresa
/// o Sucursal — sin persona asociada (para eso está `Contacto`).
///
/// Mismo patrón de arco exclusivo que [Direccion]; ver su documentación
/// para el razonamiento completo, incluyendo por qué las FK se declaran
/// como SQL crudo en vez de `.references()` tipado.
class MedioContacto extends Table with AuditColumns {
  TextColumn get empresaId => text().nullable()();

  TextColumn get sucursalId => text().nullable()();

  TextColumn get telefono => text().nullable()();

  TextColumn get correo => text().nullable()();

  TextColumn get sitioWeb => text().nullable()();

  TextColumn get etiqueta => text().nullable()();

  @override
  List<String> get customConstraints => [
        'FOREIGN KEY (empresa_id) REFERENCES empresa (id) ON DELETE RESTRICT',
        'FOREIGN KEY (sucursal_id) REFERENCES sucursal (id) ON DELETE RESTRICT',
        'CHECK ('
            '(CASE WHEN empresa_id IS NOT NULL THEN 1 ELSE 0 END + '
            'CASE WHEN sucursal_id IS NOT NULL THEN 1 ELSE 0 END) = 1'
            ')',
      ];
}
