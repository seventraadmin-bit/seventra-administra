// Etapa 3B — ausencia de N+1 al resolver la identidad efectiva,
// MEDIDA, no razonada.
//
// El listado de Usuarios tiene que leer el Empleado y el Puesto de cada
// cuenta. La forma ingenua —una consulta por fila— habría funcionado
// perfectamente con las dos cuentas que hay hoy y se habría vuelto un
// problema el día que haya cuarenta. Aquí se cuentan las sentencias
// reales contra SQLite con un `QueryInterceptor`: si alguien sustituye
// el `IN` por un bucle, el número crece y esta prueba falla.

import 'package:drift/backends.dart';
import 'package:drift/drift.dart' show ApplyInterceptor, QueryInterceptor;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/auth/password_hasher.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/organizacion/data/repositories/puesto_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/empleado_repository_impl.dart';
import 'package:riseg_one/features/usuarios/data/repositories/usuario_repository_impl.dart';
import 'package:riseg_one/features/usuarios/domain/usecases/crear_usuario_usecase.dart';

/// Cuenta cada sentencia que llega al motor. Es la única forma honesta
/// de demostrar que el número de consultas no depende del número de
/// filas — leer el código y confiar es justamente lo que deja pasar un
/// N+1.
class _Contador extends QueryInterceptor {
  int sentencias = 0;
  bool contando = false;

  void _registrar() {
    if (contando) sentencias++;
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(QueryExecutor executor, String statement, List<Object?> args) {
    _registrar();
    return executor.runSelect(statement, args);
  }

  @override
  Future<int> runUpdate(QueryExecutor executor, String statement, List<Object?> args) {
    _registrar();
    return executor.runUpdate(statement, args);
  }

  @override
  Future<int> runInsert(QueryExecutor executor, String statement, List<Object?> args) {
    _registrar();
    return executor.runInsert(statement, args);
  }

  @override
  Future<int> runDelete(QueryExecutor executor, String statement, List<Object?> args) {
    _registrar();
    return executor.runDelete(statement, args);
  }
}

void main() {
  late AppDatabase db;
  late _Contador contador;
  late UsuarioRepositoryImpl usuarioRepo;
  late CrearUsuarioUseCase crearUsuario;

  setUp(() {
    contador = _Contador();
    db = AppDatabase(NativeDatabase.memory().interceptWith(contador));
    usuarioRepo = UsuarioRepositoryImpl(db);
    crearUsuario = CrearUsuarioUseCase(
      usuarioRepo,
      PuestoRepositoryImpl(db),
      const PasswordHasher(iteraciones: 1000),
      EmpleadoRepositoryImpl(db, AsignacionServicioRepositoryImpl(db)),
    );
  });

  tearDown(() => db.close());

  Future<void> sembrar(int cuantas) async {
    for (var i = 0; i < cuantas; i++) {
      final empleado = await db
          .into(db.empleado)
          .insertReturning(
            EmpleadoCompanion.insert(
              numeroEmpleado: 100 + i,
              nombres: 'EMPLEADO$i',
              apellidoPaterno: 'APELLIDO$i',
              sexo: 'masculino',
              fechaNacimiento: DateTime(1990, 1, 1),
              curp: 'PEXJ900101HDFXX$i',
              rfc: 'PEXJ900101A$i',
              nss: '123456789$i',
              estadoCivil: 'soltero',
              fechaIngreso: DateTime(2026, 1, 1),
              aniosExperienciaSeguridad: 3,
            ),
          );
      final r = await crearUsuario.ejecutar(
        nombre: 'IGNORADO',
        nombreUsuario: 'usuario$i',
        password: 'contrasena1',
        empleadoId: empleado.id,
      );
      expect(r, isA<CrearUsuarioExitoso>());
    }
  }

  Future<int> consultasDe(Future<void> Function() operacion) async {
    contador.sentencias = 0;
    contador.contando = true;
    await operacion();
    contador.contando = false;
    return contador.sentencias;
  }

  test('listarConIdentidad no crece con el número de cuentas', () async {
    await sembrar(3);
    final conTres = await consultasDe(() => usuarioRepo.listarConIdentidad());

    // Base nueva, mismo repositorio, cuatro veces más cuentas.
    await db.close();
    contador = _Contador();
    db = AppDatabase(NativeDatabase.memory().interceptWith(contador));
    usuarioRepo = UsuarioRepositoryImpl(db);
    crearUsuario = CrearUsuarioUseCase(
      usuarioRepo,
      PuestoRepositoryImpl(db),
      const PasswordHasher(iteraciones: 1000),
      EmpleadoRepositoryImpl(db, AsignacionServicioRepositoryImpl(db)),
    );
    await sembrar(12);
    final conDoce = await consultasDe(() => usuarioRepo.listarConIdentidad());

    expect(
      conDoce,
      conTres,
      reason: 'cuadruplicar las cuentas no puede cambiar el número de consultas (hoy: usuarios + empleados + puestos)',
    );
    expect(conDoce, lessThanOrEqualTo(3));
  });

  test('la ficha de una cuenta hace consultas dirigidas, no recorre el listado', () async {
    await sembrar(12);
    final usuarios = await usuarioRepo.listar();

    final consultas = await consultasDe(() => usuarioRepo.obtenerConIdentidad(usuarios.first.id));

    expect(
      consultas,
      lessThanOrEqualTo(3),
      reason: 'usuario + su empleado + su puesto: abrir una ficha nunca lee las demás cuentas',
    );
  });
}
