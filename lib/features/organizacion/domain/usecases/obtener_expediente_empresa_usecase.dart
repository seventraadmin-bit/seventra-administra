import 'package:riseg_one/core/error/result.dart';

import '../repositories/empresa_repository.dart';
import 'empresa_expediente_data.dart';
import 'obtener_empresa_activa_usecase.dart';

/// Compone la vista completa del expediente (Empresa + Dirección fiscal
/// + Medio de contacto principal) para la pantalla. No se agrega a
/// `ObtenerEmpresaActivaUseCase` porque ese caso de uso es genérico —
/// otros módulos futuros pueden necesitar solo la Empresa, sin cargar
/// dirección/contacto que no van a usar.
class ObtenerExpedienteEmpresaUseCase {
  ObtenerExpedienteEmpresaUseCase(this._obtenerEmpresaActiva, this._repository);

  final ObtenerEmpresaActivaUseCase _obtenerEmpresaActiva;
  final EmpresaRepository _repository;

  Future<Result<EmpresaExpedienteData>> ejecutar() async {
    final empresaResult = await _obtenerEmpresaActiva.ejecutar();

    return empresaResult.when(
      ok: (empresa) async {
        final direccion = await _repository.obtenerDireccionFiscal(empresa.id);
        final contacto = await _repository.obtenerMedioContactoPrincipal(empresa.id);
        return Result.ok(
          EmpresaExpedienteData(empresa: empresa, direccionFiscal: direccion, medioContacto: contacto),
        );
      },
      failure: (f) async => Result.failure(f),
    );
  }
}
