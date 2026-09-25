import 'dart:io';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// Cifrado autenticado por segmentos del **wire format
/// `AES-GCM-HKDF-STREAMING` de Tink** (Etapa 4D).
///
/// **Qué es y qué no es.** Esto NO es Tink, y PointyCastle tampoco lo
/// es: PointyCastle aporta las primitivas (AES-GCM, HKDF-SHA256) y este
/// archivo implementa el *framing* que Tink documenta de forma
/// normativa. Se eligió seguir un formato publicado en vez de inventar
/// uno propio porque existen implementaciones de referencia contra las
/// que contrastar byte a byte — y eso es justo lo que hacen sus
/// pruebas, con vectores generados por Tink Java.
///
/// Formato, tal como lo define Tink:
///
/// ```
/// Cabecera := len(Cabecera) [1 byte] ‖ Salt [32] ‖ PrefijoNonce [7]   → 40 bytes
/// ClaveDeSegmento := HKDF-SHA256(ikm: DEK, salt: Salt, info: datosAsociados, 32)
/// IV_i := PrefijoNonce [7] ‖ i [4, big-endian] ‖ marcaFinal [1]
/// marcaFinal := 0x01 sólo en el último segmento; 0x00 en el resto
/// ```
///
/// Dos detalles que parecen menores y no lo son:
///
///  * **Los datos asociados entran como `info` del HKDF**, no como AAD
///    de cada llamada a GCM (el AAD por segmento va vacío). Cambiar un
///    solo byte de esos datos produce otra clave de segmento, así que
///    **ningún** segmento autentica. Es el mecanismo por el que la
///    cabecera pública del contenedor queda atada al contenido sin
///    necesidad de una firma aparte.
///  * **El primer segmento es más corto**, porque comparte su espacio
///    con la cabecera. Olvidarlo produce un stream que se descifra a sí
///    mismo pero que ninguna otra implementación puede leer.
class AesGcmHkdfStreaming {
  const AesGcmHkdfStreaming({required this.ikm, required this.segmentSize})
    : assert(segmentSize > longitudClaveDerivada + 24, 'segmentSize demasiado pequeño para el formato');

  /// Material de clave de entrada — la DEK del paquete. Nunca se usa
  /// directamente para cifrar: sólo alimenta al HKDF.
  final Uint8List ikm;

  /// `CiphertextSegmentSize`: tamaño de cada segmento **ya cifrado**,
  /// incluida su etiqueta. En producción, 1 MiB.
  final int segmentSize;

  static const longitudClaveDerivada = 32;
  static const longitudSalt = longitudClaveDerivada;
  static const longitudPrefijoNonce = 7;
  static const longitudEtiqueta = 16;

  /// 1 + 32 + 7 = 40.
  static const longitudCabecera = 1 + longitudSalt + longitudPrefijoNonce;

  /// Texto plano que cabe en el primer segmento — descontando la
  /// cabecera, que viaja dentro del mismo segmento.
  int get capacidadPrimerSegmento => segmentSize - longitudCabecera - longitudEtiqueta;

  /// Texto plano que cabe en cualquier segmento posterior.
  int get capacidadSegmento => segmentSize - longitudEtiqueta;

  /// Cifra [textoPlano] completo en memoria.
  ///
  /// [salt] y [prefijoNonce] se reciben para poder reproducir un vector
  /// de referencia byte a byte; en producción los genera quien llama,
  /// con un CSPRNG, y nunca se repiten para una misma DEK.
  Uint8List cifrar({
    required Uint8List textoPlano,
    required Uint8List datosAsociados,
    required Uint8List salt,
    required Uint8List prefijoNonce,
  }) {
    if (salt.length != longitudSalt) {
      throw ArgumentError.value(salt.length, 'salt', 'debe medir $longitudSalt bytes');
    }
    if (prefijoNonce.length != longitudPrefijoNonce) {
      throw ArgumentError.value(prefijoNonce.length, 'prefijoNonce', 'debe medir $longitudPrefijoNonce bytes');
    }

    final clave = _derivarClave(salt: salt, datosAsociados: datosAsociados);
    final trozos = _repartirTextoPlano(textoPlano.length);
    final salida =
        BytesBuilder(copy: false)
          ..addByte(longitudCabecera)
          ..add(salt)
          ..add(prefijoNonce);

    for (var i = 0; i < trozos.length; i++) {
      final (desde, hasta) = trozos[i];
      salida.add(
        _procesarSegmento(
          clave: clave,
          prefijoNonce: prefijoNonce,
          indice: i,
          esUltimo: i == trozos.length - 1,
          datos: Uint8List.sublistView(textoPlano, desde, hasta),
          cifrando: true,
        ),
      );
    }
    return salida.toBytes();
  }

