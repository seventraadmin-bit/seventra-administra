import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:riseg_one/core/attachments/attachment_repository.dart';
import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/empresa_repository.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/servicio_repository.dart';
import 'package:riseg_one/features/personal/domain/repositories/asignacion_servicio_repository.dart';
import 'package:riseg_one/features/personal/domain/repositories/empleado_repository.dart';

import '../../data/pdf/resguardo_pdf_renderer.dart';
import '../repositories/articulo_repository.dart';
import '../repositories/asignacion_repository.dart';
import '../repositories/entrega_repository.dart';
import '../repositories/inventario_repository.dart';
import 'resguardo_data.dart';

sealed class GenerarDocumentoResguardoResultado {}

class GenerarDocumentoResguardoExitoso extends GenerarDocumentoResguardoResultado {
  GenerarDocumentoResguardoExitoso(this.rutaArchivo);
  final String rutaArchivo;
}

class GenerarDocumentoResguardoSinAsignaciones extends GenerarDocumentoResguardoResultado {}

class GenerarDocumentoResguardoAsignacionNoExiste extends GenerarDocumentoResguardoResultado {}

/// Las Asignaciones seleccionadas no son todas del mismo Empleado, o
/// todas del mismo Servicio — un resguardo nunca mezcla destinos.
class GenerarDocumentoResguardoDestinoInvalido extends GenerarDocumentoResguardoResultado {}

class GenerarDocumentoResguardoErrorInesperado extends GenerarDocumentoResguardoResultado {
  GenerarDocumentoResguardoErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Genera el PDF de entrega/resguardo para imprimir (Etapa 7C) — reúne
/// datos ya existentes (nunca solicita ninguno nuevo, mismo criterio
/// que `GenerarFichaTecnicaEmpleadoUseCase`), renderiza, y **abre** el
/// archivo con el visor predeterminado del sistema para que el
/// operador lo imprima. No inserta ningún `Attachment` — el documento
/// de trabajo se descarta una vez impreso; lo que se persiste es el
/// escaneo/foto ya firmado, vía `AdjuntarResguardoFirmadoUseCase`.
class GenerarDocumentoResguardoUseCase {
  GenerarDocumentoResguardoUseCase(
    this._asignacionRepository,
    this._articuloRepository,
    this._inventarioRepository,
    this._empleadoRepository,
    this._servicioRepository,
    this._empresaRepository,
    this._attachmentRepository,
    this._attachmentStorage,
    this._renderer,
    this._asignacionServicioRepository,
    this._entregaRepository,
  );

  final AsignacionRepository _asignacionRepository;
  final ArticuloRepository _articuloRepository;
  final InventarioRepository _inventarioRepository;
  final EmpleadoRepository _empleadoRepository;
  final ServicioRepository _servicioRepository;
  final EmpresaRepository _empresaRepository;
  final AttachmentRepository _attachmentRepository;
  final AttachmentStorage _attachmentStorage;
  final ResguardoPdfRenderer _renderer;
  final AsignacionServicioRepository _asignacionServicioRepository;
  final EntregaRepository _entregaRepository;

