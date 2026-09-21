import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/deuda_repository.dart';
import 'calcular_fecha_tarjeta_usecase.dart';

/// Crédito disponible agregado de TDC (Etapa "Dashboard: posición
/// financiera") — `hayTarjetas == false` cuando no existe ninguna TDC
/// `activa` (estado real distinto de "$0.00 disponible"), mismo
/// criterio honesto que `PosicionDeCaja.configurada`. Nunca se suma con
/// [PosicionDeCaja.saldoDisponible] en ningún lugar — caja y crédito
/// son conceptos financieros distintos.
class CreditoDisponibleTarjetas {
  const CreditoDisponibleTarjetas({
    required this.hayTarjetas,
    required this.totalDisponible,
    required this.tarjetas,
  });

  final bool hayTarjetas;
  final int totalDisponible;
  final List<DeudaData> tarjetas;
}

/// Suma [creditoDisponibleTarjeta] sobre todas las TDC activas
/// (`DeudaRepository.listarTarjetasActivas`, la misma fuente de verdad
/// que ya usa el listado de Deudas y crédito para su propia cifra de
/// "Crédito disponible" — nunca una segunda fórmula). Una tarjeta sin
/// `tarjetaLimiteCredito` capturado se excluye de la suma (no se sabe
/// su disponible, nunca se asume $0), mismo criterio que el listado.
class ObtenerCreditoDisponibleTarjetasUseCase {
  ObtenerCreditoDisponibleTarjetasUseCase(this._repository);

  final DeudaRepository _repository;

  Future<CreditoDisponibleTarjetas> ejecutar() async {
    final tarjetas = await _repository.listarTarjetasActivas();
    if (tarjetas.isEmpty) {
      return const CreditoDisponibleTarjetas(hayTarjetas: false, totalDisponible: 0, tarjetas: []);
    }

    final totalDisponible = tarjetas.where((t) => t.tarjetaLimiteCredito != null).fold<int>(
          0,
          (acc, t) => acc + creditoDisponibleTarjeta(limiteCredito: t.tarjetaLimiteCredito, saldoActual: t.saldoActual)!,
        );

    return CreditoDisponibleTarjetas(hayTarjetas: true, totalDisponible: totalDisponible, tarjetas: tarjetas);
  }
}
