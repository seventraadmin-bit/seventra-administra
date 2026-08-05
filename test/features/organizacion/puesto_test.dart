import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/features/organizacion/data/repositories/area_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/puesto_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/puesto_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_puesto_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_puesto_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/puesto_validator.dart';

void main() {
  late AppDatabase db;
  late CrearPuestoUseCase crearPuesto;
  late PuestoRepositoryImpl repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = PuestoRepositoryImpl(db);
    crearPuesto = CrearPuestoUseCase(
      repo,
      GenerarCodigoUseCase(CodigoSecuenciaService(db)),
      PuestoValidator(AreaRepositoryImpl(db)),
    );
  });

  tearDown(() => db.close());

  test('crea un puesto con código PUE-0001 y lo puede consultar', () async {
    final resultado = await crearPuesto.ejecutar(
      const PuestoBorrador(
        nombre: 'Guardia de seguridad',
        areaId: SeedIds.areaOperaciones,
        tipo: TipoPuesto.operativo,
        nivelJerarquico: 1,
      ),
    );

    expect(resultado, isA<GuardarPuestoExitoso>());
    final exitoso = resultado as GuardarPuestoExitoso;
    expect(exitoso.puesto.codigo, 'PUE-0001');
    expect(exitoso.puesto.nombre, 'Guardia de seguridad');

    final puestos = await repo.listarActivos();
    expect(puestos, hasLength(1));
  });

  test('dos puestos consecutivos reciben códigos distintos', () async {
    final r1 = await crearPuesto.ejecutar(
      const PuestoBorrador(
        nombre: 'Guardia',
        areaId: SeedIds.areaOperaciones,
        tipo: TipoPuesto.operativo,
        nivelJerarquico: 1,
      ),
    );
    final r2 = await crearPuesto.ejecutar(
      const PuestoBorrador(
        nombre: 'Supervisor',
        areaId: SeedIds.areaOperaciones,
        tipo: TipoPuesto.administrativo,
        nivelJerarquico: 2,
      ),
    );

    final codigos = [r1, r2].map((r) => (r as GuardarPuestoExitoso).puesto.codigo).toSet();
    expect(codigos, {'PUE-0001', 'PUE-0002'});
  });
}
