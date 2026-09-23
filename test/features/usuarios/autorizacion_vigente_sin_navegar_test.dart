// Etapa 3B, cierre de seguridad — autorización contra el estado
// VIGENTE, sin depender de que nadie navegue.
//
// El cierre anterior dejaba la revocación atada al `redirect` del
// router: quien se quedaba quieto en una pantalla conservaba su
// autorización indefinidamente. Una persona a la que acaban de dar de
// baja podía seguir ejecutando mutaciones desde la ventana que ya tenía
// abierta. La seguridad no puede depender de un cambio de ruta.
//
// Todas estas pruebas ejecutan la operación protegida **directamente**
// sobre el `ProviderContainer`, sin montar un solo widget y sin navegar
// ni una vez: es exactamente el escenario que faltaba.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/auth/password_hasher.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/core/permissions/authorization_service.dart';
import 'package:riseg_one/core/permissions/modulos_permiso.dart';
import 'package:riseg_one/features/inventario/data/repositories/asignacion_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/empleado_repository_impl.dart';
import 'package:riseg_one/features/personal/data/tables/empleado_table.dart';
import 'package:riseg_one/features/personal/domain/usecases/empleado_validator.dart';
import 'package:riseg_one/features/personal/domain/usecases/registrar_baja_laboral_usecase.dart';
import 'package:riseg_one/features/usuarios/data/repositories/usuario_repository_impl.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/domain/usecases/cambiar_contrasena_usuario_usecase.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import 'package:riseg_one/features/usuarios/usuarios_providers.dart';
import 'package:riseg_one/features/vehiculos/data/repositories/asignacion_vehiculo_repository_impl.dart';

class _SesionInicial extends SesionController {
  _SesionInicial(this._inicial);
  final SesionUsuario? _inicial;

  @override
  SesionUsuario? build() => _inicial;
}

/// Resultado sellado mínimo, del mismo molde que los del proyecto.
sealed class _Resultado {}

class _Ok extends _Resultado {}

class _Denegado extends _Resultado {
  _Denegado(this.mensaje);
  final String mensaje;
}

