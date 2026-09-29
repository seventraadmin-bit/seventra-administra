// Integration Foundation IF-2 — el modelo de la sesión remota y su formato en
// disco.
//
// Lo que se defiende aquí son dos cosas que fallan caro y en silencio: que la
// identidad que observa la interfaz NO lleve credenciales dentro, y que un blob
// ilegible en el almacén del sistema no reviente el arranque ni autentique a
// nadie a medias.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:riseg_one/core/auth/sesion_remota.dart';
import 'package:riseg_one/core/error/failure.dart';

void main() {
  final expira = DateTime.utc(2026, 10, 12, 8, 30);

  CredencialRemota credencial({
    String refreshToken = 'rt_secreto_de_refresco_123',
    String? displayName = 'Ana Torres',
    DateTime? refreshExpiresAt,
  }) => CredencialRemota(
    identityId: 'i-1',
    refreshToken: refreshToken,
    refreshExpiresAt: refreshExpiresAt ?? expira,
    sessionId: '0193f0a0-0000-7000-8000-000000000001',
    email: 'ana@seventra.mx',
    displayName: displayName,
  );

  group('SesionRemota — identidad, no credencial', () {
    test('su texto no lleva ningún token', () {
      final sesion = credencial().sesion;

      expect(sesion.toString(), contains('ana@seventra.mx'));
      expect(sesion.toString(), isNot(contains('rt_secreto')));
    });

    test('se deriva de la credencial sin arrastrar el refresco', () {
      final sesion = credencial().sesion;

      expect(sesion.sessionId, '0193f0a0-0000-7000-8000-000000000001');
      expect(sesion.email, 'ana@seventra.mx');
      expect(sesion.displayName, 'Ana Torres');
    });

    test('dos sesiones con los mismos datos son iguales', () {
      // Hace falta para que el estado observable no notifique un cambio cuando
      // un refresco devuelve exactamente la misma identidad.
      expect(credencial().sesion, credencial().sesion);
      expect(
        const Autenticado(SesionRemota(identityId: 'i-1', sessionId: 's', email: 'a@b.mx')),
        const Autenticado(SesionRemota(identityId: 'i-1', sessionId: 's', email: 'a@b.mx')),
      );
    });
  });

  group('CredencialRemota — el formato en disco', () {
    test('ida y vuelta completa', () {
      final leida = CredencialRemota.desdeTexto(credencial().aTexto());

      expect(leida, isNotNull);
      expect(leida!.refreshToken, 'rt_secreto_de_refresco_123');
      expect(leida.refreshExpiresAt, expira);
      expect(leida.sessionId, '0193f0a0-0000-7000-8000-000000000001');
      expect(leida.email, 'ana@seventra.mx');
      expect(leida.displayName, 'Ana Torres');
    });

    test('sin displayName sigue siendo válida', () {
      // Es el caso normal de una sesión restaurada: el refresco del backend no
      // reenvía la identidad.
      final leida = CredencialRemota.desdeTexto(
        credencial(displayName: null).aTexto(),
      );

      expect(leida, isNotNull);
      expect(leida!.displayName, isNull);
    });

    test('la caducidad se normaliza a UTC', () {
      final local = CredencialRemota(
        identityId: 'i-1',
        refreshToken: 'rt',
        refreshExpiresAt: DateTime.parse('2026-10-12T08:30:00-06:00'),
        sessionId: 's',
        email: 'a@b.mx',
      );

      final leida = CredencialRemota.desdeTexto(local.aTexto())!;

      expect(leida.refreshExpiresAt.isUtc, isTrue);
      expect(leida.refreshExpiresAt, DateTime.utc(2026, 10, 12, 14, 30));
    });

    test('es UN solo blob y lleva su versión', () {
      // Cinco entradas sueltas en el almacén de Windows pueden quedar a medias
      // —token nuevo con caducidad vieja— y eso produce una sesión que parece
      // válida y no lo es.
      final crudo = jsonDecode(credencial().aTexto()) as Map<String, Object?>;

      expect(crudo['v'], CredencialRemota.versionActual);
    });

    test('su texto NO lleva el token de refresco', () {
      // `toString` acaba en registros y en volcados de excepción.
      expect(credencial().toString(), isNot(contains('rt_secreto')));
      expect(credencial().toString(), contains('ana@seventra.mx'));
    });
  });

  group('Un blob que no se puede interpretar se descarta, sin lanzar', () {
    void esNulo(String? texto, {required String porque}) =>
        expect(CredencialRemota.desdeTexto(texto), isNull, reason: porque);

    test('ausente o vacío', () {
      esNulo(null, porque: 'no hay nada guardado');
      esNulo('', porque: 'cadena vacía');
      esNulo('   ', porque: 'sólo espacios');
    });

    test('no es JSON', () => esNulo('{roto', porque: 'blob truncado'));

    test(
      'es JSON pero no un objeto',
      () => esNulo('[1,2,3]', porque: 'forma equivocada'),
    );

    test('versión desconocida', () {
      esNulo(
        jsonEncode({
          'v': 99,
          'rt': 'x',
          'rte': expira.toIso8601String(),
          'sid': 's',
          'em': 'a@b.mx',
        }),
        porque: 'lo escribió una versión que no conocemos',
      );
    });

    test('falta un campo obligatorio', () {
      for (final ausente in ['rt', 'rte', 'sid', 'em']) {
        final campos = <String, Object?>{
          'v': CredencialRemota.versionActual,
          'rt': 'x',
          'rte': expira.toIso8601String(),
          'sid': 's',
          'em': 'a@b.mx',
        }..remove(ausente);

        esNulo(jsonEncode(campos), porque: 'falta «$ausente»');
      }
    });

    test('la caducidad no es una fecha', () {
      esNulo(
        jsonEncode({
          'v': CredencialRemota.versionActual,
          'rt': 'x',
          'rte': 'el jueves',
          'sid': 's',
          'em': 'a@b.mx',
        }),
        porque: 'una caducidad ilegible no se puede comparar',
      );
    });
  });

  group('Caducidad', () {
    test('caducada cuando el instante ya pasó, e incluido el borde', () {
      expect(
        credencial().haCaducado(expira.subtract(const Duration(minutes: 1))),
        isFalse,
      );
      expect(
        credencial().haCaducado(expira),
        isTrue,
        reason: 'el borde ya no sirve',
      );
      expect(
        credencial().haCaducado(expira.add(const Duration(seconds: 1))),
        isTrue,
      );
    });

    test('compara en UTC aunque le pasen hora local', () {
      final antes = expira.subtract(const Duration(hours: 1)).toLocal();

      expect(credencial().haCaducado(antes), isFalse);
    });
  });

  group('copyWith de la rotación', () {
    test('cambia los dos datos del token y conserva la identidad', () {
      final rotada = credencial().copyWith(
        refreshToken: 'rt_nuevo',
        refreshExpiresAt: expira.add(const Duration(days: 14)),
      );

      expect(rotada.refreshToken, 'rt_nuevo');
      expect(rotada.sessionId, credencial().sessionId);
      expect(rotada.email, credencial().email);
    });

    test('un displayName nulo CONSERVA el que había', () {
      // El refresco del backend responde con `displayName` nulo. Sobrescribir
      // con ese nulo borraría el nombre de quien ya entró.
      final rotada = credencial().copyWith(refreshToken: 'rt_nuevo');

      expect(rotada.displayName, 'Ana Torres');
    });
  });

  group('Los cuatro estados no se colapsan', () {
    test('cada uno es distinguible', () {
      const estados = <EstadoAutenticacion>[
        AutenticacionSinResolver(),
        NoAutenticado(),
        Autenticado(SesionRemota(identityId: 'i-1', sessionId: 's', email: 'a@b.mx')),
        SesionRemotaSinConfirmar(ApiSinConexionFailure('sin red')),
      ];

      expect(estados.map((e) => e.runtimeType).toSet(), hasLength(4));
    });

    test('«sin resolver» no es «no autenticado»', () {
      // Confundirlos manda al login antes de que la restauración termine.
      expect(const AutenticacionSinResolver(), isNot(const NoAutenticado()));
    });

    test('«sin confirmar» conserva el motivo para poder explicarlo', () {
      const estado = SesionRemotaSinConfirmar(
        ApiTimeoutFailure('el servidor tardó demasiado'),
      );

      expect(estado.motivo, isA<ApiTimeoutFailure>());
      expect(estado.toString(), contains('ApiTimeoutFailure'));
    });
  });
}
