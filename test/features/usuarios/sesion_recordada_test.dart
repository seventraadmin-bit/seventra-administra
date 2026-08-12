// Etapa 15 (hallazgo funcional/UX: Inicio de sesión) — "Recuérdame en
// este equipo": token aleatorio nunca la contraseña, hash SHA-256 en
// SQLite, token en texto plano solo en un Almacén en memoria de prueba
// (el real usa Windows Credential Manager, no responde bajo
// `flutter test` — mismo criterio que `CredentialCipher`).

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/auth/password_hasher.dart';
import 'package:riseg_one/core/auth/sesion_recordada_almacen.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/usuarios/data/repositories/permiso_usuario_repository_impl.dart';
import 'package:riseg_one/features/usuarios/data/repositories/usuario_repository_impl.dart';
import 'package:riseg_one/features/usuarios/domain/usecases/cambiar_contrasena_usuario_usecase.dart';
import 'package:riseg_one/features/usuarios/domain/usecases/desactivar_usuario_usecase.dart';
import 'package:riseg_one/features/usuarios/domain/usecases/login_usecase.dart';
import 'package:riseg_one/features/usuarios/domain/usecases/restaurar_sesion_recordada_usecase.dart';

class _AlmacenSesionRecordadaEnMemoria implements AlmacenSesionRecordada {
  String? _token;

  @override
  Future<String?> leer() async => _token;

  @override
  Future<void> escribir(String valor) async => _token = valor;

  @override
  Future<void> borrar() async => _token = null;
}

