import 'dart:io';
import 'dart:typed_data';

/// Qué se acepta como logotipo de una Empresa (Etapa 5B.2).
///
/// El proyecto **no tenía** ninguna validación de imagen: `AttachmentStorage`
/// copia el archivo que le den, y el logotipo de Cliente se conforma con que
/// el selector del sistema esté puesto en `FileType.image`. Eso no basta:
/// el diálogo del sistema se puede sortear escribiendo el nombre a mano, y
/// un archivo puede llamarse `.png` sin serlo.
///
/// Aquí se comprueba el **contenido**, no la extensión, leyendo la firma de
/// los primeros bytes. No hace falta ninguna dependencia nueva.
abstract final class LogoEmpresaValidacion {
  /// PNG y JPEG. Deliberadamente no se admiten SVG ni WebP: el primero es
  /// XML ejecutable que habría que sanear, y el segundo no aporta nada que
  /// estos dos no cubran para un logotipo.
  static const formatosAceptados = {'image/png', 'image/jpeg'};

  /// 5 MiB. Un logotipo razonable pesa dos órdenes de magnitud menos; el
  /// límite está para que nadie meta una fotografía de cámara por error y
  /// la arrastre después en cada respaldo. Como referencia, el escudo
  /// heredado de RISEG pesa 2.6 MB y entra.
  static const tamanoMaximoBytes = 5 * 1024 * 1024;

  /// `image/png` o `image/jpeg` según la firma real del archivo, o `null`
  /// si no es ninguno de los dos.
  ///
  /// PNG:  `89 50 4E 47 0D 0A 1A 0A`
  /// JPEG: empieza con `FF D8 FF` y termina en `FF D9`
  static String? tipoReal(Uint8List bytes) {
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      return 'image/png';
    }
    if (bytes.length >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
      return 'image/jpeg';
    }
    return null;
  }
}

/// El veredicto sobre un archivo candidato.
sealed class RevisionLogo {}

class LogoAceptado extends RevisionLogo {
  LogoAceptado({required this.mimeType, required this.bytes});

  /// Deducido del contenido, nunca de la extensión del nombre.
  final String mimeType;
  final int bytes;
}

class LogoNoExiste extends RevisionLogo {}

class LogoDemasiadoGrande extends RevisionLogo {
  LogoDemasiadoGrande({required this.bytes, required this.maximoBytes});
  final int bytes;
  final int maximoBytes;
}

class LogoFormatoNoAceptado extends RevisionLogo {}

class LogoIlegible extends RevisionLogo {
  LogoIlegible(this.detalle);
  final String detalle;
}

/// Revisa un archivo candidato a logotipo **antes** de copiarlo a ningún
/// sitio: si no pasa, el almacén de adjuntos ni se entera.
Future<RevisionLogo> revisarLogo(String rutaArchivo) async {
  final archivo = File(rutaArchivo);
  if (!archivo.existsSync()) return LogoNoExiste();

  try {
    final bytes = await archivo.length();
    if (bytes > LogoEmpresaValidacion.tamanoMaximoBytes) {
      return LogoDemasiadoGrande(bytes: bytes, maximoBytes: LogoEmpresaValidacion.tamanoMaximoBytes);
    }
    if (bytes == 0) return LogoFormatoNoAceptado();

    // Basta la cabecera para reconocer la firma; no se carga el archivo
    // entero en memoria sólo para mirar ocho bytes.
    final cabecera = await archivo.openRead(0, 16).expand((trozo) => trozo).toList();
    final tipo = LogoEmpresaValidacion.tipoReal(Uint8List.fromList(cabecera));
    if (tipo == null) return LogoFormatoNoAceptado();

    return LogoAceptado(mimeType: tipo, bytes: bytes);
  } on FileSystemException catch (e) {
    return LogoIlegible(e.osError?.message ?? e.message);
  }
}
