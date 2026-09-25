import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// Derivación de claves de envoltura para el respaldo portable
/// (Etapa 4D).
///
/// Dos caminos con reglas deliberadamente distintas:
///
///  * **Frase** → Argon2id. Un KDF caro existe para compensar la poca
///    entropía de algo que una persona recuerda.
///  * **Clave de recuperación** → HKDF-SHA256. Son 160 bits de un
///    CSPRNG: no hay entropía baja que compensar, y ralentizarlo sólo
///    castigaría a quien está recuperando una emergencia. El HKDF está
///    ahí por separación de dominio, **nunca para "fortalecer"** algo
///    que ya es fuerte.

/// Parámetros de Argon2id tal como viajan dentro de una envoltura.
///
/// Van en el paquete, no en una configuración global: un respaldo de
/// 2026 y uno de 2030 con parámetros distintos conviven sin que ninguno
/// rompa al otro, porque cada uno dice los suyos.
class ParametrosArgon2id {
  const ParametrosArgon2id({
    required this.memoriaKiB,
    required this.iteraciones,
    required this.paralelismo,
    required this.salt,
    this.version = versionSoportada,
  });

  /// `m`, en KiB — la unidad del propio Argon2.
  final int memoriaKiB;

  /// `t`.
  final int iteraciones;

  /// `p`.
  final int paralelismo;

  final Uint8List salt;

  /// Sólo se acepta `0x13` (Argon2 v1.3).
  final int version;

  static const versionSoportada = 0x13;
  static const longitudSalida = 32;

  /// Valores por omisión de **esta versión** de RISEG ONE, elegidos tras
  /// medir Argon2id compilado en AOT sobre Windows (Etapa 4D).
  ///
  /// La regla mecánica del benchmark daba 128 MiB / t=4, pero se midió
  /// en una máquina muy rápida; en una PC administrativa varias veces
  /// más lenta esa combinación se saldría del presupuesto justo durante
  /// una recuperación de emergencia. Se eligió con margen deliberado.
  static const memoriaPorOmisionKiB = 64 * 1024;
  static const iteracionesPorOmision = 3;
  static const paralelismoPorOmision = 1;

  int get memoriaMiB => memoriaKiB ~/ 1024;
}

/// Por qué un descriptor de KDF no se acepta.
///
/// Se comprueba **antes** de derivar nada: los parámetros llegan dentro
/// de un archivo ajeno y hay que leerlos para poder autenticarlo, así
/// que en ese momento todavía no se puede confiar en ellos.
enum MotivoKdfRechazado {
  versionNoSoportada,
  memoriaFueraDeRango,
  iteracionesFueraDeRango,
  paralelismoFueraDeRango,
  saltFueraDeRango,
  costeCombinadoExcesivo,
}

/// Límites de aceptación, independientes de los valores por omisión.
///
/// Son más anchos que los defaults a propósito: permiten leer un
/// respaldo creado por una versión futura con parámetros más altos, sin
/// permitir que alguien meta `m = 4 TB` y logre que RISEG ONE intente
/// reservarlo.
///
/// El mínimo importa tanto como el máximo. Un paquete que declare
/// `m = 1 MiB, t = 1` es un intento de degradación o viene de una
/// versión rota; aceptarlo sería proteger el contenido con algo que
/// cualquiera puede romper.
abstract final class LimitesArgon2id {
  static const memoriaMinimaKiB = 8 * 1024; // 8 MiB
  static const memoriaMaximaKiB = 1024 * 1024; // 1 GiB
  static const iteracionesMinimas = 1;
  static const iteracionesMaximas = 10;
  static const paralelismoMinimo = 1;
  static const paralelismoMaximo = 4;
  static const saltMinimo = 16;
  static const saltMaximo = 32;

  /// Tope al trabajo total. Sin él, `1 GiB × 10 pasadas` seguiría
  /// dentro de los rangos individuales y bastaría para colgar el
  /// equipo con un archivo de unos pocos KiB.
  static const costeCombinadoMaximo = 2048; // m_MiB × t

