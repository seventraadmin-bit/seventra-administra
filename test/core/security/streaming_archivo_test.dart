// Etapa 4D — el mismo formato, pero sin cargar el archivo en memoria.
//
// Un respaldo puede pesar gigabytes. La variante de streaming existe
// para que la memoria usada sea del orden del segmento, y estas pruebas
// exigen lo único que importa: que produzca **exactamente los mismos
// bytes** que el camino en memoria, que a su vez ya está atado a los
// vectores de Tink. Si las dos rutas se separan, un paquete creado en
// streaming dejaría de poder abrirse.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:riseg_one/core/security/aes_gcm_hkdf_streaming.dart';

Uint8List _patron(int n) {
  final b = Uint8List(n);
  for (var i = 0; i < n; i++) {
    b[i] = (i * 31 + (i >> 8) * 17) & 0xFF;
  }
  return b;
}

void main() {
  late Directory raiz;

  setUp(() => raiz = Directory.systemTemp.createTempSync('riseg_stream_'));
  tearDown(() {
    try {
      raiz.deleteSync(recursive: true);
    } on FileSystemException {
      // En Windows un handle recién cerrado puede tardar un instante.
    }
  });

  final salt = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));
  final prefijoNonce = Uint8List.fromList([9, 8, 7, 6, 5, 4, 3]);
  final ikm = Uint8List.fromList(List<int>.generate(32, (i) => 0xA0 + i));
  final aad = Uint8List.fromList('RISEG-4D-STREAM'.codeUnits);

  /// Cifra por streaming y devuelve el archivo resultante.
  Future<File> cifrarPorStreaming(Uint8List textoPlano, int segmentSize) async {
    final origen = File(p.join(raiz.path, 'plano.bin'))..writeAsBytesSync(textoPlano);
    final destino = File(p.join(raiz.path, 'cifrado.bin'));
    final raf = await destino.open(mode: FileMode.write);
    try {
      await AesGcmHkdfStreaming(
        ikm: ikm,
        segmentSize: segmentSize,
      ).cifrarArchivoHacia(origen: origen, destino: raf, datosAsociados: aad, salt: salt, prefijoNonce: prefijoNonce);
    } finally {
      await raf.close();
    }
    return destino;
  }

  group('Streaming y memoria producen los mismos bytes', () {
    const tamanos = [0, 1, 71, 72, 73, 184, 185, 500, 1000];

    for (final segmentSize in [128, 256]) {
      test('segmentSize $segmentSize: idénticos en todos los tamaños frontera', () async {
        final motor = AesGcmHkdfStreaming(ikm: ikm, segmentSize: segmentSize);

        for (final n in tamanos) {
          final enMemoria = motor.cifrar(
            textoPlano: _patron(n),
            datosAsociados: aad,
            salt: salt,
            prefijoNonce: prefijoNonce,
          );
          final porStreaming = await (await cifrarPorStreaming(_patron(n), segmentSize)).readAsBytes();

          expect(porStreaming, equals(enMemoria), reason: 'con $n bytes y segmentos de $segmentSize');
        }
      });
    }

    test('con los parámetros de producción (1 MiB) y varios segmentos', () async {
      const segmentSize = 1024 * 1024;
      final n = segmentSize + 1234; // fuerza dos segmentos
      final motor = AesGcmHkdfStreaming(ikm: ikm, segmentSize: segmentSize);

      final enMemoria = motor.cifrar(
        textoPlano: _patron(n),
        datosAsociados: aad,
        salt: salt,
        prefijoNonce: prefijoNonce,
      );
      final porStreaming = await (await cifrarPorStreaming(_patron(n), segmentSize)).readAsBytes();

      expect(porStreaming.length, enMemoria.length);
      expect(porStreaming, equals(enMemoria));
    });
  });

  group('Descifrado por streaming', () {
    Future<Uint8List> descifrarPorStreaming(File cifrado, int segmentSize, {Uint8List? otroAad}) async {
      final salida = File(p.join(raiz.path, 'salida.bin'));
      final entrada = await cifrado.open();
      final destino = await salida.open(mode: FileMode.write);
      try {
        await AesGcmHkdfStreaming(ikm: ikm, segmentSize: segmentSize).descifrarArchivoHacia(
          origen: entrada,
          payloadBytes: await cifrado.length(),
          datosAsociados: otroAad ?? aad,
          destino: destino,
        );
      } finally {
        await entrada.close();
        await destino.close();
      }
      return salida.readAsBytes();
    }

    test('ida y vuelta exacta en todos los tamaños frontera', () async {
      for (final n in [0, 1, 71, 72, 73, 184, 185, 1000]) {
        final cifrado = await cifrarPorStreaming(_patron(n), 128);

        expect(await descifrarPorStreaming(cifrado, 128), equals(_patron(n)), reason: 'con $n bytes');
      }
    });

    test('con destino nulo autentica sin escribir nada', () async {
      final cifrado = await cifrarPorStreaming(_patron(500), 128);
      final entrada = await cifrado.open();
      try {
        await expectLater(
          AesGcmHkdfStreaming(
            ikm: ikm,
            segmentSize: 128,
          ).descifrarArchivoHacia(origen: entrada, payloadBytes: await cifrado.length(), datosAsociados: aad),
          completes,
          reason: 'es la verificación completa: recorre todo sin dejar copia descifrada',
        );
      } finally {
        await entrada.close();
      }

      expect(File(p.join(raiz.path, 'salida.bin')).existsSync(), isFalse);
    });

    test('un bit cambiado se detecta', () async {
      final cifrado = await cifrarPorStreaming(_patron(500), 128);
      final bytes = await cifrado.readAsBytes();
      bytes[60] ^= 0x01;
      await cifrado.writeAsBytes(bytes);

      await expectLater(descifrarPorStreaming(cifrado, 128), throwsA(isA<PayloadNoAutenticado>()));
    });

    test('un payload truncado se detecta', () async {
      final cifrado = await cifrarPorStreaming(_patron(500), 128);
      final bytes = await cifrado.readAsBytes();
      await cifrado.writeAsBytes(Uint8List.sublistView(bytes, 0, bytes.length - 17));

      await expectLater(descifrarPorStreaming(cifrado, 128), throwsA(isA<PayloadNoAutenticado>()));
    });

    test('unos datos asociados distintos invalidan todo el payload', () async {
      final cifrado = await cifrarPorStreaming(_patron(500), 128);

      await expectLater(
        descifrarPorStreaming(cifrado, 128, otroAad: Uint8List.fromList('otros'.codeUnits)),
        throwsA(isA<PayloadNoAutenticado>()),
      );
    });

    test('un payload declarado más largo de lo que hay se detecta', () async {
      final cifrado = await cifrarPorStreaming(_patron(500), 128);
      final entrada = await cifrado.open();
      try {
        await expectLater(
          AesGcmHkdfStreaming(
            ikm: ikm,
            segmentSize: 128,
          ).descifrarArchivoHacia(origen: entrada, payloadBytes: await cifrado.length() + 500, datosAsociados: aad),
          throwsA(isA<PayloadNoAutenticado>()),
        );
      } finally {
        await entrada.close();
      }
    });
  });
}
