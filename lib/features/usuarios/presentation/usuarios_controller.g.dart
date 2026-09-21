// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'usuarios_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$usuariosControllerHash() =>
    r'4bcdfe9eba677659d917a4255810741e4a8b76cf';

/// Controlador del listado + CRUD de Usuarios (Etapa 11A) — mismo
/// molde que `ComprasController`. Cada acción de escritura pasa el
/// `usuarioId` de la sesión activa como `actorUsuarioId` — es la
/// primera vez que el proyecto tiene un actor real que registrar en un
/// evento (antes siempre llegaba `null`).
///
/// Copied from [UsuariosController].
@ProviderFor(UsuariosController)
final usuariosControllerProvider =
    AutoDisposeNotifierProvider<UsuariosController, UsuariosState>.internal(
      UsuariosController.new,
      name: r'usuariosControllerProvider',
      debugGetCreateSourceHash:
          const bool.fromEnvironment('dart.vm.product')
              ? null
              : _$usuariosControllerHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$UsuariosController = AutoDisposeNotifier<UsuariosState>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
