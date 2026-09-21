// Etapa 1B (cierre de seguridad): auditor estático de "providers
// crudos" — detecta cuándo Presentation lee directo (`ref.read`/
// `ref.watch`) un provider de mutación que YA tiene una vía autorizada
// en algún otro archivo, saltándosela.
//
// Diseño (ver el reporte de la Etapa 1B para la justificación completa):
// nunca adivina "qué use case es una mutación" por su nombre — eso fue
// exactamente lo que la auditoría de Etapa 0 descartó como riesgoso
// (`generarDocumentoResguardoUseCaseProvider`/PDFs/XLSX/consultas nunca
// deben marcarse). En vez de eso, un provider se considera "protegido"
// ÚNICAMENTE cuando el propio código YA lo envuelve en
// `autorizarUseCase(...)`/`exigirMaestro(...)` en algún archivo — esa
// llamada es la señal real, inequívoca, de que la operación exige
// permiso; nunca una heurística sobre el nombre. El archivo donde
// aparece esa envoltura es el "dueño" legítimo del provider crudo.
// Cualquier OTRO archivo que lea ese mismo provider crudo directamente
// es una violación — sin importar si ese otro archivo es un diálogo,
// una pantalla, u otro controller.
//
// Dos pasadas sobre `lib/**/*.dart` (nunca `*.g.dart`):
//   1. Registro: busca cada `autorizarUseCase(`/`exigirMaestro(` y, en
//      las líneas siguientes, el primer `ref.read(<provider>).<metodo>(`
//      que envuelve — ESE es el provider protegido, dueño = este archivo.
//   2. Violaciones: busca cada `ref.read(<provider>)`/`ref.watch(<provider>)`
//      en todo `lib/`; si `<provider>` está en el registro y el archivo
//      actual NO es su dueño, es una violación real.
//
// Uso: `dart run tool/auditor_providers_crudos.dart [--dump-registro] [<ruta-lib>]`
// Exit code 0 sin violaciones, 1 si encuentra al menos una (listo para CI).

// ignore_for_file: avoid_print — es un script de línea de comandos, su
// única salida es stdout/stderr, nunca la UI de la app.

import 'dart:io';

/// Una entrada del registro de providers protegidos — `provider` es el
/// identificador crudo (ej. `registrarEgresoUseCaseProvider`),
/// `archivoDueno`/`lineaDueno` marcan dónde se encontró la envoltura de
/// autorización que lo hace protegido, y `wrapperEsperado` es el
/// nombre legible (mejor esfuerzo) del provider/método que SÍ debe
/// usarse en su lugar.
class ProviderProtegido {
  ProviderProtegido({
    required this.provider,
    required this.archivoDueno,
    required this.lineaDueno,
    required this.wrapperEsperado,
  });

  final String provider;
  final String archivoDueno;
  final int lineaDueno;
  final String wrapperEsperado;
}

class Violacion {
  Violacion({
    required this.archivo,
    required this.linea,
    required this.provider,
    required this.wrapperEsperado,
  });

  final String archivo;
  final int linea;
  final String provider;
  final String wrapperEsperado;

  @override
  String toString() => '$archivo:$linea | $provider | esperado: $wrapperEsperado';
}

final _regexAutorizacion = RegExp(r'\b(autorizarUseCase|exigirMaestro)\s*\(');

// Deliberadamente exige `.ejecutar(` — nunca cualquier método — en
// AMBAS pasadas. Dos falsos positivos reales, encontrados corriendo
// este auditor contra el `lib/` real, motivaron esta restricción:
//   1. Varios diálogos de eliminación física llaman
//      `ref.read(xxxUseCaseProvider).obtenerResumen(id)` para el texto
//      de confirmación (una consulta, nunca la mutación) ANTES de
//      llamar al provider autorizado para el borrado real — sin exigir
//      `.ejecutar(` específicamente, esa consulta se marcaba como si
//      fuera la mutación misma.
//   2. `ref.watch(xxxRepositoryProvider)` dentro del constructor de
//      OTRO use case (inyección de dependencias pura, ej.
//      `LoginUseCase(ref.watch(permisoUsuarioRepositoryProvider), ...)`)
//      no es "invocar" nada — un match sin exigir `.ejecutar(`
//      confundía esa referencia con una llamada real.
final _regexInvocaEjecutar = RegExp(r'ref\.(?:read|watch)\((\w+)\)\s*\.\s*ejecutar\s*\(');
final _regexProviderDecl = RegExp(r'^\s*final\s+(\w+)\s*=\s*Provider');
final _regexMetodoDecl = RegExp(r'^\s{2,6}(?:Future(?:<[^>]*>)?|void|[A-Z]\w*)\s+(\w+)\s*\(');
final _regexClaseDecl = RegExp(r'^class\s+(\w+)');

/// Lista todos los `.dart` bajo [dir], nunca `*.g.dart` (generados).
List<File> _listarArchivosDart(Directory dir) {
  return dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'))
      .toList();
}

