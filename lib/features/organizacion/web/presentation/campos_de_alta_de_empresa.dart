import 'package:flutter/material.dart';

import '../../../../core/design_system/design_system_web.dart';

/// Los campos con los que nace una empresa: nombre comercial y, si se quiere, razón
/// social.
///
/// ## Por qué es un widget propio y no está copiado en las dos pantallas
///
/// Hay **dos** sitios donde se da de alta una empresa, y son dos momentos distintos
/// del mismo acto:
///
///  · **E2**, en un diálogo de Organización › Empresa › Administración, cuando ya hay
///    al menos una empresa abierta;
///  · **E3**, en la antesala de «crea tu primera empresa», cuando no hay ninguna y por
///    tanto no hay marco de aplicación donde abrir un diálogo.
///
/// Duplicar los campos garantizaría que el día que se añada uno —o que cambie el tope
/// de la razón social— sólo se añada en uno de los dos. Una validación, unas claves
/// (`alta_nombre` y `alta_razon_social`) y un texto.
///
/// ## Lo que este widget NO hace
///
/// **No decide el ancho ni el espaciado de alrededor.** Quien lo usa lo envuelve: el
/// diálogo de E2 lo mete en un `SizedBox(width: 420)` y la pantalla de E3 lo deja
/// llenar su tarjeta. Imponerlo aquí habría obligado a una de las dos a pelearse con él.
///
/// **No guarda el estado de negocio.** Avisa de cada tecla con [alEscribirNombre] y
/// [alEscribirRazonSocial], y quien llama decide dónde vive eso: un objeto mutable
/// compartido con `onConfirm` en el diálogo, el `State` de la pantalla en E3.
class CamposDeAltaDeEmpresa extends StatefulWidget {
  const CamposDeAltaDeEmpresa({
    required this.alEscribirNombre,
    required this.alEscribirRazonSocial,
    this.autofocus = true,
    this.habilitado = true,
    this.alEnviar,
    super.key,
  });

  final ValueChanged<String> alEscribirNombre;
  final ValueChanged<String> alEscribirRazonSocial;

  /// El foco al abrir. En el diálogo sí; en una pantalla con panel de bienvenida
  /// también, porque lo único que hay que hacer ahí es escribir.
  final bool autofocus;

  /// En `false` mientras la petición está en vuelo, para que no se escriba encima de
  /// lo que ya se envió.
  final bool habilitado;

  /// Enter en la razón social. Nulo en el diálogo, que ya tiene sus botones.
  final VoidCallback? alEnviar;

  @override
  State<CamposDeAltaDeEmpresa> createState() => _CamposDeAltaDeEmpresaState();
}

class _CamposDeAltaDeEmpresaState extends State<CamposDeAltaDeEmpresa> {
  final _nombre = TextEditingController();
  final _razonSocial = TextEditingController();

  @override
  void dispose() {
    // LIBERAR LOS CONTROLLERS NO ES OPCIONAL. En este proyecto ya costó una vez, y
    // `Future.delayed(300ms)` para «esperar la animación» está PROHIBIDO.
    _nombre.dispose();
    _razonSocial.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      RisegTextField(
        key: const Key('alta_nombre'),
        label: 'Nombre comercial',
        controller: _nombre,
        autofocus: widget.autofocus,
        enabled: widget.habilitado,
        onChanged: widget.alEscribirNombre,
      ),
      const SizedBox(height: AppSpacing.md),
      RisegTextField(
        key: const Key('alta_razon_social'),
        label: 'Razón social (opcional)',
        controller: _razonSocial,
        enabled: widget.habilitado,
        onChanged: widget.alEscribirRazonSocial,
        onSubmitted: widget.alEnviar == null ? null : (_) => widget.alEnviar!(),
      ),
      const SizedBox(height: AppSpacing.md),
      Text(
        // SE DICE QUIÉN SERÁ EL MAESTRO, porque lo decide el servidor y no la
        // pantalla: elegir a otra persona exigiría resolver su identidad, y
        // Administra no tiene ninguna ruta que convierta un correo en identidad.
        'Tú serás su Maestro. Después puedes dar acceso a otras personas desde '
        'Configuración › Usuarios.',
        style: AppTypography.caption.copyWith(color: context.colors.textMuted),
      ),
    ],
  );
}
