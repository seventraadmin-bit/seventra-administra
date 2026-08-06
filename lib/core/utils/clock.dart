/// Punto de extensión para "qué hora es" — hoy delega directamente a
/// `DateTime.now()`, pero permite que pruebas, simulaciones, cierres
/// administrativos o auditorías futuras controlen el reloj sin depender
/// del reloj real de la máquina (Etapa 4G.2, pedido explícito de Marlon).
///
/// Deliberadamente mínimo: un solo método, sin zonas horarias ni
/// programación de temporizadores — solo el punto de inyección.
abstract interface class Clock {
  DateTime now();
}

class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now();
}