void main() {
  late AppDatabase db;
  const hasher = PasswordHasher(iteraciones: 1000);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  Future<UsuarioData> cuenta({
    String usuario = 'javier',
    bool esMaestro = false,
    Set<String> permisos = const {},
    String? empleadoId,
  }) async {
    final fila = await db
        .into(db.usuario)
        .insertReturning(
          UsuarioCompanion.insert(
            nombre: usuario.toUpperCase(),
            nombreUsuario: usuario,
            passwordHash: hasher.hash('contrasena1'),
            esMaestro: Value(esMaestro),
            empleadoId: Value(empleadoId),
          ),
        );
    for (final codigo in permisos) {
      await db.into(db.permisoUsuario).insert(PermisoUsuarioCompanion.insert(usuarioId: fila.id, codigo: codigo));
    }
    return fila;
  }

  Future<String> empleadoFixture({int numero = 1}) async {
    final fila = await db
        .into(db.empleado)
        .insertReturning(
          EmpleadoCompanion.insert(
            numeroEmpleado: numero,
            nombres: 'JAVIER',
            apellidoPaterno: 'RIOS',
            sexo: 'masculino',
            fechaNacimiento: DateTime(1990, 1, 1),
            curp: 'RISJ900101HDFXX$numero',
            rfc: 'RISJ900101A$numero',
            nss: '123456789$numero',
            estadoCivil: 'soltero',
            fechaIngreso: DateTime(2026, 1, 1),
            aniosExperienciaSeguridad: 3,
          ),
        );
    return fila.id;
  }

  ProviderContainer contenedorCon(SesionUsuario? sesion) {
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(() => _SesionInicial(sesion)),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  SesionUsuario sesionDe(UsuarioData u, Set<String> permisos) => SesionUsuario(
    usuarioId: u.id,
    nombre: u.nombre,
    nombreUsuario: u.nombreUsuario,
    esMaestro: u.esMaestro,
    permisos: permisos,
  );

  /// Una mutación protegida cualquiera, por el MISMO embudo que usan las
  /// 216 operaciones reales del proyecto. Nunca se navega.
  Future<_Resultado> intentarMutacion(ProviderContainer c, String codigo) {
    return autorizarUseCase<_Resultado>(
      c.read(authorizationServiceProvider),
      codigo,
      () async => _Ok(),
      _Denegado.new,
    );
  }

  /// Una facultad extraordinaria de Maestro, por el otro embudo.
  Future<_Resultado> intentarMaestro(ProviderContainer c) {
    return exigirMaestro<_Resultado>(c.read(permissionServiceProvider), () async => _Ok(), _Denegado.new);
  }

  test('A. desactivado mientras tiene la pantalla abierta: la mutación queda DENEGADA', () async {
    final u = await cuenta(permisos: {'personal.crear'});
    final c = contenedorCon(sesionDe(u, {'personal.crear'}));
    expect(await intentarMutacion(c, 'personal.crear'), isA<_Ok>(), reason: 'antes de desactivar, opera');

    // Un administrador lo desactiva. JAVIER no navega: sigue donde estaba.
    await (db.update(db.usuario)..where((t) => t.id.equals(u.id)))
        .write(const UsuarioCompanion(cicloVidaRegistro: Value('inactivo')));

    expect(await intentarMutacion(c, 'personal.crear'), isA<_Denegado>());
    expect(c.read(sesionControllerProvider), isNull, reason: 'y además la sesión queda inválida');
  });

  test('B. baja laboral del empleado vinculado: su cuenta queda DENEGADA sin navegar', () async {
    final empleadoId = await empleadoFixture();
    final u = await cuenta(permisos: {'personal.crear'}, empleadoId: empleadoId);
    final c = contenedorCon(sesionDe(u, {'personal.crear'}));
    expect(await intentarMutacion(c, 'personal.crear'), isA<_Ok>());

    final baja = await RegistrarBajaLaboralUseCase(
      EmpleadoRepositoryImpl(db, AsignacionServicioRepositoryImpl(db)),
      const EmpleadoValidator(),
      AsignacionRepositoryImpl(db),
      AsignacionVehiculoRepositoryImpl(db),
      usuarioRepository: UsuarioRepositoryImpl(db),
    ).ejecutar(empleadoId: empleadoId, fechaBaja: DateTime(2026, 6, 30), motivo: MotivoBajaEmpleado.renuncia);
    expect(baja, isA<RegistrarBajaLaboralExitoso>());

    expect(
      await intentarMutacion(c, 'personal.crear'),
      isA<_Denegado>(),
      reason: 'quien acaba de causar baja no puede seguir operando desde la ventana que ya tenía abierta',
    );
  });

  test('C. permiso REVOCADO se aplica sin navegar', () async {
    final u = await cuenta(permisos: {'personal.crear', 'personal.ver'});
    final c = contenedorCon(sesionDe(u, {'personal.crear', 'personal.ver'}));
    expect(await intentarMutacion(c, 'personal.crear'), isA<_Ok>());

    await (db.delete(db.permisoUsuario)..where((t) => t.codigo.equals('personal.crear'))).go();

    expect(await intentarMutacion(c, 'personal.crear'), isA<_Denegado>());
    expect(await intentarMutacion(c, 'personal.ver'), isA<_Ok>(), reason: 'sólo se revocó uno');
  });

  test('D. permiso CONCEDIDO se aplica sin relogin ni navegación', () async {
    final u = await cuenta(permisos: {'personal.ver'});
    final c = contenedorCon(sesionDe(u, {'personal.ver'}));
    expect(await intentarMutacion(c, 'nomina.crear'), isA<_Denegado>());

    await db.into(db.permisoUsuario).insert(
      PermisoUsuarioCompanion.insert(usuarioId: u.id, codigo: 'nomina.crear'),
    );

    expect(await intentarMutacion(c, 'nomina.crear'), isA<_Ok>());
  });

  test('E. Maestro DEGRADADO no vuelve a pasar exigirMaestro sin navegar', () async {
    final u = await cuenta(usuario: 'marlon', esMaestro: true);
    final c = contenedorCon(sesionDe(u, todosLosCodigosDePermiso()));
    expect(await intentarMaestro(c), isA<_Ok>());

    await (db.update(db.usuario)..where((t) => t.id.equals(u.id)))
        .write(const UsuarioCompanion(esMaestro: Value(false)));

    expect(
      await intentarMaestro(c),
      isA<_Denegado>(),
      reason: 'la facultad que autoriza respaldo y eliminación física no puede colgar de un booleano en memoria',
    );
    // Y tampoco recupera el acceso total por la otra vía.
    expect(await intentarMutacion(c, 'respaldo.ver'), isA<_Denegado>());
  });

  test('F. una sesión que dice ser una cuenta INEXISTENTE no autoriza nada', () async {
    final c = contenedorCon(
      const SesionUsuario(
        usuarioId: 'cuenta-que-no-existe',
        nombre: 'FANTASMA',
        nombreUsuario: 'fantasma',
        esMaestro: true,
        permisos: {'personal.crear'},
      ),
    );

    expect(await intentarMutacion(c, 'personal.crear'), isA<_Denegado>());
    expect(await intentarMaestro(c), isA<_Denegado>(), reason: 'ni siquiera afirmándose Maestro');
    expect(c.read(sesionControllerProvider), isNull, reason: 'fail closed: la sesión queda inválida');
  });

  test('G. tras un reseteo administrativo la cuenta no ejecuta operaciones protegidas', () async {
    final u = await cuenta(permisos: {'personal.crear'});
    final c = contenedorCon(sesionDe(u, {'personal.crear'}));
    expect(await intentarMutacion(c, 'personal.crear'), isA<_Ok>());

    // Un administrador resetea: la contraseña vigente la conoce otra
    // persona, así que la cuenta queda obligada a cambiarla.
    await (db.update(db.usuario)..where((t) => t.id.equals(u.id)))
        .write(const UsuarioCompanion(debeCambiarPassword: Value(true)));

    expect(
      await intentarMutacion(c, 'personal.crear'),
      isA<_Denegado>(),
      reason: 'una cuenta con contraseña temporal existe, pero no opera',
    );
    expect(
      c.read(sesionControllerProvider),
      isNotNull,
      reason: 'la sesión NO se destruye: el titular tiene que poder cambiar su contraseña',
    );
    expect(c.read(sesionControllerProvider)!.debeCambiarPassword, isTrue);
  });

  test('H. el titular cambiando su PROPIA contraseña conserva la sesión y sigue operando', () async {
    final u = await cuenta(permisos: {'personal.crear'});
    final c = contenedorCon(sesionDe(u, {'personal.crear'}));

    final resultado = await c.read(cambiarMiContrasenaProvider)('contrasenaNueva1');
    expect(resultado, isA<CambiarContrasenaUsuarioExitoso>());

    expect(c.read(sesionControllerProvider), isNotNull);
    expect(c.read(sesionControllerProvider)!.debeCambiarPassword, isFalse);
    expect(
      await intentarMutacion(c, 'personal.crear'),
      isA<_Ok>(),
      reason: 'cambiar la propia contraseña es autoservicio, no una causa para perder el acceso',
    );
  });

  test('sin sesión, deny-by-default sigue intacto', () async {
    final c = contenedorCon(null);
    expect(await intentarMutacion(c, 'personal.ver'), isA<_Denegado>());
    expect(await intentarMaestro(c), isA<_Denegado>());
  });
}
