import 'package:drift/drift.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/validation/rfc_validator.dart';

import '../repositories/empresa_repository.dart';
import '../shared/direccion_input.dart';
import '../shared/medio_contacto_input.dart';
import 'empresa_expediente_data.dart';
import 'empresa_expediente_errors.dart';
import 'empresa_expediente_input.dart';

/// Resultado de [GuardarExpedienteEmpresaUseCase] — deliberadamente su
/// propio tipo sellado, no el `Result`/`Failure` genérico: los errores de
/// validación aquí son estructurados (campo + código), algo que
/// `Failure.message` (una sola cadena) no representa bien.
sealed class GuardarExpedienteResultado {}

class GuardarExpedienteExitoso extends GuardarExpedienteResultado {
  GuardarExpedienteExitoso(this.datos);
  final EmpresaExpedienteData datos;
}

class GuardarExpedienteErroresValidacion extends GuardarExpedienteResultado {
  GuardarExpedienteErroresValidacion(this.errores);
  final List<ErrorCampoExpediente> errores;
}

class GuardarExpedienteErrorInesperado extends GuardarExpedienteResultado {
  GuardarExpedienteErrorInesperado(this.mensaje);
  final String mensaje;
}

const _campoDireccionRequerido = {
  CampoExpediente.calle,
  CampoExpediente.numeroExterior,
  CampoExpediente.colonia,
  CampoExpediente.municipioAlcaldia,
  CampoExpediente.estado,
  CampoExpediente.codigoPostal,
};

/// Coordina el guardado completo del expediente: datos generales,
/// dirección fiscal y medio de contacto principal, validando primero y
/// persistiendo todo en una sola transacción después (vía
/// `EmpresaRepository.guardarExpediente`). Reúne *todos* los errores de
/// las tres secciones antes de fallar — nunca se detiene en el primero,
/// para que la pantalla pueda mostrarlos todos de una vez.
class GuardarExpedienteEmpresaUseCase {
  GuardarExpedienteEmpresaUseCase(this._repository);

  final EmpresaRepository _repository;

  static final _correoRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
  static final _dominioRegex = RegExp(r'^[a-zA-Z0-9-]+(\.[a-zA-Z0-9-]+)+(/.*)?$');
  static final _codigoPostalMexicoRegex = RegExp(r'^\d{5}$');

  Future<GuardarExpedienteResultado> ejecutar({
    required String empresaId,
    required EmpresaExpedienteInput input,
  }) async {
    final errores = <ErrorCampoExpediente>[];

    final rfcNormalizado = _validarRfc(input.datosGenerales.rfc, errores);
    final direccionValidada = _validarDireccion(input.direccionFiscal, errores);
    final contactoValidado = _validarContacto(input.medioContacto, errores);

    if (errores.isNotEmpty) {
      return GuardarExpedienteErroresValidacion(errores);
    }

    try {
      final resultado = await _repository.guardarExpediente(
        empresaId: empresaId,
        datosGenerales: EmpresaCompanion(
          nombreComercial: Value(input.datosGenerales.nombreComercial.trim()),
          razonSocial: Value(_vacioANull(input.datosGenerales.razonSocial)),
          rfc: Value(rfcNormalizado),
          representanteLegal: Value(_vacioANull(input.datosGenerales.representanteLegal)),
          eslogan: Value(_vacioANull(input.datosGenerales.eslogan)),
        ),
        direccionFiscal: direccionValidada,
        medioContacto: contactoValidado,
      );

      return GuardarExpedienteExitoso(
        EmpresaExpedienteData(
          empresa: resultado.empresa,
          direccionFiscal: resultado.direccionFiscal,
          medioContacto: resultado.medioContacto,
        ),
      );
    } catch (e) {
      return GuardarExpedienteErrorInesperado(e.toString());
    }
  }

  String? _validarRfc(String? rfcCrudo, List<ErrorCampoExpediente> errores) {
    if (rfcCrudo == null || rfcCrudo.trim().isEmpty) return null;

    final normalizado = RfcValidator.normalizar(rfcCrudo);
    if (!RfcValidator.esFormatoValido(normalizado)) {
      errores.add(
        const ErrorCampoExpediente(campo: CampoExpediente.rfc, codigo: CodigoErrorCampo.formatoInvalido),
      );
      return null;
    }
    return normalizado;
  }

