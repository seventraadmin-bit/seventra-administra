// Cierre de la Etapa 2: aislamiento Editar ↔ Cambiar contraseña, la regla de
// credencial inactiva, la reactividad lista ↔ ficha y el comportamiento en
// los cuatro anchos de trabajo.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/core/security/credential_cipher.dart';
import 'package:riseg_one/features/boveda/boveda_providers.dart';
import 'package:riseg_one/features/boveda/domain/usecases/actualizar_credencial_boveda_usecase.dart';
import 'package:riseg_one/features/boveda/domain/usecases/cambiar_secreto_credencial_boveda_usecase.dart';
import 'package:riseg_one/features/boveda/domain/usecases/dar_de_baja_credencial_boveda_usecase.dart';
import 'package:riseg_one/features/boveda/domain/usecases/revelar_secreto_credencial_boveda_usecase.dart';
import 'package:riseg_one/features/boveda/presentation/boveda_controller.dart';
import 'package:riseg_one/features/boveda/presentation/boveda_screen.dart';
import 'package:riseg_one/features/boveda/presentation/widgets/credencial_boveda_detalle_dialog.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import '../../support/sesion_en_base.dart';

class _AlmacenEnMemoria implements AlmacenClaveCifrado {
  String? _valor;
  @override
  Future<String?> leer() async => _valor;
  @override
  Future<void> escribir(String valor) async => _valor = valor;
}

class _SesionMaestro extends SesionController {
  @override
  SesionUsuario? build() => const SesionUsuario(
    usuarioId: 'u-maestro',
    nombre: 'MARLON',
    nombreUsuario: 'marlon',
    esMaestro: true,
    permisos: {},
  );
}

