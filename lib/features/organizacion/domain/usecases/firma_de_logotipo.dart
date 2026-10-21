import 'dart:typed_data';

/// Qué se acepta como logotipo, **decidido por el CONTENIDO y no por la extensión**.
///
/// ## Por qué vive en su propio archivo
///
/// Esto estaba dentro de `logo_empresa_validacion.dart`, que **importa `dart:io`** para
/// `revisarLogo(String rutaArchivo)` —la función vecina, que abre un `File`—. Un solo
/// `import` de ese archivo rompe la build web, y la rompe **sin que nada en la pantalla
/// parezca estar mal**: es el mismo problema que obligó a crear `design_system_web.dart`.
///
/// En el navegador no hay sistema de archivos, así que `revisarLogo` no tiene sentido
/// allí; lo que los dos productos comparten es **la firma y los límites**, que son
/// aritmética pura sobre bytes.
///
/// ## Y es un AVISO TEMPRANO, nunca la garantía
///
/// Quien decide es el servidor: `FileValidation.DetectContentType` lee los mismos bytes
/// mágicos y compara el tipo **real** contra los que el uso admite. Esto existe para
/// que la persona se entere **antes** de subir 5 MB, no para autorizar nada — y por eso
/// los valores tienen que coincidir con los del catálogo (`platform_file_purpose`), no
/// ser más permisivos.
abstract final class FirmaDeLogotipo {
  /// PNG y JPEG. Deliberadamente no se admiten SVG ni WebP: el primero es XML
  /// ejecutable que habría que sanear, y el segundo no aporta nada que estos dos no
  /// cubran para un logotipo.
  ///
  /// **Son los mismos dos del catálogo del servidor** —`ARRAY['image/png',
  /// 'image/jpeg']` en la 0010—, y tienen que seguir siéndolo: ofrecer aquí un tipo que
  /// allá se rechaza sería prometer una subida que va a fallar.
  static const Set<String> tiposAceptados = {'image/png', 'image/jpeg'};

  /// 5 MiB, **el mismo `max_bytes` del catálogo**.
  ///
  /// Un logotipo razonable pesa dos órdenes de magnitud menos; el límite está para que
  /// nadie meta una fotografía de cámara por error.
  static const int tamanoMaximoBytes = 5 * 1024 * 1024;

  /// `image/png` o `image/jpeg` según **la firma real** del archivo, o `null` si no es
  /// ninguno de los dos.
  ///
  /// ```
  /// PNG:  89 50 4E 47 0D 0A 1A 0A
  /// JPEG: FF D8 FF
  /// ```
  ///
  /// **Por qué el contenido y no el nombre:** un archivo puede llamarse `.png` sin
  /// serlo, y el diálogo del sistema se puede sortear escribiendo el nombre a mano.
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

    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'image/jpeg';
    }

    return null;
  }

  /// Qué le falta a estos bytes para ser un logotipo, **o nulo si están bien**.
  ///
  /// Devuelve el motivo ya redactado porque es lo único que la pantalla va a hacer con
  /// él, y así el texto del límite —«5 MB»— sale de la misma constante que lo impone.
  static String? porQueNoSirve(Uint8List bytes) {
    if (bytes.isEmpty) return 'El archivo está vacío.';

    if (bytes.length > tamanoMaximoBytes) {
      final mb = tamanoMaximoBytes ~/ (1024 * 1024);

      return 'El logotipo no puede pasar de $mb MB, y éste pesa '
          '${(bytes.length / (1024 * 1024)).toStringAsFixed(1)} MB.';
    }

    return tipoReal(bytes) == null
        ? 'El archivo no es un PNG ni un JPEG. Puede llamarse así sin serlo: '
              'lo que se revisa es su contenido.'
        : null;
  }
}
