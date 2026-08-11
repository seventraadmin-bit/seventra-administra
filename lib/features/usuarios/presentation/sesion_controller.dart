import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../domain/sesion_usuario.dart';
import '../domain/usecases/login_usecase.dart';
import '../usuarios_providers.dart';

part 'sesion_controller.g.dart';

/// Sesión activa de RISEG ONE (Etapa 11A) — `null` significa "sin
/// sesión", el estado que fuerza al `redirect` del router a mandar a
/// `/login`. No se persiste entre reinicios a propósito (ver el plan de
/// la Etapa 11, §5): cada arranque de la aplicación exige iniciar
/// sesión de nuevo, nunca se guarda contraseña ni token.
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

  Future<LoginResultado> login({required String nombreUsuario, required String password}) async {
    final resultado = await ref.read(loginUseCaseProvider).ejecutar(nombreUsuario: nombreUsuario, password: password);
    if (resultado is LoginExitoso) state = resultado.sesion;
    return resultado;
  }

  void logout() => state = null;
}
