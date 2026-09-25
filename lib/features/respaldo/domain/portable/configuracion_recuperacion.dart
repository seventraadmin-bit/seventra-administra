import 'dart:convert';
import 'dart:typed_data';

import 'contenedor_portable.dart';
import 'sobre_portable.dart';

/// La configuración de recuperación portable de esta instalación
/// (Etapa 4D) — el "bloque de recuperación" que se copia tal cual en
/// cada `.risegbkp`.
///
/// **Nada de lo que hay aquí es secreto.** Son las dos envolturas de la
/// clave maestra del conjunto: una bajo la frase, otra bajo la clave de
/// recuperación. Quien lea esto obtiene exactamente lo mismo que quien
/// robe un USB con un respaldo, y sigue necesitando una de las dos
/// credenciales para abrir cualquiera.
///
/// Que exista esta indirección es lo que resuelve una contradicción que
/// parecía irreductible: la frase **no se guarda nunca**, la clave de
/// recuperación **tampoco**, y aun así cada respaldo nuevo puede llevar
/// ambas puertas — porque sus envolturas se calcularon una sola vez, al
/// configurar, y desde entonces se copian.
class ConfiguracionRecuperacion {
  const ConfiguracionRecuperacion({
    required this.backupSetId,
    required this.formatoVersion,
    required this.envolturaFrase,
    required this.envolturaClaveRecuperacion,
    required this.claveRecuperacionGeneradaEn,
  });

  /// 16 bytes de CSPRNG en hexadecimal. Identifica la familia
  /// criptográfica de respaldos, **no** la instalación: no deriva de
  /// `AppMetadata.installationId` ni tiene relación con él.
  final String backupSetId;

  final int formatoVersion;
  final EnvolturaMwk envolturaFrase;
  final EnvolturaMwk envolturaClaveRecuperacion;
  final DateTime claveRecuperacionGeneradaEn;

  static const formatoActual = 1;

  /// Las dos envolturas en el orden en que van a R3.
  List<EnvolturaMwk> get envolturas => [envolturaFrase, envolturaClaveRecuperacion];

  /// Abre la clave maestra con la frase, o `null` si no corresponde.
  ///
  /// Los datos asociados de una envoltura dependen de R1, y R1 es
  /// distinto en cada paquete. Por eso la configuración guarda las
  /// envolturas **tal como se escribieron al configurar**, y para
  /// abrirlas se reconstruye el mismo prefijo que se usó entonces: el de
  /// una zona de cabecera con sólo `backupSetId`. Ver
  /// [prefijoAadConfiguracion].
  Uint8List? abrirMwkConFrase({required String frase, required SobrePortable sobre}) {
    return sobre.abrirConFrase(
      envoltura: envolturaFrase,
      frase: frase,
      prefijoAad: prefijoAadConfiguracion(backupSetId),
    );
  }

  /// Abre la clave maestra con la clave de recuperación.
  Uint8List? abrirMwkConClaveRecuperacion({required Uint8List claveRecuperacion, required SobrePortable sobre}) {
    return sobre.abrirConClaveRecuperacion(
      envoltura: envolturaClaveRecuperacion,
      claveRecuperacion: claveRecuperacion,
      prefijoAad: prefijoAadConfiguracion(backupSetId),
    );
  }

  /// Datos asociados **estables** de las envolturas de la MWK.
  ///
  /// No pueden depender de R1 del paquete: entonces cada respaldo
  /// necesitaría reenvolver la MWK y haría falta la clave de
  /// recuperación cada vez, que es justo lo que este diseño evita. Se
  /// ata en cambio a lo único que define al conjunto —su `backupSetId`—
  /// más el magic y la versión del contenedor, así que una envoltura de
  /// otro conjunto no autentica aquí.
  static Uint8List prefijoAadConfiguracion(String backupSetId) {
    final etiqueta = utf8.encode('RISEG-BKP-v1 recovery-block $backupSetId');
    final salida = Uint8List(ContenedorPortable.magicBytes.length + 2 + etiqueta.length);
    salida
      ..setRange(0, ContenedorPortable.magicBytes.length, ContenedorPortable.magicBytes)
      ..setRange(ContenedorPortable.magicBytes.length + 2, salida.length, etiqueta);
    salida[ContenedorPortable.magicBytes.length + 1] = ContenedorPortable.versionSoportada;
    return salida;
  }

  String envolturaFraseJson() => jsonEncode(envolturaFrase.toJson());
  String envolturaClaveRecuperacionJson() => jsonEncode(envolturaClaveRecuperacion.toJson());

  /// Reconstruye la configuración desde lo persistido. `null` si alguna
  /// envoltura no se puede interpretar — una configuración a medias no
  /// se usa a medias.
  static ConfiguracionRecuperacion? desdePersistido({
    required String backupSetId,
    required int formatoVersion,
    required String envolturaFraseJson,
    required String envolturaClaveRecuperacionJson,
    required DateTime claveRecuperacionGeneradaEn,
  }) {
    try {
      final frase = EnvolturaMwk.fromJson(jsonDecode(envolturaFraseJson) as Map<String, dynamic>);
      final rk = EnvolturaMwk.fromJson(jsonDecode(envolturaClaveRecuperacionJson) as Map<String, dynamic>);
      if (frase == null || rk == null) return null;
      if (frase.tipo != TipoEnvoltura.frase) return null;
      if (rk.tipo != TipoEnvoltura.claveRecuperacion) return null;

      return ConfiguracionRecuperacion(
        backupSetId: backupSetId,
        formatoVersion: formatoVersion,
        envolturaFrase: frase,
        envolturaClaveRecuperacion: rk,
        claveRecuperacionGeneradaEn: claveRecuperacionGeneradaEn,
      );
    } catch (_) {
      return null;
    }
  }
}
