// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cliente_expediente_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$clienteExpedienteControllerHash() =>
    r'4e3e64a1da2844ab8b258ed9320f6ecd7b14b2f8';

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

abstract class _$ClienteExpedienteController
    extends BuildlessAutoDisposeNotifier<ClienteExpedienteState> {
  late final String clienteId;

  ClienteExpedienteState build(String clienteId);
}

/// Controlador de la pantalla de expediente de Cliente — un `family` por
/// `clienteId`. Mismo diseño que `PuestoExpedienteController`; el
/// cambio de estatus es una acción independiente del guardado del
/// formulario, y los Contactos y Entidades fiscales se agregan/editan/
/// archivan también de forma independiente (cada uno refresca solo su
/// propia lista del estado, sin tocar `modo` ni los datos generales ya
/// cargados). No guarda ningún `TextEditingController` ni objeto de UI
/// — esos viven en el `State` de la pantalla, nunca aquí.
///
/// Copied from [ClienteExpedienteController].
@ProviderFor(ClienteExpedienteController)
const clienteExpedienteControllerProvider = ClienteExpedienteControllerFamily();

/// Controlador de la pantalla de expediente de Cliente — un `family` por
/// `clienteId`. Mismo diseño que `PuestoExpedienteController`; el
/// cambio de estatus es una acción independiente del guardado del
/// formulario, y los Contactos y Entidades fiscales se agregan/editan/
/// archivan también de forma independiente (cada uno refresca solo su
/// propia lista del estado, sin tocar `modo` ni los datos generales ya
/// cargados). No guarda ningún `TextEditingController` ni objeto de UI
/// — esos viven en el `State` de la pantalla, nunca aquí.
///
/// Copied from [ClienteExpedienteController].
class ClienteExpedienteControllerFamily extends Family<ClienteExpedienteState> {
  /// Controlador de la pantalla de expediente de Cliente — un `family` por
  /// `clienteId`. Mismo diseño que `PuestoExpedienteController`; el
  /// cambio de estatus es una acción independiente del guardado del
  /// formulario, y los Contactos y Entidades fiscales se agregan/editan/
  /// archivan también de forma independiente (cada uno refresca solo su
  /// propia lista del estado, sin tocar `modo` ni los datos generales ya
  /// cargados). No guarda ningún `TextEditingController` ni objeto de UI
  /// — esos viven en el `State` de la pantalla, nunca aquí.
  ///
  /// Copied from [ClienteExpedienteController].
  const ClienteExpedienteControllerFamily();

  /// Controlador de la pantalla de expediente de Cliente — un `family` por
  /// `clienteId`. Mismo diseño que `PuestoExpedienteController`; el
  /// cambio de estatus es una acción independiente del guardado del
  /// formulario, y los Contactos y Entidades fiscales se agregan/editan/
  /// archivan también de forma independiente (cada uno refresca solo su
  /// propia lista del estado, sin tocar `modo` ni los datos generales ya
  /// cargados). No guarda ningún `TextEditingController` ni objeto de UI
  /// — esos viven en el `State` de la pantalla, nunca aquí.
  ///
  /// Copied from [ClienteExpedienteController].
  ClienteExpedienteControllerProvider call(String clienteId) {
    return ClienteExpedienteControllerProvider(clienteId);
  }

  @override
  ClienteExpedienteControllerProvider getProviderOverride(
    covariant ClienteExpedienteControllerProvider provider,
  ) {
    return call(provider.clienteId);
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'clienteExpedienteControllerProvider';
}

/// Controlador de la pantalla de expediente de Cliente — un `family` por
/// `clienteId`. Mismo diseño que `PuestoExpedienteController`; el
/// cambio de estatus es una acción independiente del guardado del
/// formulario, y los Contactos y Entidades fiscales se agregan/editan/
/// archivan también de forma independiente (cada uno refresca solo su
/// propia lista del estado, sin tocar `modo` ni los datos generales ya
/// cargados). No guarda ningún `TextEditingController` ni objeto de UI
/// — esos viven en el `State` de la pantalla, nunca aquí.
///
/// Copied from [ClienteExpedienteController].
class ClienteExpedienteControllerProvider
    extends
        AutoDisposeNotifierProviderImpl<
          ClienteExpedienteController,
          ClienteExpedienteState
        > {
  /// Controlador de la pantalla de expediente de Cliente — un `family` por
  /// `clienteId`. Mismo diseño que `PuestoExpedienteController`; el
  /// cambio de estatus es una acción independiente del guardado del
  /// formulario, y los Contactos y Entidades fiscales se agregan/editan/
  /// archivan también de forma independiente (cada uno refresca solo su
  /// propia lista del estado, sin tocar `modo` ni los datos generales ya
  /// cargados). No guarda ningún `TextEditingController` ni objeto de UI
  /// — esos viven en el `State` de la pantalla, nunca aquí.
  ///
  /// Copied from [ClienteExpedienteController].
  ClienteExpedienteControllerProvider(String clienteId)
    : this._internal(
        () => ClienteExpedienteController()..clienteId = clienteId,
        from: clienteExpedienteControllerProvider,
        name: r'clienteExpedienteControllerProvider',
        debugGetCreateSourceHash:
            const bool.fromEnvironment('dart.vm.product')
                ? null
                : _$clienteExpedienteControllerHash,
        dependencies: ClienteExpedienteControllerFamily._dependencies,
        allTransitiveDependencies:
            ClienteExpedienteControllerFamily._allTransitiveDependencies,
        clienteId: clienteId,
      );

  ClienteExpedienteControllerProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.clienteId,
  }) : super.internal();

  final String clienteId;

  @override
  ClienteExpedienteState runNotifierBuild(
    covariant ClienteExpedienteController notifier,
  ) {
    return notifier.build(clienteId);
  }

  @override
  Override overrideWith(ClienteExpedienteController Function() create) {
    return ProviderOverride(
      origin: this,
      override: ClienteExpedienteControllerProvider._internal(
        () => create()..clienteId = clienteId,
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        clienteId: clienteId,
      ),
    );
  }

  @override
  AutoDisposeNotifierProviderElement<
    ClienteExpedienteController,
    ClienteExpedienteState
  >
  createElement() {
    return _ClienteExpedienteControllerProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is ClienteExpedienteControllerProvider &&
        other.clienteId == clienteId;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, clienteId.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin ClienteExpedienteControllerRef
    on AutoDisposeNotifierProviderRef<ClienteExpedienteState> {
  /// The parameter `clienteId` of this provider.
  String get clienteId;
}

class _ClienteExpedienteControllerProviderElement
    extends
        AutoDisposeNotifierProviderElement<
          ClienteExpedienteController,
          ClienteExpedienteState
        >
    with ClienteExpedienteControllerRef {
  _ClienteExpedienteControllerProviderElement(super.provider);

  @override
  String get clienteId =>
      (origin as ClienteExpedienteControllerProvider).clienteId;
}

// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
