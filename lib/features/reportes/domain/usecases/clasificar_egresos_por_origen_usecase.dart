import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/vehiculos/domain/repositories/vehiculo_mantenimiento_repository.dart';
import 'package:riseg_one/features/compras/domain/repositories/compra_repository.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/repositories/servicio_eventual_repository.dart';
import 'package:riseg_one/features/descuentos_personal/domain/repositories/descuento_programado_repository.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/deuda_repository.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/egreso_repository.dart';
import 'package:riseg_one/features/nomina/domain/repositories/pago_nomina_repository.dart';
import 'package:riseg_one/features/tiempos_extra/domain/repositories/tiempo_extra_repository.dart';
import 'package:riseg_one/features/telefonia/domain/repositories/recarga_linea_telefonica_repository.dart';

/// A qué dio origen un `Egreso` (Etapa 12A, Reportes; `deuda` agregado
/// en la Etapa 19; `tiempoExtra` agregado en la etapa "Ingresos y
/// Egresos" — hueco real de auditoría: un Egreso de Tiempo Extra se
/// clasificaba como `manual` porque nadie consultaba
/// `TiempoExtra.egresoId`/`TiempoExtraCostoAdicional.egresoId`;
/// `descuentoProgramado` agregado en la etapa "Cierre del ciclo
/// financiero de Descuentos Programados" — mismo hueco real: el Egreso
/// de un préstamo se clasificaba como `manual` porque nadie consultaba
/// `DescuentoProgramadoEmpleado.egresoId`) — `Egreso` en sí no tiene
/// ninguna columna discriminadora (confirmado por auditoría); el
/// origen se deriva siempre por la dirección inversa de la FK, nunca
/// almacenado. Un descuento de recuperación de concepto (ej. botas,
/// sin `egresoId`) nunca genera ningún Egreso que clasificar aquí.
enum OrigenEgreso {
  compra,
  nomina,
  tiempoExtra,
  deuda,
  descuentoProgramado,
  vehiculo,
  telefonia,
  servicioEventual,
  manual,
}

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
    required this.totalTiempoExtra,
    required this.totalTelefonia,
    required this.totalDeuda,
    required this.totalDescuentoProgramado,
    required this.totalVehiculo,
    required this.totalServicioEventual,
    required this.totalManual,
    required this.detalle,
  });

  final int totalCompra;
  final int totalNomina;
  final int totalTelefonia;
  final int totalTiempoExtra;
  final int totalDeuda;
  final int totalDescuentoProgramado;

  /// schemaVersion 80 — gasto de mantenimiento de Vehículos pagado
  /// desde una CuentaFinanciera. Los pagados con TDC no aparecen aquí:
  /// no generan Egreso (viven en totalCargadoEnRango).
  final int totalVehiculo;

  /// schemaVersion 87 — coberturas y costos de Servicios Eventuales
  /// pagados desde una Cuenta. Los pagados con TDC no aparecen aquí:
  /// no generan Egreso, su peso entra por `cargosTarjetaPeriodo`.
  final int totalServicioEventual;

  final int totalManual;
  final List<EgresoConOrigen> detalle;
}

/// Compone cinco repositorios de cuatro dominios distintos (Finanzas +
/// Compras + Nómina + Tiempo Extra, `deuda` agregado en la Etapa 19,
/// `tiempoExtra` en la etapa "Ingresos y Egresos") en una sola pasada
/// de lectura, sin N+1: carga los cinco conjuntos del rango de una vez
/// y clasifica en memoria contra los `egresoId` recolectados — nunca
/// hace una consulta por cada `Egreso`.
class ClasificarEgresosPorOrigenUseCase {
  ClasificarEgresosPorOrigenUseCase(
    this._egresoRepository,
    this._compraRepository,
    this._pagoNominaRepository,
    this._tiempoExtraRepository,
    this._recargaLineaTelefonicaRepository,
    this._deudaRepository,
    this._descuentoProgramadoRepository,
    this._vehiculoMantenimientoRepository,
    this._servicioEventualRepository,
  );

  final EgresoRepository _egresoRepository;
  final CompraRepository _compraRepository;
  final PagoNominaRepository _pagoNominaRepository;
  final TiempoExtraRepository _tiempoExtraRepository;
  final RecargaLineaTelefonicaRepository _recargaLineaTelefonicaRepository;
  final VehiculoMantenimientoRepository _vehiculoMantenimientoRepository;
  final DeudaRepository _deudaRepository;
  final DescuentoProgramadoRepository _descuentoProgramadoRepository;
  final ServicioEventualRepository _servicioEventualRepository;

