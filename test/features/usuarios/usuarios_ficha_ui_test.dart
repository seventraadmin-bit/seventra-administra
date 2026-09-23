// Etapa 3B — la pantalla de Usuarios: ficha, datos efectivos,
// reactividad y responsive.
//
// Lo que se fija aquí, más allá de "no hay overflow": que la tabla y la
// ficha muestren la identidad EFECTIVA (la del expediente cuando la
// cuenta pertenece a alguien de Personal), que abrir el menú ⋮ no
// dispare además la ficha, y que una acción actualice a la vez la lista
// de atrás y la ficha abierta sin cerrar nada ni cambiar de pestaña.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/core/auth/password_hasher.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/core/permissions/modulos_permiso.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import 'package:riseg_one/features/usuarios/presentation/usuarios_controller.dart';
import 'package:riseg_one/features/usuarios/presentation/usuarios_list_screen.dart';
import 'package:riseg_one/features/usuarios/presentation/widgets/usuario_detalle_dialog.dart';

class _SesionMaestro extends SesionController {
  _SesionMaestro(this._id);
  final String _id;

  @override
  SesionUsuario? build() => SesionUsuario(
    usuarioId: _id,
    nombre: 'MARLON',
    nombreUsuario: 'marlon',
    esMaestro: true,
    permisos: todosLosCodigosDePermiso(),
  );
}

