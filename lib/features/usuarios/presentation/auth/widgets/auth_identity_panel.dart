import 'package:flutter/material.dart';

import 'package:riseg_one/core/branding/marca_producto.dart';
// BARREL WEB Y NO EL COMPLETO: este panel lo reutiliza TAMBIEN el login de la
// web, y el barrel completo exporta `riseg_entity_identity`, que lee del disco
// con `dart:io` y rompe la build del navegador. Aqui solo se usan tokens
// —`AppColors`, `AppSpacing`— que el barrel web exporta igual.
import 'package:riseg_one/core/design_system/design_system_web.dart';

/// Panel izquierdo de identidad, compartido por Login y por el
/// bootstrap del primer Maestro (Etapa 15) — la marca del **producto**
/// sobre el degradado azul institucional y un par de formas geométricas
/// muy sutiles, sin ninguna imagen generada ni fotografía. Cada pantalla
/// aporta su propio mensaje de bienvenida — el panel nunca decide *qué*
/// se está haciendo, solo *quién* es Seventra Administra.
///
/// El fondo es azul en los dos temas, así que la variante blanca del
/// logotipo se fuerza en vez de deducirse del brillo (Etapa 5B.1).
class AuthIdentityPanel extends StatelessWidget {
  const AuthIdentityPanel({required this.bienvenidaTitulo, required this.bienvenidaMensaje, super.key});

  final String bienvenidaTitulo;
  final String bienvenidaMensaje;

  @override
  Widget build(BuildContext context) {
    return Container(
      // Tinta plana. El degradado azul pertenecía a la identidad anterior.
      color: AppColors.tinta,
      child: Stack(
        // Se recorta contra el panel: la palomita tiene que verse cortada
        // por el borde, como en la referencia, no invadir el formulario.
        clipBehavior: Clip.hardEdge,
        children: [
          const Positioned(bottom: -90, left: -70, child: _PalomitaDeFondo(ancho: 520)),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.max,
              children: [
                const LogotipoProducto(key: Key('auth_logo'), ancho: 260, sobreFondoOscuro: true),
                const SizedBox(height: AppSpacing.lg),
                const Spacer(),
                Text(bienvenidaTitulo, style: AppTypography.heading2.copyWith(color: Colors.white)),
                const SizedBox(height: AppSpacing.xs),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Text(bienvenidaMensaje, style: AppTypography.body.copyWith(color: Colors.white.withValues(alpha: 0.85))),
                ),
                // Margen inferior extra, solo para el bloque de
                // bienvenida — el resto del panel no cambia.
                const SizedBox(height: AppSpacing.xl),
              ],
            ),
          ),
        ],
      ),
    );
  }

}

/// La palomita de la marca, enorme y tenue, como textura del panel.
///
/// Reutiliza `seventra-palomita.png` —que viene en verde— y lo vuelve a
/// teñir con `BlendMode.srcIn`: ese modo conserva el canal alfa del archivo
/// y sustituye el color, así que se obtiene la silueta exacta sin necesidad
/// de un asset nuevo.
///
/// Deliberadamente **no** es verde: el verde está reservado para marca y
/// acento, y una palomita verde de 520 px competiría con el wordmark y con
/// el mensaje de bienvenida. Aquí es relieve, no protagonista.
class _PalomitaDeFondo extends StatelessWidget {
  const _PalomitaDeFondo({required this.ancho});

  final double ancho;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ColorFiltered(
        colorFilter: const ColorFilter.mode(AppColors.tintaDecorativa, BlendMode.srcIn),
        // Sólo se fija el ancho: la altura la deduce Flutter de la
        // proporción del archivo (740×752), así que no puede deformarse.
        child: Image.asset('assets/images/seventra-palomita.png', width: ancho, excludeFromSemantics: true),
      ),
    );
  }
}
