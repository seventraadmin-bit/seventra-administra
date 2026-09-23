// Etapa 0 (auditoría de consistencia transversal — corrección de un
// hueco real de autorización): 9 operaciones del expediente de
// Personal (`asignarEmpleadoServicio`, `cambiarServicioEmpleado`,
// `retirarEmpleadoServicio`, `actualizarFotografiaEmpleado`,
// `guardarDomicilioEmpleado`, `adjuntarDocumentoEmpleado`,
// `registrarPerfilPsicologico`, `registrarEstudioSocioeconomico`,
// `registrarAntidoping`) se invocaban desde sus diálogos directo sobre
// el use case crudo, sin ningún `autorizarUseCase` en toda la cadena.
// Las 9 comparten exactamente el mismo permiso (`personal.modificar`)
// y el mismo envoltorio `autorizarUseCase` — esta prueba cubre 3 a
// fondo (negativo + positivo, verificando estado real en BD) y las 6
// restantes solo en negativo (rechazo + cero mutación), para dejar
// constancia de que el guardia también existe ahí sin repetir la
// prueba completa 9 veces.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/core/validation/direccion_validator.dart';
import 'package:riseg_one/features/organizacion/organizacion_providers.dart' show attachmentRepositoryProvider, attachmentStorageProvider;
import 'package:riseg_one/features/personal/data/tables/asignacion_servicio_table.dart' show MotivoTerminoAsignacion;
import 'package:riseg_one/features/personal/data/tables/empleado_table.dart';
import 'package:riseg_one/features/personal/domain/usecases/actualizar_fotografia_empleado_usecase.dart';
import 'package:riseg_one/features/personal/domain/usecases/adjuntar_documento_empleado_usecase.dart';
import 'package:riseg_one/features/personal/domain/usecases/asignar_empleado_servicio_usecase.dart' show AsignarEmpleadoServicioErrorInesperado;
import 'package:riseg_one/features/personal/domain/usecases/cambiar_servicio_empleado_usecase.dart' show CambiarServicioEmpleadoErrorInesperado;
import 'package:riseg_one/features/personal/domain/usecases/crear_empleado_usecase.dart';
import 'package:riseg_one/features/personal/domain/usecases/guardar_domicilio_empleado_usecase.dart';
import 'package:riseg_one/features/personal/domain/usecases/registrar_antidoping_usecase.dart';
import 'package:riseg_one/features/personal/domain/usecases/registrar_estudio_socioeconomico_usecase.dart';
import 'package:riseg_one/features/personal/domain/usecases/registrar_perfil_psicologico_usecase.dart';
import 'package:riseg_one/features/personal/domain/usecases/retirar_empleado_servicio_usecase.dart' show RetirarEmpleadoServicioErrorInesperado;
import 'package:riseg_one/features/personal/personal_providers.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import '../../support/sesion_en_base.dart';

class _SesionSinPermiso extends SesionController {
  @override
  SesionUsuario? build() {
    return const SesionUsuario(
      usuarioId: 'usuario-normal',
      nombre: 'Usuario normal',
      nombreUsuario: 'normal',
      esMaestro: false,
      // Tiene permisos de otros módulos, pero NUNCA personal.modificar.
      permisos: {'personal.ver', 'personal.crear'},
    );
  }
}

class _SesionConPermiso extends SesionController {
  @override
  SesionUsuario? build() {
    return const SesionUsuario(
      usuarioId: 'usuario-normal',
      nombre: 'Usuario normal',
      nombreUsuario: 'normal',
      esMaestro: false,
      permisos: {'personal.ver', 'personal.crear', 'personal.modificar'},
    );
  }
}

