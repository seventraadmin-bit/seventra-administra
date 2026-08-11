// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sesion_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$sesionControllerHash() => r'58a30dd1e634fae92234b6cbda8b2d805891ab7c';

/// Sesión activa de RISEG ONE (Etapa 11A) — `null` significa "sin
/// sesión", el estado que fuerza al `redirect` del router a mandar a
/// `/login`. No se persiste entre reinicios a propósito (ver el plan de
/// la Etapa 11, §5): cada arranque de la aplicación exige iniciar
/// sesión de nuevo, nunca se guarda contraseña ni token.
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
