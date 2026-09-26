import 'dart:io';
import 'dart:typed_data';

import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/empresa_repository.dart';

sealed class AdoptarLogoHeredadoResultado {}

/// Se adoptó: el logotipo que antes era un asset del producto pasa a ser un
/// adjunto de la Empresa.
class LogoHeredadoAdoptado extends AdoptarLogoHeredadoResultado {
  LogoHeredadoAdoptado(this.empresa);
  final EmpresaData empresa;
}

/// No había nada que hacer. Es el caso normal a partir del segundo arranque.
class LogoHeredadoNoAplica extends AdoptarLogoHeredadoResultado {
  LogoHeredadoNoAplica(this.motivo);
  final String motivo;
}

class LogoHeredadoFallo extends AdoptarLogoHeredadoResultado {
  LogoHeredadoFallo(this.mensaje);
  final String mensaje;
}

/// Convierte el logotipo heredado —el que hasta la Etapa 5B.1 vivía como
/// asset del producto— en un adjunto real de la Empresa (Etapa 5B.2).
///
/// **Por qué existe.** Antes de 5B.2 la aplicación dibujaba
/// `assets/images/logo.png` en los documentos de la Empresa. Ese archivo es
/// el escudo de RISEG: pertenece a la Empresa, no al producto. Si se
/// quitara sin más, quien ya tiene la aplicación instalada perdería su
/// logotipo de un día para otro y tendría que volver a cargarlo a mano.
///
/// **Lo que NO es.** No es una regla permanente ni un caso especial de
/// RISEG. No pregunta por el nombre ni por el código de la Empresa: adopta
/// el logotipo heredado de *cualquier* instalación que venga de una versión
/// anterior, y en una instalación nueva simplemente no encuentra nada que
/// adoptar. Cuando ya no queden instalaciones antiguas, este caso de uso se
/// puede retirar entero sin tocar nada más.
///
/// **Por qué es idempotente sin necesitar esquema nuevo.** La marca de que
/// ya se hizo no es una bandera nueva, es el propio historial: en cuanto
/// existe un adjunto de logotipo para esa Empresa —**vigente o archivado**—
/// la adopción no se repite. Eso hace que quitar el logotipo a propósito sea
/// una decisión que se respeta, en vez de algo que el siguiente arranque
/// deshace.
class AdoptarLogoHeredadoUseCase {
  AdoptarLogoHeredadoUseCase(this._repository, this._storage, this._leerAssetHeredado);

  final EmpresaRepository _repository;
  final AttachmentStorage _storage;

  /// Los bytes del asset heredado. Se inyecta porque leer un asset de
  /// Flutter es cosa de la capa de presentación (`rootBundle`), y este caso
  /// de uso es dominio puro.
  final Future<Uint8List?> Function() _leerAssetHeredado;

  /// Nombre con el que queda registrado. Describe su procedencia, que es lo
  /// que alguien querrá entender dentro de dos años al verlo en la lista de
  /// adjuntos.
  static const nombreArchivoHeredado = 'logo-heredado.png';

  Future<AdoptarLogoHeredadoResultado> ejecutar(String empresaId) async {
    try {
      final empresa = await _repository.obtenerPorId(empresaId);
      if (empresa == null) return LogoHeredadoNoAplica('la Empresa no existe');

      if (empresa.logoAttachmentId != null) {
        return LogoHeredadoNoAplica('la Empresa ya tiene logotipo');
      }

      final historial = await _repository.historialLogos(empresaId);
      if (historial.isNotEmpty) {
        // Hubo logotipo y ya no lo hay: alguien lo quitó. Se respeta.
        return LogoHeredadoNoAplica('ya hubo un logotipo; no se repone solo');
      }

      final bytes = await _leerAssetHeredado();
      if (bytes == null || bytes.isEmpty) {
        return LogoHeredadoNoAplica('no hay logotipo heredado que adoptar');
      }

      // `AttachmentStorage` copia de archivo a archivo, así que los bytes
      // del asset pasan primero por un temporal que se borra enseguida.
      final temporal = File(
        '${Directory.systemTemp.createTempSync('logo_heredado_').path}${Platform.pathSeparator}$nombreArchivoHeredado',
      );
      try {
        await temporal.writeAsBytes(bytes, flush: true);

        final guardado = await _storage.guardar(
          ownerId: empresaId,
          categoria: categoriaLogo,
          sourceFilePath: temporal.path,
          originalFileName: nombreArchivoHeredado,
        );
        final adjunto = await _repository.adjuntarLogo(
          empresaId: empresaId,
          originalFileName: nombreArchivoHeredado,
          storedFileName: guardado.storedFileName,
          path: guardado.path,
          mimeType: 'image/png',
          sizeBytes: guardado.sizeBytes,
        );
        final actualizada = await _repository.actualizarLogo(empresaId: empresaId, attachmentId: adjunto.id);
        return LogoHeredadoAdoptado(actualizada);
      } finally {
        try {
          temporal.parent.deleteSync(recursive: true);
        } on FileSystemException {
          // El temporal del sistema se limpia solo; no vale la pena que un
          // borrado fallido tumbe una adopción que ya salió bien.
        }
      }
    } catch (e) {
      return LogoHeredadoFallo(e.toString());
    }
  }
}
