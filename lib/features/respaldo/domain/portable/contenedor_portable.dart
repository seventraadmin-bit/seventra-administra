import 'dart:convert';
import 'dart:typed_data';

import '../../../../core/security/aes_gcm_hkdf_streaming.dart';
import 'kdf_portable.dart';

/// **RISEG Portable Backup Container v1** — el archivo `.risegbkp`
/// (Etapa 4D).
///
/// ```
/// offset  long.   campo
/// 0       8       MAGIC "RISEGBKP"
/// 8       2       containerVersion (uint16 BE) = 1
/// 10      2       coreLen   (uint16 BE) ≤ 2048
/// 12      2       wrapLen   (uint16 BE) ≤ 6048
/// 14      2       reservado = 0
/// 16      2048    R1 cabecera pública — JSON UTF-8 + relleno 0x00
/// 2064    64      R2 dekWrap — nonce(12) ‖ ct(32) ‖ tag(16) ‖ ceros(4)
/// 2128    6048    R3 envolturas — JSON UTF-8 + relleno 0x00
/// 8176    16      reservado = 0
/// 8192    …       payload (AES-GCM-HKDF-STREAMING)
/// ```
///
/// **La zona de cabecera mide siempre 8192 bytes.** No es una elección
/// estética: significa que **ninguna asignación de memoria depende de
/// un número que venga dentro del archivo**. `coreLen` y `wrapLen` sólo
/// acotan cuánto de esa zona fija es JSON. Un contenedor es contenido
/// ajeno, y la clase de fallo más fácil de cometer es dejar que declare
/// cuánto quiere que reserves.
///
/// **Jerarquía de claves.** La frase o la clave de recuperación abren
/// —cada una por su cuenta— la misma MWK; la MWK abre la DEK de este
/// paquete; la DEK cifra el payload. Cambiar la frase reenvuelve la MWK
/// y no toca ni un byte del contenido.
abstract final class ContenedorPortable {
  static const magic = 'RISEGBKP';
  static final magicBytes = Uint8List.fromList(utf8.encode(magic));

  static const versionSoportada = 1;
  static const extension = '.risegbkp';

  static const zonaCabecera = 8192;
  static const offsetCore = 16;
  static const longitudCore = 2048;
  static const offsetDekWrap = 2064;
  static const longitudDekWrap = 64;
  static const offsetEnvolturas = 2128;
  static const longitudEnvolturas = 6048;
  static const offsetReservadoFinal = 8176;

  /// `segmentSize` que escribe esta versión. El parser acepta un rango
  /// mayor para poder leer paquetes de versiones futuras.
  static const segmentSizePorOmision = 1024 * 1024;
  static const segmentSizeMinimo = 64 * 1024;
  static const segmentSizeMaximo = 4 * 1024 * 1024;

  /// Máximo por política, no por matemática: el contador de segmentos
  /// admitiría petabytes. 64 GiB está muy por encima de cualquier
  /// conjunto real de RISEG ONE y acota el trabajo de verificación.
  static const payloadMaximoBytes = 64 * 1024 * 1024 * 1024;

  static const maximoEnvolturas = 8;

  static const longitudNonce = 12;
  static const longitudMwk = 32;
  static const longitudDek = 32;
  static const longitudEtiqueta = 16;

  /// Prefijo común a todos los datos asociados del contenedor:
  /// `MAGIC ‖ containerVersion ‖ R1 completo tal como está en disco`.
  ///
  /// Se toman los **bytes tal cual**, nunca una reserialización del
  /// JSON: así no existe problema de canonicalización, porque nunca se
  /// vuelve a serializar nada para autenticar.
  static Uint8List prefijoAad(Uint8List zonaCabecera) {
    final salida = Uint8List(magicBytes.length + 2 + longitudCore);
    salida
      ..setRange(0, magicBytes.length, zonaCabecera)
      ..setRange(magicBytes.length, magicBytes.length + 2, zonaCabecera, 8)
      ..setRange(magicBytes.length + 2, salida.length, zonaCabecera, offsetCore);
    return salida;
  }

