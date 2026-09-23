// Etapa 4 (Nómina — corrección, cancelación y trazabilidad integral),
// Sección 13: `nomina.corregir`/`nomina.cancelar` son códigos
// INDEPENDIENTES, ninguno reutiliza `nomina.modificar` (Borrador-only)
// ni `nomina.cancelarPago` (cancelar un pago individual) — confirma
// que ambos corren por `autorizarUseCase` sin ninguna ruta de bypass.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/nomina/data/tables/nomina_table.dart';
import 'package:riseg_one/features/nomina/domain/usecases/cancelar_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/corregir_renglon_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/generar_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/nomina_providers.dart';
import 'package:riseg_one/features/nomina/presentation/nominas/nominas_controller.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_comercial_repository_impl.dart';
import 'package:riseg_one/features/organizacion/organizacion_providers.dart';
import 'package:riseg_one/features/personal/data/tables/empleado_table.dart';
import 'package:riseg_one/features/personal/domain/usecases/crear_empleado_usecase.dart';
import 'package:riseg_one/features/personal/domain/usecases/empleado_validator.dart';
import 'package:riseg_one/features/personal/personal_providers.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import '../../support/sesion_en_base.dart';

class _SesionSinCorregirNiCancelar extends SesionController {
  @override
  SesionUsuario? build() {
    return const SesionUsuario(
      usuarioId: 'usuario-prueba',
      nombre: 'Sin corregir/cancelar',
      nombreUsuario: 'sin-corregir-cancelar',
      esMaestro: false,
      permisos: {'nomina.ver', 'nomina.crear', 'nomina.modificar', 'nomina.cerrar', 'nomina.cancelarPago'},
    );
  }
}

class _SesionSoloCorregirYCancelar extends SesionController {
  @override
  SesionUsuario? build() {
    return const SesionUsuario(
      usuarioId: 'usuario-prueba',
      nombre: 'Solo corregir y cancelar Nómina',
      nombreUsuario: 'solo-corregir-cancelar',
      esMaestro: false,
      permisos: {'nomina.ver', 'nomina.corregir', 'nomina.cancelar'},
    );
  }
}

void main() {
  late AppDatabase db;
  late String nominaId;
  late String renglonId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(id: const Value('usuario-prueba'), nombre: 'Usuario de prueba', nombreUsuario: 'usuario-prueba', passwordHash: 'x'),
        );
    final container = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
    addTearDown(container.dispose);

    final crearEmpleado = CrearEmpleadoUseCase(
      container.read(empleadoRepositoryProvider),
      container.read(generarNumeroUseCaseProvider),
      const EmpleadoValidator(),
      container.read(servicioRepositoryProvider),
      ServicioComercialRepositoryImpl(db),
    );
    await crearEmpleado.ejecutar(
      nombres: 'Ana',
      apellidoPaterno: 'Gómez',
      sexo: SexoEmpleado.femenino,
      fechaNacimiento: DateTime(1990, 1, 1),
      curp: 'GOXA900101MDFXXX01',
      rfc: 'GOXA900101AB1',
      nss: '10000000001',
      estadoCivil: EstadoCivilEmpleado.soltero,
      fechaIngreso: DateTime(2025, 1, 1),
      aniosExperienciaSeguridad: 3,
      sueldoMensualAdministrativo: 1500000,
    );

    final generado =
        (await container.read(generarNominaUseCaseProvider).ejecutar(anio: 2026, mes: 1, tipo: TipoPeriodoNomina.primera)) as GenerarNominaExitoso;
    nominaId = generado.nomina.id;
    renglonId = (await container.read(nominaRepositoryProvider).listarEmpleados(nominaId)).single.id;
    await container.read(cerrarNominaUseCaseProvider).ejecutar(nominaId: nominaId);
  });

  tearDown(() => db.close());

  test('tener nomina.modificar/cerrar/cancelarPago (sin nomina.corregir) NO permite corregir un renglón cerrado', () async {
    // Etapa 3B: la autorización se revalida contra la base, así que
    // este escenario —el de ESTA prueba— se persiste antes de usarlo.
    await sembrarSesionEnBase(db, _SesionSinCorregirNiCancelar().build()!);
    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db), sesionControllerProvider.overrideWith(_SesionSinCorregirNiCancelar.new)],
    );
    addTearDown(container.dispose);

    final resultado = await container.read(nominasControllerProvider.notifier).corregirRenglon(
          nominaEmpleadoId: renglonId,
          bono: 999999,
          motivo: 'Intento sin permiso',
        );

    expect(resultado, isA<CorregirRenglonNominaErrorInesperado>());
    final renglon = await container.read(nominaRepositoryProvider).obtenerEmpleado(renglonId);
    expect(renglon!.bono, isNot(999999), reason: 'nada cambia sin el permiso correcto');
  });

  test('tener nomina.modificar/cerrar/cancelarPago (sin nomina.cancelar) NO permite cancelar la Nómina', () async {
    // Etapa 3B: la autorización se revalida contra la base, así que
    // este escenario —el de ESTA prueba— se persiste antes de usarlo.
    await sembrarSesionEnBase(db, _SesionSinCorregirNiCancelar().build()!);
    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db), sesionControllerProvider.overrideWith(_SesionSinCorregirNiCancelar.new)],
    );
    addTearDown(container.dispose);

    final resultado = await container.read(nominasControllerProvider.notifier).cancelarNomina(nominaId: nominaId, motivo: MotivoCancelacionNomina.errorDeCaptura);

    expect(resultado, isA<CancelarNominaErrorInesperado>());
    final nomina = await container.read(nominaRepositoryProvider).obtenerPorId(nominaId);
    expect(nomina!.estatus, isNot('cancelada'));
  });

  test('nomina.corregir y nomina.cancelar (sin ningún otro código) SÍ alcanzan para ambas acciones', () async {
    // Etapa 3B: la autorización se revalida contra la base, así que
    // este escenario —el de ESTA prueba— se persiste antes de usarlo.
    await sembrarSesionEnBase(db, _SesionSoloCorregirYCancelar().build()!);
    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db), sesionControllerProvider.overrideWith(_SesionSoloCorregirYCancelar.new)],
    );
    addTearDown(container.dispose);

    final corregido = await container.read(nominasControllerProvider.notifier).corregirRenglon(
          nominaEmpleadoId: renglonId,
          bono: 123456,
          motivo: 'Corrección con el permiso correcto',
        );
    expect(corregido, isA<CorregirRenglonNominaExitoso>());
    final renglon = await container.read(nominaRepositoryProvider).obtenerEmpleado(renglonId);
    expect(renglon!.bono, 123456);

    final cancelado = await container
        .read(nominasControllerProvider.notifier)
        .cancelarNomina(nominaId: nominaId, motivo: MotivoCancelacionNomina.errorDeCaptura);
    expect(cancelado, isA<CancelarNominaExitoso>(), reason: 'Cerrada sin ningún PagoNomina real — la corrección de bono no crea ningún pago');
  });
}
