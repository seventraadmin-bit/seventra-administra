// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'servicio_expediente_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$servicioExpedienteControllerHash() =>
    r'93fa912251347b98ebc18ebfe9684f1f97364aa8';

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

abstract class _$ServicioExpedienteController
    extends BuildlessAutoDisposeNotifier<ServicioExpedienteState> {
  late final String servicioId;

  ServicioExpedienteState build(String servicioId);
}

/// Controlador de la pantalla de expediente de Servicio — un `family`
/// por `servicioId`. Mismo diseño que `ClienteExpedienteController`; el
/// cambio de estatus y las 5 acciones de vinculación (Entidad fiscal,
/// Responsable del Cliente, Sucursal administrativa, Responsable
/// interno, Dirección operativa) son todas independientes del guardado
/// del formulario principal — cada una refresca el expediente completo
/// (`_recargarDatos`) sin tocar `modo` ni los errores del formulario de
/// Datos generales/Referencias.
///
/// Copied from [ServicioExpedienteController].
@ProviderFor(ServicioExpedienteController)
const servicioExpedienteControllerProvider =
    ServicioExpedienteControllerFamily();

/// Controlador de la pantalla de expediente de Servicio — un `family`
/// por `servicioId`. Mismo diseño que `ClienteExpedienteController`; el
/// cambio de estatus y las 5 acciones de vinculación (Entidad fiscal,
/// Responsable del Cliente, Sucursal administrativa, Responsable
/// interno, Dirección operativa) son todas independientes del guardado
/// del formulario principal — cada una refresca el expediente completo
/// (`_recargarDatos`) sin tocar `modo` ni los errores del formulario de
/// Datos generales/Referencias.
///
/// Copied from [ServicioExpedienteController].
class ServicioExpedienteControllerFamily
    extends Family<ServicioExpedienteState> {
  /// Controlador de la pantalla de expediente de Servicio — un `family`
  /// por `servicioId`. Mismo diseño que `ClienteExpedienteController`; el
  /// cambio de estatus y las 5 acciones de vinculación (Entidad fiscal,
  /// Responsable del Cliente, Sucursal administrativa, Responsable
  /// interno, Dirección operativa) son todas independientes del guardado
  /// del formulario principal — cada una refresca el expediente completo
  /// (`_recargarDatos`) sin tocar `modo` ni los errores del formulario de
  /// Datos generales/Referencias.
  ///
  /// Copied from [ServicioExpedienteController].
  const ServicioExpedienteControllerFamily();

  /// Controlador de la pantalla de expediente de Servicio — un `family`
  /// por `servicioId`. Mismo diseño que `ClienteExpedienteController`; el
  /// cambio de estatus y las 5 acciones de vinculación (Entidad fiscal,
  /// Responsable del Cliente, Sucursal administrativa, Responsable
  /// interno, Dirección operativa) son todas independientes del guardado
  /// del formulario principal — cada una refresca el expediente completo
  /// (`_recargarDatos`) sin tocar `modo` ni los errores del formulario de
  /// Datos generales/Referencias.
  ///
  /// Copied from [ServicioExpedienteController].
  ServicioExpedienteControllerProvider call(String servicioId) {
    return ServicioExpedienteControllerProvider(servicioId);
  }

  @override
  ServicioExpedienteControllerProvider getProviderOverride(
    covariant ServicioExpedienteControllerProvider provider,
  ) {
    return call(provider.servicioId);
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'servicioExpedienteControllerProvider';
}

/// Controlador de la pantalla de expediente de Servicio — un `family`
/// por `servicioId`. Mismo diseño que `ClienteExpedienteController`; el
/// cambio de estatus y las 5 acciones de vinculación (Entidad fiscal,
/// Responsable del Cliente, Sucursal administrativa, Responsable
/// interno, Dirección operativa) son todas independientes del guardado
/// del formulario principal — cada una refresca el expediente completo
/// (`_recargarDatos`) sin tocar `modo` ni los errores del formulario de
/// Datos generales/Referencias.
///
/// Copied from [ServicioExpedienteController].
class ServicioExpedienteControllerProvider
    extends
        AutoDisposeNotifierProviderImpl<
          ServicioExpedienteController,
          ServicioExpedienteState
        > {
  /// Controlador de la pantalla de expediente de Servicio — un `family`
  /// por `servicioId`. Mismo diseño que `ClienteExpedienteController`; el
  /// cambio de estatus y las 5 acciones de vinculación (Entidad fiscal,
  /// Responsable del Cliente, Sucursal administrativa, Responsable
  /// interno, Dirección operativa) son todas independientes del guardado
  /// del formulario principal — cada una refresca el expediente completo
  /// (`_recargarDatos`) sin tocar `modo` ni los errores del formulario de
  /// Datos generales/Referencias.
  ///
  /// Copied from [ServicioExpedienteController].
  ServicioExpedienteControllerProvider(String servicioId)
    : this._internal(
        () => ServicioExpedienteController()..servicioId = servicioId,
        from: servicioExpedienteControllerProvider,
        name: r'servicioExpedienteControllerProvider',
        debugGetCreateSourceHash:
            const bool.fromEnvironment('dart.vm.product')
                ? null
                : _$servicioExpedienteControllerHash,
        dependencies: ServicioExpedienteControllerFamily._dependencies,
        allTransitiveDependencies:
            ServicioExpedienteControllerFamily._allTransitiveDependencies,
        servicioId: servicioId,
      );

  ServicioExpedienteControllerProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.servicioId,
  }) : super.internal();

  final String servicioId;

  @override
  ServicioExpedienteState runNotifierBuild(
    covariant ServicioExpedienteController notifier,
  ) {
    return notifier.build(servicioId);
  }

  @override
  Override overrideWith(ServicioExpedienteController Function() create) {
    return ProviderOverride(
      origin: this,
      override: ServicioExpedienteControllerProvider._internal(
        () => create()..servicioId = servicioId,
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        servicioId: servicioId,
      ),
    );
  }

  @override
  AutoDisposeNotifierProviderElement<
    ServicioExpedienteController,
    ServicioExpedienteState
  >
  createElement() {
    return _ServicioExpedienteControllerProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is ServicioExpedienteControllerProvider &&
        other.servicioId == servicioId;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, servicioId.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin ServicioExpedienteControllerRef
    on AutoDisposeNotifierProviderRef<ServicioExpedienteState> {
  /// The parameter `servicioId` of this provider.
  String get servicioId;
}

class _ServicioExpedienteControllerProviderElement
    extends
        AutoDisposeNotifierProviderElement<
          ServicioExpedienteController,
          ServicioExpedienteState
        >
    with ServicioExpedienteControllerRef {
  _ServicioExpedienteControllerProviderElement(super.provider);

  @override
  String get servicioId =>
      (origin as ServicioExpedienteControllerProvider).servicioId;
}

// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
