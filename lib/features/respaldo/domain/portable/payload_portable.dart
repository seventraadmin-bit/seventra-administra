import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Contenido privado de un `.risegbkp` — lo que vive **dentro** del
/// cifrado autenticado (Etapa 4D).
///
/// ```
/// offset  long.        campo
/// 0       8            MAGIC "RISEGPL1"
/// 8       2            payloadVersion (uint16 BE) = 1
/// 10      4            metaLen (uint32 BE)
/// 14      8            respaldoBytes (uint64 BE)
/// 22      metaLen      meta JSON UTF-8 (registro de clave + contexto)
/// 22+…    respaldoBytes  paquete de respaldo v2 de la Etapa 4B, tal cual
/// ```
///
/// **Se versiona por separado del contenedor** a propósito: el formato
/// del sobre criptográfico y el de su contenido evolucionan por razones
/// distintas, y atarlos obligaría a subir `containerVersion` —y a
/// arriesgar que un lector viejo rechace el archivo— por un cambio que
/// sólo afecta a lo de dentro.
///
/// El respaldo v2 viaja **byte por byte como lo produjo 4B**: ni se
/// reempaqueta ni se duplica. Así el validador canónico funciona sin
/// cambiar una línea, y lo que se restaura es exactamente lo que 4B
/// sabe restaurar.
///
/// Aquí dentro está lo que **no puede** salir a R1/R2/R3: el registro de
/// clave AES y cualquier metadata que identifique a la empresa.
abstract final class PayloadPortable {
  static const magic = 'RISEGPL1';
  static final magicBytes = Uint8List.fromList(utf8.encode(magic));

  static const versionSoportada = 1;
  static const longitudFija = 22;

  /// Tope del bloque de metadata. Es contenido ya autenticado cuando se
  /// lee, pero acotarlo evita que un fallo de escritura produzca una
  /// asignación absurda.
  static const metaMaximaBytes = 64 * 1024;

  /// Escribe el payload en claro a [destino]: cabecera, metadata y el
  /// respaldo v2 copiado en trozos.
  ///
  /// Nunca carga el respaldo en memoria: se copia por bloques, igual que
  /// después se cifrará por segmentos.
  static Future<void> construir({
    required File destino,
    required File respaldoV2,
    required RegistroClaveAes clave,
    required String backupSetId,
    required String appVersion,
    required DateTime createdAt,
  }) async {
    final meta = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'payloadVersion': versionSoportada,
          'backupSetId': backupSetId,
          'appVersion': appVersion,
          'createdAt': createdAt.toUtc().toIso8601String(),
          'claveAes': clave.toJson(),
        }),
      ),
    );
    if (meta.length > metaMaximaBytes) {
      throw StateError('La metadata privada del payload no cabe en $metaMaximaBytes bytes.');
    }

    final respaldoBytes = await respaldoV2.length();
    final salida = await destino.open(mode: FileMode.write);
    try {
      final cabecera = Uint8List(longitudFija)..setRange(0, magicBytes.length, magicBytes);
      ByteData.sublistView(cabecera)
        ..setUint16(8, versionSoportada)
        ..setUint32(10, meta.length)
        ..setUint64(14, respaldoBytes);
      await salida.writeFrom(cabecera);
      await salida.writeFrom(meta);

      final entrada = await respaldoV2.open();
      try {
        const bloque = 1 << 20;
        while (true) {
          final trozo = await entrada.read(bloque);
          if (trozo.isEmpty) break;
          await salida.writeFrom(trozo);
        }
      } finally {
        await entrada.close();
      }
    } finally {
      await salida.close();
    }
  }

  /// Lee la metadata y extrae el respaldo v2 a [respaldoDestino].
  ///
  /// Lanza [PayloadPrivadoInvalido] si la forma no es la esperada. En ese
  /// punto el contenido **ya está autenticado** —el AEAD pasó—, así que
  /// un fallo aquí significa un paquete creado por otra versión o un
  /// error nuestro al escribirlo, nunca manipulación externa.
  static Future<PayloadLeido> extraer({required File payload, required File respaldoDestino}) async {
    final entrada = await payload.open();
    try {
      final total = await entrada.length();
      if (total < longitudFija) throw const PayloadPrivadoInvalido('más corto que su cabecera');

      final cabecera = await entrada.read(longitudFija);
      for (var i = 0; i < magicBytes.length; i++) {
        if (cabecera[i] != magicBytes[i]) throw const PayloadPrivadoInvalido('magic del payload incorrecto');
      }
      final vista = ByteData.sublistView(cabecera);
      final version = vista.getUint16(8);
      if (version > versionSoportada) {
        throw const PayloadPrivadoInvalido('payload de una versión más nueva');
      }
      final metaLen = vista.getUint32(10);
      final respaldoBytes = vista.getUint64(14);
      if (metaLen == 0 || metaLen > metaMaximaBytes) throw const PayloadPrivadoInvalido('metadata fuera de rango');
      if (longitudFija + metaLen + respaldoBytes != total) {
        throw const PayloadPrivadoInvalido('las longitudes declaradas no cuadran con el payload');
      }

      final Map<String, dynamic> meta;
      try {
        meta = jsonDecode(utf8.decode(await entrada.read(metaLen))) as Map<String, dynamic>;
      } catch (_) {
        throw const PayloadPrivadoInvalido('metadata ilegible');
      }

      final clave = RegistroClaveAes.fromJson(meta['claveAes']);
      if (clave == null) throw const PayloadPrivadoInvalido('registro de clave ausente o inválido');

      final salida = await respaldoDestino.open(mode: FileMode.write);
      try {
        var restante = respaldoBytes;
        const bloque = 1 << 20;
        while (restante > 0) {
          final trozo = await entrada.read(restante < bloque ? restante : bloque);
          if (trozo.isEmpty) throw const PayloadPrivadoInvalido('el respaldo interno acaba antes de lo declarado');
          restante -= trozo.length;
          await salida.writeFrom(trozo);
        }
      } finally {
        await salida.close();
      }

      return PayloadLeido(
        payloadVersion: version,
        backupSetId: meta['backupSetId'] as String? ?? '',
        appVersion: meta['appVersion'] as String? ?? '',
        claveAes: clave,
      );
    } finally {
      await entrada.close();
    }
  }
}

