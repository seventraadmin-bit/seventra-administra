import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/inventario/domain/repositories/articulo_repository.dart';
import 'package:riseg_one/features/inventario/domain/repositories/inventario_repository.dart';

import '../repositories/equipo_telefonico_repository.dart';
import '../tipo_evento_equipo_telefonico.dart';

sealed class ConfigurarEquipoTelefonicoResultado {}

class ConfigurarEquipoTelefonicoExitoso extends ConfigurarEquipoTelefonicoResultado {
  ConfigurarEquipoTelefonicoExitoso(this.telefono);
  final ArticuloUnidadTelefonoData telefono;
}

class ConfigurarEquipoTelefonicoUnidadNoExiste extends ConfigurarEquipoTelefonicoResultado {}

/// La unidad no pertenece a un Artículo con `manejaSerie == true` — no
/// es una unidad serializada, así que no puede tener IMEI individual.
class ConfigurarEquipoTelefonicoUnidadNoSerializada extends ConfigurarEquipoTelefonicoResultado {}

class ConfigurarEquipoTelefonicoImei1Requerido extends ConfigurarEquipoTelefonicoResultado {}

class ConfigurarEquipoTelefonicoImeiDuplicado extends ConfigurarEquipoTelefonicoResultado {
  ConfigurarEquipoTelefonicoImeiDuplicado(this.detalle);
  final String detalle;
}

class ConfigurarEquipoTelefonicoErrorInesperado extends ConfigurarEquipoTelefonicoResultado {
  ConfigurarEquipoTelefonicoErrorInesperado(this.mensaje);
  final String mensaje;
}

/// "Configurar equipo" (Etapa 9D) — captura IMEI 1/IMEI 2 sobre una
/// `ArticuloUnidad` serializada YA existente (venga de Compras o de
/// alta manual de Inventario). **Nunca crea una `ArticuloUnidad`
/// nueva** — esa sigue siendo exclusivamente la responsabilidad de
/// Inventario/Compras (punto 9 de la Etapa 9D: "no romper la cadena
/// Compra → Inventario → Finanzas").
///
/// Unicidad de IMEI validada aquí, a nivel de aplicación (no un
/// `UNIQUE` de base de datos): "único cuando corresponda" admite
/// excepciones reales (equipos de segunda mano/gris), que un índice
/// duro bloquearía con un error críptico.
class ConfigurarEquipoTelefonicoUseCase {
  ConfigurarEquipoTelefonicoUseCase(this._inventarioRepository, this._articuloRepository, this._equipoRepository);

  final InventarioRepository _inventarioRepository;
  final ArticuloRepository _articuloRepository;
  final EquipoTelefonicoRepository _equipoRepository;

  Future<ConfigurarEquipoTelefonicoResultado> ejecutar({
    required String unidadId,
    required String imei,
    String? imei2,
    String? actorUsuarioId,
  }) async {
    final unidad = await _inventarioRepository.obtenerUnidadPorId(unidadId);
    if (unidad == null) return ConfigurarEquipoTelefonicoUnidadNoExiste();

    final articulo = await _articuloRepository.obtenerPorId(unidad.articuloId);
    if (articulo == null || !articulo.manejaSerie) return ConfigurarEquipoTelefonicoUnidadNoSerializada();

    final imei1Limpio = imei.trim();
    if (imei1Limpio.isEmpty) return ConfigurarEquipoTelefonicoImei1Requerido();
    final imei2Limpio = (imei2?.trim().isEmpty ?? true) ? null : imei2!.trim();

    if (imei2Limpio != null && imei2Limpio == imei1Limpio) {
      return ConfigurarEquipoTelefonicoImeiDuplicado('IMEI 1 e IMEI 2 no pueden ser el mismo valor.');
    }

    final coincidenciasImei1 = await _inventarioRepository.listarTelefonosPorImei(imei1Limpio);
    if (coincidenciasImei1.any((t) => t.unidadId != unidadId)) {
      return ConfigurarEquipoTelefonicoImeiDuplicado('El IMEI 1 ya está registrado en otro equipo.');
    }

    if (imei2Limpio != null) {
      final coincidenciasImei2 = await _inventarioRepository.listarTelefonosPorImei(imei2Limpio);
      if (coincidenciasImei2.any((t) => t.unidadId != unidadId)) {
        return ConfigurarEquipoTelefonicoImeiDuplicado('El IMEI 2 ya está registrado en otro equipo.');
      }
    }

    try {
      final telefono = await _inventarioRepository.actualizarTelefono(
        unidadId: unidadId,
        imei: imei1Limpio,
        imei2: imei2Limpio,
      );
      await _equipoRepository.registrarEvento(
        unidadId: unidadId,
        tipoEvento: TipoEventoEquipoTelefonico.equipoConfigurado.name,
        actorUsuarioId: actorUsuarioId,
      );
      return ConfigurarEquipoTelefonicoExitoso(telefono);
    } catch (e) {
      return ConfigurarEquipoTelefonicoErrorInesperado(e.toString());
    }
  }
}
