import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/categoria_financiera_repository.dart';

sealed class ActualizarCategoriaFinancieraResultado {}

class ActualizarCategoriaFinancieraExitoso extends ActualizarCategoriaFinancieraResultado {
  ActualizarCategoriaFinancieraExitoso(this.categoria);
  final CategoriaFinancieraData categoria;
}

class ActualizarCategoriaFinancieraNoExiste extends ActualizarCategoriaFinancieraResultado {}

class ActualizarCategoriaFinancieraCodigoRequerido extends ActualizarCategoriaFinancieraResultado {}

class ActualizarCategoriaFinancieraNombreRequerido extends ActualizarCategoriaFinancieraResultado {}

class ActualizarCategoriaFinancieraErrorInesperado extends ActualizarCategoriaFinancieraResultado {
  ActualizarCategoriaFinancieraErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Edita una categoría financiera existente — mismas validaciones que
/// el alta (Etapa 18). Nunca toca `cicloVidaRegistro`; eso es solo
/// responsabilidad de `ArchivarCategoriaFinancieraUseCase`.
class ActualizarCategoriaFinancieraUseCase {
  ActualizarCategoriaFinancieraUseCase(this._repository);

  final CategoriaFinancieraRepository _repository;

  Future<ActualizarCategoriaFinancieraResultado> ejecutar({
    required String id,
    required String codigo,
    required String nombre,
    required String tipo,
    required String tipoMovimiento,
  }) async {
    if (codigo.trim().isEmpty) {
      return ActualizarCategoriaFinancieraCodigoRequerido();
    }
    if (nombre.trim().isEmpty) {
      return ActualizarCategoriaFinancieraNombreRequerido();
    }

    final existente = await _repository.obtenerPorId(id);
    if (existente == null) {
      return ActualizarCategoriaFinancieraNoExiste();
    }

    try {
      final categoria = await _repository.actualizar(
        id: id,
        codigo: codigo.trim(),
        nombre: nombre.trim(),
        tipo: tipo,
        tipoMovimiento: tipoMovimiento,
      );
      return ActualizarCategoriaFinancieraExitoso(categoria);
    } catch (e) {
      return ActualizarCategoriaFinancieraErrorInesperado(e.toString());
    }
  }
}
