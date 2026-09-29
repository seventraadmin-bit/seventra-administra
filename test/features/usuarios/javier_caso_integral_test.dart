// Etapa "Usuarios, permisos y UX de seguridad" — puntos 16 y 19 del
// pedido de Marlon.
//
// §19 CASO INTEGRAL JAVIER: recorre la vida completa de una cuenta real,
// de punta a punta y con las cifras/estados exactos de cada paso —
// empleado sin cuenta → alta vinculada con plantilla → primer acceso
// forzado → operación con sus permisos → intento de elevación → baja
// laboral → desactivación de la cuenta.
//
// §16 CAMBIO DE SESIÓN: cerrar sesión y entrar con otra cuenta nunca
// hereda nada de la anterior.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:riseg_one/app/router/app_router.dart';
import 'package:riseg_one/app/shell/shell_permissions.dart';
import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/core/auth/password_hasher.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/core/permissions/plantillas_permiso.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/domain/usecases/corregir_usuario_usecase.dart';
import 'package:riseg_one/features/usuarios/domain/usecases/crear_usuario_usecase.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import '../../support/sesion_en_base.dart';
import 'package:riseg_one/features/usuarios/presentation/usuarios_controller.dart';
import 'package:riseg_one/features/usuarios/usuarios_providers.dart';

/// Sesión de prueba mutable — a diferencia de las de otras pruebas, esta
/// permite cambiar de usuario en caliente, que es justamente lo que
/// verifica §16.
class _SesionDePrueba extends SesionController {
  _SesionDePrueba(this._inicial);
  final SesionUsuario? _inicial;

  @override
  SesionUsuario? build() => _inicial;

  /// Cambia de titular sin pasar por el login — sirve para comprobar
  /// que la sesión entrante no hereda nada de la anterior.
  ///
  /// Etapa 3B: la cuenta entrante también tiene que existir en la base,
  /// porque la autorización se revalida contra ella. Se siembra desde
  /// la propia prueba, justo antes de llamar aquí.
  void entrarComo(SesionUsuario sesion) => state = sesion;
}

const _hasher = PasswordHasher();

const _sesionMaestro = SesionUsuario(
  usuarioId: 'maestro',
  nombre: 'MARLON',
  nombreUsuario: 'marlon',
  esMaestro: true,
  permisos: {},
);

