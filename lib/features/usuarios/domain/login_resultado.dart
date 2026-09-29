/// El resultado de intentar entrar, en el vocabulario que la pantalla de login
/// ya traducía a mensajes.
///
/// **IF-5** — vivía dentro de `LoginUseCase`, que desapareció con la
/// autenticación local. Las variantes siguen siendo las mismas para que la
/// pantalla no cambie su `switch`, salvo una nueva: [LoginSinCompany].
library;

import 'sesion_usuario.dart';

sealed class LoginResultado {}

class LoginExitoso extends LoginResultado {
  LoginExitoso(this.sesion);
  final SesionUsuario sesion;
}

/// Cubre tanto «la cuenta no existe» como «la contraseña es incorrecta»: el
/// backend responde lo mismo en los dos casos y aquí no se inventa una
/// distinción que él se guarda a propósito.
class LoginCredencialesInvalidas extends LoginResultado {}

/// La cuenta existe y la contraseña era correcta, pero no puede entrar: el
/// correo sigue sin verificar, o la cuenta está suspendida o bloqueada.
class LoginUsuarioInactivo extends LoginResultado {
  LoginUsuarioInactivo([this.mensaje]);
  final String? mensaje;
}

/// **Autenticó bien y no tiene ninguna empresa donde entrar** (IF-5).
///
/// No es un error ni una credencial mala, y por eso tiene variante propia: la
/// persona es quien dice ser y el sistema no tiene nada que enseñarle todavía.
/// Colapsarlo en «credenciales inválidas» la mandaría a revisar su contraseña,
/// que es exactamente lo único que no está mal.
class LoginSinCompany extends LoginResultado {}

class LoginErrorInesperado extends LoginResultado {
  LoginErrorInesperado(this.mensaje);
  final String mensaje;
}