  /// Descifra y **autentica** un stream completo.
  ///
  /// Lanza [PayloadNoAutenticado] ante cualquier alteración: un byte
  /// cambiado, segmentos reordenados o duplicados, un archivo truncado
  /// —al que le faltaría la marca de último segmento— o datos asociados
  /// distintos de los del cifrado.
  Uint8List descifrar({required Uint8List cifrado, required Uint8List datosAsociados}) {
    if (cifrado.length < longitudCabecera + longitudEtiqueta) {
      throw const PayloadNoAutenticado('el stream es más corto que su cabecera');
    }
    if (cifrado[0] != longitudCabecera) {
      throw const PayloadNoAutenticado('cabecera con longitud inesperada');
    }

    final salt = Uint8List.sublistView(cifrado, 1, 1 + longitudSalt);
    final prefijoNonce = Uint8List.sublistView(cifrado, 1 + longitudSalt, longitudCabecera);
    final clave = _derivarClave(salt: salt, datosAsociados: datosAsociados);

    final trozos = _repartirCifrado(cifrado.length);
    final salida = BytesBuilder(copy: false);
    for (var i = 0; i < trozos.length; i++) {
      final (desde, hasta) = trozos[i];
      salida.add(
        _procesarSegmento(
          clave: clave,
          prefijoNonce: prefijoNonce,
          indice: i,
          esUltimo: i == trozos.length - 1,
          datos: Uint8List.sublistView(cifrado, desde, hasta),
          cifrando: false,
        ),
      );
    }
    return salida.toBytes();
  }

  /// `HKDF-SHA256(ikm, salt, info)`, donde **info son los datos
  /// asociados**. Es la parte del formato que ata la cabecera pública
  /// del contenedor a cada segmento.
  Uint8List _derivarClave({required Uint8List salt, required Uint8List datosAsociados}) {
    final hkdf = HKDFKeyDerivator(SHA256Digest())
      ..init(HkdfParameters(ikm, longitudClaveDerivada, salt, datosAsociados));
    final clave = Uint8List(longitudClaveDerivada);
    hkdf.deriveKey(Uint8List(0), 0, clave, 0);
    return clave;
  }

  /// Un segmento, cifrado o descifrado. El AAD de GCM va **vacío**: los
  /// datos asociados ya actuaron en la derivación de la clave.
  Uint8List _procesarSegmento({
    required Uint8List clave,
    required Uint8List prefijoNonce,
    required int indice,
    required bool esUltimo,
    required Uint8List datos,
    required bool cifrando,
  }) {
    final iv =
        Uint8List(12)
          ..setRange(0, longitudPrefijoNonce, prefijoNonce)
          ..buffer.asByteData().setUint32(longitudPrefijoNonce, indice) // big-endian
          ..[11] = esUltimo ? 0x01 : 0x00;

    final gcm = GCMBlockCipher(AESEngine())
      ..init(cifrando, AEADParameters(KeyParameter(clave), longitudEtiqueta * 8, iv, Uint8List(0)));
    try {
      return gcm.process(datos);
    } on InvalidCipherTextException {
      throw const PayloadNoAutenticado('un segmento no autentica');
    }
  }

  /// Cifra [origen] hacia [destino], **un segmento a la vez**.
  ///
  /// Existe porque un respaldo puede pesar gigabytes y cargarlo en RAM
  /// no es una opción. La memoria usada es del orden del segmento (1 MiB
  /// en producción), sin importar el tamaño del archivo.
  ///
  /// [destino] debe estar ya posicionado donde empieza el payload — en
  /// un `.risegbkp`, justo después de los 8192 bytes de cabecera.
  Future<void> cifrarArchivoHacia({
    required File origen,
    required RandomAccessFile destino,
    required Uint8List datosAsociados,
    required Uint8List salt,
    required Uint8List prefijoNonce,
  }) async {
    final clave = _derivarClave(salt: salt, datosAsociados: datosAsociados);
    await destino.writeFrom(
      Uint8List(longitudCabecera)
        ..[0] = longitudCabecera
        ..setRange(1, 1 + longitudSalt, salt)
        ..setRange(1 + longitudSalt, longitudCabecera, prefijoNonce),
    );

    final entrada = await origen.open();
    try {
      final total = await entrada.length();
      var leidos = 0;
      var indice = 0;
      // El primer segmento es más corto: comparte su espacio con la
      // cabecera. Olvidarlo produce un stream que se lee a sí mismo y
      // que ninguna otra implementación puede abrir.
      var capacidad = capacidadPrimerSegmento;

      // Un texto plano vacío NO se salta el bucle: el formato exige un
      // segmento final que autentique "aquí no había nada".
      do {
        final aLeer = (total - leidos) < capacidad ? total - leidos : capacidad;
        final trozo = await entrada.read(aLeer);
        leidos += trozo.length;
        await destino.writeFrom(
          _procesarSegmento(
            clave: clave,
            prefijoNonce: prefijoNonce,
            indice: indice,
            esUltimo: leidos >= total,
            datos: trozo,
            cifrando: true,
          ),
        );
        indice++;
        capacidad = capacidadSegmento;
      } while (leidos < total);
    } finally {
      await entrada.close();
    }
  }

