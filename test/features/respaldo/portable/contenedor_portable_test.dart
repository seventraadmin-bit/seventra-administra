// Etapa 4D — un `.risegbkp` es contenido ajeno hasta que se autentica.
//
// Estas pruebas tratan el archivo como hostil: comprueban que todo lo
// que decide cuánta memoria se reserva o cuánto trabajo se hace está
// acotado ANTES de derivar una clave, y que cualquier cosa que un
// atacante querría cambiar —parámetros del KDF, identificadores,
// relleno— invalida la autenticación en vez de abaratar el ataque.

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/security/aes_gcm_hkdf_streaming.dart';
import 'package:riseg_one/features/respaldo/domain/portable/contenedor_portable.dart';
import 'package:riseg_one/features/respaldo/domain/portable/kdf_portable.dart';
import 'package:riseg_one/features/respaldo/domain/portable/sobre_portable.dart';

/// Aleatoriedad reproducible: las pruebas necesitan poder comparar
/// bytes exactos, no "algo distinto cada vez".
class _AzarFijo implements Random {
  _AzarFijo(this.semilla);
  int semilla;

  @override
  int nextInt(int max) {
    semilla = (semilla * 1103515245 + 12345) & 0x7FFFFFFF;
    return (semilla >> 16) % max;
  }

  @override
  bool nextBool() => nextInt(2) == 0;
  @override
  double nextDouble() => nextInt(1 << 20) / (1 << 20);
}

/// Argon2 de mentira: estas pruebas miden el formato, no el KDF, y con
/// el real cada caso costaría medio segundo.
class _Argon2Rapido implements GeneradorArgon2 {
  @override
  Uint8List derivar({required Uint8List secreto, required ParametrosArgon2id parametros}) {
    final salida = Uint8List(32);
    for (var i = 0; i < 32; i++) {
      salida[i] = (secreto.isEmpty ? 0 : secreto[i % secreto.length]) ^ parametros.salt[i % parametros.salt.length] ^ i;
    }
    return salida;
  }
}

const _frase = 'una frase de recuperación larga';
final _claveRecuperacion = Uint8List.fromList(List<int>.generate(20, (i) => i * 5));

CabeceraPublica _cabecera({int? payloadBytes, int? segmentSize, int? appSchemaVersion}) => CabeceraPublica(
  packageId: 'a' * 32,
  backupSetId: 'b' * 32,
  createdAt: DateTime.utc(2026, 9, 24, 12),
  appSchemaVersion: appSchemaVersion ?? 93,
  appVersion: '1.0.0',
  segmentSize: segmentSize ?? ContenedorPortable.segmentSizePorOmision,
  payloadBytes: payloadBytes ?? 1000,
);

/// Arma una zona de cabecera completa y coherente, como haría el
/// creador de un paquete real.
({Uint8List zona, Uint8List mwk, Uint8List dek}) _armar({
  CabeceraPublica? cabecera,
  bool conFrase = true,
  bool conClaveRecuperacion = true,
}) {
  final sobre = SobrePortable(aleatorio: _AzarFijo(7), derivador: DerivadorKek(argon2: _Argon2Rapido()));
  final mwk = sobre.generarMwk();
  final dek = sobre.generarDek();

  final r1 = ConstructorZonaCabecera.construirR1(cabecera ?? _cabecera());
  final prefijo = ContenedorPortable.prefijoAad(r1.zona);

  final envolturas = <EnvolturaMwk>[
    if (conFrase) sobre.envolverConFrase(mwk: mwk, frase: _frase, prefijoAad: prefijo),
    if (conClaveRecuperacion)
      sobre.envolverConClaveRecuperacion(mwk: mwk, claveRecuperacion: _claveRecuperacion, prefijoAad: prefijo),
  ];
  final dekWrap = sobre.envolverDek(dek: dek, mwk: mwk, prefijoAad: prefijo);

  final zona = ConstructorZonaCabecera.completar(
    zonaConR1: r1.zona,
    dekWrapNonce: dekWrap.nonce,
    dekWrapCifrado: dekWrap.cifrado,
    envolturas: envolturas,
  );
  return (zona: zona, mwk: mwk, dek: dek);
}

