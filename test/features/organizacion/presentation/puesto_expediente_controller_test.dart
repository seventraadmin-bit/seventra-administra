import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/organizacion/data/repositories/area_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/puesto_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/puesto_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_puesto_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_puesto_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/puesto_errors.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/puesto_validator.dart';
import 'package:riseg_one/features/organizacion/presentation/areas/areas_list_controller.dart';
import 'package:riseg_one/features/organizacion/presentation/puestos/puesto_expediente_controller.dart';
import 'package:riseg_one/features/organizacion/presentation/puestos/puesto_expediente_state.dart';
import 'package:riseg_one/features/organizacion/presentation/puestos/puestos_list_controller.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import '../../../support/sesion_en_base.dart';

const _borradorValido = PuestoBorrador(
  nombre: 'Guardia',
  areaId: SeedIds.areaOperaciones,
  tipo: TipoPuesto.operativo,
  nivelJerarquico: 1,
);

/// Sesión Maestro fija — Etapa 11C activó autorización real en
/// `PuestoExpedienteController`; sin este override todas las acciones
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
  late AreaRepositoryImpl areaRepo;
  late ProviderContainer container;
  late String puestoId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    areaRepo = AreaRepositoryImpl(db);
    final crear = CrearPuestoUseCase(
      PuestoRepositoryImpl(db),
      GenerarCodigoUseCase(CodigoSecuenciaService(db)),
      PuestoValidator(areaRepo),
    );
    final creado = (await crear.ejecutar(_borradorValido)) as GuardarPuestoExitoso;
    puestoId = creado.puesto.id;

    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(_SesionControllerDePrueba.new),
      ],
    );
    addTearDown(container.dispose);
    container.listen(puestoExpedienteControllerProvider(puestoId), (_, _) {});
    // Etapa 3B: autorizar revalida contra la base, así que la
    // sesión de esta prueba tiene que corresponder a una cuenta real.
    await sembrarSesionEnBase(db, SesionUsuario( usuarioId: 'usuario-prueba', nombre: 'Usuario de prueba', nombreUsuario: 'prueba', esMaestro: true, permisos: {}, ));
  });

  tearDown(() => db.close());

  Future<void> esperarCargaInicial() async {
    while (container.read(puestoExpedienteControllerProvider(puestoId)).cargando) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('carga inicial resuelve el Puesto creado y las Áreas activas', () async {
    await esperarCargaInicial();
    final state = container.read(puestoExpedienteControllerProvider(puestoId));

    expect(state.cargando, isFalse);
    expect(state.errorCarga, isNull);
    expect(state.datos?.nombre, 'Guardia');
    expect(state.modo, PuestoExpedienteModo.consulta);
    expect(state.areas, isNotEmpty);
  });

  test('entrarModoEdicion cambia a edición y limpia errores previos', () async {
    await esperarCargaInicial();
    final notifier = container.read(puestoExpedienteControllerProvider(puestoId).notifier);

    notifier.entrarModoEdicion();

    final state = container.read(puestoExpedienteControllerProvider(puestoId));
    expect(state.modo, PuestoExpedienteModo.edicion);
    expect(state.tieneCambiosSinGuardar, isFalse);
  });

  test('marcarCambiosSinGuardar activa el indicador de cambios sin guardar', () async {
    await esperarCargaInicial();
    final notifier = container.read(puestoExpedienteControllerProvider(puestoId).notifier);
    notifier.entrarModoEdicion();

    notifier.marcarCambiosSinGuardar();

    expect(container.read(puestoExpedienteControllerProvider(puestoId)).tieneCambiosSinGuardar, isTrue);
  });

  test('cancelarEdicion regresa a consulta y limpia el indicador de cambios', () async {
    await esperarCargaInicial();
    final notifier = container.read(puestoExpedienteControllerProvider(puestoId).notifier);
    notifier.entrarModoEdicion();
    notifier.marcarCambiosSinGuardar();

    notifier.cancelarEdicion();

    final state = container.read(puestoExpedienteControllerProvider(puestoId));
    expect(state.modo, PuestoExpedienteModo.consulta);
    expect(state.tieneCambiosSinGuardar, isFalse);
  });

  test('guardar con datos válidos persiste y regresa a consulta', () async {
    await esperarCargaInicial();
    final notifier = container.read(puestoExpedienteControllerProvider(puestoId).notifier);
    notifier.entrarModoEdicion();

    final exito = await notifier.guardar(const PuestoBorrador(
      nombre: 'Guardia Senior',
      areaId: SeedIds.areaOperaciones,
      tipo: TipoPuesto.operativo,
      nivelJerarquico: 3,
    ));

    expect(exito, isTrue);
    final state = container.read(puestoExpedienteControllerProvider(puestoId));
    expect(state.modo, PuestoExpedienteModo.consulta);
    expect(state.guardando, isFalse);
    expect(state.datos?.nombre, 'Guardia Senior');
    expect(state.datos?.nivelJerarquico, 3);
  });

  test('guardar con Área cambiada a una inactiva reporta el error sin persistir', () async {
    await esperarCargaInicial();
    final areas = await areaRepo.listarTodas();
    final otraArea = areas.firstWhere((a) => a.id != SeedIds.areaOperaciones);
    await areaRepo.desactivar(otraArea.id);

    final notifier = container.read(puestoExpedienteControllerProvider(puestoId).notifier);
    notifier.entrarModoEdicion();

    final exito = await notifier.guardar(PuestoBorrador(
      nombre: 'Guardia',
      areaId: otraArea.id,
      tipo: TipoPuesto.operativo,
      nivelJerarquico: 1,
    ));

    expect(exito, isFalse);
    final state = container.read(puestoExpedienteControllerProvider(puestoId));
    expect(state.modo, PuestoExpedienteModo.edicion);
    expect(
      state.erroresGuardado,
      contains(predicate<ErrorCampoPuesto>(
        (e) => e.campo == CampoPuesto.area && e.codigo == CodigoErrorPuesto.inactiva,
      )),
    );
    expect(state.datos?.areaId, SeedIds.areaOperaciones);
  });

  test('cambiarCicloVida archiva y luego bloquea la reactivación si el Área queda inactiva', () async {
    await esperarCargaInicial();
    final notifier = container.read(puestoExpedienteControllerProvider(puestoId).notifier);

    final archivado = await notifier.cambiarCicloVida(CicloVidaRegistro.archivado);
    expect(archivado, isTrue);
    expect(
      container.read(puestoExpedienteControllerProvider(puestoId)).datos?.cicloVidaRegistro,
      CicloVidaRegistro.archivado.name,
    );

    await areaRepo.desactivar(SeedIds.areaOperaciones);

    final reactivado = await notifier.cambiarCicloVida(CicloVidaRegistro.activo);
    expect(reactivado, isFalse);
    expect(
      container.read(puestoExpedienteControllerProvider(puestoId)).datos?.cicloVidaRegistro,
      CicloVidaRegistro.archivado.name,
    );
  });

  // Hallazgo real (mismo patrón que `ServicioExpedienteController`/
  // `ClienteExpedienteController`): archivar/reactivar un Puesto desde
  // el expediente seguía viendo el ciclo de vida previo en el listado
  // (y en las métricas "Puestos por Área") hasta navegar a otra
  // pestaña y volver.
  test('cambiarCicloVida refleja el archivado en el listado de Puestos y en las métricas de Áreas sin recargar manualmente', () async {
    // `ListarPuestosUseCase` solo trae Puestos activos — un Puesto
    // archivado desaparece del listado por completo, nunca se muestra
    // con `cicloVidaRegistro == 'archivado'`.
    await esperarCargaInicial();
    container.listen(puestosListControllerProvider, (_, _) {});
    container.listen(areasListControllerProvider, (_, _) {});
    while (container.read(puestosListControllerProvider).cargando || container.read(areasListControllerProvider).cargando) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(container.read(puestosListControllerProvider).puestos.any((p) => p.id == puestoId), isTrue);
    expect(container.read(areasListControllerProvider).puestosPorArea[SeedIds.areaOperaciones], 1);

    final notifier = container.read(puestoExpedienteControllerProvider(puestoId).notifier);
    final archivado = await notifier.cambiarCicloVida(CicloVidaRegistro.archivado);
    expect(archivado, isTrue);

    await Future<void>.delayed(Duration.zero);
    while (container.read(puestosListControllerProvider).cargando || container.read(areasListControllerProvider).cargando) {
      await Future<void>.delayed(Duration.zero);
    }

    expect(container.read(puestosListControllerProvider).puestos.any((p) => p.id == puestoId), isFalse);
    expect(container.read(areasListControllerProvider).puestosPorArea[SeedIds.areaOperaciones] ?? 0, 0);
  });

  test('reintentarCarga vuelve a intentar tras un error de carga', () async {
    await esperarCargaInicial();
    final notifier = container.read(puestoExpedienteControllerProvider(puestoId).notifier);

    await notifier.reintentarCarga();

    final state = container.read(puestoExpedienteControllerProvider(puestoId));
    expect(state.cargando, isFalse);
    expect(state.datos, isNotNull);
  });
}
