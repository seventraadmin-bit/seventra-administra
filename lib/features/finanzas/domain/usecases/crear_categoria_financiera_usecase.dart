import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/categoria_financiera_repository.dart';

sealed class CrearCategoriaFinancieraResultado {}

class CrearCategoriaFinancieraExitoso extends CrearCategoriaFinancieraResultado {
  CrearCategoriaFinancieraExitoso(this.categoria);
  final CategoriaFinancieraData categoria;
}

class CrearCategoriaFinancieraCodigoRequerido extends CrearCategoriaFinancieraResultado {}

class CrearCategoriaFinancieraNombreRequerido extends CrearCategoriaFinancieraResultado {}

class CrearCategoriaFinancieraErrorInesperado extends CrearCategoriaFinancieraResultado {
  CrearCategoriaFinancieraErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Registra una categoría financiera (Etapa 4K.1) — el catálogo nace
/// vacío, RISEG lo captura desde una pantalla propia (ninguna
/// categoría se inventa ni se siembra).
class CrearCategoriaFinancieraUseCase {
  CrearCategoriaFinancieraUseCase(this._repository);

  final CategoriaFinancieraRepository _repository;

  Future<CrearCategoriaFinancieraResultado> ejecutar({
    required String codigo,
    required String nombre,
    required String tipo,
    required String tipoMovimiento,
  }) async {
    if (codigo.trim().isEmpty) {
      return CrearCategoriaFinancieraCodigoRequerido();
    }
    if (nombre.trim().isEmpty) {
      return CrearCategoriaFinancieraNombreRequerido();
    }

    try {
      final categoria = await _repository.crear(
        codigo: codigo.trim(),
        nombre: nombre.trim(),
        tipo: tipo,
        tipoMovimiento: tipoMovimiento,
      );
      return CrearCategoriaFinancieraExitoso(categoria);
    } catch (e) {
      return CrearCategoriaFinancieraErrorInesperado(e.toString());
    }
  }
}
