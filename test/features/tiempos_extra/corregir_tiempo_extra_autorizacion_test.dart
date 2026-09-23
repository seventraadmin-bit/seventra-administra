// Etapa "corrección real de Tiempo Extra" — frontera de autorización:
// `tiempoExtra.corregir` gatea la corrección (permiso otorgable,
// nunca hardcodeado a un rol); la eliminación física exige Maestro
// (`exigirMaestro`), ningún permiso dinámico la sustituye — mismo
// criterio que `compra_eliminar_fisicamente_autorizacion_test.dart`.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_servicio_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_validator.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/tiempos_extra/data/tables/tiempo_extra_table.dart';
import 'package:riseg_one/features/tiempos_extra/domain/usecases/corregir_tiempo_extra_usecase.dart';
import 'package:riseg_one/features/tiempos_extra/domain/usecases/eliminar_tiempo_extra_fisicamente_usecase.dart';
import 'package:riseg_one/features/tiempos_extra/domain/usecases/registrar_tiempo_extra_usecase.dart';
import 'package:riseg_one/features/tiempos_extra/tiempos_extra_providers.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import '../../support/sesion_en_base.dart';

class _SesionMaestro extends SesionController {
  @override
  SesionUsuario? build() {
    return const SesionUsuario(
      usuarioId: 'usuario-maestro', nombre: 'Maestro de prueba', nombreUsuario: 'maestro', esMaestro: true, permisos: {});
  }
}

class _SesionSinPermiso extends SesionController {
  @override
  SesionUsuario? build() {
    return const SesionUsuario(
      usuarioId: 'usuario-normal',
      nombre: 'Usuario normal',
      nombreUsuario: 'normal',
      esMaestro: false,
      // Tiene crear/cancelar pero NO corregir — debe bastar para rechazar.
      permisos: {'tiempoExtra.crear', 'tiempoExtra.cancelar'},
    );
  }
}

class _SesionConPermisoCorregir extends SesionController {
  @override
  SesionUsuario? build() {
    return const SesionUsuario(
      usuarioId: 'usuario-normal',
      nombre: 'Usuario normal',
      nombreUsuario: 'normal',
      esMaestro: false,
      permisos: {'tiempoExtra.crear', 'tiempoExtra.corregir', 'tiempoExtra.cancelar'},
    );
  }
}

class _SesionConTodosLosPermisosMenosMaestro extends SesionController {
  @override
  SesionUsuario? build() {
    return const SesionUsuario(
      usuarioId: 'usuario-normal',
      nombre: 'Usuario normal',
      nombreUsuario: 'normal',
      esMaestro: false,
      // Incluso con TODOS los permisos dinámicos de Tiempos Extra,
      // `exigirMaestro` nunca consulta esta lista.
      permisos: {'tiempoExtra.crear', 'tiempoExtra.corregir', 'tiempoExtra.cancelar'},
    );
  }
}

