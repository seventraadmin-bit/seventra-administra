import 'dart:io';
import 'dart:typed_data';

import '../../../../core/archivos/firma_de_logotipo.dart';

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
/// ⚠️ **LA FIRMA Y LOS LÍMITES YA NO VIVEN AQUÍ: viven en [FirmaDeLogotipo]**, y esta
/// clase sólo los reexpone para que el escritorio siga nombrándolos como siempre.
///
/// Se movieron el 21 de octubre de 2026 porque **la web los necesita** —el logotipo de
/// la empresa se sube desde el navegador— y este archivo importa `dart:io` para
/// `revisarLogo`, así que un solo `import` rompía la build web.
abstract final class LogoEmpresaValidacion {
  static const formatosAceptados = FirmaDeLogotipo.tiposAceptados;

  static const tamanoMaximoBytes = FirmaDeLogotipo.tamanoMaximoBytes;

  static String? tipoReal(Uint8List bytes) => FirmaDeLogotipo.tipoReal(bytes);
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
