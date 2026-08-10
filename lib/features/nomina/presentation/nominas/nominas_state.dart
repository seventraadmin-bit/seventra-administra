import 'package:riseg_one/core/database/app_database.dart';

/// Una fila del listado de Nóminas — el encabezado más los agregados de
/// sus renglones (cantidad de empleados y total a pagar), que `Nomina`
/// en sí no almacena.
class NominaResumen {
  const NominaResumen({required this.nomina, required this.totalEmpleados, required this.totalAPagar});

  final NominaData nomina;
  final int totalEmpleados;
  final int totalAPagar;
}

/// Estado del listado de Nóminas (Etapa 6C) — mismo shape que
/// `IngresosState`/`PagosState`.
class NominasState {
  const NominasState({this.cargando = true, this.nominas = const [], this.errorCarga});

  final bool cargando;
  final List<NominaResumen> nominas;
  final String? errorCarga;

  NominasState copyWith({bool? cargando, List<NominaResumen>? nominas, String? errorCarga}) {
    return NominasState(
      cargando: cargando ?? this.cargando,
      nominas: nominas ?? this.nominas,
      errorCarga: errorCarga,
    );
  }
}
