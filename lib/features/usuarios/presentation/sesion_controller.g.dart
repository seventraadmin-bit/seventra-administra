// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sesion_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$sesionControllerHash() => r'a0ffb0cad7adc733dd36997ccebe71d50df231ea';

/// Sesión activa de RISEG ONE (Etapa 11A) — `null` significa "sin
/// sesión", el estado que fuerza al `redirect` del router a mandar a
/// `/login`. No se persiste sola: si el arranque encuentra "Recuérdame
/// en este equipo" válido (Etapa 15,
/// `RestaurarSesionRecordadaUseCase`), `bootstrap()` fija el estado
/// inicial *antes* de `runApp` sobreescribiendo este provider — nunca
/// hay un estado intermedio "cargando" dentro del propio `Notifier`.
///
/// `keepAlive: true` es obligatorio aquí — sin él, `@riverpod` genera
/// un provider `autoDispose` por defecto, y la sesión se perdía (volvía
/// a `null`) en cuanto ningún widget lo observaba activamente ni
/// siquiera un instante durante una transición de navegación (bug real
/// encontrado en la Etapa 11B: el sidebar se veía correcto justo tras
/// el login pero la sesión ya aparecía `null` al leerla un frame
/// después). La sesión debe sobrevivir mientras la app esté abierta,
/// nunca destruirse por falta de observadores momentánea.
///
/// Copied from [SesionController].
@ProviderFor(SesionController)
final sesionControllerProvider =
    NotifierProvider<SesionController, SesionUsuario?>.internal(
      SesionController.new,
      name: r'sesionControllerProvider',
      debugGetCreateSourceHash:
          const bool.fromEnvironment('dart.vm.product')
              ? null
              : _$sesionControllerHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$SesionController = Notifier<SesionUsuario?>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
