// Etapa 15 — estado Asignado en los resúmenes de Existencia. Fuente de
// verdad confirmada antes de implementar (sin duplicar contadores):
// para artículos serializados, `ArticuloUnidad.estatus` (ya actualizado
// transaccionalmente por `AsignacionRepositoryImpl` al crear/cerrar una
// Asignacion) — `calcularExistenciaUnidades` ya lo contaba
// correctamente, solo faltaba mostrarlo. Para artículos por cantidad,
// el mismo `MovimientoInventario` ya usado para Total/Disponible/
// Dañado/Perdido: `salidaAsignacion`/`entradaDevolucion`/`salidaDano`/
// `salidaPerdida` (Etapa 7B) — `calcularExistencia` también ya lo
// calculaba. Ambas fuentes ya eran correctas; el trabajo real fue
// exponer `existencia.asignado` en el expediente y el listado
// (ninguna fórmula nueva, nunca `Total - Disponible`).

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/inventario/data/repositories/articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/asignacion_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/categoria_articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/inventario_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/tables/asignacion_table.dart' show MotivoCierreAsignacion;
import 'package:riseg_one/features/inventario/domain/usecases/cerrar_asignacion_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_asignacion_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_categoria_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/registrar_entrada_unidad_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/registrar_entrada_usecase.dart';
import 'package:riseg_one/features/inventario/presentation/articulos/articulos_state.dart';

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

  Future<EmpleadoData> crearEmpleado(int numero) {
    return db.into(db.empleado).insertReturning(
          EmpleadoCompanion.insert(
            numeroEmpleado: numero,
            nombres: 'Juan',
            apellidoPaterno: 'Pérez',
            sexo: 'masculino',
            fechaNacimiento: DateTime(1990, 1, 1),
            curp: 'PEXJ900101HDFXXX0$numero',
            rfc: 'PEXJ900101AB$numero',
            nss: '1234567890$numero',
            estadoCivil: 'soltero',
            fechaIngreso: DateTime(2026, 1, 1),
            aniosExperienciaSeguridad: 3,
          ),
        );
  }

  group('Artículo serializado (SMARTPHONE) — fuente: ArticuloUnidad.estatus', () {
    test('5 unidades: 3 disponibles + 2 asignadas — Total=5, Disponible=3, Asignado=2', () async {
      final categoriaRepo = CategoriaArticuloRepositoryImpl(db);
      final categoria = (await CrearCategoriaArticuloUseCase(categoriaRepo).ejecutar(nombre: 'Teléfonos') as CrearCategoriaArticuloExitoso)
          .categoria;
      final articulo = ((await CrearArticuloUseCase(articuloRepo, categoriaRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db))).ejecutar(
        categoriaId: categoria.id,
        nombre: 'SMARTPHONE',
        manejaVariante: false,
        manejaSerie: true,
      )) as CrearArticuloExitoso)
          .articulo;

      final registrarEntradaUnidad = RegistrarEntradaUnidadUseCase(inventarioRepo, articuloRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db)));
      final unidades = <ArticuloUnidadData>[];
      for (var i = 1; i <= 5; i++) {
        final resultado = await registrarEntradaUnidad.ejecutar(
          articuloId: articulo.id,
          numeroSerie: 'SN-A00$i',
          fecha: DateTime(2026, 8, 13),
        );
        unidades.add((resultado as RegistrarEntradaUnidadExitoso).unidad);
      }

      final empleado1 = await crearEmpleado(1);
      final empleado2 = await crearEmpleado(2);
      await crearAsignacion.ejecutar(
        articuloId: articulo.id,
        unidadId: unidades[0].id,
        cantidad: 1,
        empleadoId: empleado1.id,
        fechaEntrega: DateTime(2026, 8, 13),
      );
      await crearAsignacion.ejecutar(
        articuloId: articulo.id,
        unidadId: unidades[1].id,
        cantidad: 1,
        empleadoId: empleado2.id,
        fechaEntrega: DateTime(2026, 8, 13),
      );

      final existencia = await inventarioRepo.calcularExistenciaUnidades(articulo.id);
      expect(existencia.total, 5);
      expect(existencia.disponible, 3);
      expect(existencia.asignado, 2);
      expect(existencia.danado, 0);
      expect(existencia.perdido, 0);
      // La invariante explícita del pedido: Total = suma de todos los
      // estados que representan existencia física, incluidos los
      // intermedios (lavandería/reparación/pendiente de desecho). La
      // única cubeta que sale del Total es `baja` — ver el doc comment
      // de `ExistenciaArticulo.total`.
      expect(
        existencia.total,
        existencia.disponible + existencia.asignado + existencia.danado + existencia.perdido + existencia.enProceso,
      );
    });

    test('asignar una unidad más: Disponible 3→2 y Asignado 2→3', () async {
      final categoriaRepo = CategoriaArticuloRepositoryImpl(db);
      final categoria = (await CrearCategoriaArticuloUseCase(categoriaRepo).ejecutar(nombre: 'Teléfonos') as CrearCategoriaArticuloExitoso)
          .categoria;
      final articulo = ((await CrearArticuloUseCase(articuloRepo, categoriaRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db))).ejecutar(
        categoriaId: categoria.id,
        nombre: 'SMARTPHONE',
        manejaVariante: false,
        manejaSerie: true,
      )) as CrearArticuloExitoso)
          .articulo;

      final registrarEntradaUnidad = RegistrarEntradaUnidadUseCase(inventarioRepo, articuloRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db)));
      final unidades = <ArticuloUnidadData>[];
      for (var i = 1; i <= 5; i++) {
        final resultado = await registrarEntradaUnidad.ejecutar(articuloId: articulo.id, numeroSerie: 'SN-B00$i', fecha: DateTime(2026, 8, 13));
        unidades.add((resultado as RegistrarEntradaUnidadExitoso).unidad);
      }
      final empleado1 = await crearEmpleado(1);
      final empleado2 = await crearEmpleado(2);
      await crearAsignacion.ejecutar(articuloId: articulo.id, unidadId: unidades[0].id, cantidad: 1, empleadoId: empleado1.id, fechaEntrega: DateTime(2026, 8, 13));
      await crearAsignacion.ejecutar(articuloId: articulo.id, unidadId: unidades[1].id, cantidad: 1, empleadoId: empleado2.id, fechaEntrega: DateTime(2026, 8, 13));

      var existencia = await inventarioRepo.calcularExistenciaUnidades(articulo.id);
      expect(existencia.disponible, 3);
      expect(existencia.asignado, 2);

      final empleado3 = await crearEmpleado(3);
      await crearAsignacion.ejecutar(articuloId: articulo.id, unidadId: unidades[2].id, cantidad: 1, empleadoId: empleado3.id, fechaEntrega: DateTime(2026, 8, 13));

      existencia = await inventarioRepo.calcularExistenciaUnidades(articulo.id);
      expect(existencia.disponible, 2, reason: '3 → 2');
      expect(existencia.asignado, 3, reason: '2 → 3');
      expect(existencia.total, 5, reason: 'asignar nunca cambia el Total');
    });

    test('devolver una unidad: Disponible 2→3 y Asignado 3→2', () async {
      final categoriaRepo = CategoriaArticuloRepositoryImpl(db);
      final categoria = (await CrearCategoriaArticuloUseCase(categoriaRepo).ejecutar(nombre: 'Teléfonos') as CrearCategoriaArticuloExitoso)
          .categoria;
      final articulo = ((await CrearArticuloUseCase(articuloRepo, categoriaRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db))).ejecutar(
        categoriaId: categoria.id,
        nombre: 'SMARTPHONE',
        manejaVariante: false,
        manejaSerie: true,
      )) as CrearArticuloExitoso)
          .articulo;

      final registrarEntradaUnidad = RegistrarEntradaUnidadUseCase(inventarioRepo, articuloRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db)));
      final unidades = <ArticuloUnidadData>[];
      for (var i = 1; i <= 5; i++) {
        final resultado = await registrarEntradaUnidad.ejecutar(articuloId: articulo.id, numeroSerie: 'SN-C00$i', fecha: DateTime(2026, 8, 13));
        unidades.add((resultado as RegistrarEntradaUnidadExitoso).unidad);
      }
      final empleado1 = await crearEmpleado(1);
      final empleado2 = await crearEmpleado(2);
      final empleado3 = await crearEmpleado(3);
      final a1 = ((await crearAsignacion.ejecutar(articuloId: articulo.id, unidadId: unidades[0].id, cantidad: 1, empleadoId: empleado1.id, fechaEntrega: DateTime(2026, 8, 13))) as CrearAsignacionExitoso).asignacion;
      await crearAsignacion.ejecutar(articuloId: articulo.id, unidadId: unidades[1].id, cantidad: 1, empleadoId: empleado2.id, fechaEntrega: DateTime(2026, 8, 13));
      await crearAsignacion.ejecutar(articuloId: articulo.id, unidadId: unidades[2].id, cantidad: 1, empleadoId: empleado3.id, fechaEntrega: DateTime(2026, 8, 13));

      var existencia = await inventarioRepo.calcularExistenciaUnidades(articulo.id);
      expect(existencia.disponible, 2);
      expect(existencia.asignado, 3);

      final cierre = await cerrarAsignacion.ejecutar(
        asignacionId: a1.id,
        motivo: MotivoCierreAsignacion.desgaste,
        fechaCierre: DateTime(2026, 8, 14),
      );
      expect(cierre, isA<CerrarAsignacionExitoso>());

      existencia = await inventarioRepo.calcularExistenciaUnidades(articulo.id);
      expect(existencia.disponible, 3, reason: '2 → 3');
      expect(existencia.asignado, 2, reason: '3 → 2');
      expect(existencia.total, 5, reason: 'devolver nunca cambia el Total');
    });
  });

  group('Artículo por cantidad (uniformes) — fuente: MovimientoInventario (salidaAsignacion/entradaDevolucion)', () {
    test('registrar entrada y asignar cantidad: Disponible y Asignado se derivan del mismo ledger, nunca Total-Disponible', () async {
      final categoriaRepo = CategoriaArticuloRepositoryImpl(db);
      final categoria = (await CrearCategoriaArticuloUseCase(categoriaRepo).ejecutar(nombre: 'Uniformes') as CrearCategoriaArticuloExitoso)
          .categoria;
      final articulo = ((await CrearArticuloUseCase(articuloRepo, categoriaRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db))).ejecutar(
        categoriaId: categoria.id,
        nombre: 'GUANTES',
        manejaVariante: false,
        manejaSerie: false,
      )) as CrearArticuloExitoso)
          .articulo;

      await RegistrarEntradaUseCase(inventarioRepo, articuloRepo).ejecutar(articuloId: articulo.id, cantidad: 10, fecha: DateTime(2026, 8, 13));
      final empleado = await crearEmpleado(1);
      final asignacion = ((await crearAsignacion.ejecutar(
        articuloId: articulo.id,
        cantidad: 3,
        empleadoId: empleado.id,
        fechaEntrega: DateTime(2026, 8, 13),
      )) as CrearAsignacionExitoso)
          .asignacion;

      var existencia = await inventarioRepo.calcularExistencia(articuloId: articulo.id);
      expect(existencia.total, 10);
      expect(existencia.disponible, 7);
      expect(existencia.asignado, 3);
      expect(
        existencia.total,
        existencia.disponible + existencia.asignado + existencia.danado + existencia.perdido + existencia.enProceso,
      );

      final cierre = await cerrarAsignacion.ejecutar(
        asignacionId: asignacion.id,
        motivo: MotivoCierreAsignacion.desgaste,
        fechaCierre: DateTime(2026, 8, 14),
      );
      expect(cierre, isA<CerrarAsignacionExitoso>());

      existencia = await inventarioRepo.calcularExistencia(articuloId: articulo.id);
      expect(existencia.disponible, 10, reason: 'la devolución regresa toda la cantidad a Disponible');
      expect(existencia.asignado, 0);
    });
  });

  group('El listado general y el expediente dan exactamente los mismos valores', () {
    test('ArticuloResumen.existencia (listado) coincide con calcularExistenciaUnidades (expediente) para un serializado', () async {
      final categoriaRepo = CategoriaArticuloRepositoryImpl(db);
      final categoria = (await CrearCategoriaArticuloUseCase(categoriaRepo).ejecutar(nombre: 'Teléfonos') as CrearCategoriaArticuloExitoso)
          .categoria;
      final articulo = ((await CrearArticuloUseCase(articuloRepo, categoriaRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db))).ejecutar(
        categoriaId: categoria.id,
        nombre: 'SMARTPHONE',
        manejaVariante: false,
        manejaSerie: true,
      )) as CrearArticuloExitoso)
          .articulo;

      final registrarEntradaUnidad = RegistrarEntradaUnidadUseCase(inventarioRepo, articuloRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db)));
      ArticuloUnidadData? unidad;
      for (var i = 1; i <= 2; i++) {
        final resultado = await registrarEntradaUnidad.ejecutar(articuloId: articulo.id, numeroSerie: 'SN-D00$i', fecha: DateTime(2026, 8, 13));
        unidad = (resultado as RegistrarEntradaUnidadExitoso).unidad;
      }
      final empleado = await crearEmpleado(1);
      await crearAsignacion.ejecutar(articuloId: articulo.id, unidadId: unidad!.id, cantidad: 1, empleadoId: empleado.id, fechaEntrega: DateTime(2026, 8, 13));

      // Exactamente el cálculo que hace `ArticulosController._cargar()`
      // para construir `ArticuloResumen` (listado principal).
      final existenciaListado = await inventarioRepo.calcularExistenciaUnidades(articulo.id);
      final resumen = ArticuloResumen(articulo: articulo, categoriaNombre: categoria.nombre, existencia: existenciaListado);

      // Exactamente el cálculo que hace el expediente.
      final existenciaExpediente = await inventarioRepo.calcularExistenciaUnidades(articulo.id);

      expect(resumen.existencia.total, existenciaExpediente.total);
      expect(resumen.existencia.disponible, existenciaExpediente.disponible);
      expect(resumen.existencia.asignado, existenciaExpediente.asignado);
      expect(resumen.existencia.danado, existenciaExpediente.danado);
      expect(resumen.existencia.perdido, existenciaExpediente.perdido);
      expect(resumen.existencia.asignado, 1);
    });
  });
}
