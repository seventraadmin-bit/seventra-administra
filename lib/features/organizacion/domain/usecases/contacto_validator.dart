import 'package:riseg_one/features/organizacion/data/tables/contacto_table.dart';

import 'contacto_errors.dart';

/// Contacto tal como llega de un formulario — sin validar. `tipo` nulo
/// significa "sin seleccionar" (el formulario obliga a elegir uno).
class ContactoBorrador {
  const ContactoBorrador({
    required this.nombre,
    required this.tipo,
    this.puesto,
    this.telefono,
    this.correo,
    this.esPrincipal = false,
  });

  final String nombre;
  final TipoContacto? tipo;
  final String? puesto;
  final String? telefono;
  final String? correo;
  final bool esPrincipal;
}

/// Contacto ya validado y normalizado — listo para persistir.
class ContactoValidado {
  const ContactoValidado({
    required this.nombre,
    required this.tipo,
    required this.esPrincipal,
    this.puesto,
    this.telefono,
    this.correo,
  });

  final String nombre;
  final TipoContacto tipo;
  final String? puesto;
  final String? telefono;
  final String? correo;
  final bool esPrincipal;
}

/// Validador de Contacto — puro, sin dependencia de repositorio (a
/// diferencia de `PuestoValidator`): ninguna de sus reglas necesita
/// consultar la base de datos.
abstract final class ContactoValidator {
  // Estructura razonable ("algo@algo.algo", sin espacios), no una
  // validación estricta de RFC 5322 — mismo criterio deliberadamente
  // permisivo que `RfcValidator` para RFC.
  static final _correoRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  static ({ContactoValidado? resultado, List<ErrorCampoContacto> errores}) validar(ContactoBorrador borrador) {
    final errores = <ErrorCampoContacto>[];

    final nombre = borrador.nombre.trim();
    if (nombre.isEmpty) {
      errores.add(const ErrorCampoContacto(campo: CampoContacto.nombre, codigo: CodigoErrorContacto.requerido));
    }

    if (borrador.tipo == null) {
      errores.add(const ErrorCampoContacto(campo: CampoContacto.tipo, codigo: CodigoErrorContacto.requerido));
    }

    // Espacios accidentales se normalizan sin imponer un formato rígido
    // (sin exigir lada, sin exigir cantidad de dígitos).
    final telefono = _normalizarTelefono(borrador.telefono);
    final correoBruto = _vacioANull(borrador.correo);

    if (telefono == null && correoBruto == null) {
      errores.add(
        const ErrorCampoContacto(campo: CampoContacto.medioContacto, codigo: CodigoErrorContacto.requerido),
      );
    }

    String? correo;
    if (correoBruto != null) {
      if (_correoRegex.hasMatch(correoBruto)) {
        correo = correoBruto;
      } else {
        errores.add(
          const ErrorCampoContacto(campo: CampoContacto.medioContacto, codigo: CodigoErrorContacto.formatoInvalido),
        );
      }
    }

    if (errores.isNotEmpty) {
      return (resultado: null, errores: errores);
    }

    return (
      resultado: ContactoValidado(
        nombre: nombre,
        tipo: borrador.tipo!,
        puesto: _vacioANull(borrador.puesto),
        telefono: telefono,
        correo: correo,
        esPrincipal: borrador.esPrincipal,
      ),
      errores: const <ErrorCampoContacto>[],
    );
  }

  static String? _normalizarTelefono(String? valor) {
    if (valor == null) return null;
    final sinEspacios = valor.replaceAll(RegExp(r'\s+'), '');
    return sinEspacios.isEmpty ? null : sinEspacios;
  }

  static String? _vacioANull(String? valor) {
    if (valor == null) return null;
    final recortado = valor.trim();
    return recortado.isEmpty ? null : recortado;
  }
}
