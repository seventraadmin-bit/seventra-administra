// Etapa 1B (cierre de seguridad):
// `generarFichaTecnicaEmpleadoAutorizadoProvider` estaba gateado por
// `personal.crear` sin razón real (confirmado por auditoría) — generar
// la ficha técnica de un Empleado YA EXISTENTE no crea ningún Empleado,
// es una consulta/generación de documento sobre datos ya visibles en su
// expediente. Ahora gatea con `personal.ver`. La prueba clave es la
// #1: una sesión con `personal.ver` pero explícitamente SIN
// `personal.crear` — antes de la corrección, esa sesión exacta habría
// sido rechazada.

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/organizacion/organizacion_providers.dart' show attachmentStorageProvider;
import 'package:riseg_one/features/personal/data/tables/empleado_table.dart';
import 'package:riseg_one/features/personal/domain/usecases/crear_empleado_usecase.dart';
import 'package:riseg_one/features/personal/domain/usecases/generar_ficha_tecnica_empleado_usecase.dart';
import 'package:riseg_one/features/personal/personal_providers.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

class _SesionSoloVer extends SesionController {
  @override
  SesionUsuario? build() {
    return const SesionUsuario(
      usuarioId: 'usuario-normal',
      nombre: 'Usuario normal',
      nombreUsuario: 'normal',
      esMaestro: false,
      // Deliberadamente SOLO personal.ver — SIN personal.crear. Antes de
      // la corrección, esta sesión exacta habría sido rechazada.
      permisos: {'personal.ver'},
    );
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
      // Tiene permisos de otros módulos, pero NUNCA personal.ver.
      permisos: {'organizacion.ver'},
    );
  }
}

class _SesionMaestro extends SesionController {
  @override
  SesionUsuario? build() {
    return const SesionUsuario(
      usuarioId: 'usuario-maestro',
      nombre: 'Maestro de prueba',
      nombreUsuario: 'maestro',
      esMaestro: true,
      permisos: {},
    );
  }
}

void main() {
  late AppDatabase db;
  late Directory tempDir;
  late String empleadoId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    tempDir = Directory.systemTemp.createTempSync('riseg_ficha_tecnica_autorizacion_test_');

    final container = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
    final resultado = await container.read(crearEmpleadoUseCaseProvider).ejecutar(
          nombres: 'Juan',
          apellidoPaterno: 'Pérez',
          sexo: SexoEmpleado.masculino,
          fechaNacimiento: DateTime(1990, 1, 1),
          curp: 'PEXJ900101HDFXXX01',
          rfc: 'PEXJ900101AB1',
          nss: '12345678901',
          estadoCivil: EstadoCivilEmpleado.soltero,
          fechaIngreso: DateTime(2026, 1, 1),
          aniosExperienciaSeguridad: 3,
        );
    empleadoId = (resultado as CrearEmpleadoExitoso).empleado.id;
    container.dispose();
  });

  tearDown(() {
    db.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  ProviderContainer containerCon(SesionController Function() sesion) {
    return ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      sesionControllerProvider.overrideWith(sesion),
      attachmentStorageProvider.overrideWithValue(AttachmentStorage(tempDir.path)),
    ]);
  }

  test('un usuario con personal.ver (pero explícitamente SIN personal.crear) sí puede generar la ficha técnica', () async {
    final container = containerCon(_SesionSoloVer.new);
    addTearDown(container.dispose);

    final resultado = await container.read(generarFichaTecnicaEmpleadoAutorizadoProvider)(empleadoId: empleadoId);

    expect(resultado, isA<GenerarFichaTecnicaEmpleadoExitoso>());
  });

  test('un usuario sin personal.ver no puede generar la ficha técnica', () async {
    final container = containerCon(_SesionSinPermiso.new);
    addTearDown(container.dispose);

    final resultado = await container.read(generarFichaTecnicaEmpleadoAutorizadoProvider)(empleadoId: empleadoId);

    expect(resultado, isA<GenerarFichaTecnicaEmpleadoErrorInesperado>());
    expect(
      (resultado as GenerarFichaTecnicaEmpleadoErrorInesperado).mensaje,
      'No tiene permiso para realizar esta acción.',
    );
  });

  test('el Usuario Maestro (sin filas de PermisoUsuario) sí puede generar la ficha técnica', () async {
    final container = containerCon(_SesionMaestro.new);
    addTearDown(container.dispose);

    final resultado = await container.read(generarFichaTecnicaEmpleadoAutorizadoProvider)(empleadoId: empleadoId);

    expect(resultado, isA<GenerarFichaTecnicaEmpleadoExitoso>());
  });

  test('generar la ficha técnica nunca muta la fila de Empleado (solo inserta un histórico de FichaTecnicaEmpleado)', () async {
    final container = containerCon(_SesionSoloVer.new);
    addTearDown(container.dispose);

    final empleadoAntes = await container.read(empleadoRepositoryProvider).obtenerPorId(empleadoId);

    final resultado = await container.read(generarFichaTecnicaEmpleadoAutorizadoProvider)(empleadoId: empleadoId);
    expect(resultado, isA<GenerarFichaTecnicaEmpleadoExitoso>());

    final empleadoDespues = await container.read(empleadoRepositoryProvider).obtenerPorId(empleadoId);

    expect(empleadoDespues, empleadoAntes, reason: 'la fila de Empleado nunca cambia al generar la ficha técnica');
  });
}
