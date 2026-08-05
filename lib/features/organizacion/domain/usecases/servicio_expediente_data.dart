import 'package:riseg_one/core/database/app_database.dart';

/// Servicio junto con si ya tiene una Dirección operativa activa — lo
/// que necesita el expediente para decidir cómo mostrar la opción
/// "Activo" (deshabilitada, o con la indicación "Disponible al
/// completar la Dirección operativa", punto 3 de la aprobación de la
/// Etapa 4F.1). Durante toda la 4F.1 esto es siempre `false`: la
/// captura de Dirección llega hasta la 4F.2 — intencional, no un
/// defecto (ver `CambiarEstatusServicioUseCase`).
class ServicioExpedienteData {
  const ServicioExpedienteData({required this.servicio, required this.tieneDireccionOperativaActiva});

  final ServicioData servicio;
  final bool tieneDireccionOperativaActiva;
}
