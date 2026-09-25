import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import '../../../../core/security/aes_gcm_hkdf_streaming.dart';
import 'contenedor_portable.dart';
import 'kdf_portable.dart';

/// Operaciones de envoltura del respaldo portable (Etapa 4D):
/// frase/clave de recuperación → KEK → **MWK** → **DEK** → payload.
///
/// La MWK es lo que hace que la frase no tenga que pedirse dos veces ni
/// guardarse nunca: se envuelve una sola vez con cada credencial, y ese
/// bloque se copia tal cual en cada paquete. Crear un respaldo sólo
/// necesita abrir la MWK; la clave de recuperación no vuelve a hacer
/// falta después de configurarla.
class SobrePortable {
  SobrePortable({Random? aleatorio, DerivadorKek derivador = const DerivadorKek()})
    : _aleatorio = aleatorio ?? Random.secure(),
      _derivador = derivador;

  /// Inyectable para que las pruebas puedan fijar salts y nonces y
  /// comparar bytes exactos. En producción es `Random.secure()`.
  final Random _aleatorio;
  final DerivadorKek _derivador;

  Uint8List bytesAleatorios(int longitud) {
    return Uint8List.fromList(List<int>.generate(longitud, (_) => _aleatorio.nextInt(256)));
  }

  /// Una MWK nueva: 32 bytes de CSPRNG.
  Uint8List generarMwk() => bytesAleatorios(ContenedorPortable.longitudMwk);

  /// Una DEK nueva, distinta en cada paquete.
  Uint8List generarDek() => bytesAleatorios(ContenedorPortable.longitudDek);

  /// 160 bits para la clave de recuperación.
  Uint8List generarClaveRecuperacion() => bytesAleatorios(20);

  /// Envuelve [mwk] con la KEK derivada de [frase].
  ///
  /// [aad] son los datos asociados **sin** el descriptor: esta función
  /// lo añade, porque el descriptor depende del salt y los parámetros
  /// que aquí se eligen.
  EnvolturaMwk envolverConFrase({
    required Uint8List mwk,
    required String frase,
    required Uint8List prefijoAad,
    ParametrosArgon2id? parametros,
  }) {
    final p =
        parametros ??
        ParametrosArgon2id(
          memoriaKiB: ParametrosArgon2id.memoriaPorOmisionKiB,
          iteraciones: ParametrosArgon2id.iteracionesPorOmision,
          paralelismo: ParametrosArgon2id.paralelismoPorOmision,
          salt: bytesAleatorios(16),
        );
    final kek = _derivador.desdeFrase(frase: frase, parametros: p);
    return _envolver(
      mwk: mwk,
      kek: kek,
      prefijoAad: prefijoAad,
      plantilla: EnvolturaMwk(
        tipo: TipoEnvoltura.frase,
        salt: p.salt,
        nonce: bytesAleatorios(ContenedorPortable.longitudNonce),
        cifrado: Uint8List(0),
        parametrosArgon2: p,
      ),
    );
  }

  /// Envuelve [mwk] con la KEK derivada de la clave de recuperación.
  EnvolturaMwk envolverConClaveRecuperacion({
    required Uint8List mwk,
    required Uint8List claveRecuperacion,
    required Uint8List prefijoAad,
  }) {
    final salt = bytesAleatorios(16);
    final kek = _derivador.desdeClaveRecuperacion(claveRecuperacion: claveRecuperacion, salt: salt);
    return _envolver(
      mwk: mwk,
      kek: kek,
      prefijoAad: prefijoAad,
      plantilla: EnvolturaMwk(
        tipo: TipoEnvoltura.claveRecuperacion,
        salt: salt,
        nonce: bytesAleatorios(ContenedorPortable.longitudNonce),
        cifrado: Uint8List(0),
      ),
    );
  }

  EnvolturaMwk _envolver({
    required Uint8List mwk,
    required Uint8List kek,
    required Uint8List prefijoAad,
    required EnvolturaMwk plantilla,
  }) {
    final aad = _concatenar(prefijoAad, plantilla.descriptorBinario());
    final cifrado = _gcm(cifrando: true, clave: kek, nonce: plantilla.nonce, aad: aad, datos: mwk);
    return EnvolturaMwk(
      tipo: plantilla.tipo,
      salt: plantilla.salt,
      nonce: plantilla.nonce,
      cifrado: cifrado,
      parametrosArgon2: plantilla.parametrosArgon2,
    );
  }

  /// Abre la MWK con la frase. `null` si la credencial no corresponde.
  ///
  /// Es barato a propósito: la envoltura son 48 bytes, así que saber
  /// que una frase es incorrecta **nunca** obliga a tocar el payload.
  Uint8List? abrirConFrase({required EnvolturaMwk envoltura, required String frase, required Uint8List prefijoAad}) {
    final p = envoltura.parametrosArgon2;
    if (p == null) return null;
    try {
      final kek = _derivador.desdeFrase(frase: frase, parametros: p);
      return _abrir(envoltura: envoltura, kek: kek, prefijoAad: prefijoAad);
    } on ParametrosKdfRechazados {
      return null;
    }
  }

  /// Abre la MWK con la clave de recuperación.
  Uint8List? abrirConClaveRecuperacion({
    required EnvolturaMwk envoltura,
    required Uint8List claveRecuperacion,
    required Uint8List prefijoAad,
  }) {
    final kek = _derivador.desdeClaveRecuperacion(claveRecuperacion: claveRecuperacion, salt: envoltura.salt);
    return _abrir(envoltura: envoltura, kek: kek, prefijoAad: prefijoAad);
  }