  DireccionInput? _validarDireccion(
    DireccionFiscalBorrador? borrador,
    List<ErrorCampoExpediente> errores,
  ) {
    if (borrador == null || borrador.estaCompletamenteVacia) return null;

    void requerido(String valor, CampoExpediente campo) {
      if (valor.trim().isEmpty) {
        errores.add(ErrorCampoExpediente(campo: campo, codigo: CodigoErrorCampo.requerido));
      }
    }

    requerido(borrador.calle, CampoExpediente.calle);
    requerido(borrador.numeroExterior, CampoExpediente.numeroExterior);
    requerido(borrador.colonia, CampoExpediente.colonia);
    requerido(borrador.municipioAlcaldia, CampoExpediente.municipioAlcaldia);
    requerido(borrador.estado, CampoExpediente.estado);

    final cp = borrador.codigoPostal.trim();
    final paisNormalizado = borrador.pais.trim().isEmpty ? 'México' : borrador.pais.trim();
    final esMexico = paisNormalizado.toLowerCase() == 'méxico' || paisNormalizado.toLowerCase() == 'mexico';

    if (cp.isEmpty) {
      errores.add(
        const ErrorCampoExpediente(campo: CampoExpediente.codigoPostal, codigo: CodigoErrorCampo.requerido),
      );
    } else if (esMexico && !_codigoPostalMexicoRegex.hasMatch(cp)) {
      // La regla de 5 dígitos depende de `país` — si en el futuro se
      // selecciona otro país, esta validación de formato no aplica.
      errores.add(
        const ErrorCampoExpediente(campo: CampoExpediente.codigoPostal, codigo: CodigoErrorCampo.formatoInvalido),
      );
    }

    final huboErrorEnDireccion = errores.any((e) => _campoDireccionRequerido.contains(e.campo));
    if (huboErrorEnDireccion) return null;

    return DireccionInput(
      calle: borrador.calle.trim(),
      numeroExterior: borrador.numeroExterior.trim(),
      numeroInterior: _vacioANull(borrador.numeroInterior),
      colonia: borrador.colonia.trim(),
      municipioAlcaldia: borrador.municipioAlcaldia.trim(),
      ciudadLocalidad: _vacioANull(borrador.ciudadLocalidad),
      estado: borrador.estado.trim(),
      codigoPostal: cp,
      pais: paisNormalizado,
      referencias: _vacioANull(borrador.referencias),
    );
  }

  MedioContactoInput? _validarContacto(
    MedioContactoBorrador? borrador,
    List<ErrorCampoExpediente> errores,
  ) {
    if (borrador == null || borrador.estaCompletamenteVacio) return null;

    String? correoValidado;
    final correo = _vacioANull(borrador.correo);
    if (correo != null) {
      if (!_correoRegex.hasMatch(correo)) {
        errores.add(
          const ErrorCampoExpediente(campo: CampoExpediente.correo, codigo: CodigoErrorCampo.formatoInvalido),
        );
      } else {
        correoValidado = correo;
      }
    }

    String? sitioWebValidado;
    final sitioWeb = _vacioANull(borrador.sitioWeb);
    if (sitioWeb != null) {
      final sinProtocolo = sitioWeb
          .replaceFirst(RegExp('^https?://', caseSensitive: false), '')
          .replaceFirst(RegExp(r'^www\.', caseSensitive: false), '');
      if (!_dominioRegex.hasMatch(sinProtocolo)) {
        errores.add(
          const ErrorCampoExpediente(campo: CampoExpediente.sitioWeb, codigo: CodigoErrorCampo.formatoInvalido),
        );
      } else {
        sitioWebValidado = sitioWeb;
      }
    }

    final huboErrorEnContacto = errores.any(
      (e) => e.campo == CampoExpediente.correo || e.campo == CampoExpediente.sitioWeb,
    );
    if (huboErrorEnContacto) return null;

    return MedioContactoInput(
      telefono: _normalizarTelefono(borrador.telefono),
      correo: correoValidado,
      sitioWeb: sitioWebValidado,
    );
  }

  static String? _vacioANull(String? valor) {
    if (valor == null) return null;
    final recortado = valor.trim();
    return recortado.isEmpty ? null : recortado;
  }

  static String? _normalizarTelefono(String? valor) {
    final sinVacio = _vacioANull(valor);
    if (sinVacio == null) return null;
    return sinVacio.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