/// Mejor esfuerzo: encuentra el nombre del provider/método que
/// envuelve la línea [indiceAutorizacion] (0-based) dentro de [lineas],
/// buscando hacia atrás la declaración más cercana. Solo afecta la
/// columna de reporte "wrapper esperado" — nunca la lógica de
/// detección de violaciones (que depende únicamente del nombre del
/// provider crudo, no de este nombre).
String _nombreEnvolvente(List<String> lineas, int indiceAutorizacion) {
  String? claseCercana;
  for (var i = indiceAutorizacion; i >= 0; i--) {
    final linea = lineas[i];
    final matchProvider = _regexProviderDecl.firstMatch(linea);
    if (matchProvider != null) return matchProvider.group(1)!;

    final matchMetodo = _regexMetodoDecl.firstMatch(linea);
    if (matchMetodo != null) {
      // Sigue buscando hacia atrás la clase contenedora, para reportar
      // `Clase.metodo` en vez de solo `metodo`.
      for (var j = i; j >= 0; j--) {
        final matchClase = _regexClaseDecl.firstMatch(lineas[j]);
        if (matchClase != null) {
          claseCercana = matchClase.group(1);
          break;
        }
      }
      final metodo = matchMetodo.group(1)!;
      return claseCercana != null ? '$claseCercana.$metodo' : metodo;
    }
  }
  return '(sin identificar)';
}

/// Pasada 1 — construye el registro de providers protegidos a partir
/// de toda envoltura `autorizarUseCase`/`exigirMaestro` ya existente en
/// [libDir]. Devuelve un mapa `provider -> lista de dueños` (rara vez
/// más de uno; se admite más de un archivo dueño legítimo si el mismo
/// provider llegara a envolverse en más de un lugar).
Map<String, List<ProviderProtegido>> descubrirProvidersProtegidos(Directory libDir) {
  final registro = <String, List<ProviderProtegido>>{};

  for (final archivo in _listarArchivosDart(libDir)) {
    final lineas = archivo.readAsLinesSync();
    for (var i = 0; i < lineas.length; i++) {
      if (!_regexAutorizacion.hasMatch(lineas[i])) continue;

      // Busca, en esta línea y hasta 15 líneas siguientes, el primer
      // `ref.read(<provider>).<metodo>(` — ese es el provider envuelto.
      String? providerEncontrado;
      for (var j = i; j < lineas.length && j < i + 15; j++) {
        final m = _regexInvocaEjecutar.firstMatch(lineas[j]);
        if (m != null) {
          providerEncontrado = m.group(1);
          break;
        }
      }
      if (providerEncontrado == null) continue;

      final wrapper = _nombreEnvolvente(lineas, i);
      registro
          .putIfAbsent(providerEncontrado, () => [])
          .add(ProviderProtegido(
            provider: providerEncontrado,
            archivoDueno: archivo.path,
            lineaDueno: i + 1,
            wrapperEsperado: wrapper,
          ));
    }
  }

  return registro;
}

/// Pasada 2 — cualquier `ref.read`/`ref.watch` de un provider ya
/// registrado como protegido, fuera de TODOS sus archivos dueños, es
/// una violación real.
List<Violacion> buscarViolaciones(Directory libDir, Map<String, List<ProviderProtegido>> registro) {
  final violaciones = <Violacion>[];

  for (final archivo in _listarArchivosDart(libDir)) {
    final lineas = archivo.readAsLinesSync();
    for (var i = 0; i < lineas.length; i++) {
      for (final m in _regexInvocaEjecutar.allMatches(lineas[i])) {
        final provider = m.group(1)!;
        final duenos = registro[provider];
        if (duenos == null) continue;
        final esDueno = duenos.any((d) => d.archivoDueno == archivo.path);
        if (esDueno) continue;

        violaciones.add(Violacion(
          archivo: archivo.path,
          linea: i + 1,
          provider: provider,
          wrapperEsperado: duenos.map((d) => d.wrapperEsperado).join(' / '),
        ));
      }
    }
  }

  return violaciones;
}

void main(List<String> args) {
  final dumpRegistro = args.contains('--dump-registro');
  final rutaLib = args.firstWhere((a) => !a.startsWith('--'), orElse: () => 'lib');
  final libDir = Directory(rutaLib);

  if (!libDir.existsSync()) {
    stderr.writeln('No existe el directorio "$rutaLib".');
    exit(2);
  }

  final registro = descubrirProvidersProtegidos(libDir);

  if (dumpRegistro) {
    print('--- Registro de providers protegidos (${registro.length}) ---');
    final claves = registro.keys.toList()..sort();
    for (final provider in claves) {
      for (final dueno in registro[provider]!) {
        print('$provider  →  ${dueno.archivoDueno}:${dueno.lineaDueno}  (${dueno.wrapperEsperado})');
      }
    }
    print('');
  }

  final violaciones = buscarViolaciones(libDir, registro);

  if (violaciones.isEmpty) {
    print('Auditor de providers crudos: sin violaciones (${registro.length} providers protegidos revisados).');
    exit(0);
  }

  print('Auditor de providers crudos: ${violaciones.length} violación(es) encontrada(s).');
  print('archivo | línea | provider crudo | wrapper autorizado esperado');
  for (final v in violaciones) {
    print('${v.archivo} | ${v.linea} | ${v.provider} | ${v.wrapperEsperado}');
  }
  exit(1);
}
