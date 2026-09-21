// Prueba funcional Inventario + Personal (Marlon, puntos 1 y 3): la
// máquina de estados de una asignación — disponible → asignado →
// devuelto/dañado/perdido — debe mantener la igualdad
// Total = Disponible + Asignado + Dañado + Perdido en todo momento,
// nunca stock negativo, y nunca dos estados simultáneos para la misma
// unidad/cantidad. Verificado explícitamente para AMBOS modelos
// (artículo por cantidad y artículo serializado) para confirmar que
// comparten la misma semántica — ya lo garantiza el dominio
// (`calcularExistencia`/`calcularExistenciaUnidades`, ver el doc
// comment de `ExistenciaArticulo`), esta prueba lo deja fijo como
// regresión.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/inventario/data/repositories/articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/asignacion_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/categoria_articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/inventario_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/tables/articulo_unidad_table.dart' show EstatusArticuloUnidad;
import 'package:riseg_one/features/inventario/data/tables/asignacion_table.dart' show MotivoCierreAsignacion;
import 'package:riseg_one/features/inventario/domain/usecases/cerrar_asignacion_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_asignacion_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_categoria_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/existencia_articulo.dart';
import 'package:riseg_one/features/inventario/domain/usecases/registrar_baja_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/registrar_entrada_unidad_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/registrar_entrada_usecase.dart';

