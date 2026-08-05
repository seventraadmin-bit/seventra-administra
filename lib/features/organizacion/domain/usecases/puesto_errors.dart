/// Campo de un `PuestoBorrador` que puede fallar la validación.
enum CampoPuesto { nombre, area, tipo, nivelJerarquico }

enum CodigoErrorPuesto { requerido, noExiste, inactiva, fueraDeRango }

class ErrorCampoPuesto {
  const ErrorCampoPuesto({required this.campo, required this.codigo});

  final CampoPuesto campo;
  final CodigoErrorPuesto codigo;
}
