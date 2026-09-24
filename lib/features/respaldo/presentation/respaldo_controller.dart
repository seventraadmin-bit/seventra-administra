import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../domain/manifest_respaldo.dart';
import '../domain/rutas_paquete.dart';
import '../domain/usecases/crear_respaldo_usecase.dart';
import '../domain/usecases/eliminar_respaldo_usecase.dart';
import '../domain/usecases/preparar_restauracion_usecase.dart';
import '../domain/usecases/validar_paquete_respaldo_usecase.dart';
import '../respaldo_providers.dart';
import 'respaldo_state.dart';

part 'respaldo_controller.g.dart';

/// Controlador de la pantalla de Respaldo y restauración (exclusiva del
/// Usuario Maestro). Lista lo que existe en `AppPaths.backupsDir` y
/// delega crear/restaurar/verificar/eliminar a los providers
/// autorizados, que exigen Maestro con el mismo mecanismo que la
/// eliminación física — este controlador nunca decide por su cuenta si
/// la acción está permitida.
@riverpod
class RespaldoController extends _$RespaldoController {
  @override
  RespaldoState build() {
    Future.microtask(_cargarLista);
    return const RespaldoState();
  }

  Future<void> _cargarLista() async {
    final dir = Directory(ref.read(backupsDirProvider));
    final archivos = <ArchivoRespaldo>[];
    if (dir.existsSync()) {
      for (final entidad in dir.listSync()) {
        if (entidad is! File || !entidad.path.endsWith('.zip')) continue;
        final stat = entidad.statSync();
        final manifiesto = await _leerManifiestoLigero(entidad);
        archivos.add(
          ArchivoRespaldo(
            nombre: p.basename(entidad.path),
            ruta: entidad.path,
            tamanoBytes: stat.size,
            modificado: stat.modified,
            tipo: manifiesto?.tipo,
            formatVersion: manifiesto?.formatVersion,
            appSchemaVersion: manifiesto?.appSchemaVersion,
            archivosAdjuntos: manifiesto?.archivosAdjuntos,
            // Un paquete cuyo manifiesto ni siquiera se puede leer ya se
            // sabe dañado sin necesidad de verificarlo entero.
            integridad: manifiesto == null ? EstadoIntegridad.invalido : EstadoIntegridad.sinVerificar,
          ),
        );
      }
      archivos.sort((a, b) => b.modificado.compareTo(a.modificado));
    }
    state = state.copyWith(cargando: false, respaldos: archivos);
  }

  /// Lee **sólo** `manifest.json` del `.zip`, sin extraer nada más.
  ///
  /// Es lo que permite que la lista muestre tipo, formato y esquema sin
  /// pagar el precio de abrir paquetes de gigabytes cada vez que se
  /// pinta la pantalla. La verificación de verdad es una acción aparte.
  Future<ManifestRespaldo?> _leerManifiestoLigero(File zip) async {
    InputFileStream? entrada;
    try {
      entrada = InputFileStream(zip.path);
      final archivo = ZipDecoder().decodeBuffer(entrada);
      for (final entry in archivo) {
        if (entry.name != RutasPaquete.nombreManifiesto || !entry.isFile) continue;
        final json = jsonDecode(utf8.decode(entry.content as List<int>)) as Map<String, dynamic>;
        return ManifestRespaldo.fromJson(json);
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      await entrada?.close();
    }
  }

  Future<void> recargar() => _cargarLista();

  Future<ResultadoCrearRespaldo> crearRespaldo(String destinoZip) async {
    state = state.copyWith(procesando: true);
    final resultado = await ref.read(crearRespaldoAutorizadoProvider)(destinoZip: destinoZip);
    state = state.copyWith(procesando: false);
    if (resultado is RespaldoCreado) await _cargarLista();
    return resultado;
  }

  Future<ResultadoPrepararRestauracion> restaurar(String rutaZip) async {
    state = state.copyWith(procesando: true);
    final resultado = await ref.read(restaurarAutorizadoProvider)(rutaZip: rutaZip);
    state = state.copyWith(procesando: false);
    return resultado;
  }

  /// Verificación completa con el validador canónico — el mismo que
  /// usaría Restaurar. El resultado se recuerda en la fila, para no
  /// obligar a repetirlo.
  Future<ResultadoValidarPaqueteRespaldo> verificar(ArchivoRespaldo archivo) async {
    state = state.copyWith(procesando: true);
    final resultado = await ref.read(verificarRespaldoAutorizadoProvider)(rutaZip: archivo.ruta);
    final nuevoEstado = switch (resultado) {
      PaqueteRespaldoValido(:final verificacionCompleta) =>
        verificacionCompleta ? EstadoIntegridad.verificado : EstadoIntegridad.limitada,
      _ => EstadoIntegridad.invalido,
    };
    if (resultado is PaqueteRespaldoValido) {
      await resultado.staging.delete(recursive: true);
    }
    state = state.copyWith(
      procesando: false,
      respaldos: [for (final r in state.respaldos) r.ruta == archivo.ruta ? r.copyWith(integridad: nuevoEstado) : r],
    );
    return resultado;
  }

  Future<ResultadoEliminarRespaldo> eliminar(ArchivoRespaldo archivo) async {
    final resultado = await ref.read(eliminarRespaldoAutorizadoProvider)(
      rutaZip: archivo.ruta,
      esPreventivo: archivo.tipo == TipoRespaldo.preventivo,
    );
    if (resultado is RespaldoEliminado) await _cargarLista();
    return resultado;
  }

  Future<bool> abrirUbicacion(ArchivoRespaldo archivo) {
    return ref.read(abridorUbicacionProvider).mostrarArchivo(archivo.ruta);
  }
}
