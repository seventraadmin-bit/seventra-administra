import 'evaluador_instalacion.dart';

/// Quién puede restaurar un paquete portable, y cuándo (Etapa 4D).
///
/// Es la única compuerta del proyecto que puede abrirse **sin sesión**, y
/// por eso vive en su propio archivo con su propia justificación en vez de
/// esconderse dentro de un provider.
///
/// El problema es real: cuando la computadora de la empresa se destruye, en
/// la nueva no hay ningún usuario que pudiera autorizar nada. Exigir
/// Maestro ahí convertiría el respaldo en un adorno. Pero abrir la puerta
/// sin más sería peor: cualquiera con un USB podría reemplazar la base de
/// una instalación en funcionamiento.
///
/// La pregunta correcta no es "¿hay usuarios?" sino **"¿hay aquí algo que
/// una restauración pudiera destruir?"**. Ésa la responde
/// [EvaluadorInstalacion], y sólo su respuesta más rotunda
/// —[EstadoInstalacion.vaciaSegura]— abre la puerta sin credencial.
/// [EstadoInstalacion.indeterminada] **nunca** la abre: cuando no se puede
/// saber qué hay en el disco, se asume que hay algo.
enum PuertaRestauracionPortable {
  /// Instalación sin nada que perder: se puede restaurar sin sesión.
  /// Es el camino de "la computadora se destruyó y ésta es nueva".
  sinCredencial,

  /// Hay datos aquí. Restaurar los reemplaza, así que hace falta el
  /// Usuario Maestro **además** de la credencial del paquete.
  exigeMaestro,
}

/// Decide qué puerta corresponde al estado de esta instalación.
PuertaRestauracionPortable puertaSegunInstalacion(EstadoInstalacion estado) {
  return switch (estado) {
    EstadoInstalacion.vaciaSegura => PuertaRestauracionPortable.sinCredencial,
    // Las dos restantes se tratan igual a propósito, y no con un `_`:
    // escribirlas se encarga de que añadir un estado nuevo al enum rompa
    // la compilación aquí, donde alguien tiene que pensarlo, en vez de
    // caer silenciosamente en el caso permisivo.
    EstadoInstalacion.existente => PuertaRestauracionPortable.exigeMaestro,
    EstadoInstalacion.indeterminada => PuertaRestauracionPortable.exigeMaestro,
  };
}