  Uint8List? _abrir({required EnvolturaMwk envoltura, required Uint8List kek, required Uint8List prefijoAad}) {
    final aad = _concatenar(prefijoAad, envoltura.descriptorBinario());
    try {
      return _gcm(cifrando: false, clave: kek, nonce: envoltura.nonce, aad: aad, datos: envoltura.cifrado);
    } on InvalidCipherTextException {
      return null;
    }
  }

  /// Envuelve la DEK bajo la MWK. El nonce son 96 bits de CSPRNG
  /// **independientes**: derivarlo del `packageId` no habría añadido
  /// ninguna garantía —serían los mismos 96 bits aleatorios— y ataría
  /// dos cosas que deben poder fallar por separado.
  ({Uint8List nonce, Uint8List cifrado}) envolverDek({
    required Uint8List dek,
    required Uint8List mwk,
    required Uint8List prefijoAad,
  }) {
    final nonce = bytesAleatorios(ContenedorPortable.longitudNonce);
    return (nonce: nonce, cifrado: _gcm(cifrando: true, clave: mwk, nonce: nonce, aad: prefijoAad, datos: dek));
  }

  /// Abre la DEK. `null` si la MWK no corresponde o el paquete está
  /// manipulado.
  Uint8List? abrirDek({
    required Uint8List mwk,
    required Uint8List nonce,
    required Uint8List cifrado,
    required Uint8List prefijoAad,
  }) {
    try {
      return _gcm(cifrando: false, clave: mwk, nonce: nonce, aad: prefijoAad, datos: cifrado);
    } on InvalidCipherTextException {
      return null;
    }
  }

  Uint8List _gcm({
    required bool cifrando,
    required Uint8List clave,
    required Uint8List nonce,
    required Uint8List aad,
    required Uint8List datos,
  }) {
    final gcm = GCMBlockCipher(AESEngine())
      ..init(cifrando, AEADParameters(KeyParameter(clave), ContenedorPortable.longitudEtiqueta * 8, nonce, aad));
    return gcm.process(datos);
  }

  static Uint8List _concatenar(Uint8List a, Uint8List b) {
    return Uint8List(a.length + b.length)
      ..setRange(0, a.length, a)
      ..setRange(a.length, a.length + b.length, b);
  }
}

/// Arma los 8192 bytes de la zona de cabecera.
///
/// El orden importa y es circular sólo en apariencia: R1 se escribe
/// primero porque **es** el material del AAD de todo lo demás; las
/// envolturas y el `dekWrap` se calculan después, sobre esos bytes ya
/// fijados. Ninguna estructura autentica su propia salida.
abstract final class ConstructorZonaCabecera {
  /// Bytes que ocupará el payload cifrado, calculables antes de cifrar.
  ///
  /// `cabecera(40) + textoPlano + 16 por segmento`.
  static int calcularPayloadBytes({required int textoPlanoBytes, required int segmentSize}) {
    final cap0 = segmentSize - AesGcmHkdfStreaming.longitudCabecera - AesGcmHkdfStreaming.longitudEtiqueta;
    final capN = segmentSize - AesGcmHkdfStreaming.longitudEtiqueta;
    var segmentos = 1;
    if (textoPlanoBytes > cap0) {
      final resto = textoPlanoBytes - cap0;
      segmentos += (resto / capN).ceil();
    }
    return AesGcmHkdfStreaming.longitudCabecera + textoPlanoBytes + segmentos * AesGcmHkdfStreaming.longitudEtiqueta;
  }

  /// R1 relleno a 2048 bytes. Se devuelve junto a su longitud útil.
  static ({Uint8List zona, int coreLen}) construirR1(CabeceraPublica cabecera) {
    final json = Uint8List.fromList(utf8.encode(jsonEncode(cabecera.toJson())));
    if (json.length > ContenedorPortable.longitudCore) {
      throw StateError('La cabecera pública no cabe en ${ContenedorPortable.longitudCore} bytes.');
    }
    final zona = Uint8List(ContenedorPortable.zonaCabecera);
    zona
      ..setRange(0, ContenedorPortable.magicBytes.length, ContenedorPortable.magicBytes)
      ..setRange(ContenedorPortable.offsetCore, ContenedorPortable.offsetCore + json.length, json);
    ByteData.sublistView(zona)
      ..setUint16(8, ContenedorPortable.versionSoportada)
      ..setUint16(10, json.length)
      ..setUint16(12, 0)
      ..setUint16(14, 0);
    return (zona: zona, coreLen: json.length);
  }

  /// Completa la zona con `dekWrap` y las envolturas ya calculadas.
  static Uint8List completar({
    required Uint8List zonaConR1,
    required Uint8List dekWrapNonce,
    required Uint8List dekWrapCifrado,
    required List<EnvolturaMwk> envolturas,
  }) {
    final json = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'wrappers': [for (final e in envolturas) e.toJson()],
        }),
      ),
    );
    if (json.length > ContenedorPortable.longitudEnvolturas) {
      throw StateError('Las envolturas no caben en ${ContenedorPortable.longitudEnvolturas} bytes.');
    }

    final zona =
        Uint8List.fromList(zonaConR1)
          ..setRange(
            ContenedorPortable.offsetDekWrap,
            ContenedorPortable.offsetDekWrap + ContenedorPortable.longitudNonce,
            dekWrapNonce,
          )
          ..setRange(
            ContenedorPortable.offsetDekWrap + ContenedorPortable.longitudNonce,
            ContenedorPortable.offsetDekWrap + 60,
            dekWrapCifrado,
          )
          ..setRange(ContenedorPortable.offsetEnvolturas, ContenedorPortable.offsetEnvolturas + json.length, json);
    ByteData.sublistView(zona).setUint16(12, json.length);
    return zona;
  }
}
