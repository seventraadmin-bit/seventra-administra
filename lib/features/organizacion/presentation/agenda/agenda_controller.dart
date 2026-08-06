import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:riseg_one/features/organizacion/data/tables/documento_por_emitir_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/actualizar_ajuste_manual_documento_por_emitir_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cambiar_estatus_documento_por_emitir_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_documento_manual_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/documento_por_emitir_detalle.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/generar_agenda_usecase.dart';

import '../../organizacion_providers.dart';
import 'agenda_state.dart';

part 'agenda_controller.g.dart';

/// Controlador de la Agenda de documentos por emitir (Etapa 4I.1) —
/// mismo diseño que `ServiciosListController`, con acciones propias de
/// generación y ciclo de vida.
@riverpod
class AgendaController extends _$AgendaController {
  @override
  AgendaState build() {
    Future.microtask(_cargar);
    return const AgendaState();
  }

  Future<void> _cargar() async {
    state = state.copyWith(cargando: true, errorCarga: null);
    try {
      final documentos = await ref.read(documentoPorEmitirRepositoryProvider).listar(
            rangoInicio: state.rangoInicio,
            rangoFin: state.rangoFin,
            clienteId: state.clienteId,
            servicioId: state.servicioId,
            tipoDocumento: state.tipoDocumento,
            estatus: state.estatus,
          );
      state = state.copyWith(cargando: false, documentos: documentos, errorCarga: null);
    } catch (e) {
      state = state.copyWith(cargando: false, errorCarga: e.toString());
    }
  }

  Future<void> reintentarCarga() => _cargar();

  Future<void> aplicarFiltros({
    DateTime? rangoInicio,
    DateTime? rangoFin,
    String? clienteId,
    String? servicioId,
    String? tipoDocumento,
    String? estatus,
    bool limpiarClienteId = false,
    bool limpiarServicioId = false,
    bool limpiarTipoDocumento = false,
    bool limpiarEstatus = false,
  }) async {
    state = state.copyWith(
      rangoInicio: rangoInicio,
      rangoFin: rangoFin,
      clienteId: clienteId,
      servicioId: servicioId,
      tipoDocumento: tipoDocumento,
      estatus: estatus,
      limpiarClienteId: limpiarClienteId,
      limpiarServicioId: limpiarServicioId,
      limpiarTipoDocumento: limpiarTipoDocumento,
      limpiarEstatus: limpiarEstatus,
    );
    await _cargar();
  }

  Future<GenerarAgendaResultado?> generar({String? servicioId, String? clienteId}) async {
    if (state.generando) return null;
    state = state.copyWith(generando: true);

    final resultado = await ref.read(generarAgendaUseCaseProvider).ejecutar(
          rangoInicio: state.rangoInicio,
          rangoFin: state.rangoFin,
          servicioId: servicioId,
          clienteId: clienteId,
        );

    await _cargar();
    state = state.copyWith(generando: false);
    return resultado;
  }

  Future<CrearDocumentoManualResultado?> crearManual({
    required String clienteId,
    required List<String> servicioIds,
    required DateTime periodoInicio,
    required DateTime periodoFin,
    String? entidadFiscalId,
  }) async {
    if (state.generando) return null;
    state = state.copyWith(generando: true);

    final resultado = await ref.read(crearDocumentoManualUseCaseProvider).ejecutar(
          clienteId: clienteId,
          servicioIds: servicioIds,
          periodoInicio: periodoInicio,
          periodoFin: periodoFin,
          entidadFiscalId: entidadFiscalId,
        );

    if (resultado is CrearDocumentoManualExitoso) {
      await _cargar();
    }
    state = state.copyWith(generando: false);
    return resultado;
  }

  Future<CambiarEstatusDocumentoPorEmitirResultado?> cambiarEstatus({
    required String documentoPorEmitirId,
    required EstatusDocumentoPorEmitir nuevo,
    String? motivo,
  }) async {
    final resultado = await ref.read(cambiarEstatusDocumentoPorEmitirUseCaseProvider).ejecutar(
          documentoPorEmitirId: documentoPorEmitirId,
          nuevo: nuevo,
          motivo: motivo,
        );
    if (resultado is CambiarEstatusDocumentoPorEmitirExitoso) {
      await _cargar();
    }
    return resultado;
  }

  Future<ActualizarAjusteManualDocumentoPorEmitirResultado?> actualizarAjusteManual({
    required String documentoPorEmitirId,
    int? ajusteManual,
    String? motivoAjuste,
  }) async {
    final resultado = await ref.read(actualizarAjusteManualDocumentoPorEmitirUseCaseProvider).ejecutar(
          documentoPorEmitirId: documentoPorEmitirId,
          ajusteManual: ajusteManual,
          motivoAjuste: motivoAjuste,
        );
    if (resultado is ActualizarAjusteManualDocumentoPorEmitirExitoso) {
      await _cargar();
    }
    return resultado;
  }

  Future<DocumentoPorEmitirDetalle?> obtenerDetalle(String documentoPorEmitirId) {
    return ref.read(documentoPorEmitirRepositoryProvider).obtenerDetalle(documentoPorEmitirId);
  }
}
