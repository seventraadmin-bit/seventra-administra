// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'equipos_telefonicos_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$equiposTelefonicosControllerHash() =>
    r'04a672caf7026385cf2356cdf77304ab9b4e0904';

/// Controlador del listado de Equipos telefónicos (Etapa 9D, corrección
/// de invalidación) — antes de esta corrección, `EquiposTelefonicosListScreen`
/// mantenía esta misma consulta como estado local (`setState`, cargado
/// solo en `initState`), por lo que ninguna mutación (Configurar
/// equipo, editar IMEI, asignar/retirar, asociar/cambiar/retirar
/// equipo de una línea, etc.) podía refrescar la fila visible sin
/// forzar un remount completo de la pantalla (cambiar de pestaña y
/// volver). Mismo patrón exacto que `TelefoniaController` (líneas):
/// un controlador Riverpod único, invalidado explícitamente por cada
/// mutador real de Telefonía que cambie algo visible aquí.
///
/// Copied from [EquiposTelefonicosController].
@ProviderFor(EquiposTelefonicosController)
final equiposTelefonicosControllerProvider = AutoDisposeNotifierProvider<
  EquiposTelefonicosController,
  EquiposTelefonicosState
>.internal(
  EquiposTelefonicosController.new,
  name: r'equiposTelefonicosControllerProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$equiposTelefonicosControllerHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$EquiposTelefonicosController =
    AutoDisposeNotifier<EquiposTelefonicosState>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
