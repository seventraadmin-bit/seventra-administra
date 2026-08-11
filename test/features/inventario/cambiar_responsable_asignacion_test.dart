import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/inventario/data/repositories/articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/asignacion_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/categoria_articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/inventario_repository_impl.dart';
import 'package:riseg_one/features/inventario/domain/usecases/cambiar_responsable_asignacion_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_asignacion_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_categoria_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/registrar_entrada_unidad_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/registrar_entrada_usecase.dart';
import 'package:riseg_one/features/telefonia/data/repositories/asignacion_linea_telefonica_repository_impl.dart';
import 'package:riseg_one/features/telefonia/data/repositories/linea_telefonica_equipo_repository_impl.dart';
import 'package:riseg_one/features/telefonia/data/repositories/linea_telefonica_repository_impl.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/asignar_linea_telefonica_usecase.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/asociar_equipo_linea_telefonica_usecase.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/crear_linea_telefonica_usecase.dart';

/// Cubre "Cambiar responsable" (Etapa 9D, ajuste aprobado por Marlon
/// tras el cierre inicial) — distinto de `ReemplazarAsignacionUseCase`
/// (cambia el bien) y de `CerrarAsignacionUseCase`+`CrearAsignacionUseCase`
/// (generan devolución/salida reales). El bien se queda igual, solo
/// cambia el responsable, sin tocar `MovimientoInventario` ni
/// `ArticuloUnidad.estatus`.
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
  late CambiarResponsableAsignacionUseCase cambiarResponsable;

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
    cambiarResponsable = CambiarResponsableAsignacionUseCase(asignacionRepo);
  });

  tearDown(() => db.close());

  Future<ArticuloData> crearArticuloTelefono() async {
    final categoria = (await crearCategoria.ejecutar(nombre: 'Teléfonos') as CrearCategoriaArticuloExitoso).categoria;
    final resultado = await crearArticulo.ejecutar(categoriaId: categoria.id, nombre: 'Teléfono POCO C71', manejaSerie: true);
    return (resultado as CrearArticuloExitoso).articulo;
  }

  Future<ArticuloUnidadData> crearUnidadTelefono(
    String articuloId, {
    String numeroSerie = 'SN-REAL-001',
    String imei = '123456789012345',
  }) async {
    final resultado = await registrarEntradaUnidad.ejecutar(
      articuloId: articuloId,
      numeroSerie: numeroSerie,
      marca: 'POCO',
      modelo: 'C71',
      imei: imei,
      fecha: DateTime(2026, 1, 1),
      costoUnitario: 250000,
    );
    return (resultado as RegistrarEntradaUnidadExitoso).unidad;
  }

  Future<EmpleadoData> crearEmpleado(int numero) {
    return db.into(db.empleado).insertReturning(
          EmpleadoCompanion.insert(
            numeroEmpleado: numero,
            nombres: 'Empleado',
            apellidoPaterno: 'Número $numero',
            sexo: 'masculino',
            fechaNacimiento: DateTime(1990, 1, 1),
            curp: 'PEXJ90010${numero}HDFXXX0$numero',
            rfc: 'PEXJ90010${numero}AB$numero',
            nss: '1234567890$numero',
            estadoCivil: 'soltero',
            fechaIngreso: DateTime(2026, 1, 1),
            aniosExperienciaSeguridad: 3,
          ),
        );
  }

  Future<ServicioData> crearServicio(String sufijo) async {
    final tipoServicio = await db.into(db.tipoServicio).insertReturning(
          TipoServicioCompanion.insert(id: 'tipo-servicio-$sufijo', codigo: 'VIGILANCIA_$sufijo', nombre: 'Vigilancia $sufijo'),
        );
    final cliente = await db
        .into(db.cliente)
        .insertReturning(ClienteCompanion.insert(codigo: 'CLI-$sufijo', nombreComercial: 'Cliente $sufijo'));
    return db.into(db.servicio).insertReturning(
          ServicioCompanion.insert(
            codigo: 'SER-$sufijo',
            clienteId: cliente.id,
            nombre: 'Servicio $sufijo',
            tipoServicioId: tipoServicio.id,
            fechaInicio: DateTime(2026, 1, 1),
          ),
        );
  }

  group('CambiarResponsableAsignacionUseCase — cambios de destino', () {
    test('Empleado A → Empleado B con el mismo teléfono', () async {
      final articulo = await crearArticuloTelefono();
      final unidad = await crearUnidadTelefono(articulo.id);
      final empleadoA = await crearEmpleado(1);
      final empleadoB = await crearEmpleado(2);

      final asignacionInicial = (await crearAsignacion.ejecutar(
        articuloId: articulo.id,
        unidadId: unidad.id,
        cantidad: 1,
        empleadoId: empleadoA.id,
        fechaEntrega: DateTime(2026, 1, 10),
      )) as CrearAsignacionExitoso;

      final resultado = await cambiarResponsable.ejecutar(
        asignacionId: asignacionInicial.asignacion.id,
        nuevoEmpleadoId: empleadoB.id,
        fecha: DateTime(2026, 2, 1),
        actorUsuarioId: null,
      );

      expect(resultado, isA<CambiarResponsableAsignacionExitoso>());
      final nueva = (resultado as CambiarResponsableAsignacionExitoso).nueva;
      expect(nueva.empleadoId, empleadoB.id);
      expect(nueva.unidadId, unidad.id, reason: 'misma unidad física en todo el proceso');
      expect(nueva.estatus, 'activa');
    });

    test('Servicio A → Servicio B con el mismo teléfono', () async {
      final articulo = await crearArticuloTelefono();
      final unidad = await crearUnidadTelefono(articulo.id);
      final servicioA = await crearServicio('A');
      final servicioB = await crearServicio('B');

      final asignacionInicial = (await crearAsignacion.ejecutar(
        articuloId: articulo.id,
        unidadId: unidad.id,
        cantidad: 1,
        servicioId: servicioA.id,
        fechaEntrega: DateTime(2026, 1, 10),
      )) as CrearAsignacionExitoso;

      final resultado = await cambiarResponsable.ejecutar(
        asignacionId: asignacionInicial.asignacion.id,
        nuevoServicioId: servicioB.id,
        fecha: DateTime(2026, 2, 1),
      );

      expect(resultado, isA<CambiarResponsableAsignacionExitoso>());
      expect((resultado as CambiarResponsableAsignacionExitoso).nueva.servicioId, servicioB.id);
    });

    test('Empleado → Servicio', () async {
      final articulo = await crearArticuloTelefono();
      final unidad = await crearUnidadTelefono(articulo.id);
      final empleado = await crearEmpleado(1);
      final servicio = await crearServicio('X');

      final asignacionInicial = (await crearAsignacion.ejecutar(
        articuloId: articulo.id,
        unidadId: unidad.id,
        cantidad: 1,
        empleadoId: empleado.id,
        fechaEntrega: DateTime(2026, 1, 10),
      )) as CrearAsignacionExitoso;

      final resultado = await cambiarResponsable.ejecutar(
        asignacionId: asignacionInicial.asignacion.id,
        nuevoServicioId: servicio.id,
        fecha: DateTime(2026, 2, 1),
      );

      expect(resultado, isA<CambiarResponsableAsignacionExitoso>());
      final nueva = (resultado as CambiarResponsableAsignacionExitoso).nueva;
      expect(nueva.servicioId, servicio.id);
      expect(nueva.empleadoId, isNull);
    });

    test('Servicio → Empleado', () async {
      final articulo = await crearArticuloTelefono();
      final unidad = await crearUnidadTelefono(articulo.id);
      final servicio = await crearServicio('Y');
      final empleado = await crearEmpleado(1);

      final asignacionInicial = (await crearAsignacion.ejecutar(
        articuloId: articulo.id,
        unidadId: unidad.id,
        cantidad: 1,
        servicioId: servicio.id,
        fechaEntrega: DateTime(2026, 1, 10),
      )) as CrearAsignacionExitoso;

      final resultado = await cambiarResponsable.ejecutar(
        asignacionId: asignacionInicial.asignacion.id,
        nuevoEmpleadoId: empleado.id,
        fecha: DateTime(2026, 2, 1),
      );

      expect(resultado, isA<CambiarResponsableAsignacionExitoso>());
      final nueva = (resultado as CambiarResponsableAsignacionExitoso).nueva;
      expect(nueva.empleadoId, empleado.id);
      expect(nueva.servicioId, isNull);
    });
  });

  group('CambiarResponsableAsignacionUseCase — invariantes', () {
    test('una sola asignación vigente por unidad tras el cambio', () async {
      final articulo = await crearArticuloTelefono();
      final unidad = await crearUnidadTelefono(articulo.id);
      final empleadoA = await crearEmpleado(1);
      final empleadoB = await crearEmpleado(2);

      final inicial = (await crearAsignacion.ejecutar(
        articuloId: articulo.id,
        unidadId: unidad.id,
        cantidad: 1,
        empleadoId: empleadoA.id,
        fechaEntrega: DateTime(2026, 1, 10),
      )) as CrearAsignacionExitoso;

      await cambiarResponsable.ejecutar(
        asignacionId: inicial.asignacion.id,
        nuevoEmpleadoId: empleadoB.id,
        fecha: DateTime(2026, 2, 1),
      );

      final activas = await asignacionRepo.listarPorUnidad(unidad.id);
      expect(activas.where((a) => a.estatus == 'activa'), hasLength(1), reason: 'una sola asignación vigente');

      final vigente = await asignacionRepo.obtenerActivaPorUnidad(unidad.id);
      expect(vigente!.empleadoId, empleadoB.id, reason: 'Telefonía/Inventario reflejan de inmediato al nuevo responsable');
    });

    test('histórico anterior conservado — ambas filas consultables', () async {
      final articulo = await crearArticuloTelefono();
      final unidad = await crearUnidadTelefono(articulo.id);
      final empleadoA = await crearEmpleado(1);
      final empleadoB = await crearEmpleado(2);

      final inicial = (await crearAsignacion.ejecutar(
        articuloId: articulo.id,
        unidadId: unidad.id,
        cantidad: 1,
        empleadoId: empleadoA.id,
        fechaEntrega: DateTime(2026, 1, 10),
      )) as CrearAsignacionExitoso;

      await cambiarResponsable.ejecutar(
        asignacionId: inicial.asignacion.id,
        nuevoEmpleadoId: empleadoB.id,
        fecha: DateTime(2026, 2, 1),
      );

      final historial = await asignacionRepo.listarPorUnidad(unidad.id);
      expect(historial, hasLength(2));
      final anterior = historial.firstWhere((a) => a.id == inicial.asignacion.id);
      expect(anterior.estatus, 'reasignada');
      expect(anterior.empleadoId, empleadoA.id, reason: 'la fila vieja conserva el responsable original');
      expect(anterior.fechaCierre, DateTime(2026, 2, 1));
    });

    test('existencias no cambian por cambiar responsable — la unidad sigue "asignado"', () async {
      final articulo = await crearArticuloTelefono();
      final unidad = await crearUnidadTelefono(articulo.id);
      final empleadoA = await crearEmpleado(1);
      final empleadoB = await crearEmpleado(2);

      final inicial = (await crearAsignacion.ejecutar(
        articuloId: articulo.id,
        unidadId: unidad.id,
        cantidad: 1,
        empleadoId: empleadoA.id,
        fechaEntrega: DateTime(2026, 1, 10),
      )) as CrearAsignacionExitoso;

      final existenciaAntes = await inventarioRepo.calcularExistenciaUnidades(articulo.id);

      await cambiarResponsable.ejecutar(
        asignacionId: inicial.asignacion.id,
        nuevoEmpleadoId: empleadoB.id,
        fecha: DateTime(2026, 2, 1),
      );

      final unidadTrasCambio = await inventarioRepo.obtenerUnidadPorId(unidad.id);
      expect(unidadTrasCambio!.estatus, 'asignado', reason: 'nunca pasa por disponible');

      final existenciaDespues = await inventarioRepo.calcularExistenciaUnidades(articulo.id);
      expect(existenciaDespues.asignado, existenciaAntes.asignado);
      expect(existenciaDespues.disponible, existenciaAntes.disponible);
      expect(existenciaDespues.total, existenciaAntes.total);
    });

    test('MovimientoInventario no recibe una falsa devolución/entrada', () async {
      final articulo = await crearArticuloTelefono();
      final unidad = await crearUnidadTelefono(articulo.id);
      final empleadoA = await crearEmpleado(1);
      final empleadoB = await crearEmpleado(2);

      final inicial = (await crearAsignacion.ejecutar(
        articuloId: articulo.id,
        unidadId: unidad.id,
        cantidad: 1,
        empleadoId: empleadoA.id,
        fechaEntrega: DateTime(2026, 1, 10),
      )) as CrearAsignacionExitoso;

      final movimientosAntes = await inventarioRepo.listarMovimientos(unidadId: unidad.id);

      await cambiarResponsable.ejecutar(
        asignacionId: inicial.asignacion.id,
        nuevoEmpleadoId: empleadoB.id,
        fecha: DateTime(2026, 2, 1),
      );

      final movimientosDespues = await inventarioRepo.listarMovimientos(unidadId: unidad.id);
      expect(
        movimientosDespues.length,
        movimientosAntes.length,
        reason: 'cambiar responsable nunca genera un MovimientoInventario nuevo',
      );
    });

    test('nunca liga asignacionReemplazoId — no es un reemplazo', () async {
      final articulo = await crearArticuloTelefono();
      final unidad = await crearUnidadTelefono(articulo.id);
      final empleadoA = await crearEmpleado(1);
      final empleadoB = await crearEmpleado(2);

      final inicial = (await crearAsignacion.ejecutar(
        articuloId: articulo.id,
        unidadId: unidad.id,
        cantidad: 1,
        empleadoId: empleadoA.id,
        fechaEntrega: DateTime(2026, 1, 10),
      )) as CrearAsignacionExitoso;

      await cambiarResponsable.ejecutar(
        asignacionId: inicial.asignacion.id,
        nuevoEmpleadoId: empleadoB.id,
        fecha: DateTime(2026, 2, 1),
      );

      final anterior = await asignacionRepo.obtenerPorId(inicial.asignacion.id);
      expect(anterior!.asignacionReemplazoId, isNull);
    });

    test('actorUsuarioId se persiste en ambas filas (vieja y nueva)', () async {
      final usuario = await db.into(db.usuario).insertReturning(
            UsuarioCompanion.insert(nombre: 'Ana', nombreUsuario: 'ana', passwordHash: 'pbkdf2\$1\$AA==\$BB=='),
          );
      final articulo = await crearArticuloTelefono();
      final unidad = await crearUnidadTelefono(articulo.id);
      final empleadoA = await crearEmpleado(1);
      final empleadoB = await crearEmpleado(2);

      final inicial = (await crearAsignacion.ejecutar(
        articuloId: articulo.id,
        unidadId: unidad.id,
        cantidad: 1,
        empleadoId: empleadoA.id,
        fechaEntrega: DateTime(2026, 1, 10),
      )) as CrearAsignacionExitoso;

      final resultado = await cambiarResponsable.ejecutar(
        asignacionId: inicial.asignacion.id,
        nuevoEmpleadoId: empleadoB.id,
        fecha: DateTime(2026, 2, 1),
        actorUsuarioId: usuario.id,
      );

      final nueva = (resultado as CambiarResponsableAsignacionExitoso).nueva;
      expect(nueva.actorUsuarioId, usuario.id);
      final anterior = await asignacionRepo.obtenerPorId(inicial.asignacion.id);
      expect(anterior!.actorUsuarioId, usuario.id);
    });
  });

  group('CambiarResponsableAsignacionUseCase — validaciones', () {
    test('rechaza artículos por cantidad — solo unidades serializadas', () async {
      final categoria = (await crearCategoria.ejecutar(nombre: 'Uniformes')) as CrearCategoriaArticuloExitoso;
      final articulo =
          (await crearArticulo.ejecutar(categoriaId: categoria.categoria.id, nombre: 'Camisa')) as CrearArticuloExitoso;
      await registrarEntrada.ejecutar(articuloId: articulo.articulo.id, cantidad: 10, fecha: DateTime(2026, 1, 1));
      final empleadoA = await crearEmpleado(1);
      final empleadoB = await crearEmpleado(2);

      final inicial = (await crearAsignacion.ejecutar(
        articuloId: articulo.articulo.id,
        cantidad: 3,
        empleadoId: empleadoA.id,
        fechaEntrega: DateTime(2026, 1, 10),
      )) as CrearAsignacionExitoso;

      final resultado = await cambiarResponsable.ejecutar(
        asignacionId: inicial.asignacion.id,
        nuevoEmpleadoId: empleadoB.id,
        fecha: DateTime(2026, 2, 1),
      );

      expect(resultado, isA<CambiarResponsableAsignacionSoloUnidadesSerializadas>());
    });

    test('rechaza asignación inexistente', () async {
      final resultado = await cambiarResponsable.ejecutar(
        asignacionId: 'asignacion-inexistente',
        nuevoEmpleadoId: 'empleado-cualquiera',
        fecha: DateTime(2026, 2, 1),
      );
      expect(resultado, isA<CambiarResponsableAsignacionNoExiste>());
    });

    test('rechaza una asignación ya cerrada', () async {
      final articulo = await crearArticuloTelefono();
      final unidad = await crearUnidadTelefono(articulo.id);
      final empleadoA = await crearEmpleado(1);
      final empleadoB = await crearEmpleado(2);
      final empleadoC = await crearEmpleado(3);

      final inicial = (await crearAsignacion.ejecutar(
        articuloId: articulo.id,
        unidadId: unidad.id,
        cantidad: 1,
        empleadoId: empleadoA.id,
        fechaEntrega: DateTime(2026, 1, 10),
      )) as CrearAsignacionExitoso;

      await cambiarResponsable.ejecutar(
        asignacionId: inicial.asignacion.id,
        nuevoEmpleadoId: empleadoB.id,
        fecha: DateTime(2026, 2, 1),
      );

      final segundoIntento = await cambiarResponsable.ejecutar(
        asignacionId: inicial.asignacion.id,
        nuevoEmpleadoId: empleadoC.id,
        fecha: DateTime(2026, 3, 1),
      );

      expect(segundoIntento, isA<CambiarResponsableAsignacionNoVigente>());
    });

    test('rechaza destino inválido (ninguno o ambos)', () async {
      final articulo = await crearArticuloTelefono();
      final unidad = await crearUnidadTelefono(articulo.id);
      final empleado = await crearEmpleado(1);

      final inicial = (await crearAsignacion.ejecutar(
        articuloId: articulo.id,
        unidadId: unidad.id,
        cantidad: 1,
        empleadoId: empleado.id,
        fechaEntrega: DateTime(2026, 1, 10),
      )) as CrearAsignacionExitoso;

      final resultado = await cambiarResponsable.ejecutar(
        asignacionId: inicial.asignacion.id,
        fecha: DateTime(2026, 2, 1),
      );

      expect(resultado, isA<CambiarResponsableAsignacionDestinoInvalido>());
    });

    test('rechaza mismo responsable', () async {
      final articulo = await crearArticuloTelefono();
      final unidad = await crearUnidadTelefono(articulo.id);
      final empleado = await crearEmpleado(1);

      final inicial = (await crearAsignacion.ejecutar(
        articuloId: articulo.id,
        unidadId: unidad.id,
        cantidad: 1,
        empleadoId: empleado.id,
        fechaEntrega: DateTime(2026, 1, 10),
      )) as CrearAsignacionExitoso;

      final resultado = await cambiarResponsable.ejecutar(
        asignacionId: inicial.asignacion.id,
        nuevoEmpleadoId: empleado.id,
        fecha: DateTime(2026, 2, 1),
      );

      expect(resultado, isA<CambiarResponsableAsignacionMismoResponsable>());
    });

    test('rechaza fecha anterior a la de la asignación original', () async {
      final articulo = await crearArticuloTelefono();
      final unidad = await crearUnidadTelefono(articulo.id);
      final empleadoA = await crearEmpleado(1);
      final empleadoB = await crearEmpleado(2);

      final inicial = (await crearAsignacion.ejecutar(
        articuloId: articulo.id,
        unidadId: unidad.id,
        cantidad: 1,
        empleadoId: empleadoA.id,
        fechaEntrega: DateTime(2026, 1, 10),
      )) as CrearAsignacionExitoso;

      final resultado = await cambiarResponsable.ejecutar(
        asignacionId: inicial.asignacion.id,
        nuevoEmpleadoId: empleadoB.id,
        fecha: DateTime(2026, 1, 1),
      );

      expect(resultado, isA<CambiarResponsableAsignacionFechaInvalida>());
    });
  });

  group('Consistencia con Telefonía (línea asociada y divergence guard de 9B)', () {
    test('la línea asociada permanece igual si no se pidió cambiarla', () async {
      final articulo = await crearArticuloTelefono();
      final unidad = await crearUnidadTelefono(articulo.id);
      final empleadoA = await crearEmpleado(1);
      final empleadoB = await crearEmpleado(2);

      final asignacionLineaRepo = AsignacionLineaTelefonicaRepositoryImpl(db);
      final equipoRepo = LineaTelefonicaEquipoRepositoryImpl(db, asignacionLineaRepo, asignacionRepo, inventarioRepo);
      final lineaRepo = LineaTelefonicaRepositoryImpl(db, asignacionLineaRepo, equipoRepo);
      final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
      final crearLinea = CrearLineaTelefonicaUseCase(lineaRepo, generarCodigo);
      final asociarEquipo = AsociarEquipoLineaTelefonicaUseCase(lineaRepo, equipoRepo, inventarioRepo);
      final asignarLinea = AsignarLineaTelefonicaUseCase(lineaRepo, asignacionLineaRepo, equipoRepo);

      final linea = (await crearLinea.ejecutar(operador: 'telcel', modalidadSim: 'fisica')) as CrearLineaTelefonicaExitoso;
      final asociado = await asociarEquipo.ejecutar(
        lineaTelefonicaId: linea.linea.id,
        unidadId: unidad.id,
        fechaInicio: DateTime(2026, 1, 15),
      );
      expect(asociado, isA<AsociarEquipoLineaTelefonicaExitoso>());
      await asignarLinea.ejecutar(
        lineaTelefonicaId: linea.linea.id,
        empleadoId: empleadoA.id,
        fechaInicio: DateTime(2026, 1, 15),
        moverEquipoAsociado: false,
      );

      final inicial = (await crearAsignacion.ejecutar(
        articuloId: articulo.id,
        unidadId: unidad.id,
        cantidad: 1,
        empleadoId: empleadoA.id,
        fechaEntrega: DateTime(2026, 1, 10),
      )) as CrearAsignacionExitoso;

      final equipoAntes = await equipoRepo.obtenerActualPorUnidad(unidad.id);

      await cambiarResponsable.ejecutar(
        asignacionId: inicial.asignacion.id,
        nuevoEmpleadoId: empleadoB.id,
        fecha: DateTime(2026, 2, 1),
      );

      final equipoDespues = await equipoRepo.obtenerActualPorUnidad(unidad.id);
      expect(equipoDespues!.id, equipoAntes!.id, reason: 'cambiar responsable no toca LineaTelefonicaEquipo');
      expect(equipoDespues.lineaTelefonicaId, linea.linea.id);

      final asignacionLineaVigente = await asignacionLineaRepo.obtenerActivaPorLinea(linea.linea.id);
      expect(
        asignacionLineaVigente!.empleadoId,
        empleadoA.id,
        reason: 'la asignación de la línea no cambia — cambiar responsable no sincroniza hacia Telefonía',
      );
    });

    test(
      'consistencia con el divergence guard de 9B — cambiar responsable en Inventario no fuerza ninguna '
      'sincronización con la línea, la divergencia queda visible, no auto-corregida',
      () async {
        final articulo = await crearArticuloTelefono();
        final unidad = await crearUnidadTelefono(articulo.id);
        final empleadoA = await crearEmpleado(1);
        final empleadoB = await crearEmpleado(2);

        final asignacionLineaRepo = AsignacionLineaTelefonicaRepositoryImpl(db);
        final equipoRepo = LineaTelefonicaEquipoRepositoryImpl(db, asignacionLineaRepo, asignacionRepo, inventarioRepo);
        final lineaRepo = LineaTelefonicaRepositoryImpl(db, asignacionLineaRepo, equipoRepo);
        final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
        final crearLinea = CrearLineaTelefonicaUseCase(lineaRepo, generarCodigo);
        final asociarEquipo = AsociarEquipoLineaTelefonicaUseCase(lineaRepo, equipoRepo, inventarioRepo);
        final asignarLinea = AsignarLineaTelefonicaUseCase(lineaRepo, asignacionLineaRepo, equipoRepo);

        final linea = (await crearLinea.ejecutar(operador: 'telcel', modalidadSim: 'fisica')) as CrearLineaTelefonicaExitoso;
        final asociado = await asociarEquipo.ejecutar(
          lineaTelefonicaId: linea.linea.id,
          unidadId: unidad.id,
          fechaInicio: DateTime(2026, 1, 15),
        );
        expect(asociado, isA<AsociarEquipoLineaTelefonicaExitoso>());
        await asignarLinea.ejecutar(
          lineaTelefonicaId: linea.linea.id,
          empleadoId: empleadoA.id,
          fechaInicio: DateTime(2026, 1, 15),
          moverEquipoAsociado: false,
        );

        final inicial = (await crearAsignacion.ejecutar(
          articuloId: articulo.id,
          unidadId: unidad.id,
          cantidad: 1,
          empleadoId: empleadoA.id,
          fechaEntrega: DateTime(2026, 1, 10),
        )) as CrearAsignacionExitoso;

        await cambiarResponsable.ejecutar(
          asignacionId: inicial.asignacion.id,
          nuevoEmpleadoId: empleadoB.id,
          fecha: DateTime(2026, 2, 1),
        );

        final custodiaInventario = await equipoRepo.obtenerCustodiaInventarioActual(unidad.id);
        final asignacionLineaVigente = await asignacionLineaRepo.obtenerActivaPorLinea(linea.linea.id);

        expect(custodiaInventario!.empleadoId, empleadoB.id, reason: 'Inventario ya refleja al nuevo responsable');
        expect(
          asignacionLineaVigente!.empleadoId,
          empleadoA.id,
          reason: 'la línea sigue apuntando al responsable anterior — divergencia real, visible, nunca auto-corregida',
        );
        expect(
          custodiaInventario.empleadoId != asignacionLineaVigente.empleadoId,
          isTrue,
          reason: 'misma advertencia de divergencia que ya usa el expediente de la Línea (9B)',
        );
      },
    );
  });
}
