import 'package:drift/drift.dart';

import '../app_database.dart';

/// Migración de esquema de la Etapa 4E.1 (`schemaVersion` 2 o 3 → 4):
/// retira `razonSocial`/`rfc` de `Cliente` (pasan conceptualmente a
/// Entidad fiscal, Etapa 4E.2 — un Cliente comercial puede agrupar
/// varias Entidades fiscales, así que no tiene sentido que cargue una
/// única razón social/RFC propios) y vuelve requerido `nombreComercial`;
/// agrega la columna `tipo` a `Contacto` junto con su índice único de
/// "un principal activo por tipo".
///
/// No es una migración de datos (no hay valores que trasladar de un
/// lado a otro): es estructural. Por eso, antes de tocar nada, verifica
/// que ambas tablas estén vacías — nunca hubo pantalla real para crear
/// un Cliente antes de esta etapa, así que en cualquier instalación
/// real no debería haber filas, pero la migración falla explícitamente
/// en vez de asumirlo y descartar datos en silencio.
Future<void> migrarClienteContactoV4(AppDatabase db, Migrator m) async {
  await db.transaction(() async {
    final clientes = await db.customSelect('SELECT COUNT(*) AS n FROM cliente').getSingle();
    final contactos = await db.customSelect('SELECT COUNT(*) AS n FROM contacto').getSingle();
    final totalClientes = clientes.data['n'] as int;
    final totalContactos = contactos.data['n'] as int;

    if (totalClientes > 0 || totalContactos > 0) {
      throw StateError(
        'Migración a schemaVersion 4: el nuevo esquema de Cliente retira las '
        'columnas razonSocial/rfc, algo que solo es seguro si la tabla está '
        'vacía. Se encontraron $totalClientes fila(s) en Cliente y '
        '$totalContactos en Contacto — la migración se detiene para no '
        'perder datos reales.',
      );
    }

    // `Contacto` se elimina antes que `Cliente` porque su FK depende de
    // ella; ambas se recrean con la forma actual de sus clases Dart
    // (ya actualizadas a la forma de la Etapa 4E.1).
    await db.customStatement('DROP TABLE contacto');
    await db.customStatement('DROP TABLE cliente');
    await m.createTable(db.cliente);
    await m.createTable(db.contacto);
    await m.createIndex(db.idxContactoClienteTipoPrincipalActivo);
  });
}
