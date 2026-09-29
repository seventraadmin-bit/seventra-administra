import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:riseg_one/core/auth/auth_providers.dart';
import 'package:riseg_one/core/auth/sesion_remota.dart';
import 'package:riseg_one/core/company/company_providers.dart';
import 'package:riseg_one/core/company/company_remota.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/core/error/failure.dart';
import 'package:riseg_one/core/error/result.dart';
import 'package:riseg_one/core/identity/proyeccion_identity_usuario.dart';
import 'package:riseg_one/core/permissions/vocabulario_permisos.dart';

import '../domain/login_resultado.dart';
import '../domain/sesion_usuario.dart';

part 'sesion_controller.g.dart';

/// La sesión activa de Seventra Administra.
///
/// ## Qué cambió en IF-5
///
/// Hasta el cutover esto preguntaba a SQLite: `LoginUseCase` comparaba un hash
/// local y `revalidar()` releía la fila `Usuario`. **Ya no.** La cadena
/// productiva es:
///
/// ```
///   Identity SaaS  →  Company  →  CompanyContext  →  proyección  →  sesión
/// ```
///
/// y cada eslabón lo resuelve el motor que ya existía: `GestorDeSesion` (IF-2),
/// `GestorDeCompany` (IF-3) y la autorización que llega dentro del contexto
/// (IF-4). Este controlador no reimplementa ninguno: los encadena y traduce el
/// resultado al [SesionUsuario] que el producto entero consume desde la Etapa
/// 11A, para que las sesenta y una pantallas que lo leen no se enteren.
///
/// **No hay camino alternativo.** Si el backend no responde, no se entra: no
/// existe repliegue a la autenticación local, y eso es deliberado — un repliegue
/// silencioso convertiría una caída de red en una sesión con permisos de otra
/// época.
///
/// `keepAlive: true` sigue siendo obligatorio por la misma razón de siempre (ver
/// el historial de la Etapa 11B): sin él la sesión volvía a `null` en cuanto
/// ningún widget la observaba durante una transición de navegación.
@Riverpod(keepAlive: true)
class SesionController extends _$SesionController {
  @override
  SesionUsuario? build() => null;

  /// ¿La sesión viva NACIÓ de la cadena SaaS de este controlador?
  ///
  /// Lo pone [_abrirCompany], que es el único camino por el que se publica una
  /// sesión en producción —tanto al entrar como al restaurar—. Sirve para una
  /// cosa concreta: **[revalidar] sólo puede preguntar por una sesión que salió
  /// de un `CompanyContext`**. Una sesión inyectada por otra vía no tiene fuente
  /// a la que volver, y salir a la red por ella devolvería «no hay contexto» y
  /// la mataría sin que nada hubiera cambiado de verdad.
  ///
  /// No debilita nada en producción: ahí no existe otra vía de publicar sesión,
  /// así que esto es siempre `true` desde el primer instante.
  bool _nacidaDelContexto = false;

  /// Entra con correo y contraseña contra el backend SaaS.
  Future<LoginResultado> login({
    required String correo,
    required String password,
  }) async {
    final autenticacion = await ref
        .read(gestorDeSesionProvider)
        .iniciarSesion(email: correo.trim(), password: password);

    switch (autenticacion) {
      case Err<SesionRemota>(:final failure):
        return _traducirFalloDeLogin(failure);

      case Ok<SesionRemota>(:final value):
        return _abrirCompany(value);
    }
  }

  /// Restaura la sesión guardada en el equipo, si la hay.
  ///
  /// Es lo que sustituye a «Recuérdame en este equipo»: el refresco vive cifrado
  /// en el almacén del sistema y el backend decide si sigue valiendo. Una
  /// credencial revocada —contraseña restablecida, cuenta suspendida, canje
  /// repetido— no restaura nada, y eso ocurre en el servidor, no aquí.
  ///
  /// Devuelve la sesión resultante, o `null` si no había o ya no vale.
  Future<SesionUsuario?> restaurar() async {
    final estado = await ref.read(gestorDeSesionProvider).restaurar();

    if (estado is! Autenticado) {
      state = null;
      return null;
    }

    final resultado = await _abrirCompany(estado.sesion);
    return resultado is LoginExitoso ? resultado.sesion : null;
  }

  /// Cierra la sesión. `state = null` es lo único síncrono e incondicional.
  ///
  /// El aviso al backend y el borrado de la credencial se disparan sin esperar:
  /// cerrar sesión no puede quedarse colgado de una llamada de red ni del
  /// almacén de credenciales del sistema. Si fallan, el peor caso es que el
  /// servidor conserve una sesión que ya nadie usa y que caducará sola.
  void logout() {
    state = null;
    _nacidaDelContexto = false;
    unawaited(_cerrarRemoto());
  }

