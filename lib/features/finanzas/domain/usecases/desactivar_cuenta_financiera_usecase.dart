import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/cuenta_financiera_repository.dart';

/// Desactivar una `CuentaFinanciera` (Etapa 19C) — nunca bloqueado por
/// movimientos históricos: una cuenta desactivada conserva su
/// historial y su saldo derivado intactos (Parte I del pedido), solo
/// deja de sumar a la posición de caja disponible hoy
/// (`ObtenerPosicionDeCajaUseCase` filtra por `soloActivas: true`). El
/// bloqueo real vive únicamente en la eliminación física
/// (`EliminarCuentaFinancieraFisicamenteUseCase`).
class DesactivarCuentaFinancieraUseCase {
  DesactivarCuentaFinancieraUseCase(this._repository);

  final CuentaFinancieraRepository _repository;

  Future<CuentaFinancieraData> ejecutar(String cuentaId) => _repository.desactivar(cuentaId);
}