void main() {
  late AppDatabase db;
  late CredentialCipher cipher;
  late ProviderContainer container;
  late String credencialId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db
        .into(db.usuario)
        .insert(
          UsuarioCompanion.insert(
            id: const Value('u-maestro'),
            nombre: 'MARLON',
            nombreUsuario: 'marlon',
            passwordHash: 'x',
          ),
        );
    cipher = CredentialCipher(almacen: _AlmacenEnMemoria());

    final credencial = await db
        .into(db.bovedaCredencial)
        .insertReturning(
          BovedaCredencialCompanion.insert(
            nombre: 'RISEG ONE',
            tipo: 'software',
            usuarioAcceso: const Value('USUARIO-A'),
            correo: const Value('a@riseg.mx'),
            url: const Value('https://a.riseg.mx'),
            observaciones: const Value('OBSERVACION-A'),
            secretoCifrado: Value(await cipher.cifrar('Contrasena-X')),
          ),
        );
    credencialId = credencial.id;

    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(_SesionMaestro.new),
        credentialCipherProvider.overrideWithValue(cipher),
      ],
    );
    // Etapa 3B: autorizar revalida contra la base, así que la
    // sesión de esta prueba tiene que corresponder a una cuenta real.
    await sembrarSesionEnBase(db, SesionUsuario( usuarioId: 'u-maestro', nombre: 'MARLON', nombreUsuario: 'marlon', esMaestro: true, permisos: {}, ));
  });

  tearDown(() {
    container.dispose();
    db.close();
  });

  Future<BovedaCredencialData> recargarCredencial() async {
    return (await container.read(bovedaCredencialRepositoryProvider).obtenerPorId(credencialId))!;
  }

  Future<String> contrasenaActual() async {
    final c = await recargarCredencial();
    return cipher.descifrar(c.secretoCifrado!);
  }

  group('Editar metadatos y Cambiar contraseña son operaciones ajenas', () {
    test('1. editar los metadatos deja la contraseña intacta', () async {
      final resultado = await container.read(actualizarCredencialBovedaAutorizadoProvider)(
        id: credencialId,
        nombre: 'RISEG ONE MAESTRO',
        tipo: 'portal',
        usuarioAcceso: 'USUARIO-B',
        correo: 'b@riseg.mx',
        url: 'https://b.riseg.mx',
        observaciones: 'OBSERVACION-B',
      );
      expect(resultado, isA<ActualizarCredencialBovedaExitoso>());

      final c = await recargarCredencial();
      expect(c.nombre, 'RISEG ONE MAESTRO');
      expect(c.usuarioAcceso, 'USUARIO-B');
      expect(c.correo, 'b@riseg.mx');
      expect(c.url, 'https://b.riseg.mx');
      expect(c.observaciones, 'OBSERVACION-B');
      expect(
        await contrasenaActual(),
        'Contrasena-X',
        reason: 'editar no puede tocar la contraseña, ni siquiera por accidente',
      );
    });

    test('2. cambiar la contraseña deja TODOS los metadatos intactos', () async {
      final resultado = await container.read(cambiarSecretoCredencialBovedaAutorizadoProvider)(
        id: credencialId,
        secreto: 'Contrasena-Y',
      );
      expect(resultado, isA<CambiarSecretoCredencialBovedaExitoso>());

      final c = await recargarCredencial();
      expect(await contrasenaActual(), 'Contrasena-Y');
      expect(c.nombre, 'RISEG ONE');
      expect(c.usuarioAcceso, 'USUARIO-A');
      expect(c.correo, 'a@riseg.mx');
      expect(c.url, 'https://a.riseg.mx');
      expect(c.observaciones, 'OBSERVACION-A');
      expect(c.fechaActualizacionSecreto, isNotNull, reason: 'sí actualiza su propia fecha');
    });
  });

  group('Credencial dada de baja', () {
    setUp(() async {
      final baja = await container.read(darDeBajaCredencialBovedaAutorizadoProvider)(id: credencialId);
      expect(baja, isA<DarDeBajaCredencialBovedaExitoso>());
    });

    test('3. cambiar la contraseña se rechaza EN DOMINIO, no escondiendo el botón', () async {
      final resultado = await container.read(cambiarSecretoCredencialBovedaAutorizadoProvider)(
        id: credencialId,
        secreto: 'Contrasena-Z',
      );

      expect(resultado, isA<CambiarSecretoCredencialBovedaDadaDeBaja>());
      expect(await contrasenaActual(), 'Contrasena-X', reason: 'nada se escribió');
    });

    test('4. mostrar sigue permitido: consultar un acceso retirado es legítimo', () async {
      final resultado = await container.read(revelarSecretoCredencialBovedaAutorizadoProvider)(
        credencialId: credencialId,
        accion: AccionRevelacionSecreto.mostrar,
      );

      expect(resultado, isA<RevelarSecretoCredencialBovedaExitoso>());
      expect((resultado as RevelarSecretoCredencialBovedaExitoso).secreto, 'Contrasena-X');
    });

    test('5. copiar sigue permitido y sigue auditado', () async {
      await container.read(revelarSecretoCredencialBovedaAutorizadoProvider)(
        credencialId: credencialId,
        accion: AccionRevelacionSecreto.copiar,
      );

      final eventos = await db.select(db.bovedaCredencialEvento).get();
      expect(eventos.where((e) => e.tipoEvento == 'secretoCopiado'), hasLength(1));
    });

    test('6. reactivar devuelve la posibilidad de cambiarla', () async {
      await container.read(reactivarCredencialBovedaAutorizadoProvider)(id: credencialId);

      final resultado = await container.read(cambiarSecretoCredencialBovedaAutorizadoProvider)(
        id: credencialId,
        secreto: 'Contrasena-Z',
      );

      expect(resultado, isA<CambiarSecretoCredencialBovedaExitoso>());
      expect(await contrasenaActual(), 'Contrasena-Z');
    });
  });

  group('Reactividad lista ↔ ficha', () {
    test('7. editar el nombre actualiza el estado que alimenta lista y ficha', () async {
      container.listen(bovedaControllerProvider, (_, _) {});
      await container.read(bovedaControllerProvider.notifier).recargar();
      expect(container.read(bovedaControllerProvider).credenciales.single.nombre, 'RISEG ONE');

      await container.read(actualizarCredencialBovedaAutorizadoProvider)(
        id: credencialId,
        nombre: 'RISEG ONE MAESTRO',
        tipo: 'software',
      );
      await container.read(bovedaControllerProvider.notifier).recargar();

      // La ficha lee de este mismo estado, así que ambas cambian a la vez.
      expect(container.read(bovedaControllerProvider).credenciales.single.nombre, 'RISEG ONE MAESTRO');
    });

    test('8. baja y reactivación se reflejan en el mismo estado', () async {
      container.listen(bovedaControllerProvider, (_, _) {});
      await container.read(bovedaControllerProvider.notifier).recargar();

      await container.read(darDeBajaCredencialBovedaAutorizadoProvider)(id: credencialId);
      await container.read(bovedaControllerProvider.notifier).recargar();
      // El listado filtra "sólo activas" por omisión: la credencial dada de
      // baja sale de la lista. La ficha NO depende de eso — lee por id.
      expect(container.read(bovedaControllerProvider).credenciales, isEmpty);
      final trasBaja = await recargarCredencial();
      expect(trasBaja.cicloVidaRegistro, 'baja');

      await container.read(reactivarCredencialBovedaAutorizadoProvider)(id: credencialId);
      await container.read(bovedaControllerProvider.notifier).recargar();
      expect(container.read(bovedaControllerProvider).credenciales.single.cicloVidaRegistro, 'activo');
    });
  });

  group('Responsive y datos largos', () {
    const anchos = [1366.0, 1024.0, 700.0, 500.0];

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
            home: Scaffold(body: pantalla ?? const BovedaScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    for (final ancho in anchos) {
      testWidgets('9. lista de Bóveda a ${ancho.toInt()}px: cero overflow', (tester) async {
        await montar(tester, ancho);
        expect(tester.takeException(), isNull);
      });

      testWidgets('10. ficha a ${ancho.toInt()}px: cero overflow', (tester) async {
        await montar(tester, ancho, pantalla: CredencialBovedaDetalleDialog(credencialId: credencialId));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('11. una contraseña larguísima revelada no rompe la ficha', (tester) async {
      final larga = 'C' * 80;
      await container.read(cambiarSecretoCredencialBovedaAutorizadoProvider)(id: credencialId, secreto: larga);
      await container.read(bovedaControllerProvider.notifier).recargar();

      await montar(tester, 500, pantalla: CredencialBovedaDetalleDialog(credencialId: credencialId));
      await tester.tap(find.byKey(const Key('boveda_detalle_alternar_contrasena')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('12. una URL larguísima no rompe ni la ficha ni la lista', (tester) async {
      await container.read(actualizarCredencialBovedaAutorizadoProvider)(
        id: credencialId,
        nombre: 'N' * 90,
        tipo: 'portal',
        url: 'https://portal.riseg.mx/${'segmento-muy-largo/' * 12}final',
        observaciones: 'O' * 400,
      );
      await container.read(bovedaControllerProvider.notifier).recargar();

      await montar(tester, 500);
      expect(tester.takeException(), isNull);

      await montar(tester, 500, pantalla: CredencialBovedaDetalleDialog(credencialId: credencialId));
      expect(tester.takeException(), isNull);
    });
  });
}
