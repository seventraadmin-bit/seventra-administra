import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/features/telefonia/domain/coherencia_linea_equipo.dart';

import '../../telefonia_providers.dart';

/// Nombres de Empleados y Servicios, ya cargados, para poner una
/// etiqueta legible a un [DestinoTelefonia] sin volver a consultar.
///
/// La comparación de destinos NUNCA usa estos nombres — se hace por
/// tipo + FK en el dominio. Esto es sólo para el mensaje.
class NombresDestinoTelefonia {
  const NombresDestinoTelefonia(this.empleados, this.servicios);

  final Map<String, String> empleados;
  final Map<String, String> servicios;

  static Future<NombresDestinoTelefonia> cargar(WidgetRef ref) async {
    final opciones = ref.read(obtenerOpcionesAsignacionLineaTelefonicaUseCaseProvider);
    final empleados = await opciones.obtenerEmpleados();
    final servicios = await opciones.obtenerServicios();
    return NombresDestinoTelefonia(
      {for (final e in empleados) e.id: e.nombre},
      {for (final s in servicios) s.id: s.nombre},
    );
  }

  String etiqueta(DestinoTelefonia? destino, AppLocalizations l10n) {
    if (destino == null) return l10n.lineaTelefonicaCoherenciaDestinoDesconocido;
    final nombre = switch (destino.tipo) {
      TipoDestinoTelefonia.empleado => empleados[destino.id],
      TipoDestinoTelefonia.servicio => servicios[destino.id],
    };
    // Si el destino ya no está en el catálogo (empleado de baja,
    // servicio archivado) se dice "otro destino" — nunca el UUID.
    return nombre ?? l10n.lineaTelefonicaCoherenciaDestinoDesconocido;
  }
}

/// El mensaje que corresponde a una incoherencia concreta. Un solo sitio
/// para los tres textos, de modo que los cinco diálogos y el expediente
/// digan exactamente lo mismo.
String? mensajeIncoherenciaLineaEquipo(
  AppLocalizations l10n,
  CoherenciaLineaEquipo coherencia,
  NombresDestinoTelefonia nombres,
) {
  return switch (coherencia.estado) {
    EstadoCoherenciaLineaEquipo.lineaSinAsignacion =>
      l10n.lineaTelefonicaCoherenciaEquipoCustodiado(nombres.etiqueta(coherencia.destinoEquipo, l10n)),
    EstadoCoherenciaLineaEquipo.equipoSinCustodia =>
      l10n.lineaTelefonicaCoherenciaEquipoSinCustodia(nombres.etiqueta(coherencia.destinoLinea, l10n)),
    EstadoCoherenciaLineaEquipo.destinosDistintos => l10n.lineaTelefonicaCoherenciaDestinosDistintos(
        nombres.etiqueta(coherencia.destinoLinea, l10n),
        nombres.etiqueta(coherencia.destinoEquipo, l10n),
      ),
    EstadoCoherenciaLineaEquipo.equipoPendienteRecuperacion =>
      l10n.lineaTelefonicaCoherenciaPendienteRecuperacion(nombres.etiqueta(coherencia.destinoEquipo, l10n)),
    EstadoCoherenciaLineaEquipo.coherente || EstadoCoherenciaLineaEquipo.sinEquipo => null,
  };
}
