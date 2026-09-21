// Personal → Plantilla activa: la asignación administrativa cuenta.
//
// Bug real que cierran estas pruebas: la pantalla mostraba
// "16 activos / 15 asignados / 1 sin asignar / 94%" con MARLON RIOS
// (DIRECCION GENERAL) marcado como "Sin asignar", pese a estar
// correctamente adscrito a su Sucursal.
//
// La regla ya estaba bien en el dominio (`ObtenerPlantillaPersonalUseCase`)
// y el FILTRO de la pantalla ya la consumía; lo que seguía sin migrar
// eran los KPI y la columna de destino, que miraban únicamente la
// `AsignacionServicio`. Por eso un administrativo entraba al denominador
// sin poder entrar nunca al numerador.
//
// Se prueba contra el controller real y BD real — nunca un mock de la
// clasificación, que es justo lo que se quiere evitar que vuelva a
// divergir.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/organizacion/data/tables/puesto_table.dart' show TipoPuesto;
import 'package:riseg_one/features/personal/domain/plantilla_personal.dart';
import 'package:riseg_one/features/personal/personal_providers.dart';
import 'package:riseg_one/features/personal/presentation/empleados/personal_activo_controller.dart';
import 'package:riseg_one/features/personal/presentation/empleados/personal_activo_state.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