/// La clave AES de RISEG ONE, viajando dentro del payload cifrado.
///
/// Es lo único del paquete que convierte una restauración en
/// *recuperación total*: sin ella, la base llega completa pero Bóveda,
/// Telefonía y el Portal del Cliente quedan ilegibles en el equipo
/// nuevo.
///
/// [keyId] identifica **este registro**, para poder comparar la clave
/// del paquete con la instalada y hacer idempotente la promoción durante
/// una restauración. **No** significa que los textos cifrados existentes
/// lleven ese identificador: siguen siendo `aesgcm$1$…` y no se tocan.
/// La rotación real es otra etapa.
class RegistroClaveAes {
  const RegistroClaveAes({required this.keyId, required this.clave, this.algoritmo = algoritmoEsperado});

  /// 16 bytes de CSPRNG en hexadecimal.
  final String keyId;

  /// Los 32 bytes de la clave.
  final Uint8List clave;

  final String algoritmo;

  static const algoritmoEsperado = 'aes-256-gcm';
  static const longitudClave = 32;

  Map<String, dynamic> toJson() => {'keyId': keyId, 'alg': algoritmo, 'key': _hex(clave)};

  /// `null` si el registro no sirve. Nunca lanza.
  static RegistroClaveAes? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final keyId = json['keyId'];
    final alg = json['alg'];
    final clave = _deHex(json['key']);
    if (keyId is! String || keyId.length != 32) return null;
    if (alg != algoritmoEsperado) return null;
    if (clave == null || clave.length != longitudClave) return null;
    return RegistroClaveAes(keyId: keyId, clave: clave, algoritmo: alg as String);
  }
}

/// Lo que se supo del payload tras extraerlo.
class PayloadLeido {
  const PayloadLeido({
    required this.payloadVersion,
    required this.backupSetId,
    required this.appVersion,
    required this.claveAes,
  });

  final int payloadVersion;
  final String backupSetId;
  final String appVersion;
  final RegistroClaveAes claveAes;
}

class PayloadPrivadoInvalido implements Exception {
  const PayloadPrivadoInvalido(this.detalle);

  /// Técnico, para registro. Nunca se muestra tal cual.
  final String detalle;

  @override
  String toString() => 'PayloadPrivadoInvalido($detalle)';
}

String _hex(Uint8List bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List? _deHex(Object? valor) {
  if (valor is! String || valor.isEmpty || valor.length.isOdd) return null;
  final bytes = Uint8List(valor.length ~/ 2);
  for (var i = 0; i < bytes.length; i++) {
    final b = int.tryParse(valor.substring(i * 2, i * 2 + 2), radix: 16);
    if (b == null) return null;
    bytes[i] = b;
  }
  return bytes;
}
