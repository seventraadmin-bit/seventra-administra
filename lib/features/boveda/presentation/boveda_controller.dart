import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../boveda_providers.dart';
import 'boveda_state.dart';

part 'boveda_controller.g.dart';

/// Controlador de la pantalla de la Bóveda de Accesos del Maestro
/// (Etapa 14D) — mismo criterio que `AuditoriaController`: sin
/// autorización propia de lectura (la pantalla ya solo es alcanzable
/// con Maestro, ver `app_router.dart`); las acciones de escritura
/// (crear/editar/cambiar secreto/revelar/baja/reactivar) sí pasan
/// siempre por su `XxxAutorizadoProvider` (`exigirMaestro`).
@riverpod
class BovedaController extends _$BovedaController {
  @override
  BovedaState build() {
    Future.microtask(_cargar);
    return const BovedaState();
  }

  Future<void> _cargar() async {
    state = state.copyWith(cargando: true, errorCarga: null);
    try {
      final credenciales = await ref
          .read(bovedaCredencialRepositoryProvider)
          .listar(tipo: state.tipo, soloActivos: state.soloActivos ? true : null, texto: state.texto);
      state = state.copyWith(cargando: false, credenciales: credenciales);
    } catch (e) {
      state = state.copyWith(cargando: false, errorCarga: e.toString());
    }
  }

  Future<void> aplicarFiltros({String? tipo, bool limpiarTipo = false, bool? soloActivos, String? texto, bool limpiarTexto = false}) async {
    state = state.copyWith(
      tipo: tipo,
      limpiarTipo: limpiarTipo,
      soloActivos: soloActivos ?? state.soloActivos,
      texto: texto,
      limpiarTexto: limpiarTexto,
    );
    await _cargar();
  }

  Future<void> recargar() => _cargar();
}
