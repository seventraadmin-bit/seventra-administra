// Etapa 4D — prueba de compatibilidad byte a byte con la referencia.
//
// RISEG ONE implementa el *framing* del wire format
// `AES-GCM-HKDF-STREAMING` de Tink sobre las primitivas de PointyCastle.
// Ni PointyCastle ni este archivo son Tink: por eso estas pruebas no se
// conforman con una ida y vuelta consigo mismas, que pasaría igual de
// bien con un formato inventado y silenciosamente incompatible.
//
// Los vectores de abajo los produjo **Tink Java 1.23.0**
// (`com.google.crypto.tink.subtle.AesGcmHkdfStreaming`) sobre Java
// 17.0.12, con `DerivedKeySize = 32`, `hkdf = HmacSha256` y
// `firstSegmentOffset = 0`. El generador vivió fuera del repositorio y
// Tink **no** es dependencia de RISEG ONE.
//
// Se usa `segmentSize = 128` para los casos frontera —el formato está
// parametrizado por ese tamaño, así que ejercita exactamente el mismo
// código con archivos de unos cientos de bytes— más un vector con los
// parámetros de producción (1 MiB) para comprobarlos también.
//
// Si un byte de un vector cambia, estas pruebas fallan. Ésa es toda su
// razón de ser.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/security/aes_gcm_hkdf_streaming.dart';

class VectorTink {
  const VectorTink({
    required this.nombre,
    required this.segmentSize,
    required this.textoPlanoBytes,
    required this.ikmHex,
    required this.aadHex,
    required this.cifradoHex,
  });

  final String nombre;
  final int segmentSize;
  final int textoPlanoBytes;
  final String ikmHex;
  final String aadHex;
  final String cifradoHex;
}

Uint8List _deHex(String hex) {
  final bytes = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return bytes;
}

