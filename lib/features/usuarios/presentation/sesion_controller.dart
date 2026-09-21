import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../domain/sesion_usuario.dart';
import '../domain/usecases/cambiar_contrasena_usuario_usecase.dart';
import '../domain/usecases/login_usecase.dart';
import '../usuarios_providers.dart';

part 'sesion_controller.g.dart';

/// Sesión activa de RISEG ONE (Etapa 11A) — `null` significa "sin
/// sesión", el estado que fuerza al `redirect` del router a mandar a
/// `/login`. No se persiste sola: si el arranque encuentra "Recuérdame
/// en este equipo" válido (Etapa 15,
/// `RestaurarSesionRecordadaUseCase`), `bootstrap()` fija el estado
/// inicial *antes* de `runApp` sobreescribiendo este provider — nunca
/// hay un estado intermedio "cargando" dentro del propio `Notifier`.
///
/// `keepAlive: true` es obligatorio aquí — sin él, `@riverpod` genera
/// un provider `autoDispose` por defecto, y la sesión se perdía (volvía
/// a `null`) en cuanto ningún widget lo observaba activamente ni
/// siquiera un instante durante una transición de navegación (bug real
/// encontrado en la Etapa 11B: el sidebar se veía correcto justo tras
/// el login pero la sesión ya aparecía `null` al leerla un frame
/// después). La sesión debe sobrevivir mientras la app esté abierta,
/// nunca destruirse por falta de observadores momentánea.
@Riverpod(keepAlive: true)
class SesionController extends _$SesionController {
  @override
  SesionUsuario? build() => null;

  Future<LoginResultado> login({required String nombreUsuario, required String password, bool recordarme = false}) async {
    final resultado = await ref
        .read(loginUseCaseProvider)
        .ejecutar(nombreUsuario: nombreUsuario, password: password, recordarme: recordarme);
    if (resultado is LoginExitoso) state = resultado.sesion;
    return resultado;
  }

  /// `state = null` es lo único que este método garantiza de forma
  /// síncrona e incondicional — cerrar sesión nunca debe esperar a
  /// nada más. Limpiar "Recuérdame en este equipo" (Etapa 15) se
  /// dispara en segundo plano, sin `await`: el Almacén de Credenciales
  /// de Windows es una llamada al sistema operativo que puede tardar o,
  /// bajo `flutter test` sin un canal de plataforma real, no
  /// responder nunca — bloquear el cierre de sesión en eso sería un
  /// error tanto en producción (UX) como en pruebas (cuelgue real,
  /// confirmado). Es best-effort: si falla o nunca corre, el peor caso
  /// es que el dispositivo siga recordado hasta que
  /// `RestaurarSesionRecordadaUseCase` lo descarte por su cuenta en un
  /// arranque futuro (mismo criterio de invalidación que ya existe) —
  /// nunca un usuario que no puede cerrar sesión.
  ///
  /// **Limpieza de datos de la sesión anterior** (Etapa "Usuarios,
  /// permisos y UX de seguridad"): NO enumera providers a invalidar, y es correcto que no lo haga:
  /// este controller es el ÚNICO `keepAlive` del proyecto. Todos los
  /// controllers de módulo son `autoDispose`, y `/login` vive fuera del
  /// `StatefulShellRoute`, así que navegar allí desmonta el shell
  /// entero y con él sus ramas y sus controllers. Una lista explícita
  /// aquí se desactualizaría en cuanto naciera un módulo nuevo —
  /// exactamente la clase de fuga que se quiere evitar.
  ///
  /// Lo que sí garantiza que no se vea nada ajeno es el `redirect` del
  /// router: sin sesión manda a `/login` ANTES de construir cualquier
  /// pantalla, y con sesión nueva vuelve a evaluar permisos por ruta.
  /// `SesionRestauradaTest`/`autorizacion_transversal_test` fijan ese
  /// comportamiento.
  void logout() {
    final usuarioId = state?.usuarioId;
    state = null;
    unawaited(_limpiarSesionRecordada(usuarioId));
  }

  /// El titular ya cumplió el cambio obligatorio (Etapa "Usuarios,
  /// permisos y UX de seguridad") — se apaga el candado en la sesión
  /// viva, sin obligar a un nuevo login. La fila de `Usuario` ya quedó
  /// actualizada en la misma transacción del cambio; esto solo
  /// sincroniza el estado en memoria que lee el `redirect`.
  void marcarContrasenaActualizada() {
    final actual = state;
    if (actual == null || !actual.debeCambiarPassword) return;
    state = actual.copyWith(debeCambiarPassword: false);
  }

  Future<void> _limpiarSesionRecordada(String? usuarioId) async {
    try {
      if (usuarioId != null) await ref.read(usuarioRepositoryProvider).borrarSesionPersistente(usuarioId);
      await ref.read(almacenSesionRecordadaProvider).borrar();
    } catch (_) {
      // Best-effort — ver el doc comment de `logout`.
    }
  }
}

/// Cambiar la PROPIA contraseña — deliberadamente SIN `autorizarUseCase`
/// (Etapa "Usuarios, permisos y UX de seguridad").
///
/// Cambiar la contraseña de la cuenta con la que uno ya inició sesión no
/// es administrar usuarios: es autoservicio, y exigir
/// `usuarios.resetearPassword` (la facultad de resetear la de OTRA
/// persona) dejaría a cualquier usuario Normal sin poder cambiar la
/// suya. La autorización aquí es la sesión misma: solo puede afectar al
/// `usuarioId` que está autenticado, nunca a otro.
final cambiarMiContrasenaProvider = Provider<Future<CambiarContrasenaUsuarioResultado> Function(String)>((ref) {
  return (String password) async {
    final sesion = ref.read(sesionControllerProvider);
    if (sesion == null) return CambiarContrasenaUsuarioNoExiste();
    final resultado = await ref.read(cambiarMiContrasenaUseCaseProvider).ejecutar(
          usuarioId: sesion.usuarioId,
          password: password,
          // El actor es el titular: se cambió su propia contraseña.
          actorUsuarioId: sesion.usuarioId,
          // Nadie más la conoce: esto ES cumplir el cambio obligatorio,
          // no crear uno nuevo.
        );
    if (resultado is CambiarContrasenaUsuarioExitoso) {
      ref.read(sesionControllerProvider.notifier).marcarContrasenaActualizada();
    }
    return resultado;
  };
});
