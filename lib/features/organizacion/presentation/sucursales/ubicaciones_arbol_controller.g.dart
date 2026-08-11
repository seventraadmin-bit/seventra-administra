// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ubicaciones_arbol_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$ubicacionesArbolControllerHash() =>
    r'74fbd16963fd2a835283d7614babd82188cc412e';

/// Copied from Dart SDK
class _SystemHash {
  _SystemHash._();

  static int combine(int hash, int value) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + value);
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
    return hash ^ (hash >> 6);
  }

  static int finish(int hash) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    // ignore: parameter_assignments
    hash = hash ^ (hash >> 11);
    return 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
  }
}

abstract class _$UbicacionesArbolController
    extends BuildlessAutoDisposeNotifier<UbicacionesArbolState> {
  late final String sucursalId;

  UbicacionesArbolState build(String sucursalId);
}

/// Controlador del árbol de Ubicaciones de una Sucursal — un `family`
/// por `sucursalId`. Reutiliza sin cambios los casos de uso de 4A
/// (`CrearUbicacionUseCase`, `MoverUbicacionUseCase`) — este controlador
/// solo coordina el estado de la pantalla (carga, expandido/colapsado).
///
/// Copied from [UbicacionesArbolController].
@ProviderFor(UbicacionesArbolController)
const ubicacionesArbolControllerProvider = UbicacionesArbolControllerFamily();

/// Controlador del árbol de Ubicaciones de una Sucursal — un `family`
/// por `sucursalId`. Reutiliza sin cambios los casos de uso de 4A
/// (`CrearUbicacionUseCase`, `MoverUbicacionUseCase`) — este controlador
/// solo coordina el estado de la pantalla (carga, expandido/colapsado).
///
/// Copied from [UbicacionesArbolController].
class UbicacionesArbolControllerFamily extends Family<UbicacionesArbolState> {
  /// Controlador del árbol de Ubicaciones de una Sucursal — un `family`
  /// por `sucursalId`. Reutiliza sin cambios los casos de uso de 4A
  /// (`CrearUbicacionUseCase`, `MoverUbicacionUseCase`) — este controlador
  /// solo coordina el estado de la pantalla (carga, expandido/colapsado).
  ///
  /// Copied from [UbicacionesArbolController].
  const UbicacionesArbolControllerFamily();

  /// Controlador del árbol de Ubicaciones de una Sucursal — un `family`
  /// por `sucursalId`. Reutiliza sin cambios los casos de uso de 4A
  /// (`CrearUbicacionUseCase`, `MoverUbicacionUseCase`) — este controlador
  /// solo coordina el estado de la pantalla (carga, expandido/colapsado).
  ///
  /// Copied from [UbicacionesArbolController].
  UbicacionesArbolControllerProvider call(String sucursalId) {
    return UbicacionesArbolControllerProvider(sucursalId);
  }

  @override
  UbicacionesArbolControllerProvider getProviderOverride(
    covariant UbicacionesArbolControllerProvider provider,
  ) {
    return call(provider.sucursalId);
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'ubicacionesArbolControllerProvider';
}

/// Controlador del árbol de Ubicaciones de una Sucursal — un `family`
/// por `sucursalId`. Reutiliza sin cambios los casos de uso de 4A
/// (`CrearUbicacionUseCase`, `MoverUbicacionUseCase`) — este controlador
/// solo coordina el estado de la pantalla (carga, expandido/colapsado).
///
/// Copied from [UbicacionesArbolController].
class UbicacionesArbolControllerProvider
    extends
        AutoDisposeNotifierProviderImpl<
          UbicacionesArbolController,
          UbicacionesArbolState
        > {
  /// Controlador del árbol de Ubicaciones de una Sucursal — un `family`
  /// por `sucursalId`. Reutiliza sin cambios los casos de uso de 4A
  /// (`CrearUbicacionUseCase`, `MoverUbicacionUseCase`) — este controlador
  /// solo coordina el estado de la pantalla (carga, expandido/colapsado).
  ///
  /// Copied from [UbicacionesArbolController].
  UbicacionesArbolControllerProvider(String sucursalId)
    : this._internal(
        () => UbicacionesArbolController()..sucursalId = sucursalId,
        from: ubicacionesArbolControllerProvider,
        name: r'ubicacionesArbolControllerProvider',
        debugGetCreateSourceHash:
            const bool.fromEnvironment('dart.vm.product')
                ? null
                : _$ubicacionesArbolControllerHash,
        dependencies: UbicacionesArbolControllerFamily._dependencies,
        allTransitiveDependencies:
            UbicacionesArbolControllerFamily._allTransitiveDependencies,
        sucursalId: sucursalId,
      );

  UbicacionesArbolControllerProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.sucursalId,
  }) : super.internal();

  final String sucursalId;

  @override
  UbicacionesArbolState runNotifierBuild(
    covariant UbicacionesArbolController notifier,
  ) {
    return notifier.build(sucursalId);
  }

  @override
  Override overrideWith(UbicacionesArbolController Function() create) {
    return ProviderOverride(
      origin: this,
      override: UbicacionesArbolControllerProvider._internal(
        () => create()..sucursalId = sucursalId,
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        sucursalId: sucursalId,
      ),
    );
  }

  @override
  AutoDisposeNotifierProviderElement<
    UbicacionesArbolController,
    UbicacionesArbolState
  >
  createElement() {
    return _UbicacionesArbolControllerProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is UbicacionesArbolControllerProvider &&
        other.sucursalId == sucursalId;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, sucursalId.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin UbicacionesArbolControllerRef
    on AutoDisposeNotifierProviderRef<UbicacionesArbolState> {
  /// The parameter `sucursalId` of this provider.
  String get sucursalId;
}

class _UbicacionesArbolControllerProviderElement
    extends
        AutoDisposeNotifierProviderElement<
          UbicacionesArbolController,
          UbicacionesArbolState
        >
    with UbicacionesArbolControllerRef {
  _UbicacionesArbolControllerProviderElement(super.provider);

  @override
  String get sucursalId =>
      (origin as UbicacionesArbolControllerProvider).sucursalId;
}

// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
