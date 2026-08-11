import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/compras/domain/repositories/compra_repository.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/egreso_repository.dart';
import 'package:riseg_one/features/nomina/domain/repositories/pago_nomina_repository.dart';

/// A qué dio origen un `Egreso` (Etapa 12A, Reportes) — `Egreso` en sí
/// no tiene ninguna columna discriminadora (confirmado por auditoría);
/// el origen se deriva siempre por la dirección inversa de la FK
/// (`Compra.egresoId`/`PagoNomina.egresoId`), nunca almacenado.
enum OrigenEgreso { compra, nomina, manual }

class EgresoConOrigen {
  const EgresoConOrigen({required this.egreso, required this.origen});

  final EgresoData egreso;
  final OrigenEgreso origen;
}

/// Totales por origen — puramente informativo para el desglose de
/// Finanzas: la suma de los tres coincide siempre con
/// `EgresoRepository.totalEgresos` del mismo rango, nunca se usa para
/// recalcular un Resultado operativo distinto.
class ResumenEgresosPorOrigen {
  const ResumenEgresosPorOrigen({
    required this.totalCompra,
    required this.totalNomina,
    required this.totalManual,
    required this.detalle,
  });

  final int totalCompra;
  final int totalNomina;
  final int totalManual;
  final List<EgresoConOrigen> detalle;
}

/// Compone tres repositorios de dos dominios distintos (Finanzas +
/// Compras + Nómina) en una sola pasada de lectura, sin N+1: carga los
/// tres conjuntos del rango de una vez y clasifica en memoria contra
/// los `egresoId` recolectados — nunca hace una consulta por cada
/// `Egreso`.
class ClasificarEgresosPorOrigenUseCase {
  ClasificarEgresosPorOrigenUseCase(this._egresoRepository, this._compraRepository, this._pagoNominaRepository);

  final EgresoRepository _egresoRepository;
  final CompraRepository _compraRepository;
  final PagoNominaRepository _pagoNominaRepository;

  Future<ResumenEgresosPorOrigen> ejecutar({DateTime? rangoInicio, DateTime? rangoFin}) async {
    final egresos = await _egresoRepository.listar(
      estatus: 'registrado',
      rangoInicio: rangoInicio,
      rangoFin: rangoFin,
    );
    final compras = await _compraRepository.listar(desde: rangoInicio, hasta: rangoFin, estatus: 'registrada');
    final pagosNomina = await _pagoNominaRepository.listarEnRango(rangoInicio: rangoInicio, rangoFin: rangoFin);

    final egresoIdsDeCompras = {for (final c in compras) if (c.egresoId != null) c.egresoId!};
    final egresoIdsDeNomina = {for (final p in pagosNomina) if (p.egresoId != null) p.egresoId!};

    var totalCompra = 0;
    var totalNomina = 0;
    var totalManual = 0;
    final detalle = <EgresoConOrigen>[];

    for (final egreso in egresos) {
      final OrigenEgreso origen;
      if (egresoIdsDeCompras.contains(egreso.id)) {
        origen = OrigenEgreso.compra;
        totalCompra += egreso.monto;
      } else if (egresoIdsDeNomina.contains(egreso.id)) {
        origen = OrigenEgreso.nomina;
        totalNomina += egreso.monto;
      } else {
        origen = OrigenEgreso.manual;
        totalManual += egreso.monto;
      }
      detalle.add(EgresoConOrigen(egreso: egreso, origen: origen));
    }

    return ResumenEgresosPorOrigen(
      totalCompra: totalCompra,
      totalNomina: totalNomina,
      totalManual: totalManual,
      detalle: detalle,
    );
  }
}
