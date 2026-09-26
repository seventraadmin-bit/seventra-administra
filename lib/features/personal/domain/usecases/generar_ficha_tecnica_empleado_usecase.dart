import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:riseg_one/core/attachments/attachment_repository.dart';
import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';

import '../../../organizacion/domain/repositories/catalogo_repository.dart';
import '../../../organizacion/domain/repositories/empresa_repository.dart';
import '../../../organizacion/domain/repositories/puesto_repository.dart';
import '../../../organizacion/domain/repositories/servicio_repository.dart';
import '../../data/pdf/ficha_tecnica_pdf_renderer.dart';
import '../repositories/asignacion_servicio_repository.dart';
import '../repositories/empleado_repository.dart';
import '../repositories/ficha_tecnica_empleado_repository.dart';
import 'ficha_tecnica_data.dart';

sealed class GenerarFichaTecnicaEmpleadoResultado {}

class GenerarFichaTecnicaEmpleadoExitoso extends GenerarFichaTecnicaEmpleadoResultado {
  GenerarFichaTecnicaEmpleadoExitoso(this.ficha);
  final FichaTecnicaEmpleadoData ficha;
}

class GenerarFichaTecnicaEmpleadoNoExiste extends GenerarFichaTecnicaEmpleadoResultado {}

class GenerarFichaTecnicaEmpleadoErrorInesperado extends GenerarFichaTecnicaEmpleadoResultado {
  GenerarFichaTecnicaEmpleadoErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Datos ya reunidos para armar la Ficha (`_datos`) más el `servicioId`
/// vigente del Empleado en ese momento — separado de `FichaTecnicaData`
/// porque este último es puramente lo que se *imprime*, mientras que
/// `servicioId` es metadato de relación que igual se persiste en
/// `FichaTecnicaEmpleado` aunque la sección Servicio/turno se haya
/// excluido de la impresión (Resolución 6 de Marlon: el historial debe
/// poder ligarse al Servicio/Cliente incluso si esa sección no se
/// mostró en el PDF).
class _DatosReunidos {
  const _DatosReunidos(this.ficha, this.servicioIdVigente);
  final FichaTecnicaData ficha;
  final String? servicioIdVigente;
}

/// Genera la Ficha técnica corporativa de un Empleado (Etapa 5E) — PDF
/// de una página (o dos, si el contenido lo requiere), a partir
/// exclusivamente de información ya existente en el expediente.
///
/// Orquesta, en este orden: reunir los datos ya capturados (nunca
/// solicita ninguno nuevo) → reservar el folio (`GenerarCodigoUseCase`)
/// → renderizar el PDF (`FichaTecnicaPdfRenderer`, puro) → guardarlo
/// físicamente (`AttachmentStorage`, fuera de cualquier transacción de
/// BD — igual que cualquier otro flujo de adjuntos del proyecto) →
/// insertar `Attachment` + `FichaTecnicaEmpleado` en una sola
/// transacción (`FichaTecnicaEmpleadoRepository.generar`).
class GenerarFichaTecnicaEmpleadoUseCase {
  GenerarFichaTecnicaEmpleadoUseCase(
    this._empleadoRepository,
    this._asignacionServicioRepository,
    this._servicioRepository,
    this._puestoRepository,
    this._catalogoRepository,
    this._empresaRepository,
    this._attachmentRepository,
    this._attachmentStorage,
    this._fichaTecnicaEmpleadoRepository,
    this._generarCodigo,
    this._renderer,
  );

  final EmpleadoRepository _empleadoRepository;
  final AsignacionServicioRepository _asignacionServicioRepository;
  final ServicioRepository _servicioRepository;
  final PuestoRepository _puestoRepository;
  final CatalogoRepository _catalogoRepository;
  final EmpresaRepository _empresaRepository;
  final AttachmentRepository _attachmentRepository;
  final AttachmentStorage _attachmentStorage;
  final FichaTecnicaEmpleadoRepository _fichaTecnicaEmpleadoRepository;
  final GenerarCodigoUseCase _generarCodigo;
  final FichaTecnicaPdfRenderer _renderer;

