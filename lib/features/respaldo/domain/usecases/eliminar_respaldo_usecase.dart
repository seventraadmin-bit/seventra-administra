import 'dart:io';

sealed class ResultadoEliminarRespaldo {}

class RespaldoEliminado extends ResultadoEliminarRespaldo {}

class RespaldoNoEncontrado extends ResultadoEliminarRespaldo {}

/// El archivo es el respaldo preventivo de una restauración que todavía
/// no se ha aplicado — es la única red que tiene esa operación, y
/// borrarlo la dejaría sin vuelta atrás.
class RespaldoProtegidoPorRestauracionPendiente extends ResultadoEliminarRespaldo {}

class EliminarRespaldoErrorInesperado extends ResultadoEliminarRespaldo {
  EliminarRespaldoErrorInesperado(this.detalle);
  final String detalle;
}

/// Borra un `.zip` de respaldo del disco.
///
/// Sólo eso: **nunca** toca la base de datos, los adjuntos ni otro
/// respaldo. No hay papelera propia — el archivo se borra, y la
/// confirmación de la pantalla es toda la protección que necesita una
/// acción sobre un archivo que el usuario mismo creó.
class EliminarRespaldoUseCase {
  EliminarRespaldoUseCase({required String restorePendingMarkerFile})
    : _restorePendingMarkerFile = restorePendingMarkerFile;

  final String _restorePendingMarkerFile;

  Future<ResultadoEliminarRespaldo> ejecutar({required String rutaZip, required bool esPreventivo}) async {
    // Mientras haya una restauración a medias, su preventivo es
    // intocable: es el estado al que se vuelve si algo sale mal.
    if (esPreventivo && File(_restorePendingMarkerFile).existsSync()) {
      return RespaldoProtegidoPorRestauracionPendiente();
    }

    final archivo = File(rutaZip);
    if (!archivo.existsSync()) return RespaldoNoEncontrado();

    try {
      await archivo.delete();
      return RespaldoEliminado();
    } catch (e) {
      return EliminarRespaldoErrorInesperado(e.toString());
    }
  }
}
