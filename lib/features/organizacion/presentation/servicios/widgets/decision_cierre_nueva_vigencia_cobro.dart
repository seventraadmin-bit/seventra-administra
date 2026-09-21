import 'package:riseg_one/features/organizacion/domain/usecases/cambiar_vigencia_configuracion_cobro_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/configuracion_cobro_errors.dart';

/// Qué hacer con el diálogo de "Nueva vigencia" según lo que devolvió el
/// caso de uso.
class DecisionCierreNuevaVigenciaCobro {
  const DecisionCierreNuevaVigenciaCobro({
    required this.cierraElDialogo,
    this.errores = const [],
    this.errorGeneral,
  });

  /// `false` mantiene el formulario abierto con toda la captura intacta.
  final bool cierraElDialogo;

  /// Errores por campo, para el `errorText` de cada control.
  final List<ErrorConfiguracionCobro> errores;

  /// Error que no pertenece a ningún campo — se muestra arriba del
  /// formulario.
  final String? errorGeneral;
}

/// Regla de UX establecida en la etapa de Usuarios y reafirmada aquí
/// tras el caso MORGAN ATLACOMULCO: **nada que el usuario pueda
/// corregir dentro del formulario cierra el diálogo**.
///
/// Antes, sólo `ErroresValidacion` mantenía el diálogo abierto; un fallo
/// al persistir (`ErrorInesperado`) lo cerraba y tiraba toda la captura,
/// dejando un snackbar genérico ("No se pudo registrar la nueva
/// vigencia. Intenta de nuevo.") sin decir qué había pasado ni cómo
/// recuperar lo escrito.
///
/// Se cierra únicamente en los dos casos en que insistir en el
/// formulario no puede llevar a nada: el Servicio está terminado, o la
/// Configuración ya no existe.
///
/// Es una función pura a propósito — es la línea que tenía el bug, y
/// una decisión de este peso no debe quedar sólo dentro de un `onConfirm`
/// imposible de probar sin montar el expediente completo.
DecisionCierreNuevaVigenciaCobro decidirCierreNuevaVigenciaCobro(
  CambiarVigenciaConfiguracionCobroResultado? resultado, {
  required String mensajeReglasEtapas,
}) {
  switch (resultado) {
    case null:
      // El usuario canceló (o no confirmó una vigencia retroactiva).
      return const DecisionCierreNuevaVigenciaCobro(cierraElDialogo: false);
    case CambiarVigenciaConfiguracionCobroErroresValidacion(:final errores, :final erroresEtapas):
      return DecisionCierreNuevaVigenciaCobro(
        cierraElDialogo: false,
        errores: errores,
        // Las reglas de las etapas no tienen un campo propio del
        // formulario donde colgarse: van al error general, ya no a un
        // snackbar que se iba junto con el diálogo.
        errorGeneral: erroresEtapas.isEmpty ? null : mensajeReglasEtapas,
      );
    case CambiarVigenciaConfiguracionCobroErrorInesperado(:final mensaje):
      return DecisionCierreNuevaVigenciaCobro(cierraElDialogo: false, errorGeneral: mensaje);
    case CambiarVigenciaConfiguracionCobroExitoso():
    case CambiarVigenciaConfiguracionCobroServicioNoDisponible():
    case CambiarVigenciaConfiguracionCobroNoExiste():
      return const DecisionCierreNuevaVigenciaCobro(cierraElDialogo: true);
  }
}