Future<String> _sembrarBase(AppDatabase db) async {
  await db.into(db.usuario).insert(UsuarioCompanion.insert(id: const Value('usuario-maestro'), nombre: 'Maestro', nombreUsuario: 'usuario-maestro', passwordHash: 'x'));
  await db.into(db.usuario).insert(UsuarioCompanion.insert(id: const Value('usuario-normal'), nombre: 'Normal', nombreUsuario: 'usuario-normal', passwordHash: 'x'));

  final asignacionServicioRepo = AsignacionServicioRepositoryImpl(db);
  final servicioRepo = ServicioRepositoryImpl(db, asignacionServicioRepo);
  final clienteRepo = ClienteRepositoryImpl(db);
  final catalogoRepo = CatalogoRepositoryImpl(db);
  final codigoSecuencia = CodigoSecuenciaService(db);

  final cliente = await clienteRepo.crear(ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'Sportium'));
  final servicioCreado = await CrearServicioUseCase(servicioRepo, GenerarCodigoUseCase(codigoSecuencia), ServicioValidator(clienteRepo, catalogoRepo)).ejecutar(
    clienteId: cliente.id,
    borrador: ServicioBorrador(nombre: 'Vigilancia Sportium', tipoServicioId: SeedIds.tipoServicioVigilanciaFija, fechaInicio: DateTime(2026, 1, 1)),
  );
  final servicioId = (servicioCreado as GuardarServicioExitoso).servicio.id;

  final empleadoAusente = await db.into(db.empleado).insertReturning(EmpleadoCompanion.insert(
        numeroEmpleado: 1, nombres: 'Monica', apellidoPaterno: 'Ausente', sexo: 'femenino', fechaNacimiento: DateTime(1990, 1, 1),
        curp: 'PEXJ900101MDFXXX01', rfc: 'PEXJ90010101', nss: '10000000001', estadoCivil: 'soltero', fechaIngreso: DateTime(2025, 1, 1), aniosExperienciaSeguridad: 3,
      ));
  final empleadoCubre = await db.into(db.empleado).insertReturning(EmpleadoCompanion.insert(
        numeroEmpleado: 2, nombres: 'Juan', apellidoPaterno: 'Cubre', sexo: 'masculino', fechaNacimiento: DateTime(1990, 1, 1),
        curp: 'PEXJ900101HDFXXX02', rfc: 'PEXJ90010102', nss: '10000000002', estadoCivil: 'soltero', fechaIngreso: DateTime(2025, 1, 1), aniosExperienciaSeguridad: 3,
      ));

  // Etapa 3B: la autorización se revalida contra la base, así que
  // este escenario —el de ESTA prueba— se persiste antes de usarlo.
  await sembrarSesionEnBase(db, _SesionMaestro().build()!);
  final container = ProviderContainer(overrides: [
    appDatabaseProvider.overrideWithValue(db),
    sesionControllerProvider.overrideWith(_SesionMaestro.new),
  ]);
  final resultado = await container.read(registrarTiempoExtraAutorizadoProvider)(
    fecha: DateTime(2026, 9, 3),
    servicioId: servicioId,
    origenCobertura: OrigenCoberturaTiempoExtra.ausenciaEmpleado.name,
    empleadoAusenteId: empleadoAusente.id,
    motivoAusencia: MotivoAusenciaTiempoExtra.faltaInjustificada.name,
    empleadoCubreId: empleadoCubre.id,
    turnoId: SeedIds.modalidadTurno24x24,
    montoTiempoExtra: 50000,
    formaPago: 'efectivo',
  );
  container.dispose();
  return (resultado as RegistrarTiempoExtraExitoso).tiempoExtra.id;
}

