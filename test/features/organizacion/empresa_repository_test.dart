import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/organizacion/data/repositories/empresa_repository_impl.dart';

void main() {
  late AppDatabase db;
  late EmpresaRepositoryImpl repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = EmpresaRepositoryImpl(db);
  });

  tearDown(() => db.close());

  test('obtenerActiva devuelve la RSG-01 sembrada', () async {
    final activa = await repo.obtenerActiva();
    expect(activa.codigo, 'RSG-01');
    expect(activa.nombreComercial, 'Seguridad Privada RISEG');
    expect(activa.razonSocial, isNull);
    expect(activa.rfc, isNull);
  });

  test('el índice único parcial impide una segunda empresa activa', () async {
    await expectLater(
      db.into(db.empresa).insert(
            EmpresaCompanion.insert(codigo: 'RSG-02', nombreComercial: 'Otra empresa'),
          ),
      throwsA(anything),
    );
  });

  test('actualizarDatosGenerales aplica los cambios sobre la activa', () async {
    await repo.actualizarDatosGenerales(
      const EmpresaCompanion(razonSocial: Value('Seguridad Privada RISEG S.A. de C.V.')),
    );

    final activa = await repo.obtenerActiva();
    expect(activa.razonSocial, 'Seguridad Privada RISEG S.A. de C.V.');
  });

  test('archivar la única empresa activa lanza StateError', () async {
    final activa = await repo.obtenerActiva();
    await expectLater(() => repo.archivar(activa.id), throwsStateError);
  });
}
