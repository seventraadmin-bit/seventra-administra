import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/cliente_repository.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/repositories/servicio_eventual_repository.dart';

import '../contraparte_cobro.dart';

/// Los nombres ya resueltos de un conjunto de contrapartes — el objeto
/// que las pantallas pasan a `nombreContraparte`.
class NombresContraparte {
  const NombresContraparte({required this.clientes, required this.serviciosEventuales});

  const NombresContraparte.vacio() : clientes = const {}, serviciosEventuales = const {};

  final Map<String, String> clientes;
  final Map<String, String> serviciosEventuales;

  /// El nombre que se muestra. Nunca un UUID: si la contraparte no se
  /// puede resolver, el guion largo dice "no se sabe" en vez de fingir
  /// que un identificador técnico es el nombre de alguien.
  String de(ContraparteCobro? contraparte) {
    return nombreContraparte(
      contraparte,
      nombresCliente: clientes,
      nombresServicioEventual: serviciosEventuales,
    );
  }
}

/// Resuelve en LOTE el nombre de toda contraparte de cobranza, sea
/// Cliente permanente o Servicio Eventual (schemaVersion 88).
///
/// Existe para que ningún widget vuelva a escribir
/// `clienteId ?? servicioEventualId`: desde que la contraparte puede
/// ser de dos tipos, resolverla a mano en cada pantalla garantiza que
/// tarde o temprano una muestre un UUID crudo. Dos consultas fijas, sin
/// importar cuántas filas se pidan.
class ResolverNombresContraparteUseCase {
  ResolverNombresContraparteUseCase(this._clienteRepository, this._servicioEventualRepository);

  final ClienteRepository _clienteRepository;
  final ServicioEventualRepository _servicioEventualRepository;

  Future<NombresContraparte> paraCuentas(Iterable<CuentaPorCobrarData> cuentas) {
    return _resolver(cuentas.map(contraparteDeCuenta));
  }

  Future<NombresContraparte> paraPagos(Iterable<PagoData> pagos) {
    return _resolver(pagos.map(contraparteDePago));
  }

  Future<NombresContraparte> paraContrapartes(Iterable<ContraparteCobro?> contrapartes) {
    return _resolver(contrapartes);
  }

  Future<NombresContraparte> _resolver(Iterable<ContraparteCobro?> contrapartes) async {
    final clientes = <String>{};
    final eventuales = <String>{};
    for (final contraparte in contrapartes) {
      switch (contraparte?.tipo) {
        case TipoContraparteCobro.cliente:
          clientes.add(contraparte!.id);
        case TipoContraparteCobro.servicioEventual:
          eventuales.add(contraparte!.id);
        case null:
          break;
      }
    }

    // Cada mapa se pide sólo si hace falta: una pantalla de cobranza
    // recurrente pura no paga por una consulta de eventuales.
    final nombresCliente = clientes.isEmpty
        ? const <String, String>{}
        : {
            for (final entrada in (await _clienteRepository.listarPorIds(clientes)).entries)
              entrada.key: entrada.value.nombreComercial,
          };
    final nombresEventual = eventuales.isEmpty
        ? const <String, String>{}
        : await _servicioEventualRepository.nombresSolicitantePorIds(eventuales);

    return NombresContraparte(clientes: nombresCliente, serviciosEventuales: nombresEventual);
  }
}
