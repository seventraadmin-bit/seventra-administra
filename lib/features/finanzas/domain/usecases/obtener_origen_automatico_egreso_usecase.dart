import 'package:riseg_one/features/compras/domain/repositories/compra_repository.dart';
import 'package:riseg_one/features/descuentos_personal/domain/repositories/descuento_programado_repository.dart';
import 'package:riseg_one/features/nomina/domain/repositories/pago_nomina_repository.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/repositories/servicio_eventual_repository.dart';
import 'package:riseg_one/features/telefonia/domain/repositories/linea_telefonica_repository.dart';
import 'package:riseg_one/features/telefonia/domain/repositories/recarga_linea_telefonica_repository.dart';
import 'package:riseg_one/features/tiempos_extra/domain/repositories/tiempo_extra_repository.dart';
import 'package:riseg_one/features/vehiculos/domain/repositories/vehiculo_mantenimiento_repository.dart';
import 'package:riseg_one/features/vehiculos/domain/repositories/vehiculo_repository.dart';

import '../repositories/deuda_repository.dart';

/// A qué entidad dio origen automático un `Egreso` puntual — resuelto
/// siempre por FK real (nunca por texto/concepto), un caso de uso a la
/// vez (para reportes en lote ver `ClasificarEgresosPorOrigenUseCase`,
/// que preserva su propio camino sin N+1). `null` cuando el Egreso es
/// manual — es la ÚNICA fuente de verdad de "¿puedo corregir/cancelar
/// este Egreso directamente desde Finanzas?" (usada por
/// `CorregirEgresoUseCase`/`CancelarEgresoUseCase`) y también de qué
/// mostrar/hacia dónde navegar en "Ver origen" en la UI.
sealed class OrigenAutomaticoEgreso {}

class OrigenAutomaticoEgresoCompra extends OrigenAutomaticoEgreso {
  OrigenAutomaticoEgresoCompra({required this.compraId, required this.folio});
  final String compraId;
  final String folio;
}

class OrigenAutomaticoEgresoNomina extends OrigenAutomaticoEgreso {
  OrigenAutomaticoEgresoNomina({required this.pagoNominaId, required this.folio});
  final String pagoNominaId;
  final String folio;
}

class OrigenAutomaticoEgresoTiempoExtra extends OrigenAutomaticoEgreso {
  OrigenAutomaticoEgresoTiempoExtra({required this.tiempoExtraId, required this.folio});
  final String tiempoExtraId;
  final String folio;
}

class OrigenAutomaticoEgresoDeuda extends OrigenAutomaticoEgreso {
  OrigenAutomaticoEgresoDeuda({required this.deudaId, required this.folio});
  final String deudaId;
  final String folio;
}

class OrigenAutomaticoEgresoDescuentoProgramado extends OrigenAutomaticoEgreso {
  OrigenAutomaticoEgresoDescuentoProgramado({required this.descuentoProgramadoId, required this.folio});
  final String descuentoProgramadoId;
  final String folio;
}

/// schemaVersion 80 — un gasto de Vehículos pagado desde una
/// CuentaFinanciera. Como cualquier otro origen automático, su Egreso
/// NO puede corregirse ni cancelarse desde Finanzas: se resuelve desde
/// el mantenimiento que lo originó.
class OrigenAutomaticoEgresoVehiculo extends OrigenAutomaticoEgreso {
  OrigenAutomaticoEgresoVehiculo({
    required this.vehiculoId,
    required this.vehiculoMantenimientoId,
    required this.folio,
  });

  final String vehiculoId;
  final String vehiculoMantenimientoId;

  /// Código del Vehículo (VEH-000001) — lo que se muestra en "Ver
  /// origen", igual que el folio de una Compra.
  final String folio;
}

/// Rebanada 1 de Telefonía — una recarga pagada desde cuenta genera su
/// Egreso. Faltaba aquí, y la consecuencia no era sólo cosmética: como
/// este caso de uso es la ÚNICA fuente de verdad de "¿es manual?", el
/// Egreso de una recarga se podía corregir y cancelar desde Finanzas,
/// por encima de Telefonía.
class OrigenAutomaticoEgresoTelefonia extends OrigenAutomaticoEgreso {
  OrigenAutomaticoEgresoTelefonia({
    required this.lineaTelefonicaId,
    required this.recargaLineaTelefonicaId,
    required this.folio,
  });

  final String lineaTelefonicaId;
  final String recargaLineaTelefonicaId;

  /// Código de la línea (LIN-000004) — nunca el número, que es dato
  /// sensible de la SIM.
  final String folio;
}

/// schemaVersion 87 — una cobertura o un costo de Servicio Eventual
/// pagado desde una Cuenta financiera genera su Egreso. Se cablea aquí
/// desde el día uno, no después: este caso de uso es la ÚNICA fuente de
/// verdad de "¿es manual?", y un origen que falta aquí deja su Egreso
/// corregible y cancelable desde Finanzas, por encima del dominio que
/// lo creó — exactamente lo que pasó con Préstamos, Vehículos y
/// Telefonía.
class OrigenAutomaticoEgresoServicioEventual extends OrigenAutomaticoEgreso {
  OrigenAutomaticoEgresoServicioEventual({
    required this.servicioEventualId,
    required this.folio,
    this.coberturaId,
    this.costoId,
  });

