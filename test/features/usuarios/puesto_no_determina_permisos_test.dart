// Etapa 3B — el puesto es DESCRIPTIVO. Nunca autoriza nada.
//
// Esta regla ya existía y estaba probada para el puesto propio de una
// cuenta. Lo que la Etapa 3B introduce es una vía nueva por la que el
// puesto llega a un Usuario —el del Empleado vinculado— y con ella la
// tentación futura de "si es Gerente, que pueda ver Nómina". Estas
// pruebas son el candado contra esa idea: lo único que decide es
// `PermisoUsuario`, y cambiar de puesto no concede ni revoca nada.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/auth/password_hasher.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import 'package:riseg_one/features/usuarios/usuarios_providers.dart';

class _SesionDe extends SesionController {
  _SesionDe(this._sesion);
  final SesionUsuario _sesion;

  @override
  SesionUsuario? build() => _sesion;
}

void main() {
  late AppDatabase db;
  const hasher = PasswordHasher(iteraciones: 1000);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  Future<String> puestoFixture(String nombre) async {
    final area = (await db.select(db.area).get()).first;
    final fila = await db
        .into(db.puesto)
        .insertReturning(
          PuestoCompanion.insert(
            codigo: 'PUE-$nombre',
            nombre: nombre,
            areaId: area.id,
            tipo: 'administrativo',
            nivelJerarquico: 1,
          ),
        );
    return fila.id;
  }

  Future<String> empleadoFixture({required int numero, String? puestoId}) async {
    final fila = await db
        .into(db.empleado)
        .insertReturning(
          EmpleadoCompanion.insert(
            numeroEmpleado: numero,
            nombres: 'EMPLEADO$numero',
            apellidoPaterno: 'APELLIDO',
            sexo: 'masculino',
            fechaNacimiento: DateTime(1990, 1, 1),
            curp: 'PEXJ900101HDFXX$numero',
            rfc: 'PEXJ900101A$numero',
            nss: '123456789$numero',
            estadoCivil: 'soltero',
            fechaIngreso: DateTime(2026, 1, 1),
            aniosExperienciaSeguridad: 3,
            puestoId: Value(puestoId),
          ),
        );
    return fila.id;
  }

  Future<UsuarioData> cuentaFixture({
    required String usuario,
    String? puestoId,
    String? empleadoId,
    Set<String> permisos = const {},
  }) async {
    final fila = await db
        .into(db.usuario)
        .insertReturning(
          UsuarioCompanion.insert(
            nombre: usuario.toUpperCase(),
            nombreUsuario: usuario,
            passwordHash: hasher.hash('contrasena1'),
            puestoId: Value(puestoId),
            empleadoId: Value(empleadoId),
          ),
        );
    for (final codigo in permisos) {
      await db.into(db.permisoUsuario).insert(PermisoUsuarioCompanion.insert(usuarioId: fila.id, codigo: codigo));
    }
    return fila;
  }

  ProviderContainer contenedorPara(UsuarioData u, Set<String> permisos) {
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(
          () => _SesionDe(
            SesionUsuario(
              usuarioId: u.id,
              nombre: u.nombre,
              nombreUsuario: u.nombreUsuario,
              esMaestro: u.esMaestro,
              permisos: permisos,
            ),
          ),
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('34. dos cuentas con el MISMO puesto pueden tener permisos distintos', () async {
    final gerente = await puestoFixture('Gerente');
    final una = await cuentaFixture(usuario: 'una', puestoId: gerente, permisos: {'nomina.ver'});
    final otra = await cuentaFixture(usuario: 'otra', puestoId: gerente);

    final cUna = contenedorPara(una, {'nomina.ver'});
    final cOtra = contenedorPara(otra, const {});

    expect(cUna.read(permissionServiceProvider).hasCode('nomina.ver'), isTrue);
    expect(
      cOtra.read(permissionServiceProvider).hasCode('nomina.ver'),
      isFalse,
      reason: 'compartir puesto no comparte acceso; "Gerente" no es un rol',
    );
  });

  test('35. cambiar el puesto del EMPLEADO no cambia los permisos de su cuenta', () async {
    final auxiliar = await puestoFixture('Auxiliar');
    final director = await puestoFixture('Director');
    final empleadoId = await empleadoFixture(numero: 1, puestoId: auxiliar);
    final u = await cuentaFixture(usuario: 'javier', empleadoId: empleadoId, permisos: {'personal.ver'});
    final container = contenedorPara(u, {'personal.ver'});

    // Ascenso en Personal: el puesto visible de la cuenta cambia…
    await (db.update(db.empleado)..where((t) => t.id.equals(empleadoId)))
        .write(PuestoIdDeEmpleado(director).companion);
    await container.read(sesionControllerProvider.notifier).revalidar();

    final identidad = await container.read(usuarioRepositoryProvider).obtenerConIdentidad(u.id);
    expect(identidad!.nombrePuestoEfectivo, 'Director', reason: 'el puesto efectivo sí sigue al expediente');
    // …y el acceso NO.
    expect(container.read(permissionServiceProvider).hasCode('personal.ver'), isTrue);
    expect(
      container.read(permissionServiceProvider).hasCode('nomina.ver'),
      isFalse,
      reason: 'ascender a Director no concede Nómina: los permisos siguen siendo explícitos',
    );
    expect(container.read(permissionServiceProvider).esMaestroActivo, isFalse);
  });

  test('33. cambiar el puesto PROPIO de una cuenta independiente no cambia sus permisos', () async {
    final auxiliar = await puestoFixture('Auxiliar');
    final director = await puestoFixture('Director');
    final u = await cuentaFixture(usuario: 'externo', puestoId: auxiliar, permisos: {'personal.ver'});
    final container = contenedorPara(u, {'personal.ver'});

    await (db.update(db.usuario)..where((t) => t.id.equals(u.id)))
        .write(UsuarioCompanion(puestoId: Value(director)));
    await container.read(sesionControllerProvider.notifier).revalidar();

    expect(container.read(permissionServiceProvider).hasCode('personal.ver'), isTrue);
    expect(container.read(permissionServiceProvider).hasCode('nomina.ver'), isFalse);
  });

  test('ningún puesto puede fabricar un Maestro', () async {
    final director = await puestoFixture('Director General');
    final u = await cuentaFixture(usuario: 'director', puestoId: director, permisos: {'personal.ver'});
    final container = contenedorPara(u, {'personal.ver'});

    expect(
      container.read(permissionServiceProvider).esMaestroActivo,
      isFalse,
      reason: 'esMaestro es una columna, no una consecuencia del nombre del puesto',
    );
  });
}

/// Azúcar mínima para escribir sólo el puesto del Empleado sin arrastrar
/// el resto de columnas obligatorias.
extension type PuestoIdDeEmpleado(String id) {
  EmpleadoCompanion get companion => EmpleadoCompanion(puestoId: Value(id));
}