void main() {
  late AppDatabase db;
  late ArticuloRepositoryImpl articuloRepo;
  late InventarioRepositoryImpl inventarioRepo;
  late AsignacionRepositoryImpl asignacionRepo;
  late CrearAsignacionUseCase crearAsignacion;
  late CerrarAsignacionUseCase cerrarAsignacion;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    articuloRepo = ArticuloRepositoryImpl(db);
    inventarioRepo = InventarioRepositoryImpl(db);
    asignacionRepo = AsignacionRepositoryImpl(db);
    crearAsignacion = CrearAsignacionUseCase(asignacionRepo, articuloRepo, inventarioRepo);
    cerrarAsignacion = CerrarAsignacionUseCase(asignacionRepo);
  });

  tearDown(() => db.close());

  Future<ArticuloData> crearArticulo({required String nombre, required bool manejaSerie}) async {
    final categoria = (await CrearCategoriaArticuloUseCase(CategoriaArticuloRepositoryImpl(db)).ejecutar(nombre: '$nombre-cat')
            as CrearCategoriaArticuloExitoso)
        .categoria;
    final resultado = await CrearArticuloUseCase(articuloRepo, CategoriaArticuloRepositoryImpl(db), GenerarCodigoUseCase(CodigoSecuenciaService(db)))
        .ejecutar(categoriaId: categoria.id, nombre: nombre, manejaVariante: false, manejaSerie: manejaSerie);
    return (resultado as CrearArticuloExitoso).articulo;
  }

  Future<String> crearEmpleado() async {
    final empleado = await db.into(db.empleado).insertReturning(
          EmpleadoCompanion.insert(
            numeroEmpleado: 1,
            nombres: 'Juan Manuel',
            apellidoPaterno: 'Zintzun',
            sexo: 'masculino',
            fechaNacimiento: DateTime(1990, 1, 1),
            curp: 'ZILJ900101HDFXXX01',
            rfc: 'ZILJ900101AB1',
            nss: '12345678901',
            estadoCivil: 'soltero',
            fechaIngreso: DateTime(2026, 1, 1),
            aniosExperienciaSeguridad: 3,
          ),
        );
    return empleado.id;
  }

  void esperarInvariante(ExistenciaArticulo e, {required int total}) {
    expect(e.disponible, greaterThanOrEqualTo(0), reason: 'disponible nunca negativo');
    expect(e.total, total, reason: 'Total = Disponible + Asignado + Dañado + Perdido siempre se conserva');
  }

  group('artículo POR CANTIDAD', () {
    late ArticuloData articulo;
    late String empleadoId;

    setUp(() async {
      articulo = await crearArticulo(nombre: 'PANTALON NEGRO COMANDO', manejaSerie: false);
      empleadoId = await crearEmpleado();
      await RegistrarEntradaUseCase(inventarioRepo, articuloRepo).ejecutar(articuloId: articulo.id, cantidad: 1, fecha: DateTime(2026, 8, 20));
    });

    test('estado inicial: Total 1 / Disponible 1 / Asignado 0', () async {
      final e = await inventarioRepo.calcularExistencia(articuloId: articulo.id);
      expect(e.disponible, 1);
      expect(e.asignado, 0);
      esperarInvariante(e, total: 1);
    });

    test('asignar: Disponible baja y Asignado sube inmediatamente a Total 1 / Disponible 0 / Asignado 1', () async {
      final resultado = await crearAsignacion.ejecutar(
        articuloId: articulo.id,
        cantidad: 1,
        empleadoId: empleadoId,
        fechaEntrega: DateTime(2026, 8, 21),
      );
      expect(resultado, isA<CrearAsignacionExitoso>());

      final e = await inventarioRepo.calcularExistencia(articuloId: articulo.id);
      expect(e.disponible, 0);
      expect(e.asignado, 1);
      esperarInvariante(e, total: 1);
    });

    test('devolución: Asignado baja y Disponible sube de vuelta a Total 1 / Disponible 1 / Asignado 0', () async {
      final creada = ((await crearAsignacion.ejecutar(
        articuloId: articulo.id,
        cantidad: 1,
        empleadoId: empleadoId,
        fechaEntrega: DateTime(2026, 8, 21),
      )) as CrearAsignacionExitoso)
          .asignacion;

      final resultado = await cerrarAsignacion.ejecutar(
        asignacionId: creada.id,
        motivo: MotivoCierreAsignacion.desgaste,
        fechaCierre: DateTime(2026, 8, 22),
      );
      expect(resultado, isA<CerrarAsignacionExitoso>());

      final e = await inventarioRepo.calcularExistencia(articuloId: articulo.id);
      expect(e.disponible, 1);
      expect(e.asignado, 0);
      esperarInvariante(e, total: 1);
    });

    test('daño: deja de estar Asignado y pasa a Dañado, sin duplicar ni sumar de más', () async {
      final creada = ((await crearAsignacion.ejecutar(
        articuloId: articulo.id,
        cantidad: 1,
        empleadoId: empleadoId,
        fechaEntrega: DateTime(2026, 8, 21),
      )) as CrearAsignacionExitoso)
          .asignacion;

      final resultado = await cerrarAsignacion.ejecutar(
        asignacionId: creada.id,
        motivo: MotivoCierreAsignacion.dano,
        fechaCierre: DateTime(2026, 8, 22),
        atribuibleAlEmpleado: false,
      );
      expect(resultado, isA<CerrarAsignacionExitoso>());

      final e = await inventarioRepo.calcularExistencia(articuloId: articulo.id);
      expect(e.disponible, 0, reason: 'un artículo dañado nunca vuelve a estar disponible');
      expect(e.asignado, 0, reason: 'ya no debe seguir contando como asignado');
      expect(e.danado, 1);
      expect(e.perdido, 0);
      esperarInvariante(e, total: 1);
    });

    test('pérdida: deja de estar Asignado y pasa a Perdido, sin duplicar ni sumar de más', () async {
      final creada = ((await crearAsignacion.ejecutar(
        articuloId: articulo.id,
        cantidad: 1,
        empleadoId: empleadoId,
        fechaEntrega: DateTime(2026, 8, 21),
      )) as CrearAsignacionExitoso)
          .asignacion;

      final resultado = await cerrarAsignacion.ejecutar(
        asignacionId: creada.id,
        motivo: MotivoCierreAsignacion.perdida,
        fechaCierre: DateTime(2026, 8, 22),
        atribuibleAlEmpleado: true,
        generaDescuento: true,
        importeDescuento: 20000,
        empleadoResponsableDescuentoId: empleadoId,
      );
      expect(resultado, isA<CerrarAsignacionExitoso>());

      final e = await inventarioRepo.calcularExistencia(articuloId: articulo.id);
      expect(e.disponible, 0);
      expect(e.asignado, 0);
      expect(e.danado, 0);
      expect(e.perdido, 1);
      esperarInvariante(e, total: 1);
    });

    test('ninguna operación genera stock negativo: una baja manual mayor al disponible se rechaza limpio', () async {
      final registrarBaja = RegistrarBajaUseCase(inventarioRepo, articuloRepo);
      final resultado = await registrarBaja.ejecutar(articuloId: articulo.id, cantidad: 5, observaciones: 'Prueba de rechazo por exceso');
      expect(resultado, isA<RegistrarBajaSobrepasaDisponible>());

      final e = await inventarioRepo.calcularExistencia(articuloId: articulo.id);
      expect(e.disponible, 1, reason: 'sin cambios tras el rechazo');
      esperarInvariante(e, total: 1);
    });
  });

  group('artículo SERIALIZADO — misma semántica que por cantidad', () {
    late ArticuloData articulo;
    late ArticuloUnidadData unidad;
    late String empleadoId;

    setUp(() async {
      articulo = await crearArticulo(nombre: 'RADIO PORTATIL', manejaSerie: true);
      empleadoId = await crearEmpleado();
      final resultado = await RegistrarEntradaUnidadUseCase(inventarioRepo, articuloRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db)))
          .ejecutar(articuloId: articulo.id, numeroSerie: 'SN-0001', fecha: DateTime(2026, 8, 20));
      unidad = (resultado as RegistrarEntradaUnidadExitoso).unidad;
    });

    test('estado inicial: Total 1 / Disponible 1 / Asignado 0', () async {
      final e = await inventarioRepo.calcularExistenciaUnidades(articulo.id);
      expect(e.disponible, 1);
      expect(e.asignado, 0);
      esperarInvariante(e, total: 1);
    });

    test('asignar: Disponible baja y Asignado sube inmediatamente', () async {
      final resultado = await crearAsignacion.ejecutar(
        articuloId: articulo.id,
        unidadId: unidad.id,
        cantidad: 1,
        empleadoId: empleadoId,
        fechaEntrega: DateTime(2026, 8, 21),
      );
      expect(resultado, isA<CrearAsignacionExitoso>());

      final e = await inventarioRepo.calcularExistenciaUnidades(articulo.id);
      expect(e.disponible, 0);
      expect(e.asignado, 1);
      esperarInvariante(e, total: 1);

      final unidadActualizada = await inventarioRepo.obtenerUnidadPorId(unidad.id);
      expect(unidadActualizada!.estatus, EstatusArticuloUnidad.asignado.name);
    });

    test('devolución: Asignado baja y Disponible sube de vuelta', () async {
      final creada = ((await crearAsignacion.ejecutar(
        articuloId: articulo.id,
        unidadId: unidad.id,
        cantidad: 1,
        empleadoId: empleadoId,
        fechaEntrega: DateTime(2026, 8, 21),
      )) as CrearAsignacionExitoso)
          .asignacion;

      await cerrarAsignacion.ejecutar(asignacionId: creada.id, motivo: MotivoCierreAsignacion.desgaste, fechaCierre: DateTime(2026, 8, 22));

      final e = await inventarioRepo.calcularExistenciaUnidades(articulo.id);
      expect(e.disponible, 1);
      expect(e.asignado, 0);
      esperarInvariante(e, total: 1);

      final unidadActualizada = await inventarioRepo.obtenerUnidadPorId(unidad.id);
      expect(unidadActualizada!.estatus, EstatusArticuloUnidad.disponible.name);
    });

    test('daño: la unidad pasa a Dañado, nunca simultáneamente disponible/asignada', () async {
      final creada = ((await crearAsignacion.ejecutar(
        articuloId: articulo.id,
        unidadId: unidad.id,
        cantidad: 1,
        empleadoId: empleadoId,
        fechaEntrega: DateTime(2026, 8, 21),
      )) as CrearAsignacionExitoso)
          .asignacion;

      await cerrarAsignacion.ejecutar(
        asignacionId: creada.id,
        motivo: MotivoCierreAsignacion.dano,
        fechaCierre: DateTime(2026, 8, 22),
        atribuibleAlEmpleado: false,
      );

      final e = await inventarioRepo.calcularExistenciaUnidades(articulo.id);
      expect(e.disponible, 0);
      expect(e.asignado, 0);
      expect(e.danado, 1);
      esperarInvariante(e, total: 1);

      // La unidad tiene EXACTAMENTE un estatus — nunca puede aparecer
      // simultáneamente en dos buckets, a diferencia de lo fungible
      // (aritmético): aquí es estructural, una sola columna.
      final unidadActualizada = await inventarioRepo.obtenerUnidadPorId(unidad.id);
      expect(unidadActualizada!.estatus, EstatusArticuloUnidad.danado.name);
    });

    test('pérdida: la unidad pasa a Perdido, nunca simultáneamente disponible/asignada', () async {
      final creada = ((await crearAsignacion.ejecutar(
        articuloId: articulo.id,
        unidadId: unidad.id,
        cantidad: 1,
        empleadoId: empleadoId,
        fechaEntrega: DateTime(2026, 8, 21),
      )) as CrearAsignacionExitoso)
          .asignacion;

      await cerrarAsignacion.ejecutar(
        asignacionId: creada.id,
        motivo: MotivoCierreAsignacion.perdida,
        fechaCierre: DateTime(2026, 8, 22),
        atribuibleAlEmpleado: true,
        generaDescuento: true,
        importeDescuento: 50000,
        empleadoResponsableDescuentoId: empleadoId,
      );

      final e = await inventarioRepo.calcularExistenciaUnidades(articulo.id);
      expect(e.disponible, 0);
      expect(e.asignado, 0);
      expect(e.perdido, 1);
      esperarInvariante(e, total: 1);

      final unidadActualizada = await inventarioRepo.obtenerUnidadPorId(unidad.id);
      expect(unidadActualizada!.estatus, EstatusArticuloUnidad.perdido.name);
    });
  });
}
