import 'package:riseg_one/core/database/app_database.dart';

/// Vista compuesta del expediente de Sucursal — la Sucursal junto con su
/// Dirección principal y su Horario semanal, si existen.
class SucursalExpedienteData {
  const SucursalExpedienteData({required this.sucursal, this.direccionPrincipal, this.horario});

  final SucursalData sucursal;
  final DireccionData? direccionPrincipal;
  final List<HorarioDetalleData>? horario;
}
