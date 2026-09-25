// Etapa 4D — los parámetros del KDF llegan dentro de un archivo ajeno.
//
// Hay que leerlos para poder autenticar el paquete, así que en el
// momento de leerlos todavía no se puede confiar en ellos. De ahí que
// estas pruebas no se conformen con "lanza una excepción": comprueban
// el ORDEN, con un generador espía que registra si llegó a invocarse.
// Rechazar después de haber intentado reservar un gigabyte no es
// rechazar.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/features/respaldo/domain/portable/kdf_portable.dart';

/// Registra si alguien lo llamó. Nunca deriva nada de verdad: si una
/// prueba de límites lo invoca, eso mismo es el fallo.
class _Argon2Espia implements GeneradorArgon2 {
  int invocaciones = 0;
  ParametrosArgon2id? ultimos;

  @override
  Uint8List derivar({required Uint8List secreto, required ParametrosArgon2id parametros}) {
    invocaciones++;
    ultimos = parametros;
    return Uint8List(32);
  }
}

Uint8List _salt([int n = 16]) => Uint8List.fromList(List<int>.generate(n, (i) => i));

ParametrosArgon2id _validos({int? m, int? t, int? p, int? version, Uint8List? salt}) => ParametrosArgon2id(
  memoriaKiB: m ?? ParametrosArgon2id.memoriaPorOmisionKiB,
  iteraciones: t ?? ParametrosArgon2id.iteracionesPorOmision,
  paralelismo: p ?? ParametrosArgon2id.paralelismoPorOmision,
  salt: salt ?? _salt(),
  version: version ?? ParametrosArgon2id.versionSoportada,
);

