import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';

/// Servicio junto con todo lo que su expediente necesita mostrar: el
/// Cliente propietario (solo lectura, relación inmutable), si ya tiene
/// una Dirección operativa activa (y la propia Dirección, si existe), y
/// sus 3 vinculaciones opcionales (Entidad fiscal, Responsable del
/// Cliente, Sucursal administrativa) — cada una acompañada de si el
/// registro relacionado sigue activo, para que el expediente pueda
/// mostrar una advertencia sin desvincular nada automáticamente (Etapa
/// 4F.2, "las relaciones no se desvinculan solas cuando lo asignado se
/// archiva después").
///
/// `tieneDireccionOperativaActiva` decide cómo se muestra "Activar"
/// (deshabilitado + indicación "Disponible al completar la Dirección
/// operativa", punto 3 de la aprobación de la Etapa 4F.1) — durante
/// toda la 4F.1 era siempre `false`; desde la 4F.2, con la captura de
/// Dirección ya construida, puede ser `true`.
class ServicioExpedienteData {
  const ServicioExpedienteData({
    required this.servicio,
    required this.cliente,
    required this.tieneDireccionOperativaActiva,
    this.direccionOperativa,
    this.entidadFiscal,
    this.responsableCliente,
    this.sucursalAdministrativa,
  });

  final ServicioData servicio;
  final ClienteData cliente;
  final bool tieneDireccionOperativaActiva;
  final DireccionData? direccionOperativa;
  final EntidadFiscalData? entidadFiscal;
  final ContactoData? responsableCliente;
  final SucursalData? sucursalAdministrativa;

  bool get entidadFiscalArchivada =>
      entidadFiscal != null && entidadFiscal!.cicloVidaRegistro != CicloVidaRegistro.activo.name;

  bool get responsableClienteArchivado =>
      responsableCliente != null && responsableCliente!.cicloVidaRegistro != CicloVidaRegistro.activo.name;

  bool get sucursalAdministrativaArchivada =>
      sucursalAdministrativa != null && sucursalAdministrativa!.cicloVidaRegistro != CicloVidaRegistro.activo.name;
}
