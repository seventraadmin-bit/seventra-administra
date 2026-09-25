import 'dart:math';
import 'dart:typed_data';

import 'clave_recuperacion.dart';
import 'configuracion_recuperacion.dart';
import 'kdf_portable.dart';
import 'sobre_portable.dart';

/// Lo que se entrega al terminar de configurar: la configuración a
/// persistir y **la única vez** que la clave de recuperación existe en
/// forma legible.
class RecuperacionConfigurada {
  const RecuperacionConfigurada({required this.configuracion, required this.claveRecuperacionTexto});

  final ConfiguracionRecuperacion configuracion;

  /// Para mostrar, imprimir y verificar **dentro de esta sesión**.
  /// Después se descarta: no se guarda en la base, ni en el Almacén de
  /// Credenciales, ni en preferencias, ni en un log, y no hay ninguna
  /// acción que pueda volver a mostrarla.
  final String claveRecuperacionTexto;
}

/// Configura la recuperación portable por primera vez (Etapa 4D).
///
/// Genera la clave maestra del conjunto y sus dos envolturas —frase y
/// clave de recuperación—, que desde ahora se copiarán tal cual en cada
/// respaldo. La frase no se guarda; se pedirá cada vez que haga falta
/// abrir la clave maestra. La clave de recuperación tampoco: se muestra
/// una vez, se exige verificarla, y se olvida.
class ConfigurarRecuperacionUseCase {
  ConfigurarRecuperacionUseCase({SobrePortable? sobre, Random? aleatorio, DateTime Function()? ahora})
    : _sobre = sobre ?? SobrePortable(aleatorio: aleatorio),
      _aleatorio = aleatorio ?? Random.secure(),
      _ahora = ahora ?? DateTime.now;

  final SobrePortable _sobre;
  final Random _aleatorio;
  final DateTime Function() _ahora;

  /// Longitud mínima de la frase. Se elige por **longitud**, no por
  /// composición: obligar a una mayúscula y un símbolo produce
  /// `Riseg2026!` y una falsa sensación de seguridad.
  static const longitudMinimaFrase = 12;

  RecuperacionConfigurada ejecutar({required String frase, ParametrosArgon2id? parametros}) {
    if (frase.trim().length < longitudMinimaFrase) {
      throw ArgumentError.value(frase.length, 'frase', 'necesita al menos $longitudMinimaFrase caracteres');
    }

    final backupSetId = _hexAleatorio(16);
    final mwk = _sobre.generarMwk();
    final claveRecuperacion = _sobre.generarClaveRecuperacion();
    final prefijo = ConfiguracionRecuperacion.prefijoAadConfiguracion(backupSetId);

    final configuracion = ConfiguracionRecuperacion(
      backupSetId: backupSetId,
      formatoVersion: ConfiguracionRecuperacion.formatoActual,
      envolturaFrase: _sobre.envolverConFrase(mwk: mwk, frase: frase, prefijoAad: prefijo, parametros: parametros),
      envolturaClaveRecuperacion: _sobre.envolverConClaveRecuperacion(
        mwk: mwk,
        claveRecuperacion: claveRecuperacion,
        prefijoAad: prefijo,
      ),
      claveRecuperacionGeneradaEn: _ahora(),
    );

    return RecuperacionConfigurada(
      configuracion: configuracion,
      claveRecuperacionTexto: ClaveRecuperacion.formatear(claveRecuperacion),
    );
  }

  /// Cambia la frase **sin recifrar nada**: la clave maestra no cambia,
  /// así que sólo se reenvuelve ella. Devuelve `null` si la frase actual
  /// no abre la configuración.
  ///
  /// Los respaldos ya escritos **siguen abriéndose con la frase
  /// anterior**: llevan su propia copia del bloque de recuperación, y un
  /// archivo que ya salió en un USB es una fotografía. La pantalla tiene
  /// que decirlo con esas palabras.
  ConfiguracionRecuperacion? cambiarFrase({
    required ConfiguracionRecuperacion actual,
    required String fraseActual,
    required String fraseNueva,
    ParametrosArgon2id? parametros,
  }) {
    if (fraseNueva.trim().length < longitudMinimaFrase) {
      throw ArgumentError.value(fraseNueva.length, 'fraseNueva', 'necesita al menos $longitudMinimaFrase caracteres');
    }
    final mwk = actual.abrirMwkConFrase(frase: fraseActual, sobre: _sobre);
    if (mwk == null) return null;

    final prefijo = ConfiguracionRecuperacion.prefijoAadConfiguracion(actual.backupSetId);
    return ConfiguracionRecuperacion(
      backupSetId: actual.backupSetId,
      formatoVersion: actual.formatoVersion,
      envolturaFrase: _sobre.envolverConFrase(mwk: mwk, frase: fraseNueva, prefijoAad: prefijo, parametros: parametros),
      // Intacta: cambiar la frase no toca la otra puerta.
      envolturaClaveRecuperacion: actual.envolturaClaveRecuperacion,
      claveRecuperacionGeneradaEn: actual.claveRecuperacionGeneradaEn,
    );
  }

  /// Genera una clave de recuperación nueva sobre la **misma** clave
  /// maestra. `null` si la frase no abre la configuración.
  ///
  /// Los respaldos anteriores conservan la clave con la que fueron
  /// creados; no hay forma de revocar copias que ya salieron.
  RecuperacionConfigurada? regenerarClaveRecuperacion({
    required ConfiguracionRecuperacion actual,
    required String frase,
  }) {
    final mwk = actual.abrirMwkConFrase(frase: frase, sobre: _sobre);
    if (mwk == null) return null;

    final nueva = _sobre.generarClaveRecuperacion();
    final prefijo = ConfiguracionRecuperacion.prefijoAadConfiguracion(actual.backupSetId);

    return RecuperacionConfigurada(
      configuracion: ConfiguracionRecuperacion(
        backupSetId: actual.backupSetId,
        formatoVersion: actual.formatoVersion,
        // Intacta: regenerar la clave de recuperación no toca la frase.
        envolturaFrase: actual.envolturaFrase,
        envolturaClaveRecuperacion: _sobre.envolverConClaveRecuperacion(
          mwk: mwk,
          claveRecuperacion: nueva,
          prefijoAad: prefijo,
        ),
        claveRecuperacionGeneradaEn: _ahora(),
      ),
      claveRecuperacionTexto: ClaveRecuperacion.formatear(nueva),
    );
  }

  String _hexAleatorio(int bytes) {
    return List<int>.generate(
      bytes,
      (_) => _aleatorio.nextInt(256),
    ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}

/// Utilidad de lectura para las pruebas y para la verificación del
/// asistente: comprobar que el usuario transcribió bien la clave sin
/// tener que guardarla.
Uint8List? interpretarClaveRecuperacion(String texto) => ClaveRecuperacion.interpretar(texto);