  Future<ResumenEgresosPorOrigen> ejecutar({DateTime? rangoInicio, DateTime? rangoFin}) async {
    // `soloSalidaDeEfectivo` (Etapa "Origen financiero de Egresos
    // manuales") mantiene intacta la invariante documentada de
    // `ResumenEgresosPorOrigen`: la suma de los totales por origen
    // coincide siempre con `EgresoRepository.totalEgresos` del mismo
    // rango — y ese total ya excluye los Egresos financiados con TDC.
    // El gasto de esos Egresos no se pierde del Resumen: entra por
    // `cargosTarjetaPeriodo`, igual que el de Compras/Tiempos Extra
    // con tarjeta.
    final egresos = await _egresoRepository.listar(
      estatus: 'registrado',
      rangoInicio: rangoInicio,
      rangoFin: rangoFin,
      soloSalidaDeEfectivo: true,
    );
    final compras = await _compraRepository.listar(desde: rangoInicio, hasta: rangoFin, estatus: 'registrada');
    final pagosNomina = await _pagoNominaRepository.listarEnRango(rangoInicio: rangoInicio, rangoFin: rangoFin);
    final egresoIdsDeTiempoExtra =
        await _tiempoExtraRepository.listarEgresoIdsEnRango(rangoInicio: rangoInicio, rangoFin: rangoFin);
    final egresoIdsDeDeuda =
        await _deudaRepository.listarEgresoIdsDePagosEnRango(rangoInicio: rangoInicio, rangoFin: rangoFin);
    final egresoIdsDeDescuentoProgramado =
        await _descuentoProgramadoRepository.listarEgresoIdsEnRango(rangoInicio: rangoInicio, rangoFin: rangoFin);

    final egresoIdsDeCompras = {for (final c in compras) if (c.egresoId != null) c.egresoId!};
    final egresoIdsDeNomina = {for (final p in pagosNomina) if (p.egresoId != null) p.egresoId!};
    final egresoIdsDeTiempoExtraSet = egresoIdsDeTiempoExtra.toSet();
    final egresoIdsDeDeudaSet = egresoIdsDeDeuda.toSet();
    final egresoIdsDeDescuentoProgramadoSet = egresoIdsDeDescuentoProgramado.toSet();
    // schemaVersion 80 — Vehículos genera Egresos automáticos. Sin
    // esto quedarían clasificados como 'manual', que es exactamente el
    // gap que tuvimos con Préstamos: el origen principal corregido pero
    // este clasificador independiente olvidado.
    final egresoIdsDeVehiculoSet = (await _vehiculoMantenimientoRepository.listarEgresoIds()).toSet();
    // schemaVersion 86 — Telefonía genera Egresos automáticos por
    // recarga. Sin esto quedarían como 'manual', que es exactamente el
    // mismo gap que ya tuvimos con Préstamos y con Vehículos: el origen
    // principal corregido y este clasificador independiente olvidado.
    final egresoIdsDeTelefoniaSet = (await _recargaLineaTelefonicaRepository.listarEgresoIds()).toSet();
    // schemaVersion 87 — Servicios Eventuales, cableado desde el día
    // uno para no repetir el hueco de "clasificador independiente
    // olvidado" por cuarta vez.
    final egresoIdsDeServicioEventualSet = (await _servicioEventualRepository.listarEgresoIds()).toSet();

    var totalCompra = 0;
    var totalNomina = 0;
    var totalTiempoExtra = 0;
    var totalDeuda = 0;
    var totalDescuentoProgramado = 0;
    var totalVehiculo = 0;
    var totalTelefonia = 0;
    var totalServicioEventual = 0;
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
      } else if (egresoIdsDeTiempoExtraSet.contains(egreso.id)) {
        origen = OrigenEgreso.tiempoExtra;
        totalTiempoExtra += egreso.monto;
      } else if (egresoIdsDeDeudaSet.contains(egreso.id)) {
        origen = OrigenEgreso.deuda;
        totalDeuda += egreso.monto;
      } else if (egresoIdsDeDescuentoProgramadoSet.contains(egreso.id)) {
        origen = OrigenEgreso.descuentoProgramado;
        totalDescuentoProgramado += egreso.monto;
      } else if (egresoIdsDeTelefoniaSet.contains(egreso.id)) {
        origen = OrigenEgreso.telefonia;
        totalTelefonia += egreso.monto;
      } else if (egresoIdsDeVehiculoSet.contains(egreso.id)) {
        origen = OrigenEgreso.vehiculo;
        totalVehiculo += egreso.monto;
      } else if (egresoIdsDeServicioEventualSet.contains(egreso.id)) {
        origen = OrigenEgreso.servicioEventual;
        totalServicioEventual += egreso.monto;
      } else {
        origen = OrigenEgreso.manual;
        totalManual += egreso.monto;
      }
      detalle.add(EgresoConOrigen(egreso: egreso, origen: origen));
    }

    return ResumenEgresosPorOrigen(
      totalCompra: totalCompra,
      totalNomina: totalNomina,
      totalTiempoExtra: totalTiempoExtra,
      totalTelefonia: totalTelefonia,
      totalDeuda: totalDeuda,
      totalDescuentoProgramado: totalDescuentoProgramado,
      totalVehiculo: totalVehiculo,
      totalServicioEventual: totalServicioEventual,
      totalManual: totalManual,
      detalle: detalle,
    );
  }
}