  final String servicioEventualId;

  /// Folio del eventual (EVT-000001).
  final String folio;

  /// Exactamente uno de los dos está poblado — el Egreso lo produjo o
  /// una cobertura o un costo, nunca ambos.
  final String? coberturaId;
  final String? costoId;
}

class ObtenerOrigenAutomaticoEgresoUseCase {
  ObtenerOrigenAutomaticoEgresoUseCase(
    this._compraRepository,
    this._pagoNominaRepository,
    this._tiempoExtraRepository,
    this._deudaRepository,
    this._descuentoProgramadoRepository,
    this._vehiculoMantenimientoRepository,
    this._vehiculoRepository,
    this._recargaLineaTelefonicaRepository,
    this._lineaTelefonicaRepository,
    this._servicioEventualRepository,
  );

  final CompraRepository _compraRepository;
  final PagoNominaRepository _pagoNominaRepository;
  final TiempoExtraRepository _tiempoExtraRepository;
  final DeudaRepository _deudaRepository;
  final DescuentoProgramadoRepository _descuentoProgramadoRepository;
  final VehiculoMantenimientoRepository _vehiculoMantenimientoRepository;
  final VehiculoRepository _vehiculoRepository;
  final RecargaLineaTelefonicaRepository _recargaLineaTelefonicaRepository;
  final LineaTelefonicaRepository _lineaTelefonicaRepository;
  final ServicioEventualRepository _servicioEventualRepository;

  /// `null` si [egresoId] es un Egreso manual — nunca lanza para ese
  /// caso, es el resultado esperado, no una excepción.
  Future<OrigenAutomaticoEgreso?> ejecutar(String egresoId) async {
    final origenCompra = await _compraRepository.obtenerOrigenPorEgreso(egresoId);
    if (origenCompra != null) {
      return OrigenAutomaticoEgresoCompra(compraId: origenCompra.compraId, folio: origenCompra.folioCompra);
    }

    final pagoNomina = await _pagoNominaRepository.obtenerPorEgresoId(egresoId);
    if (pagoNomina != null) {
      return OrigenAutomaticoEgresoNomina(pagoNominaId: pagoNomina.id, folio: pagoNomina.folioPagoNomina);
    }

    final tiempoExtraId = await _tiempoExtraRepository.obtenerTiempoExtraIdPorEgresoId(egresoId);
    if (tiempoExtraId != null) {
      final tiempoExtra = await _tiempoExtraRepository.obtenerPorId(tiempoExtraId);
      if (tiempoExtra != null) {
        return OrigenAutomaticoEgresoTiempoExtra(tiempoExtraId: tiempoExtraId, folio: tiempoExtra.folio);
      }
    }

    final deudaId = await _deudaRepository.obtenerDeudaIdPorEgresoDePago(egresoId);
    if (deudaId != null) {
      final deuda = await _deudaRepository.obtenerPorId(deudaId);
      if (deuda != null) {
        return OrigenAutomaticoEgresoDeuda(deudaId: deudaId, folio: deuda.folio);
      }
    }

    final descuento = await _descuentoProgramadoRepository.obtenerPorEgresoId(egresoId);
    if (descuento != null) {
      return OrigenAutomaticoEgresoDescuentoProgramado(descuentoProgramadoId: descuento.id, folio: descuento.folio);
    }

    final mantenimiento = await _vehiculoMantenimientoRepository.obtenerPorEgresoId(egresoId);
    if (mantenimiento != null) {
      final vehiculo = await _vehiculoRepository.obtenerPorId(mantenimiento.vehiculoId);
      if (vehiculo != null) {
        return OrigenAutomaticoEgresoVehiculo(
          vehiculoId: vehiculo.id,
          vehiculoMantenimientoId: mantenimiento.id,
          folio: vehiculo.codigo,
        );
      }
    }

    final recarga = await _recargaLineaTelefonicaRepository.obtenerPorEgresoId(egresoId);
    if (recarga != null) {
      final linea = await _lineaTelefonicaRepository.obtenerPorId(recarga.lineaTelefonicaId);
      if (linea != null) {
        return OrigenAutomaticoEgresoTelefonia(
          lineaTelefonicaId: linea.id,
          recargaLineaTelefonicaId: recarga.id,
          folio: linea.codigo,
        );
      }
    }

    final cobertura = await _servicioEventualRepository.obtenerCoberturaPorEgresoId(egresoId);
    if (cobertura != null) {
      final eventual = await _servicioEventualRepository.obtenerPorId(cobertura.servicioEventualId);
      if (eventual != null) {
        return OrigenAutomaticoEgresoServicioEventual(
          servicioEventualId: eventual.id,
          folio: eventual.folio,
          coberturaId: cobertura.id,
        );
      }
    }

    final costo = await _servicioEventualRepository.obtenerCostoPorEgresoId(egresoId);
    if (costo != null) {
      final eventual = await _servicioEventualRepository.obtenerPorId(costo.servicioEventualId);
      if (eventual != null) {
        return OrigenAutomaticoEgresoServicioEventual(
          servicioEventualId: eventual.id,
          folio: eventual.folio,
          costoId: costo.id,
        );
      }
    }

    return null;
  }
}
