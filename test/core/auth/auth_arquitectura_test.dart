// Integration Foundation IF-2 — los LÍMITES de la etapa, verificados sobre el
// árbol de código.
//
// IF-2 construye el motor de autenticación remota **sin convertirlo en el portón
// del producto**. Es una transición deliberada, y las transiciones se rompen sin
// darse cuenta: basta un `redirect` «temporal» en el router, o un proveedor que
// empareje una Identity del backend con un `Usuario` local «para poder probar»,
// para que la convivencia que se decidió mantener separada quede soldada. Después
// cuesta mucho revertirlo, porque 359 archivos escriben `actorUsuarioId`.
//
// Estas pruebas leen los archivos reales, así que no se pueden satisfacer por
// accidente. Y **se ignoran los comentarios** a propósito: es el quinto tropiezo
// del proyecto con lo mismo —el backend lo tuvo tres veces con `COMMENT ON` y el
// guardia de `/api/v1` una— y un guardia que se dispara contra su propia
// explicación obliga a borrar la explicación, que es lo contrario de lo que se
// quiere.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:riseg_one/core/auth/almacen_sesion_remota.dart';
import 'package:riseg_one/core/auth/sesion_recordada_almacen.dart';
import 'package:riseg_one/core/auth/sesion_remota.dart';

/// Los archivos que IF-2 añade. Se nombran uno a uno en vez de tomar la carpeta
/// entera porque `lib/core/auth/` ya contenía piezas de la sesión LOCAL
/// (`password_hasher`, `sesion_recordada_almacen`), y mezclarlas escondería
/// justamente la separación que se está defendiendo.
const List<String> _archivosDeIF2 = [
  'lib/core/auth/sesion_remota.dart',
  'lib/core/auth/almacen_sesion_remota.dart',
  'lib/core/auth/auth_api.dart',
  'lib/core/auth/gestor_de_sesion.dart',
  'lib/core/auth/auth_providers.dart',
  'lib/core/api/api_client_autenticado.dart',
];

/// Cómo se reconoce, desde fuera, que un archivo habla de la sesión REMOTA.
const List<String> _simbolosRemotos = [
  'SesionRemota',
  'CredencialRemota',
  'GestorDeSesion',
  'EstadoAutenticacion',
  'gestorDeSesionProvider',
  'estadoAutenticacionProvider',
  'apiClientAutenticadoProvider',
  'ApiClientAutenticado',
  'AuthApi',
  'core/auth/auth_providers',
];

