// Muestra representativa (no exhaustiva) de que `actorUsuarioId`
// llega realmente hasta la fila de evento correspondiente, para 3
// dominios ya threaded (Etapa 11D): Compras (`CompraEvento`), Finanzas/
// Ingreso (`IngresoEvento`) y Vehículos/Kilometraje (el propio ledger
// `VehiculoKilometraje` es su evento, sin tabla `XxxEvento` aparte —
// ver el doc comment de esa tabla). El resto de dominios ya threaded
// tiene cobertura indirecta extensa en el resto de la suite; esto solo
// confirma el mecanismo, no repite cada dominio.

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/compras/data/repositories/compra_repository_impl.dart';
import 'package:riseg_one/features/compras/domain/repositories/compra_repository.dart';
import 'package:riseg_one/features/compras/domain/usecases/registrar_compra_usecase.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/ingreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show FormaPago;
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_ingreso_manual_usecase.dart';
import 'package:riseg_one/features/inventario/data/repositories/articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/inventario_repository_impl.dart';
import 'package:riseg_one/features/vehiculos/data/repositories/asignacion_vehiculo_repository_impl.dart';
import 'package:riseg_one/features/vehiculos/data/repositories/vehiculo_kilometraje_repository_impl.dart';
import 'package:riseg_one/features/vehiculos/data/repositories/vehiculo_repository_impl.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/crear_vehiculo_usecase.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/registrar_kilometraje_vehiculo_usecase.dart';

void main() {
  late AppDatabase db;
  const actorId = 'usuario-prueba';

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(id: const Value(actorId), nombre: 'Usuario de prueba', nombreUsuario: 'usuario-prueba', passwordHash: 'x'),
        );
  });

  tearDown(() => db.close());

  group('Compras — CompraEvento', () {
    late RegistrarCompraUseCase registrarCompra;

    setUp(() {
      final articuloRepo = ArticuloRepositoryImpl(db);
      final inventarioRepo = InventarioRepositoryImpl(db);
      final egresoRepo = EgresoRepositoryImpl(db);
      final deudaRepo = DeudaRepositoryImpl(db, egresoRepo);
      final compraRepo = CompraRepositoryImpl(db, inventarioRepo, articuloRepo, egresoRepo, deudaRepo);
      registrarCompra = RegistrarCompraUseCase(compraRepo, articuloRepo, inventarioRepo, deudaRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db)));
    });

    Future<RegistrarCompraResultado> registrarCompraDePrueba({String? actorUsuarioId}) {
      return registrarCompra.ejecutar(
        fecha: DateTime(2026, 1, 1),
        formaPago: FormaPago.efectivo.name,
        partidas: const [
          PartidaCompraInput(destino: 'gastoDirecto', concepto: 'Gasolina', cantidad: 1, costoUnitario: 10000),
        ],
        actorUsuarioId: actorUsuarioId,
      );
    }

    test('actorUsuarioId real llega hasta CompraEvento.actorUsuarioId', () async {
      final resultado = await registrarCompraDePrueba(actorUsuarioId: actorId);
      final compra = (resultado as RegistrarCompraExitosa).compra;

      final evento = await (db.select(db.compraEvento)..where((t) => t.compraId.equals(compra.id))).getSingle();
      expect(evento.actorUsuarioId, actorId);
    });

    test('sin sesión (actorUsuarioId null) el evento queda con actorUsuarioId null, sin romper nada', () async {
      final resultado = await registrarCompraDePrueba();
      final compra = (resultado as RegistrarCompraExitosa).compra;

      final evento = await (db.select(db.compraEvento)..where((t) => t.compraId.equals(compra.id))).getSingle();
      expect(evento.actorUsuarioId, isNull);
    });
  });

  group('Finanzas/Ingreso — IngresoEvento', () {
    late RegistrarIngresoManualUseCase registrarIngreso;

    setUp(() {
      registrarIngreso = RegistrarIngresoManualUseCase(IngresoRepositoryImpl(db), GenerarCodigoUseCase(CodigoSecuenciaService(db)));
    });

    Future<RegistrarIngresoManualResultado> registrarIngresoDePrueba({String? actorUsuarioId}) {
      return registrarIngreso.ejecutar(
        monto: 50000,
        fecha: DateTime(2026, 1, 1),
        formaPago: 'efectivo',
        concepto: 'Ingreso de prueba',
        actorUsuarioId: actorUsuarioId,
      );
    }

    test('actorUsuarioId real llega hasta IngresoEvento.actorUsuarioId', () async {
      final resultado = await registrarIngresoDePrueba(actorUsuarioId: actorId);
      final ingreso = (resultado as RegistrarIngresoManualExitoso).ingreso;

      final evento = await (db.select(db.ingresoEvento)..where((t) => t.ingresoId.equals(ingreso.id))).getSingle();
      expect(evento.actorUsuarioId, actorId);
    });

    test('sin sesión (actorUsuarioId null) el evento queda con actorUsuarioId null, sin romper nada', () async {
      final resultado = await registrarIngresoDePrueba();
      final ingreso = (resultado as RegistrarIngresoManualExitoso).ingreso;

      final evento = await (db.select(db.ingresoEvento)..where((t) => t.ingresoId.equals(ingreso.id))).getSingle();
      expect(evento.actorUsuarioId, isNull);
    });
  });

  group('Vehículos/Kilometraje — el propio ledger es el evento', () {
    late VehiculoRepositoryImpl vehiculoRepo;
    late RegistrarKilometrajeVehiculoUseCase registrarKilometraje;

    setUp(() {
      final asignacionRepo = AsignacionVehiculoRepositoryImpl(db);
      vehiculoRepo = VehiculoRepositoryImpl(db, asignacionRepo);
      final kilometrajeRepo = VehiculoKilometrajeRepositoryImpl(db);
      registrarKilometraje = RegistrarKilometrajeVehiculoUseCase(kilometrajeRepo, vehiculoRepo);
    });

    Future<VehiculoData> crearVehiculoDePrueba() async {
      final crear = CrearVehiculoUseCase(vehiculoRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db)));
      final r = await crear.ejecutar(marca: 'BMW', modelo: '320i', tipoVehiculo: 'sedan');
      return (r as CrearVehiculoExitoso).vehiculo;
    }

    test('actorUsuarioId real llega hasta VehiculoKilometraje.actorUsuarioId', () async {
      final vehiculo = await crearVehiculoDePrueba();
      final resultado = await registrarKilometraje.ejecutar(
        vehiculoId: vehiculo.id,
        fecha: DateTime(2026, 1, 5),
        kilometraje: 1000,
        origen: 'lecturaManual',
        actorUsuarioId: actorId,
      );
      final lectura = (resultado as RegistrarKilometrajeVehiculoExitoso).lectura;
      expect(lectura.actorUsuarioId, actorId);
    });

    test('sin sesión (actorUsuarioId null) la lectura queda con actorUsuarioId null, sin romper nada', () async {
      final vehiculo = await crearVehiculoDePrueba();
      final resultado = await registrarKilometraje.ejecutar(
        vehiculoId: vehiculo.id,
        fecha: DateTime(2026, 1, 5),
        kilometraje: 1000,
        origen: 'lecturaManual',
      );
      final lectura = (resultado as RegistrarKilometrajeVehiculoExitoso).lectura;
      expect(lectura.actorUsuarioId, isNull);
    });
  });
}