void main() {
  group('Valores por omisión congelados en esta versión', () {
    test('64 MiB, t=3, p=1, salida de 32 bytes, Argon2id v19', () {
      expect(ParametrosArgon2id.memoriaPorOmisionKiB, 64 * 1024);
      expect(ParametrosArgon2id.iteracionesPorOmision, 3);
      expect(ParametrosArgon2id.paralelismoPorOmision, 1);
      expect(ParametrosArgon2id.longitudSalida, 32);
      expect(ParametrosArgon2id.versionSoportada, 0x13);
    });

    test('los valores por omisión caen dentro de los límites de parseo', () {
      expect(LimitesArgon2id.validar(_validos()), isNull);
    });
  });

  group('El orden: rechazar ANTES de derivar', () {
    late _Argon2Espia espia;
    late DerivadorKek derivador;

    setUp(() {
      espia = _Argon2Espia();
      derivador = DerivadorKek(argon2: espia);
    });

    void rechazaSinDerivar(ParametrosArgon2id parametros, MotivoKdfRechazado motivo) {
      expect(
        () => derivador.desdeFrase(frase: 'una frase de recuperación', parametros: parametros),
        throwsA(isA<ParametrosKdfRechazados>().having((e) => e.motivo, 'motivo', motivo)),
      );
      expect(
        espia.invocaciones,
        0,
        reason: 'se rechazó, pero DESPUÉS de invocar Argon2: el trabajo hostil ya se habría hecho',
      );
    }

    test(
      'm = 4 TB',
      () => rechazaSinDerivar(_validos(m: 4 * 1024 * 1024 * 1024), MotivoKdfRechazado.memoriaFueraDeRango),
    );

    test('m por debajo del mínimo', () => rechazaSinDerivar(_validos(m: 1024), MotivoKdfRechazado.memoriaFueraDeRango));

    test('t = 0', () => rechazaSinDerivar(_validos(t: 0), MotivoKdfRechazado.iteracionesFueraDeRango));

    test('t = 11', () => rechazaSinDerivar(_validos(t: 11), MotivoKdfRechazado.iteracionesFueraDeRango));

    test('p = 5', () => rechazaSinDerivar(_validos(p: 5), MotivoKdfRechazado.paralelismoFueraDeRango));

    test('p = 0', () => rechazaSinDerivar(_validos(p: 0), MotivoKdfRechazado.paralelismoFueraDeRango));

    test(
      'versión desconocida',
      () => rechazaSinDerivar(_validos(version: 0x10), MotivoKdfRechazado.versionNoSoportada),
    );

    test(
      'salt demasiado corto',
      () => rechazaSinDerivar(_validos(salt: _salt(8)), MotivoKdfRechazado.saltFueraDeRango),
    );

    test(
      'salt demasiado largo',
      () => rechazaSinDerivar(_validos(salt: _salt(64)), MotivoKdfRechazado.saltFueraDeRango),
    );

    test('coste combinado: 1 GiB × 10 pasa cada rango individual pero no el tope', () {
      // Cada parámetro por separado es legal. Juntos colgarían el equipo.
      expect(LimitesArgon2id.validar(_validos(m: 1024 * 1024, t: 10)), MotivoKdfRechazado.costeCombinadoExcesivo);
      rechazaSinDerivar(_validos(m: 1024 * 1024, t: 10), MotivoKdfRechazado.costeCombinadoExcesivo);
    });

    test('unos parámetros aceptables SÍ llegan al generador', () {
      derivador.desdeFrase(frase: 'una frase de recuperación', parametros: _validos());

      expect(espia.invocaciones, 1);
      expect(espia.ultimos!.memoriaKiB, ParametrosArgon2id.memoriaPorOmisionKiB);
    });

    test('la frase viaja al generador en UTF-8, no en UTF-16', () {
      // Con `codeUnits`, "ñ" daría un solo byte 0xF1; en UTF-8 son dos
      // (0xC3 0xB1). Elegir mal aquí produce una KEK distinta para la
      // misma frase, y el paquete deja de abrirse.
      final esperado = utf8.encode('contraseña con ñ y acentós');
      final visto = <int>[];
      final capturador = _Argon2Capturador(visto);

      DerivadorKek(argon2: capturador).desdeFrase(frase: 'contraseña con ñ y acentós', parametros: _validos());

      expect(visto, equals(esperado));
    });
  });

  group('Argon2id real', () {
    test('la misma frase y el mismo salt dan la misma KEK', () {
      const derivador = DerivadorKek();
      final parametros = _validos(m: 8 * 1024, t: 1); // mínimo legal: prueba rápida

      final a = derivador.desdeFrase(frase: 'mi frase', parametros: parametros);
      final b = derivador.desdeFrase(frase: 'mi frase', parametros: parametros);

      expect(a, equals(b));
      expect(a.length, 32);
    });

    test('otra frase da otra KEK', () {
      const derivador = DerivadorKek();
      final parametros = _validos(m: 8 * 1024, t: 1);

      expect(
        derivador.desdeFrase(frase: 'mi frase', parametros: parametros),
        isNot(equals(derivador.desdeFrase(frase: 'mi frase.', parametros: parametros))),
      );
    });

    test('otro salt da otra KEK con la misma frase', () {
      const derivador = DerivadorKek();
      final uno = _validos(m: 8 * 1024, t: 1, salt: _salt());
      final otro = _validos(m: 8 * 1024, t: 1, salt: Uint8List.fromList(List.filled(16, 9)));

      expect(
        derivador.desdeFrase(frase: 'mi frase', parametros: uno),
        isNot(equals(derivador.desdeFrase(frase: 'mi frase', parametros: otro))),
      );
    });
  });

  group('HKDF de la clave de recuperación', () {
    const derivador = DerivadorKek();

    test('determinista y de 32 bytes', () {
      final clave = Uint8List.fromList(List<int>.generate(20, (i) => i * 3));
      final a = derivador.desdeClaveRecuperacion(claveRecuperacion: clave, salt: _salt());
      final b = derivador.desdeClaveRecuperacion(claveRecuperacion: clave, salt: _salt());

      expect(a, equals(b));
      expect(a.length, 32);
    });

    test('otra clave, otra KEK; otro salt, otra KEK', () {
      final clave = Uint8List.fromList(List<int>.generate(20, (i) => i * 3));
      final otraClave = Uint8List.fromList(List<int>.generate(20, (i) => i * 3 + 1));
      final base = derivador.desdeClaveRecuperacion(claveRecuperacion: clave, salt: _salt());

      expect(derivador.desdeClaveRecuperacion(claveRecuperacion: otraClave, salt: _salt()), isNot(equals(base)));
      expect(
        derivador.desdeClaveRecuperacion(claveRecuperacion: clave, salt: Uint8List.fromList(List.filled(16, 7))),
        isNot(equals(base)),
      );
    });

    test('el contexto del HKDF está fijado y documentado', () {
      expect(DerivadorKek.contextoClaveRecuperacion, 'RISEG-BKP-v1 recovery-key KEK');
    });
  });
}

/// Captura el secreto exacto que se le pasa al generador.
class _Argon2Capturador implements GeneradorArgon2 {
  _Argon2Capturador(this.visto);
  final List<int> visto;

  @override
  Uint8List derivar({required Uint8List secreto, required ParametrosArgon2id parametros}) {
    visto.addAll(secreto);
    return Uint8List(32);
  }
}
