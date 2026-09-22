import 'dart:async';

import 'package:flutter/services.dart';

/// Frontera mínima sobre el portapapeles del sistema, para poder probar la
/// política de limpieza sin canales de plataforma — mismo criterio que
/// `AlmacenClaveCifrado` con el Almacén de Credenciales de Windows.
abstract class AccesoPortapapeles {
  Future<void> escribir(String texto);
  Future<String?> leer();
}

class AccesoPortapapelesSistema implements AccesoPortapapeles {
  const AccesoPortapapelesSistema();

  @override
  Future<void> escribir(String texto) => Clipboard.setData(ClipboardData(text: texto));

  @override
  Future<String?> leer() async => (await Clipboard.getData(Clipboard.kTextPlain))?.text;
}

/// Copia un valor sensible al portapapeles y lo retira pasado un tiempo,
/// **sólo si nadie lo sustituyó entretanto**.
///
/// La comparación previa no es un detalle: sin ella, RISEG ONE borraría lo
/// que la persona copiara después —un número de cuenta, un texto cualquiera—
/// simplemente porque venció un temporizador suyo. Destruir el portapapeles
/// ajeno es peor que dejar una contraseña un minuto de más, así que ante
/// cualquier duda no se toca nada.
///
/// Un solo temporizador vivo a la vez: copiar una segunda contraseña cancela
/// la limpieza pendiente de la primera y abre su propia ventana. El
/// temporizador de A nunca puede borrar a B.
class PortapapelesSensible {
  PortapapelesSensible({AccesoPortapapeles? acceso}) : _acceso = acceso ?? const AccesoPortapapelesSistema();

  final AccesoPortapapeles _acceso;

  Timer? _limpiezaPendiente;
  String? _valorColocado;

  /// Cuánto vive el valor antes de intentar retirarlo.
  static const ventanaPredeterminada = Duration(seconds: 60);

  Future<void> copiarTemporal(String valor, {Duration ventana = ventanaPredeterminada}) async {
    await _acceso.escribir(valor);
    // Antes de programar la nueva: si quedaba una pendiente, muere aquí.
    _limpiezaPendiente?.cancel();
    _valorColocado = valor;
    _limpiezaPendiente = Timer(ventana, () => limpiarSiSigueSiendoNuestro());
  }

  /// Público para que las pruebas puedan adelantar el vencimiento sin
  /// esperar un minuto real.
  Future<void> limpiarSiSigueSiendoNuestro() async {
    final esperado = _valorColocado;
    _limpiezaPendiente = null;
    _valorColocado = null;
    if (esperado == null) return;

    final actual = await _acceso.leer();
    // Cualquier diferencia —otro texto, vacío, o un portapapeles que no se
    // puede leer— significa NO TOCAR.
    if (actual != esperado) return;

    await _acceso.escribir('');
  }

  /// Cancela la limpieza pendiente sin tocar el portapapeles. Se usa al
  /// desmontar: dejar el temporizador vivo podría borrar, minutos después,
  /// algo que ya no es nuestro.
  void cancelar() {
    _limpiezaPendiente?.cancel();
    _limpiezaPendiente = null;
    _valorColocado = null;
  }
}