  Future<GenerarDocumentoResguardoResultado> ejecutar({required List<String> asignacionIds}) async {
    if (asignacionIds.isEmpty) return GenerarDocumentoResguardoSinAsignaciones();

    final asignaciones = <AsignacionData>[];
    for (final id in asignacionIds) {
      final asignacion = await _asignacionRepository.obtenerPorId(id);
      if (asignacion == null) return GenerarDocumentoResguardoAsignacionNoExiste();
      asignaciones.add(asignacion);
    }

    final empleadoIds = asignaciones.map((a) => a.empleadoId).toSet();
    final servicioIds = asignaciones.map((a) => a.servicioId).toSet();
    final mismoEmpleado = empleadoIds.length == 1 && empleadoIds.single != null;
    final mismoServicio = servicioIds.length == 1 && servicioIds.single != null;
    if (!mismoEmpleado && !mismoServicio) return GenerarDocumentoResguardoDestinoInvalido();

    try {
      String? empleadoNombre;
      String? servicioNombre;
      String? servicioActualNombre;
      if (mismoEmpleado) {
        final empleado = await _empleadoRepository.obtenerPorId(empleadoIds.single!);
        empleadoNombre = empleado == null
            ? null
            : [empleado.nombres, empleado.apellidoPaterno, empleado.apellidoMaterno]
                .whereType<String>()
                .where((p) => p.trim().isNotEmpty)
                .join(' ');
        final asignacionServicioVigente = await _asignacionServicioRepository.obtenerActivaPorEmpleado(empleadoIds.single!);
        if (asignacionServicioVigente != null) {
          final servicioActual = await _servicioRepository.obtenerPorId(asignacionServicioVigente.servicioId);
          servicioActualNombre = servicioActual?.nombre;
        }
      } else {
        final servicio = await _servicioRepository.obtenerPorId(servicioIds.single!);
        servicioNombre = servicio?.nombre;
      }

      final items = <ResguardoItem>[];
      for (final asignacion in asignaciones) {
        items.add(await _construirItem(asignacion));
      }

      // Folio de la Entrega (Etapa "Entrega múltiple de Inventario") —
      // solo cuando TODAS las Asignaciones vienen del mismo acto de
      // entrega; mixto o legacy (`entregaId == null`) nunca tiene folio.
      final entregaIds = asignaciones.map((a) => a.entregaId).toSet();
      String? folio;
      if (entregaIds.length == 1 && entregaIds.single != null) {
        folio = (await _entregaRepository.obtenerPorId(entregaIds.single!))?.folio;
      }

      final empresa = await _empresaRepository.obtenerActiva();
      final logoBytes = await _leerBytesAttachment(empresa.logoAttachmentId);

      final data = ResguardoData(
        empleadoNombre: empleadoNombre,
        servicioNombre: servicioNombre,
        servicioActualNombre: servicioActualNombre,
        folio: folio,
        fechaGeneracion: DateTime.now(),
        items: items,
      );
      final pdfBytes = await _renderer.renderizar(
        data: data,
        logoBytes: logoBytes,
        empresaNombreComercial: empresa.nombreComercial,
      );

      final nombreArchivo = 'resguardo_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final tempFile = File(p.join(Directory.systemTemp.path, nombreArchivo));
      await tempFile.writeAsBytes(pdfBytes);

      await _attachmentStorage.abrir(tempFile.path);

      return GenerarDocumentoResguardoExitoso(tempFile.path);
    } catch (e) {
      return GenerarDocumentoResguardoErrorInesperado(e.toString());
    }
  }

  Future<ResguardoItem> _construirItem(AsignacionData asignacion) async {
    final articulo = await _articuloRepository.obtenerPorId(asignacion.articuloId);
    final articuloNombre = articulo?.nombre ?? asignacion.articuloId;

    String? varianteLabel;
    if (asignacion.varianteId != null) {
      final variantes = await _articuloRepository.listarVariantes(asignacion.articuloId, soloActivas: false);
      varianteLabel = variantes.where((v) => v.id == asignacion.varianteId).firstOrNull?.valor;
    }

    String? unidadLabel;
    if (asignacion.unidadId != null) {
      final unidad = await _inventarioRepository.obtenerUnidadPorId(asignacion.unidadId!);
      if (unidad != null) unidadLabel = '${unidad.codigo} · ${unidad.numeroSerie}';
    }

    String? sustituyeA;
    final reemplazada = await _asignacionRepository.obtenerAsignacionReemplazada(asignacion.id);
    if (reemplazada != null) {
      final articuloAnterior = await _articuloRepository.obtenerPorId(reemplazada.articuloId);
      sustituyeA = articuloAnterior?.nombre ?? reemplazada.articuloId;
    }

    return ResguardoItem(
      articuloNombre: articuloNombre,
      varianteLabel: varianteLabel,
      unidadLabel: unidadLabel,
      cantidad: asignacion.cantidad,
      condicionEntrega: asignacion.condicionEntrega,
      sustituyeA: sustituyeA,
    );
  }

  Future<Uint8List?> _leerBytesAttachment(String? attachmentId) async {
    if (attachmentId == null) return null;
    final attachment = await _attachmentRepository.obtenerPorId(attachmentId);
    if (attachment == null) return null;
    final file = File(attachment.path);
    if (!file.existsSync()) return null;
    return file.readAsBytes();
  }
}
