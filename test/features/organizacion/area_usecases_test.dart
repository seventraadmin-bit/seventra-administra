import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';
import 'package:riseg_one/features/organizacion/data/repositories/area_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/puesto_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/puesto_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/activar_area_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/actualizar_area_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_area_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_puesto_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/desactivar_area_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_area_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_puesto_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/puesto_validator.dart';

void main() {
  late AppDatabase db;
  late AreaRepositoryImpl areaRepo;
  late PuestoRepositoryImpl puestoRepo;
  late GenerarCodigoUseCase generarCodigo;
  late CrearAreaUseCase crearArea;
  late ActualizarAreaUseCase actualizarArea;
  late ActivarAreaUseCase activarArea;
  late DesactivarAreaUseCase desactivarArea;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    areaRepo = AreaRepositoryImpl(db);
    puestoRepo = PuestoRepositoryImpl(db);
    generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
    crearArea = CrearAreaUseCase(areaRepo, generarCodigo);
    actualizarArea = ActualizarAreaUseCase(areaRepo);
    activarArea = ActivarAreaUseCase(areaRepo);
    desactivarArea = DesactivarAreaUseCase(areaRepo, puestoRepo);
  });

  tearDown(() => db.close());

  test('la primera Área nueva creada por la UI obtiene exactamente ARE-0007', () async {
    // Prueba de integración del flujo completo: siembra (6 Áreas ya en
    // ARE-0001..0006, contador en 6) + GenerarCodigoUseCase +
    // CrearAreaUseCase — no solo el generador aislado.
    final resultado = await crearArea.ejecutar(nombre: 'Calidad');

    expect(resultado, isA<GuardarAreaExitoso>());
    expect((resultado as GuardarAreaExitoso).area.codigo, 'ARE-0007');

    final segundaResultado = await crearArea.ejecutar(nombre: 'Innovación');
    expect((segundaResultado as GuardarAreaExitoso).area.codigo, 'ARE-0008');
  });

  test('nombre vacío se rechaza al crear', () async {
    final resultado = await crearArea.ejecutar(nombre: '   ');
    expect(resultado, isA<GuardarAreaNombreRequerido>());
  });

  test('nombre vacío se rechaza al actualizar', () async {
    final creada = (await crearArea.ejecutar(nombre: 'Calidad')) as GuardarAreaExitoso;
    final resultado = await actualizarArea.ejecutar(id: creada.area.id, nombre: '');
    expect(resultado, isA<GuardarAreaNombreRequerido>());
  });

  group('DesactivarAreaUseCase', () {
    Future<String> crearPuestoActivoEn(String areaId) async {
      final crearPuesto = CrearPuestoUseCase(puestoRepo, generarCodigo, PuestoValidator(areaRepo));
      final resultado = await crearPuesto.ejecutar(
        PuestoBorrador(nombre: 'Guardia', areaId: areaId, tipo: TipoPuesto.operativo, nivelJerarquico: 1),
      );
      return (resultado as GuardarPuestoExitoso).puesto.id;
    }

    test('permite desactivar cuando no hay Puestos activos relacionados', () async {
      final resultado = await desactivarArea.ejecutar(SeedIds.areaOperaciones);
      expect(resultado, isA<DesactivarAreaExitoso>());
      expect((resultado as DesactivarAreaExitoso).area.activo, isFalse);
    });

    test('bloquea la desactivación si hay al menos un Puesto activo en el Área', () async {
      await crearPuestoActivoEn(SeedIds.areaOperaciones);

      final resultado = await desactivarArea.ejecutar(SeedIds.areaOperaciones);

      expect(resultado, isA<DesactivarAreaBloqueadaPorPuestosActivos>());
      expect((resultado as DesactivarAreaBloqueadaPorPuestosActivos).cantidad, 1);

      final area = await areaRepo.obtenerPorId(SeedIds.areaOperaciones);
      expect(area!.activo, isTrue, reason: 'no debió modificarse');
    });

    test('los Puestos archivados no cuentan para el bloqueo', () async {
      final puestoId = await crearPuestoActivoEn(SeedIds.areaOperaciones);
      await puestoRepo.cambiarCicloVida(id: puestoId, nuevo: CicloVidaRegistro.archivado);

      final resultado = await desactivarArea.ejecutar(SeedIds.areaOperaciones);

      expect(resultado, isA<DesactivarAreaExitoso>());
    });

    test('reactivar un Área nunca se bloquea', () async {
      await desactivarArea.ejecutar(SeedIds.areaOperaciones);
      final area = await activarArea.ejecutar(SeedIds.areaOperaciones);
      expect(area.activo, isTrue);
    });
  });
}