String _aHex(Uint8List bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// El mismo texto plano determinista que usó el generador Java.
Uint8List _patron(int n) {
  final b = Uint8List(n);
  for (var i = 0; i < n; i++) {
    b[i] = (i * 31 + (i >> 8) * 17) & 0xFF;
  }
  return b;
}

const vectores = <VectorTink>[
  VectorTink(
    nombre: 'vacio',
    segmentSize: 128,
    textoPlanoBytes: 0,
    ikmHex: 'a0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebf',
    aadHex: '52495345472d34442d464958545552452d414144',
    cifradoHex:
        '281e04785a5164bf79eb0b16f2e9921166bd2dd57b1247cdb94ae1ffb064c11bed41b4a5890f6b9629f5ea92e86667ecc57278c846103f48',
  ),
  VectorTink(
    nombre: 'un_byte',
    segmentSize: 128,
    textoPlanoBytes: 1,
    ikmHex: 'a0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebf',
    aadHex: '52495345472d34442d464958545552452d414144',
    cifradoHex:
        '280ba533e72e7adf81bafe85260cfdbef69860e72a1360ca91775a73bcbd93fc56ad14dbde3f50b6fbbbb1c7ed7ce18ae08de164ae3990e238',
  ),
  VectorTink(
    nombre: 'cap0_menos_1',
    segmentSize: 128,
    textoPlanoBytes: 71,
    ikmHex: 'a0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebf',
    aadHex: '52495345472d34442d464958545552452d414144',
    cifradoHex:
        '28649da8cc2fd1e896f558c23632152c9fe737d37abd9e203e2a366712e0b566401af05430ae6ddf58679b34b1a960680b971bb58325aae4a3e44e9cd496ff1ec50c4cbd1848c02389188bf661ad6a181e8a4efd5abfe06a861c985fbf8fd890dee453553b34f81d009b7c0ad072808c1807455bebb8146af6762f087fd7b3',
  ),
  VectorTink(
    nombre: 'cap0_exacto',
    segmentSize: 128,
    textoPlanoBytes: 72,
    ikmHex: 'a0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebf',
    aadHex: '52495345472d34442d464958545552452d414144',
    cifradoHex:
        '28f7e5fd3b3c43193e7732a8265f7e8489edda420bb2fd4b4ef08e6fac8c5f37ae30735f16c61e17d5fb7fe7b4dffb1b3650e9d238c3b21739bed0282890fc2909872efe895b59130fc68e9e3d7da84cc5e1c3ad08f69e235a04ffb9ecb9abe02a67cfc937110ba3a0cd8ae40a62168eb860cea5b0b92aa6a93d76e96c03845f',
  ),
  VectorTink(
    nombre: 'cap0_mas_1',
    segmentSize: 128,
    textoPlanoBytes: 73,
    ikmHex: 'a0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebf',
    aadHex: '52495345472d34442d464958545552452d414144',
    cifradoHex:
        '28400f4dfe597ac40823cbc912a5f91454ddec5f9ddff4fc06762285b232d1e895abfacf04cc4618a25f32225110af693e000dbdeecdba7795f391e6d0f76e8f4614f5b24a483f9e34b1bf872309242622879bdaa583c8df05ee2b3747d09a50fe8916c9f096c909155b2e91b64984db4bf63698f2e7c24cb017c98d5fef5c0f002aacba30aa5b443e1d5fa230ba517050',
  ),
  VectorTink(
    nombre: 'dos_segmentos_exacto',
    segmentSize: 128,
    textoPlanoBytes: 184,
    ikmHex: 'a0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebf',
    aadHex: '52495345472d34442d464958545552452d414144',
    cifradoHex:
        '2838710e050c798c0d65f5ddda3b0d6c2ac154e1ea1e515dbd8e1f6770887b2d8c3fce4b521763e48d63ecc73ac76981b34d04536301e7b1b20ea70ba1cf482411fc16ada2b652edd4783cdd8695c731a6ed25612b1e99901ce0539944efc1dea3b9265a2748646c76bc1e7208ccf5798c71706bcc9f67e803f324276c79ff79d0fd00615234f63bf2f60521b99df7914cc6d10b7637ca9715b9a8c824489d52ba00c7c4e81876b370af2301fa19382e75aede3e720562c4d675dbfdb0daaccb6ebfd5da0218641c19bb16a653dddd8d1ecb2971e66081a0079685df59dd22b9709f21b48ee89de0e689af6ed4ad8a44b95977e181b553f04e72748baf4e999b',
  ),
  VectorTink(
    nombre: 'tres_segmentos',
    segmentSize: 128,
    textoPlanoBytes: 185,
    ikmHex: 'a0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebf',
    aadHex: '52495345472d34442d464958545552452d414144',
    cifradoHex:
        '2807222a19a732661308675a756497c59535da3023f09506ada66551a9ebd9736338549de986c8d2639bda7c8bfdab3414081806b434401fac8087f4d6ca31733cce3d238186abbea0d12e8c0dc3c642a9c33223e23242d998244495531bfef17dcb85c590984ddb062ec79064c63d4c10b998378e4cc6af30c567a303968b84235c2588a8571432e87c0f416206466efd85662810cb6bf6d66a411b35d18d0cae718c9993065c6baea02d48f994d7e99a1fba8987eca74f2520266820759a924fb093383fb9bcedbda0fbe55dab32e5e4f327fd2e99e63d0238eca1fd41cbd1c25b221f635d39f8b409c42b51b7609f31f1b72770da170da977b363bcdff448cb6df7920a82baae002fabe4e0cd9def40',
  ),
  VectorTink(
    nombre: 'aad_vacio',
    segmentSize: 128,
    textoPlanoBytes: 100,
    ikmHex: 'a0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebf',
    aadHex: '',
    cifradoHex:
        '284f8ecaef0d47f11e0b97125c4f07284231ff34e0e2bfb1333af18d282ea1f4b6c0f0ff74dadcae96d6d24999bcece8383d5c3df8f9e39acfccf8a479c970847cbe08f658556d274f72ace56ce6acee54bad850e1f6c39cdded6209973b6d459d810f805daa031e0a8341dc2ee275dc469ff77a688d50ce78ea6261aabbdab4b9807d0a8e7658e304e210f92ec5c930753ecebaeb10a3ca319a523151f1083ac1f5a9be23fde9d312eacb2d',
  ),
  VectorTink(
    nombre: 'produccion_1mib',
    segmentSize: 1048576,
    textoPlanoBytes: 100,
    ikmHex: 'a0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebf',
    aadHex: '52495345472d34442d464958545552452d414144',
    cifradoHex:
        '28d00e811d9d1e0dca7f1c419de4a0ae8833fcc676c2066a55083ec7bf041e76ab2de3f880050cf9525afebdfa4069bca89155043b894e65d0cf65e55cd2ecef4c353958214b93be93ee7a34ff8c9282764f8db0a4af3f86e7b34b275c0b0856a84d1d9427156652c97caed9c3eb12cc5a6c34d5a1039313fc2b5ff3bcc293053d32a36e7cc438e1c1adb703c2a57ddf87c1969483005bc255744e9d',
  ),
];

void main() {
  group('Compatibilidad byte a byte con Tink', () {
    for (final v in vectores) {
      test('${v.nombre}: descifrar el vector de referencia da el texto plano exacto', () {
        final motor = AesGcmHkdfStreaming(ikm: _deHex(v.ikmHex), segmentSize: v.segmentSize);

        final plano = motor.descifrar(cifrado: _deHex(v.cifradoHex), datosAsociados: _deHex(v.aadHex));

        expect(plano.length, v.textoPlanoBytes);
        expect(plano, equals(_patron(v.textoPlanoBytes)));
      });

      test('${v.nombre}: cifrar reproduce el vector byte a byte', () {
        final cifradoReferencia = _deHex(v.cifradoHex);
        final motor = AesGcmHkdfStreaming(ikm: _deHex(v.ikmHex), segmentSize: v.segmentSize);

        // El salt y el prefijo de nonce se toman de la propia cabecera
        // del vector: AES-GCM es determinista dados clave, IV, texto y
        // AAD, así que reinyectarlos convierte cada vector de descifrado
        // en un vector de cifrado completo, sin necesitar Tink aquí.
        final salt = Uint8List.sublistView(cifradoReferencia, 1, 33);
        final prefijoNonce = Uint8List.sublistView(cifradoReferencia, 33, 40);

        final nuestro = motor.cifrar(
          textoPlano: _patron(v.textoPlanoBytes),
          datosAsociados: _deHex(v.aadHex),
          salt: salt,
          prefijoNonce: prefijoNonce,
        );

        expect(_aHex(nuestro), equals(v.cifradoHex));
      });
    }

    test('el múltiplo exacto NO añade un segmento vacío al final', () {
      final v = vectores.firstWhere((x) => x.nombre == 'cap0_exacto');
      // 128 bytes de cifrado = exactamente un segmento. Si añadiéramos
      // un segmento final vacío, serían 128 + 16.
      expect(_deHex(v.cifradoHex).length, v.segmentSize);

      final dos = vectores.firstWhere((x) => x.nombre == 'dos_segmentos_exacto');
      expect(_deHex(dos.cifradoHex).length, 2 * dos.segmentSize);
    });

    test('la cabecera mide 40 bytes y declara su propia longitud', () {
      for (final v in vectores) {
        final cifrado = _deHex(v.cifradoHex);
        expect(cifrado[0], 40, reason: '${v.nombre}: primer byte = len(cabecera)');
        expect(AesGcmHkdfStreaming.longitudCabecera, 40);
      }
    });
  });

  group('Rechazos', () {
    final v = vectores.firstWhere((x) => x.nombre == 'tres_segmentos');
    AesGcmHkdfStreaming motor() => AesGcmHkdfStreaming(ikm: _deHex(v.ikmHex), segmentSize: v.segmentSize);
    Uint8List cifrado() => _deHex(v.cifradoHex);

    void esperarRechazo(Uint8List datos, {Uint8List? aad, String? porque}) {
      expect(
        () => motor().descifrar(cifrado: datos, datosAsociados: aad ?? _deHex(v.aadHex)),
        throwsA(isA<PayloadNoAutenticado>()),
        reason: porque,
      );
    }

    test('un bit cambiado en el primer segmento', () {
      final roto = cifrado()..[50] ^= 0x01;
      esperarRechazo(roto);
    });

    test('un bit cambiado en el último segmento', () {
      final roto = cifrado();
      roto[roto.length - 1] ^= 0x01;
      esperarRechazo(roto);
    });

    test('truncar el archivo: al último segmento le falta su marca', () {
      final entero = cifrado();
      esperarRechazo(
        Uint8List.sublistView(entero, 0, entero.length - 17),
        porque: 'el segmento que queda al final ya no es el marcado como último',
      );
    });

    test('añadir bytes después del final', () {
      final entero = cifrado();
      final mas = Uint8List(entero.length + 17)..setRange(0, entero.length, entero);
      esperarRechazo(mas);
    });

    test('reordenar dos segmentos', () {
      final entero = cifrado();
      final seg0 = Uint8List.sublistView(entero, 40, 128);
      final seg1 = Uint8List.sublistView(entero, 128, 256);
      final mezclado =
          Uint8List(entero.length)
            ..setRange(0, 40, entero)
            ..setRange(40, 40 + seg1.length, seg1)
            ..setRange(40 + seg1.length, 40 + seg1.length + seg0.length, seg0)
            ..setRange(256, entero.length, Uint8List.sublistView(entero, 256));
      esperarRechazo(mezclado, porque: 'el índice del segmento va dentro del IV');
    });

    test('duplicar un segmento', () {
      final entero = cifrado();
      final seg1 = Uint8List.sublistView(entero, 128, 256);
      final duplicado =
          Uint8List(entero.length)
            ..setRange(0, 128, entero)
            ..setRange(128, 256, seg1)
            ..setRange(256, entero.length, Uint8List.sublistView(entero, 256));
      duplicado.setRange(40, 128, Uint8List.sublistView(seg1, 0, 88));
      esperarRechazo(duplicado);
    });

    test('datos asociados distintos: cambia la clave derivada y nada autentica', () {
      esperarRechazo(cifrado(), aad: utf8.encode('otros-datos-asociados'));
    });

    test('DEK distinta', () {
      final otraClave = _deHex(v.ikmHex)..[0] ^= 0xFF;
      expect(
        () => AesGcmHkdfStreaming(
          ikm: otraClave,
          segmentSize: v.segmentSize,
        ).descifrar(cifrado: cifrado(), datosAsociados: _deHex(v.aadHex)),
        throwsA(isA<PayloadNoAutenticado>()),
      );
    });

    test('una cabecera con longitud inesperada', () {
      final roto = cifrado()..[0] = 24;
      esperarRechazo(roto);
    });
  });
}
