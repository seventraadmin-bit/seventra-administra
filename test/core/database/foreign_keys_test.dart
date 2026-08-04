// Prueba dedicada a que `PRAGMA foreign_keys` nunca vuelva a quedar
// apagado en silencio — encontrado como un bug real durante la Etapa 4B
// (SQLite lo trae apagado por defecto; sin esto, cada FK declarada desde
// la Etapa 4A era solo documentación, nunca se aplicaba). Cubre tanto el
// valor del flag como la aplicación real (una FK inválida debe rechazarse,
// no solo "el PRAGMA dice 1").

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('PRAGMA foreign_keys queda activado en cualquier conexión nueva', () async {
    final fila = await db.customSelect('PRAGMA foreign_keys').getSingle();
    expect(fila.read<int>('foreign_keys'), 1);
  });

  test('una referencia inválida es rechazada de verdad, no solo el flag', () async {
    // `empresaId` apunta a una Empresa que no existe — si la aplicación de
    // FK alguna vez se desactiva por accidente, este insert pasaría en
    // silencio en vez de fallar.
    await expectLater(
      db.into(db.direccion).insert(
            DireccionCompanion.insert(
              empresaId: const Value('empresa-inexistente'),
              tipoDireccion: 'fiscal',
              calle: 'Calle Falsa',
              numeroExterior: '123',
              colonia: 'Colonia X',
              municipioAlcaldia: 'Municipio X',
              estado: 'Estado X',
              codigoPostal: '00000',
            ),
          ),
      throwsException,
    );
  });
}
