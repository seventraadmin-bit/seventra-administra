import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/core/validation/direccion_validator.dart';
import 'package:riseg_one/features/organizacion/data/repositories/sucursal_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/sucursal_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_sucursal_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/sucursal_expediente_input.dart';
import 'package:riseg_one/features/organizacion/presentation/sucursales/sucursal_expediente_controller.dart';
import 'package:riseg_one/features/organizacion/presentation/sucursales/sucursal_expediente_state.dart';
import 'package:riseg_one/features/organizacion/presentation/sucursales/sucursales_list_controller.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import '../../../support/sesion_en_base.dart';

const _datosGeneralesValidos = SucursalDatosGeneralesInput(nombre: 'Sucursal Norte', tipoSucursalId: '');

/// Sesión Maestro fija — Etapa 11C activó autorización real en
/// `SucursalExpedienteController`; sin este override todas las acciones
/// serían rechazadas por `AuthorizationService` (mismo criterio que
/// `areas_list_screen_test.dart`).
class _SesionControllerDePrueba extends SesionController {
  @override
  SesionUsuario? build() {
    return const SesionUsuario(
      usuarioId: 'usuario-prueba',
      nombre: 'Usuario de prueba',
      nombreUsuario: 'prueba',
      esMaestro: true,
      permisos: {},
    );
  }
}

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late String sucursalId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final crear = CrearSucursalUseCase(
      SucursalRepositoryImpl(db),
      GenerarCodigoUseCase(CodigoSecuenciaService(db)),
    );
    final creada = await crear.ejecutar(nombre: 'Sucursal Norte', tipoSucursalId: SeedIds.tipoSucursalBaseOperativa);
    sucursalId = creada.when(ok: (s) => s.id, failure: (f) => throw StateError(f.message));

    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(_SesionControllerDePrueba.new),
      ],
    );
    addTearDown(container.dispose);
    container.listen(sucursalExpedienteControllerProvider(sucursalId), (_, _) {});
    // Etapa 3B: autorizar revalida contra la base, así que la
    // sesión de esta prueba tiene que corresponder a una cuenta real.
    await sembrarSesionEnBase(db, const SesionUsuario( usuarioId: 'usuario-prueba', nombre: 'Usuario de prueba', nombreUsuario: 'prueba', esMaestro: true, permisos: {}, ));
  });

  tearDown(() => db.close());

  Future<void> esperarCargaInicial() async {
    while (container.read(sucursalExpedienteControllerProvider(sucursalId)).cargando) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('carga inicial resuelve la Sucursal creada', () async {
    await esperarCargaInicial();
    final state = container.read(sucursalExpedienteControllerProvider(sucursalId));

    expect(state.cargando, isFalse);
    expect(state.errorCarga, isNull);
    expect(state.datos?.sucursal.nombre, 'Sucursal Norte');
    expect(state.modo, SucursalExpedienteModo.consulta);
    expect(state.tipos, isNotEmpty);
  });

  test('entrarModoEdicion cambia a edición y limpia errores previos', () async {
    await esperarCargaInicial();
    final notifier = container.read(sucursalExpedienteControllerProvider(sucursalId).notifier);

    notifier.entrarModoEdicion();

    final state = container.read(sucursalExpedienteControllerProvider(sucursalId));
    expect(state.modo, SucursalExpedienteModo.edicion);
    expect(state.tieneCambiosSinGuardar, isFalse);
  });

  test('marcarCambiosSinGuardar activa el indicador de cambios sin guardar', () async {
    await esperarCargaInicial();
    final notifier = container.read(sucursalExpedienteControllerProvider(sucursalId).notifier);
    notifier.entrarModoEdicion();

    notifier.marcarCambiosSinGuardar();

    expect(container.read(sucursalExpedienteControllerProvider(sucursalId)).tieneCambiosSinGuardar, isTrue);
  });

  test('cancelarEdicion regresa a consulta y limpia el indicador de cambios', () async {
    await esperarCargaInicial();
    final notifier = container.read(sucursalExpedienteControllerProvider(sucursalId).notifier);
    notifier.entrarModoEdicion();
    notifier.marcarCambiosSinGuardar();

    notifier.cancelarEdicion();

    final state = container.read(sucursalExpedienteControllerProvider(sucursalId));
    expect(state.modo, SucursalExpedienteModo.consulta);
    expect(state.tieneCambiosSinGuardar, isFalse);
  });

  test('guardar con datos válidos persiste y regresa a consulta', () async {
    await esperarCargaInicial();
    final notifier = container.read(sucursalExpedienteControllerProvider(sucursalId).notifier);
    notifier.entrarModoEdicion();

    final exito = await notifier.guardar(
      const SucursalExpedienteInput(
        datosGenerales: SucursalDatosGeneralesInput(
          nombre: 'Sucursal Norte Renombrada',
          tipoSucursalId: SeedIds.tipoSucursalBodega,
        ),
        direccionPrincipal: DireccionBorrador(
          calle: 'Reforma',
          numeroExterior: '123',
          colonia: 'Centro',
          municipioAlcaldia: 'Cuauhtémoc',
          estado: 'CDMX',
          codigoPostal: '06000',
        ),
      ),
    );

    expect(exito, isTrue);
    final state = container.read(sucursalExpedienteControllerProvider(sucursalId));
    expect(state.modo, SucursalExpedienteModo.consulta);
    expect(state.guardando, isFalse);
    expect(state.datos?.sucursal.nombre, 'Sucursal Norte Renombrada');
    expect(state.datos?.direccionPrincipal?.calle, 'Reforma');
  });

  test('guardar con tipo vacío reporta el error estructurado sin persistir', () async {
    await esperarCargaInicial();
    final notifier = container.read(sucursalExpedienteControllerProvider(sucursalId).notifier);
    notifier.entrarModoEdicion();

    final exito = await notifier.guardar(
      const SucursalExpedienteInput(datosGenerales: _datosGeneralesValidos),
    );

    expect(exito, isFalse);
    final state = container.read(sucursalExpedienteControllerProvider(sucursalId));
    expect(state.modo, SucursalExpedienteModo.edicion);
    expect(state.erroresGuardado, isNotEmpty);
  });

  test('una segunda llamada a guardar mientras la primera está en curso se ignora', () async {
    await esperarCargaInicial();
    final notifier = container.read(sucursalExpedienteControllerProvider(sucursalId).notifier);
    notifier.entrarModoEdicion();
    const input = SucursalExpedienteInput(
      datosGenerales: SucursalDatosGeneralesInput(nombre: 'X', tipoSucursalId: SeedIds.tipoSucursalBodega),
    );

    final primera = notifier.guardar(input);
    expect(container.read(sucursalExpedienteControllerProvider(sucursalId)).guardando, isTrue);

    final segunda = await notifier.guardar(input);
    expect(segunda, isFalse);

    expect(await primera, isTrue);
  });

  test('cambiarEstadoOperativo actualiza el estado y refleja el cambio', () async {
    await esperarCargaInicial();
    final notifier = container.read(sucursalExpedienteControllerProvider(sucursalId).notifier);

    final exito = await notifier.cambiarEstadoOperativo(EstadoOperativoSucursal.cerradaTemporalmente);

    expect(exito, isTrue);
    final state = container.read(sucursalExpedienteControllerProvider(sucursalId));
    expect(state.datos?.sucursal.estadoOperativo, EstadoOperativoSucursal.cerradaTemporalmente.name);
    expect(state.cambiandoEstadoOperativo, isFalse);
  });

  // Hallazgo real (mismo patrón que `ServicioExpedienteController`/
  // `ClienteExpedienteController`): un cambio de estado operativo desde
  // el expediente seguía viendo el estado previo en el listado hasta
  // navegar a otra pestaña y volver.
  test('cambiarEstadoOperativo refleja el nuevo estado en el listado sin recargar manualmente', () async {
    await esperarCargaInicial();
    container.listen(sucursalesListControllerProvider, (_, _) {});
    while (container.read(sucursalesListControllerProvider).cargando) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(
      container.read(sucursalesListControllerProvider).sucursales.singleWhere((s) => s.id == sucursalId).estadoOperativo,
      EstadoOperativoSucursal.operando.name,
    );

    final notifier = container.read(sucursalExpedienteControllerProvider(sucursalId).notifier);
    final exito = await notifier.cambiarEstadoOperativo(EstadoOperativoSucursal.cerradaTemporalmente);
    expect(exito, isTrue);

    await Future<void>.delayed(Duration.zero);
    while (container.read(sucursalesListControllerProvider).cargando) {
      await Future<void>.delayed(Duration.zero);
    }

    expect(
      container.read(sucursalesListControllerProvider).sucursales.singleWhere((s) => s.id == sucursalId).estadoOperativo,
      EstadoOperativoSucursal.cerradaTemporalmente.name,
    );
  });

  test('reintentarCarga vuelve a intentar tras un error de carga', () async {
    await esperarCargaInicial();
    final notifier = container.read(sucursalExpedienteControllerProvider(sucursalId).notifier);

    await notifier.reintentarCarga();

    final state = container.read(sucursalExpedienteControllerProvider(sucursalId));
    expect(state.cargando, isFalse);
    expect(state.datos, isNotNull);
  });
}
