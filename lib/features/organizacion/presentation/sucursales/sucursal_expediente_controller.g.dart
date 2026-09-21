// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sucursal_expediente_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$sucursalExpedienteControllerHash() =>
    r'd1234118ebdefc033dda4de0ac3b03ba9d5f615f';

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

abstract class _$SucursalExpedienteController
    extends BuildlessAutoDisposeNotifier<SucursalExpedienteState> {
  late final String sucursalId;

  SucursalExpedienteState build(String sucursalId);
}

/// Controlador de la pantalla de expediente de Sucursal — un `family`
/// por `sucursalId`. Mismo diseño que `EmpresaExpedienteController`
/// (carga, consulta/edición, guardado, errores, estado sucio); guarda
/// datos y estado, nunca `TextEditingController`s (esos viven en la
/// pantalla).
///
/// Copied from [SucursalExpedienteController].
@ProviderFor(SucursalExpedienteController)
const sucursalExpedienteControllerProvider =
    SucursalExpedienteControllerFamily();

/// Controlador de la pantalla de expediente de Sucursal — un `family`
/// por `sucursalId`. Mismo diseño que `EmpresaExpedienteController`
/// (carga, consulta/edición, guardado, errores, estado sucio); guarda
/// datos y estado, nunca `TextEditingController`s (esos viven en la
/// pantalla).
///
/// Copied from [SucursalExpedienteController].
class SucursalExpedienteControllerFamily
    extends Family<SucursalExpedienteState> {
  /// Controlador de la pantalla de expediente de Sucursal — un `family`
  /// por `sucursalId`. Mismo diseño que `EmpresaExpedienteController`
  /// (carga, consulta/edición, guardado, errores, estado sucio); guarda
  /// datos y estado, nunca `TextEditingController`s (esos viven en la
  /// pantalla).
  ///
  /// Copied from [SucursalExpedienteController].
  const SucursalExpedienteControllerFamily();

  /// Controlador de la pantalla de expediente de Sucursal — un `family`
  /// por `sucursalId`. Mismo diseño que `EmpresaExpedienteController`
  /// (carga, consulta/edición, guardado, errores, estado sucio); guarda
  /// datos y estado, nunca `TextEditingController`s (esos viven en la
  /// pantalla).
  ///
  /// Copied from [SucursalExpedienteController].
  SucursalExpedienteControllerProvider call(String sucursalId) {
    return SucursalExpedienteControllerProvider(sucursalId);
  }

  @override
  SucursalExpedienteControllerProvider getProviderOverride(
    covariant SucursalExpedienteControllerProvider provider,
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
  String? get name => r'sucursalExpedienteControllerProvider';
}

/// Controlador de la pantalla de expediente de Sucursal — un `family`
/// por `sucursalId`. Mismo diseño que `EmpresaExpedienteController`
/// (carga, consulta/edición, guardado, errores, estado sucio); guarda
/// datos y estado, nunca `TextEditingController`s (esos viven en la
/// pantalla).
///
/// Copied from [SucursalExpedienteController].
class SucursalExpedienteControllerProvider
    extends
        AutoDisposeNotifierProviderImpl<
          SucursalExpedienteController,
          SucursalExpedienteState
        > {
  /// Controlador de la pantalla de expediente de Sucursal — un `family`
  /// por `sucursalId`. Mismo diseño que `EmpresaExpedienteController`
  /// (carga, consulta/edición, guardado, errores, estado sucio); guarda
  /// datos y estado, nunca `TextEditingController`s (esos viven en la
  /// pantalla).
  ///
  /// Copied from [SucursalExpedienteController].
  SucursalExpedienteControllerProvider(String sucursalId)
    : this._internal(
        () => SucursalExpedienteController()..sucursalId = sucursalId,
        from: sucursalExpedienteControllerProvider,
        name: r'sucursalExpedienteControllerProvider',
        debugGetCreateSourceHash:
            const bool.fromEnvironment('dart.vm.product')
                ? null
                : _$sucursalExpedienteControllerHash,
        dependencies: SucursalExpedienteControllerFamily._dependencies,
        allTransitiveDependencies:
            SucursalExpedienteControllerFamily._allTransitiveDependencies,
        sucursalId: sucursalId,
      );

  SucursalExpedienteControllerProvider._internal(
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
  SucursalExpedienteState runNotifierBuild(
    covariant SucursalExpedienteController notifier,
  ) {
    return notifier.build(sucursalId);
  }

  @override
  Override overrideWith(SucursalExpedienteController Function() create) {
    return ProviderOverride(
      origin: this,
      override: SucursalExpedienteControllerProvider._internal(
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
    SucursalExpedienteController,
    SucursalExpedienteState
  >
  createElement() {
    return _SucursalExpedienteControllerProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is SucursalExpedienteControllerProvider &&
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
mixin SucursalExpedienteControllerRef
    on AutoDisposeNotifierProviderRef<SucursalExpedienteState> {
  /// The parameter `sucursalId` of this provider.
  String get sucursalId;
}

class _SucursalExpedienteControllerProviderElement
    extends
        AutoDisposeNotifierProviderElement<
          SucursalExpedienteController,
          SucursalExpedienteState
        >
    with SucursalExpedienteControllerRef {
  _SucursalExpedienteControllerProviderElement(super.provider);

  @override
  String get sucursalId =>
      (origin as SucursalExpedienteControllerProvider).sucursalId;
}

// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
