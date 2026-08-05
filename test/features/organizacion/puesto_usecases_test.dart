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
import 'package:riseg_one/features/organizacion/domain/usecases/actualizar_puesto_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cambiar_ciclo_vida_puesto_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_puesto_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_puesto_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/puesto_errors.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/puesto_validator.dart';

const _puestoValido = PuestoBorrador(
  nombre: 'Guardia',
  areaId: SeedIds.areaOperaciones,
  tipo: TipoPuesto.operativo,
  nivelJerarquico: 1,
);

void main() {
  late AppDatabase db;
  late AreaRepositoryImpl areaRepo;
  late PuestoRepositoryImpl puestoRepo;
  late CrearPuestoUseCase crear;
  late ActualizarPuestoUseCase actualizar;
  late CambiarCicloVidaPuestoUseCase cambiarCicloVida;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    areaRepo = AreaRepositoryImpl(db);
    puestoRepo = PuestoRepositoryImpl(db);
    final validator = PuestoValidator(areaRepo);
    crear = CrearPuestoUseCase(puestoRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db)), validator);
    actualizar = ActualizarPuestoUseCase(puestoRepo, validator);
    cambiarCicloVida = CambiarCicloVidaPuestoUseCase(puestoRepo, areaRepo);
  });

  tearDown(() => db.close());

  group('validaciones compartidas (Crear y Actualizar)', () {
    test('nombre vacío se rechaza', () async {
      final resultado = await crear.ejecutar(const PuestoBorrador(
        nombre: '',
        areaId: SeedIds.areaOperaciones,
        tipo: TipoPuesto.operativo,
        nivelJerarquico: 1,
      ));
      expect(resultado, isA<GuardarPuestoErroresValidacion>());
      final errores = (resultado as GuardarPuestoErroresValidacion).errores;
      expect(errores.map((e) => e.campo), contains(CampoPuesto.nombre));
    });

    test('área inexistente se rechaza', () async {
      final resultado = await crear.ejecutar(const PuestoBorrador(
        nombre: 'Guardia',
        areaId: 'no-existe',
        tipo: TipoPuesto.operativo,
        nivelJerarquico: 1,
      ));
      expect(resultado, isA<GuardarPuestoErroresValidacion>());
      final errores = (resultado as GuardarPuestoErroresValidacion).errores;
      expect(
        errores,
        contains(predicate<ErrorCampoPuesto>(
          (e) => e.campo == CampoPuesto.area && e.codigo == CodigoErrorPuesto.noExiste,
        )),
      );
    });

    test('área inactiva se rechaza — no basta con que el selector solo muestre activas', () async {
      final areas = await areaRepo.listarTodas();
      final areaInactiva = areas.first;
      await areaRepo.desactivar(areaInactiva.id);

      final resultado = await crear.ejecutar(PuestoBorrador(
        nombre: 'Guardia',
        areaId: areaInactiva.id,
        tipo: TipoPuesto.operativo,
        nivelJerarquico: 1,
      ));
      expect(resultado, isA<GuardarPuestoErroresValidacion>());
      final errores = (resultado as GuardarPuestoErroresValidacion).errores;
      expect(
        errores,
        contains(predicate<ErrorCampoPuesto>(
          (e) => e.campo == CampoPuesto.area && e.codigo == CodigoErrorPuesto.inactiva,
        )),
      );
    });

    test('tipo no seleccionado se rechaza', () async {
      final resultado = await crear.ejecutar(const PuestoBorrador(
        nombre: 'Guardia',
        areaId: SeedIds.areaOperaciones,
        tipo: null,
        nivelJerarquico: 1,
      ));
      expect(resultado, isA<GuardarPuestoErroresValidacion>());
      final errores = (resultado as GuardarPuestoErroresValidacion).errores;
      expect(errores.map((e) => e.campo), contains(CampoPuesto.tipo));
    });

    test('nivel jerárquico fuera de 1–10 se rechaza en ambos extremos', () async {
      final bajo = await crear.ejecutar(const PuestoBorrador(
        nombre: 'Guardia',
        areaId: SeedIds.areaOperaciones,
        tipo: TipoPuesto.operativo,
        nivelJerarquico: 0,
      ));
      final alto = await crear.ejecutar(const PuestoBorrador(
        nombre: 'Guardia',
        areaId: SeedIds.areaOperaciones,
        tipo: TipoPuesto.operativo,
        nivelJerarquico: 11,
      ));

      for (final resultado in [bajo, alto]) {
        expect(resultado, isA<GuardarPuestoErroresValidacion>());
        final errores = (resultado as GuardarPuestoErroresValidacion).errores;
        expect(
          errores,
          contains(predicate<ErrorCampoPuesto>(
            (e) => e.campo == CampoPuesto.nivelJerarquico && e.codigo == CodigoErrorPuesto.fueraDeRango,
          )),
        );
      }
    });

    test('nivel jerárquico 1 y 10 (límites inclusive) son válidos', () async {
      final r1 = await crear.ejecutar(const PuestoBorrador(
        nombre: 'Guardia',
        areaId: SeedIds.areaOperaciones,
        tipo: TipoPuesto.operativo,
        nivelJerarquico: 1,
      ));
      final r10 = await crear.ejecutar(const PuestoBorrador(
        nombre: 'Director',
        areaId: SeedIds.areaOperaciones,
        tipo: TipoPuesto.administrativo,
        nivelJerarquico: 10,
      ));
      expect(r1, isA<GuardarPuestoExitoso>());
      expect(r10, isA<GuardarPuestoExitoso>());
    });
  });

  test('actualizar un Puesto cambiándolo a un Área inactiva se rechaza igual que en el alta', () async {
    final creado = (await crear.ejecutar(_puestoValido)) as GuardarPuestoExitoso;
    final areas = await areaRepo.listarTodas();
    final otraArea = areas.firstWhere((a) => a.id != SeedIds.areaOperaciones);
    await areaRepo.desactivar(otraArea.id);

    final resultado = await actualizar.ejecutar(
      id: creado.puesto.id,
      borrador: PuestoBorrador(
        nombre: 'Guardia',
        areaId: otraArea.id,
        tipo: TipoPuesto.operativo,
        nivelJerarquico: 1,
      ),
    );

    expect(resultado, isA<GuardarPuestoErroresValidacion>());
    final errores = (resultado as GuardarPuestoErroresValidacion).errores;
    expect(
      errores,
      contains(predicate<ErrorCampoPuesto>(
        (e) => e.campo == CampoPuesto.area && e.codigo == CodigoErrorPuesto.inactiva,
      )),
    );

    // El Puesto no debe haber quedado apuntando a la nueva Área.
    final sinCambios = await puestoRepo.obtenerPorId(creado.puesto.id);
    expect(sinCambios!.areaId, SeedIds.areaOperaciones);
  });

  test('actualizar con datos válidos persiste los cambios', () async {
    final creado = (await crear.ejecutar(_puestoValido)) as GuardarPuestoExitoso;

    final resultado = await actualizar.ejecutar(
      id: creado.puesto.id,
      borrador: const PuestoBorrador(
        nombre: 'Guardia Senior',
        areaId: SeedIds.areaOperaciones,
        tipo: TipoPuesto.operativo,
        nivelJerarquico: 3,
      ),
    );

    expect(resultado, isA<GuardarPuestoExitoso>());
    expect((resultado as GuardarPuestoExitoso).puesto.nombre, 'Guardia Senior');
    expect(resultado.puesto.nivelJerarquico, 3);
  });

  group('CambiarCicloVidaPuestoUseCase', () {
    test('archivar siempre está permitido', () async {
      final creado = (await crear.ejecutar(_puestoValido)) as GuardarPuestoExitoso;

      final resultado = await cambiarCicloVida.ejecutar(
        puestoId: creado.puesto.id,
        nuevo: CicloVidaRegistro.archivado,
      );

      expect(resultado, isA<CambiarCicloVidaPuestoExitoso>());
      expect(
        (resultado as CambiarCicloVidaPuestoExitoso).puesto.cicloVidaRegistro,
        CicloVidaRegistro.archivado.name,
      );
    });

    test('reactivar con el Área todavía activa funciona', () async {
      final creado = (await crear.ejecutar(_puestoValido)) as GuardarPuestoExitoso;
      await cambiarCicloVida.ejecutar(puestoId: creado.puesto.id, nuevo: CicloVidaRegistro.archivado);

      final resultado = await cambiarCicloVida.ejecutar(
        puestoId: creado.puesto.id,
        nuevo: CicloVidaRegistro.activo,
      );

      expect(resultado, isA<CambiarCicloVidaPuestoExitoso>());
      expect(
        (resultado as CambiarCicloVidaPuestoExitoso).puesto.cicloVidaRegistro,
        CicloVidaRegistro.activo.name,
      );
    });

    test('reactivar con el Área inactiva se bloquea sin modificar el registro', () async {
      final creado = (await crear.ejecutar(_puestoValido)) as GuardarPuestoExitoso;
      await cambiarCicloVida.ejecutar(puestoId: creado.puesto.id, nuevo: CicloVidaRegistro.archivado);
      await areaRepo.desactivar(SeedIds.areaOperaciones);

      final resultado = await cambiarCicloVida.ejecutar(
        puestoId: creado.puesto.id,
        nuevo: CicloVidaRegistro.activo,
      );

      expect(resultado, isA<CambiarCicloVidaPuestoAreaInactiva>());

      final sinCambios = await puestoRepo.obtenerPorId(creado.puesto.id);
      expect(sinCambios!.cicloVidaRegistro, CicloVidaRegistro.archivado.name);
    });
  });
}
