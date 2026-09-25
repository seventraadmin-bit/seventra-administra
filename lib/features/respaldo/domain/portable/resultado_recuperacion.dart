import 'configurar_recuperacion_usecase.dart';

/// Resultados de las tres operaciones de configuración de la recuperación
/// portable, tal como los ve la pantalla (Etapa 4D).
///
/// Existen porque los casos de uso devuelven `null` para decir "la frase
/// no abre esto", y eso no basta en cuanto la operación pasa por una
/// compuerta de autorización: "no eres Maestro", "la frase está mal" y
/// "todavía no hay nada configurado" acabarían siendo el mismo `null`, y
/// la pantalla tendría que elegir un mensaje a ciegas. El proyecto ya
/// arrastra ese patrón en otras etapas como deuda reconocida; aquí, donde
/// lo que está en juego es si alguien puede recuperar su empresa, no se
/// repite.
sealed class ResultadoRecuperacion {}

/// Configurada o reconfigurada con éxito. [datos] trae la clave de
/// recuperación en claro: **la única vez** que existe legible. Quien
/// reciba esto tiene que mostrarla, exigir que se verifique y olvidarla.
class RecuperacionLista extends ResultadoRecuperacion {
  RecuperacionLista(this.datos);
  final RecuperacionConfigurada datos;
}

/// La frase actual no abre la configuración. No se ha cambiado nada.
class RecuperacionFraseIncorrecta extends ResultadoRecuperacion {}

/// La frase nueva es demasiado corta. Lleva el mínimo para que el mensaje
/// no repita el número en dos sitios.
class RecuperacionFraseDemasiadoCorta extends ResultadoRecuperacion {
  RecuperacionFraseDemasiadoCorta(this.longitudMinima);
  final int longitudMinima;
}

/// Se pidió cambiar algo que todavía no está configurado.
class RecuperacionNoConfigurada extends ResultadoRecuperacion {}

/// La frase quedó cambiada. No hay clave de recuperación que mostrar:
/// cambiar la frase no toca la otra puerta.
class RecuperacionFraseCambiada extends ResultadoRecuperacion {}

class RecuperacionNoAutorizada extends ResultadoRecuperacion {
  RecuperacionNoAutorizada(this.mensaje);
  final String mensaje;
}

class RecuperacionErrorInesperado extends ResultadoRecuperacion {
  RecuperacionErrorInesperado(this.mensaje);
  final String mensaje;
}
