import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// La clave de recuperación: 160 bits que una persona tiene que poder
/// copiar a mano desde una hoja de papel, años después, sin RISEG ONE
/// delante (Etapa 4D).
///
/// **Codificación.** Base32 de Crockford — alfabeto de 32 símbolos
/// **sin I, L, O ni U**, diseñado precisamente para que un humano lo
/// transcriba. 160 bits caben en 32 caracteres exactos, que agrupan
/// limpio en 8 grupos de 4. Los 160 bits no aportan seguridad sobre
/// 128: aportan que la agrupación salga entera.
///
/// **Checksum.** 10 bits tomados de `SHA-256(bytes)`, en 2 caracteres
/// más. **No es un mecanismo criptográfico** y no se le puede pedir lo
/// que no da: un error aleatorio de transcripción pasa inadvertido con
/// probabilidad **aproximada de 1/1024**, y no hay garantía de detectar
/// todo error de un solo carácter ni toda transposición — eso exigiría
/// un código diseñado para ello, no un hash truncado. Sirve para una
/// cosa concreta: distinguir *"la escribiste mal"* de *"esa clave no
/// abre este paquete"* antes de gastar un KDF. La verificación de
/// verdad la hace el AEAD, que rechaza una clave incorrecta con
/// certeza.
///
/// `RISEG-` es presentación, no dato: se descarta al normalizar.
abstract final class ClaveRecuperacion {
  /// Alfabeto de Crockford, en orden de valor 0..31.
  static const alfabeto = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

  static const longitudBytes = 20; // 160 bits
  static const caracteresDatos = 32; // 160 / 5
  static const caracteresChecksum = 2; // 10 bits
  static const caracteresTotales = caracteresDatos + caracteresChecksum;

  /// Prefijo que se muestra y se imprime, nunca parte del secreto.
  static const prefijoPresentacion = 'RISEG';

  /// Texto listo para imprimir: `RISEG-XXXX-XXXX-…-XX`.
  static String formatear(Uint8List bytes) {
    _exigirLongitud(bytes);
    final cuerpo = _codificar(bytes) + _checksum(bytes);
    final grupos = <String>[];
    for (var i = 0; i < caracteresDatos; i += 4) {
      grupos.add(cuerpo.substring(i, i + 4));
    }
    grupos.add(cuerpo.substring(caracteresDatos));
    return '$prefijoPresentacion-${grupos.join('-')}';
  }

  /// Los 20 bytes reales a partir de lo que el usuario haya tecleado.
  ///
  /// Tolera lo que una persona hace de verdad: minúsculas, espacios,
  /// saltos de línea, guiones de más o de menos, el prefijo puesto o
  /// quitado, y las confusiones clásicas `I`/`l` → `1` y `O` → `0`.
  /// Devuelve `null` —nunca lanza— si el texto no puede ser una clave:
  /// quien llama traduce eso a "está mal escrita".
  static Uint8List? interpretar(String entrada) {
    final normalizado = _normalizar(entrada);
    if (normalizado.length != caracteresTotales) return null;

    final datos = normalizado.substring(0, caracteresDatos);
    final checksum = normalizado.substring(caracteresDatos);

    final bytes = _decodificar(datos);
    if (bytes == null) return null;
    if (_checksum(bytes) != checksum) return null;
    return bytes;
  }

  /// Mayúsculas, sin separadores, sin prefijo, con las confusiones
  /// habituales resueltas. Cualquier carácter ajeno al alfabeto
  /// sobrevive a propósito hasta [_decodificar], que lo rechaza.
  static String _normalizar(String entrada) {
    var limpio = entrada.toUpperCase().replaceAll(RegExp(r'[^0-9A-Z]'), '');

    // El prefijo se descarta ANTES de resolver las confusiones de
    // caracteres, y el orden no es casual: `RISEG` lleva una `I`, así
    // que mapear primero lo convertiría en `R1SEG` y dejaría de
    // reconocerse. Se comprueba la longitud para no comerse cinco
    // caracteres de una clave que, por azar, empiece igual.
    if (limpio.startsWith(prefijoPresentacion) && limpio.length > caracteresTotales) {
      limpio = limpio.substring(prefijoPresentacion.length);
    }

    return limpio.replaceAll('I', '1').replaceAll('L', '1').replaceAll('O', '0');
  }

  static String _codificar(Uint8List bytes) {
    final salida = StringBuffer();
    var acumulador = 0;
    var bits = 0;
    for (final byte in bytes) {
      acumulador = (acumulador << 8) | byte;
      bits += 8;
      while (bits >= 5) {
        bits -= 5;
        salida.write(alfabeto[(acumulador >> bits) & 0x1F]);
      }
    }
    if (bits > 0) salida.write(alfabeto[(acumulador << (5 - bits)) & 0x1F]);
    return salida.toString();
  }

  static Uint8List? _decodificar(String texto) {
    var acumulador = 0;
    var bits = 0;
    final salida = <int>[];
    for (final caracter in texto.split('')) {
      final valor = alfabeto.indexOf(caracter);
      if (valor < 0) return null; // carácter fuera del alfabeto
      acumulador = (acumulador << 5) | valor;
      bits += 5;
      if (bits >= 8) {
        bits -= 8;
        salida.add((acumulador >> bits) & 0xFF);
      }
    }
    if (salida.length != longitudBytes) return null;
    return Uint8List.fromList(salida);
  }

  /// Los 10 bits altos de `SHA-256(bytes)`, en dos caracteres.
  static String _checksum(Uint8List bytes) {
    final resumen = sha256.convert(bytes).bytes;
    final valor = ((resumen[0] << 2) | (resumen[1] >> 6)) & 0x3FF;
    return '${alfabeto[(valor >> 5) & 0x1F]}${alfabeto[valor & 0x1F]}';
  }

  static void _exigirLongitud(Uint8List bytes) {
    if (bytes.length != longitudBytes) {
      throw ArgumentError.value(bytes.length, 'bytes', 'la clave de recuperación mide $longitudBytes bytes');
    }
  }
}