void main() {
  String normalizar(String ruta) => ruta.replaceAll(r'\', '/');

  /// Todos los `.dart` de `lib/`, excluyendo lo generado.
  List<File> fuentesDeLib() =>
      Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'))
          .toList();

  /// El código sin las líneas de comentario. Ver la nota de cabecera.
  String sinComentarios(String fuente) => fuente
      .split('\n')
      .where((linea) => !linea.trimLeft().startsWith('//'))
      .join('\n');

  String codigoDe(String ruta) => sinComentarios(File(ruta).readAsStringSync());

  /// El cuerpo de una clase, entre su `{` y el `}` que lo cierra. Sirve para
  /// afirmar qué campos tiene SIN que cuente lo que digan los comentarios de
  /// alrededor.
  String cuerpoDeClase(String codigo, String nombre) {
    final declaracion = codigo.indexOf('class $nombre {');

    expect(
      declaracion,
      greaterThan(-1),
      reason: 'no se encontró class $nombre',
    );

    var profundidad = 0;
    final inicio = codigo.indexOf('{', declaracion);

    for (var i = inicio; i < codigo.length; i++) {
      if (codigo[i] == '{') profundidad++;
      if (codigo[i] == '}') {
        profundidad--;
        if (profundidad == 0) return codigo.substring(inicio, i + 1);
      }
    }

    fail('la clase $nombre no está cerrada');
  }

  // =========================================================================
  // A y B — el portón productivo no se toca
  // =========================================================================

  group('A/B — el gate productivo sigue siendo el legacy', () {
    const router = 'lib/app/router/app_router.dart';

    test('app_router NO conoce la autenticación remota', () {
      final codigo = codigoDe(router);

      for (final simbolo in _simbolosRemotos) {
        expect(
          codigo,
          isNot(contains(simbolo)),
          reason:
              'IF-2 no releva el portón: «$simbolo» en el router haría que la '
              'sesión remota decidiera la navegación antes de que exista forma '
              'segura de llegar al producto sin una SesionUsuario',
        );
      }
    });

    test('app_router SIGUE dependiendo de la sesión local', () {
      final codigo = codigoDe(router);

      expect(codigo, contains('sesionControllerProvider'));
      expect(
        codigo,
        contains('permisosQueAbrenRuta'),
        reason: 'los permisos que abren cada módulo siguen siendo los locales',
      );
    });

    test('bootstrap NO arranca la autenticación remota', () {
      // Restaurar la sesión remota en el arranque la convertiría de hecho en el
      // portón: un fallo suyo pasaría a bloquear el login local.
      final codigo = codigoDe('lib/app/bootstrap.dart');

      for (final simbolo in _simbolosRemotos) {
        expect(codigo, isNot(contains(simbolo)), reason: simbolo);
      }

      expect(
        codigo,
        contains('RestaurarSesionRecordadaUseCase'),
        reason: 'lo que sí se restaura en el arranque sigue siendo lo local',
      );
    });
  });

  // =========================================================================
  // C — la pantalla de login productiva
  // =========================================================================

  group('C — el login productivo sigue siendo local', () {
    const pantalla =
        'lib/features/usuarios/presentation/auth/login_screen.dart';

    test('la pantalla de login usa la sesión local y no la remota', () {
      final codigo = codigoDe(pantalla);

      expect(codigo, contains('sesionControllerProvider'));

      for (final simbolo in _simbolosRemotos) {
        expect(
          codigo,
          isNot(contains(simbolo)),
          reason:
              'sustituir esta pantalla exigiría un segundo login o fabricar una '
              'identidad local, y las dos cosas están descartadas',
        );
      }
    });

    test('NO existe una segunda pantalla de login', () {
      // Ni productiva ni «oculta para poder probar»: una ruta que sólo existe
      // para justificar la etapa se queda para siempre.
      final pantallas =
          fuentesDeLib()
              .map((f) => normalizar(f.path))
              .where(
                (ruta) =>
                    ruta.contains('login') && ruta.endsWith('_screen.dart'),
              )
              .toList();

      expect(pantallas, [pantalla]);
    });

    test('ninguna ruta del router menciona un login remoto', () {
      expect(
        codigoDe('lib/app/router/app_router.dart').toLowerCase(),
        isNot(contains('login-remoto')),
      );
      expect(
        codigoDe('lib/app/router/app_router.dart').toLowerCase(),
        isNot(contains('loginremoto')),
      );
    });
  });

  // =========================================================================
  // D, E y F — la Identity del backend no se convierte en Usuario local
  // =========================================================================

  group('D/E/F — Identity != Usuario, sin puente de ninguna clase', () {
    test('los archivos de IF-2 no conocen el Usuario local', () {
      const prohibidos = [
        'SesionUsuario',
        'UsuarioRepository',
        'usuarioId',
        'actorUsuarioId',
        'AppDatabase',
        'sesionControllerProvider',
        'permisoUsuario',
      ];

      for (final ruta in _archivosDeIF2) {
        final codigo = codigoDe(ruta);

        for (final simbolo in prohibidos) {
          expect(
            codigo,
            isNot(contains(simbolo)),
            reason: '$ruta no debe conocer «$simbolo»',
          );
        }
      }
    });

    test('NO hay emparejamiento por correo, nombre, displayName ni username', () {
      // La prueba mira la CONVIVENCIA de símbolos: un archivo que hable de la
      // sesión remota y a la vez de la búsqueda de un Usuario local es
      // exactamente la forma que tendría el emparejamiento prohibido.
      const buscarUsuarioLocal = [
        'obtenerPorNombreUsuario',
        'nombreUsuario',
        'UsuarioRepositoryImpl',
        'obtenerPorId',
      ];

      final sospechosos = <String>[];

      for (final archivo in fuentesDeLib()) {
        final codigo = sinComentarios(archivo.readAsStringSync());

        final hablaDeRemoto = _simbolosRemotos.any(codigo.contains);
        final buscaUsuario = buscarUsuarioLocal.any(codigo.contains);

        if (hablaDeRemoto && buscaUsuario) {
          sospechosos.add(normalizar(archivo.path));
        }
      }

      expect(
        sospechosos,
        isEmpty,
        reason:
            'emparejar una Identity con un Usuario por texto es inferir la '
            'pertenencia, que es lo mismo que el backend prohíbe para la Company',
      );
    });

    test('el ID de Identity NUNCA llega a actorUsuarioId', () {
      final sospechosos = <String>[];

      for (final archivo in fuentesDeLib()) {
        final codigo = sinComentarios(archivo.readAsStringSync());

        if (codigo.contains('actorUsuarioId') &&
            _simbolosRemotos.any(codigo.contains)) {
          sospechosos.add(normalizar(archivo.path));
        }
      }

      expect(
        sospechosos,
        isEmpty,
        reason:
            'la atribución de 15 tablas apunta a Usuario por clave ajena real; '
            'escribir ahí un id del backend la rompería en silencio',
      );
    });

    test('no existe columna ni tabla puente Usuario↔Identity', () {
      // La relación queda FUERA de IF-2: se prefiere retirar dependencias
      // legacy antes que introducir un vínculo transitorio sin evidencia de que
      // vaya a formar parte del modelo final.
      final tablas = fuentesDeLib()
          .where((f) => normalizar(f.path).contains('core/database'))
          .map((f) => sinComentarios(f.readAsStringSync()))
          .join('\n');

      for (final prohibido in [
        'identityId',
        'identity_id',
        'sessionId',
        'identidadRemota',
      ]) {
        expect(tablas, isNot(contains(prohibido)), reason: prohibido);
      }
    });

    test('la sesión local no depende de la remota', () {
      // La dependencia es de un solo sentido, y por eso no hay ciclo posible ni
      // forma de que cerrar la sesión remota cierre la local.
      for (final ruta in [
        'lib/features/usuarios/presentation/sesion_controller.dart',
        'lib/features/usuarios/domain/usecases/login_usecase.dart',
        'lib/features/usuarios/usuarios_providers.dart',
        'lib/core/auth/sesion_recordada_almacen.dart',
        'lib/core/auth/password_hasher.dart',
        'lib/app/shell/shell_permissions.dart',
      ]) {
        final codigo = codigoDe(ruta);

        for (final simbolo in _simbolosRemotos) {
          expect(codigo, isNot(contains(simbolo)), reason: '$ruta → $simbolo');
        }
      }
    });
  });

  // =========================================================================
  // G y H — qué lleva cada objeto dentro
  // =========================================================================

  group('G — SesionRemota no lleva credenciales ni autorización', () {
    late String cuerpo;

    setUp(
      () =>
          cuerpo = cuerpoDeClase(
            codigoDe('lib/core/auth/sesion_remota.dart'),
            'SesionRemota',
          ),
    );

    test('ningún token', () {
      expect(cuerpo, isNot(contains('refreshToken')));
      expect(cuerpo, isNot(contains('accessToken')));
    });

    test('ni Company, ni permisos, ni restricted', () {
      // Autenticarse responde «quién eres». Qué Company está activa y qué puede
      // hacer esa identidad lo responde `/context`, y es una pregunta de IF-4.
      // Mezclarlas obligaría a reautenticar para refrescar un permiso.
      for (final prohibido in [
        'company',
        'Company',
        'permis',
        'restricted',
        'moduleEnabled',
      ]) {
        expect(cuerpo, isNot(contains(prohibido)), reason: prohibido);
      }
    });

    test('sólo tres campos: sessionId, email y displayName', () {
      expect(cuerpo, contains('final String sessionId;'));
      expect(cuerpo, contains('final String email;'));
      expect(cuerpo, contains('final String? displayName;'));
    });
  });

  group('H — el token de acceso no se persiste', () {
    test('CredencialRemota no tiene dónde guardarlo', () {
      final cuerpo = cuerpoDeClase(
        codigoDe('lib/core/auth/sesion_remota.dart'),
        'CredencialRemota',
      );

      expect(cuerpo, isNot(contains('accessToken')));
      expect(cuerpo, contains('final String refreshToken;'));
    });

    test('el almacén seguro no menciona el token de acceso', () {
      expect(
        codigoDe('lib/core/auth/almacen_sesion_remota.dart'),
        isNot(contains('accessToken')),
      );
    });

    test('y lo que se escribe en disco tampoco lo lleva', () {
      // La comprobación de comportamiento, no de código: se serializa una
      // credencial de verdad y se mira el texto.
      final texto =
          CredencialRemota(
            refreshToken: 'rt_1',
            refreshExpiresAt: DateTime.utc(2026, 10, 12),
            sessionId: 's',
            email: 'a@b.mx',
          ).aTexto();

      expect(texto.toLowerCase(), isNot(contains('access')));
      expect(texto.toLowerCase(), isNot(contains('password')));
    });
  });

  // =========================================================================
  // I — dónde NO aparece el token de refresco
  // =========================================================================

  group('I — el token de refresco vive en un solo sitio', () {
    test('sólo tres archivos de lib/ lo mencionan', () {
      final archivos =
          fuentesDeLib()
              .where(
                (f) => sinComentarios(
                  f.readAsStringSync(),
                ).contains('refreshToken'),
              )
              .map((f) => normalizar(f.path))
              .toList()
            ..sort();

      expect(archivos, [
        'lib/core/auth/auth_api.dart',
        'lib/core/auth/gestor_de_sesion.dart',
        'lib/core/auth/sesion_remota.dart',
      ]);
    });

    test('NO está en Drift', () {
      // La base local se respalda y se restaura en otro equipo (Etapa 14C/4D).
      // Una credencial de sesión ahí viajaría con el respaldo.
      for (final archivo in fuentesDeLib()) {
        final codigo = sinComentarios(archivo.readAsStringSync());

        if (!codigo.contains('refreshToken')) continue;

        expect(
          codigo,
          isNot(contains('drift')),
          reason: '${normalizar(archivo.path)} mezcla el refresco con Drift',
        );
      }
    });

    test('NO está en shared_preferences', () {
      // `shared_preferences` guarda preferencias de interfaz en claro.
      for (final archivo in fuentesDeLib()) {
        final codigo = sinComentarios(archivo.readAsStringSync());

        if (!codigo.contains('refreshToken')) continue;

        expect(codigo, isNot(contains('shared_preferences')));
        expect(codigo, isNot(contains('SharedPreferences')));
      }
    });

    test('la entrada del almacén es independiente de la sesión local', () {
      expect(
        AlmacenSesionRemotaWindows.nombreClave,
        'seventra_sesion_remota_v1',
      );

      final legacy = codigoDe('lib/core/auth/sesion_recordada_almacen.dart');

      expect(legacy, contains('riseg_one_sesion_recordada_token_v1'));
      expect(
        legacy,
        isNot(contains(AlmacenSesionRemotaWindows.nombreClave)),
        reason: 'compartir entrada haría que cerrar una sesión borrara la otra',
      );
    });

    test('tampoco se mezcla con la Bóveda empresarial', () {
      // La Bóveda guarda secretos de la EMPRESA bajo una clave maestra que se
      // respalda y se recupera en otro equipo. Una sesión de usuario es de esta
      // persona y de este equipo.
      for (final ruta in _archivosDeIF2) {
        final codigo = codigoDe(ruta);

        expect(codigo, isNot(contains('Boveda')));
        expect(codigo, isNot(contains('CredentialCipher')));
        expect(codigo, isNot(contains('AlmacenClaveCifrado')));
        expect(codigo, isNot(contains('AlmacenRanurasClave')));
      }
    });
  });

  // =========================================================================
  // J — independencia de las dos infraestructuras
  // =========================================================================

  group('J — la maquinaria remota se sostiene sola', () {
    test('no importa nada de features/ ni de la base de datos', () {
      for (final ruta in _archivosDeIF2) {
        final codigo = codigoDe(ruta);

        expect(
          codigo,
          isNot(contains('features/')),
          reason: '$ruta importa una feature',
        );
        expect(
          codigo,
          isNot(contains('core/database')),
          reason: '$ruta importa la base local',
        );
      }
    });

    test('NINGUNA feature consume todavía la capa remota', () {
      // Conectar un módulo es IF-6 y siguientes. Que una feature empiece a usar
      // esto antes del relevo del portón la obligaría a resolver por su cuenta
      // qué identidad atribuye lo que escribe.
      final infractores = <String>[];

      for (final archivo in fuentesDeLib()) {
        if (!normalizar(archivo.path).contains('/features/')) continue;

        final codigo = sinComentarios(archivo.readAsStringSync());

        if (_simbolosRemotos.any(codigo.contains)) {
          infractores.add(normalizar(archivo.path));
        }
      }

      expect(infractores, isEmpty);
    });

    test('los dos almacenes son tipos distintos, no uno reutilizado', () {
      expect(
        const AlmacenSesionRemotaWindows(),
        isNot(isA<AlmacenSesionRecordada>()),
      );
      expect(
        const AlmacenSesionRecordadaWindows(),
        isNot(isA<AlmacenSesionRemota>()),
      );
    });
  });

  // =========================================================================
  // El alcance de lo implementado
  // =========================================================================

  group('El alcance de IF-2', () {
    test('AuthApi implementa TRES rutas y ninguna más', () {
      final codigo = codigoDe('lib/core/auth/auth_api.dart');

      expect(codigo, contains("'/auth/login'"));
      expect(codigo, contains("'/auth/refresh'"));
      expect(codigo, contains("'/auth/logout'"));

      // Existen en el backend, pero alta de cuentas y recuperación de contraseña
      // son flujos con correo de por medio: pertenecen al portal web.
      for (final fuera in [
        '/auth/register',
        '/auth/verify-email',
        '/auth/forgot-password',
        '/auth/reset-password',
      ]) {
        expect(codigo, isNot(contains(fuera)), reason: fuera);
      }
    });

    test('la etapa no trajo ningún paquete nuevo', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();

      for (final descartado in [
        'dio:',
        'oauth2:',
        'jwt_decoder:',
        'dart_jsonwebtoken:',
        'cookie_jar:',
        'http_interceptor:',
      ]) {
        expect(pubspec, isNot(contains(descartado)), reason: descartado);
      }

      // Los dos que hacen falta ya estaban: `http` desde IF-1 y
      // `flutter_secure_storage` desde la Etapa 9D.
      expect(pubspec, contains('http: ^1.6.0'));
      expect(pubspec, contains('flutter_secure_storage: ^9.2.2'));
    });

    test('el cliente desnudo de IF-1 sigue sin autenticar', () {
      // La frontera de IF-1 se conserva: la política de sesión vive en el
      // decorador, no en el transporte.
      final codigo = codigoDe('lib/core/api/api_client.dart');

      expect(codigo, isNot(contains("'Authorization'")));
      expect(codigo, isNot(contains('accessToken')));
      expect(codigo, isNot(contains('refreshToken')));
    });
  });
}
