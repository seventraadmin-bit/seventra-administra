import 'package:riseg_one/core/database/app_database.dart';

/// Vista compuesta del expediente de Empresa — la Empresa activa junto
/// con su Dirección fiscal y Medio de contacto principal, si existen.
/// La usan tanto `ObtenerExpedienteEmpresaUseCase` (lectura) como
/// `GuardarExpedienteEmpresaUseCase` (para devolver el estado ya
/// actualizado sin que el llamador tenga que volver a consultar).
class EmpresaExpedienteData {
  const EmpresaExpedienteData({
    required this.empresa,
    this.direccionFiscal,
    this.medioContacto,
  });

  final EmpresaData empresa;
  final DireccionData? direccionFiscal;
  final MedioContactoData? medioContacto;
}