  Future<GenerarFichaTecnicaEmpleadoResultado> ejecutar({
    required String empleadoId,
    Set<String> seccionesExcluidas = const {},
  }) async {
    final empleado = await _empleadoRepository.obtenerPorId(empleadoId);
    if (empleado == null) return GenerarFichaTecnicaEmpleadoNoExiste();

    try {
      final reunidos = await _reunirDatos(empleado, seccionesExcluidas);

      final fotografiaBytes = await _leerBytesAttachment(reunidos.ficha.fotografiaAttachmentId);
      final empresa = await _empresaRepository.obtenerActiva();
      final logoBytes = await _leerBytesAttachment(empresa.logoAttachmentId);

      final folioResultado = await _generarCodigo.ejecutar('ficha_tecnica');
      final folio = folioResultado.when(ok: (c) => c, failure: (f) => throw StateError(f.message));

      final ahora = DateTime.now();
      final pdfBytes = await _renderer.renderizar(
        data: reunidos.ficha,
        folio: folio,
        fechaGeneracion: ahora,
        logoBytes: logoBytes,
        fotografiaBytes: fotografiaBytes,
        empresaNombreComercial: empresa.nombreComercial,
      );

      // `Directory.systemTemp` (dart:io puro, sin canal de plataforma) —
      // solo un archivo de paso: `AttachmentStorage.guardar` lo copia de
      // inmediato a su ubicación definitiva, así que no necesita vivir
      // en el directorio temporal *de la app* (`path_provider`).
      final nombreArchivo = 'ficha_tecnica_${empleadoId}_${ahora.millisecondsSinceEpoch}.pdf';
      final tempFile = File(p.join(Directory.systemTemp.path, nombreArchivo));
      await tempFile.writeAsBytes(pdfBytes);

      final guardado = await _attachmentStorage.guardar(
        ownerId: empleadoId,
        categoria: 'fichaTecnica',
        sourceFilePath: tempFile.path,
        originalFileName: 'Ficha_tecnica_$folio.pdf',
      );
      // `guardar` copia, nunca mueve — el archivo de paso ya no hace
      // falta. Falla en silencio si algo más ya lo limpió: no debe
      // tumbar una generación que por lo demás fue exitosa.
      try {
        await tempFile.delete();
      } catch (_) {}

      final ficha = await _fichaTecnicaEmpleadoRepository.generar(
        empleadoId: empleadoId,
        folio: folio,
        servicioId: seccionesExcluidas.contains(SeccionFichaTecnica.servicioTurno) ? null : reunidos.servicioIdVigente,
        camposExcluidos: seccionesExcluidas.isEmpty ? null : seccionesExcluidas.join(','),
        originalFileName: guardado.storedFileName,
        storedFileName: guardado.storedFileName,
        path: guardado.path,
        mimeType: 'application/pdf',
        sizeBytes: guardado.sizeBytes,
      );

      return GenerarFichaTecnicaEmpleadoExitoso(ficha);
    } catch (e) {
      return GenerarFichaTecnicaEmpleadoErrorInesperado(e.toString());
    }
  }

  Future<_DatosReunidos> _reunirDatos(EmpleadoData empleado, Set<String> seccionesExcluidas) async {
    final domicilio = await _empleadoRepository.obtenerDomicilio(empleado.id);

    String? puestoNombre;
    if (empleado.puestoId != null) {
      final puesto = await _puestoRepository.obtenerPorId(empleado.puestoId!);
      puestoNombre = puesto?.nombre;
    }

    String? servicioIdVigente;
    String? servicioNombre;
    String? turnoNombre;
    final asignacion = await _asignacionServicioRepository.obtenerActivaPorEmpleado(empleado.id);
    if (asignacion != null) {
      servicioIdVigente = asignacion.servicioId;
      final servicio = await _servicioRepository.obtenerPorId(asignacion.servicioId);
      servicioNombre = servicio?.nombre;
      if (asignacion.turnoId != null) {
        final modalidades = await _catalogoRepository.listarModalidadesTurno();
        for (final m in modalidades) {
          if (m.id == asignacion.turnoId) turnoNombre = m.nombre;
        }
      }
    }

    final ficha = construirFichaTecnicaData(
      empleado: empleado,
      domicilio: domicilio,
      puestoNombre: puestoNombre,
      servicioNombre: servicioNombre,
      turnoNombre: turnoNombre,
      seccionesExcluidas: seccionesExcluidas,
    );

    return _DatosReunidos(ficha, servicioIdVigente);
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
