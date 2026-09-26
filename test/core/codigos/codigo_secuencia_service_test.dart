import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/database/app_database.dart';

void main() {
  late AppDatabase db;
  late CodigoSecuenciaService service;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    service = CodigoSecuenciaService(db);
  });

  tearDown(() => db.close());

  test('genera códigos secuenciales con el padding configurado', () async {
    expect(await service.siguienteCodigo('cliente'), 'CLI-000001');
    expect(await service.siguienteCodigo('cliente'), 'CLI-000002');
  });

  test('el código de empresa ya refleja la Empresa inicial sembrada', () async {
    // La siembra (EMP-01) ya consumió el primer número: el siguiente debe
    // ser 02, no volver a emitir 01.
    expect(await service.siguienteCodigo('empresa'), 'EMP-02');
  });

  test('nunca reutiliza un número, incluso si se generan muchos', () async {
    final generados = <String>{};
    for (var i = 0; i < 20; i++) {
      generados.add(await service.siguienteCodigo('sucursal'));
    }
    expect(generados.length, 20);
  });

  test('tipo de entidad sin configuración lanza StateError', () async {
    expect(() => service.siguienteCodigo('inexistente'), throwsStateError);
  });

  test('reinicio anual: mismo año incrementa, año distinto reinicia en 1', () async {
    await db.into(db.codigoSecuencia).insert(
          CodigoSecuenciaCompanion.insert(
            entityType: 'compra_sintetica',
            prefijo: 'COM',
            digitos: 4,
            reseteaAnualmente: const Value(true),
          ),
        );

    final primero = await service.siguienteCodigo('compra_sintetica');
    expect(primero, 'COM-0001');

    final segundo = await service.siguienteCodigo('compra_sintetica');
    expect(segundo, 'COM-0002');

    // Simula que cambió el año: el contador debe reiniciar en 1.
    await (db.update(db.codigoSecuencia)
          ..where((t) => t.entityType.equals('compra_sintetica')))
        .write(const CodigoSecuenciaCompanion(anioActual: Value(2000)));

    final tercero = await service.siguienteCodigo('compra_sintetica');
    expect(tercero, 'COM-0001');
  });
}