void main() {
  late AppDatabase db;
  late String empleadoJavierId;
  late String puestoId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());

    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(
            id: const Value('maestro'),
            nombre: 'MARLON',
            nombreUsuario: 'marlon',
            passwordHash: _hasher.hash('contrasenaMaestro1'),
            esMaestro: const Value(true),
          ),
        );

    var puestos = await db.select(db.puesto).get();
    if (puestos.isEmpty) {
      await db.into(db.puesto).insert(
            PuestoCompanion.insert(
              codigo: 'PUE-RH',
              nombre: 'Coordinador de Recursos Humanos',
              areaId: (await db.select(db.area).get()).first.id,
              tipo: 'administrativo',
              nivelJerarquico: 6,
            ),
          );
      puestos = await db.select(db.puesto).get();
    }
    puestoId = puestos.first.id;

    // JAVIER existe primero como EMPLEADO — el orden real: entra a la
    // empresa, y solo después (si le toca) recibe una cuenta.
    await db.into(db.empleado).insert(
          EmpleadoCompanion.insert(
            numeroEmpleado: 42,
            nombres: 'JAVIER',
            apellidoPaterno: 'RIOS',
            apellidoMaterno: const Value('MENDOZA'),
            sexo: 'masculino',
            fechaNacimiento: DateTime(1992, 5, 14),
            curp: 'RIMJ920514HDFXX1',
            rfc: 'RIMJ920514',
            nss: '10000000042',
            estadoCivil: 'soltero',
            fechaIngreso: DateTime(2026, 3, 2),
            aniosExperienciaSeguridad: 4,
            puestoId: Value(puestoId),
            estatus: const Value('activo'),
          ),
        );
    empleadoJavierId = (await db.select(db.empleado).get()).first.id;
  });

  tearDown(() => db.close());

  /// Etapa 3B: la autorización se revalida contra la base, así que el
  /// escenario de CADA paso se persiste aquí. Este archivo recorre a la
  /// misma persona cambiando de permisos paso a paso, así que sembrar
  /// una sola vez en el `setUp` mezclaría escenarios que la prueba
  /// quiere separar.
  Future<ProviderContainer> contenedor({SesionUsuario? sesion = _sesionMaestro}) async {
    if (sesion != null) await sembrarSesionEnBase(db, sesion);
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(() => _SesionDePrueba(sesion)),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('§19 — CASO INTEGRAL JAVIER, de empleado a cuenta y hasta su baja', () {
    test('PASO 1: JAVIER es un empleado activo SIN cuenta, así que es vinculable', () async {
      final c = await contenedor();
      final vinculables = await c.read(usuariosControllerProvider.notifier).empleadosVinculables();

      expect(vinculables.map((e) => e.id), contains(empleadoJavierId));
      expect(await db.select(db.usuario).get(), hasLength(1), reason: 'solo el Maestro: JAVIER aún no tiene cuenta');
    });

    test('PASO 2: el alta crea cuenta + permisos + evento en UNA operación, con la plantilla de RH', () async {
      final c = await contenedor();
      final plantillaRh = codigosDePlantilla('recursosHumanos');

      final resultado = await c.read(usuariosControllerProvider.notifier).crear(
            nombre: 'JAVIER RIOS MENDOZA',
            nombreUsuario: 'javier.rios',
            password: 'temporalDelAlta1',
            puestoId: puestoId,
            empleadoId: empleadoJavierId,
            permisosIniciales: plantillaRh,
          );

      expect(
        resultado,
        isA<CrearUsuarioExitoso>(),
        reason: resultado is CrearUsuarioErrorInesperado ? 'falló con: ${resultado.mensaje}' : null,
      );

      final javier = await (db.select(db.usuario)..where((t) => t.nombreUsuario.equals('javier.rios'))).getSingle();
      expect(javier.empleadoId, empleadoJavierId, reason: 'la cuenta queda ligada a su expediente');
      expect(javier.esMaestro, isFalse);
      expect(javier.debeCambiarPassword, isTrue, reason: 'la contraseña del alta es temporal');

      // Los permisos viajan CON el alta — cifras exactas de la plantilla.
      final codigos = (await db.select(db.permisoUsuario).get()).map((p) => p.codigo).toSet();
      expect(codigos, plantillaRh);
      expect(codigos, hasLength(14), reason: 'la plantilla de RH concede exactamente 14 códigos');

      // Y su evento, en la misma transacción, sin la contraseña en claro.
      final eventos = await db.select(db.usuarioEvento).get();
      expect(eventos, isNotEmpty);
      for (final e in eventos) {
        expect(e.datosRelevantes ?? '', isNot(contains('temporalDelAlta1')));
      }
      expect(javier.passwordHash, isNot(contains('temporalDelAlta1')));
    });

    test('PASO 3: ya con cuenta, JAVIER deja de aparecer como vinculable', () async {
      final c = await contenedor();
      await c.read(usuariosControllerProvider.notifier).crear(
            nombre: 'JAVIER RIOS MENDOZA',
            nombreUsuario: 'javier.rios',
            password: 'temporalDelAlta1',
            puestoId: puestoId,
            empleadoId: empleadoJavierId,
            permisosIniciales: codigosDePlantilla('recursosHumanos'),
          );

      final vinculables = await c.read(usuariosControllerProvider.notifier).empleadosVinculables();
      expect(
        vinculables.map((e) => e.id),
        isNot(contains(empleadoJavierId)),
        reason: 'una persona nunca debe terminar con dos cuentas',
      );
    });

    // IF-5 — PASO 4 («su primer login trae la obligación de cambio») se retiró:
    // no hay login local ni contraseña temporal que cambiar. Quién entra lo
    // decide el backend, y eso se prueba en `test/core/identity/cutover_if5_test.dart`.
    // Los pasos 5 a 8, que son autorización y ciclo de vida de la cuenta, siguen.

    test('PASO 5: con la plantilla de RH entra a Personal y Nómina, nunca a Finanzas ni Configuración', () async {
      final c = await contenedor(
        sesion: SesionUsuario(
          usuarioId: 'javier',
          nombre: 'JAVIER RIOS MENDOZA',
          nombreUsuario: 'javier.rios',
          esMaestro: false,
          permisos: codigosDePlantilla('recursosHumanos'),
        ),
      );
      final permisos = c.read(permissionServiceProvider);

      bool abre(String ruta) {
        final codigos = permisosQueAbrenRuta(ruta);
        return codigos.isEmpty || codigos.any(permisos.hasCode);
      }

      expect(abre('/personal'), isTrue);
      expect(abre('/dashboard'), isTrue);
      expect(abre('/reportes'), isTrue);
      expect(abre('/finanzas'), isFalse);
      expect(abre('/comercial'), isFalse);
      expect(abre('/configuracion'), isFalse);
      expect(abre('/configuracion/auditoria'), isFalse);

      // Mínima información: puede llevar expedientes, no tocar sueldos
      // ni mover dinero.
      for (final vetado in ['personal.cambiarSueldo', 'egresos.crear', 'nomina.registrarPago', 'usuarios.administrar']) {
        expect(permisos.hasCode(vetado), isFalse, reason: 'dbetado no viene con la plantilla de RH');
      }
    });

    test('PASO 6: JAVIER con usuarios.administrar NO puede elevarse a Maestro', () async {
      final c = await contenedor();
      await c.read(usuariosControllerProvider.notifier).crear(
            nombre: 'JAVIER RIOS MENDOZA',
            nombreUsuario: 'javier.rios',
            password: 'temporalDelAlta1',
            puestoId: puestoId,
            empleadoId: empleadoJavierId,
          );
      final javierId = (await (db.select(db.usuario)..where((t) => t.nombreUsuario.equals('javier.rios'))).getSingle()).id;

      // Ahora actúa ÉL, con el permiso más fuerte que un Normal puede
      // tener sobre cuentas.
      final cJavier = await contenedor(
        sesion: SesionUsuario(
          usuarioId: javierId,
          nombre: 'JAVIER RIOS MENDOZA',
          nombreUsuario: 'javier.rios',
          esMaestro: false,
          permisos: const {'usuarios.administrar', 'usuarios.otorgarPermisos', 'usuarios.resetearPassword'},
        ),
      );

      final intento = await cJavier.read(usuariosControllerProvider.notifier).corregir(
            usuarioId: javierId,
            nombre: 'JAVIER RIOS MENDOZA',
            nombreUsuario: 'javier.rios',
            puestoId: puestoId,
            esMaestro: true,
          );

      expect(intento, isA<CorregirUsuarioErrorInesperado>());
      final despues = await (db.select(db.usuario)..where((t) => t.id.equals(javierId))).getSingle();
      expect(despues.esMaestro, isFalse, reason: 'nadie se reparte acceso total a sí mismo');

      // Tampoco fabricando una cuenta Maestra nueva.
      final altaMaestra = await cJavier.read(usuariosControllerProvider.notifier).crear(
            nombre: 'PUERTA TRASERA',
            nombreUsuario: 'backdoor',
            password: 'contrasenaLarga1',
            puestoId: puestoId,
            esMaestro: true,
          );
      expect(altaMaestra, isA<CrearUsuarioErrorInesperado>());
      expect(
        await (db.select(db.usuario)..where((t) => t.nombreUsuario.equals('backdoor'))).getSingleOrNull(),
        isNull,
      );

      // Pero corregir sus datos administrativos SÍ le está permitido:
      // el candado es sobre elevar, no sobre administrar.
      final correccion = await cJavier.read(usuariosControllerProvider.notifier).corregir(
            usuarioId: javierId,
            nombre: 'JAVIER RIOS M.',
            nombreUsuario: 'javier.rios',
            puestoId: puestoId,
            esMaestro: false,
          );
      expect(correccion, isA<CorregirUsuarioExitoso>());
    });

    test('PASO 7: una baja laboral NO borra ni desactiva su cuenta por su cuenta', () async {
      final c = await contenedor();
      await c.read(usuariosControllerProvider.notifier).crear(
            nombre: 'JAVIER RIOS MENDOZA',
            nombreUsuario: 'javier.rios',
            password: 'temporalDelAlta1',
            puestoId: puestoId,
            empleadoId: empleadoJavierId,
          );

      // Baja laboral del EMPLEADO.
      await (db.update(db.empleado)..where((t) => t.id.equals(empleadoJavierId)))
          .write(const EmpleadoCompanion(estatus: Value('baja')));

      final cuenta = await (db.select(db.usuario)..where((t) => t.nombreUsuario.equals('javier.rios'))).getSingle();
      expect(cuenta.cicloVidaRegistro, 'activo', reason: 'desactivar una cuenta es una decisión explícita, nunca un efecto colateral');
      expect(cuenta.empleadoId, empleadoJavierId, reason: 'el vínculo se conserva: es parte del historial');
    });

    test('PASO 8: desactivar la cuenta la deja inactiva SIN borrarla', () async {
      final c = await contenedor();
      await c.read(usuariosControllerProvider.notifier).crear(
            nombre: 'JAVIER RIOS MENDOZA',
            nombreUsuario: 'javier.rios',
            password: 'temporalDelAlta1',
            puestoId: puestoId,
            empleadoId: empleadoJavierId,
            permisosIniciales: codigosDePlantilla('recursosHumanos'),
          );
      final javierId = (await (db.select(db.usuario)..where((t) => t.nombreUsuario.equals('javier.rios'))).getSingle()).id;

      expect(
        (await (db.select(db.usuario)..where((t) => t.id.equals(javierId))).getSingle()).cicloVidaRegistro,
        'activo',
      );

      await c.read(usuariosControllerProvider.notifier).desactivar(usuarioId: javierId, motivo: 'Baja laboral');

      // IF-5 — antes esto se comprobaba intentando un login local. Quién puede
      // autenticarse lo decide ahora el backend; lo que esta prueba fija es el
      // hecho local que sigue siendo suyo: la cuenta queda inactiva y NO se borra.

      // La cuenta NO se eliminó: su historial y su vínculo siguen ahí.
      final fila = await (db.select(db.usuario)..where((t) => t.id.equals(javierId))).getSingle();
      expect(fila.cicloVidaRegistro, isNot('activo'));
      expect(fila.empleadoId, empleadoJavierId);
      expect(await db.select(db.permisoUsuario).get(), isNotEmpty, reason: 'reactivarla no debe obligar a rearmar sus permisos');
    });
  });

  group('§16 — cambiar de sesión no hereda nada de la anterior', () {
    Future<GoRouter> montar(WidgetTester tester, ProviderContainer _, SesionUsuario sesion) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Etapa 3B: estas pruebas montan la aplicación con una sesión
      // distinta a la del contenedor anterior, así que la cuenta de
      // ESTA sesión se persiste aquí, inmediatamente antes de montar.
      await sembrarSesionEnBase(db, sesion);

      final router = createAppRouter();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            sesionControllerProvider.overrideWith(() => _SesionDePrueba(sesion)),
          ],
          child: MaterialApp.router(
            theme: AppTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      return router;
    }

    testWidgets('tras cerrar sesión, la sesión siguiente NO conserva los permisos de la anterior', (tester) async {
      final router = await montar(
        tester,
        await contenedor(),
        SesionUsuario(
          usuarioId: 'tesorero',
          nombre: 'TESORERA',
          nombreUsuario: 'tesorera',
          esMaestro: false,
          permisos: codigosDePlantilla('tesoreria'),
        ),
      );

      router.go('/finanzas');
      await tester.pumpAndSettle();
      expect(router.routerDelegate.currentConfiguration.uri.path, startsWith('/finanzas'));

      // Cambio de sesión: entra JAVIER, que NO tiene Finanzas.
      final elemento = tester.element(find.byType(MaterialApp));
      final contenedorVivo = ProviderScope.containerOf(elemento);
      final notifier = contenedorVivo.read(sesionControllerProvider.notifier) as _SesionDePrueba;

      // Igual que `_ProfileChip._cerrarSesion`: limpiar la sesión y
      // navegar. El `redirect` de GoRouter se evalúa AL NAVEGAR, no
      // reactivamente — no hay `refreshListenable`, y por eso la barra
      // superior hace `context.go('/login')` en vez de confiar en que el
      // router se entere solo.
      notifier.logout();
      router.go('/login');
      await tester.pumpAndSettle();
      expect(router.routerDelegate.currentConfiguration.uri.path, '/login');

      // Y sin sesión, ninguna ruta del sistema se sostiene.
      router.go('/finanzas');
      await tester.pumpAndSettle();
      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        '/login',
        reason: 'sin sesión no se construye ninguna pantalla del sistema',
      );

      final javierRh = SesionUsuario(
        usuarioId: 'javier',
        nombre: 'JAVIER RIOS MENDOZA',
        nombreUsuario: 'javier.rios',
        esMaestro: false,
        permisos: codigosDePlantilla('recursosHumanos'),
      );
      // La cuenta entrante también vive en la base: la autorización se
      // revalida contra ella, y lo que se comprueba es que NO hereda los
      // permisos del titular anterior, no que no exista.
      await sembrarSesionEnBase(db, javierRh);
      notifier.entrarComo(javierRh);
      await tester.pumpAndSettle();

      router.go('/finanzas');
      await tester.pumpAndSettle();
      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        '/acceso-denegado',
        reason: 'los permisos del titular anterior no sobreviven al cambio de sesión',
      );

      router.go('/personal');
      await tester.pumpAndSettle();
      expect(router.routerDelegate.currentConfiguration.uri.path, startsWith('/personal'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('un Maestro que cede la sesión a un Normal pierde el acceso total de inmediato', (tester) async {
      final router = await montar(tester, await contenedor(), _sesionMaestro);

      router.go('/configuracion/boveda');
      await tester.pumpAndSettle();
      expect(router.routerDelegate.currentConfiguration.uri.path, '/configuracion/boveda');

      final contenedorVivo = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      const javierNormal = SesionUsuario(
        usuarioId: 'javier',
        nombre: 'JAVIER RIOS MENDOZA',
        nombreUsuario: 'javier.rios',
        esMaestro: false,
        permisos: {'usuarios.administrar'},
      );
      await sembrarSesionEnBase(db, javierNormal);
      (contenedorVivo.read(sesionControllerProvider.notifier) as _SesionDePrueba).entrarComo(javierNormal);
      await tester.pumpAndSettle();

      router.go('/configuracion/boveda');
      await tester.pumpAndSettle();
      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        '/acceso-denegado',
        reason: 'Bóveda y Respaldo son Maestro-only: ningún permiso genérico las abre',
      );
    });
  });
}
