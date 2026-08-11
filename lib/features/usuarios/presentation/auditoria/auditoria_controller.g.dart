// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'auditoria_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$auditoriaControllerHash() =>
    r'4300fb79eb063bd7c14ce1b37f45b011405a601e';

/// Controlador de la pantalla central de Auditoría (Etapa 11D) — solo
/// lectura, agrega los eventos de todos los dominios vía
/// `BuscarAuditoriaUseCase`. Sin autorización propia: vive dentro de
/// `/configuracion`, ya gateada por `usuarios.administrar` a nivel de
/// router (Etapa 11B) — mismo criterio que `UsuariosListScreen`.
///
/// Copied from [AuditoriaController].
@ProviderFor(AuditoriaController)
final auditoriaControllerProvider =
    AutoDisposeNotifierProvider<AuditoriaController, AuditoriaState>.internal(
      AuditoriaController.new,
      name: r'auditoriaControllerProvider',
      debugGetCreateSourceHash:
          const bool.fromEnvironment('dart.vm.product')
              ? null
              : _$auditoriaControllerHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$AuditoriaController = AutoDisposeNotifier<AuditoriaState>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
