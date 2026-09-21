import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/vehiculos/data/repositories/asignacion_vehiculo_repository_impl.dart';
import 'package:riseg_one/features/vehiculos/data/repositories/vehiculo_repository_impl.dart';
import 'package:riseg_one/features/vehiculos/data/tables/vehiculo_table.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/cambiar_estatus_vehiculo_usecase.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/corregir_vehiculo_usecase.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/crear_vehiculo_usecase.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/dar_de_baja_vehiculo_usecase.dart';

/// Cubre la fundación del dominio Vehículos (Etapa 8A) — alta,
/// unicidad condicional de placas/VIN, corrección, cambios de estatus
/// manuales y baja terminal. Asignaciones/kilometraje/documentos/
/// mantenimiento llegan en etapas futuras (8B-8E).
void main() {
  late AppDatabase db;
  late VehiculoRepositoryImpl vehiculoRepo;
  late CrearVehiculoUseCase crearVehiculo;
  late CorregirVehiculoUseCase corregirVehiculo;
  late CambiarEstatusVehiculoUseCase cambiarEstatus;
  late DarDeBajaVehiculoUseCase darDeBaja;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    vehiculoRepo = VehiculoRepositoryImpl(db, AsignacionVehiculoRepositoryImpl(db));
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));

    crearVehiculo = CrearVehiculoUseCase(vehiculoRepo, generarCodigo);
    corregirVehiculo = CorregirVehiculoUseCase(vehiculoRepo);
    cambiarEstatus = CambiarEstatusVehiculoUseCase(vehiculoRepo);
    darDeBaja = DarDeBajaVehiculoUseCase(vehiculoRepo);
  });

  tearDown(() => db.close());

  group('CrearVehiculoUseCase', () {
    test('da de alta con código consecutivo y estatus disponible por defecto', () async {
      final resultado = await crearVehiculo.ejecutar(marca: 'BMW', modelo: '320i', tipoVehiculo: 'sedan');

      expect(resultado, isA<CrearVehiculoExitoso>());
      final vehiculo = (resultado as CrearVehiculoExitoso).vehiculo;
      expect(vehiculo.codigo, 'VEH-000001');
      expect(vehiculo.estatus, 'disponible');
      expect(vehiculo.anio, isNull, reason: 'año es opcional');
      expect(vehiculo.placas, isNull, reason: 'placas es opcional — vehículo sin placas permitido');
    });

    test('rechaza marca vacía', () async {
      final resultado = await crearVehiculo.ejecutar(marca: '  ', modelo: '320i', tipoVehiculo: 'sedan');
      expect(resultado, isA<CrearVehiculoMarcaRequerida>());
    });

    test('rechaza modelo vacío', () async {
      final resultado = await crearVehiculo.ejecutar(marca: 'BMW', modelo: '', tipoVehiculo: 'sedan');
      expect(resultado, isA<CrearVehiculoModeloRequerido>());
    });

    test('rechaza año fuera de rango razonable', () async {
      final resultado = await crearVehiculo.ejecutar(marca: 'BMW', modelo: '320i', tipoVehiculo: 'sedan', anio: 1900);
      expect(resultado, isA<CrearVehiculoAnioInvalido>());
    });

    test('rechaza costo de adquisición negativo', () async {
      final resultado = await crearVehiculo.ejecutar(
        marca: 'BMW',
        modelo: '320i',
        tipoVehiculo: 'sedan',
        costoAdquisicion: -100,
      );
      expect(resultado, isA<CrearVehiculoCostoInvalido>());
    });

    test('rechaza placas duplicadas', () async {
      await crearVehiculo.ejecutar(marca: 'BMW', modelo: '320i', tipoVehiculo: 'sedan', placas: 'ABC-123');

      final resultado = await crearVehiculo.ejecutar(
        marca: 'Nissan',
        modelo: 'Versa',
        tipoVehiculo: 'sedan',
        placas: 'abc-123',
      );
      expect(resultado, isA<CrearVehiculoPlacasDuplicadas>(), reason: 'la comparación no distingue mayúsculas');
    });

    test('rechaza VIN duplicado', () async {
      await crearVehiculo.ejecutar(marca: 'BMW', modelo: '320i', tipoVehiculo: 'sedan', vin: 'VIN-0001');

      final resultado = await crearVehiculo.ejecutar(
        marca: 'Nissan',
        modelo: 'Versa',
        tipoVehiculo: 'sedan',
        vin: 'VIN-0001',
      );
      expect(resultado, isA<CrearVehiculoVinDuplicado>());
    });

    test('dos vehículos sin placas ni VIN coexisten sin conflicto', () async {
      final r1 = await crearVehiculo.ejecutar(marca: 'BMW', modelo: '320i', tipoVehiculo: 'sedan');
      final r2 = await crearVehiculo.ejecutar(marca: 'Nissan', modelo: 'Versa', tipoVehiculo: 'sedan');
      expect(r1, isA<CrearVehiculoExitoso>());
      expect(r2, isA<CrearVehiculoExitoso>());
    });
  });

  group('CorregirVehiculoUseCase', () {
    test('corrige metadatos y permite limpiar campos opcionales', () async {
      final vehiculo = ((await crearVehiculo.ejecutar(
        marca: 'BMW',
        modelo: '320i',
        tipoVehiculo: 'sedan',
        color: 'Negro',
      )) as CrearVehiculoExitoso)
          .vehiculo;

      final resultado = await corregirVehiculo.ejecutar(motivo: 'Corrección de prueba', vehiculoId: vehiculo.id, color: 'Blanco');
      expect(resultado, isA<CorregirVehiculoExitoso>());
      expect((resultado as CorregirVehiculoExitoso).vehiculo.color, 'Blanco');

      final limpiado = await corregirVehiculo.ejecutar(motivo: 'Corrección de prueba', vehiculoId: vehiculo.id, limpiarColor: true);
      expect((limpiado as CorregirVehiculoExitoso).vehiculo.color, isNull);
    });

    test('rechaza placas duplicadas contra otro Vehículo, pero permite conservar las propias', () async {
      final v1 = ((await crearVehiculo.ejecutar(
        marca: 'BMW',
        modelo: '320i',
        tipoVehiculo: 'sedan',
        placas: 'ABC-123',
      )) as CrearVehiculoExitoso)
          .vehiculo;
      await crearVehiculo.ejecutar(marca: 'Nissan', modelo: 'Versa', tipoVehiculo: 'sedan', placas: 'XYZ-999');

      final chocaConOtro = await corregirVehiculo.ejecutar(motivo: 'Corrección de prueba', vehiculoId: v1.id, placas: 'XYZ-999');
      expect(chocaConOtro, isA<CorregirVehiculoPlacasDuplicadas>());

      final conservaLaPropia = await corregirVehiculo.ejecutar(motivo: 'Corrección de prueba', vehiculoId: v1.id, placas: 'ABC-123');
      expect(conservaLaPropia, isA<CorregirVehiculoExitoso>());
    });

    test('rechaza id inexistente', () async {
      final resultado = await corregirVehiculo.ejecutar(motivo: 'Corrección de prueba', vehiculoId: 'no-existe', marca: 'BMW');
      expect(resultado, isA<CorregirVehiculoNoExiste>());
    });
  });

  group('CambiarEstatusVehiculoUseCase', () {
    test('mueve entre disponible/enMantenimiento/fueraDeServicio', () async {
      final vehiculo = ((await crearVehiculo.ejecutar(marca: 'BMW', modelo: '320i', tipoVehiculo: 'sedan'))
              as CrearVehiculoExitoso)
          .vehiculo;

      final aMantenimiento = await cambiarEstatus.ejecutar(vehiculoId: vehiculo.id, estatus: 'enMantenimiento');
      expect((aMantenimiento as CambiarEstatusVehiculoExitoso).vehiculo.estatus, 'enMantenimiento');

      final aDisponible = await cambiarEstatus.ejecutar(vehiculoId: vehiculo.id, estatus: 'disponible');
      expect((aDisponible as CambiarEstatusVehiculoExitoso).vehiculo.estatus, 'disponible');
    });

    test('rechaza destino asignado/baja — no son transiciones manuales', () async {
      final vehiculo = ((await crearVehiculo.ejecutar(marca: 'BMW', modelo: '320i', tipoVehiculo: 'sedan'))
              as CrearVehiculoExitoso)
          .vehiculo;

      final aAsignado = await cambiarEstatus.ejecutar(vehiculoId: vehiculo.id, estatus: 'asignado');
      expect(aAsignado, isA<CambiarEstatusVehiculoDestinoInvalido>());

      final aBaja = await cambiarEstatus.ejecutar(vehiculoId: vehiculo.id, estatus: 'baja');
      expect(aBaja, isA<CambiarEstatusVehiculoDestinoInvalido>());
    });

    test('un vehículo dado de baja nunca vuelve a cambiar de estatus', () async {
      final vehiculo = ((await crearVehiculo.ejecutar(marca: 'BMW', modelo: '320i', tipoVehiculo: 'sedan'))
              as CrearVehiculoExitoso)
          .vehiculo;
      await darDeBaja.ejecutar(vehiculoId: vehiculo.id, fechaBaja: DateTime(2026, 1, 1), motivoBaja: MotivoBajaVehiculo.venta);

      final resultado = await cambiarEstatus.ejecutar(vehiculoId: vehiculo.id, estatus: 'disponible');
      expect(resultado, isA<CambiarEstatusVehiculoYaDeBaja>());
    });
  });

  group('DarDeBajaVehiculoUseCase', () {
    test('venta no exige observaciones', () async {
      final vehiculo = ((await crearVehiculo.ejecutar(marca: 'BMW', modelo: '320i', tipoVehiculo: 'sedan'))
              as CrearVehiculoExitoso)
          .vehiculo;

      final resultado = await darDeBaja.ejecutar(
        vehiculoId: vehiculo.id,
        fechaBaja: DateTime(2026, 1, 1),
        motivoBaja: MotivoBajaVehiculo.venta,
      );
      expect(resultado, isA<DarDeBajaVehiculoExitoso>());
      final actualizado = (resultado as DarDeBajaVehiculoExitoso).vehiculo;
      expect(actualizado.estatus, 'baja');
      expect(actualizado.fechaBaja, DateTime(2026, 1, 1));
      expect(actualizado.motivoBaja, 'venta');
    });

    test('robo y pérdida total exigen observaciones — el contexto queda conservado', () async {
      final vehiculo = ((await crearVehiculo.ejecutar(marca: 'BMW', modelo: '320i', tipoVehiculo: 'sedan'))
              as CrearVehiculoExitoso)
          .vehiculo;

      final sinObservaciones = await darDeBaja.ejecutar(
        vehiculoId: vehiculo.id,
        fechaBaja: DateTime(2026, 1, 1),
        motivoBaja: MotivoBajaVehiculo.robo,
      );
      expect(sinObservaciones, isA<DarDeBajaVehiculoObservacionesRequeridas>());

      final conObservaciones = await darDeBaja.ejecutar(
        vehiculoId: vehiculo.id,
        fechaBaja: DateTime(2026, 1, 1),
        motivoBaja: MotivoBajaVehiculo.robo,
        observacionesBaja: 'Reporte policial folio 12345, sucedió en la caseta de Toluca',
      );
      expect(conObservaciones, isA<DarDeBajaVehiculoExitoso>());
      final actualizado = (conObservaciones as DarDeBajaVehiculoExitoso).vehiculo;
      expect(actualizado.motivoBaja, 'robo');
      expect(actualizado.observacionesBaja, contains('Reporte policial'));
    });

    test('rechaza dar de baja dos veces', () async {
      final vehiculo = ((await crearVehiculo.ejecutar(marca: 'BMW', modelo: '320i', tipoVehiculo: 'sedan'))
              as CrearVehiculoExitoso)
          .vehiculo;
      await darDeBaja.ejecutar(vehiculoId: vehiculo.id, fechaBaja: DateTime(2026, 1, 1), motivoBaja: MotivoBajaVehiculo.venta);

      final segundoIntento = await darDeBaja.ejecutar(
        vehiculoId: vehiculo.id,
        fechaBaja: DateTime(2026, 1, 2),
        motivoBaja: MotivoBajaVehiculo.venta,
      );
      expect(segundoIntento, isA<DarDeBajaVehiculoYaDeBaja>());
    });

    test('el expediente sigue consultable después de la baja', () async {
      final vehiculo = ((await crearVehiculo.ejecutar(
        marca: 'BMW',
        modelo: '320i',
        tipoVehiculo: 'sedan',
        placas: 'ABC-123',
      )) as CrearVehiculoExitoso)
          .vehiculo;
      await darDeBaja.ejecutar(
        vehiculoId: vehiculo.id,
        fechaBaja: DateTime(2026, 1, 1),
        motivoBaja: MotivoBajaVehiculo.finVidaUtil,
      );

      final consultado = await vehiculoRepo.obtenerPorId(vehiculo.id);
      expect(consultado, isNotNull);
      expect(consultado!.placas, 'ABC-123', reason: 'nunca se borra el expediente');

      final listado = await vehiculoRepo.listar();
      expect(listado.map((v) => v.id), contains(vehiculo.id), reason: 'sigue activo (cicloVidaRegistro), solo cambia estatus');
    });
  });
}
