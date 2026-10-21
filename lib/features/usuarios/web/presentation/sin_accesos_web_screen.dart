import 'package:flutter/material.dart';

import '../../../../core/design_system/design_system_web.dart';

/// **Nadie te dio nada que hacer en esta empresa.**
///
/// ## Por qué existe, y por qué no existía antes
///
/// Hasta el 21 de octubre de 2026 este estado era **inalcanzable**: el menú enseñaba
/// los nueve apartados y los no mudados salían con «Próximamente», así que cualquiera
/// con acceso a la empresa veía al menos Dashboard. Al dejar de enseñar lo que no se
/// puede abrir —ese aviso nombraba la aplicación de escritorio, que un cliente nuevo
/// no tiene— quien no tiene ningún permiso se queda sin ningún apartado, y sin esta
/// pantalla vería un marco con el menú vacío y un hueco en medio.
///
/// ## Qué dice y qué no
///
/// **DICE QUÉ HACER, y es lo único útil que se le puede decir.** «No tienes accesos» a
/// secas deja a alguien pensando que el producto está roto o que se equivocó de
/// cuenta; nombrar al administrador convierte una pared en un siguiente paso.
///
/// **NO dice «Próximamente»**, ni nombra el escritorio, ni promete nada: lo que falta
/// no es una función nuestra, son permisos que alguien de su empresa tiene que
/// conceder.
///
/// **LLEVA SU NOMBRE Y EL DE LA EMPRESA** porque las dos preguntas que se hace quien
/// ve esto son «¿entré con mi cuenta?» y «¿entré a la empresa correcta?». Y lleva
/// cerrar sesión por lo mismo: si la respuesta a una de las dos es no, tiene que poder
/// salir sin buscar dónde.
///
/// ## Vive en su propio archivo, no como ayudante privado del portón
///
/// Es una pantalla del producto, con su texto y su botón, y lo que no se puede montar
/// no se puede probar. El aviso que esto reemplaza llevaba meses diciendo «desde la
/// aplicación de escritorio» sin que ninguna prueba lo leyera.
class SinAccesosWebScreen extends StatelessWidget {
  const SinAccesosWebScreen({
    required this.nombre,
    required this.empresa,
    required this.alCerrarSesion,
    super.key,
  });

  /// Cómo se llama quien entró. Vacío si la sesión restaurada no lo trae:
  /// `/auth/refresh` responde con `displayName` nulo.
  final String nombre;

  /// La empresa que el servidor confirmó.
  final String empresa;

  final VoidCallback alCerrarSesion;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.surface,
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            // ANCHO ACOTADO: un párrafo que cruza una pantalla de 27 pulgadas no se
            // lee, se barre.
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.lock_person_outlined,
                    size: 48,
                    color: colors.textMuted,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Hola${nombre.isEmpty ? '' : ', $nombre'}',
                    style: AppTypography.heading2,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  // LA EMPRESA, EN SU PROPIA LÍNEA. Es la mitad de la pregunta que se
                  // hace quien ve esto, y enterrada en el párrafo se pasa por alto.
                  if (empresa.isNotEmpty)
                    Text(
                      empresa,
                      style: AppTypography.body.copyWith(
                        color: colors.textMuted,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Todavía no tienes accesos asignados en esta empresa. '
                    'Pídele al administrador que te los otorgue.',
                    style: AppTypography.body.copyWith(color: colors.textMuted),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  RisegButton(
                    label: 'Cerrar sesión',
                    variant: RisegButtonVariant.secondary,
                    icon: Icons.logout_outlined,
                    onPressed: alCerrarSesion,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