  /// Descifra y autentica el payload leyendo de [origen], que debe estar
  /// posicionado en su primer byte.
  ///
  /// Con [destino] en `null` **autentica sin escribir nada**: es la
  /// verificación completa, que recorre todo el paquete para poder decir
  /// "verificado" sin dejar una copia descifrada en disco.
  Future<void> descifrarArchivoHacia({
    required RandomAccessFile origen,
    required int payloadBytes,
    required Uint8List datosAsociados,
    RandomAccessFile? destino,
  }) async {
    if (payloadBytes < longitudCabecera + longitudEtiqueta) {
      throw const PayloadNoAutenticado('el payload es más corto que su cabecera');
    }
    final cabecera = await origen.read(longitudCabecera);
    if (cabecera.length != longitudCabecera || cabecera[0] != longitudCabecera) {
      throw const PayloadNoAutenticado('cabecera con longitud inesperada');
    }
    final salt = Uint8List.sublistView(cabecera, 1, 1 + longitudSalt);
    final prefijoNonce = Uint8List.sublistView(cabecera, 1 + longitudSalt, longitudCabecera);
    final clave = _derivarClave(salt: salt, datosAsociados: datosAsociados);

    var restante = payloadBytes - longitudCabecera;
    var indice = 0;
    var capacidad = segmentSize - longitudCabecera;
    while (restante > 0) {
      final aLeer = restante < capacidad ? restante : capacidad;
      final trozo = await origen.read(aLeer);
      if (trozo.length != aLeer) throw const PayloadNoAutenticado('el payload acaba antes de lo declarado');
      restante -= trozo.length;

      final plano = _procesarSegmento(
        clave: clave,
        prefijoNonce: prefijoNonce,
        indice: indice,
        esUltimo: restante == 0,
        datos: trozo,
        cifrando: false,
      );
      if (destino != null) await destino.writeFrom(plano);
      indice++;
      capacidad = segmentSize;
    }
  }

  /// Reparto del texto plano en segmentos.
  ///
  /// El formato exige que todo segmento anterior al último vaya lleno, y
  /// que ninguno salvo el primero pueda quedar vacío. De ahí sale una
  /// consecuencia que conviene tener presente: cuando el texto plano
  /// llena exactamente los segmentos, **no se añade un segmento final
  /// vacío** — el último lleno es el que lleva la marca.
  List<(int, int)> _repartirTextoPlano(int longitud) {
    if (longitud <= capacidadPrimerSegmento) return [(0, longitud)];

    final trozos = <(int, int)>[(0, capacidadPrimerSegmento)];
    var cursor = capacidadPrimerSegmento;
    while (cursor < longitud) {
      final fin = (cursor + capacidadSegmento) < longitud ? cursor + capacidadSegmento : longitud;
      trozos.add((cursor, fin));
      cursor = fin;
    }
    return trozos;
  }

  /// Reparto inverso: dónde empieza y acaba cada segmento **cifrado**.
  /// El primero es más corto porque comparte su segmento con la cabecera.
  List<(int, int)> _repartirCifrado(int longitudTotal) {
    final trozos = <(int, int)>[];
    var cursor = longitudCabecera;
    var capacidad = segmentSize - longitudCabecera;
    while (cursor < longitudTotal) {
      final fin = (cursor + capacidad) < longitudTotal ? cursor + capacidad : longitudTotal;
      trozos.add((cursor, fin));
      cursor = fin;
      capacidad = segmentSize;
    }
    // Un stream cuyo texto plano era vacío sigue teniendo un segmento:
    // la etiqueta de 16 bytes que autentica "aquí no había nada".
    if (trozos.isEmpty) throw const PayloadNoAutenticado('el stream no tiene segmentos');
    return trozos;
  }
}

/// El contenido no es el que se cifró, o la credencial no corresponde.
///
/// Deliberadamente **no distingue** entre "alterado", "truncado" y
/// "datos asociados incorrectos": quien manipula un paquete no debe
/// recibir pistas sobre qué comprobación falló. La pantalla traduce
/// esto a una sola frase humana.
class PayloadNoAutenticado implements Exception {
  const PayloadNoAutenticado(this.detalle);

  /// Para registro técnico, nunca para mostrarse tal cual.
  final String detalle;

  @override
  String toString() => 'PayloadNoAutenticado($detalle)';
}
