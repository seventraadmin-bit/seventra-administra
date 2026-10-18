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

  // IF-5 — ESTE GRUPO CAMBIÓ DE SIGNO, y era su destino.
  //
  // En IF-2 decía «el gate productivo sigue siendo el legacy»: la maquinaria
  // remota existía y no gobernaba nada, a propósito, porque no había forma
  // segura de llegar al producto sin una `SesionUsuario` local. El cutover es
  // justamente el momento en que eso se invierte, así que la afirmación se
  // reescribe en vez de borrarse — lo que se vigila ahora es que el portón sea
  // el remoto y que NO haya quedado ninguno local.
  group('A/B — el gate productivo ES el remoto, y no queda ninguno local', () {
    const router = 'lib/app/router/app_router.dart';

    test('el router ya no cuenta usuarios locales ni ofrece bootstrap local', () {
      final codigo = codigoDe(router);

      expect(
        codigo,
        isNot(contains('contarUsuariosProvider')),
        reason: 'contar filas de `Usuario` era el portón que decidía si había que '
            'crear el primer Maestro a mano. Ese alta es hoy del aprovisionamiento SaaS',
      );
      expect(codigo, isNot(contains('/bootstrap-maestro')));
      expect(
        codigo,
        isNot(contains('debeCambiarPassword')),
        reason: 'no quedan contraseñas temporales que un Maestro fije en local',
      );
    });

    test('el router sigue gateando por sesión y por permiso de módulo', () {
      final codigo = codigoDe(router);

      // La ESTRUCTURA del gate no cambió, y eso es lo valioso: lo que cambió es
      // de dónde salen las respuestas.
      expect(codigo, contains('sesionControllerProvider'));
      expect(codigo, contains('revalidar()'));
      expect(
        codigo,
        contains('permisosQueAbrenRuta'),
        reason: 'los módulos se siguen abriendo por permiso, con la granularidad del producto',
      );
    });

    test('el arranque restaura la sesión SaaS y ya no la local', () {
      final codigo = codigoDe('lib/app/bootstrap.dart');

      expect(
        codigo,
        isNot(contains('RestaurarSesionRecordadaUseCase')),
        reason: '«Recuérdame en este equipo» leía la base local; ahora restaura el '
            'refresco cifrado y decide el servidor',
      );
      expect(
        codigo,
        contains('restaurar()'),
        reason: 'el arranque pide la restauración remota',
      );
    });
  });

  // =========================================================================
  // C — la pantalla de login productiva
  // =========================================================================

  group('C — el login productivo es el REAL, y sigue siendo uno solo', () {
    const pantalla =
        'lib/features/usuarios/presentation/auth/login_screen.dart';

    test('la pantalla de siempre autentica ahora contra el backend', () {
      final codigo = codigoDe(pantalla);

      // Es LA MISMA pantalla: no se creó otra, y sigue publicando la sesión por
      // el mismo controlador que consume el producto entero.
      expect(codigo, contains('sesionControllerProvider'));

      // Y pide correo, no nombre de usuario.
      expect(codigo, contains('correo:'));
      expect(
        codigo,
        contains('loginOlvideContrasena'),
        reason: 'la recuperación se conecta al ciclo de correo que ya existía',
      );
    });

    const pantallaWeb = 'lib/features/usuarios/web/login_web_screen.dart';

    test('UNA pantalla de login por punto de entrada, y ninguna más', () {
      // ASÍ SE AJUSTÓ ESTA PRUEBA EN M3, Y POR QUÉ NO ES UN AFLOJE.
      //
      // Hasta aquí exigía UNA sola pantalla, con esta razón: «ni productiva ni
      // oculta para poder probar — una ruta que sólo existe para justificar la
      // etapa se queda para siempre». Eso sigue siendo verdad.
      //
      // Lo que cambió es que hay DOS PUNTOS DE ENTRADA, no dos logins del mismo:
      // `lib/main.dart` compila para Windows y `lib/main_web.dart` para el
      // navegador, y **no pueden compartir pantalla** — la del escritorio pasa por
      // `sesionControllerProvider`, que arrastra Drift y por tanto `dart:ffi`. Es
      // una imposibilidad medida, no una preferencia.
      //
      // Así que la lista es cerrada y de dos, y la prueba de abajo exige lo que de
      // verdad importaba: que las dos autentiquen contra EL MISMO motor. Una tercera
      // pantalla —o una segunda para el mismo destino— vuelve a fallar aquí.
      final pantallas =
          fuentesDeLib()
              .map((f) => normalizar(f.path))
              .where(
                (ruta) =>
                    ruta.contains('login') && ruta.endsWith('_screen.dart'),
              )
              .toList()
            ..sort();

      expect(pantallas, [pantalla, pantallaWeb]..sort());
    });

    test('las dos pantallas autentican contra el MISMO motor', () {
      // ESTO ES LO QUE LA PRUEBA DE ARRIBA PROTEGÍA DE VERDAD. Dos puertas son
      // aceptables; dos formas de decidir quién eres, no. El día que una pantalla
      // compruebe la contraseña por su cuenta —contra la tabla `Usuario` local, por
      // ejemplo— habría dos verdades sobre la identidad y la auditoría quedaría
      // atribuida a dos actores distintos para la misma persona.
      final web = codigoDe(pantallaWeb);

      // La web habla con el gestor directamente: no hay Riverpod en su árbol.
      expect(web, contains('GestorDeSesion'));
      expect(web, contains('iniciarSesion'));

      // Y NINGUNA DE LAS DOS conoce el usuario local ni comprueba contraseñas.
      for (final ruta in [pantalla, pantallaWeb]) {
        final codigo = codigoDe(ruta);

        for (final prohibido in [
          'PasswordHasher',
          'usuarioRepository',
          'UsuarioRepository',
          'verificarPassword',
        ]) {
          expect(
            codigo,
            isNot(contains(prohibido)),
            reason:
                '$ruta menciona «$prohibido»: una pantalla de login no decide si '
                'una contraseña es válida, la manda y espera la respuesta',
          );
        }
      }
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

    /// ESTE GUARDIA SIGUE VIVO Y ES EL MÁS IMPORTANTE DEL ARCHIVO.
    ///
    /// IF-5 permite proyectar la Identity en una fila `Usuario`, pero **sólo por
    /// su id**. Buscar un Usuario existente por correo, por nombre o por
    /// username para «reconocerlo» sigue prohibido: sería inferir la pertenencia
    /// de una identidad a partir de texto, que es exactamente lo que el backend
    /// prohíbe para la Company.
    test('NADIE busca un Usuario local por correo, nombre o username', () {
      // Se buscan las consultas por TEXTO. `obtenerPorId` queda fuera a
      // propósito: buscar por clave primaria es lo que hace la proyección, y es
      // precisamente lo permitido.
      const buscarPorTexto = [
        'obtenerPorNombreUsuario',
        'nombreUsuario.equals',
        'email.equals',
        'nombre.equals',
      ];

      final sospechosos = <String>[];

      for (final archivo in fuentesDeLib()) {
        final ruta = normalizar(archivo.path);

        // El repositorio de Usuarios y la pantalla de administración consultan
        // por nombre de usuario porque administran cuentas locales, que es otra
        // cosa: lo que se vigila es que NADIE lo haga desde el camino de la
        // identidad remota.
        if (!ruta.contains('core/identity') && !ruta.contains('sesion_controller')) continue;

        final codigo = sinComentarios(archivo.readAsStringSync());

        for (final patron in buscarPorTexto) {
          if (codigo.contains(patron)) sospechosos.add('$ruta → $patron');
        }
      }

      expect(
        sospechosos,
        isEmpty,
        reason: 'emparejar una Identity con un Usuario por texto es inferir la '
            'pertenencia, que es lo mismo que el backend prohíbe para la Company',
      );
    });

    /// El signo contrario del guardia de IF-2, y aprobado explícitamente: el
    /// `identityId` **ES** el `Usuario.id`.
    ///
    /// Lo que se vigila ahora es que no haya un id ALTERNATIVO: la proyección no
    /// puede generar un identificador propio ni traducir, porque entonces
    /// existirían dos identidades y la atribución de quince tablas apuntaría a
    /// la equivocada.
    test('la proyección usa el identityId TAL CUAL, sin generar otro id', () {
      final codigo = sinComentarios(
        codigoDe('lib/core/identity/proyeccion_identity_usuario.dart'),
      );

      expect(
        codigo,
        contains('id: Value(identityId)'),
        reason: 'la fila local nace con el id del backend, no con uno propio',
      );

      for (final generador in ['Uuid()', 'uuid.v4', 'Random()', 'CreateVersion7']) {
        expect(
          codigo,
          isNot(contains(generador)),
          reason: 'generar un id aquí crearía una segunda identidad: «$generador»',
        );
      }
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
      // IF-5 — `sesion_controller` SÍ depende ahora de la capa remota: es el
      // eslabón del cutover. Lo que se sigue vigilando es que la dependencia no
      // se haya derramado a la administración de cuentas ni a los permisos.
      for (final ruta in [
        'lib/features/usuarios/usuarios_providers.dart',
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
            identityId: 'i-1',
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

    test('la entrada del almacén sigue siendo una sola y con nombre propio', () {
      // IF-5 — ya no hay una segunda entrada con la que confundirse: el almacén
      // de la sesión recordada local se retiró con la autenticación local. Lo
      // que se conserva es el nombre exacto de la que queda, porque cambiarlo
      // dejaría huérfanas las credenciales guardadas en los equipos.
      expect(
        AlmacenSesionRemotaWindows.nombreClave,
        'seventra_sesion_remota_v1',
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

    test('SÓLO el camino de la sesión consume la capa remota', () {
      // IF-5 — antes esto exigía que NINGUNA feature la consumiera, porque la
      // maquinaria remota todavía no gobernaba nada. El cutover la conectó, y lo
      // que importa ahora es que la conexión ocurra en UN sitio: si cada módulo
      // hablara con el backend por su cuenta, tendría que resolver solo qué
      // identidad atribuye lo que escribe, y ahí nacen las divergencias.
      // M3 AÑADE LA PRIMERA DE LA MUDANZA, y el motivo de que no viole lo de arriba
      // es preciso: `AreasRepositorioHttp` **recibe** el cliente autenticado por
      // constructor. No construye una sesión, no lee un estado global y no resuelve
      // ninguna identidad — eso sigue pasando en UN sitio.
      //
      // Lo que esta prueba vigila es que nadie se autentique por su cuenta. Un
      // repositorio que acepta el cliente ya autenticado no es eso, y confundir las
      // dos cosas obligaría a cada módulo migrado a pasar por `sesion_controller`
      // para hacer un GET.
      // EL PORTÓN WEB AÑADE DOS, y por la misma razón que el repositorio de áreas:
      // los dos **reciben** el `GestorDeSesion` por constructor. No construyen una
      // sesión, no leen un estado global y no resuelven ninguna identidad.
      //
      // `login_web_screen.dart` es la contraparte de `login_screen.dart`, que ya
      // estaba permitido: es la pantalla donde se escribe la contraseña, y el
      // escritorio y la web son dos puertas al mismo motor. `porton_web.dart` es
      // quien observa el estado para decidir qué pantalla toca — exactamente el
      // papel que `sesion_controller.dart` hace en el escritorio.
      //
      // SON RUTAS EXACTAS, NO LA CARPETA `features/usuarios/web/`. Con el prefijo,
      // cualquier archivo futuro de esa carpeta entraría sin que nadie lo decidiera.
      const permitidos = [
        'lib/features/usuarios/presentation/sesion_controller.dart',
        'lib/features/usuarios/presentation/auth/login_screen.dart',
        'lib/features/organizacion/web/datos/areas_repositorio_http.dart',
        'lib/features/usuarios/web/login_web_screen.dart',
        'lib/features/usuarios/web/porton_web.dart',
      ];

      final infractores = <String>[];

      for (final archivo in fuentesDeLib()) {
        final ruta = normalizar(archivo.path);
        if (!ruta.contains('/features/')) continue;
        if (permitidos.contains(ruta)) continue;

        final codigo = sinComentarios(archivo.readAsStringSync());

        if (_simbolosRemotos.any(codigo.contains)) infractores.add(ruta);
      }

      expect(infractores, isEmpty);
    });

    // IF-5 — la prueba «los dos almacenes son tipos distintos» se retiró con el
    // almacén de la sesión recordada local: ya no hay dos almacenes que confundir.
    // El único que queda es el de la credencial remota, y su aislamiento lo fijan
    // las pruebas de este mismo archivo que comprueban que nada fuera de
    // `core/auth` lo toca.
  });

  // =========================================================================
  // El alcance de lo implementado
  // =========================================================================

  group('El alcance del cliente de autenticación', () {
    test('AuthApi implementa CUATRO rutas y ninguna más', () {
      final codigo = codigoDe('lib/core/auth/auth_api.dart');

      expect(codigo, contains("'/auth/login'"));
      expect(codigo, contains("'/auth/refresh'"));
      expect(codigo, contains("'/auth/logout'"));

      // IF-5 añadió el DISPARADOR de la recuperación —«¿Olvidaste tu
      // contraseña?»— para que quien no la recuerda no tenga que salir de la
      // aplicación. Sólo el disparador: el enlace, la página y el canje del token
      // siguen siendo del ciclo web, y esta prueba lo fija.
      expect(codigo, contains("'/auth/forgot-password'"));

      for (final fuera in [
        '/auth/register',
        '/auth/verify-email',
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
