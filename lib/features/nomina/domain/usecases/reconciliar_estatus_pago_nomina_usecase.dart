import '../repositories/nomina_repository.dart';
import '../repositories/pago_nomina_repository.dart';

/// Cuántos renglones/Nóminas tocó una corrida de
/// [ReconciliarEstatusPagoNominaUseCase] — puramente informativo (log
/// de arranque), nunca se persiste.
class ReconciliacionEstatusPagoResultado {
  const ReconciliacionEstatusPagoResultado({required this.renglonesCorregidos, required this.nominasActualizadas});
  final int renglonesCorregidos;
  final int nominasActualizadas;
}

/// Repara datos HISTÓRICOS anteriores a `PagoNominaRepository.
/// sincronizarEstatusPago` (Etapa 15, bug real reportado por Marlon:
/// NOM-000012 completamente cubierta seguía apareciendo "Próxima
/// nómina" en el Dashboard). Antes de ese método, `NominaEmpleado.
/// estatusPago` solo se actualizaba dentro de un pago real
/// (`PagoNominaRepositoryImpl.crear`/`cancelar`) — un renglón cuyo
/// `totalAPagar` ya era `0` ANTES de que existiera `sincronizarEstatusPago`
/// nunca vuelve a pasar por `generar`/`guardarRenglon`/`actualizarRenglon`
/// (esos escriben `totalAPagar` de nuevo, lo que sí lo habría
/// corregido) simplemente porque nadie vuelve a tocar una Nómina ya
/// `cerrada`/`pagada` — se queda atorado en el default `pendiente`
/// para siempre sin este mecanismo explícito de reconciliación.
///
/// Se ejecuta una vez por arranque de la aplicación (`bootstrap.dart`,
/// antes de `runApp`) sobre TODAS las Nóminas existentes,
/// independientemente de su estatus — deliberado: es más simple y más
/// seguro reconciliar todo que intentar adivinar cuáles Nóminas
/// podrían tener datos viejos, y [PagoNominaRepository.
/// sincronizarEstatusPago] ya es un no-op instantáneo (sin escritura)
/// sobre cualquier renglón que ya esté correcto — por construcción,
/// ejecutar esta reconciliación dos veces seguidas nunca produce un
/// segundo cambio, un segundo pago, ni un segundo movimiento de
/// `DescuentoProgramadoCuota` (mismo criterio de idempotencia que
/// `sincronizarEstatusPago` documenta).
///
/// Reutiliza deliberadamente la MISMA fórmula de dominio
/// (`sincronizarEstatusPago`, que a su vez comparte
/// `_estatusPagoPorSaldo` con un pago real) en vez de reimplementar el
/// criterio `saldoPendiente <= 0 → pagado` en SQL — evita que este
/// backfill diverja silenciosamente del criterio real si ese último
/// cambia en el futuro.
class ReconciliarEstatusPagoNominaUseCase {
  ReconciliarEstatusPagoNominaUseCase(this._nominaRepository, this._pagoNominaRepository);

  final NominaRepository _nominaRepository;
  final PagoNominaRepository _pagoNominaRepository;

  Future<ReconciliacionEstatusPagoResultado> ejecutar() async {
    final nominas = await _nominaRepository.listar();
    final estatusAntes = {for (final n in nominas) n.id: n.estatus};

    var renglonesCorregidos = 0;
    for (final nomina in nominas) {
      final renglones = await _nominaRepository.listarEmpleados(nomina.id);
      for (final renglon in renglones) {
        final cambio = await _pagoNominaRepository.sincronizarEstatusPago(nominaEmpleadoId: renglon.id);
        if (cambio) renglonesCorregidos++;
      }
    }

    var nominasActualizadas = 0;
    for (final nomina in nominas) {
      final actual = await _nominaRepository.obtenerPorId(nomina.id);
      if (actual != null && actual.estatus != estatusAntes[nomina.id]) nominasActualizadas++;
    }

    return ReconciliacionEstatusPagoResultado(renglonesCorregidos: renglonesCorregidos, nominasActualizadas: nominasActualizadas);
  }
}
