import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:riseg_one/core/permissions/authorization_service.dart';
import 'package:riseg_one/features/usuarios/usuarios_providers.dart';

import '../../domain/usecases/empresa_expediente_input.dart';
import '../../domain/usecases/eliminar_logo_empresa_usecase.dart';
import '../../domain/usecases/guardar_expediente_empresa_usecase.dart';
import '../../domain/usecases/registrar_logo_empresa_usecase.dart';
import '../../organizacion_providers.dart';
import 'empresa_expediente_state.dart';

part 'empresa_expediente_controller.g.dart';

/// Controlador de la pantalla de expediente de Empresa.
///
/// Guarda datos y estado (carga, modo, guardando, errores, "hay cambios
/// sin guardar") — nunca objetos de UI. Los `TextEditingController` del
/// formulario de edición viven en el widget de pantalla, con su propio
/// ciclo de vida; este controlador solo necesita saber *que* hubo un
/// cambio, no el contenido de cada campo.
@riverpod
class EmpresaExpedienteController extends _$EmpresaExpedienteController {
  @override
  EmpresaExpedienteState build() {
    // `_cargar` escribe en `state` de inmediato (antes de su primer
    // `await`) — llamarla de forma síncrona aquí chocaría con Riverpod,
    // que todavía no terminó de inicializar el estado en este punto.
    // `Future.microtask` la difiere justo después de que `build()` retorne.
    Future.microtask(_cargar);
    return const EmpresaExpedienteState();
  }

  Future<void> _cargar() async {
    state = state.copyWith(cargando: true, errorCarga: null);
    final resultado = await ref.read(obtenerExpedienteEmpresaUseCaseProvider).ejecutar();

    await resultado.when(
      ok: (datos) async {
        final logoPath = await _resolverLogoPath(datos.empresa.logoAttachmentId);
        state = state.copyWith(
          cargando: false,
          datos: datos,
          logoPath: logoPath,
          limpiarLogo: logoPath == null,
          modo: EmpresaExpedienteModo.consulta,
          errorCarga: null,
        );
      },
      failure: (f) {
        state = state.copyWith(cargando: false, errorCarga: f.message);
      },
    );
  }

  Future<void> reintentarCarga() => _cargar();

  /// La ruta física del adjunto, o `null` si no hay logotipo.
  Future<String?> _resolverLogoPath(String? attachmentId) async {
    if (attachmentId == null) return null;
    final adjunto = await ref.read(attachmentRepositoryProvider).obtenerPorId(attachmentId);
    return adjunto?.path;
  }

  /// Carga o reemplaza el logotipo de la Empresa (Etapa 5B.2).
  ///
  /// Recarga el expediente al terminar: así la ficha muestra el logotipo
  /// nuevo de inmediato, sin reiniciar la aplicación.
  Future<RegistrarLogoEmpresaResultado> registrarLogo({
    required String sourceFilePath,
    required String originalFileName,
  }) async {
    final empresa = state.datos?.empresa;
    if (empresa == null) return RegistrarLogoEmpresaNoExiste();

    final resultado = await ref.read(registrarLogoEmpresaAutorizadoProvider)(
      empresaId: empresa.id,
      sourceFilePath: sourceFilePath,
      originalFileName: originalFileName,
    );
    if (resultado is RegistrarLogoEmpresaExitoso) await _cargar();
    return resultado;
  }

  /// Quita el logotipo vigente. El adjunto se archiva, no se borra.
  Future<EliminarLogoEmpresaResultado> quitarLogo() async {
    final empresa = state.datos?.empresa;
    if (empresa == null) return EliminarLogoEmpresaNoExiste();

    final resultado = await ref.read(eliminarLogoEmpresaAutorizadoProvider)(empresa.id);
    if (resultado is EliminarLogoEmpresaExitoso) await _cargar();
    return resultado;
  }

  void entrarModoEdicion() {
    state = state.copyWith(
      modo: EmpresaExpedienteModo.edicion,
      tieneCambiosSinGuardar: false,
      erroresGuardado: const [],
      errorGuardadoGeneral: false,
    );
  }

  /// El widget de edición llama esto la primera vez que el usuario
  /// modifica cualquier campo — el controlador solo registra el hecho.
  void marcarCambiosSinGuardar() {
    if (!state.tieneCambiosSinGuardar) {
      state = state.copyWith(tieneCambiosSinGuardar: true);
    }
  }

  void cancelarEdicion() {
    state = state.copyWith(
      modo: EmpresaExpedienteModo.consulta,
      tieneCambiosSinGuardar: false,
      erroresGuardado: const [],
      errorGuardadoGeneral: false,
    );
  }

  /// Devuelve `true` si el guardado tuvo éxito. Ignora una segunda
  /// invocación mientras ya hay un guardado en curso (protege contra
  /// doble clic).
  Future<bool> guardar(EmpresaExpedienteInput input) async {
    if (state.guardando || state.datos == null) return false;

    state = state.copyWith(guardando: true, erroresGuardado: const [], errorGuardadoGeneral: false);

    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'organizacion.modificar',
      () => ref.read(guardarExpedienteEmpresaUseCaseProvider).ejecutar(empresaId: state.datos!.empresa.id, input: input),
      GuardarExpedienteErrorInesperado.new,
    );

    switch (resultado) {
      case GuardarExpedienteExitoso(datos: final datos):
        state = state.copyWith(
          guardando: false,
          datos: datos,
          modo: EmpresaExpedienteModo.consulta,
          tieneCambiosSinGuardar: false,
          erroresGuardado: const [],
          errorGuardadoGeneral: false,
        );
        return true;
      case GuardarExpedienteErroresValidacion(errores: final errores):
        state = state.copyWith(guardando: false, erroresGuardado: errores, errorGuardadoGeneral: false);
        return false;
      case GuardarExpedienteErrorInesperado():
        state = state.copyWith(guardando: false, erroresGuardado: const [], errorGuardadoGeneral: true);
        return false;
    }
  }
}
