// Los límites de la app WEB, verificados sobre el árbol de código.
//
// ESTAS PRUEBAS NO MIRAN COMPORTAMIENTO, MIRAN ALCANCE. La web se construye con
// `-t lib/main_web.dart` y crece módulo a módulo; lo que la rompe no es un error de
// lógica, es un `import` que arrastra algo que el navegador no tiene. Y cuando eso
// pasa, la build falla con un mensaje que no menciona el archivo culpable.
//
// POR QUÉ ACOTADAS Y NO SOBRE TODO `lib/`. `dart:io` está en 43 archivos, la mayoría
// de `respaldo`, `reportes` y PDF. Exigir web limpio en todo el árbol obligaría a
// cada etapa a arrastrar una limpieza que no le toca. Así que la lista de lo que la
// web alcanza se declara aquí y **se aprieta etapa a etapa**: el día que cubra todo
// `lib/`, la mudanza terminó.
//
// Leen los archivos reales, así que no se pueden satisfacer por accidente.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  /// Lo que la app web alcanza HOY. **Esta lista es el contrato de la etapa.**
  ///
  /// Crece cuando una etapa conecta una pantalla nueva, y nunca al revés: quitar una
  /// entrada para que una prueba pase sería apagar el guardia.
  /// ⚠️ **LA ENTRADA DE ORGANIZACIÓN ESTABA MAL ESCRITA Y ESTA PRUEBA NO MIRABA LA
  /// PANTALLA DE ÁREAS.** Decía `features/organizacion/presentation/web/`, y la
  /// carpeta real es `features/organizacion/web/presentation/`. La prueba pasaba
  /// porque no cubría nada: era un verde falso.
  ///
  /// Es el riesgo propio de un guardia declarado con cadenas de texto — una ruta
  /// inexistente no falla, se calla—, así que la lección se queda escrita aquí: al
  /// añadir una entrada, **comprobar que de verdad hay archivos debajo**. La última
  /// prueba de este archivo lo hace ahora para todas.
  const alcanzadoPorLaWeb = <String>[
    'lib/main_web.dart',
    'lib/core/api/',
    // C1 — EL SELECTOR DE LOGOTIPO Y SU FIRMA, que dejaron de ser de Organización
    // cuando el alta de un cliente necesitó el mismo recorrido. Vigilarlos aquí
    // importa más que antes: `firma_de_logotipo.dart` existe precisamente porque su
    // archivo vecino del escritorio abre un `File`.
    'lib/core/archivos/',
    'lib/core/auth/',
    'lib/core/company/',
    // EL ARCHIVO Y NO LA CARPETA: `core/config/app_paths.dart` resuelve rutas del
    // disco con `dart:io` y es del escritorio. La web sólo alcanza la configuración
    // de la API, así que se nombra ésa.
    'lib/core/config/api_config.dart',
    'lib/core/design_system/',
    'lib/core/error/',
    'lib/core/logging/',
    // LA WEB ALCANZA EL TEMA DEL PRODUCTO DESDE M3, y no por comodidad: el Design
    // System lee sus colores con `extension<AppColorScheme>()!`, así que la web
    // necesita el MISMO `ThemeData` que instala esa extensión. Un tema propio
    // devolvía la pantalla roja a Áreas.
    'lib/app/theme/',
    // Y DESDE EL MARCO, EL SHELL ENTERO. La web **reutiliza** `AppSidebar`,
    // `AppBreadcrumb`, `ShellDestination`, `ShellBreakpoints` y
    // `ModulePlaceholderScreen` en vez de dibujar los suyos: es lo que hace que se
    // vea igual que el escritorio y no parecida. Que estén aquí significa que
    // ninguno puede volverse dependiente de `dart:io` sin que esta prueba lo diga.
    'lib/app/shell/',
    'lib/core/branding/',
    // El panel oscuro del login, que el login web reutiliza tal cual.
    'lib/features/usuarios/presentation/auth/widgets/auth_identity_panel.dart',
    // C1 — la cartera comercial, que es la primera pantalla de un módulo contratado.
    'lib/features/comercial/web/',
    // C1 — el ayudante del «hoy» del negocio (D-55). Entra en la lista porque la web lo
    // alcanza desde el alta de un cliente: es el único sitio que aplica el −06:00.
    'lib/core/fechas/',
    'lib/features/organizacion/web/',
    'lib/features/usuarios/web/',
  ];

  /// Lo que la lista de arriba NO incluye aunque esté dentro de una carpeta suya.
  ///
  /// `riseg_entity_identity.dart` lee una imagen del disco con `File()`, y por eso
  /// existe `design_system_web.dart` sin él. El archivo se queda donde está —el
  /// escritorio lo usa— y lo que se vigila es que **nadie lo alcance desde la web**.
  const exentos = <String>[
    'lib/core/design_system/components/riseg_entity_identity.dart',
    'lib/core/design_system/design_system.dart',
    'lib/core/api/fallo_de_conexion_io.dart',
  ];

  bool estaExento(String ruta) => exentos.any(ruta.replaceAll(r'\', '/').endsWith);

  List<File> fuentesAlcanzadas() => Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) {
        final ruta = f.path.replaceAll(r'\', '/');

        if (!ruta.endsWith('.dart') || ruta.endsWith('.g.dart')) return false;
        if (estaExento(ruta)) return false;

        return alcanzadoPorLaWeb.any(ruta.contains);
      })
      .toList();

  /// Las líneas de código, sin comentarios.
  ///
  /// **SE IGNORAN LOS COMENTARIOS, y no es una concesión.** Los dos archivos de
  /// `fallo_de_conexion_*` explican en prosa por qué `dart:io` no puede importarse
  /// aquí, y un guardia que se dispare contra su propia explicación obliga a borrar
  /// la explicación. Es el quinto tropiezo del proyecto con lo mismo.
  Iterable<String> codigo(File f) => f
      .readAsLinesSync()
      .where((l) {
        final t = l.trimLeft();

        return !t.startsWith('//') && !t.startsWith('///') && !t.startsWith('*');
      });

  test('Ningún archivo que la web alcanza importa dart:io ni dart:ffi', () {
    final culpables = <String>[];

    for (final f in fuentesAlcanzadas()) {
      final lineas = codigo(f).toList();

      for (var i = 0; i < lineas.length; i++) {
        final l = lineas[i];

        // SE BUSCA EL `import`, no la cadena: `fallo_de_conexion_web.dart` menciona
        // `dart:io` en su documentación para explicar por qué NO lo usa, y eso es
        // prosa. Lo que rompe la build es la directiva.
        if (l.contains("import 'dart:io'") || l.contains("import 'dart:ffi'")) {
          culpables.add('${f.path}:${i + 1}  →  ${l.trim()}');
        }
      }
    }

    expect(
      culpables,
      isEmpty,
      reason:
          'Estos archivos los alcanza la app web y no compilarán para el navegador:\n'
          '${culpables.join('\n')}\n\n'
          'Si de verdad hace falta esa biblioteca, se resuelve con importación '
          'condicional —ver lib/core/api/fallo_de_conexion_io.dart— y NO quitando '
          'el archivo de la lista de alcanzados.',
    );
  });

  test('Lo que la web alcanza importa design_system_web, nunca el barrel completo', () {
    // EL BARREL COMPLETO EXPORTA `riseg_entity_identity`, que trae `dart:io`. Un
    // `import` del barrel rompe la build web **sin que nada en la pantalla parezca
    // estar mal**: el error habla de `dart:io` en un archivo que la pantalla nunca
    // nombró. Por eso se vigila el import y no sólo el resultado.
    final culpables = <String>[];

    for (final f in fuentesAlcanzadas()) {
      final lineas = codigo(f).toList();

      for (var i = 0; i < lineas.length; i++) {
        final l = lineas[i];

        // `design_system_web.dart` también termina en `design_system.dart`... no:
        // termina en `_web.dart`. Se exige la comilla de cierre justo después para
        // no confundirlos.
        if (l.contains("design_system/design_system.dart'") ||
            l.contains("/design_system.dart'") && !l.contains('_web.dart')) {
          culpables.add('${f.path}:${i + 1}  →  ${l.trim()}');
        }
      }
    }

    expect(
      culpables,
      isEmpty,
      reason:
          'Estos archivos son de la web y usan el barrel completo del Design '
          'System:\n${culpables.join('\n')}\n\n'
          'Usa design_system_web.dart, que exporta los 39 componentes que sí '
          'compilan para el navegador.',
    );
  });

  test('El barrel web NO exporta el componente que lee del disco', () {
    // La contraparte, y hace falta: sin ella, alguien podría añadir el export que
    // falta «para que no falte nada» y las dos pruebas de arriba seguirían pasando
    // hasta que fallara la build.
    final web = File('lib/core/design_system/design_system_web.dart');

    expect(web.existsSync(), isTrue, reason: 'Falta design_system_web.dart.');

    final exports = web
        .readAsLinesSync()
        .where((l) => l.trimLeft().startsWith('export '))
        .toList();

    expect(
      exports.where((l) => l.contains('riseg_entity_identity')),
      isEmpty,
      reason:
          'design_system_web.dart exporta riseg_entity_identity, que importa '
          'dart:io. Eso anula la razón de que este barrel exista.',
    );

    // Y QUE NO SE QUEDE ATRÁS DEL COMPLETO: si alguien añade un componente nuevo al
    // barrel de escritorio y olvida el web, la web se queda sin él y nadie lo nota
    // hasta que una pantalla lo necesita.
    final completo = File('lib/core/design_system/design_system.dart')
        .readAsLinesSync()
        .where((l) => l.trimLeft().startsWith('export '))
        .toList();

    expect(
      exports.length,
      completo.length - 1,
      reason:
          'El barrel web tiene ${exports.length} exports y el completo '
          '${completo.length}. Deberían diferir en exactamente uno '
          '(riseg_entity_identity). Si se añadió un componente al completo, añádelo '
          'también al web.',
    );
  });

  test('Cada entrada de la lista de alcanzados apunta a algo que existe', () {
    // ESTA PRUEBA NACE DE UN VERDE FALSO MEDIDO, no de una precaución teórica.
    //
    // `lib/features/organizacion/presentation/web/` estuvo en la lista y la carpeta
    // real era `lib/features/organizacion/web/presentation/`. Las dos pruebas de
    // arriba pasaban **sin mirar la pantalla de Áreas**, porque una ruta que no
    // coincide con ningún archivo no deja rastro: no hay error, no hay aviso, y el
    // guardia parece estar puesto.
    //
    // Es el mismo problema que las listas exactas del backend, por el otro lado: ahí
    // el riesgo es fijar de más, y aquí fijar de menos sin notarlo.
    final vacias = <String>[];

    for (final entrada in alcanzadoPorLaWeb) {
      final coincidencias = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) {
            final ruta = f.path.replaceAll(r'\', '/');

            return ruta.endsWith('.dart') && ruta.contains(entrada);
          });

      if (coincidencias.isEmpty) vacias.add(entrada);
    }

    expect(
      vacias,
      isEmpty,
      reason:
          'Estas entradas de `alcanzadoPorLaWeb` no coinciden con ningún archivo, '
          'así que no vigilan nada:\n${vacias.join('\n')}\n\n'
          'Corrige la ruta. Quitarla sería apagar el guardia que se quería poner.',
    );
  });
}