void main() {
  late AppDatabase db;
  late String tiempoExtraId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    tiempoExtraId = await _sembrarBase(db);
  });

  tearDown(() => db.close());

  test('un usuario sin tiempoExtra.corregir (aunque tenga crear/cancelar) no puede corregir', () async {
    // Etapa 3B: la autorización se revalida contra la base, así que
    // este escenario —el de ESTA prueba— se persiste antes de usarlo.
    await sembrarSesionEnBase(db, _SesionSinPermiso().build()!);
    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      sesionControllerProvider.overrideWith(_SesionSinPermiso.new),
    ]);
    addTearDown(container.dispose);

    final resultado = await container.read(corregirTiempoExtraAutorizadoProvider)(
      tiempoExtraId: tiempoExtraId,
      fecha: DateTime(2026, 9, 3),
      servicioId: (await container.read(tiempoExtraRepositoryProvider).obtenerPorId(tiempoExtraId))!.servicioId,
      origenCobertura: OrigenCoberturaTiempoExtra.ausenciaEmpleado.name,
      empleadoAusenteId: (await container.read(tiempoExtraRepositoryProvider).obtenerPorId(tiempoExtraId))!.empleadoAusenteId,
      motivoAusencia: MotivoAusenciaTiempoExtra.faltaInjustificada.name,
      empleadoCubreId: (await container.read(tiempoExtraRepositoryProvider).obtenerPorId(tiempoExtraId))!.empleadoCubreId,
      turnoId: SeedIds.modalidadTurno24x24,
      montoTiempoExtra: 60000,
      formaPago: 'efectivo',
      motivo: 'Intento sin permiso',
    );

    expect(resultado, isA<CorregirTiempoExtraErrorInesperado>());
    final actual = await container.read(tiempoExtraRepositoryProvider).obtenerPorId(tiempoExtraId);
    expect(actual!.montoTiempoExtra, 50000, reason: 'nunca se corrige sin el permiso');
  });

  test('un usuario con tiempoExtra.corregir sí puede corregir', () async {
    // Etapa 3B: la autorización se revalida contra la base, así que
    // este escenario —el de ESTA prueba— se persiste antes de usarlo.
    await sembrarSesionEnBase(db, _SesionConPermisoCorregir().build()!);
    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      sesionControllerProvider.overrideWith(_SesionConPermisoCorregir.new),
    ]);
    addTearDown(container.dispose);
    final actualAntes = await container.read(tiempoExtraRepositoryProvider).obtenerPorId(tiempoExtraId);

    final resultado = await container.read(corregirTiempoExtraAutorizadoProvider)(
      tiempoExtraId: tiempoExtraId,
      fecha: actualAntes!.fecha,
      servicioId: actualAntes.servicioId,
      origenCobertura: OrigenCoberturaTiempoExtra.ausenciaEmpleado.name,
      empleadoAusenteId: actualAntes.empleadoAusenteId,
      motivoAusencia: actualAntes.motivoAusencia,
      empleadoCubreId: actualAntes.empleadoCubreId,
      turnoId: actualAntes.turnoId,
      montoTiempoExtra: 60000,
      formaPago: 'efectivo',
      motivo: 'Corrección autorizada',
    );

    expect(resultado, isA<CorregirTiempoExtraExitoso>());
    final actualDespues = await container.read(tiempoExtraRepositoryProvider).obtenerPorId(tiempoExtraId);
    expect(actualDespues!.montoTiempoExtra, 60000);
  });

  test('un usuario normal (incluso con todos los permisos dinámicos de Tiempos Extra) no puede eliminar físicamente', () async {
    // Etapa 3B: la autorización se revalida contra la base, así que
    // este escenario —el de ESTA prueba— se persiste antes de usarlo.
    await sembrarSesionEnBase(db, _SesionConTodosLosPermisosMenosMaestro().build()!);
    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      sesionControllerProvider.overrideWith(_SesionConTodosLosPermisosMenosMaestro.new),
    ]);
    addTearDown(container.dispose);
    await container.read(cancelarTiempoExtraAutorizadoProvider)(tiempoExtraId: tiempoExtraId, motivo: 'Para eliminar después');

    final resultado = await container.read(eliminarTiempoExtraFisicamenteAutorizadoProvider)(
      tiempoExtraId: tiempoExtraId,
      motivo: MotivoEliminacionFisicaTiempoExtra.errorDeCaptura,
    );

    expect(resultado, isA<EliminarTiempoExtraFisicamenteErrorInesperado>());
    expect(await container.read(tiempoExtraRepositoryProvider).obtenerPorId(tiempoExtraId), isNotNull, reason: 'nunca se elimina sin ser Maestro');
  });

  test('el Usuario Maestro sí puede eliminar físicamente (tras cancelar)', () async {
    // Etapa 3B: la autorización se revalida contra la base, así que
    // este escenario —el de ESTA prueba— se persiste antes de usarlo.
    await sembrarSesionEnBase(db, _SesionConPermisoCorregir().build()!);
    final containerNormal = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      sesionControllerProvider.overrideWith(_SesionConPermisoCorregir.new),
    ]);
    addTearDown(containerNormal.dispose);
    await containerNormal.read(cancelarTiempoExtraAutorizadoProvider)(tiempoExtraId: tiempoExtraId, motivo: 'Para eliminar después');

    // Etapa 3B: la autorización se revalida contra la base, así que
    // este escenario —el de ESTA prueba— se persiste antes de usarlo.
    await sembrarSesionEnBase(db, _SesionMaestro().build()!);
    final containerMaestro = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      sesionControllerProvider.overrideWith(_SesionMaestro.new),
    ]);
    addTearDown(containerMaestro.dispose);

    final resultado = await containerMaestro.read(eliminarTiempoExtraFisicamenteAutorizadoProvider)(
      tiempoExtraId: tiempoExtraId,
      motivo: MotivoEliminacionFisicaTiempoExtra.registroDePrueba,
    );

    expect(resultado, isA<EliminarTiempoExtraFisicamenteExitoso>());
    expect(await containerMaestro.read(tiempoExtraRepositoryProvider).obtenerPorId(tiempoExtraId), isNull);
  });
}
