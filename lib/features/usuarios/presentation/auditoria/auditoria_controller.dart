import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/usecases/buscar_auditoria_usecase.dart';
import '../../usuarios_providers.dart';
import 'auditoria_state.dart';

part 'auditoria_controller.g.dart';

/// Controlador de la pantalla central de Auditoría (Etapa 11D) — solo
/// lectura, agrega los eventos de todos los dominios vía
/// `BuscarAuditoriaUseCase`. Sin autorización propia: vive dentro de
/// `/configuracion`, ya gateada por `usuarios.administrar` a nivel de
/// router (Etapa 11B) — mismo criterio que `UsuariosListScreen`.
@riverpod
class AuditoriaController extends _$AuditoriaController {
  @override
  AuditoriaState build() {
    Future.microtask(_cargar);
    return const AuditoriaState(cargando: true);
  }

  Future<void> _cargar() async {
    state = state.copyWith(cargando: true, errorCarga: null);
    try {
      final usuarios = await ref.read(usuarioRepositoryProvider).listar(cicloVidaRegistro: null);
      final eventos = await ref.read(buscarAuditoriaUseCaseProvider).ejecutar(
            FiltroAuditoria(
              actorUsuarioId: state.actorUsuarioId,
              modulo: state.modulo,
              accion: state.accion,
              desde: state.desde,
              hasta: state.hasta,
            ),
          );
      state = state.copyWith(cargando: false, eventos: eventos, usuarios: usuarios, errorCarga: null);
    } catch (e) {
      state = state.copyWith(cargando: false, errorCarga: e.toString());
    }
  }

  Future<void> aplicarFiltros({
    String? actorUsuarioId,
    bool limpiarActorUsuarioId = false,
    String? modulo,
    bool limpiarModulo = false,
    String? accion,
    bool limpiarAccion = false,
    DateTime? desde,
    bool limpiarDesde = false,
    DateTime? hasta,
    bool limpiarHasta = false,
  }) async {
    state = state.copyWith(
      actorUsuarioId: actorUsuarioId,
      limpiarActorUsuarioId: limpiarActorUsuarioId,
      modulo: modulo,
      limpiarModulo: limpiarModulo,
      accion: accion,
      limpiarAccion: limpiarAccion,
      desde: desde,
      limpiarDesde: limpiarDesde,
      hasta: hasta,
      limpiarHasta: limpiarHasta,
    );
    await _cargar();
  }

  Future<void> limpiarFiltros() async {
    state = state.copyWith(
      limpiarActorUsuarioId: true,
      limpiarModulo: true,
      limpiarAccion: true,
      limpiarDesde: true,
      limpiarHasta: true,
    );
    await _cargar();
  }
}