  /// Datos asociados de una envoltura: el prefijo más un **descriptor
  /// binario de layout fijo**, nunca el JSON de la envoltura.
  ///
  /// El descriptor excluye a propósito el ciphertext y la etiqueta de
  /// la propia envoltura: una envoltura no puede autenticar su propia
  /// salida sin crear una dependencia circular. Lo que sí queda atado
  /// es todo lo que un atacante querría cambiar — tipo, KDF, versión,
  /// parámetros y salt—, así que degradar `m` de 64 MiB a 8 MiB rompe
  /// la autenticación en vez de abaratar un ataque.
  static Uint8List aadEnvoltura({required Uint8List zonaCabecera, required EnvolturaMwk envoltura}) {
    final prefijo = prefijoAad(zonaCabecera);
    final descriptor = envoltura.descriptorBinario();
    return Uint8List(prefijo.length + descriptor.length)
      ..setRange(0, prefijo.length, prefijo)
      ..setRange(prefijo.length, prefijo.length + descriptor.length, descriptor);
  }
}

/// Cómo se protege la MWK en una envoltura.
enum TipoEnvoltura {
  frase(0x01),
  claveRecuperacion(0x02);

  const TipoEnvoltura(this.id);
  final int id;

  static TipoEnvoltura? desdeNombre(String? nombre) {
    for (final t in TipoEnvoltura.values) {
      if (t.name == nombre) return t;
    }
    return null;
  }
}

/// Una envoltura de la MWK. Las dos —frase y clave de recuperación—
/// envuelven **exactamente la misma** MWK de 32 bytes.
class EnvolturaMwk {
  const EnvolturaMwk({
    required this.tipo,
    required this.salt,
    required this.nonce,
    required this.cifrado,
    this.parametrosArgon2,
  });

  final TipoEnvoltura tipo;
  final Uint8List salt;
  final Uint8List nonce;

  /// MWK cifrada con la KEK: 32 bytes de ciphertext + 16 de etiqueta.
  final Uint8List cifrado;

  /// Sólo en [TipoEnvoltura.frase]. La de clave de recuperación usa
  /// HKDF, que no tiene parámetros de coste que negociar.
  final ParametrosArgon2id? parametrosArgon2;

  static const longitudCifrado = ContenedorPortable.longitudMwk + ContenedorPortable.longitudEtiqueta;

  /// Identificadores estables del descriptor binario. Se escriben a
  /// mano y no se derivan de `index` para que reordenar un `enum` no
  /// invalide paquetes ya escritos.
  static const _kdfArgon2id = 0x01;
  static const _kdfHkdfSha256 = 0x02;
  static const _wrapAesGcm256 = 0x01;

  /// `tipo(1) ‖ kdf(1) ‖ kdfVersion(1) ‖ m(4) ‖ t(4) ‖ p(4) ‖
  /// saltLen(1) ‖ salt ‖ wrapAlg(1)`, todo big-endian.
  Uint8List descriptorBinario() {
    final p = parametrosArgon2;
    final salida = Uint8List(1 + 1 + 1 + 4 + 4 + 4 + 1 + salt.length + 1);
    final vista = ByteData.sublistView(salida);
    salida[0] = tipo.id;
    salida[1] = p != null ? _kdfArgon2id : _kdfHkdfSha256;
    salida[2] = p?.version ?? 0;
    vista
      ..setUint32(3, p?.memoriaKiB ?? 0)
      ..setUint32(7, p?.iteraciones ?? 0)
      ..setUint32(11, p?.paralelismo ?? 0);
    salida[15] = salt.length;
    salida.setRange(16, 16 + salt.length, salt);
    salida[16 + salt.length] = _wrapAesGcm256;
    return salida;
  }

  Map<String, dynamic> toJson() => {
    'tipo': tipo.name,
    'kdf': parametrosArgon2 != null ? 'argon2id' : 'hkdf-sha256',
    if (parametrosArgon2 != null) 'kdfVersion': parametrosArgon2!.version,
    if (parametrosArgon2 != null) 'm': parametrosArgon2!.memoriaKiB,
    if (parametrosArgon2 != null) 't': parametrosArgon2!.iteraciones,
    if (parametrosArgon2 != null) 'p': parametrosArgon2!.paralelismo,
    'salt': _hex(salt),
    'wrap': 'aes-256-gcm',
    'nonce': _hex(nonce),
    'ct': _hex(cifrado),
  };

