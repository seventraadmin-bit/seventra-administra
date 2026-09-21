import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/cuenta_financiera_repository.dart';

/// Reactivar una `CuentaFinanciera` nunca está bloqueado (Etapa 19C) —
/// a diferencia de Desactivar, tampoco tiene condición alguna: no
/// existe ninguna regla de negocio que impida volver a operar una
/// cuenta previamente desactivada.
class ActivarCuentaFinancieraUseCase {
  ActivarCuentaFinancieraUseCase(this._repository);

  final CuentaFinancieraRepository _repository;

  Future<CuentaFinancieraData> ejecutar(String cuentaId) => _repository.activar(cuentaId);
}
