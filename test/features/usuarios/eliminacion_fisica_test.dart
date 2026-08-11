// Pruebas de eliminación física extraordinaria (Etapa 11D) — un
// UseCase sellado + repositorio transaccional por entidad (7 en
// total), todos con la misma forma de resultado (Exitoso/NoExiste/
// MotivoRequerido/TieneDependencias/ErrorInesperado). El backend ya
// está cerrado; este archivo solo cubre lo que faltaba de prueba.
//
// `actorUsuarioId` es una FK real hacia `Usuario` (`PRAGMA
// foreign_keys = ON`) en `EliminacionFisicaEvento` — cualquier valor
// que se le pase a `ejecutar()` debe existir de antemano en la base de
// prueba, o la inserción falla (se traduce en `ErrorInesperado`, un
// resultado confuso si no se sabe el porqué). `usuario-prueba` se
// siembra en el `setUp` compartido exactamente para eso.

import 'dart:convert';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/core/di/providers.dart';

import 'package:riseg_one/features/inventario/data/repositories/articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/asignacion_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/categoria_articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/inventario_repository_impl.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/crear_categoria_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/eliminar_articulo_fisicamente_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/eliminar_categoria_articulo_fisicamente_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/registrar_entrada_unidad_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/regularizar_articulo_serializado_usecase.dart';
import 'package:riseg_one/features/inventario/inventario_providers.dart';

import 'package:riseg_one/features/organizacion/data/repositories/area_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/configuracion_cobro_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/puesto_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_comercial_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/sucursal_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_linea_comercial_vigencia_table.dart' show TratamientoIva;
import 'package:riseg_one/features/organizacion/domain/usecases/crear_area_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_linea_comercial_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_sucursal_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/eliminar_area_fisicamente_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/eliminar_puesto_fisicamente_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/eliminar_sucursal_fisicamente_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_area_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_servicio_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/linea_comercial_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_validator.dart';

import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';

import 'package:riseg_one/features/telefonia/data/repositories/asignacion_linea_telefonica_repository_impl.dart';
import 'package:riseg_one/features/telefonia/data/repositories/linea_telefonica_equipo_repository_impl.dart';
import 'package:riseg_one/features/telefonia/data/repositories/linea_telefonica_repository_impl.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/asignar_linea_telefonica_usecase.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/crear_linea_telefonica_usecase.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/eliminar_linea_telefonica_fisicamente_usecase.dart';

import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

import 'package:riseg_one/features/vehiculos/data/repositories/asignacion_vehiculo_repository_impl.dart';
import 'package:riseg_one/features/vehiculos/data/repositories/vehiculo_kilometraje_repository_impl.dart';
import 'package:riseg_one/features/vehiculos/data/repositories/vehiculo_repository_impl.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/asignar_vehiculo_usecase.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/crear_vehiculo_usecase.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/eliminar_vehiculo_fisicamente_usecase.dart';
import 'package:riseg_one/features/vehiculos/vehiculos_providers.dart';

const _actorUsuarioId = 'usuario-prueba';

/// Copiado de `authorization_service_test.dart` (Etapa 11C/11D) — fija
/// una sesión sin pasar por `LoginUseCase`, mismo patrón que el resto
/// del proyecto usa para probar fachadas `Autorizado`/`exigirMaestro`
/// sin montar ningún widget.
class _SesionFija extends SesionController {
  _SesionFija(this._sesion);
  final SesionUsuario? _sesion;
  @override
  SesionUsuario? build() => _sesion;
}