  /// `null` si el JSON no describe una envoltura utilizable. Nunca
  /// lanza: un paquete ajeno malformado es un paquete inválido, no una
  /// excepción que se escape.
  static EnvolturaMwk? fromJson(Map<String, dynamic> json) {
    try {
      final tipo = TipoEnvoltura.desdeNombre(json['tipo'] as String?);
      if (tipo == null) return null;
      if (json['wrap'] != 'aes-256-gcm') return null;

      final salt = _deHex(json['salt'] as String?);
      final nonce = _deHex(json['nonce'] as String?);
      final cifrado = _deHex(json['ct'] as String?);
      if (salt == null || nonce == null || cifrado == null) return null;
      if (nonce.length != ContenedorPortable.longitudNonce) return null;
      if (cifrado.length != longitudCifrado) return null;

      final kdf = json['kdf'] as String?;
      if (kdf == 'hkdf-sha256') {
        if (salt.length < LimitesArgon2id.saltMinimo || salt.length > LimitesArgon2id.saltMaximo) return null;
        return EnvolturaMwk(tipo: tipo, salt: salt, nonce: nonce, cifrado: cifrado);
      }
      if (kdf != 'argon2id') return null;

      final parametros = ParametrosArgon2id(
        memoriaKiB: json['m'] as int,
        iteraciones: json['t'] as int,
        paralelismo: json['p'] as int,
        salt: salt,
        version: json['kdfVersion'] as int,
      );
      // Los límites se aplican AQUÍ, al leer, antes de que nadie pueda
      // pedirle trabajo a Argon2 con ellos.
      if (LimitesArgon2id.validar(parametros) != null) return null;

      return EnvolturaMwk(tipo: tipo, salt: salt, nonce: nonce, cifrado: cifrado, parametrosArgon2: parametros);
    } catch (_) {
      return null;
    }
  }
}

/// Metadata pública de R1 — lo único que puede leerse sin credencial.
///
/// Deliberadamente **no** lleva nombres de empresa, clientes o
/// empleados, RFC, rutas ni nombres de adjuntos, conteos de registros
/// ni cifras. Lo que sí lleva se justifica por su utilidad: la fecha y
/// el esquema permiten que la lista diga algo útil y que un paquete
/// demasiado nuevo se rechace **antes** de pedir la frase.
class CabeceraPublica {
  const CabeceraPublica({
    required this.packageId,
    required this.backupSetId,
    required this.createdAt,
    required this.appSchemaVersion,
    required this.appVersion,
    required this.segmentSize,
    required this.payloadBytes,
  });

  final String packageId;
  final String backupSetId;
  final DateTime createdAt;
  final int appSchemaVersion;
  final String appVersion;
  final int segmentSize;

  /// Bytes del payload cifrado. Debe cuadrar exactamente con el tamaño
  /// físico del archivo menos la zona de cabecera; si no, el paquete
  /// está truncado o manipulado.
  final int payloadBytes;

  static const algoritmoPayload = 'AES256-GCM-HKDF-SHA256-STREAMING';

  Map<String, dynamic> toJson() => {
    'containerVersion': ContenedorPortable.versionSoportada,
    'packageId': packageId,
    'backupSetId': backupSetId,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'appSchemaVersion': appSchemaVersion,
    'appVersion': appVersion,
    'segmentSize': segmentSize,
    'payloadBytes': payloadBytes,
    'payloadAlg': algoritmoPayload,
  };

