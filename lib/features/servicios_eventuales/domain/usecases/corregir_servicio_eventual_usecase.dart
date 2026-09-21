import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show EstatusAplicacionPago;
import 'package:riseg_one/features/finanzas/domain/repositories/cuenta_por_cobrar_repository.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/pago_repository.dart';

import '../../data/tables/servicio_eventual_table.dart';
import '../repositories/servicio_eventual_repository.dart';
import '../totales_venta_eventual.dart';

sealed class CorregirServicioEventualResultado {}

class CorregirServicioEventualExitoso extends CorregirServicioEventualResultado {
  CorregirServicioEventualExitoso(this.servicioEventual);
  final ServicioEventualData servicioEventual;
}

class CorregirServicioEventualNoExiste extends CorregirServicioEventualResultado {}

class CorregirServicioEventualMotivoRequerido extends CorregirServicioEventualResultado {}

class CorregirServicioEventualNombreRequerido extends CorregirServicioEventualResultado {}

class CorregirServicioEventualRangoInvalido extends CorregirServicioEventualResultado {}

class CorregirServicioEventualImporteInvalido extends CorregirServicioEventualResultado {}

/// Un eventual cancelado es historia: se consulta, no se corrige.
class CorregirServicioEventualCancelado extends CorregirServicioEventualResultado {}

/// Ni el importe ni el tratamiento de IVA se pueden mover: la Cuenta
/// por cobrar tiene al menos un Pago aplicado (schemaVersion 88/89).
/// Bajar el total dejaría un cobro sin deuda que lo sostenga, y subirlo
/// fingiría que el cliente quedó a deber algo que nunca se le documentó
/// — y cambiar de "IVA incluido" a "más IVA" después de cobrar mueve el
/// total exactamente igual, por la puerta de atrás. Primero se corrige o
/// cancela el Pago, por su propio flujo — nunca en cascada desde aquí.
class CorregirServicioEventualImporteBloqueadoPorPago extends CorregirServicioEventualResultado {
  CorregirServicioEventualImporteBloqueadoPorPago(this.aplicacionesActivas);
  final int aplicacionesActivas;
}

class CorregirServicioEventualErrorInesperado extends CorregirServicioEventualResultado {
  CorregirServicioEventualErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Corrección de los datos del acuerdo. Deja intactos solicitante y
/// tipo de solicitante: cambiar de quién es el evento no es una
/// corrección de captura, y en la Rebanada 2 movería la contraparte de
/// una cobranza ya emitida.
class CorregirServicioEventualUseCase {
  CorregirServicioEventualUseCase(this._repository, this._cuentaPorCobrarRepository, this._pagoRepository);

  final ServicioEventualRepository _repository;
  final CuentaPorCobrarRepository _cuentaPorCobrarRepository;
  final PagoRepository _pagoRepository;

  Future<CorregirServicioEventualResultado> ejecutar({
    required String servicioEventualId,
    String? nombre,
    DateTime? fechaHoraInicio,
    DateTime? fechaHoraFin,
    String? ubicacion,
    String? notas,
    int? importeAcordado,
    TratamientoIva? tratamientoIva,
    bool? requiereFactura,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    final motivoLimpio = motivo.trim();
    if (motivoLimpio.isEmpty) return CorregirServicioEventualMotivoRequerido();

    final actual = await _repository.obtenerPorId(servicioEventualId);
    if (actual == null) return CorregirServicioEventualNoExiste();
    if (actual.estatus == EstatusServicioEventual.cancelado.name) {
      return CorregirServicioEventualCancelado();
    }

    final nombreLimpio = nombre?.trim();
    if (nombreLimpio != null && nombreLimpio.isEmpty) return CorregirServicioEventualNombreRequerido();
    if (importeAcordado != null && importeAcordado <= 0) return CorregirServicioEventualImporteInvalido();

    // El rango se valida contra el estado RESULTANTE, no solo contra
    // lo que viene en la llamada: mover únicamente el inicio también
    // puede invertirlo.
    final inicio = fechaHoraInicio ?? actual.fechaHoraInicio;
    final fin = fechaHoraFin ?? actual.fechaHoraFin;
    if (fin.isBefore(inicio)) return CorregirServicioEventualRangoInvalido();

    // El total de la venta y el de su Cuenta por cobrar son el mismo
    // número: corregir uno sin el otro los volvería incoherentes. Y
    // sólo se puede mientras nadie haya pagado.
    //
    // Cambiar el tratamiento de IVA cuenta como cambiar el importe:
    // mueve el total igual que mover el número capturado.
    final cambiaTratamiento = tratamientoIva != null && tratamientoIva.name != actual.tratamientoIva;
    final cambiaImporte =
        (importeAcordado != null && importeAcordado != actual.importeAcordado) || cambiaTratamiento;
    final cuenta = await _cuentaPorCobrarRepository.obtenerPorServicioEventualId(servicioEventualId);
    if (cambiaImporte && cuenta != null) {
      final aplicaciones = await _pagoRepository.listarAplicacionesPorCuenta(cuenta.id);
      final activas =
          aplicaciones.where((a) => a.estatus == EstatusAplicacionPago.aplicada.name).length;
      if (activas > 0) return CorregirServicioEventualImporteBloqueadoPorPago(activas);
    }

    try {
      final eventual = await _repository.corregir(
        servicioEventualId: servicioEventualId,
        nombre: nombreLimpio,
        tratamientoIva: tratamientoIva?.name,
        fechaHoraInicio: fechaHoraInicio,
        fechaHoraFin: fechaHoraFin,
        ubicacion: ubicacion == null || ubicacion.trim().isEmpty ? null : ubicacion.trim(),
        notas: notas == null || notas.trim().isEmpty ? null : notas.trim(),
        importeAcordado: importeAcordado,
        requiereFactura: requiereFactura,
        motivo: motivoLimpio,
        actorUsuarioId: actorUsuarioId,
      );
      if (cambiaImporte && cuenta != null) {
        // La Cuenta recibe el TOTAL resultante, derivado del estado que
        // quedó — nunca el importe capturado a secas.
        await _cuentaPorCobrarRepository.corregirImporte(
          cuentaPorCobrarId: cuenta.id,
          importeEmitido: totalVentaEventual(
            importeAcordado: eventual.importeAcordado,
            tratamientoIva: TratamientoIva.values.byName(eventual.tratamientoIva),
          ),
          motivo: motivoLimpio,
          actorUsuarioId: actorUsuarioId,
        );
      }
      return CorregirServicioEventualExitoso(eventual);
    } catch (e) {
      return CorregirServicioEventualErrorInesperado(e.toString());
    }
  }
}