/// Los cuatro anchos de trabajo declarados para RISEG ONE.
const _anchos = [1366.0, 1024.0, 700.0, 500.0];

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late String maestroId;
  late String vinculadaId;
  late String independienteId;
  const hasher = PasswordHasher(iteraciones: 1000);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());

    final puesto = await db.select(db.puesto).get();
    final puestoId = puesto.isEmpty ? null : puesto.first.id;

    final empleado = await db
        .into(db.empleado)
        .insertReturning(
          EmpleadoCompanion.insert(
            numeroEmpleado: 7,
            nombres: 'JAVIER',
            apellidoPaterno: 'RIOS',
            apellidoMaterno: const Value('SOTO'),
            sexo: 'masculino',
            fechaNacimiento: DateTime(1990, 1, 1),
            curp: 'RISJ900101HDFXXX01',
            rfc: 'RISJ900101AB1',
            nss: '12345678901',
            estadoCivil: 'soltero',
            fechaIngreso: DateTime(2026, 1, 1),
            aniosExperienciaSeguridad: 3,
            puestoId: Value(puestoId),
          ),
        );

    maestroId = (await db.into(db.usuario).insertReturning(
      UsuarioCompanion.insert(nombre: 'MARLON', nombreUsuario: 'marlon', passwordHash: hasher.hash('contrasena1'), esMaestro: const Value(true)),
    )).id;

    // Cuenta vinculada: su `nombre` propio es basura a propósito, para
    // que la prueba distinga de dónde sale lo que se muestra.
    vinculadaId = (await db.into(db.usuario).insertReturning(
      UsuarioCompanion.insert(
        nombre: 'NOMBRE VIEJO',
        nombreUsuario: 'javier',
        passwordHash: hasher.hash('contrasena1'),
        empleadoId: Value(empleado.id),
      ),
    )).id;

    independienteId = (await db.into(db.usuario).insertReturning(
      UsuarioCompanion.insert(
        nombre: 'ADMINISTRADOR EXTERNO',
        nombreUsuario: 'externo',
        passwordHash: hasher.hash('contrasena1'),
        puestoId: Value(puestoId),
      ),
    )).id;
    await db.into(db.permisoUsuario).insert(
      PermisoUsuarioCompanion.insert(usuarioId: independienteId, codigo: 'personal.ver'),
    );

    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(() => _SesionMaestro(maestroId)),
      ],
    );
  });

  tearDown(() {
    container.dispose();
    db.close();
  });

  Future<void> montar(WidgetTester tester, double ancho, {Widget? pantalla}) async {
    tester.view.physicalSize = Size(ancho, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: pantalla ?? const UsuariosListScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('La tabla muestra datos efectivos', () {
    testWidgets('una cuenta vinculada se nombra con el expediente, no con su nombre propio', (tester) async {
      await montar(tester, 1366);

      expect(find.text('JAVIER RIOS SOTO'), findsOneWidget);
      expect(
        find.text('NOMBRE VIEJO'),
        findsNothing,
        reason: 'el nombre propio de una cuenta vinculada no se presenta jamás',
      );
    });

    testWidgets('una cuenta independiente conserva su propio nombre', (tester) async {
      await montar(tester, 1366);
      expect(find.text('ADMINISTRADOR EXTERNO'), findsOneWidget);
    });
  });

  group('42-43. Fila y menú', () {
    testWidgets('42. pulsar la fila abre la ficha', (tester) async {
      await montar(tester, 1366);

      await tester.tap(find.text('ADMINISTRADOR EXTERNO'));
      await tester.pumpAndSettle();

      expect(find.byType(UsuarioDetalleDialog), findsOneWidget);
    });

    testWidgets('43. abrir el menú ⋮ NO abre además la ficha', (tester) async {
      await montar(tester, 1366);

      await tester.tap(find.byKey(Key('usuarios_menu_$independienteId')));
      await tester.pumpAndSettle();

      expect(find.byType(UsuarioDetalleDialog), findsNothing);
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));
      expect(find.text(l10n.usuariosAccionEditar), findsOneWidget);
    });
  });

  group('44-45. La ficha', () {
    testWidgets('44. la ficha de una cuenta vinculada muestra su Empleado', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));
      await montar(tester, 1366, pantalla: UsuarioDetalleDialog(usuarioId: vinculadaId));

      expect(find.text(l10n.usuarioCampoEmpleado), findsOneWidget);
      expect(find.text('JAVIER RIOS SOTO'), findsWidgets);
      expect(find.text(l10n.usuarioEmpleadoSinVincular), findsNothing);
    });

    testWidgets('45. la ficha de una cuenta independiente NO presenta el vínculo como un error', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));
      await montar(tester, 1366, pantalla: UsuarioDetalleDialog(usuarioId: independienteId));

      // Se dice el estado, y nada más: ni advertencia, ni aviso de baja.
      expect(find.text(l10n.usuarioEmpleadoSinVincular), findsOneWidget);
      expect(find.text(l10n.usuarioFichaAvisoEmpleadoDeBaja), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a un Maestro no se le finge una lista de permisos', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));
      await montar(tester, 1366, pantalla: UsuarioDetalleDialog(usuarioId: maestroId));

      expect(find.text(l10n.permisosMaestroMensaje), findsOneWidget);
      expect(find.text(l10n.usuarioFichaSinPermisos), findsNothing, reason: 'tiene todo, no nada');
    });

    testWidgets('la ficha nunca muestra el hash de la contraseña', (tester) async {
      await montar(tester, 1366, pantalla: UsuarioDetalleDialog(usuarioId: independienteId));

      final usuario = await (db.select(db.usuario)..where((t) => t.id.equals(independienteId))).getSingle();
      expect(find.textContaining('pbkdf2'), findsNothing);
      expect(find.textContaining(usuario.passwordHash), findsNothing);
      // Tampoco identificadores técnicos.
      expect(find.textContaining(independienteId), findsNothing);
    });
  });

  group('46-50. Reactividad', () {
    testWidgets('48 y 46. desactivar actualiza la lista y la ficha sin cerrar nada', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));
      await montar(tester, 1366, pantalla: UsuarioDetalleDialog(usuarioId: independienteId));
      expect(find.text(l10n.usuarioEstadoActivo), findsOneWidget);

      await container
          .read(usuariosControllerProvider.notifier)
          .desactivar(usuarioId: independienteId, motivo: 'Ya no colabora');
      await tester.pumpAndSettle();

      expect(find.byType(UsuarioDetalleDialog), findsOneWidget, reason: 'la ficha sigue abierta');
      expect(find.text(l10n.usuarioEstadoInactivo), findsOneWidget, reason: 'y ya refleja el estado nuevo');
    });

    testWidgets('49. reactivar vuelve a reflejarse de inmediato', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));
      await container
          .read(usuariosControllerProvider.notifier)
          .desactivar(usuarioId: independienteId, motivo: 'temporal');
      await montar(tester, 1366, pantalla: UsuarioDetalleDialog(usuarioId: independienteId));
      expect(find.text(l10n.usuarioEstadoInactivo), findsOneWidget);

      await container.read(usuariosControllerProvider.notifier).activar(independienteId);
      await tester.pumpAndSettle();

      expect(find.text(l10n.usuarioEstadoActivo), findsOneWidget);
    });

    testWidgets('47. cambiar el vínculo actualiza la ficha abierta', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));
      await montar(tester, 1366, pantalla: UsuarioDetalleDialog(usuarioId: vinculadaId));
      expect(find.text('JAVIER RIOS SOTO'), findsWidgets);

      await container.read(usuariosControllerProvider.notifier).cambiarVinculoEmpleado(
        usuarioId: vinculadaId,
        empleadoIdNuevo: null,
        motivo: 'Ya no aplica',
      );
      await tester.pumpAndSettle();

      expect(find.text(l10n.usuarioEmpleadoSinVincular), findsOneWidget, reason: 'la ficha ya no presenta vínculo');
      expect(
        find.text('JAVIER RIOS SOTO'),
        findsWidgets,
        reason: 'y conserva el nombre congelado: desvincular no renombra la cuenta',
      );
    });

    testWidgets('50. guardar permisos actualiza el resumen de la ficha', (tester) async {
      await montar(tester, 1366, pantalla: UsuarioDetalleDialog(usuarioId: independienteId));
      final antes = tester.widget<Text>(find.byKey(const Key('usuario_ficha_permisos_resumen'))).data;

      await container.read(usuariosControllerProvider.notifier).guardarPermisos(
        usuarioId: independienteId,
        codigos: {'personal.ver', 'nomina.ver'},
      );
      await tester.pumpAndSettle();

      final despues = tester.widget<Text>(find.byKey(const Key('usuario_ficha_permisos_resumen'))).data;
      expect(despues, isNot(antes), reason: 'el resumen visible tiene que seguir al cambio');
    });
  });

  group('Responsive — cero overflow en los cuatro anchos', () {
    for (final ancho in _anchos) {
      final px = ancho.toInt();

      testWidgets('listado a ${px}px', (tester) async {
        await montar(tester, ancho);
        expect(tester.takeException(), isNull);
      });

      testWidgets('ficha vinculada a ${px}px', (tester) async {
        await montar(tester, ancho, pantalla: UsuarioDetalleDialog(usuarioId: vinculadaId));
        expect(tester.takeException(), isNull);
      });

      testWidgets('ficha independiente a ${px}px', (tester) async {
        await montar(tester, ancho, pantalla: UsuarioDetalleDialog(usuarioId: independienteId));
        expect(tester.takeException(), isNull);
      });

      testWidgets('menú ⋮ a ${px}px: dentro del viewport', (tester) async {
        final l10n = await AppLocalizations.delegate.load(const Locale('es'));
        await montar(tester, ancho);

        final menu = find.byKey(Key('usuarios_menu_$independienteId'));
        await tester.ensureVisible(menu);
        await tester.pumpAndSettle();
        await tester.tap(menu);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        for (final etiqueta in [
          l10n.usuariosAccionEditar,
          l10n.usuariosAccionCambiarContrasena,
          l10n.usuariosAccionPermisos,
          l10n.usuariosAccionDesactivar,
          l10n.usuariosAccionHistorial,
        ]) {
          final opcion = find.text(etiqueta).last;
          expect(opcion, findsOneWidget, reason: 'falta "$etiqueta"');
          final caja = tester.getRect(opcion);
          expect(caja.left, greaterThanOrEqualTo(0), reason: '"$etiqueta" se sale por la izquierda');
          expect(caja.right, lessThanOrEqualTo(ancho), reason: '"$etiqueta" se sale por la derecha');
          expect(caja.bottom, lessThanOrEqualTo(768), reason: '"$etiqueta" se sale por abajo');
        }
      });
    }
  });
}