class _SesionMaestro extends SesionController {
  @override
  SesionUsuario? build() => const SesionUsuario(
        usuarioId: 'maestro',
        nombre: 'Maestro de prueba',
        nombreUsuario: 'maestro',
        esMaestro: true,
        permisos: {},
      );
}

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  late String puestoOperativoId;
  late String puestoAdministrativoId;
  late String servicioId;
  late String sucursalId;
  late String otraSucursalId;
  var numero = 0;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      sesionControllerProvider.overrideWith(_SesionMaestro.new),
    ]);
    numero = 0;

    final areaId = (await db.select(db.area).get()).first.id;
    puestoOperativoId = (await db.into(db.puesto).insertReturning(
              PuestoCompanion.insert(
                codigo: 'PUE-OP',
                nombre: 'Elemento Operativo',
                areaId: areaId,
                tipo: TipoPuesto.operativo.name,
                nivelJerarquico: 1,
              ),
            ))
        .id;
    puestoAdministrativoId = (await db.into(db.puesto).insertReturning(
              PuestoCompanion.insert(
                codigo: 'PUE-ADM',
                nombre: 'DIRECCION GENERAL',
                areaId: areaId,
                tipo: TipoPuesto.administrativo.name,
                nivelJerarquico: 10,
              ),
            ))
        .id;

    final cliente = await db.into(db.cliente).insertReturning(
          ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'De Acero'),
        );
    servicioId = (await db.into(db.servicio).insertReturning(
              ServicioCompanion.insert(
                codigo: 'SRV-0001',
                nombre: 'DE ACERO PATIO TOLUCA',
                clienteId: cliente.id,
                tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
                fechaInicio: DateTime(2026, 1, 1),
              ),
            ))
        .id;
    sucursalId = (await db.into(db.sucursal).insertReturning(
              SucursalCompanion.insert(
                codigo: 'SUC-0001',
                nombre: 'SUCURSAL TOLUCA',
                tipoSucursalId: SeedIds.tipoSucursalOficinaAdministrativa,
              ),
            ))
        .id;
    otraSucursalId = (await db.into(db.sucursal).insertReturning(
              SucursalCompanion.insert(
                codigo: 'SUC-0002',
                nombre: 'SUCURSAL METEPEC',
                tipoSucursalId: SeedIds.tipoSucursalOficinaAdministrativa,
              ),
            ))
        .id;
  });

  tearDown(() {
    container.dispose();
    db.close();
  });

  Future<EmpleadoData> crearEmpleado({required bool operativo, String? sucursal}) async {
    numero++;
    return db.into(db.empleado).insertReturning(
          EmpleadoCompanion.insert(
            numeroEmpleado: numero,
            nombres: operativo ? 'Guardia' : 'MARLON',
            apellidoPaterno: operativo ? 'Operativo $numero' : 'RIOS HERNANDEZ',
            sexo: 'masculino',
            fechaNacimiento: DateTime(1990, 1, 1),
            curp: 'PEXJ90010${numero.toString().padLeft(2, '0')}HDFXX1',
            rfc: 'PEXJ9001${numero.toString().padLeft(2, '0')}',
            nss: '1000000${numero.toString().padLeft(4, '0')}',
            estadoCivil: 'soltero',
            fechaIngreso: DateTime(2026, 1, 1),
            aniosExperienciaSeguridad: 1,
            puestoId: Value(operativo ? puestoOperativoId : puestoAdministrativoId),
            sucursalId: Value(sucursal),
          ),
        );
  }

  Future<void> asignarAServicio(String empleadoId, {String? servicio}) async {
    await db.into(db.asignacionServicio).insert(
          AsignacionServicioCompanion.insert(
            empleadoId: empleadoId,
            servicioId: servicio ?? servicioId,
            turnoId: const Value(SeedIds.modalidadTurno24x24),
            fechaInicio: DateTime(2026, 1, 1),
          ),
        );
  }

  /// Carga el controller real y devuelve su estado ya resuelto.
  ///
  /// `listen` y no `read`: el controller es autoDispose y sin una
  /// suscripción viva se destruiría antes de terminar de cargar.
  Future<PersonalActivoState> cargarPantalla() async {
    container.listen(personalActivoControllerProvider, (_, __) {}, fireImmediately: true);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final state = container.read(personalActivoControllerProvider);
    expect(state.cargando, isFalse, reason: 'la pantalla debe terminar de cargar');
    return state;
  }

  group('Casos obligatorios A-G', () {
    test('A. operativo con Servicio: asignado', () async {
      final e = await crearEmpleado(operativo: true);
      await asignarAServicio(e.id);

      final state = await cargarPantalla();
      final clasificacion = state.clasificacionPorEmpleado[e.id]!;

      expect(clasificacion.asignacion, AsignacionEstructural.servicio);
      expect(clasificacion.plantilla, PlantillaPersonal.operativa);
      expect(state.personalAsignado, 1);
      expect(state.personalSinAsignar, 0);
    });

    test('B. operativo sin Servicio: sin asignación', () async {
      final e = await crearEmpleado(operativo: true);

      final state = await cargarPantalla();

      expect(state.clasificacionPorEmpleado[e.id]!.asignacion, AsignacionEstructural.sinAsignacion);
      expect(state.personalAsignado, 0);
      expect(state.personalSinAsignar, 1);
      expect(state.porcentajeAsignado, 0);
    });

    test('C. administrativo con Sucursal: asignado', () async {
      final e = await crearEmpleado(operativo: false, sucursal: sucursalId);

      final state = await cargarPantalla();
      final clasificacion = state.clasificacionPorEmpleado[e.id]!;

      expect(clasificacion.asignacion, AsignacionEstructural.sucursal);
      expect(clasificacion.plantilla, PlantillaPersonal.administrativa);
      expect(clasificacion.sucursalId, sucursalId);
      expect(state.personalAsignado, 1);
      expect(state.personalSinAsignar, 0);
    });

    test('D. administrativo sin Sucursal: sin asignación', () async {
      final e = await crearEmpleado(operativo: false);

      final state = await cargarPantalla();

      expect(state.clasificacionPorEmpleado[e.id]!.asignacion, AsignacionEstructural.sinAsignacion);
      expect(state.clasificacionPorEmpleado[e.id]!.plantilla, PlantillaPersonal.administrativa,
          reason: 'sigue perteneciendo a la plantilla administrativa por su puesto');
      expect(state.personalAsignado, 0);
      expect(state.personalSinAsignar, 1);
    });

    test('E. administrativo con Sucursal y SIN Servicio: nunca "sin asignar" — el bug reportado', () async {
      final marlon = await crearEmpleado(operativo: false, sucursal: sucursalId);

      final state = await cargarPantalla();
      final clasificacion = state.clasificacionPorEmpleado[marlon.id]!;

      expect(clasificacion.servicioId, isNull, reason: 'un administrativo no ocupa una posición de Servicio');
      expect(clasificacion.estaAsignado, isTrue);
      expect(state.personalSinAsignar, 0, reason: 'estaba perfectamente asignado, sólo que a una Sucursal');
      expect(state.porcentajeAsignado, 100);
    });

    test('F. 15 operativos asignados + 1 administrativo asignado: 16/16/0/100%', () async {
      for (var i = 0; i < 15; i++) {
        final e = await crearEmpleado(operativo: true);
        await asignarAServicio(e.id);
      }
      await crearEmpleado(operativo: false, sucursal: sucursalId);

      final state = await cargarPantalla();

      expect(state.personalActivo, 16);
      expect(state.personalAsignado, 16, reason: 'el administrativo también está asignado');
      expect(state.personalSinAsignar, 0);
      expect(state.porcentajeAsignado.round(), 100, reason: 'NUNCA 94%');
      expect(state.personalInconsistente, 0);
    });

    test('G. Servicio + Sucursal: inconsistencia, ni asignado ni sin asignar', () async {
      final roto = await crearEmpleado(operativo: true, sucursal: sucursalId);
      await asignarAServicio(roto.id);

      final state = await cargarPantalla();
      final clasificacion = state.clasificacionPorEmpleado[roto.id]!;

      expect(clasificacion.asignacion, AsignacionEstructural.inconsistente);
      expect(clasificacion.plantilla, isNull, reason: 'elegir una sería la prioridad arbitraria que la regla prohíbe');
      expect(state.personalInconsistente, 1);
      expect(state.personalAsignado, 0);
      expect(state.personalSinAsignar, 0, reason: 'no le falta destino: le sobra');
    });
  });

  group('Filtro de plantilla', () {
    setUp(() async {
      // El escenario real: 2 guardias asignados, 1 administrativo con
      // Sucursal, 1 administrativo sin Sucursal, 1 operativo sin Servicio.
      for (var i = 0; i < 2; i++) {
        final e = await crearEmpleado(operativo: true);
        await asignarAServicio(e.id);
      }
      await crearEmpleado(operativo: false, sucursal: sucursalId);
      await crearEmpleado(operativo: false);
      await crearEmpleado(operativo: true);
    });

    test('el administrativo con Sucursal aparece en Administrativo y NO en Sin asignación', () async {
      await cargarPantalla();
      final notifier = container.read(personalActivoControllerProvider.notifier);

      notifier.aplicarFiltros(estadoAsignacion: FiltroPlantilla.administrativo);
      final administrativos = container.read(personalActivoControllerProvider).visibles;
      expect(administrativos, hasLength(2), reason: 'el de Sucursal y el que aún no tiene destino');
      expect(administrativos.every((e) => e.apellidoPaterno == 'RIOS HERNANDEZ'), isTrue);

      notifier.aplicarFiltros(estadoAsignacion: FiltroPlantilla.sinAsignacion);
      final sinAsignacion = container.read(personalActivoControllerProvider).visibles;
      expect(sinAsignacion, hasLength(2), reason: 'el administrativo sin Sucursal y el operativo sin Servicio');

      final state = container.read(personalActivoControllerProvider);
      final conSucursal = state.empleados.firstWhere(
        (e) => state.clasificacionPorEmpleado[e.id]?.sucursalId == sucursalId,
      );
      expect(sinAsignacion.map((e) => e.id), isNot(contains(conSucursal.id)),
          reason: 'un administrativo adscrito a su Sucursal nunca está sin asignación');
    });

    test('los guardias con Servicio aparecen en Operativo', () async {
      await cargarPantalla();
      container.read(personalActivoControllerProvider.notifier).aplicarFiltros(
            estadoAsignacion: FiltroPlantilla.operativo,
          );

      final operativos = container.read(personalActivoControllerProvider).visibles;
      expect(operativos, hasLength(3), reason: '2 asignados + 1 sin Servicio, los tres son plantilla operativa');
      expect(operativos.every((e) => e.apellidoPaterno.startsWith('Operativo')), isTrue);
    });
  });

  group('Filtro de Asignación — Servicios y Sucursales, por id real', () {
    test('filtrar por una Sucursal deja sólo a su personal administrativo', () async {
      final guardia = await crearEmpleado(operativo: true);
      await asignarAServicio(guardia.id);
      final enToluca = await crearEmpleado(operativo: false, sucursal: sucursalId);
      await crearEmpleado(operativo: false, sucursal: otraSucursalId);

      await cargarPantalla();
      container.read(personalActivoControllerProvider.notifier).aplicarFiltros(
            destino: (tipo: TipoDestinoFiltro.sucursal, id: sucursalId),
          );

      final visibles = container.read(personalActivoControllerProvider).visibles;
      expect(visibles, hasLength(1));
      expect(visibles.single.id, enToluca.id);
    });

    test('filtrar por un Servicio deja sólo a su personal operativo', () async {
      final guardia = await crearEmpleado(operativo: true);
      await asignarAServicio(guardia.id);
      await crearEmpleado(operativo: false, sucursal: sucursalId);

      await cargarPantalla();
      container.read(personalActivoControllerProvider.notifier).aplicarFiltros(
            destino: (tipo: TipoDestinoFiltro.servicio, id: servicioId),
          );

      final visibles = container.read(personalActivoControllerProvider).visibles;
      expect(visibles, hasLength(1));
      expect(visibles.single.id, guardia.id);
    });

    test('la opción "Sin asignación" del filtro de Asignación no oculta al administrativo asignado', () async {
      final marlon = await crearEmpleado(operativo: false, sucursal: sucursalId);
      final pendiente = await crearEmpleado(operativo: true);

      await cargarPantalla();
      container.read(personalActivoControllerProvider.notifier).aplicarFiltros(
            destino: (tipo: TipoDestinoFiltro.sinAsignacion, id: null),
          );

      final visibles = container.read(personalActivoControllerProvider).visibles;
      expect(visibles.map((e) => e.id), [pendiente.id]);
      expect(visibles.map((e) => e.id), isNot(contains(marlon.id)));
    });

    test('el catálogo del filtro ofrece los dos destinos, no sólo Servicios', () async {
      final guardia = await crearEmpleado(operativo: true);
      await asignarAServicio(guardia.id);
      await crearEmpleado(operativo: false, sucursal: sucursalId);

      final state = await cargarPantalla();

      expect(state.servicios.map((s) => s.servicio.id), contains(servicioId));
      expect(state.sucursales.map((s) => s.id), containsAll([sucursalId, otraSucursalId]));
      expect(state.sucursalNombrePorId[sucursalId], 'SUCURSAL TOLUCA');
    });
  });

  group('Paridad con Dashboard — una sola clasificación', () {
    test('el mismo conjunto de empleados se clasifica idéntico en Personal y en Dashboard', () async {
      for (var i = 0; i < 4; i++) {
        final e = await crearEmpleado(operativo: true);
        await asignarAServicio(e.id);
      }
      await crearEmpleado(operativo: true); // operativo sin Servicio
      await crearEmpleado(operativo: false, sucursal: sucursalId); // administrativo asignado
      await crearEmpleado(operativo: false); // administrativo sin Sucursal
      final roto = await crearEmpleado(operativo: true, sucursal: sucursalId);
      await asignarAServicio(roto.id); // inconsistente

      final state = await cargarPantalla();
      // La MISMA fuente que consume el Dashboard, invocada aparte.
      final plantilla = await container.read(obtenerPlantillaPersonalUseCaseProvider).ejecutar();

      expect(state.personalActivo, plantilla.totalActivos);
      expect(
        state.personalAsignado,
        plantilla.clasificaciones.where((c) => c.estaAsignado).length,
        reason: 'asignados',
      );
      expect(state.personalSinAsignar, plantilla.sinAsignacion.length, reason: 'sin asignación');
      expect(state.personalInconsistente, plantilla.inconsistentes.length, reason: 'inconsistentes');

      // Y empleado por empleado, no sólo en los totales.
      for (final c in plantilla.clasificaciones) {
        final deLaPantalla = state.clasificacionPorEmpleado[c.empleado.id]!;
        expect(deLaPantalla.asignacion, c.asignacion, reason: c.empleado.id);
        expect(deLaPantalla.plantilla, c.plantilla, reason: c.empleado.id);
        expect(deLaPantalla.servicioId, c.servicioId, reason: c.empleado.id);
        expect(deLaPantalla.sucursalId, c.sucursalId, reason: c.empleado.id);
      }

      // El escenario no es trivial: hay de los cuatro tipos.
      expect(plantilla.operativa.activos, 5);
      expect(plantilla.administrativa.activos, 2);
      expect(plantilla.sinAsignacion, hasLength(2));
      expect(plantilla.inconsistentes, hasLength(1));
    });
  });
}
