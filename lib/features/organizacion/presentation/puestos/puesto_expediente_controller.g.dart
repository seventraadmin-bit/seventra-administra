// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'puesto_expediente_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$puestoExpedienteControllerHash() =>
    r'69c1c1caa0752f47e88cd17953d8e69363bb411c';

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

abstract class _$PuestoExpedienteController
    extends BuildlessAutoDisposeNotifier<PuestoExpedienteState> {
  late final String puestoId;

  PuestoExpedienteState build(String puestoId);
}

/// Controlador de la pantalla de expediente de Puesto — un `family` por
/// `puestoId`. Mismo diseño que `SucursalExpedienteController`, sin las
/// secciones de sub-entidades; el ciclo de vida (archivar/reactivar) es
/// una acción independiente del guardado del formulario, igual que el
/// estado operativo de Sucursal.
///
/// Copied from [PuestoExpedienteController].
@ProviderFor(PuestoExpedienteController)
const puestoExpedienteControllerProvider = PuestoExpedienteControllerFamily();

/// Controlador de la pantalla de expediente de Puesto — un `family` por
/// `puestoId`. Mismo diseño que `SucursalExpedienteController`, sin las
/// secciones de sub-entidades; el ciclo de vida (archivar/reactivar) es
/// una acción independiente del guardado del formulario, igual que el
/// estado operativo de Sucursal.
///
/// Copied from [PuestoExpedienteController].
class PuestoExpedienteControllerFamily extends Family<PuestoExpedienteState> {
  /// Controlador de la pantalla de expediente de Puesto — un `family` por
  /// `puestoId`. Mismo diseño que `SucursalExpedienteController`, sin las
  /// secciones de sub-entidades; el ciclo de vida (archivar/reactivar) es
  /// una acción independiente del guardado del formulario, igual que el
  /// estado operativo de Sucursal.
  ///
  /// Copied from [PuestoExpedienteController].
  const PuestoExpedienteControllerFamily();

  /// Controlador de la pantalla de expediente de Puesto — un `family` por
  /// `puestoId`. Mismo diseño que `SucursalExpedienteController`, sin las
  /// secciones de sub-entidades; el ciclo de vida (archivar/reactivar) es
  /// una acción independiente del guardado del formulario, igual que el
  /// estado operativo de Sucursal.
  ///
  /// Copied from [PuestoExpedienteController].
  PuestoExpedienteControllerProvider call(String puestoId) {
    return PuestoExpedienteControllerProvider(puestoId);
  }

  @override
  PuestoExpedienteControllerProvider getProviderOverride(
    covariant PuestoExpedienteControllerProvider provider,
  ) {
    return call(provider.puestoId);
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'puestoExpedienteControllerProvider';
}

/// Controlador de la pantalla de expediente de Puesto — un `family` por
/// `puestoId`. Mismo diseño que `SucursalExpedienteController`, sin las
/// secciones de sub-entidades; el ciclo de vida (archivar/reactivar) es
/// una acción independiente del guardado del formulario, igual que el
/// estado operativo de Sucursal.
///
/// Copied from [PuestoExpedienteController].
class PuestoExpedienteControllerProvider
    extends
        AutoDisposeNotifierProviderImpl<
          PuestoExpedienteController,
          PuestoExpedienteState
        > {
  /// Controlador de la pantalla de expediente de Puesto — un `family` por
  /// `puestoId`. Mismo diseño que `SucursalExpedienteController`, sin las
  /// secciones de sub-entidades; el ciclo de vida (archivar/reactivar) es
  /// una acción independiente del guardado del formulario, igual que el
  /// estado operativo de Sucursal.
  ///
  /// Copied from [PuestoExpedienteController].
  PuestoExpedienteControllerProvider(String puestoId)
    : this._internal(
        () => PuestoExpedienteController()..puestoId = puestoId,
        from: puestoExpedienteControllerProvider,
        name: r'puestoExpedienteControllerProvider',
        debugGetCreateSourceHash:
            const bool.fromEnvironment('dart.vm.product')
                ? null
                : _$puestoExpedienteControllerHash,
        dependencies: PuestoExpedienteControllerFamily._dependencies,
        allTransitiveDependencies:
            PuestoExpedienteControllerFamily._allTransitiveDependencies,
        puestoId: puestoId,
      );

  PuestoExpedienteControllerProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.puestoId,
  }) : super.internal();

  final String puestoId;

  @override
  PuestoExpedienteState runNotifierBuild(
    covariant PuestoExpedienteController notifier,
  ) {
    return notifier.build(puestoId);
  }

  @override
  Override overrideWith(PuestoExpedienteController Function() create) {
    return ProviderOverride(
      origin: this,
      override: PuestoExpedienteControllerProvider._internal(
        () => create()..puestoId = puestoId,
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        puestoId: puestoId,
      ),
    );
  }

  @override
  AutoDisposeNotifierProviderElement<
    PuestoExpedienteController,
    PuestoExpedienteState
  >
  createElement() {
    return _PuestoExpedienteControllerProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is PuestoExpedienteControllerProvider &&
        other.puestoId == puestoId;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, puestoId.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin PuestoExpedienteControllerRef
    on AutoDisposeNotifierProviderRef<PuestoExpedienteState> {
  /// The parameter `puestoId` of this provider.
  String get puestoId;
}

class _PuestoExpedienteControllerProviderElement
    extends
        AutoDisposeNotifierProviderElement<
          PuestoExpedienteController,
          PuestoExpedienteState
        >
    with PuestoExpedienteControllerRef {
  _PuestoExpedienteControllerProviderElement(super.provider);

  @override
  String get puestoId =>
      (origin as PuestoExpedienteControllerProvider).puestoId;
}

// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
