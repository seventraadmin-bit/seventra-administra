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
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/attachments/attachment_repository.dart';
import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/core/di/providers.dart';

import 'package:riseg_one/features/finanzas/data/repositories/cuenta_por_cobrar_repository_impl.dart';

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
import 'package:riseg_one/features/organizacion/data/repositories/documento_por_emitir_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/puesto_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_comercial_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/sucursal_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/ubicacion_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_linea_comercial_vigencia_table.dart' show TratamientoIva;
import 'package:riseg_one/features/organizacion/data/tables/ubicacion_table.dart' show TipoUbicacion;
import 'package:riseg_one/features/organizacion/domain/usecases/crear_area_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_cliente_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_linea_comercial_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_sucursal_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/eliminar_area_fisicamente_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/eliminar_cliente_fisicamente_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/eliminar_documento_por_emitir_fisicamente_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/eliminar_puesto_fisicamente_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/eliminar_servicio_fisicamente_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/eliminar_sucursal_fisicamente_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_area_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_servicio_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/linea_comercial_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_validator.dart';
import 'package:riseg_one/features/organizacion/organizacion_providers.dart';

import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/empleado_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/ficha_tecnica_empleado_repository_impl.dart';
import 'package:riseg_one/features/personal/domain/usecases/eliminar_empleado_fisicamente_usecase.dart';
import 'package:riseg_one/features/personal/personal_providers.dart';

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

  // Sucursal (Etapa 15, hallazgo real): la Ubicación raíz + Almacén
  // General automáticos de `crear()` ya NO cuentan como dependencia —
  // ver el doc comment de `SucursalRepositoryImpl.eliminarFisicamente`.
  group('Eliminación física — Sucursal', () {
    late SucursalRepositoryImpl sucursalRepo;
    late UbicacionRepositoryImpl ubicacionRepo;
    late ClienteRepositoryImpl clienteRepo;
    late ServicioRepositoryImpl servicioRepo;
    late CrearSucursalUseCase crearSucursal;
    late CrearServicioUseCase crearServicio;
    late EliminarSucursalFisicamenteUseCase eliminar;

    setUp(() {
      sucursalRepo = SucursalRepositoryImpl(db);
      ubicacionRepo = UbicacionRepositoryImpl(db);
      clienteRepo = ClienteRepositoryImpl(db);
      servicioRepo = ServicioRepositoryImpl(db, AsignacionServicioRepositoryImpl(db));
      final catalogoRepo = CatalogoRepositoryImpl(db);
      final servicioValidator = ServicioValidator(clienteRepo, catalogoRepo);
      crearSucursal = CrearSucursalUseCase(sucursalRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db)));
      crearServicio = CrearServicioUseCase(servicioRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db)), servicioValidator);
      eliminar = EliminarSucursalFisicamenteUseCase(sucursalRepo);
    });

    Future<String> crearSucursalDePrueba({String nombre = 'Sucursal Norte'}) async {
      final resultado = await crearSucursal.ejecutar(nombre: nombre, tipoSucursalId: SeedIds.tipoSucursalBaseOperativa);
      late String sucursalId;
      resultado.when(ok: (s) => sucursalId = s.id, failure: (_) => fail('no debería fallar'));
      return sucursalId;
    }

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
      '1. Exitoso — Sucursal recién creada, solo con su Ubicación raíz + Almacén General '
      'automáticos: ya no queda bloqueada por su propia estructura interna',
      () async {
        final sucursalId = await crearSucursalDePrueba();

        final r = await eliminar.ejecutar(sucursalId: sucursalId, motivo: 'prueba', actorUsuarioId: _actorUsuarioId);
        expect(r, isA<EliminarSucursalFisicamenteExitoso>());
        expect(await sucursalRepo.obtenerPorId(sucursalId), isNull);
      },
    );

    test('2. TieneDependencias — con un Servicio administrado por la Sucursal', () async {
      final sucursalId = await crearSucursalDePrueba();
      final cliente = await clienteRepo.crear(ClienteCompanion.insert(codigo: 'CLI-9201', nombreComercial: 'Sportium'));
      final servicioResultado = await crearServicio.ejecutar(
        clienteId: cliente.id,
        borrador: ServicioBorrador(
          nombre: 'Vigilancia Sportium',
          tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
          fechaInicio: DateTime(2026, 1, 1),
        ),
      );
      final servicio = (servicioResultado as GuardarServicioExitoso).servicio;
      await servicioRepo.asignarSucursalAdministrativa(servicioId: servicio.id, sucursalId: sucursalId);

      final r = await eliminar.ejecutar(sucursalId: sucursalId, motivo: 'prueba');
      expect(r, isA<EliminarSucursalFisicamenteTieneDependencias>());
      expect((r as EliminarSucursalFisicamenteTieneDependencias).detalle, contains('1 servicio'));
    });

    test('3. TieneDependencias — con un Empleado adscrito a la Sucursal', () async {
      final sucursalId = await crearSucursalDePrueba();
      await db.into(db.empleado).insert(
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
              sucursalId: Value(sucursalId),
            ),
          );

      final r = await eliminar.ejecutar(sucursalId: sucursalId, motivo: 'prueba');
      expect(r, isA<EliminarSucursalFisicamenteTieneDependencias>());
      expect((r as EliminarSucursalFisicamenteTieneDependencias).detalle, contains('1 empleado'));
    });

    test('4. TieneDependencias — con un movimiento financiero (Ingreso) de la Sucursal', () async {
      final sucursalId = await crearSucursalDePrueba();
      await db.into(db.ingreso).insert(
            IngresoCompanion.insert(
              folioIngreso: 'ING-TEST-0001',
              monto: 100000,
              fecha: DateTime(2026, 1, 1),
              formaPago: 'efectivo',
              concepto: 'prueba',
              sucursalId: Value(sucursalId),
            ),
          );

      final r = await eliminar.ejecutar(sucursalId: sucursalId, motivo: 'prueba');
      expect(r, isA<EliminarSucursalFisicamenteTieneDependencias>());
      expect((r as EliminarSucursalFisicamenteTieneDependencias).detalle, contains('1 ingreso'));
    });

    test(
      '5. TieneDependencias — una Ubicación real agregada bajo el Almacén General ya no es '
      'solo estructura automática, aunque nunca haya un Servicio/Empleado/movimiento real',
      () async {
        final sucursalId = await crearSucursalDePrueba();
        final raiz = await ubicacionRepo.obtenerRaizDeSucursal(sucursalId);
        final almacenGeneral = (await ubicacionRepo.obtenerHijos(raiz!.id)).single;
        await ubicacionRepo.crearHijo(
          codigo: 'UBI-TEST-0001',
          nombre: 'Oficina de guardias',
          tipo: TipoUbicacion.oficina,
          parentId: almacenGeneral.id,
        );

        final r = await eliminar.ejecutar(sucursalId: sucursalId, motivo: 'prueba');
        expect(r, isA<EliminarSucursalFisicamenteTieneDependencias>());
        expect((r as EliminarSucursalFisicamenteTieneDependencias).detalle, contains('ubicaciones adicionales'));
      },
    );

    test('6. Atomicidad — un bloqueo no borra nada: la Sucursal y sus dos Ubicaciones siguen intactas', () async {
      final sucursalId = await crearSucursalDePrueba();
      final cliente = await clienteRepo.crear(ClienteCompanion.insert(codigo: 'CLI-9202', nombreComercial: 'Sportium'));
      final servicioResultado = await crearServicio.ejecutar(
        clienteId: cliente.id,
        borrador: ServicioBorrador(
          nombre: 'Vigilancia Sportium',
          tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
          fechaInicio: DateTime(2026, 1, 1),
        ),
      );
      final servicio = (servicioResultado as GuardarServicioExitoso).servicio;
      await servicioRepo.asignarSucursalAdministrativa(servicioId: servicio.id, sucursalId: sucursalId);

      final r = await eliminar.ejecutar(sucursalId: sucursalId, motivo: 'prueba');
      expect(r, isA<EliminarSucursalFisicamenteTieneDependencias>());

      expect(await sucursalRepo.obtenerPorId(sucursalId), isNotNull);
      final raiz = await ubicacionRepo.obtenerRaizDeSucursal(sucursalId);
      expect(raiz, isNotNull);
      expect(await ubicacionRepo.obtenerHijos(raiz!.id), hasLength(1));
    });

    test('7. Exitoso — el evento de eliminación conserva la Sucursal y sus dos Ubicaciones en el snapshot', () async {
      final sucursalId = await crearSucursalDePrueba();
      final raiz = await ubicacionRepo.obtenerRaizDeSucursal(sucursalId);
      final almacenGeneralId = (await ubicacionRepo.obtenerHijos(raiz!.id)).single.id;

      final r = await eliminar.ejecutar(sucursalId: sucursalId, motivo: 'prueba', actorUsuarioId: _actorUsuarioId);
      expect(r, isA<EliminarSucursalFisicamenteExitoso>());

      final evento =
          await (db.select(db.eliminacionFisicaEvento)..where((t) => t.entidadIdOriginal.equals(sucursalId))).getSingle();
      expect(evento.tipoEntidad, 'sucursal');
      expect(evento.actorUsuarioId, _actorUsuarioId);
      final snapshot = jsonDecode(evento.snapshotJson) as Map<String, dynamic>;
      expect(snapshot['sucursal']['id'], sucursalId);
      final ubicacionesEliminadas = (snapshot['ubicacionesEliminadas'] as List).cast<Map<String, dynamic>>();
      expect(ubicacionesEliminadas.map((u) => u['id']), containsAll([raiz.id, almacenGeneralId]));
    });

    test('8. Exitoso — no deja Ubicación huérfana: ni la raíz ni el Almacén General sobreviven', () async {
      final sucursalId = await crearSucursalDePrueba();
      final raiz = await ubicacionRepo.obtenerRaizDeSucursal(sucursalId);
      final almacenGeneralId = (await ubicacionRepo.obtenerHijos(raiz!.id)).single.id;

      final r = await eliminar.ejecutar(sucursalId: sucursalId, motivo: 'prueba');
      expect(r, isA<EliminarSucursalFisicamenteExitoso>());

      expect(await ubicacionRepo.obtenerPorId(raiz.id), isNull);
      expect(await ubicacionRepo.obtenerPorId(almacenGeneralId), isNull);
    });

    test('9. Maestro solamente — un no-Maestro con un código de permiso inventado sigue rechazado', () async {
      final container = _container(
        db,
        const SesionUsuario(
          usuarioId: _actorUsuarioId,
          nombre: 'Usuario de prueba',
          nombreUsuario: 'usuario-prueba',
          esMaestro: false,
          permisos: {'organizacion.eliminar'},
        ),
      );
      final resultado =
          await container.read(eliminarSucursalFisicamenteAutorizadoProvider)(sucursalId: 'no-existe', motivo: 'prueba');

      expect(resultado, isA<EliminarSucursalFisicamenteErrorInesperado>());
      expect((resultado as EliminarSucursalFisicamenteErrorInesperado).mensaje, 'Esta acción requiere el Usuario Maestro.');
    });
  });

  // Cliente (Etapa 15, hallazgo de Comercial) — a diferencia de
  // Sucursal/Servicio, `crear` no inserta ninguna fila automática (sin
  // transacción, sin estructura que distinguir): un Cliente recién
  // creado ya es el caso Exitoso.
  group('Eliminación física — Cliente', () {
    late ClienteRepositoryImpl clienteRepo;
    late ServicioRepositoryImpl servicioRepo;
    late CrearClienteUseCase crearCliente;
    late EliminarClienteFisicamenteUseCase eliminar;

    setUp(() {
      clienteRepo = ClienteRepositoryImpl(db);
      servicioRepo = ServicioRepositoryImpl(db, AsignacionServicioRepositoryImpl(db));
      crearCliente = CrearClienteUseCase(clienteRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db)));
      eliminar = EliminarClienteFisicamenteUseCase(clienteRepo);
    });

    Future<String> crearClienteDePrueba({String nombre = 'Sportium'}) async {
      final resultado = await crearCliente.ejecutar(nombreComercial: nombre);
      return resultado.when(ok: (c) => c.id, failure: (f) => throw StateError(f.message));
    }

    test('NoExiste cuando el id no existe', () async {
      final r = await eliminar.ejecutar(clienteId: 'no-existe', motivo: 'prueba');
      expect(r, isA<EliminarClienteFisicamenteNoExiste>());
    });

    test('MotivoRequerido con motivo vacío o solo espacios', () async {
      final vacio = await eliminar.ejecutar(clienteId: 'cualquiera', motivo: '');
      expect(vacio, isA<EliminarClienteFisicamenteMotivoRequerido>());
    });

    test('1. Exitoso — Cliente recién creado, sin dependencias', () async {
      final clienteId = await crearClienteDePrueba();

      final r = await eliminar.ejecutar(clienteId: clienteId, motivo: 'prueba', actorUsuarioId: _actorUsuarioId);
      expect(r, isA<EliminarClienteFisicamenteExitoso>());
      expect(await clienteRepo.obtenerPorId(clienteId), isNull);

      final evento =
          await (db.select(db.eliminacionFisicaEvento)..where((t) => t.entidadIdOriginal.equals(clienteId))).getSingle();
      expect(evento.tipoEntidad, 'cliente');
      expect(evento.actorUsuarioId, _actorUsuarioId);
    });

    test('2. TieneDependencias — con un Servicio', () async {
      final clienteId = await crearClienteDePrueba();
      await servicioRepo.crear(
        codigoServicio: 'SRV-9301',
        clienteId: clienteId,
        nombre: 'Vigilancia Sportium',
        tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
        fechaInicio: DateTime(2026, 1, 1),
        codigoUbicacionRaiz: 'UBI-9301',
      );

      final r = await eliminar.ejecutar(clienteId: clienteId, motivo: 'prueba');
      expect(r, isA<EliminarClienteFisicamenteTieneDependencias>());
      expect((r as EliminarClienteFisicamenteTieneDependencias).detalle, contains('1 servicio'));
    });

    test('3. TieneDependencias — con historia financiera (Pago)', () async {
      final clienteId = await crearClienteDePrueba();
      await db.into(db.pago).insert(
            PagoCompanion.insert(
              folioPago: 'PAG-TEST-0001',
              clienteId: clienteId,
              montoTotal: 100000,
              fechaPago: DateTime(2026, 1, 1),
              formaPago: 'efectivo',
            ),
          );

      final r = await eliminar.ejecutar(clienteId: clienteId, motivo: 'prueba');
      expect(r, isA<EliminarClienteFisicamenteTieneDependencias>());
      expect((r as EliminarClienteFisicamenteTieneDependencias).detalle, contains('1 pago'));
    });

    test('4. Maestro solamente — un no-Maestro con un código de permiso inventado sigue rechazado', () async {
      final container = _container(
        db,
        const SesionUsuario(
          usuarioId: _actorUsuarioId,
          nombre: 'Usuario de prueba',
          nombreUsuario: 'usuario-prueba',
          esMaestro: false,
          permisos: {'comercial.eliminar'},
        ),
      );
      final resultado =
          await container.read(eliminarClienteFisicamenteAutorizadoProvider)(clienteId: 'no-existe', motivo: 'prueba');

      expect(resultado, isA<EliminarClienteFisicamenteErrorInesperado>());
      expect((resultado as EliminarClienteFisicamenteErrorInesperado).mensaje, 'Esta acción requiere el Usuario Maestro.');
    });
  });

  // Servicio (Etapa 15, hallazgo de Comercial) — mismo caso estructural
  // que Sucursal: `crear` inserta automáticamente una Ubicación raíz
  // (sin hijo, a diferencia de Sucursal) — ver el doc comment de
  // `ServicioRepositoryImpl.eliminarFisicamente`.
  group('Eliminación física — Servicio', () {
    late ServicioRepositoryImpl servicioRepo;
    late ServicioComercialRepositoryImpl comercialRepo;
    late PuestoRepositoryImpl puestoRepo;
    late CrearLineaComercialUseCase crearLineaComercial;
    late EliminarServicioFisicamenteUseCase eliminar;
    late String clienteId;

    setUp(() async {
      servicioRepo = ServicioRepositoryImpl(db, AsignacionServicioRepositoryImpl(db));
      final clienteRepo = ClienteRepositoryImpl(db);
      comercialRepo = ServicioComercialRepositoryImpl(db);
      puestoRepo = PuestoRepositoryImpl(db);
      final catalogoRepo = CatalogoRepositoryImpl(db);
      crearLineaComercial = CrearLineaComercialUseCase(
        comercialRepo,
        servicioRepo,
        LineaComercialValidator(puestoRepo, catalogoRepo, servicioRepo, ConfiguracionCobroRepositoryImpl(db)),
      );
      eliminar = EliminarServicioFisicamenteUseCase(servicioRepo);

      final crearCliente = CrearClienteUseCase(clienteRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db)));
      final resultado = await crearCliente.ejecutar(nombreComercial: 'Sportium');
      clienteId = resultado.when(ok: (c) => c.id, failure: (f) => throw StateError(f.message));
    });

    Future<String> crearServicioDePrueba({String codigo = 'SRV-9401'}) async {
      final servicio = await servicioRepo.crear(
        codigoServicio: codigo,
        clienteId: clienteId,
        nombre: 'Vigilancia Sportium',
        tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
        fechaInicio: DateTime(2026, 1, 1),
        codigoUbicacionRaiz: '$codigo-UBI',
      );
      return servicio.id;
    }

    test('NoExiste cuando el id no existe', () async {
      final r = await eliminar.ejecutar(servicioId: 'no-existe', motivo: 'prueba');
      expect(r, isA<EliminarServicioFisicamenteNoExiste>());
    });

    test('1. Exitoso — Servicio recién creado, solo con su Ubicación raíz automática', () async {
      final servicioId = await crearServicioDePrueba();

      final r = await eliminar.ejecutar(servicioId: servicioId, motivo: 'prueba', actorUsuarioId: _actorUsuarioId);
      expect(r, isA<EliminarServicioFisicamenteExitoso>());
      expect(await servicioRepo.obtenerPorId(servicioId), isNull);
    });

    test('2. TieneDependencias — con Personal asignado', () async {
      final servicioId = await crearServicioDePrueba(codigo: 'SRV-9402');
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
      await db.into(db.asignacionServicio).insert(
            AsignacionServicioCompanion.insert(
              empleadoId: empleado.id,
              servicioId: servicioId,
              fechaInicio: DateTime(2026, 1, 5),
            ),
          );

      final r = await eliminar.ejecutar(servicioId: servicioId, motivo: 'prueba');
      expect(r, isA<EliminarServicioFisicamenteTieneDependencias>());
      expect((r as EliminarServicioFisicamenteTieneDependencias).detalle, contains('1 asignación'));
    });

    test('3. TieneDependencias — con Configuración comercial', () async {
      final servicioId = await crearServicioDePrueba(codigo: 'SRV-9403');
      final puesto = await puestoRepo.crear(
        PuestoCompanion.insert(codigo: 'PUE-9403', nombre: 'Guardia', areaId: SeedIds.areaOperaciones, tipo: 'operativo', nivelJerarquico: 1),
      );
      await crearLineaComercial.ejecutar(
        servicioId: servicioId,
        borrador: LineaComercialBorrador(
          puestoId: puesto.id,
          modalidadTurnoId: SeedIds.modalidadTurno24x24,
          cantidadElementos: 2,
          precioUnitario: 1500000,
          tratamientoIva: TratamientoIva.masIva,
          fechaInicioVigencia: DateTime(2026, 1, 1),
        ),
      );

      final r = await eliminar.ejecutar(servicioId: servicioId, motivo: 'prueba');
      expect(r, isA<EliminarServicioFisicamenteTieneDependencias>());
      expect((r as EliminarServicioFisicamenteTieneDependencias).detalle, contains('1 línea'));
    });

    test('4. TieneDependencias — con Configuración de cobro', () async {
      final servicioId = await crearServicioDePrueba(codigo: 'SRV-9404');
      await db.into(db.configuracionCobro).insert(ConfiguracionCobroCompanion.insert(servicioId: servicioId));

      final r = await eliminar.ejecutar(servicioId: servicioId, motivo: 'prueba');
      expect(r, isA<EliminarServicioFisicamenteTieneDependencias>());
      expect((r as EliminarServicioFisicamenteTieneDependencias).detalle, contains('configuración de cobro'));
    });

    test('5. Maestro solamente — un no-Maestro con un código de permiso inventado sigue rechazado', () async {
      final container = _container(
        db,
        const SesionUsuario(
          usuarioId: _actorUsuarioId,
          nombre: 'Usuario de prueba',
          nombreUsuario: 'usuario-prueba',
          esMaestro: false,
          permisos: {'comercial.eliminar'},
        ),
      );
      final resultado =
          await container.read(eliminarServicioFisicamenteAutorizadoProvider)(servicioId: 'no-existe', motivo: 'prueba');

      expect(resultado, isA<EliminarServicioFisicamenteErrorInesperado>());
      expect((resultado as EliminarServicioFisicamenteErrorInesperado).mensaje, 'Esta acción requiere el Usuario Maestro.');
    });
  });

  group('Eliminación física — DocumentoPorEmitir', () {
    late ClienteRepositoryImpl clienteRepo;
    late DocumentoPorEmitirRepositoryImpl documentoRepo;
    late EliminarDocumentoPorEmitirFisicamenteUseCase eliminar;
    late String clienteId;

    setUp(() async {
      clienteRepo = ClienteRepositoryImpl(db);
      documentoRepo = DocumentoPorEmitirRepositoryImpl(
        db,
        AttachmentRepository(db),
        CuentaPorCobrarRepositoryImpl(db),
      );
      eliminar = EliminarDocumentoPorEmitirFisicamenteUseCase(documentoRepo);

      final crearCliente = CrearClienteUseCase(clienteRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db)));
      final resultado = await crearCliente.ejecutar(nombreComercial: 'Sportium');
      clienteId = resultado.when(ok: (c) => c.id, failure: (f) => throw StateError(f.message));
    });

    Future<String> crearDocumentoDePrueba({String codigo = 'DOC-9501', String estatus = 'cancelado'}) async {
      final documento = await db.into(db.documentoPorEmitir).insertReturning(
            DocumentoPorEmitirCompanion.insert(
              codigo: codigo,
              clienteId: clienteId,
              tipoDocumento: 'reciboDePago',
              agrupacion: 'porServicio',
              metodo: 'noAplica',
              periodoInicio: DateTime(2026, 1, 1),
              periodoFin: DateTime(2026, 1, 31),
              generationKey: 'GK-$codigo',
              importeBaseEsperado: 2180000,
              importeFinalEsperado: 2180000,
              estatus: Value(estatus),
            ),
          );
      return documento.id;
    }

    test('NoExiste cuando el id no existe', () async {
      final r = await eliminar.ejecutar(documentoPorEmitirId: 'no-existe', motivo: 'prueba');
      expect(r, isA<EliminarDocumentoPorEmitirFisicamenteNoExiste>());
    });

    test('MotivoRequerido con motivo vacío o solo espacios', () async {
      final vacio = await eliminar.ejecutar(documentoPorEmitirId: 'cualquiera', motivo: '   ');
      expect(vacio, isA<EliminarDocumentoPorEmitirFisicamenteMotivoRequerido>());
    });

    test('1. Exitoso — documento Cancelado de prueba, sin dependencias', () async {
      final documentoId = await crearDocumentoDePrueba();

      final r = await eliminar.ejecutar(documentoPorEmitirId: documentoId, motivo: 'prueba', actorUsuarioId: _actorUsuarioId);
      expect(r, isA<EliminarDocumentoPorEmitirFisicamenteExitoso>());
      expect(await documentoRepo.obtenerPorId(documentoId), isNull);

      final evento = await (db.select(db.eliminacionFisicaEvento)..where((t) => t.entidadIdOriginal.equals(documentoId)))
          .getSingle();
      expect(evento.tipoEntidad, 'documentoPorEmitir');
      expect(evento.actorUsuarioId, _actorUsuarioId);
    });

    test('2. Exitoso — documento marcado No requerido, sin dependencias', () async {
      final documentoId = await crearDocumentoDePrueba(codigo: 'DOC-9502', estatus: 'noRequerido');

      final r = await eliminar.ejecutar(documentoPorEmitirId: documentoId, motivo: 'prueba');
      expect(r, isA<EliminarDocumentoPorEmitirFisicamenteExitoso>());
    });

    test('3. Exitoso — el estatus por sí solo ya no bloquea (Pendiente, sin CxC)', () async {
      final documentoId = await crearDocumentoDePrueba(codigo: 'DOC-9503', estatus: 'pendiente');

      final r = await eliminar.ejecutar(documentoPorEmitirId: documentoId, motivo: 'prueba');
      expect(r, isA<EliminarDocumentoPorEmitirFisicamenteExitoso>());
      expect(await documentoRepo.obtenerPorId(documentoId), isNull);
    });

    test('4. Exitoso — documento Procesado/Aceptado de prueba con CxC pero sin pago aplicado', () async {
      final documentoId = await crearDocumentoDePrueba(codigo: 'DOC-9504', estatus: 'procesadoAceptado');
      await db.into(db.cuentaPorCobrar).insert(
            CuentaPorCobrarCompanion.insert(
              documentoPorEmitirId: documentoId,
              clienteId: clienteId,
              tipoDocumento: 'reciboDePago',
              metodo: 'noAplica',
              fechaEmisionReal: DateTime(2026, 1, 5),
              importeEmitido: 0,
              saldoOriginal: 2180000,
              saldoPendiente: 2180000,
            ),
          );

      final r = await eliminar.ejecutar(documentoPorEmitirId: documentoId, motivo: r'prueba: importe emitido $0');
      expect(r, isA<EliminarDocumentoPorEmitirFisicamenteExitoso>());
      expect(await documentoRepo.obtenerPorId(documentoId), isNull);
      final cxcSigueExistiendo = await (db.select(db.cuentaPorCobrar)..where((t) => t.documentoPorEmitirId.equals(documentoId))).getSingleOrNull();
      expect(cxcSigueExistiendo, isNull, reason: 'la Cuenta por cobrar sin pagos se limpia junto con el documento');
    });

    test('5. Exitoso — documento con adjuntos PDF/XML: se eliminan y no quedan huérfanos', () async {
      final documentoId = await crearDocumentoDePrueba(codigo: 'DOC-9505');
      final tempDir = Directory.systemTemp.createTempSync('riseg_doc_adjuntos_test_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final archivoPdf = File('${tempDir.path}/comprobante.pdf')..writeAsStringSync('pdf de prueba');
      final archivoXml = File('${tempDir.path}/comprobante.xml')..writeAsStringSync('<xml/>');

      final attachmentRepo = AttachmentRepository(db);
      final adjuntoPdf = await attachmentRepo.crear(
        AttachmentCompanion.insert(
          id: 'attachment-9505-pdf',
          originalFileName: 'comprobante.pdf',
          storedFileName: 'uuid-9505.pdf',
          path: archivoPdf.path,
          mimeType: 'application/pdf',
          sizeBytes: archivoPdf.lengthSync(),
        ),
      );
      final adjuntoXml = await attachmentRepo.crear(
        AttachmentCompanion.insert(
          id: 'attachment-9505-xml',
          originalFileName: 'comprobante.xml',
          storedFileName: 'uuid-9505.xml',
          path: archivoXml.path,
          mimeType: 'application/xml',
          sizeBytes: archivoXml.lengthSync(),
        ),
      );
      await db.into(db.documentoPorEmitirAttachment).insert(
            DocumentoPorEmitirAttachmentCompanion.insert(attachmentId: adjuntoPdf.id, documentoPorEmitirId: documentoId),
          );
      await db.into(db.documentoPorEmitirAttachment).insert(
            DocumentoPorEmitirAttachmentCompanion.insert(attachmentId: adjuntoXml.id, documentoPorEmitirId: documentoId),
          );

      final documentoRepoConStorage = DocumentoPorEmitirRepositoryImpl(
        db,
        attachmentRepo,
        CuentaPorCobrarRepositoryImpl(db),
        attachmentStorage: AttachmentStorage(tempDir.path),
      );
      final eliminarConStorage = EliminarDocumentoPorEmitirFisicamenteUseCase(documentoRepoConStorage);

      final r = await eliminarConStorage.ejecutar(documentoPorEmitirId: documentoId, motivo: 'prueba con adjuntos');
      expect(r, isA<EliminarDocumentoPorEmitirFisicamenteExitoso>());
      expect((r as EliminarDocumentoPorEmitirFisicamenteExitoso).archivosNoEliminadosFisicamente, isEmpty);

      expect(await documentoRepo.obtenerPorId(documentoId), isNull);
      expect(await attachmentRepo.obtenerPorId(adjuntoPdf.id), isNull);
      expect(await attachmentRepo.obtenerPorId(adjuntoXml.id), isNull);
      expect(archivoPdf.existsSync(), isFalse, reason: 'el archivo físico no debe quedar huérfano');
      expect(archivoXml.existsSync(), isFalse, reason: 'el archivo físico no debe quedar huérfano');
    });

    test('6. TieneDependencias — con una AplicacionPago ACTIVA (aplicada)', () async {
      final documentoId = await crearDocumentoDePrueba(codigo: 'DOC-9506', estatus: 'procesadoAceptado');
      final cuenta = await db.into(db.cuentaPorCobrar).insertReturning(
            CuentaPorCobrarCompanion.insert(
              documentoPorEmitirId: documentoId,
              clienteId: clienteId,
              tipoDocumento: 'reciboDePago',
              metodo: 'noAplica',
              fechaEmisionReal: DateTime(2026, 1, 5),
              importeEmitido: 2180000,
              saldoOriginal: 2180000,
              saldoPendiente: 0,
            ),
          );
      final pago = await db.into(db.pago).insertReturning(
            PagoCompanion.insert(
              folioPago: 'PAG-9506-0001',
              clienteId: clienteId,
              montoTotal: 2180000,
              fechaPago: DateTime(2026, 1, 6),
              formaPago: 'transferencia',
            ),
          );
      await db.into(db.aplicacionPago).insert(
            AplicacionPagoCompanion.insert(
              pagoId: pago.id,
              cuentaPorCobrarId: cuenta.id,
              monto: 2180000,
              saldoAntes: 2180000,
              saldoDespues: 0,
            ),
          );

      final r = await eliminar.ejecutar(documentoPorEmitirId: documentoId, motivo: 'prueba');
      expect(r, isA<EliminarDocumentoPorEmitirFisicamenteTieneDependencias>());
      expect((r as EliminarDocumentoPorEmitirFisicamenteTieneDependencias).detalle, contains('pago(s) aplicado(s)'));
      expect(await documentoRepo.obtenerPorId(documentoId), isNotNull, reason: 'con dinero real aplicado, nada se borra');
      final cuentaSigueExistiendo = await (db.select(db.cuentaPorCobrar)..where((t) => t.id.equals(cuenta.id))).getSingleOrNull();
      expect(cuentaSigueExistiendo, isNotNull);
    });

    test(
      '6b. Exitoso — AplicacionPago CANCELADA no bloquea (Pago cancelado, sin efecto financiero real; Etapa '
      '15, corrección del hallazgo real de Marlon)',
      () async {
        final documentoId = await crearDocumentoDePrueba(codigo: 'DOC-9507', estatus: 'procesadoAceptado');
        final cuenta = await db.into(db.cuentaPorCobrar).insertReturning(
              CuentaPorCobrarCompanion.insert(
                documentoPorEmitirId: documentoId,
                clienteId: clienteId,
                tipoDocumento: 'reciboDePago',
                metodo: 'noAplica',
                fechaEmisionReal: DateTime(2026, 1, 5),
                importeEmitido: 2180000,
                saldoOriginal: 2180000,
                // Saldo ya revertido — mismo estado real que deja
                // `PagoRepositoryImpl.cancelar` tras cancelar la
                // aplicación: la Cuenta vuelve a Pendiente.
                saldoPendiente: 2180000,
              ),
            );
        final pago = await db.into(db.pago).insertReturning(
              PagoCompanion.insert(
                folioPago: 'PAG-9507-0001',
                clienteId: clienteId,
                montoTotal: 2180000,
                fechaPago: DateTime(2026, 1, 6),
                formaPago: 'transferencia',
                estatus: const Value('cancelado'),
              ),
            );
        await db.into(db.aplicacionPago).insert(
              AplicacionPagoCompanion.insert(
                pagoId: pago.id,
                cuentaPorCobrarId: cuenta.id,
                monto: 2180000,
                saldoAntes: 2180000,
                saldoDespues: 0,
                estatus: const Value('cancelada'),
                motivoCancelacion: const Value('Pago cancelado, duplicado por error'),
              ),
            );

        final r = await eliminar.ejecutar(documentoPorEmitirId: documentoId, motivo: 'prueba de limpieza');
        expect(r, isA<EliminarDocumentoPorEmitirFisicamenteExitoso>());
        expect(await documentoRepo.obtenerPorId(documentoId), isNull);
        final cuentaSigueExistiendo =
            await (db.select(db.cuentaPorCobrar)..where((t) => t.id.equals(cuenta.id))).getSingleOrNull();
        expect(cuentaSigueExistiendo, isNull, reason: 'la CxC se limpia junto con el documento');
        final aplicacionSigueExistiendo =
            await (db.select(db.aplicacionPago)..where((t) => t.cuentaPorCobrarId.equals(cuenta.id))).getSingleOrNull();
        expect(aplicacionSigueExistiendo, isNull, reason: 'la AplicacionPago cancelada se limpia junto con la CxC');
        final pagoSigueExistiendo = await (db.select(db.pago)..where((t) => t.id.equals(pago.id))).getSingleOrNull();
        expect(pagoSigueExistiendo, isNotNull, reason: 'el Pago en sí nunca se toca desde la eliminación del Documento');
      },
    );

    test('7. Maestro solamente — un no-Maestro con un código de permiso inventado sigue rechazado', () async {
      final container = _container(
        db,
        const SesionUsuario(
          usuarioId: _actorUsuarioId,
          nombre: 'Usuario de prueba',
          nombreUsuario: 'usuario-prueba',
          esMaestro: false,
          permisos: {'comercial.eliminar'},
        ),
      );
      final resultado = await container.read(eliminarDocumentoPorEmitirFisicamenteAutorizadoProvider)(
        documentoPorEmitirId: 'no-existe',
        motivo: 'prueba',
      );

      expect(resultado, isA<EliminarDocumentoPorEmitirFisicamenteErrorInesperado>());
      expect(
        (resultado as EliminarDocumentoPorEmitirFisicamenteErrorInesperado).mensaje,
        'Esta acción requiere el Usuario Maestro.',
      );
    });
  });

  group('Eliminación física — Empleado', () {
    late EmpleadoRepositoryImpl empleadoRepo;
    late EliminarEmpleadoFisicamenteUseCase eliminar;
    var numeroEmpleadoContador = 9600;

    setUp(() {
      empleadoRepo = EmpleadoRepositoryImpl(
        db,
        AsignacionServicioRepositoryImpl(db),
        attachmentStorage: AttachmentStorage('.'),
      );
      eliminar = EliminarEmpleadoFisicamenteUseCase(empleadoRepo);
    });

    Future<EmpleadoData> crearEmpleadoDePrueba() async {
      numeroEmpleadoContador += 1;
      return db.into(db.empleado).insertReturning(
            EmpleadoCompanion.insert(
              numeroEmpleado: numeroEmpleadoContador,
              nombres: 'Juan',
              apellidoPaterno: 'Pérez',
              sexo: 'masculino',
              fechaNacimiento: DateTime(1990, 1, 1),
              curp: 'PEXJ900101HDFXXX${numeroEmpleadoContador.toString().padLeft(2, '0')}',
              rfc: 'PEXJ900101AB$numeroEmpleadoContador',
              nss: '1234567890$numeroEmpleadoContador',
              estadoCivil: 'soltero',
              fechaIngreso: DateTime(2026, 1, 1),
              aniosExperienciaSeguridad: 3,
            ),
          );
    }

    Future<String> crearServicioDePrueba({required String codigo}) async {
      final servicioRepo = ServicioRepositoryImpl(db, AsignacionServicioRepositoryImpl(db));
      final clienteRepo = ClienteRepositoryImpl(db);
      final crearCliente = CrearClienteUseCase(clienteRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db)));
      final resultado = await crearCliente.ejecutar(nombreComercial: 'Sportium $codigo');
      final clienteId = resultado.when(ok: (c) => c.id, failure: (f) => throw StateError(f.message));
      final servicio = await servicioRepo.crear(
        codigoServicio: codigo,
        clienteId: clienteId,
        nombre: 'Vigilancia $codigo',
        tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
        fechaInicio: DateTime(2026, 1, 1),
        codigoUbicacionRaiz: '$codigo-UBI',
      );
      return servicio.id;
    }

    Future<ArticuloData> crearArticuloDePrueba({required String nombre}) async {
      final categoriaRepo = CategoriaArticuloRepositoryImpl(db);
      final articuloRepo = ArticuloRepositoryImpl(db);
      final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
      final categoria =
          (await CrearCategoriaArticuloUseCase(categoriaRepo).ejecutar(nombre: 'Cat $nombre') as CrearCategoriaArticuloExitoso)
              .categoria;
      final r = await CrearArticuloUseCase(articuloRepo, categoriaRepo, generarCodigo).ejecutar(
        categoriaId: categoria.id,
        nombre: nombre,
        manejaVariante: false,
        manejaSerie: false,
      );
      return (r as CrearArticuloExitoso).articulo;
    }

    test('NoExiste cuando el id no existe', () async {
      final r = await eliminar.ejecutar(empleadoId: 'no-existe', motivo: 'prueba');
      expect(r, isA<EliminarEmpleadoFisicamenteNoExiste>());
    });

    test('MotivoRequerido con motivo vacío o solo espacios', () async {
      final vacio = await eliminar.ejecutar(empleadoId: 'cualquiera', motivo: '   ');
      expect(vacio, isA<EliminarEmpleadoFisicamenteMotivoRequerido>());
    });

    test('1. Exitoso — Empleado de prueba sin ninguna dependencia real', () async {
      final empleado = await crearEmpleadoDePrueba();

      final r = await eliminar.ejecutar(empleadoId: empleado.id, motivo: 'prueba', actorUsuarioId: _actorUsuarioId);
      expect(r, isA<EliminarEmpleadoFisicamenteExitoso>());
      expect(await empleadoRepo.obtenerPorId(empleado.id), isNull);

      final evento =
          await (db.select(db.eliminacionFisicaEvento)..where((t) => t.entidadIdOriginal.equals(empleado.id))).getSingle();
      expect(evento.tipoEntidad, 'empleado');
      expect(evento.actorUsuarioId, _actorUsuarioId);
    });

    test(
      '2. Exitoso — Empleado con Ficha técnica generada: la Ficha técnica NUNCA bloquea, se limpia junto con el '
      'Empleado (Resolución explícita de Marlon, Etapa 15) — incluye su PDF físico, sin quedar huérfano',
      () async {
        final empleado = await crearEmpleadoDePrueba();
        final tempDir = Directory.systemTemp.createTempSync('riseg_empleado_ficha_test_');
        addTearDown(() => tempDir.deleteSync(recursive: true));
        final archivoPdf = File('${tempDir.path}/ficha.pdf')..writeAsStringSync('pdf de prueba');

        final fichaRepo = FichaTecnicaEmpleadoRepositoryImpl(db);
        final ficha = await fichaRepo.generar(
          empleadoId: empleado.id,
          folio: 'FICHA-9600',
          originalFileName: 'ficha.pdf',
          storedFileName: 'uuid-ficha.pdf',
          path: archivoPdf.path,
          mimeType: 'application/pdf',
          sizeBytes: archivoPdf.lengthSync(),
        );

        final empleadoRepoConStorage = EmpleadoRepositoryImpl(
          db,
          AsignacionServicioRepositoryImpl(db),
          attachmentStorage: AttachmentStorage(tempDir.path),
        );
        final eliminarConStorage = EliminarEmpleadoFisicamenteUseCase(empleadoRepoConStorage);

        final r = await eliminarConStorage.ejecutar(empleadoId: empleado.id, motivo: 'prueba con ficha técnica');
        expect(r, isA<EliminarEmpleadoFisicamenteExitoso>());
        expect((r as EliminarEmpleadoFisicamenteExitoso).archivosNoEliminadosFisicamente, isEmpty);

        expect(await empleadoRepo.obtenerPorId(empleado.id), isNull);
        final fichaSigueExistiendo =
            await (db.select(db.fichaTecnicaEmpleado)..where((t) => t.id.equals(ficha.id))).getSingleOrNull();
        expect(fichaSigueExistiendo, isNull);
        final attachmentRepo = AttachmentRepository(db);
        expect(await attachmentRepo.obtenerPorId(ficha.attachmentId), isNull);
        expect(archivoPdf.existsSync(), isFalse, reason: 'el PDF físico no debe quedar huérfano');
      },
    );

    test('3. TieneDependencias — con historial de Asignación a Servicio', () async {
      final empleado = await crearEmpleadoDePrueba();
      final servicioId = await crearServicioDePrueba(codigo: 'SRV-9601');
      await db.into(db.asignacionServicio).insert(
            AsignacionServicioCompanion.insert(
              empleadoId: empleado.id,
              servicioId: servicioId,
              fechaInicio: DateTime(2026, 1, 5),
            ),
          );

      final r = await eliminar.ejecutar(empleadoId: empleado.id, motivo: 'prueba');
      expect(r, isA<EliminarEmpleadoFisicamenteTieneDependencias>());
    });

    test('4. TieneDependencias — con Nómina generada', () async {
      final empleado = await crearEmpleadoDePrueba();
      final nomina = await db.into(db.nomina).insertReturning(
            NominaCompanion.insert(
              folio: 'NOM-9602',
              anio: 2026,
              mes: 1,
              tipoPeriodo: 'primera',
              fechaInicioPeriodo: DateTime(2026, 1, 1),
              fechaFinPeriodo: DateTime(2026, 1, 15),
              fechaPagoOrdinaria: DateTime(2026, 1, 20),
            ),
          );
      await db.into(db.nominaEmpleado).insert(
            NominaEmpleadoCompanion.insert(
              nominaId: nomina.id,
              empleadoId: empleado.id,
              numeroEmpleado: empleado.numeroEmpleado,
              nombreCompleto: 'Juan Pérez',
              fuenteSueldoUtilizada: 'administrativo',
              diasPagables: 15,
              sueldoMensualUtilizado: 1500000,
              sueldoQuincenalReferencia: 750000,
              pagoPorDia: 50000,
              importeBase: 750000,
              totalAPagar: 750000,
            ),
          );

      final r = await eliminar.ejecutar(empleadoId: empleado.id, motivo: 'prueba');
      expect(r, isA<EliminarEmpleadoFisicamenteTieneDependencias>());
    });

    test('5. TieneDependencias — con resguardo de Inventario', () async {
      final empleado = await crearEmpleadoDePrueba();
      final articulo = await crearArticuloDePrueba(nombre: 'Radio 9603');
      await db.into(db.asignacion).insert(
            AsignacionCompanion.insert(
              articuloId: articulo.id,
              cantidad: 1,
              empleadoId: Value(empleado.id),
              fechaEntrega: DateTime(2026, 1, 5),
            ),
          );

      final r = await eliminar.ejecutar(empleadoId: empleado.id, motivo: 'prueba');
      expect(r, isA<EliminarEmpleadoFisicamenteTieneDependencias>());
    });

    test('6. TieneDependencias — con reclamo de Inventario (daño/pérdida)', () async {
      final empleado = await crearEmpleadoDePrueba();
      final articulo = await crearArticuloDePrueba(nombre: 'Radio 9604');
      final asignacion = await db.into(db.asignacion).insertReturning(
            AsignacionCompanion.insert(
              articuloId: articulo.id,
              cantidad: 1,
              empleadoId: Value(empleado.id),
              fechaEntrega: DateTime(2026, 1, 5),
            ),
          );
      await db.into(db.descuentoInventario).insert(
            DescuentoInventarioCompanion.insert(
              asignacionId: asignacion.id,
              empleadoId: empleado.id,
              motivo: 'dano',
              importe: 50000,
            ),
          );

      final r = await eliminar.ejecutar(empleadoId: empleado.id, motivo: 'prueba');
      expect(r, isA<EliminarEmpleadoFisicamenteTieneDependencias>());
    });

    test('7. TieneDependencias — con Vehículo asignado', () async {
      final empleado = await crearEmpleadoDePrueba();
      final vehiculoRepo = VehiculoRepositoryImpl(db, AsignacionVehiculoRepositoryImpl(db));
      final vehiculo = await CrearVehiculoUseCase(vehiculoRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db)))
          .ejecutar(marca: 'BMW', modelo: '320i', tipoVehiculo: 'sedan');
      final vehiculoId = (vehiculo as CrearVehiculoExitoso).vehiculo.id;
      await db.into(db.asignacionVehiculo).insert(
            AsignacionVehiculoCompanion.insert(
              vehiculoId: vehiculoId,
              empleadoId: Value(empleado.id),
              fechaInicio: DateTime(2026, 1, 5),
            ),
          );

      final r = await eliminar.ejecutar(empleadoId: empleado.id, motivo: 'prueba');
      expect(r, isA<EliminarEmpleadoFisicamenteTieneDependencias>());
    });

    test('8. TieneDependencias — con Línea telefónica asignada', () async {
      final empleado = await crearEmpleadoDePrueba();
      final asignacionLineaRepo = AsignacionLineaTelefonicaRepositoryImpl(db);
      final equipoRepo = LineaTelefonicaEquipoRepositoryImpl(
        db,
        asignacionLineaRepo,
        AsignacionRepositoryImpl(db),
        InventarioRepositoryImpl(db),
      );
      final lineaRepo = LineaTelefonicaRepositoryImpl(db, asignacionLineaRepo, equipoRepo);
      final linea = await CrearLineaTelefonicaUseCase(lineaRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db)))
          .ejecutar(operador: 'telcel', modalidadSim: 'fisica');
      final lineaId = (linea as CrearLineaTelefonicaExitoso).linea.id;
      await db.into(db.asignacionLineaTelefonica).insert(
            AsignacionLineaTelefonicaCompanion.insert(
              lineaTelefonicaId: lineaId,
              empleadoId: Value(empleado.id),
              fechaInicio: DateTime(2026, 1, 5),
            ),
          );

      final r = await eliminar.ejecutar(empleadoId: empleado.id, motivo: 'prueba');
      expect(r, isA<EliminarEmpleadoFisicamenteTieneDependencias>());
    });

    test('Exitoso — el domicilio (Direccion) se limpia junto con el Empleado', () async {
      final empleado = await crearEmpleadoDePrueba();
      await db.into(db.direccion).insert(
            DireccionCompanion.insert(
              empleadoId: Value(empleado.id),
              tipoDireccion: 'domicilio',
              calle: 'Calle Falsa',
              numeroExterior: '123',
              colonia: 'Centro',
              municipioAlcaldia: 'Cuauhtémoc',
              estado: 'CDMX',
              codigoPostal: '06000',
            ),
          );

      final r = await eliminar.ejecutar(empleadoId: empleado.id, motivo: 'prueba');
      expect(r, isA<EliminarEmpleadoFisicamenteExitoso>());
      final domicilioSigueExistiendo =
          await (db.select(db.direccion)..where((t) => t.empleadoId.equals(empleado.id))).getSingleOrNull();
      expect(domicilioSigueExistiendo, isNull);
    });
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

    test('Empleado — un no-Maestro con un código de permiso inventado ("personal.eliminar") sigue '
        'rechazado, porque exigirMaestro nunca consulta PermisoUsuario/hasCode', () async {
      final container = _container(db, sesionConPermisoInventado({'personal.eliminar'}));
      final resultado =
          await container.read(eliminarEmpleadoFisicamenteAutorizadoProvider)(empleadoId: 'no-existe', motivo: 'prueba');

      expect(resultado, isA<EliminarEmpleadoFisicamenteErrorInesperado>());
      expect((resultado as EliminarEmpleadoFisicamenteErrorInesperado).mensaje, 'Esta acción requiere el Usuario Maestro.');
    });

    test('Empleado — un Maestro sin ninguna fila de PermisoUsuario sí pasa (llega al dominio real)', () async {
      // A diferencia de Vehiculo/Articulo, `eliminarEmpleadoFisicamenteUseCaseProvider`
      // sí necesita `AttachmentStorage` (limpia fotografía/documentos/PDFs
      // de fichas técnicas) — `attachmentStorageProvider` requiere
      // `appPathsProvider`, no disponible en pruebas sin sobreescribirlo.
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          sesionControllerProvider.overrideWith(() => _SesionFija(sesionMaestroSinPermisos)),
          attachmentStorageProvider.overrideWithValue(AttachmentStorage('.')),
        ],
      );
      addTearDown(container.dispose);
      final resultado =
          await container.read(eliminarEmpleadoFisicamenteAutorizadoProvider)(empleadoId: 'no-existe', motivo: 'prueba');

      expect(resultado, isNot(isA<EliminarEmpleadoFisicamenteErrorInesperado>()));
      expect(resultado, isA<EliminarEmpleadoFisicamenteNoExiste>());
    });
  });
}