int _tamanoCoherente(Uint8List zona) {
  final leido = LectorContenedor.leer(zonaCabecera: zona, tamanoArchivo: ContenedorPortable.zonaCabecera + 1000);
  return ContenedorPortable.zonaCabecera + leido.cabecera.payloadBytes;
}

void main() {
  group('Layout', () {
    test('la zona de cabecera mide exactamente 8192 bytes, siempre', () {
      expect(_armar().zona.length, 8192);
      expect(ContenedorPortable.zonaCabecera, 8192);
    });

    test('empieza por el magic y la versión, legibles con un editor hexadecimal', () {
      final zona = _armar().zona;

      expect(utf8.decode(Uint8List.sublistView(zona, 0, 8)), 'RISEGBKP');
      expect(ByteData.sublistView(zona).getUint16(8), 1);
    });

    test('las regiones están en los offsets congelados', () {
      expect(ContenedorPortable.offsetCore, 16);
      expect(ContenedorPortable.longitudCore, 2048);
      expect(ContenedorPortable.offsetDekWrap, 2064);
      expect(ContenedorPortable.offsetEnvolturas, 2128);
      expect(ContenedorPortable.longitudEnvolturas, 6048);
      expect(ContenedorPortable.offsetReservadoFinal, 8176);
    });

    test('se lee de vuelta con sus dos envolturas', () {
      final zona = _armar().zona;

      final leido = LectorContenedor.leer(zonaCabecera: zona, tamanoArchivo: _tamanoCoherente(zona));

      expect(leido.envolturas, hasLength(2));
      expect(leido.tieneEnvolturaDeFrase, isTrue);
      expect(leido.tieneEnvolturaDeClaveRecuperacion, isTrue);
      expect(leido.cabecera.appSchemaVersion, 93);
      expect(leido.cabecera.segmentSize, 1024 * 1024);
    });

    test('la cabecera pública no filtra nada sensible', () {
      final zona = _armar().zona;
      final json = utf8.decode(
        Uint8List.sublistView(zona, ContenedorPortable.offsetCore, ContenedorPortable.offsetCore + 400),
      );

      for (final prohibido in ['nombre', 'rfc', 'empleado', 'cliente', 'ruta', 'attachment']) {
        expect(json.toLowerCase(), isNot(contains(prohibido)), reason: 'R1 no debe hablar de $prohibido');
      }
    });
  });

  group('Parser hostil', () {
    void rechaza(Uint8List zona, MotivoContenedorInvalido motivo, {int? tamano}) {
      expect(
        () =>
            LectorContenedor.leer(zonaCabecera: zona, tamanoArchivo: tamano ?? ContenedorPortable.zonaCabecera + 1000),
        throwsA(isA<ContenedorInvalido>().having((e) => e.motivo, 'motivo', motivo)),
      );
    }

    test('magic incorrecto', () {
      final zona = _armar().zona..[0] = 0x50;
      rechaza(zona, MotivoContenedorInvalido.magicIncorrecto);
    });

    test('un .zip renombrado no se confunde con un contenedor', () {
      final zona =
          Uint8List(8192)
            ..[0] = 0x50
            ..[1] = 0x4B;
      rechaza(zona, MotivoContenedorInvalido.magicIncorrecto);
    });

    test('containerVersion del futuro', () {
      final zona = _armar().zona;
      ByteData.sublistView(zona).setUint16(8, 2);
      rechaza(zona, MotivoContenedorInvalido.versionMasNueva);
    });

    test('coreLen por encima del máximo', () {
      final zona = _armar().zona;
      ByteData.sublistView(zona).setUint16(10, 2049);
      rechaza(zona, MotivoContenedorInvalido.longitudesFueraDeRango);
    });

    test('wrapLen por encima del máximo', () {
      final zona = _armar().zona;
      ByteData.sublistView(zona).setUint16(12, 6049);
      rechaza(zona, MotivoContenedorInvalido.longitudesFueraDeRango);
    });

    test('coreLen en cero', () {
      final zona = _armar().zona;
      ByteData.sublistView(zona).setUint16(10, 0);
      rechaza(zona, MotivoContenedorInvalido.longitudesFueraDeRango);
    });

    test('relleno de R1 con un byte no nulo', () {
      final zona = _armar().zona;
      final coreLen = ByteData.sublistView(zona).getUint16(10);
      zona[ContenedorPortable.offsetCore + coreLen + 5] = 0x41;
      rechaza(zona, MotivoContenedorInvalido.rellenoNoNulo);
    });

    test('reserva final con basura', () {
      final zona = _armar().zona..[8180] = 0xFF;
      rechaza(zona, MotivoContenedorInvalido.rellenoNoNulo);
    });

    test('reserva de R2 con basura', () {
      final zona = _armar().zona..[ContenedorPortable.offsetDekWrap + 61] = 0x01;
      rechaza(zona, MotivoContenedorInvalido.rellenoNoNulo);
    });

    test('JSON de R1 inválido', () {
      final zona = _armar().zona..[ContenedorPortable.offsetCore] = 0x41;
      rechaza(zona, MotivoContenedorInvalido.cabeceraIlegible);
    });

    test('JSON absurdamente anidado', () {
      var profundo = '1';
      for (var i = 0; i < 40; i++) {
        profundo = '{"a":$profundo}';
      }
      final bytes = Uint8List.fromList(utf8.encode(profundo));
      final zona =
          _armar().zona
            ..fillRange(ContenedorPortable.offsetCore, ContenedorPortable.offsetDekWrap, 0)
            ..setRange(ContenedorPortable.offsetCore, ContenedorPortable.offsetCore + bytes.length, bytes);
      ByteData.sublistView(zona).setUint16(10, bytes.length);
      rechaza(zona, MotivoContenedorInvalido.cabeceraIlegible);
    });

    test('payloadBytes que no cuadra con el tamaño físico: truncado o manipulado', () {
      final zona = _armar().zona;
      rechaza(zona, MotivoContenedorInvalido.tamanoInconsistente, tamano: ContenedorPortable.zonaCabecera + 999);
    });

    test('payloadBytes por encima del máximo de política (64 GiB)', () {
      final zona = _armar(cabecera: _cabecera(payloadBytes: 65 * 1024 * 1024 * 1024)).zona;
      rechaza(zona, MotivoContenedorInvalido.cabeceraIlegible);
    });

    test('segmentSize que no es potencia de dos', () {
      final zona = _armar(cabecera: _cabecera(segmentSize: 1000000)).zona;
      rechaza(zona, MotivoContenedorInvalido.cabeceraIlegible);
    });

    test('segmentSize fuera de rango', () {
      for (final tamano in [1024, 8 * 1024 * 1024]) {
        final zona = _armar(cabecera: _cabecera(segmentSize: tamano)).zona;
        rechaza(zona, MotivoContenedorInvalido.cabeceraIlegible);
      }
    });

    test('archivo más corto que su propia cabecera', () {
      rechaza(_armar().zona, MotivoContenedorInvalido.demasiadoCorto, tamano: 8192);
    });

    test('sin ninguna envoltura: nadie podría abrirlo', () {
      final zona = _armar(conFrase: false, conClaveRecuperacion: false).zona;
      rechaza(zona, MotivoContenedorInvalido.sinEnvolturas);
    });

    test('más de ocho envolturas', () {
      final zona = _armar().zona;
      final muchas = jsonEncode({
        'wrappers': [
          for (var i = 0; i < 9; i++)
            {
              'tipo': 'frase',
              'kdf': 'argon2id',
              'kdfVersion': 0x13,
              'm': 65536,
              't': 3,
              'p': 1,
              'salt': '00' * 16,
              'wrap': 'aes-256-gcm',
              'nonce': '00' * 12,
              'ct': '00' * 48,
            },
        ],
      });
      final bytes = Uint8List.fromList(utf8.encode(muchas));
      zona
        ..fillRange(ContenedorPortable.offsetEnvolturas, ContenedorPortable.offsetReservadoFinal, 0)
        ..setRange(ContenedorPortable.offsetEnvolturas, ContenedorPortable.offsetEnvolturas + bytes.length, bytes);
      ByteData.sublistView(zona).setUint16(12, bytes.length);
      rechaza(zona, MotivoContenedorInvalido.demasiadasEnvolturas);
    });
  });

  group('Parámetros de Argon2 hostiles dentro de una envoltura', () {
    /// Sustituye el bloque de envolturas por uno con los parámetros
    /// indicados, manteniendo el resto de la zona intacto.
    Uint8List conParametros({required int m, required int t, required int p, int version = 0x13, int saltBytes = 16}) {
      final zona = _armar().zona;
      final json = jsonEncode({
        'wrappers': [
          {
            'tipo': 'frase',
            'kdf': 'argon2id',
            'kdfVersion': version,
            'm': m,
            't': t,
            'p': p,
            'salt': '00' * saltBytes,
            'wrap': 'aes-256-gcm',
            'nonce': '00' * 12,
            'ct': '00' * 48,
          },
        ],
      });
      final bytes = Uint8List.fromList(utf8.encode(json));
      zona
        ..fillRange(ContenedorPortable.offsetEnvolturas, ContenedorPortable.offsetReservadoFinal, 0)
        ..setRange(ContenedorPortable.offsetEnvolturas, ContenedorPortable.offsetEnvolturas + bytes.length, bytes);
      ByteData.sublistView(zona).setUint16(12, bytes.length);
      return zona;
    }

    void rechazaAlLeer(Uint8List zona) {
      expect(
        () => LectorContenedor.leer(zonaCabecera: zona, tamanoArchivo: ContenedorPortable.zonaCabecera + 1000),
        throwsA(
          isA<ContenedorInvalido>().having((e) => e.motivo, 'motivo', MotivoContenedorInvalido.envolturasIlegibles),
        ),
      );
    }

    test('m = 4 TB se rechaza al leer, sin llegar a ninguna derivación', () {
      rechazaAlLeer(conParametros(m: 4 * 1024 * 1024 * 1024, t: 3, p: 1));
    });

    test('m por debajo del mínimo', () => rechazaAlLeer(conParametros(m: 1024, t: 3, p: 1)));
    test('t = 0', () => rechazaAlLeer(conParametros(m: 65536, t: 0, p: 1)));
    test('t = 11', () => rechazaAlLeer(conParametros(m: 65536, t: 11, p: 1)));
    test('p = 5', () => rechazaAlLeer(conParametros(m: 65536, t: 3, p: 5)));
    test('versión desconocida', () => rechazaAlLeer(conParametros(m: 65536, t: 3, p: 1, version: 0x10)));
    test('salt fuera de rango', () => rechazaAlLeer(conParametros(m: 65536, t: 3, p: 1, saltBytes: 8)));

    test('coste combinado excesivo', () => rechazaAlLeer(conParametros(m: 1024 * 1024, t: 10, p: 1)));

    test('unos parámetros legítimos sí se leen', () {
      final zona = conParametros(m: 65536, t: 3, p: 1);

      final leido = LectorContenedor.leer(zonaCabecera: zona, tamanoArchivo: _tamanoCoherente(zona));

      expect(leido.envolturas.single.parametrosArgon2!.memoriaKiB, 65536);
    });
  });

  group('Envolturas y jerarquía de claves', () {
    late SobrePortable sobre;

    setUp(() {
      sobre = SobrePortable(aleatorio: _AzarFijo(7), derivador: DerivadorKek(argon2: _Argon2Rapido()));
    });

    test('la frase y la clave de recuperación abren EXACTAMENTE la misma MWK', () {
      final armado = _armar();
      final leido = LectorContenedor.leer(zonaCabecera: armado.zona, tamanoArchivo: _tamanoCoherente(armado.zona));
      final prefijo = ContenedorPortable.prefijoAad(armado.zona);

      final porFrase = sobre.abrirConFrase(
        envoltura: leido.envolturas.firstWhere((e) => e.tipo == TipoEnvoltura.frase),
        frase: _frase,
        prefijoAad: prefijo,
      );
      final porClave = sobre.abrirConClaveRecuperacion(
        envoltura: leido.envolturas.firstWhere((e) => e.tipo == TipoEnvoltura.claveRecuperacion),
        claveRecuperacion: _claveRecuperacion,
        prefijoAad: prefijo,
      );

      expect(porFrase, equals(armado.mwk));
      expect(porClave, equals(armado.mwk));
      expect(porFrase, equals(porClave));
    });

    test('una frase incorrecta devuelve null, sin tocar el payload', () {
      final armado = _armar();
      final leido = LectorContenedor.leer(zonaCabecera: armado.zona, tamanoArchivo: _tamanoCoherente(armado.zona));

      expect(
        sobre.abrirConFrase(
          envoltura: leido.envolturas.first,
          frase: 'otra frase',
          prefijoAad: ContenedorPortable.prefijoAad(armado.zona),
        ),
        isNull,
      );
    });

    test('una clave de recuperación incorrecta devuelve null', () {
      final armado = _armar();
      final leido = LectorContenedor.leer(zonaCabecera: armado.zona, tamanoArchivo: _tamanoCoherente(armado.zona));

      expect(
        sobre.abrirConClaveRecuperacion(
          envoltura: leido.envolturas.firstWhere((e) => e.tipo == TipoEnvoltura.claveRecuperacion),
          claveRecuperacion: Uint8List(20),
          prefijoAad: ContenedorPortable.prefijoAad(armado.zona),
        ),
        isNull,
      );
    });

    test('la MWK abre la DEK del paquete', () {
      final armado = _armar();
      final leido = LectorContenedor.leer(zonaCabecera: armado.zona, tamanoArchivo: _tamanoCoherente(armado.zona));

      final dek = sobre.abrirDek(
        mwk: armado.mwk,
        nonce: leido.dekWrapNonce,
        cifrado: leido.dekWrapCifrado,
        prefijoAad: ContenedorPortable.prefijoAad(armado.zona),
      );

      expect(dek, equals(armado.dek));
      expect(dek!.length, 32);
    });

    test('otra MWK no abre la DEK', () {
      final armado = _armar();
      final leido = LectorContenedor.leer(zonaCabecera: armado.zona, tamanoArchivo: _tamanoCoherente(armado.zona));

      expect(
        sobre.abrirDek(
          mwk: Uint8List(32),
          nonce: leido.dekWrapNonce,
          cifrado: leido.dekWrapCifrado,
          prefijoAad: ContenedorPortable.prefijoAad(armado.zona),
        ),
        isNull,
      );
    });

    test('cada paquete lleva su propia DEK', () {
      final uno = _armar();
      final otroSobre = SobrePortable(aleatorio: _AzarFijo(99), derivador: DerivadorKek(argon2: _Argon2Rapido()));

      expect(otroSobre.generarDek(), isNot(equals(uno.dek)));
    });

    test('el nonce del dekWrap no se repite entre paquetes', () {
      final a = SobrePortable(aleatorio: _AzarFijo(1), derivador: DerivadorKek(argon2: _Argon2Rapido()));
      final b = SobrePortable(aleatorio: _AzarFijo(2), derivador: DerivadorKek(argon2: _Argon2Rapido()));
      final mwk = Uint8List(32);
      final prefijo = Uint8List(100);

      expect(
        a.envolverDek(dek: a.generarDek(), mwk: mwk, prefijoAad: prefijo).nonce,
        isNot(equals(b.envolverDek(dek: b.generarDek(), mwk: mwk, prefijoAad: prefijo).nonce)),
      );
    });
  });

  group('El AAD ata la cabecera al contenido', () {
    late SobrePortable sobre;
    setUp(() {
      sobre = SobrePortable(aleatorio: _AzarFijo(7), derivador: DerivadorKek(argon2: _Argon2Rapido()));
    });

    test('alterar el packageId invalida el dekWrap', () {
      final armado = _armar();
      final zonaAlterada = Uint8List.fromList(armado.zona);
      // Cambia un byte dentro del JSON de R1 sin tocar su longitud.
      final posicion = utf8
          .decode(
            Uint8List.sublistView(zonaAlterada, ContenedorPortable.offsetCore, ContenedorPortable.offsetCore + 300),
          )
          .indexOf('aaaa');
      zonaAlterada[ContenedorPortable.offsetCore + posicion] = 0x62; // 'b'

      final leido = LectorContenedor.leer(zonaCabecera: zonaAlterada, tamanoArchivo: _tamanoCoherente(zonaAlterada));

      expect(
        sobre.abrirDek(
          mwk: armado.mwk,
          nonce: leido.dekWrapNonce,
          cifrado: leido.dekWrapCifrado,
          prefijoAad: ContenedorPortable.prefijoAad(zonaAlterada),
        ),
        isNull,
        reason: 'el prefijo del AAD incluye R1 entero',
      );
    });

    test('alterar el descriptor de la envoltura la invalida', () {
      final armado = _armar();
      final leido = LectorContenedor.leer(zonaCabecera: armado.zona, tamanoArchivo: _tamanoCoherente(armado.zona));
      final original = leido.envolturas.firstWhere((e) => e.tipo == TipoEnvoltura.frase);

      // Mismo ciphertext, parámetros degradados: es el ataque que el
      // descriptor binario existe para impedir.
      final degradada = EnvolturaMwk(
        tipo: original.tipo,
        salt: original.salt,
        nonce: original.nonce,
        cifrado: original.cifrado,
        parametrosArgon2: ParametrosArgon2id(memoriaKiB: 8 * 1024, iteraciones: 1, paralelismo: 1, salt: original.salt),
      );

      expect(
        sobre.abrirConFrase(
          envoltura: degradada,
          frase: _frase,
          prefijoAad: ContenedorPortable.prefijoAad(armado.zona),
        ),
        isNull,
        reason: 'degradar m de 64 MiB a 8 MiB debe romper la autenticación',
      );
    });

    test('alterar el ciphertext de una envoltura la invalida', () {
      final armado = _armar();
      final leido = LectorContenedor.leer(zonaCabecera: armado.zona, tamanoArchivo: _tamanoCoherente(armado.zona));
      final original = leido.envolturas.first;
      final roto = Uint8List.fromList(original.cifrado)..[0] ^= 0xFF;

      expect(
        sobre.abrirConFrase(
          envoltura: EnvolturaMwk(
            tipo: original.tipo,
            salt: original.salt,
            nonce: original.nonce,
            cifrado: roto,
            parametrosArgon2: original.parametrosArgon2,
          ),
          frase: _frase,
          prefijoAad: ContenedorPortable.prefijoAad(armado.zona),
        ),
        isNull,
      );
    });
  });

  group('Cálculo del tamaño del payload', () {
    test('coincide byte a byte con lo que produce el cifrador real', () {
      // No se compara contra otra fórmula —eso no probaría nada— sino
      // contra la salida del motor. Si la cuenta y el formato se
      // separan, el paquete declararía un tamaño que no es el suyo y su
      // propio parser lo rechazaría como truncado.
      const segmentSize = 128;
      final motor = AesGcmHkdfStreaming(ikm: Uint8List(32), segmentSize: segmentSize);

      for (final n in [0, 1, 71, 72, 73, 184, 185, 500]) {
        final real =
            motor
                .cifrar(
                  textoPlano: Uint8List(n),
                  datosAsociados: Uint8List(0),
                  salt: Uint8List(32),
                  prefijoNonce: Uint8List(7),
                )
                .length;

        expect(
          ConstructorZonaCabecera.calcularPayloadBytes(textoPlanoBytes: n, segmentSize: segmentSize),
          real,
          reason: 'con  bytes de texto plano',
        );
      }
    });
  });
}
