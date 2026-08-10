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
import 'package:riseg_one/features/inventario/domain/usecases/buscar_inventario_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/cerrar_asignacion_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_asignacion_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_categoria_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_variante_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/registrar_ajuste_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/registrar_entrada_unidad_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/registrar_entrada_usecase.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/empleado_repository_impl.dart';

/// Cubre las consultas nuevas de Etapa 7D — cero tablas de resumen,
/// todas derivadas en vivo de las fuentes ya existentes (Etapas
/// 7A-7C): las versiones "globales" de `AsignacionRepository`, el
/// costo promedio ponderado, y la búsqueda contextual entre Inventario/
/// Personal/Organización.
void main() {
  late AppDatabase db;
  late ArticuloRepositoryImpl articuloRepo;
  late InventarioRepositoryImpl inventarioRepo;
  late AsignacionRepositoryImpl asignacionRepo;
  late CrearCategoriaArticuloUseCase crearCategoria;
  late CrearArticuloUseCase crearArticulo;
  late CrearVarianteArticuloUseCase crearVariante;
  late RegistrarEntradaUseCase registrarEntrada;
  late RegistrarEntradaUnidadUseCase registrarEntradaUnidad;
  late RegistrarAjusteUseCase registrarAjuste;
  late CrearAsignacionUseCase crearAsignacion;
  late CerrarAsignacionUseCase cerrarAsignacion;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    final categoriaRepo = CategoriaArticuloRepositoryImpl(db);
    articuloRepo = ArticuloRepositoryImpl(db);
    inventarioRepo = InventarioRepositoryImpl(db);
    asignacionRepo = AsignacionRepositoryImpl(db);
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));

    crearCategoria = CrearCategoriaArticuloUseCase(categoriaRepo);
    crearArticulo = CrearArticuloUseCase(articuloRepo, categoriaRepo, generarCodigo);
    crearVariante = CrearVarianteArticuloUseCase(articuloRepo);
    registrarEntrada = RegistrarEntradaUseCase(inventarioRepo, articuloRepo);
    registrarEntradaUnidad = RegistrarEntradaUnidadUseCase(inventarioRepo, articuloRepo, generarCodigo);
    registrarAjuste = RegistrarAjusteUseCase(inventarioRepo, articuloRepo);
    crearAsignacion = CrearAsignacionUseCase(asignacionRepo, articuloRepo, inventarioRepo);
    cerrarAsignacion = CerrarAsignacionUseCase(asignacionRepo);
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

  Future<EmpleadoData> crearEmpleadoDePrueba({int numeroEmpleado = 1, String nombres = 'Juan'}) {
    return db.into(db.empleado).insertReturning(
          EmpleadoCompanion.insert(
            numeroEmpleado: numeroEmpleado,
            nombres: nombres,
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

  Future<ServicioData> crearServicioDePrueba({String codigo = 'SER-000001', String nombre = 'Vigilancia Sportium Toluca'}) async {
    final tipoServicio = await db
        .into(db.tipoServicio)
        .insertReturning(TipoServicioCompanion.insert(id: 'tipo-servicio-$codigo', codigo: 'VIGILANCIA_FIJA', nombre: 'Vigilancia fija'));
    final cliente = await db
        .into(db.cliente)
        .insertReturning(ClienteCompanion.insert(codigo: 'CLI-$codigo', nombreComercial: 'Sportium'));
    return db.into(db.servicio).insertReturning(
          ServicioCompanion.insert(
            codigo: codigo,
            clienteId: cliente.id,
            nombre: nombre,
            tipoServicioId: tipoServicio.id,
            fechaInicio: DateTime(2026, 1, 1),
          ),
        );
  }

  group('AsignacionRepository — reportes globales (7D)', () {
    test('listarTodasActivas junta Empleado y Servicio, sin las ya cerradas', () async {
      final articulo = await crearArticuloDePrueba();
      await registrarEntrada.ejecutar(articuloId: articulo.id, cantidad: 10, fecha: DateTime(2026, 1, 1));
      final empleado = await crearEmpleadoDePrueba();
      final servicio = await crearServicioDePrueba();

      final aEmpleado = ((await crearAsignacion.ejecutar(
        articuloId: articulo.id,
        cantidad: 1,
        empleadoId: empleado.id,
        fechaEntrega: DateTime(2026, 1, 5),
      )) as CrearAsignacionExitoso)
          .asignacion;
      final aServicio = ((await crearAsignacion.ejecutar(
        articuloId: articulo.id,
        cantidad: 2,
        servicioId: servicio.id,
        fechaEntrega: DateTime(2026, 1, 6),
      )) as CrearAsignacionExitoso)
          .asignacion;
      final cerrada = ((await crearAsignacion.ejecutar(
        articuloId: articulo.id,
        cantidad: 1,
        empleadoId: empleado.id,
        fechaEntrega: DateTime(2026, 1, 7),
      )) as CrearAsignacionExitoso)
          .asignacion;
      await cerrarAsignacion.ejecutar(
        asignacionId: cerrada.id,
        motivo: MotivoCierreAsignacion.desgaste,
        fechaCierre: DateTime(2026, 1, 10),
      );

      final activas = await asignacionRepo.listarTodasActivas();

      expect(activas.map((a) => a.id).toSet(), {aEmpleado.id, aServicio.id});
    });

    test('listarDanadasPerdidas solo trae esos dos estatus', () async {
      final articulo = await crearArticuloDePrueba();
      await registrarEntrada.ejecutar(articuloId: articulo.id, cantidad: 10, fecha: DateTime(2026, 1, 1));
      final empleado = await crearEmpleadoDePrueba();

      final devuelta = ((await crearAsignacion.ejecutar(
        articuloId: articulo.id,
        cantidad: 1,
        empleadoId: empleado.id,
        fechaEntrega: DateTime(2026, 1, 5),
      )) as CrearAsignacionExitoso)
          .asignacion;
      await cerrarAsignacion.ejecutar(
        asignacionId: devuelta.id,
        motivo: MotivoCierreAsignacion.desgaste,
        fechaCierre: DateTime(2026, 1, 6),
      );

      final danada = ((await crearAsignacion.ejecutar(
        articuloId: articulo.id,
        cantidad: 1,
        empleadoId: empleado.id,
        fechaEntrega: DateTime(2026, 1, 7),
      )) as CrearAsignacionExitoso)
          .asignacion;
      await cerrarAsignacion.ejecutar(
        asignacionId: danada.id,
        motivo: MotivoCierreAsignacion.dano,
        fechaCierre: DateTime(2026, 1, 8),
        atribuibleAlEmpleado: false,
      );

      final perdida = ((await crearAsignacion.ejecutar(
        articuloId: articulo.id,
        cantidad: 1,
        empleadoId: empleado.id,
        fechaEntrega: DateTime(2026, 1, 9),
      )) as CrearAsignacionExitoso)
          .asignacion;
      await cerrarAsignacion.ejecutar(
        asignacionId: perdida.id,
        motivo: MotivoCierreAsignacion.perdida,
        fechaCierre: DateTime(2026, 1, 10),
        atribuibleAlEmpleado: false,
      );

      final resultado = await asignacionRepo.listarDanadasPerdidas();

      expect(resultado.map((a) => a.id).toSet(), {danada.id, perdida.id});
      expect(resultado.map((a) => a.estatus).toSet(), {'danada', 'perdida'});
    });

    test('listarTodosDescuentosPendientes junta varios Empleados y excluye cancelados', () async {
      final articulo = await crearArticuloDePrueba();
      await registrarEntrada.ejecutar(articuloId: articulo.id, cantidad: 10, fecha: DateTime(2026, 1, 1));
      final empleado1 = await crearEmpleadoDePrueba(numeroEmpleado: 1);
      final empleado2 = await crearEmpleadoDePrueba(numeroEmpleado: 2);

      final asignacion1 = ((await crearAsignacion.ejecutar(
        articuloId: articulo.id,
        cantidad: 1,
        empleadoId: empleado1.id,
        fechaEntrega: DateTime(2026, 1, 5),
      )) as CrearAsignacionExitoso)
          .asignacion;
      await cerrarAsignacion.ejecutar(
        asignacionId: asignacion1.id,
        motivo: MotivoCierreAsignacion.dano,
        fechaCierre: DateTime(2026, 1, 6),
        atribuibleAlEmpleado: true,
        generaDescuento: true,
        importeDescuento: 50000,
        empleadoResponsableDescuentoId: empleado1.id,
      );

      final asignacion2 = ((await crearAsignacion.ejecutar(
        articuloId: articulo.id,
        cantidad: 1,
        empleadoId: empleado2.id,
        fechaEntrega: DateTime(2026, 1, 7),
      )) as CrearAsignacionExitoso)
          .asignacion;
      await cerrarAsignacion.ejecutar(
        asignacionId: asignacion2.id,
        motivo: MotivoCierreAsignacion.perdida,
        fechaCierre: DateTime(2026, 1, 8),
        atribuibleAlEmpleado: true,
        generaDescuento: true,
        importeDescuento: 30000,
        empleadoResponsableDescuentoId: empleado2.id,
      );
      final descuento2 = (await asignacionRepo.obtenerDescuentoPorAsignacion(asignacion2.id))!;
      await asignacionRepo.cancelarDescuento(descuentoId: descuento2.id);

      final pendientes = await asignacionRepo.listarTodosDescuentosPendientes();

      expect(pendientes, hasLength(1));
      expect(pendientes.single.empleadoId, empleado1.id);
      expect(pendientes.single.estatus, 'pendiente');
    });
  });

  group('InventarioRepository.calcularCostoPromedio (7D)', () {
    test('pondera por cantidad entre varias entradas', () async {
      final articulo = await crearArticuloDePrueba();
      await registrarEntrada.ejecutar(articuloId: articulo.id, cantidad: 10, costoUnitario: 10000, fecha: DateTime(2026, 1, 1));
      await registrarEntrada.ejecutar(articuloId: articulo.id, cantidad: 5, costoUnitario: 40000, fecha: DateTime(2026, 1, 2));

      final costo = await inventarioRepo.calcularCostoPromedio(articuloId: articulo.id);

      // (10*10000 + 5*40000) / 15 = 20000
      expect(costo, 20000);
    });

    test('ignora entradas sin costoUnitario capturado', () async {
      final articulo = await crearArticuloDePrueba();
      await registrarEntrada.ejecutar(articuloId: articulo.id, cantidad: 10, costoUnitario: 10000, fecha: DateTime(2026, 1, 1));
      await registrarEntrada.ejecutar(articuloId: articulo.id, cantidad: 100, fecha: DateTime(2026, 1, 2));

      final costo = await inventarioRepo.calcularCostoPromedio(articuloId: articulo.id);

      expect(costo, 10000, reason: 'la entrada sin costo no debe diluir el promedio');
    });

    test('regresa null cuando ninguna entrada tiene costo capturado', () async {
      final articulo = await crearArticuloDePrueba();
      await registrarEntrada.ejecutar(articuloId: articulo.id, cantidad: 10, fecha: DateTime(2026, 1, 1));

      final costo = await inventarioRepo.calcularCostoPromedio(articuloId: articulo.id);

      expect(costo, isNull);
    });

    test('nunca cuenta un ajuste como si fuera una entrada', () async {
      final articulo = await crearArticuloDePrueba();
      await registrarEntrada.ejecutar(articuloId: articulo.id, cantidad: 10, costoUnitario: 10000, fecha: DateTime(2026, 1, 1));
      await registrarAjuste.ejecutar(
        articuloId: articulo.id,
        cantidad: 5,
        esEntrada: true,
        observaciones: 'Conteo físico',
      );

      final costo = await inventarioRepo.calcularCostoPromedio(articuloId: articulo.id);

      expect(costo, 10000, reason: 'un ajuste no lleva costoUnitario ni debe alterar el promedio de entradas reales');
    });

    test('separa el costo por variante — cada talla su propio promedio', () async {
      final articulo = await crearArticuloDePrueba(nombre: 'Playera', manejaVariante: true);
      final chica = (await crearVariante.ejecutar(articuloId: articulo.id, valor: 'CH') as CrearVarianteArticuloExitoso)
          .variante;
      final grande = (await crearVariante.ejecutar(articuloId: articulo.id, valor: 'G') as CrearVarianteArticuloExitoso)
          .variante;
      await registrarEntrada.ejecutar(
        articuloId: articulo.id,
        varianteId: chica.id,
        cantidad: 10,
        costoUnitario: 5000,
        fecha: DateTime(2026, 1, 1),
      );
      await registrarEntrada.ejecutar(
        articuloId: articulo.id,
        varianteId: grande.id,
        cantidad: 10,
        costoUnitario: 9000,
        fecha: DateTime(2026, 1, 1),
      );

      final costoChica = await inventarioRepo.calcularCostoPromedio(articuloId: articulo.id, varianteId: chica.id);
      final costoGrande = await inventarioRepo.calcularCostoPromedio(articuloId: articulo.id, varianteId: grande.id);

      expect(costoChica, 5000);
      expect(costoGrande, 9000);
    });
  });

  group('InventarioRepository.listarTodasUnidades (7D)', () {
    test('regresa todas las unidades serializadas de cualquier Artículo', () async {
      final radio = await crearArticuloDePrueba(nombre: 'Radio', manejaSerie: true);
      final chaleco = await crearArticuloDePrueba(nombre: 'Chaleco', manejaSerie: true);
      await registrarEntradaUnidad.ejecutar(articuloId: radio.id, numeroSerie: 'SN-0001', fecha: DateTime(2026, 1, 1));
      await registrarEntradaUnidad.ejecutar(articuloId: chaleco.id, numeroSerie: 'SN-0002', fecha: DateTime(2026, 1, 1));

      final unidades = await inventarioRepo.listarTodasUnidades();

      expect(unidades.map((u) => u.numeroSerie).toSet(), {'SN-0001', 'SN-0002'});
    });
  });

  group('BuscarInventarioUseCase (7D)', () {
    late BuscarInventarioUseCase buscar;

    setUp(() {
      final asignacionServicioRepo = AsignacionServicioRepositoryImpl(db);
      final empleadoRepo = EmpleadoRepositoryImpl(db, asignacionServicioRepo);
      final servicioRepo = ServicioRepositoryImpl(db, asignacionServicioRepo);
      buscar = BuscarInventarioUseCase(articuloRepo, inventarioRepo, empleadoRepo, servicioRepo);
    });

    test('consulta vacía no toca la base de datos y regresa vacío', () async {
      final resultado = await buscar.ejecutar('   ');
      expect(resultado.vacio, isTrue);
    });

    test('encuentra Artículo por nombre o folio, sin distinguir mayúsculas', () async {
      final articulo = await crearArticuloDePrueba(nombre: 'Radio Motorola');

      final porNombre = await buscar.ejecutar('motorola');
      expect(porNombre.articulos.map((a) => a.id), [articulo.id]);

      final porFolio = await buscar.ejecutar(articulo.folio.toLowerCase());
      expect(porFolio.articulos.map((a) => a.id), [articulo.id]);
    });

    test('encuentra unidad por código UNI- o número de serie', () async {
      final radio = await crearArticuloDePrueba(nombre: 'Radio', manejaSerie: true);
      final unidad = ((await registrarEntradaUnidad.ejecutar(
        articuloId: radio.id,
        numeroSerie: 'SN-EXCLUSIVO',
        fecha: DateTime(2026, 1, 1),
      )) as RegistrarEntradaUnidadExitoso)
          .unidad;

      final porSerie = await buscar.ejecutar('sn-exclusivo');
      expect(porSerie.unidades.map((u) => u.codigo), [unidad.codigo]);

      final porCodigo = await buscar.ejecutar(unidad.codigo.toLowerCase());
      expect(porCodigo.unidades.map((u) => u.codigo), [unidad.codigo]);
    });

    test('encuentra Empleado por nombre o número', () async {
      final empleado = await crearEmpleadoDePrueba(numeroEmpleado: 42, nombres: 'Ricardo');

      final porNombre = await buscar.ejecutar('ricardo');
      expect(porNombre.empleados.map((e) => e.id), [empleado.id]);

      final porNumero = await buscar.ejecutar('42');
      expect(porNumero.empleados.map((e) => e.id), [empleado.id]);
    });

    test('encuentra Servicio por nombre o código', () async {
      final servicio = await crearServicioDePrueba(codigo: 'SER-000009', nombre: 'Vigilancia Andrómeda');

      final porNombre = await buscar.ejecutar('andrómeda');
      expect(porNombre.servicios.map((s) => s.id), [servicio.id]);

      final porCodigo = await buscar.ejecutar('ser-000009');
      expect(porCodigo.servicios.map((s) => s.id), [servicio.id]);
    });

    test('acota cada grupo a 8 resultados', () async {
      for (var i = 1; i <= 10; i++) {
        await crearArticuloDePrueba(nombre: 'Chamarra táctica $i');
      }

      final resultado = await buscar.ejecutar('chamarra');

      expect(resultado.articulos, hasLength(8));
    });
  });
}