  static CabeceraPublica? fromJson(Map<String, dynamic> json) {
    try {
      if (json['payloadAlg'] != algoritmoPayload) return null;
      final segmentSize = json['segmentSize'] as int;
      if (segmentSize < ContenedorPortable.segmentSizeMinimo) return null;
      if (segmentSize > ContenedorPortable.segmentSizeMaximo) return null;
      if (segmentSize & (segmentSize - 1) != 0) return null; // potencia de dos
      final payloadBytes = json['payloadBytes'] as int;
      if (payloadBytes < 0 || payloadBytes > ContenedorPortable.payloadMaximoBytes) return null;

      return CabeceraPublica(
        packageId: json['packageId'] as String,
        backupSetId: json['backupSetId'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        appSchemaVersion: json['appSchemaVersion'] as int,
        appVersion: json['appVersion'] as String,
        segmentSize: segmentSize,
        payloadBytes: payloadBytes,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Por qué un `.risegbkp` no se puede siquiera intentar abrir.
///
/// Todo esto se decide **antes** de derivar una clave, crear un archivo
/// o descifrar un byte.
enum MotivoContenedorInvalido {
  demasiadoCorto,
  magicIncorrecto,
  versionMasNueva,
  longitudesFueraDeRango,
  rellenoNoNulo,
  cabeceraIlegible,
  envolturasIlegibles,
  sinEnvolturas,
  demasiadasEnvolturas,
  tamanoInconsistente,
  dekWrapInvalido,
}

/// Lo que se puede saber de un paquete sin ninguna credencial.
class ContenedorLeido {
  const ContenedorLeido({
    required this.zonaCabecera,
    required this.cabecera,
    required this.envolturas,
    required this.dekWrapNonce,
    required this.dekWrapCifrado,
  });

  /// Los 8192 bytes tal como estaban en disco — el material del AAD.
  final Uint8List zonaCabecera;
  final CabeceraPublica cabecera;
  final List<EnvolturaMwk> envolturas;
  final Uint8List dekWrapNonce;
  final Uint8List dekWrapCifrado;

  bool get tieneEnvolturaDeFrase => envolturas.any((e) => e.tipo == TipoEnvoltura.frase);
  bool get tieneEnvolturaDeClaveRecuperacion => envolturas.any((e) => e.tipo == TipoEnvoltura.claveRecuperacion);
}

class ContenedorInvalido implements Exception {
  const ContenedorInvalido(this.motivo);
  final MotivoContenedorInvalido motivo;

  @override
  String toString() => 'ContenedorInvalido(${motivo.name})';
}

/// Lee y valida la zona de cabecera de un `.risegbkp`.
///
/// El orden de las comprobaciones es la parte importante, y va de lo
/// más barato y menos confiado a lo más caro: forma del archivo →
/// magic → versión → longitudes → relleno → JSON acotado → coherencia
/// con el tamaño real. Sólo después de todo eso tiene sentido hablar de
/// credenciales.
abstract final class LectorContenedor {
  /// Profundidad máxima del JSON de R1/R3. Ninguna estructura legítima
  /// pasa de 3; el límite existe para que un anidamiento absurdo no
  /// convierta el parseo en el ataque.
  static const profundidadMaximaJson = 6;

  static ContenedorLeido leer({required Uint8List zonaCabecera, required int tamanoArchivo}) {
    if (zonaCabecera.length != ContenedorPortable.zonaCabecera) {
      throw const ContenedorInvalido(MotivoContenedorInvalido.demasiadoCorto);
    }
    if (tamanoArchivo < ContenedorPortable.zonaCabecera + AesGcmHkdfStreaming.longitudCabecera) {
      throw const ContenedorInvalido(MotivoContenedorInvalido.demasiadoCorto);
    }

    for (var i = 0; i < ContenedorPortable.magicBytes.length; i++) {
      if (zonaCabecera[i] != ContenedorPortable.magicBytes[i]) {
        throw const ContenedorInvalido(MotivoContenedorInvalido.magicIncorrecto);
      }
    }

    final vista = ByteData.sublistView(zonaCabecera);
    final version = vista.getUint16(8);
    if (version > ContenedorPortable.versionSoportada) {
      throw const ContenedorInvalido(MotivoContenedorInvalido.versionMasNueva);
    }

    final coreLen = vista.getUint16(10);
    final wrapLen = vista.getUint16(12);
    if (coreLen == 0 || coreLen > ContenedorPortable.longitudCore) {
      throw const ContenedorInvalido(MotivoContenedorInvalido.longitudesFueraDeRango);
    }
    if (wrapLen == 0 || wrapLen > ContenedorPortable.longitudEnvolturas) {
      throw const ContenedorInvalido(MotivoContenedorInvalido.longitudesFueraDeRango);
    }
    if (vista.getUint16(14) != 0) {
      throw const ContenedorInvalido(MotivoContenedorInvalido.rellenoNoNulo);
    }

    _exigirCeros(zonaCabecera, ContenedorPortable.offsetCore + coreLen, ContenedorPortable.offsetDekWrap);
    _exigirCeros(zonaCabecera, ContenedorPortable.offsetEnvolturas + wrapLen, ContenedorPortable.offsetReservadoFinal);
    _exigirCeros(zonaCabecera, ContenedorPortable.offsetReservadoFinal, ContenedorPortable.zonaCabecera);
    // Los 4 bytes de reserva del propio R2.
    _exigirCeros(zonaCabecera, ContenedorPortable.offsetDekWrap + 60, ContenedorPortable.offsetDekWrap + 64);

    final cabecera = _leerCabecera(zonaCabecera, coreLen);
    final envolturas = _leerEnvolturas(zonaCabecera, wrapLen);

    if (cabecera.payloadBytes != tamanoArchivo - ContenedorPortable.zonaCabecera) {
      throw const ContenedorInvalido(MotivoContenedorInvalido.tamanoInconsistente);
    }

    return ContenedorLeido(
      zonaCabecera: zonaCabecera,
      cabecera: cabecera,
      envolturas: envolturas,
      dekWrapNonce: Uint8List.sublistView(
        zonaCabecera,
        ContenedorPortable.offsetDekWrap,
        ContenedorPortable.offsetDekWrap + ContenedorPortable.longitudNonce,
      ),
      dekWrapCifrado: Uint8List.sublistView(
        zonaCabecera,
        ContenedorPortable.offsetDekWrap + ContenedorPortable.longitudNonce,
        ContenedorPortable.offsetDekWrap + 60,
      ),
    );
  }

  static CabeceraPublica _leerCabecera(Uint8List zona, int coreLen) {
    final json = _decodificarJson(
      zona,
      ContenedorPortable.offsetCore,
      coreLen,
      MotivoContenedorInvalido.cabeceraIlegible,
    );
    final cabecera = CabeceraPublica.fromJson(json);
    if (cabecera == null) throw const ContenedorInvalido(MotivoContenedorInvalido.cabeceraIlegible);
    return cabecera;
  }

  static List<EnvolturaMwk> _leerEnvolturas(Uint8List zona, int wrapLen) {
    final json = _decodificarJson(
      zona,
      ContenedorPortable.offsetEnvolturas,
      wrapLen,
      MotivoContenedorInvalido.envolturasIlegibles,
    );
    final lista = json['wrappers'];
    if (lista is! List) throw const ContenedorInvalido(MotivoContenedorInvalido.envolturasIlegibles);
    if (lista.isEmpty) throw const ContenedorInvalido(MotivoContenedorInvalido.sinEnvolturas);
    if (lista.length > ContenedorPortable.maximoEnvolturas) {
      throw const ContenedorInvalido(MotivoContenedorInvalido.demasiadasEnvolturas);
    }

    final envolturas = <EnvolturaMwk>[];
    for (final elemento in lista) {
      if (elemento is! Map<String, dynamic>) {
        throw const ContenedorInvalido(MotivoContenedorInvalido.envolturasIlegibles);
      }
      final envoltura = EnvolturaMwk.fromJson(elemento);
      if (envoltura == null) throw const ContenedorInvalido(MotivoContenedorInvalido.envolturasIlegibles);
      envolturas.add(envoltura);
    }
    return envolturas;
  }

  static Map<String, dynamic> _decodificarJson(
    Uint8List zona,
    int offset,
    int longitud,
    MotivoContenedorInvalido motivo,
  ) {
    try {
      final texto = utf8.decode(Uint8List.sublistView(zona, offset, offset + longitud));
      final json = jsonDecode(texto);
      if (json is! Map<String, dynamic>) throw const ContenedorInvalido(MotivoContenedorInvalido.cabeceraIlegible);
      if (_profundidad(json) > profundidadMaximaJson) throw ContenedorInvalido(motivo);
      return json;
    } on ContenedorInvalido {
      rethrow;
    } catch (_) {
      throw ContenedorInvalido(motivo);
    }
  }

  static int _profundidad(Object? valor, [int actual = 1]) {
    if (actual > profundidadMaximaJson) return actual;
    if (valor is Map) {
      var maximo = actual;
      for (final v in valor.values) {
        final d = _profundidad(v, actual + 1);
        if (d > maximo) maximo = d;
        if (maximo > profundidadMaximaJson) return maximo;
      }
      return maximo;
    }
    if (valor is List) {
      var maximo = actual;
      for (final v in valor) {
        final d = _profundidad(v, actual + 1);
        if (d > maximo) maximo = d;
        if (maximo > profundidadMaximaJson) return maximo;
      }
      return maximo;
    }
    return actual;
  }

  static void _exigirCeros(Uint8List zona, int desde, int hasta) {
    for (var i = desde; i < hasta; i++) {
      if (zona[i] != 0) throw const ContenedorInvalido(MotivoContenedorInvalido.rellenoNoNulo);
    }
  }
}

String _hex(Uint8List bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List? _deHex(String? hex) {
  if (hex == null || hex.isEmpty || hex.length.isOdd) return null;
  final bytes = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < bytes.length; i++) {
    final valor = int.tryParse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    if (valor == null) return null;
    bytes[i] = valor;
  }
  return bytes;
}