  /// Vuelve a preguntar al servidor quién es y qué puede hacer.
  ///
  /// **Es el único mecanismo por el que una sesión abierta deja de estar
  /// autorizada**, y sigue estando donde estaba: lo llama el `redirect` del
  /// router en cada navegación y los dos embudos de autorización. Lo que cambió
  /// es a quién pregunta — antes a SQLite, ahora al `CompanyContext`, que es la
  /// autoridad.
  ///
  /// Cubre de una vez el acceso revocado, el permiso retirado, el Maestro
  /// degradado, el módulo apagado y la suscripción caída en `restricted`: todos
  /// son el mismo hecho, «la sesión en memoria dejó de describir la realidad».
  Future<SesionUsuario?> revalidar() async {
    final actual = state;
    if (actual == null) return null;

    // Ver `_nacidaDelContexto`: sin fuente a la que volver no hay nada que
    // revalidar, y preguntar de todos modos mataría una sesión sana.
    if (!_nacidaDelContexto) return actual;

    final estado = await ref.read(gestorDeCompanyProvider).revalidar();

    if (estado is! CompanyActiva) {
      // Perder la Company es perder el acceso a los datos: la sesión de
      // Administra deja de existir aunque la Identity siga autenticada.
      state = null;
      return null;
    }

    final nueva = _desdeContexto(actual.usuarioId, actual.nombreUsuario, estado.contexto);

    // Sólo se reemplaza si algo cambió de verdad: `state =` reconstruye el
    // sidebar y los gates, y hacerlo en cada navegación sin motivo sería
    // repintar media aplicación por nada.
    if (_equivalentes(actual, nueva)) return actual;

    state = nueva;
    return nueva;
  }

  // =========================================================================

  /// Resuelve la Company y arma la sesión. Compartido por login y restauración,
  /// porque a partir de tener la Identity los dos caminos son el mismo.
  Future<LoginResultado> _abrirCompany(SesionRemota remota) async {
    final estado = await ref.read(gestorDeCompanyProvider).resolver();

    switch (estado) {
      // Autenticó bien y no tiene dónde entrar. No es un error de credencial.
      case SinAccesoACompanies():
        return LoginSinCompany();

      // Varias empresas sin preferencia válida: el motor de IF-3 ya eligió
      // candidata cuando pudo; si llega aquí es que hay que preguntar, y eso
      // todavía no tiene pantalla. Se trata como «sin Company» —explícito y sin
      // entrar a medias— en vez de elegir una por el cliente, que sería mezclar
      // datos de empresas distintas por comodidad.
      case SeleccionDeCompanyRequerida():
        return LoginSinCompany();

      case CompanyNoResuelta(:final motivo):
        return LoginErrorInesperado(motivo.message);

      case CompanySinResolver():
        return LoginErrorInesperado('No se pudo resolver la empresa activa.');

      case CompanyActiva(:final contexto):
        final sesion = _desdeContexto(remota.identityId, remota.email, contexto);

        // La proyección va DESPUÉS de tener contexto y ANTES de publicar la
        // sesión: `esMaestro` se proyecta desde el servidor, y ninguna pantalla
        // debe poder leer la sesión antes de que exista la fila a la que apunta
        // `actorUsuarioId`.
        await ProyeccionIdentityUsuario(ref.read(appDatabaseProvider)).proyectar(
          identityId: remota.identityId,
          nombre: remota.displayName ?? remota.email,
          correo: remota.email,
          esMaestro: contexto.isMaestro,
        );

        state = sesion;
        _nacidaDelContexto = true;
        return LoginExitoso(sesion);
    }
  }

  /// La sesión del producto, armada desde lo que dijo el servidor.
  SesionUsuario _desdeContexto(String identityId, String correo, CompanyContext contexto) {
    return SesionUsuario(
      // El `identityId`, tal cual. Ver `ProyeccionIdentityUsuario`.
      usuarioId: identityId,
      nombre: state?.nombre ?? correo,
      nombreUsuario: correo,
      esMaestro: contexto.isMaestro,
      // La ÚNICA traducción de vocabulario del proyecto.
      permisos: permisosDelProducto(contexto.effectivePermissions),
      restringido: contexto.restricted,
    );
  }

  static bool _equivalentes(SesionUsuario a, SesionUsuario b) =>
      a.esMaestro == b.esMaestro &&
      a.restringido == b.restringido &&
      a.nombre == b.nombre &&
      a.nombreUsuario == b.nombreUsuario &&
      a.permisos.length == b.permisos.length &&
      a.permisos.containsAll(b.permisos);

  LoginResultado _traducirFalloDeLogin(Failure failure) {
    final mensaje = failure.message;

    // El backend distingue «correo sin verificar», «cuenta suspendida» y
    // «bloqueada por intentos» de una credencial incorrecta, y esa distinción
    // ayuda a quien ya demostró conocer su contraseña. Se conserva tal cual
    // llega: el mensaje lo redacta el servidor, que es quien sabe.
    if (failure is ApiHttpFailure) {
      return switch (failure.codigo) {
        'credenciales_invalidas' => LoginCredencialesInvalidas(),
        'email_no_verificado' || 'cuenta_suspendida' || 'cuenta_bloqueada' =>
          LoginUsuarioInactivo(mensaje),
        _ => LoginErrorInesperado(mensaje),
      };
    }

    return LoginErrorInesperado(mensaje);
  }

  Future<void> _cerrarRemoto() async {
    try {
      await ref.read(gestorDeSesionProvider).cerrarSesion();
      await ref.read(gestorDeCompanyProvider).olvidarSeleccion();
    } catch (_) {
      // Best-effort — ver el doc comment de `logout`.
    }
  }
}
