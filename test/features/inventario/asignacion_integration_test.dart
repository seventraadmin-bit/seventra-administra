import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/inventario/data/repositories/articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/asignacion_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/categoria_articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/inventario_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/tables/asignacion_table.dart';
import 'package:riseg_one/features/inventario/domain/usecases/cancelar_descuento_inventario_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/cerrar_asignacion_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_asignacion_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_categoria_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/registrar_entrada_unidad_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/registrar_entrada_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/reemplazar_asignacion_usecase.dart';

void main() {
  late AppDatabase db;
  late ArticuloRepositoryImpl articuloRepo;
  late InventarioRepositoryImpl inventarioRepo;
  late AsignacionRepositoryImpl asignacionRepo;
  late CrearCategoriaArticuloUseCase crearCategoria;
  late CrearArticuloUseCase crearArticulo;
  late RegistrarEntradaUseCase registrarEntrada;
  late RegistrarEntradaUnidadUseCase registrarEntradaUnidad;
  late CrearAsignacionUseCase crearAsignacion;
  late CerrarAsignacionUseCase cerrarAsignacion;
  late ReemplazarAsignacionUseCase reemplazarAsignacion;
  late CancelarDescuentoInventarioUseCase cancelarDescuento;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    final categoriaRepo = CategoriaArticuloRepositoryImpl(db);
    articuloRepo = ArticuloRepositoryImpl(db);
    inventarioRepo = InventarioRepositoryImpl(db);
    asignacionRepo = AsignacionRepositoryImpl(db);
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));

    crearCategoria = CrearCategoriaArticuloUseCase(categoriaRepo);
    crearArticulo = CrearArticuloUseCase(articuloRepo, categoriaRepo, generarCodigo);
    registrarEntrada = RegistrarEntradaUseCase(inventarioRepo, articuloRepo);
    registrarEntradaUnidad = RegistrarEntradaUnidadUseCase(inventarioRepo, articuloRepo, generarCodigo);
    crearAsignacion = CrearAsignacionUseCase(asignacionRepo, articuloRepo, inventarioRepo);
    cerrarAsignacion = CerrarAsignacionUseCase(asignacionRepo);
    reemplazarAsignacion = ReemplazarAsignacionUseCase(asignacionRepo, articuloRepo, inventarioRepo);
    cancelarDescuento = CancelarDescuentoInventarioUseCase(asignacionRepo);
  });

  tearDown(() => db.close());

  Future<ArticuloData> crearArticuloDePrueba({
    String nombre = 'Camisa RISEG',
    bool manejaVariante = false,
    bool manejaSerie = false,
  }) async {
    final categoria = (await crearCategoria.ejecutar(nombre: '$nombre-categoria') as CrearCategoriaArticuloExitoso)
        .categoria;
    final resultado = await crearArticulo.ejecutar(
      categoriaId: categoria.id,
      nombre: nombre,
      manejaVariante: manejaVariante,
      manejaSerie: manejaSerie,
    );
    return (resultado as CrearArticuloExitoso).articulo;
  }

  Future<EmpleadoData> crearEmpleadoDePrueba({int numeroEmpleado = 1}) {
    return db.into(db.empleado).insertReturning(
          EmpleadoCompanion.insert(
            numeroEmpleado: numeroEmpleado,
            nombres: 'Juan',
            apellidoPaterno: 'Pérez',
            sexo: 'masculino',
            fechaNacimiento: DateTime(1990, 1, 1),
            curp: 'PEXJ900101HDFXXX0$numeroEmpleado',
            rfc: 'PEXJ900101AB$numeroEmpleado',
            nss: '1234567890$numeroEmpleado',
            estadoCivil: 'soltero',
            fechaIngreso: DateTime(2026, 1, 1),
            aniosExperienciaSeguridad: 3,
          ),
        );
  }

  Future<ServicioData> crearServicioDePrueba() async {
    final tipoServicio = await db
        .into(db.tipoServicio)
        .insertReturning(TipoServicioCompanion.insert(id: 'tipo-servicio-prueba', codigo: 'VIGILANCIA_FIJA', nombre: 'Vigilancia fija'));
    final cliente = await db
        .into(db.cliente)
        .insertReturning(ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'Sportium'));
    return db.into(db.servicio).insertReturning(
          ServicioCompanion.insert(
            codigo: 'SER-000001',
            clienteId: cliente.id,
            nombre: 'Vigilancia Sportium Toluca',
            tipoServicioId: tipoServicio.id,
            fechaInicio: DateTime(2026, 1, 1),
          ),
        );
  }

  group('CrearAsignacionUseCase — artículo por cantidad', () {
    test('reduce Disponible y aumenta Asignado', () async {
      final articulo = await crearArticuloDePrueba();
      await registrarEntrada.ejecutar(articuloId: articulo.id, cantidad: 10, fecha: DateTime(2026, 1, 1));
      final empleado = await crearEmpleadoDePrueba();

      final resultado = await crearAsignacion.ejecutar(
        articuloId: articulo.id,
        cantidad: 3,
        empleadoId: empleado.id,
        fechaEntrega: DateTime(2026, 1, 5),
      );
      expect(resultado, isA<CrearAsignacionExitoso>());

      final existencia = await inventarioRepo.calcularExistencia(articuloId: articulo.id);
      expect(existencia.disponible, 7);
      expect(existencia.asignado, 3);
      expect(existencia.total, 10, reason: 'asignar nunca reduce el Total');
    });

    test('rechaza cantidad mayor al Disponible', () async {
      final articulo = await crearArticuloDePrueba();
      await registrarEntrada.ejecutar(articuloId: articulo.id, cantidad: 2, fecha: DateTime(2026, 1, 1));
      final empleado = await crearEmpleadoDePrueba();

      final resultado = await crearAsignacion.ejecutar(
        articuloId: articulo.id,
        cantidad: 5,
        empleadoId: empleado.id,
        fechaEntrega: DateTime(2026, 1, 5),
      );
      expect(resultado, isA<CrearAsignacionSobrepasaDisponible>());
      expect((resultado as CrearAsignacionSobrepasaDisponible).disponible, 2);
    });

    test('rechaza cuando no se indica ni empleado ni servicio, o ambos', () async {
      final articulo = await crearArticuloDePrueba();
      await registrarEntrada.ejecutar(articuloId: articulo.id, cantidad: 5, fecha: DateTime(2026, 1, 1));
      final empleado = await crearEmpleadoDePrueba();
      final servicio = await crearServicioDePrueba();

      final ninguno =
          await crearAsignacion.ejecutar(articuloId: articulo.id, cantidad: 1, fechaEntrega: DateTime(2026, 1, 5));
      expect(ninguno, isA<CrearAsignacionDestinoInvalido>());

      final ambos = await crearAsignacion.ejecutar(
        articuloId: articulo.id,
        cantidad: 1,
        empleadoId: empleado.id,
        servicioId: servicio.id,
        fechaEntrega: DateTime(2026, 1, 5),
      );
      expect(ambos, isA<CrearAsignacionDestinoInvalido>());
    });
  });

  group('CrearAsignacionUseCase — unidad serializada', () {
    test('la unidad pasa a asignado y una segunda asignación se rechaza', () async {
      final articulo = await crearArticuloDePrueba(nombre: 'Radio', manejaSerie: true);
      final unidad = ((await registrarEntradaUnidad.ejecutar(
        articuloId: articulo.id,
        numeroSerie: 'SN-0001',
        fecha: DateTime(2026, 1, 1),
      )) as RegistrarEntradaUnidadExitoso)
          .unidad;
      final empleado = await crearEmpleadoDePrueba();

      final resultado = await crearAsignacion.ejecutar(
        articuloId: articulo.id,
        unidadId: unidad.id,
        cantidad: 1,
        empleadoId: empleado.id,
        fechaEntrega: DateTime(2026, 1, 5),
      );
      expect(resultado, isA<CrearAsignacionExitoso>());

      final unidadActualizada = await inventarioRepo.obtenerUnidadPorId(unidad.id);
      expect(unidadActualizada!.estatus, 'asignado');

      final segundoEmpleado = await crearEmpleadoDePrueba(numeroEmpleado: 2);
      final segundoIntento = await crearAsignacion.ejecutar(
        articuloId: articulo.id,
        unidadId: unidad.id,
        cantidad: 1,
        empleadoId: segundoEmpleado.id,
        fechaEntrega: DateTime(2026, 1, 6),
      );
      expect(segundoIntento, isA<CrearAsignacionUnidadNoDisponible>());
    });
  });

  group('CerrarAsignacionUseCase', () {
    test('devolver regresa Asignado a Disponible y la unidad a disponible', () async {
      final articulo = await crearArticuloDePrueba(nombre: 'Radio', manejaSerie: true);
      final unidad = ((await registrarEntradaUnidad.ejecutar(
        articuloId: articulo.id,
        numeroSerie: 'SN-0002',
        fecha: DateTime(2026, 1, 1),
      )) as RegistrarEntradaUnidadExitoso)
          .unidad;
      final empleado = await crearEmpleadoDePrueba();
      final asignacion = ((await crearAsignacion.ejecutar(
        articuloId: articulo.id,
        unidadId: unidad.id,
        cantidad: 1,
        empleadoId: empleado.id,
        fechaEntrega: DateTime(2026, 1, 5),
      )) as CrearAsignacionExitoso)
          .asignacion;

      final resultado = await cerrarAsignacion.ejecutar(
        asignacionId: asignacion.id,
        motivo: MotivoCierreAsignacion.desgaste,
        fechaCierre: DateTime(2026, 1, 10),
      );
      expect(resultado, isA<CerrarAsignacionExitoso>());
      expect((resultado as CerrarAsignacionExitoso).asignacion.estatus, 'devuelta');

      final unidadActualizada = await inventarioRepo.obtenerUnidadPorId(unidad.id);
      expect(unidadActualizada!.estatus, 'disponible');
    });

    test('dañar con descuento crea un DescuentoInventario pendiente y sube Dañado', () async {
      final articulo = await crearArticuloDePrueba();
      await registrarEntrada.ejecutar(articuloId: articulo.id, cantidad: 5, fecha: DateTime(2026, 1, 1));
      final empleado = await crearEmpleadoDePrueba();
      final asignacion = ((await crearAsignacion.ejecutar(
        articuloId: articulo.id,
        cantidad: 2,
        empleadoId: empleado.id,
        fechaEntrega: DateTime(2026, 1, 5),
      )) as CrearAsignacionExitoso)
          .asignacion;

      final resultado = await cerrarAsignacion.ejecutar(
        asignacionId: asignacion.id,
        motivo: MotivoCierreAsignacion.dano,
        fechaCierre: DateTime(2026, 1, 10),
        observacionesCierre: 'Mal uso',
        atribuibleAlEmpleado: true,
        generaDescuento: true,
        importeDescuento: 150000,
        empleadoResponsableDescuentoId: empleado.id,
      );
      expect(resultado, isA<CerrarAsignacionExitoso>());
      expect((resultado as CerrarAsignacionExitoso).asignacion.estatus, 'danada');

      final existencia = await inventarioRepo.calcularExistencia(articuloId: articulo.id);
      expect(existencia.danado, 2);
      expect(existencia.asignado, 0);

      final descuento = await asignacionRepo.obtenerDescuentoPorAsignacion(asignacion.id);
      expect(descuento, isNotNull);
      expect(descuento!.estatus, 'pendiente');
      expect(descuento.importe, 150000);
    });

    test('perder sin marcar descuento no crea DescuentoInventario', () async {
      final articulo = await crearArticuloDePrueba();
      await registrarEntrada.ejecutar(articuloId: articulo.id, cantidad: 5, fecha: DateTime(2026, 1, 1));
      final empleado = await crearEmpleadoDePrueba();
      final asignacion = ((await crearAsignacion.ejecutar(
        articuloId: articulo.id,
        cantidad: 1,
        empleadoId: empleado.id,
        fechaEntrega: DateTime(2026, 1, 5),
      )) as CrearAsignacionExitoso)
          .asignacion;

      final resultado = await cerrarAsignacion.ejecutar(
        asignacionId: asignacion.id,
        motivo: MotivoCierreAsignacion.perdida,
        fechaCierre: DateTime(2026, 1, 10),
        atribuibleAlEmpleado: false,
      );
      expect(resultado, isA<CerrarAsignacionExitoso>());

      final existencia = await inventarioRepo.calcularExistencia(articuloId: articulo.id);
      expect(existencia.perdido, 1);

      final descuento = await asignacionRepo.obtenerDescuentoPorAsignacion(asignacion.id);
      expect(descuento, isNull);
    });

    test('rechaza cerrar sin observaciones cuando motivo es otro', () async {
      final articulo = await crearArticuloDePrueba();
      await registrarEntrada.ejecutar(articuloId: articulo.id, cantidad: 5, fecha: DateTime(2026, 1, 1));
      final empleado = await crearEmpleadoDePrueba();
      final asignacion = ((await crearAsignacion.ejecutar(
        articuloId: articulo.id,
        cantidad: 1,
        empleadoId: empleado.id,
        fechaEntrega: DateTime(2026, 1, 5),
      )) as CrearAsignacionExitoso)
          .asignacion;

      final resultado = await cerrarAsignacion.ejecutar(
        asignacionId: asignacion.id,
        motivo: MotivoCierreAsignacion.otro,
        fechaCierre: DateTime(2026, 1, 10),
      );
      expect(resultado, isA<CerrarAsignacionObservacionesRequeridas>());
    });

    test('rechaza dano/perdida sin indicar atribuibleAlEmpleado', () async {
      final articulo = await crearArticuloDePrueba();
      await registrarEntrada.ejecutar(articuloId: articulo.id, cantidad: 5, fecha: DateTime(2026, 1, 1));
      final empleado = await crearEmpleadoDePrueba();
      final asignacion = ((await crearAsignacion.ejecutar(
        articuloId: articulo.id,
        cantidad: 1,
        empleadoId: empleado.id,
        fechaEntrega: DateTime(2026, 1, 5),
      )) as CrearAsignacionExitoso)
          .asignacion;

      final resultado = await cerrarAsignacion.ejecutar(
        asignacionId: asignacion.id,
        motivo: MotivoCierreAsignacion.dano,
        fechaCierre: DateTime(2026, 1, 10),
      );
      expect(resultado, isA<CerrarAsignacionAtribucionRequerida>());
    });

    test('rechaza generaDescuento sin importe/responsable', () async {
      final articulo = await crearArticuloDePrueba();
      await registrarEntrada.ejecutar(articuloId: articulo.id, cantidad: 5, fecha: DateTime(2026, 1, 1));
      final empleado = await crearEmpleadoDePrueba();
      final asignacion = ((await crearAsignacion.ejecutar(
        articuloId: articulo.id,
        cantidad: 1,
        empleadoId: empleado.id,
        fechaEntrega: DateTime(2026, 1, 5),
      )) as CrearAsignacionExitoso)
          .asignacion;

      final resultado = await cerrarAsignacion.ejecutar(
        asignacionId: asignacion.id,
        motivo: MotivoCierreAsignacion.dano,
        fechaCierre: DateTime(2026, 1, 10),
        atribuibleAlEmpleado: true,
        generaDescuento: true,
      );
      expect(resultado, isA<CerrarAsignacionDescuentoInvalido>());
    });

    test('rechaza cerrar una Asignacion ya cerrada', () async {
      final articulo = await crearArticuloDePrueba();
      await registrarEntrada.ejecutar(articuloId: articulo.id, cantidad: 5, fecha: DateTime(2026, 1, 1));
      final empleado = await crearEmpleadoDePrueba();
      final asignacion = ((await crearAsignacion.ejecutar(
        articuloId: articulo.id,
        cantidad: 1,
        empleadoId: empleado.id,
        fechaEntrega: DateTime(2026, 1, 5),
      )) as CrearAsignacionExitoso)
          .asignacion;
      await cerrarAsignacion.ejecutar(
        asignacionId: asignacion.id,
        motivo: MotivoCierreAsignacion.desgaste,
        fechaCierre: DateTime(2026, 1, 10),
      );

      final segundoIntento = await cerrarAsignacion.ejecutar(
        asignacionId: asignacion.id,
        motivo: MotivoCierreAsignacion.desgaste,
        fechaCierre: DateTime(2026, 1, 11),
      );
      expect(segundoIntento, isA<CerrarAsignacionYaCerrada>());
    });
  });

  group('ReemplazarAsignacionUseCase', () {
    test('cierra la vieja, crea la nueva, liga asignacionReemplazoId y deja la existencia neta correcta', () async {
      final articulo = await crearArticuloDePrueba(nombre: 'Radio', manejaSerie: true);
      final unidadVieja = ((await registrarEntradaUnidad.ejecutar(
        articuloId: articulo.id,
        numeroSerie: 'SN-VIEJA',
        fecha: DateTime(2026, 1, 1),
      )) as RegistrarEntradaUnidadExitoso)
          .unidad;
      final unidadNueva = ((await registrarEntradaUnidad.ejecutar(
        articuloId: articulo.id,
        numeroSerie: 'SN-NUEVA',
        fecha: DateTime(2026, 1, 1),
      )) as RegistrarEntradaUnidadExitoso)
          .unidad;
      final empleado = await crearEmpleadoDePrueba();
      final asignacionVieja = ((await crearAsignacion.ejecutar(
        articuloId: articulo.id,
        unidadId: unidadVieja.id,
        cantidad: 1,
        empleadoId: empleado.id,
        fechaEntrega: DateTime(2026, 1, 5),
      )) as CrearAsignacionExitoso)
          .asignacion;

      final resultado = await reemplazarAsignacion.ejecutar(
        asignacionId: asignacionVieja.id,
        motivo: MotivoCierreAsignacion.dano,
        fechaCierre: DateTime(2026, 1, 10),
        observacionesCierre: 'Se cayó y dejó de encender',
        atribuibleAlEmpleado: false,
        articuloIdReemplazo: articulo.id,
        unidadIdReemplazo: unidadNueva.id,
        cantidadReemplazo: 1,
      );
      expect(resultado, isA<ReemplazarAsignacionExitoso>());
      final nueva = (resultado as ReemplazarAsignacionExitoso).nuevaAsignacion;
      expect(nueva.empleadoId, empleado.id, reason: 'el reemplazo hereda el destino de la Asignación vieja');

      final viejaActualizada = await asignacionRepo.obtenerPorId(asignacionVieja.id);
      expect(viejaActualizada!.estatus, 'danada');
      expect(viejaActualizada.asignacionReemplazoId, nueva.id);

      final existencia = await inventarioRepo.calcularExistenciaUnidades(articulo.id);
      expect(existencia.danado, 1, reason: 'la unidad vieja quedó dañada');
      expect(existencia.asignado, 1, reason: 'la unidad nueva quedó asignada');
      expect(existencia.total, 2, reason: 'el reemplazo nunca da de baja del Total real');
    });
  });

  group('CancelarDescuentoInventarioUseCase', () {
    test('cancela un descuento pendiente', () async {
      final articulo = await crearArticuloDePrueba();
      await registrarEntrada.ejecutar(articuloId: articulo.id, cantidad: 5, fecha: DateTime(2026, 1, 1));
      final empleado = await crearEmpleadoDePrueba();
      final asignacion = ((await crearAsignacion.ejecutar(
        articuloId: articulo.id,
        cantidad: 1,
        empleadoId: empleado.id,
        fechaEntrega: DateTime(2026, 1, 5),
      )) as CrearAsignacionExitoso)
          .asignacion;
      await cerrarAsignacion.ejecutar(
        asignacionId: asignacion.id,
        motivo: MotivoCierreAsignacion.dano,
        fechaCierre: DateTime(2026, 1, 10),
        atribuibleAlEmpleado: true,
        generaDescuento: true,
        importeDescuento: 50000,
        empleadoResponsableDescuentoId: empleado.id,
      );
      final descuento = (await asignacionRepo.obtenerDescuentoPorAsignacion(asignacion.id))!;

      final resultado = await cancelarDescuento.ejecutar(descuentoId: descuento.id, observaciones: 'Atribución incorrecta');
      expect(resultado, isA<CancelarDescuentoInventarioExitoso>());
      expect((resultado as CancelarDescuentoInventarioExitoso).descuento.estatus, 'cancelado');

      final segundoIntento = await cancelarDescuento.ejecutar(descuentoId: descuento.id);
      expect(segundoIntento, isA<CancelarDescuentoInventarioYaResuelto>());
    });
  });
}