ProviderContainer _container(AppDatabase db, SesionUsuario? sesion) {
  final container = ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      sesionControllerProvider.overrideWith(() => _SesionFija(sesion)),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(
            id: const Value(_actorUsuarioId),
            nombre: 'Usuario de prueba',
            nombreUsuario: 'usuario-prueba',
            passwordHash: 'x',
          ),
        );
  });

  tearDown(() => db.close());

  group('Eliminación física — Vehiculo', () {
    late VehiculoRepositoryImpl vehiculoRepo;
    late CrearVehiculoUseCase crearVehiculo;
    late AsignarVehiculoUseCase asignarVehiculo;
    late EliminarVehiculoFisicamenteUseCase eliminar;

    setUp(() {
      final asignacionRepo = AsignacionVehiculoRepositoryImpl(db);
      vehiculoRepo = VehiculoRepositoryImpl(db, asignacionRepo);
      final kilometrajeRepo = VehiculoKilometrajeRepositoryImpl(db);
      crearVehiculo = CrearVehiculoUseCase(vehiculoRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db)));
      asignarVehiculo = AsignarVehiculoUseCase(vehiculoRepo, asignacionRepo, kilometrajeRepo);
      eliminar = EliminarVehiculoFisicamenteUseCase(vehiculoRepo);
    });

    Future<VehiculoData> crearVehiculoDePrueba() async {
      final r = await crearVehiculo.ejecutar(marca: 'BMW', modelo: '320i', tipoVehiculo: 'sedan');
      return (r as CrearVehiculoExitoso).vehiculo;
    }

    test('NoExiste cuando el id no existe', () async {
      final r = await eliminar.ejecutar(vehiculoId: 'no-existe', motivo: 'Registro duplicado');
      expect(r, isA<EliminarVehiculoFisicamenteNoExiste>());
    });

    test('MotivoRequerido con motivo vacío o solo espacios', () async {
      final vacio = await eliminar.ejecutar(vehiculoId: 'cualquiera', motivo: '');
      expect(vacio, isA<EliminarVehiculoFisicamenteMotivoRequerido>());
      final espacios = await eliminar.ejecutar(vehiculoId: 'cualquiera', motivo: '   ');
      expect(espacios, isA<EliminarVehiculoFisicamenteMotivoRequerido>());
    });

    test('TieneDependencias — al menos una asignación registrada', () async {
      final vehiculo = await crearVehiculoDePrueba();
      final empleado = await db.into(db.empleado).insertReturning(
            EmpleadoCompanion.insert(
              numeroEmpleado: 1,
              nombres: 'Juan',
              apellidoPaterno: 'Pérez',
              sexo: 'masculino',
              fechaNacimiento: DateTime(1990, 1, 1),
              curp: 'PEXJ900101HDFXXX01',
              rfc: 'PEXJ900101AB1',
              nss: '12345678901',
              estadoCivil: 'soltero',
              fechaIngreso: DateTime(2026, 1, 1),
              aniosExperienciaSeguridad: 3,
            ),
          );
      await asignarVehiculo.ejecutar(vehiculoId: vehiculo.id, empleadoId: empleado.id, fechaInicio: DateTime(2026, 1, 5));

      final r = await eliminar.ejecutar(vehiculoId: vehiculo.id, motivo: 'prueba');
      expect(r, isA<EliminarVehiculoFisicamenteTieneDependencias>());
      expect((r as EliminarVehiculoFisicamenteTieneDependencias).detalle, contains('1 asignación'));
    });

    test('Exitoso — borra la fila y registra el evento de auditoría con el actor', () async {
      final vehiculo = await crearVehiculoDePrueba();
      final r = await eliminar.ejecutar(
        vehiculoId: vehiculo.id,
        motivo: 'Registro duplicado por error de captura',
        actorUsuarioId: _actorUsuarioId,
      );
      expect(r, isA<EliminarVehiculoFisicamenteExitoso>());
      expect(await vehiculoRepo.obtenerPorId(vehiculo.id), isNull);

      final evento =
          await (db.select(db.eliminacionFisicaEvento)..where((t) => t.entidadIdOriginal.equals(vehiculo.id))).getSingle();
      expect(evento.tipoEntidad, 'vehiculo');
      expect(evento.entidadIdOriginal, vehiculo.id);
      expect(evento.motivo, 'Registro duplicado por error de captura');
      expect(evento.actorUsuarioId, _actorUsuarioId);
      final snapshot = jsonDecode(evento.snapshotJson) as Map<String, dynamic>;
      expect(snapshot['id'], vehiculo.id);
    });

    test('Exitoso con actorUsuarioId null — sesión ausente, el evento se guarda igual', () async {
      final vehiculo = await crearVehiculoDePrueba();
      final r = await eliminar.ejecutar(vehiculoId: vehiculo.id, motivo: 'prueba sin sesión');
      expect(r, isA<EliminarVehiculoFisicamenteExitoso>());

      final evento =
          await (db.select(db.eliminacionFisicaEvento)..where((t) => t.entidadIdOriginal.equals(vehiculo.id))).getSingle();
      expect(evento.actorUsuarioId, isNull);
    });
  });

  group('Eliminación física — LineaTelefonica', () {
    late LineaTelefonicaRepositoryImpl lineaRepo;
    late CrearLineaTelefonicaUseCase crearLinea;
    late AsignarLineaTelefonicaUseCase asignarLinea;
    late EliminarLineaTelefonicaFisicamenteUseCase eliminar;

    setUp(() {
      final asignacionLineaRepo = AsignacionLineaTelefonicaRepositoryImpl(db);
      final equipoRepo = LineaTelefonicaEquipoRepositoryImpl(
        db,
        asignacionLineaRepo,
        AsignacionRepositoryImpl(db),
        InventarioRepositoryImpl(db),
      );
      lineaRepo = LineaTelefonicaRepositoryImpl(db, asignacionLineaRepo, equipoRepo);
      crearLinea = CrearLineaTelefonicaUseCase(lineaRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db)));
      asignarLinea = AsignarLineaTelefonicaUseCase(lineaRepo, asignacionLineaRepo, equipoRepo);
      eliminar = EliminarLineaTelefonicaFisicamenteUseCase(lineaRepo);
    });

    Future<LineaTelefonicaData> crearLineaDePrueba() async {
      final r = await crearLinea.ejecutar(operador: 'telcel', modalidadSim: 'fisica');
      return (r as CrearLineaTelefonicaExitoso).linea;
    }

    test('NoExiste cuando el id no existe', () async {
      final r = await eliminar.ejecutar(lineaTelefonicaId: 'no-existe', motivo: 'prueba');
      expect(r, isA<EliminarLineaTelefonicaFisicamenteNoExiste>());
    });

    test('MotivoRequerido con motivo vacío o solo espacios', () async {
      final vacio = await eliminar.ejecutar(lineaTelefonicaId: 'cualquiera', motivo: '');
      expect(vacio, isA<EliminarLineaTelefonicaFisicamenteMotivoRequerido>());
      final espacios = await eliminar.ejecutar(lineaTelefonicaId: 'cualquiera', motivo: '  ');
      expect(espacios, isA<EliminarLineaTelefonicaFisicamenteMotivoRequerido>());
    });

    test('TieneDependencias — al menos una asignación registrada', () async {
      final linea = await crearLineaDePrueba();
      final empleado = await db.into(db.empleado).insertReturning(
            EmpleadoCompanion.insert(
              numeroEmpleado: 1,
              nombres: 'Juan',
              apellidoPaterno: 'Pérez',
              sexo: 'masculino',
              fechaNacimiento: DateTime(1990, 1, 1),
              curp: 'PEXJ900101HDFXXX01',
              rfc: 'PEXJ900101AB1',
              nss: '12345678901',
              estadoCivil: 'soltero',
              fechaIngreso: DateTime(2026, 1, 1),
              aniosExperienciaSeguridad: 3,
            ),
          );
      await asignarLinea.ejecutar(lineaTelefonicaId: linea.id, empleadoId: empleado.id, fechaInicio: DateTime(2026, 1, 5));

      final r = await eliminar.ejecutar(lineaTelefonicaId: linea.id, motivo: 'prueba');
      expect(r, isA<EliminarLineaTelefonicaFisicamenteTieneDependencias>());
      expect((r as EliminarLineaTelefonicaFisicamenteTieneDependencias).detalle, contains('1 asignación'));
    });

    test('Exitoso — borra la fila y registra el evento de auditoría con el actor', () async {
      final linea = await crearLineaDePrueba();
      final r = await eliminar.ejecutar(
        lineaTelefonicaId: linea.id,
        motivo: 'Línea capturada por error',
        actorUsuarioId: _actorUsuarioId,
      );
      expect(r, isA<EliminarLineaTelefonicaFisicamenteExitoso>());
      expect(await lineaRepo.obtenerPorId(linea.id), isNull);

      final evento =
          await (db.select(db.eliminacionFisicaEvento)..where((t) => t.entidadIdOriginal.equals(linea.id))).getSingle();
      expect(evento.tipoEntidad, 'lineaTelefonica');
      expect(evento.motivo, 'Línea capturada por error');
      expect(evento.actorUsuarioId, _actorUsuarioId);
      final snapshot = jsonDecode(evento.snapshotJson) as Map<String, dynamic>;
      expect(snapshot['id'], linea.id);
    });

    test('Exitoso con actorUsuarioId null — sesión ausente, el evento se guarda igual', () async {
      final linea = await crearLineaDePrueba();
      final r = await eliminar.ejecutar(lineaTelefonicaId: linea.id, motivo: 'prueba sin sesión');
      expect(r, isA<EliminarLineaTelefonicaFisicamenteExitoso>());

      final evento =
          await (db.select(db.eliminacionFisicaEvento)..where((t) => t.entidadIdOriginal.equals(linea.id))).getSingle();
      expect(evento.actorUsuarioId, isNull);
    });
  });

  group('Eliminación física — Articulo', () {
    late ArticuloRepositoryImpl articuloRepo;
    late CategoriaArticuloRepositoryImpl categoriaRepo;
    late CrearCategoriaArticuloUseCase crearCategoria;
    late CrearArticuloUseCase crearArticulo;
    late RegistrarEntradaUnidadUseCase registrarEntradaUnidad;
    late EliminarArticuloFisicamenteUseCase eliminar;

    setUp(() {
      categoriaRepo = CategoriaArticuloRepositoryImpl(db);
      articuloRepo = ArticuloRepositoryImpl(db);
      final inventarioRepo = InventarioRepositoryImpl(db);
      final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
      crearCategoria = CrearCategoriaArticuloUseCase(categoriaRepo);
      crearArticulo = CrearArticuloUseCase(articuloRepo, categoriaRepo, generarCodigo);
      registrarEntradaUnidad = RegistrarEntradaUnidadUseCase(inventarioRepo, articuloRepo, generarCodigo);
      eliminar = EliminarArticuloFisicamenteUseCase(articuloRepo);
    });

    Future<CategoriaArticuloData> crearCategoriaDePrueba() async {
      final r = await crearCategoria.ejecutar(nombre: 'Radios');
      return (r as CrearCategoriaArticuloExitoso).categoria;
    }

    Future<ArticuloData> crearArticuloDePrueba({bool manejaSerie = false, String? categoriaId}) async {
      final catId = categoriaId ?? (await crearCategoriaDePrueba()).id;
      final r = await crearArticulo.ejecutar(
        categoriaId: catId,
        nombre: 'Radio Motorola',
        manejaVariante: false,
        manejaSerie: manejaSerie,
      );
      return (r as CrearArticuloExitoso).articulo;
    }

    test('NoExiste cuando el id no existe', () async {
      final r = await eliminar.ejecutar(articuloId: 'no-existe', motivo: 'prueba');
      expect(r, isA<EliminarArticuloFisicamenteNoExiste>());
    });

    test('MotivoRequerido con motivo vacío o solo espacios', () async {
      final vacio = await eliminar.ejecutar(articuloId: 'cualquiera', motivo: '');
      expect(vacio, isA<EliminarArticuloFisicamenteMotivoRequerido>());
      final espacios = await eliminar.ejecutar(articuloId: 'cualquiera', motivo: '  ');
      expect(espacios, isA<EliminarArticuloFisicamenteMotivoRequerido>());
    });

    test('TieneDependencias — al menos una unidad serializada registrada', () async {
      final articulo = await crearArticuloDePrueba(manejaSerie: true);
      await registrarEntradaUnidad.ejecutar(articuloId: articulo.id, numeroSerie: 'SN-0001', fecha: DateTime(2026, 1, 1));

      final r = await eliminar.ejecutar(articuloId: articulo.id, motivo: 'prueba');
      expect(r, isA<EliminarArticuloFisicamenteTieneDependencias>());
      expect((r as EliminarArticuloFisicamenteTieneDependencias).detalle, contains('1 unidad'));
    });

    test('Exitoso — borra la fila y registra el evento de auditoría con el actor', () async {
      final articulo = await crearArticuloDePrueba();
      final r = await eliminar.ejecutar(
        articuloId: articulo.id,
        motivo: 'Artículo duplicado por error de captura',
        actorUsuarioId: _actorUsuarioId,
      );
      expect(r, isA<EliminarArticuloFisicamenteExitoso>());
      expect(await articuloRepo.obtenerPorId(articulo.id), isNull);

      final evento =
          await (db.select(db.eliminacionFisicaEvento)..where((t) => t.entidadIdOriginal.equals(articulo.id))).getSingle();
      expect(evento.tipoEntidad, 'articulo');
      expect(evento.motivo, 'Artículo duplicado por error de captura');
      expect(evento.actorUsuarioId, _actorUsuarioId);
      final snapshot = jsonDecode(evento.snapshotJson) as Map<String, dynamic>;
      expect(snapshot['id'], articulo.id);
    });

    test('Exitoso con actorUsuarioId null — sesión ausente, el evento se guarda igual', () async {
      final articulo = await crearArticuloDePrueba();
      final r = await eliminar.ejecutar(articuloId: articulo.id, motivo: 'prueba sin sesión');
      expect(r, isA<EliminarArticuloFisicamenteExitoso>());

      final evento =
          await (db.select(db.eliminacionFisicaEvento)..where((t) => t.entidadIdOriginal.equals(articulo.id))).getSingle();
      expect(evento.actorUsuarioId, isNull);
    });
  });

  group('Eliminación física — CategoriaArticulo', () {
    late CategoriaArticuloRepositoryImpl categoriaRepo;
    late CrearCategoriaArticuloUseCase crearCategoria;
    late CrearArticuloUseCase crearArticulo;
    late EliminarCategoriaArticuloFisicamenteUseCase eliminar;

    setUp(() {
      categoriaRepo = CategoriaArticuloRepositoryImpl(db);
      final articuloRepo = ArticuloRepositoryImpl(db);
      crearCategoria = CrearCategoriaArticuloUseCase(categoriaRepo);
      crearArticulo = CrearArticuloUseCase(articuloRepo, categoriaRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db)));
      eliminar = EliminarCategoriaArticuloFisicamenteUseCase(categoriaRepo);
    });

    Future<CategoriaArticuloData> crearCategoriaDePrueba() async {
      final r = await crearCategoria.ejecutar(nombre: 'Radios');
      return (r as CrearCategoriaArticuloExitoso).categoria;
    }

    test('NoExiste cuando el id no existe', () async {
      final r = await eliminar.ejecutar(categoriaArticuloId: 'no-existe', motivo: 'prueba');
      expect(r, isA<EliminarCategoriaArticuloFisicamenteNoExiste>());
    });

    test('MotivoRequerido con motivo vacío o solo espacios', () async {
      final vacio = await eliminar.ejecutar(categoriaArticuloId: 'cualquiera', motivo: '');
      expect(vacio, isA<EliminarCategoriaArticuloFisicamenteMotivoRequerido>());
      final espacios = await eliminar.ejecutar(categoriaArticuloId: 'cualquiera', motivo: '  ');
      expect(espacios, isA<EliminarCategoriaArticuloFisicamenteMotivoRequerido>());
    });

    test('TieneDependencias — al menos un artículo registrado', () async {
      final categoria = await crearCategoriaDePrueba();
      await crearArticulo.ejecutar(categoriaId: categoria.id, nombre: 'Radio', manejaVariante: false, manejaSerie: false);

      final r = await eliminar.ejecutar(categoriaArticuloId: categoria.id, motivo: 'prueba');
      expect(r, isA<EliminarCategoriaArticuloFisicamenteTieneDependencias>());
      expect((r as EliminarCategoriaArticuloFisicamenteTieneDependencias).detalle, contains('1 artículo'));
    });

    test('Exitoso — borra la fila y registra el evento de auditoría con el actor', () async {
      final categoria = await crearCategoriaDePrueba();
      final r = await eliminar.ejecutar(
        categoriaArticuloId: categoria.id,
        motivo: 'Categoría duplicada por error de captura',
        actorUsuarioId: _actorUsuarioId,
      );
      expect(r, isA<EliminarCategoriaArticuloFisicamenteExitoso>());
      expect(await categoriaRepo.obtenerPorId(categoria.id), isNull);

      final evento =
          await (db.select(db.eliminacionFisicaEvento)..where((t) => t.entidadIdOriginal.equals(categoria.id))).getSingle();
      expect(evento.tipoEntidad, 'categoriaArticulo');
      expect(evento.motivo, 'Categoría duplicada por error de captura');
      expect(evento.actorUsuarioId, _actorUsuarioId);
      final snapshot = jsonDecode(evento.snapshotJson) as Map<String, dynamic>;
      expect(snapshot['id'], categoria.id);
    });

    test('Exitoso con actorUsuarioId null — sesión ausente, el evento se guarda igual', () async {
      final categoria = await crearCategoriaDePrueba();
      final r = await eliminar.ejecutar(categoriaArticuloId: categoria.id, motivo: 'prueba sin sesión');
      expect(r, isA<EliminarCategoriaArticuloFisicamenteExitoso>());

      final evento =
          await (db.select(db.eliminacionFisicaEvento)..where((t) => t.entidadIdOriginal.equals(categoria.id))).getSingle();
      expect(evento.actorUsuarioId, isNull);
    });
  });

  group('Eliminación física — Area', () {
    late AreaRepositoryImpl areaRepo;
    late PuestoRepositoryImpl puestoRepo;
    late CrearAreaUseCase crearArea;
    late EliminarAreaFisicamenteUseCase eliminar;

    setUp(() {
      areaRepo = AreaRepositoryImpl(db);
      puestoRepo = PuestoRepositoryImpl(db);
      crearArea = CrearAreaUseCase(areaRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db)));
      eliminar = EliminarAreaFisicamenteUseCase(areaRepo);
    });

    Future<AreaData> crearAreaDePrueba() async {
      final r = await crearArea.ejecutar(nombre: 'Calidad');
      return (r as GuardarAreaExitoso).area;
    }

    test('NoExiste cuando el id no existe', () async {
      final r = await eliminar.ejecutar(areaId: 'no-existe', motivo: 'prueba');
      expect(r, isA<EliminarAreaFisicamenteNoExiste>());
    });

    test('MotivoRequerido con motivo vacío o solo espacios', () async {
      final vacio = await eliminar.ejecutar(areaId: 'cualquiera', motivo: '');
      expect(vacio, isA<EliminarAreaFisicamenteMotivoRequerido>());
      final espacios = await eliminar.ejecutar(areaId: 'cualquiera', motivo: '  ');
      expect(espacios, isA<EliminarAreaFisicamenteMotivoRequerido>());
    });

    test('TieneDependencias — al menos un puesto registrado', () async {
      final area = await crearAreaDePrueba();
      await puestoRepo.crear(
        PuestoCompanion.insert(codigo: 'PUE-9001', nombre: 'Guardia', areaId: area.id, tipo: 'operativo', nivelJerarquico: 1),
      );

      final r = await eliminar.ejecutar(areaId: area.id, motivo: 'prueba');
      expect(r, isA<EliminarAreaFisicamenteTieneDependencias>());
      expect((r as EliminarAreaFisicamenteTieneDependencias).detalle, contains('1 puesto'));
    });

    test('Exitoso — borra la fila y registra el evento de auditoría con el actor', () async {
      final area = await crearAreaDePrueba();
      final r = await eliminar.ejecutar(
        areaId: area.id,
        motivo: 'Área duplicada por error de captura',
        actorUsuarioId: _actorUsuarioId,
      );
      expect(r, isA<EliminarAreaFisicamenteExitoso>());
      expect(await areaRepo.obtenerPorId(area.id), isNull);

      final evento = await (db.select(db.eliminacionFisicaEvento)..where((t) => t.entidadIdOriginal.equals(area.id))).getSingle();
      expect(evento.tipoEntidad, 'area');
      expect(evento.motivo, 'Área duplicada por error de captura');
      expect(evento.actorUsuarioId, _actorUsuarioId);
      final snapshot = jsonDecode(evento.snapshotJson) as Map<String, dynamic>;
      expect(snapshot['id'], area.id);
    });

    test('Exitoso con actorUsuarioId null — sesión ausente, el evento se guarda igual', () async {
      final area = await crearAreaDePrueba();
      final r = await eliminar.ejecutar(areaId: area.id, motivo: 'prueba sin sesión');
      expect(r, isA<EliminarAreaFisicamenteExitoso>());

      final evento = await (db.select(db.eliminacionFisicaEvento)..where((t) => t.entidadIdOriginal.equals(area.id))).getSingle();
      expect(evento.actorUsuarioId, isNull);
    });
  });

  group('Eliminación física — Puesto', () {
    late PuestoRepositoryImpl puestoRepo;
    late ClienteRepositoryImpl clienteRepo;
    late CrearServicioUseCase crearServicio;
    late CrearLineaComercialUseCase crearLineaComercial;
    late EliminarPuestoFisicamenteUseCase eliminar;

    setUp(() {
      puestoRepo = PuestoRepositoryImpl(db);
      clienteRepo = ClienteRepositoryImpl(db);
      final servicioRepo = ServicioRepositoryImpl(db, AsignacionServicioRepositoryImpl(db));
      final catalogoRepo = CatalogoRepositoryImpl(db);
      final comercialRepo = ServicioComercialRepositoryImpl(db);
      final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
      final servicioValidator = ServicioValidator(clienteRepo, catalogoRepo);
      final lineaComercialValidator =
          LineaComercialValidator(puestoRepo, catalogoRepo, servicioRepo, ConfiguracionCobroRepositoryImpl(db));

      crearServicio = CrearServicioUseCase(servicioRepo, generarCodigo, servicioValidator);
      crearLineaComercial = CrearLineaComercialUseCase(comercialRepo, servicioRepo, lineaComercialValidator);
      eliminar = EliminarPuestoFisicamenteUseCase(puestoRepo);
    });

    Future<PuestoData> crearPuestoDePrueba({String codigo = 'PUE-9101'}) {
      return puestoRepo.crear(
        PuestoCompanion.insert(codigo: codigo, nombre: 'Guardia', areaId: SeedIds.areaOperaciones, tipo: 'operativo', nivelJerarquico: 1),
      );
    }

    test('NoExiste cuando el id no existe', () async {
      final r = await eliminar.ejecutar(puestoId: 'no-existe', motivo: 'prueba');
      expect(r, isA<EliminarPuestoFisicamenteNoExiste>());
    });

    test('MotivoRequerido con motivo vacío o solo espacios', () async {
      final vacio = await eliminar.ejecutar(puestoId: 'cualquiera', motivo: '');
      expect(vacio, isA<EliminarPuestoFisicamenteMotivoRequerido>());
      final espacios = await eliminar.ejecutar(puestoId: 'cualquiera', motivo: '  ');
      expect(espacios, isA<EliminarPuestoFisicamenteMotivoRequerido>());
    });

    test('TieneDependencias — al menos una vigencia comercial registrada', () async {
      final puesto = await crearPuestoDePrueba();
      final cliente = await clienteRepo.crear(ClienteCompanion.insert(codigo: 'CLI-9101', nombreComercial: 'Sportium'));
      final servicioResultado = await crearServicio.ejecutar(
        clienteId: cliente.id,
        borrador: ServicioBorrador(
          nombre: 'Vigilancia Sportium',
          tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
          fechaInicio: DateTime(2026, 1, 1),
        ),
      );
      final servicio = (servicioResultado as GuardarServicioExitoso).servicio;

      await crearLineaComercial.ejecutar(
        servicioId: servicio.id,
        borrador: LineaComercialBorrador(
          puestoId: puesto.id,
          modalidadTurnoId: SeedIds.modalidadTurno24x24,
          cantidadElementos: 2,
          precioUnitario: 1500000,
          tratamientoIva: TratamientoIva.masIva,
          fechaInicioVigencia: DateTime(2026, 1, 1),
        ),
      );

      final r = await eliminar.ejecutar(puestoId: puesto.id, motivo: 'prueba');
      expect(r, isA<EliminarPuestoFisicamenteTieneDependencias>());
      expect((r as EliminarPuestoFisicamenteTieneDependencias).detalle, contains('1 vigencia'));
    });

    test('Exitoso — borra la fila y registra el evento de auditoría con el actor', () async {
      final puesto = await crearPuestoDePrueba();
      final r = await eliminar.ejecutar(
        puestoId: puesto.id,
        motivo: 'Puesto duplicado por error de captura',
        actorUsuarioId: _actorUsuarioId,
      );
      expect(r, isA<EliminarPuestoFisicamenteExitoso>());
      expect(await puestoRepo.obtenerPorId(puesto.id), isNull);

      final evento =
          await (db.select(db.eliminacionFisicaEvento)..where((t) => t.entidadIdOriginal.equals(puesto.id))).getSingle();
      expect(evento.tipoEntidad, 'puesto');
      expect(evento.motivo, 'Puesto duplicado por error de captura');
      expect(evento.actorUsuarioId, _actorUsuarioId);
      final snapshot = jsonDecode(evento.snapshotJson) as Map<String, dynamic>;
      expect(snapshot['id'], puesto.id);
    });

    test('Exitoso con actorUsuarioId null — sesión ausente, el evento se guarda igual', () async {
      final puesto = await crearPuestoDePrueba();
      final r = await eliminar.ejecutar(puestoId: puesto.id, motivo: 'prueba sin sesión');
      expect(r, isA<EliminarPuestoFisicamenteExitoso>());

      final evento =
          await (db.select(db.eliminacionFisicaEvento)..where((t) => t.entidadIdOriginal.equals(puesto.id))).getSingle();
      expect(evento.actorUsuarioId, isNull);
    });
  });

  // Sucursal: sin caso Exitoso — ver el doc comment de
  // `EliminarSucursalFisicamenteTieneDependencias` en el test siguiente.
  group('Eliminación física — Sucursal', () {
    late SucursalRepositoryImpl sucursalRepo;
    late CrearSucursalUseCase crearSucursal;
    late EliminarSucursalFisicamenteUseCase eliminar;

    setUp(() {
      sucursalRepo = SucursalRepositoryImpl(db);
      crearSucursal = CrearSucursalUseCase(sucursalRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db)));
      eliminar = EliminarSucursalFisicamenteUseCase(sucursalRepo);
    });

    test('NoExiste cuando el id no existe', () async {
      final r = await eliminar.ejecutar(sucursalId: 'no-existe', motivo: 'prueba');
      expect(r, isA<EliminarSucursalFisicamenteNoExiste>());
    });

    test('MotivoRequerido con motivo vacío o solo espacios', () async {
      final vacio = await eliminar.ejecutar(sucursalId: 'cualquiera', motivo: '');
      expect(vacio, isA<EliminarSucursalFisicamenteMotivoRequerido>());
      final espacios = await eliminar.ejecutar(sucursalId: 'cualquiera', motivo: '  ');
      expect(espacios, isA<EliminarSucursalFisicamenteMotivoRequerido>());
    });

    test(
      'TieneDependencias — cualquier Sucursal creada por el flujo normal siempre la dispara: '
      'SucursalRepositoryImpl.crear inserta transaccionalmente una Ubicación raíz + su Almacén '
      'General, así que no hay ningún camino real para llegar a un caso Exitoso con '
      'CrearSucursalUseCase (confirmado, fuera de alcance de esta suite)',
      () async {
        final resultado =
            await crearSucursal.ejecutar(nombre: 'Sucursal Norte', tipoSucursalId: SeedIds.tipoSucursalBaseOperativa);
        late String sucursalId;
        resultado.when(ok: (s) => sucursalId = s.id, failure: (_) => fail('no debería fallar'));

        final r = await eliminar.ejecutar(sucursalId: sucursalId, motivo: 'prueba');
        expect(r, isA<EliminarSucursalFisicamenteTieneDependencias>());
        expect((r as EliminarSucursalFisicamenteTieneDependencias).detalle, contains('ubicación'));
      },
    );
  });

  // --- Estructural: la facultad es Maestro-only, independiente de
  // cualquier permiso dinámico (Etapa 11D) ---
  group('Frontera Maestro-only — independiente de permisos dinámicos', () {
    SesionUsuario sesionConPermisoInventado(Set<String> permisos) => SesionUsuario(
          usuarioId: _actorUsuarioId,
          nombre: 'Usuario de prueba',
          nombreUsuario: 'usuario-prueba',
          esMaestro: false,
          permisos: permisos,
        );

    const sesionMaestroSinPermisos = SesionUsuario(
      usuarioId: 'maestro-prueba',
      nombre: 'Maestro de prueba',
      nombreUsuario: 'maestro-prueba',
      esMaestro: true,
      permisos: {},
    );

    setUp(() async {
      await db.into(db.usuario).insert(
            UsuarioCompanion.insert(
              id: const Value('maestro-prueba'),
              nombre: 'Maestro de prueba',
              nombreUsuario: 'maestro-prueba',
              passwordHash: 'x',
            ),
          );
    });

    test('Vehiculo — un no-Maestro con un código de permiso inventado ("vehiculos.eliminar") sigue '
        'rechazado, porque exigirMaestro nunca consulta PermisoUsuario/hasCode', () async {
      final container = _container(db, sesionConPermisoInventado({'vehiculos.eliminar'}));
      final resultado =
          await container.read(eliminarVehiculoFisicamenteAutorizadoProvider)(vehiculoId: 'no-existe', motivo: 'prueba');

      expect(resultado, isA<EliminarVehiculoFisicamenteErrorInesperado>());
      expect((resultado as EliminarVehiculoFisicamenteErrorInesperado).mensaje, 'Esta acción requiere el Usuario Maestro.');
    });

    test('Vehiculo — un Maestro sin ninguna fila de PermisoUsuario sí pasa (llega al dominio real)', () async {
      final container = _container(db, sesionMaestroSinPermisos);
      final resultado =
          await container.read(eliminarVehiculoFisicamenteAutorizadoProvider)(vehiculoId: 'no-existe', motivo: 'prueba');

      expect(resultado, isNot(isA<EliminarVehiculoFisicamenteErrorInesperado>()));
      expect(resultado, isA<EliminarVehiculoFisicamenteNoExiste>());
    });

    test('Articulo — un no-Maestro con un código de permiso inventado ("inventario.eliminar") sigue '
        'rechazado, porque exigirMaestro nunca consulta PermisoUsuario/hasCode', () async {
      final container = _container(db, sesionConPermisoInventado({'inventario.eliminar'}));
      final resultado =
          await container.read(eliminarArticuloFisicamenteAutorizadoProvider)(articuloId: 'no-existe', motivo: 'prueba');

      expect(resultado, isA<EliminarArticuloFisicamenteErrorInesperado>());
      expect((resultado as EliminarArticuloFisicamenteErrorInesperado).mensaje, 'Esta acción requiere el Usuario Maestro.');
    });

    test('Articulo — un Maestro sin ninguna fila de PermisoUsuario sí pasa (llega al dominio real)', () async {
      final container = _container(db, sesionMaestroSinPermisos);
      final resultado =
          await container.read(eliminarArticuloFisicamenteAutorizadoProvider)(articuloId: 'no-existe', motivo: 'prueba');

      expect(resultado, isNot(isA<EliminarArticuloFisicamenteErrorInesperado>()));
      expect(resultado, isA<EliminarArticuloFisicamenteNoExiste>());
    });

    test('RegularizarArticuloSerializado — un no-Maestro con un código de permiso inventado '
        '("inventario.modificar") sigue rechazado, porque exigirMaestro nunca consulta PermisoUsuario/hasCode', () async {
      final container = _container(db, sesionConPermisoInventado({'inventario.modificar'}));
      final resultado = await container.read(regularizarArticuloSerializadoAutorizadoProvider)(
        articuloId: 'no-existe',
        movimientoInventarioId: 'no-existe',
        unidades: const [],
      );

      expect(resultado, isA<RegularizarArticuloSerializadoErrorInesperado>());
      expect((resultado as RegularizarArticuloSerializadoErrorInesperado).mensaje, 'Esta acción requiere el Usuario Maestro.');
    });

    test('RegularizarArticuloSerializado — un Maestro sin ninguna fila de PermisoUsuario sí pasa (llega al dominio real)', () async {
      final container = _container(db, sesionMaestroSinPermisos);
      final resultado = await container.read(regularizarArticuloSerializadoAutorizadoProvider)(
        articuloId: 'no-existe',
        movimientoInventarioId: 'no-existe',
        unidades: const [],
      );

      expect(resultado, isNot(isA<RegularizarArticuloSerializadoErrorInesperado>()));
      expect(resultado, isA<RegularizarArticuloSerializadoArticuloNoExiste>());
    });
  });
}