  static MotivoKdfRechazado? validar(ParametrosArgon2id p) {
    if (p.version != ParametrosArgon2id.versionSoportada) return MotivoKdfRechazado.versionNoSoportada;
    if (p.memoriaKiB < memoriaMinimaKiB || p.memoriaKiB > memoriaMaximaKiB) {
      return MotivoKdfRechazado.memoriaFueraDeRango;
    }
    if (p.iteraciones < iteracionesMinimas || p.iteraciones > iteracionesMaximas) {
      return MotivoKdfRechazado.iteracionesFueraDeRango;
    }
    if (p.paralelismo < paralelismoMinimo || p.paralelismo > paralelismoMaximo) {
      return MotivoKdfRechazado.paralelismoFueraDeRango;
    }
    if (p.salt.length < saltMinimo || p.salt.length > saltMaximo) return MotivoKdfRechazado.saltFueraDeRango;
    if (p.memoriaMiB * p.iteraciones > costeCombinadoMaximo) return MotivoKdfRechazado.costeCombinadoExcesivo;
    return null;
  }
}

/// El descriptor de KDF venía fuera de los límites aceptables.
class ParametrosKdfRechazados implements Exception {
  const ParametrosKdfRechazados(this.motivo);
  final MotivoKdfRechazado motivo;

  @override
  String toString() => 'ParametrosKdfRechazados(${motivo.name})';
}

/// Argon2id, detrás de una interfaz para poder **demostrar el orden** en
/// las pruebas: que un descriptor hostil se rechaza sin llegar a
/// invocar al generador. Comprobar sólo que "lanza una excepción" no
/// distingue entre rechazar antes o después de reservar un gigabyte.
abstract class GeneradorArgon2 {
  Uint8List derivar({required Uint8List secreto, required ParametrosArgon2id parametros});
}

class GeneradorArgon2PointyCastle implements GeneradorArgon2 {
  const GeneradorArgon2PointyCastle();

  @override
  Uint8List derivar({required Uint8List secreto, required ParametrosArgon2id parametros}) {
    final generador =
        Argon2BytesGenerator()..init(
          Argon2Parameters(
            Argon2Parameters.ARGON2_id,
            parametros.salt,
            version: parametros.version,
            iterations: parametros.iteraciones,
            // `memory` va en KiB. Cuidado: pasar también `memoryPowerOf2`
            // haría que éste se ignorara — tiene precedencia.
            memory: parametros.memoriaKiB,
            lanes: parametros.paralelismo,
            desiredKeyLength: ParametrosArgon2id.longitudSalida,
          ),
        );
    final salida = Uint8List(ParametrosArgon2id.longitudSalida);
    generador.deriveKey(secreto, 0, salida, 0);
    return salida;
  }
}

/// Deriva las claves que envuelven la clave maestra del conjunto.
class DerivadorKek {
  const DerivadorKek({GeneradorArgon2 argon2 = const GeneradorArgon2PointyCastle()}) : _argon2 = argon2;

  final GeneradorArgon2 _argon2;

  /// Contexto fijo del HKDF de la clave de recuperación. Que sea
  /// distinto de cualquier otro uso impide reutilizar ese material por
  /// accidente en otro propósito, hoy o dentro de tres etapas.
  static const contextoClaveRecuperacion = 'RISEG-BKP-v1 recovery-key KEK';

  /// KEK a partir de la frase. **Valida los parámetros primero**; si no
  /// pasan, lanza sin haber tocado Argon2.
  Uint8List desdeFrase({required String frase, required ParametrosArgon2id parametros}) {
    final motivo = LimitesArgon2id.validar(parametros);
    if (motivo != null) throw ParametrosKdfRechazados(motivo);

    // UTF-8 explícito, nunca codeUnits: una frase con ñ o acentos — lo
    // normal aquí — se codificaría en UTF-16 y produciría otra KEK.
    return _argon2.derivar(secreto: Uint8List.fromList(utf8.encode(frase)), parametros: parametros);
  }

  /// KEK a partir de la clave de recuperación: HKDF-SHA256 sobre los 20
  /// bytes reales, nunca sobre el texto con guiones.
  Uint8List desdeClaveRecuperacion({required Uint8List claveRecuperacion, required Uint8List salt}) {
    final hkdf = HKDFKeyDerivator(SHA256Digest())..init(
      HkdfParameters(
        claveRecuperacion,
        ParametrosArgon2id.longitudSalida,
        salt,
        Uint8List.fromList(utf8.encode(contextoClaveRecuperacion)),
      ),
    );
    final salida = Uint8List(ParametrosArgon2id.longitudSalida);
    hkdf.deriveKey(Uint8List(0), 0, salida, 0);
    return salida;
  }
}
