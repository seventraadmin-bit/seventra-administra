import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../domain/usecases/crear_respaldo_usecase.dart';
import '../domain/usecases/preparar_restauracion_usecase.dart';
import '../respaldo_providers.dart';
import 'respaldo_state.dart';

part 'respaldo_controller.g.dart';

/// Controlador de la pantalla de Respaldo y restauración (Etapa 14C,
/// exclusiva del Usuario Maestro). Solo lista lo que ya existe en
/// `AppPaths.backupsDir` y delega crear/restaurar a los providers
/// autorizados (`crearRespaldoAutorizadoProvider`/
/// `restaurarAutorizadoProvider`, que exigen Maestro con el mismo
/// mecanismo que la eliminación física de la Etapa 11D) — este
/// controlador nunca decide por su cuenta si la acción está permitida.
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
        if (entidad is File && entidad.path.endsWith('.zip')) {
          final stat = entidad.statSync();
          archivos.add(
            ArchivoRespaldo(nombre: p.basename(entidad.path), ruta: entidad.path, tamanoBytes: stat.size, modificado: stat.modified),
          );
        }
      }
      archivos.sort((a, b) => b.modificado.compareTo(a.modificado));
    }
    state = state.copyWith(cargando: false, respaldos: archivos);
  }

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
}
