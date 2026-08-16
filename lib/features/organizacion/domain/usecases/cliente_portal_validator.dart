import 'package:riseg_one/core/database/tables/audit_columns.dart';

import '../../data/tables/cliente_portal_table.dart';
import '../repositories/cliente_repository.dart';
import 'cliente_portal_errors.dart';

/// Datos de un portal del Cliente tal como llegan del formulario — sin
/// validar. `contrasenaNueva` sigue el mismo criterio de escritura que
/// `CambiarSecretoCredencialBovedaUseCase`: `null` significa "no tocar
/// la contraseña ya guardada" (el formulario de edición nunca la
/// prellena, así que en blanco es indistinguible de "sin cambio"); un
/// valor no vacío significa "cifrar y reemplazar". No incluye
/// `clienteId`: la relación con el Cliente es inmutable después de
/// creado, igual que `EntidadFiscalBorrador`.
class ClientePortalBorrador {
  const ClientePortalBorrador({
    required this.nombre,
    required this.tipo,
    this.url,
    this.usuario,
    this.contrasenaNueva,
    this.observaciones,
  });

  final String nombre;
  final TipoPortalCliente tipo;
  final String? url;
  final String? usuario;
  final String? contrasenaNueva;
  final String? observaciones;
}

/// Portal ya validado y normalizado — listo para persistir.
class ClientePortalValidada {
  const ClientePortalValidada({
    required this.nombre,
    required this.tipo,
    this.url,
    this.usuario,
    this.contrasenaNueva,
    this.observaciones,
  });

  final String nombre;
  final TipoPortalCliente tipo;
  final String? url;
  final String? usuario;
  final String? contrasenaNueva;
  final String? observaciones;
}

/// Validación compartida entre alta y edición de un portal del Cliente
/// — mismo patrón que `EntidadFiscalValidator`. Sin unicidad de
/// nombre/URL: el Cliente puede tener varios portales que compartan
/// cualquiera de esos datos (ej. mismo proveedor, dos cuentas).
class ClientePortalValidator {
  ClientePortalValidator(this._clienteRepository);

  final ClienteRepository _clienteRepository;

  Future<({ClientePortalValidada? resultado, List<ErrorCampoClientePortal> errores})> validar({
    required String clienteId,
    required ClientePortalBorrador borrador,
  }) async {
    final errores = <ErrorCampoClientePortal>[];

    final cliente = await _clienteRepository.obtenerPorId(clienteId);
    if (cliente == null || cliente.cicloVidaRegistro != CicloVidaRegistro.activo.name) {
      errores.add(
        const ErrorCampoClientePortal(campo: CampoClientePortal.cliente, codigo: CodigoErrorClientePortal.clienteInactivo),
      );
    }

    final nombre = borrador.nombre.trim();
    if (nombre.isEmpty) {
      errores.add(
        const ErrorCampoClientePortal(campo: CampoClientePortal.nombre, codigo: CodigoErrorClientePortal.requerido),
      );
    }

    if (errores.isNotEmpty) {
      return (resultado: null, errores: errores);
    }

    return (
      resultado: ClientePortalValidada(
        nombre: nombre,
        tipo: borrador.tipo,
        url: _vacioANull(borrador.url),
        usuario: _vacioANull(borrador.usuario),
        contrasenaNueva: _vacioANull(borrador.contrasenaNueva),
        observaciones: _vacioANull(borrador.observaciones),
      ),
      errores: const <ErrorCampoClientePortal>[],
    );
  }

  static String? _vacioANull(String? valor) {
    final limpio = valor?.trim();
    return (limpio == null || limpio.isEmpty) ? null : limpio;
  }
}