void main() {
  late AppDatabase db;
  late UsuarioRepositoryImpl usuarioRepo;
  late PermisoUsuarioRepositoryImpl permisoUsuarioRepo;
  late PasswordHasher hasher;
  late _AlmacenSesionRecordadaEnMemoria almacen;
  late LoginUseCase login;
  late RestaurarSesionRecordadaUseCase restaurar;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    usuarioRepo = UsuarioRepositoryImpl(db);
    permisoUsuarioRepo = PermisoUsuarioRepositoryImpl(db);
    hasher = const PasswordHasher(iteraciones: 1000);
    almacen = _AlmacenSesionRecordadaEnMemoria();
    login = LoginUseCase(usuarioRepo, permisoUsuarioRepo, hasher, almacen);
    restaurar = RestaurarSesionRecordadaUseCase(usuarioRepo, permisoUsuarioRepo, almacen);

    await usuarioRepo.crear(
      nombre: 'Ana Torres',
      nombreUsuario: 'ana.torres',
      passwordHash: hasher.hash('Sup3rSecreta!'),
      esMaestro: true,
    );
    await usuarioRepo.crear(
      nombre: 'Beto Ruiz',
      nombreUsuario: 'beto',
      passwordHash: hasher.hash('ClaveSegura1'),
    );
  });

  tearDown(() => db.close());

  test('checkbox desmarcado (recordarme: false) no deja nada para restaurar', () async {
    final resultado = await login.ejecutar(nombreUsuario: 'ana.torres', password: 'Sup3rSecreta!');
    expect(resultado, isA<LoginExitoso>());
    expect(await almacen.leer(), isNull);

    final restaurada = await restaurar.ejecutar();
    expect(restaurada, isNull);
  });

  test('checkbox marcado (recordarme: true) restaura la sesión completa al "reiniciar"', () async {
    final resultado =
        await login.ejecutar(nombreUsuario: 'ana.torres', password: 'Sup3rSecreta!', recordarme: true);
    expect(resultado, isA<LoginExitoso>());
    expect(await almacen.leer(), isNotNull);

    final restaurada = await restaurar.ejecutar();
    expect(restaurada, isNotNull);
    expect(restaurada!.nombreUsuario, 'ana.torres');
    expect(restaurada.esMaestro, isTrue);
  });

  test('Maestro recordado obtiene el catálogo completo de permisos, igual que un login normal', () async {
    await login.ejecutar(nombreUsuario: 'ana.torres', password: 'Sup3rSecreta!', recordarme: true);
    final restaurada = await restaurar.ejecutar();
    expect(restaurada!.permisos, isNotEmpty);
  });

  test('Usuario normal recordado obtiene sus PermisoUsuario reales (aquí, ninguno)', () async {
    await login.ejecutar(nombreUsuario: 'beto', password: 'ClaveSegura1', recordarme: true);
    final restaurada = await restaurar.ejecutar();
    expect(restaurada!.esMaestro, isFalse);
    expect(restaurada.permisos, isEmpty);
  });

  test('el token guardado nunca es la contraseña ni un derivado reutilizable de PasswordHasher', () async {
    await login.ejecutar(nombreUsuario: 'ana.torres', password: 'Sup3rSecreta!', recordarme: true);
    final token = await almacen.leer();
    expect(token, isNotNull);
    expect(token, isNot('Sup3rSecreta!'));
    expect(token, isNot(contains('Sup3rSecreta')));
    expect(token, isNot(startsWith('pbkdf2\$')), reason: 'nunca el formato de PasswordHasher');
    // El hash que viaja a SQLite es de un algoritmo y una entrada
    // completamente distintos del hash de la contraseña — no hay forma
    // de derivar uno del otro.
    expect(hashTokenSesion(token!), isNot(hasher.hash('Sup3rSecreta!')));
  });

  test('un token que no corresponde a ninguna fila (BD sin el Usuario recordado) exige Login normal', () async {
    await almacen.escribir('token-que-nunca-se-guardo-en-sqlite');
    final restaurada = await restaurar.ejecutar();
    expect(restaurada, isNull);
    expect(await almacen.leer(), isNull, reason: 'el token inválido se limpia del Almacén');
  });

  test('cambiar la contraseña invalida la sesión recordada existente (misma transacción)', () async {
    final loginResultado =
        await login.ejecutar(nombreUsuario: 'ana.torres', password: 'Sup3rSecreta!', recordarme: true);
    final usuarioId = (loginResultado as LoginExitoso).sesion.usuarioId;

    await CambiarContrasenaUsuarioUseCase(usuarioRepo, hasher).ejecutar(usuarioId: usuarioId, password: 'NuevaClave1');

    // El Almacén todavía tiene el token viejo (nadie lo tocó desde
    // fuera), pero la fila de SesionPersistente ya no existe.
    final restaurada = await restaurar.ejecutar();
    expect(restaurada, isNull);
  });

  test('desactivar el Usuario invalida la sesión recordada existente', () async {
    final loginResultado =
        await login.ejecutar(nombreUsuario: 'beto', password: 'ClaveSegura1', recordarme: true);
    final usuarioId = (loginResultado as LoginExitoso).sesion.usuarioId;

    await DesactivarUsuarioUseCase(usuarioRepo).ejecutar(usuarioId: usuarioId, motivo: 'prueba');

    final restaurada = await restaurar.ejecutar();
    expect(restaurada, isNull);
  });

  test('un segundo "recuérdame" reemplaza al primero — un solo slot por equipo', () async {
    await login.ejecutar(nombreUsuario: 'ana.torres', password: 'Sup3rSecreta!', recordarme: true);
    await login.ejecutar(nombreUsuario: 'beto', password: 'ClaveSegura1', recordarme: true);

    final restaurada = await restaurar.ejecutar();
    expect(restaurada!.nombreUsuario, 'beto');
  });

  test('logout (vía UsuarioRepository.borrarSesionPersistente + Almacén) impide el auto-login siguiente', () async {
    await login.ejecutar(nombreUsuario: 'ana.torres', password: 'Sup3rSecreta!', recordarme: true);

    // Mismo par de pasos que `SesionController.logout()`.
    final usuario = await usuarioRepo.obtenerPorNombreUsuario('ana.torres');
    await usuarioRepo.borrarSesionPersistente(usuario!.id);
    await almacen.borrar();

    final restaurada = await restaurar.ejecutar();
    expect(restaurada, isNull);
  });
}
