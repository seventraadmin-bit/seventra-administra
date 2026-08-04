import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/features/organizacion/data/repositories/puesto_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/puesto_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_puesto_usecase.dart';

void main() {
  late AppDatabase db;
  late CrearPuestoUseCase crearPuesto;
  late PuestoRepositoryImpl repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = PuestoRepositoryImpl(db);
    crearPuesto = CrearPuestoUseCase(repo, GenerarCodigoUseCase(CodigoSecuenciaService(db)));
  });

  tearDown(() => db.close());

  test('crea un puesto con código PUE-0001 y lo puede consultar', () async {
    final result = await crearPuesto.ejecutar(
      nombre: 'Guardia de seguridad',
      areaId: SeedIds.areaOperaciones,
      tipo: TipoPuesto.operativo,
      nivelJerarquico: 1,
    );

    expect(result.isOk, isTrue);
    result.when(
      ok: (p) {
        expect(p.codigo, 'PUE-0001');
        expect(p.nombre, 'Guardia de seguridad');
      },
      failure: (_) => fail('no debería fallar'),
    );

    final puestos = await repo.listarActivos();
    expect(puestos, hasLength(1));
  });

  test('dos puestos consecutivos reciben códigos distintos', () async {
    final r1 = await crearPuesto.ejecutar(
      nombre: 'Guardia',
      areaId: SeedIds.areaOperaciones,
      tipo: TipoPuesto.operativo,
      nivelJerarquico: 1,
    );
    final r2 = await crearPuesto.ejecutar(
      nombre: 'Supervisor',
      areaId: SeedIds.areaOperaciones,
      tipo: TipoPuesto.administrativo,
      nivelJerarquico: 2,
    );

    final codigos = [r1, r2].map((r) {
      String? codigo;
      r.when(ok: (p) => codigo = p.codigo, failure: (_) {});
      return codigo;
    }).toSet();

    expect(codigos, {'PUE-0001', 'PUE-0002'});
  });
}