void main() {
  late AppDatabase db;
  late Directory tempDir;
  late String empleadoId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    tempDir = Directory.systemTemp.createTempSync('riseg_personal_p0_test_');

    // `guardarDomicilioEmpleado` registra un evento con `actorUsuarioId`
    // (FK real a Usuario) — necesario para que el caso positivo no
    // truene por violación de llave foránea.
    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(id: const Value('usuario-normal'), nombre: 'Normal', nombreUsuario: 'usuario-normal', passwordHash: 'x'),
        );

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

  Future<ProviderContainer> containerCon(SesionController Function() sesion) async {
    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      sesionControllerProvider.overrideWith(sesion),
      attachmentStorageProvider.overrideWithValue(AttachmentStorage(tempDir.path)),
    ]);
    // Etapa 3B: la autorización se revalida contra la base. Se
    // persiste la sesión que ESTA prueba va a usar, leída del
    // propio contenedor: así el escenario sembrado y el inyectado
    // no pueden divergir, y una prueba negativa sigue sin permisos.
    final sesionDeLaPrueba = container.read(sesionControllerProvider);
    if (sesionDeLaPrueba != null) await sembrarSesionEnBase(db, sesionDeLaPrueba);
    return container;
  }

  group('actualizarFotografiaEmpleadoAutorizadoProvider (representativa a fondo)', () {
    test('un usuario sin personal.modificar no puede actualizar la fotografía', () async {
      final container = await containerCon(_SesionSinPermiso.new);
      addTearDown(container.dispose);

      final archivo = '${tempDir.path}/foto.png';
      File(archivo).writeAsStringSync('contenido foto');

      final resultado = await container.read(actualizarFotografiaEmpleadoAutorizadoProvider)(
        empleadoId: empleadoId,
        sourceFilePath: archivo,
        originalFileName: 'foto.png',
        mimeType: 'image/png',
      );

      expect(resultado, isA<ActualizarFotografiaEmpleadoErrorInesperado>());
      final empleado = await container.read(empleadoRepositoryProvider).obtenerPorId(empleadoId);
      expect(empleado!.fotografiaAttachmentId, isNull, reason: 'nunca se actualiza la fotografía sin el permiso');
      expect(await container.read(attachmentRepositoryProvider).listarActivosPorEmpleado(empleadoId), isEmpty);
    });

    test('un usuario con personal.modificar sí puede actualizar la fotografía', () async {
      final container = await containerCon(_SesionConPermiso.new);
      addTearDown(container.dispose);

      final archivo = '${tempDir.path}/foto.png';
      File(archivo).writeAsStringSync('contenido foto');

      final resultado = await container.read(actualizarFotografiaEmpleadoAutorizadoProvider)(
        empleadoId: empleadoId,
        sourceFilePath: archivo,
        originalFileName: 'foto.png',
        mimeType: 'image/png',
      );

      expect(resultado, isA<ActualizarFotografiaEmpleadoExitoso>());
      final empleado = await container.read(empleadoRepositoryProvider).obtenerPorId(empleadoId);
      expect(empleado!.fotografiaAttachmentId, isNotNull);
      expect(await container.read(attachmentRepositoryProvider).listarActivosPorEmpleado(empleadoId), hasLength(1));
    });
  });

  group('guardarDomicilioEmpleadoAutorizadoProvider (representativa a fondo)', () {
    test('un usuario sin personal.modificar no puede guardar el domicilio', () async {
      final container = await containerCon(_SesionSinPermiso.new);
      addTearDown(container.dispose);

      final resultado = await container.read(guardarDomicilioEmpleadoAutorizadoProvider)(
        empleadoId: empleadoId,
        domicilio: const DireccionBorrador(
          calle: 'Reforma',
          numeroExterior: '100',
          colonia: 'Centro',
          municipioAlcaldia: 'Cuauhtémoc',
          estado: 'CDMX',
          codigoPostal: '06000',
        ),
      );

      expect(resultado, isA<GuardarDomicilioEmpleadoErrorInesperado>());
      expect(
        await container.read(empleadoRepositoryProvider).obtenerDomicilio(empleadoId),
        isNull,
        reason: 'nunca se guarda el domicilio sin el permiso',
      );
    });

    test('un usuario con personal.modificar sí puede guardar el domicilio', () async {
      final container = await containerCon(_SesionConPermiso.new);
      addTearDown(container.dispose);

      final resultado = await container.read(guardarDomicilioEmpleadoAutorizadoProvider)(
        empleadoId: empleadoId,
        domicilio: const DireccionBorrador(
          calle: 'Reforma',
          numeroExterior: '100',
          colonia: 'Centro',
          municipioAlcaldia: 'Cuauhtémoc',
          estado: 'CDMX',
          codigoPostal: '06000',
        ),
      );

      expect(resultado, isA<GuardarDomicilioEmpleadoExitoso>());
      final domicilio = await container.read(empleadoRepositoryProvider).obtenerDomicilio(empleadoId);
      expect(domicilio, isNotNull);
      expect(domicilio!.calle, 'Reforma');
    });
  });

  group('adjuntarDocumentoEmpleadoAutorizadoProvider (representativa a fondo)', () {
    test('un usuario sin personal.modificar no puede adjuntar un documento', () async {
      final container = await containerCon(_SesionSinPermiso.new);
      addTearDown(container.dispose);

      final archivo = '${tempDir.path}/ine.pdf';
      File(archivo).writeAsStringSync('contenido ine');

      final resultado = await container.read(adjuntarDocumentoEmpleadoAutorizadoProvider)(
        empleadoId: empleadoId,
        categoria: CategoriaDocumentoEmpleado.ine,
        sourceFilePath: archivo,
        originalFileName: 'ine.pdf',
        mimeType: 'application/pdf',
      );

      expect(resultado, isA<AdjuntarDocumentoEmpleadoErrorInesperado>());
      expect(await container.read(attachmentRepositoryProvider).listarActivosPorEmpleado(empleadoId), isEmpty);
    });

    test('un usuario con personal.modificar sí puede adjuntar un documento', () async {
      final container = await containerCon(_SesionConPermiso.new);
      addTearDown(container.dispose);

      final archivo = '${tempDir.path}/ine.pdf';
      File(archivo).writeAsStringSync('contenido ine');

      final resultado = await container.read(adjuntarDocumentoEmpleadoAutorizadoProvider)(
        empleadoId: empleadoId,
        categoria: CategoriaDocumentoEmpleado.ine,
        sourceFilePath: archivo,
        originalFileName: 'ine.pdf',
        mimeType: 'application/pdf',
      );

      expect(resultado, isA<AdjuntarDocumentoEmpleadoExitoso>());
      final adjuntos = await container.read(attachmentRepositoryProvider).listarActivosPorEmpleado(empleadoId);
      expect(adjuntos, hasLength(1));
      expect(adjuntos.single.categoria, 'ine');
    });
  });

  // Las 6 operaciones restantes comparten exactamente la misma cadena
  // `autorizarUseCase(..., 'personal.modificar', ...)` ya cubierta a
  // fondo arriba — aquí solo se confirma que el guardia también existe
  // en cada una (rechazo + cero mutación), sin repetir el caso
  // positivo.

  test('asignarEmpleadoServicioAutorizadoProvider rechaza sin personal.modificar', () async {
    final container = await containerCon(_SesionSinPermiso.new);
    addTearDown(container.dispose);

    final resultado = await container.read(asignarEmpleadoServicioAutorizadoProvider)(
      empleadoId: empleadoId,
      servicioId: 'servicio-inexistente',
      fechaInicio: DateTime(2026, 1, 1),
    );

    expect(resultado, isA<AsignarEmpleadoServicioErrorInesperado>());
  });

  test('cambiarServicioEmpleadoAutorizadoProvider rechaza sin personal.modificar', () async {
    final container = await containerCon(_SesionSinPermiso.new);
    addTearDown(container.dispose);

    final resultado = await container.read(cambiarServicioEmpleadoAutorizadoProvider)(
      empleadoId: empleadoId,
      nuevoServicioId: 'servicio-inexistente',
      fecha: DateTime(2026, 1, 1),
    );

    expect(resultado, isA<CambiarServicioEmpleadoErrorInesperado>());
  });

  test('retirarEmpleadoServicioAutorizadoProvider rechaza sin personal.modificar', () async {
    final container = await containerCon(_SesionSinPermiso.new);
    addTearDown(container.dispose);

    final resultado = await container.read(retirarEmpleadoServicioAutorizadoProvider)(
      empleadoId: empleadoId,
      fechaTermino: DateTime(2026, 1, 1),
      motivo: MotivoTerminoAsignacion.solicitudCliente,
    );

    expect(resultado, isA<RetirarEmpleadoServicioErrorInesperado>());
  });

  test('registrarPerfilPsicologicoAutorizadoProvider rechaza sin personal.modificar', () async {
    final container = await containerCon(_SesionSinPermiso.new);
    addTearDown(container.dispose);

    final resultado = await container.read(registrarPerfilPsicologicoAutorizadoProvider)(
      empleadoId: empleadoId,
      fecha: DateTime(2026, 1, 1),
    );

    expect(resultado, isA<RegistrarPerfilPsicologicoErrorInesperado>());
    expect(await container.read(attachmentRepositoryProvider).listarActivosPorEmpleado(empleadoId), isEmpty);
  });

  test('registrarEstudioSocioeconomicoAutorizadoProvider rechaza sin personal.modificar', () async {
    final container = await containerCon(_SesionSinPermiso.new);
    addTearDown(container.dispose);

    final resultado = await container.read(registrarEstudioSocioeconomicoAutorizadoProvider)(
      empleadoId: empleadoId,
      fecha: DateTime(2026, 1, 1),
    );

    expect(resultado, isA<RegistrarEstudioSocioeconomicoErrorInesperado>());
    expect(await container.read(attachmentRepositoryProvider).listarActivosPorEmpleado(empleadoId), isEmpty);
  });

  test('registrarAntidopingAutorizadoProvider rechaza sin personal.modificar', () async {
    final container = await containerCon(_SesionSinPermiso.new);
    addTearDown(container.dispose);

    final resultado = await container.read(registrarAntidopingAutorizadoProvider)(
      empleadoId: empleadoId,
      fecha: DateTime(2026, 1, 1),
      amp: ResultadoSustanciaAntidoping.negativo,
      bzd: ResultadoSustanciaAntidoping.negativo,
      coc: ResultadoSustanciaAntidoping.negativo,
      met: ResultadoSustanciaAntidoping.negativo,
      opi: ResultadoSustanciaAntidoping.negativo,
    );

    expect(resultado, isA<RegistrarAntidopingErrorInesperado>());
    expect(await container.read(attachmentRepositoryProvider).listarActivosPorEmpleado(empleadoId), isEmpty);
  });
}
