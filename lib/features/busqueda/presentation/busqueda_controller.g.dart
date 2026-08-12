// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'busqueda_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$busquedaControllerHash() =>
    r'098c8d78913e375c8c67e73310752ececbc19e3c';

/// Controlador de Búsqueda global (Etapa 14A) — igual que Reportes/
/// Dashboard, la guardia real de permiso vive aquí: cada grupo solo se
/// consulta si la sesión tiene su `hasCode(...)` correspondiente, antes
/// de invocar `BuscarGlobalUseCase`. Menos de 2 caracteres nunca
/// dispara ninguna consulta.
///
/// Copied from [BusquedaController].
@ProviderFor(BusquedaController)
final busquedaControllerProvider =
    AutoDisposeNotifierProvider<BusquedaController, BusquedaState>.internal(
      BusquedaController.new,
      name: r'busquedaControllerProvider',
      debugGetCreateSourceHash:
          const bool.fromEnvironment('dart.vm.product')
              ? null
              : _$busquedaControllerHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$BusquedaController = AutoDisposeNotifier<BusquedaState>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
