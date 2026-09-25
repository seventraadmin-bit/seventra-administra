// Etapa 5B.1 — corrección P0.
//
// Esta prueba existe por un incidente real, no por completar cobertura.
//
// `AppPaths.resolve` delegaba en `getApplicationSupportDirectory()`. En
// Windows ese método construye la ruta como
// `%APPDATA%\<CompanyName>\<ProductName>` leyendo esos dos valores de los
// **metadatos del ejecutable**. Al renombrar `ProductName` de "RISEG ONE" a
// "Seventra Administra", la aplicación pasó a abrir una carpeta distinta,
// encontró una base vacía y mostró el alta del primer Maestro como si fuera
// una instalación nueva. Los datos seguían intactos en su sitio; nadie los
// estaba mirando.
//
// La lección: la ubicación de los datos del usuario no puede depender del
// nombre comercial del producto. Estas pruebas fijan ese anclaje.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:riseg_one/core/config/app_paths.dart';
import 'package:riseg_one/core/config/env.dart';

void main() {
  group('La carpeta de datos está anclada, no depende de la marca', () {
    test('el fabricante y el producto son los de la instalación original', () {
      // Si alguien "actualiza" estas constantes al nombre comercial nuevo,
      // todos los usuarios con datos arrancarán vacíos. Mover esta carpeta
      // exige una migración, no editar una constante.
      expect(AppPaths.carpetaFabricante, 'RISEG');
      expect(AppPaths.carpetaProducto, 'RISEG ONE');
    });

    test('en Windows la raíz cuelga de %APPDATA%\\RISEG\\RISEG ONE', () async {
      if (!Platform.isWindows) return;
      final appData = Platform.environment['APPDATA'];
      if (appData == null || appData.isEmpty) return;

      final rutas = await AppPaths.resolve(Env.prod);
      expect(rutas.rootDir, p.join(appData, 'RISEG', 'RISEG ONE', 'RISEGONE'));
      expect(rutas.databaseFile, endsWith(p.join('RISEGONE', 'riseg_one.sqlite')));
    });

    test('el nombre del archivo de base de datos no cambió', () async {
      final rutas = await AppPaths.resolve(Env.prod);
      // Es el mismo nombre que viaja dentro de los respaldos v2.
      expect(p.basename(rutas.databaseFile), 'riseg_one.sqlite');
    });

    test('desarrollo y producción siguen separados', () async {
      final dev = await AppPaths.resolve(Env.dev);
      final prod = await AppPaths.resolve(Env.prod);

      expect(p.basename(dev.rootDir), 'RISEGONE-dev');
      expect(p.basename(prod.rootDir), 'RISEGONE');
      expect(dev.rootDir, isNot(prod.rootDir));
      // Pero cuelgan de la MISMA raíz: el entorno separa, la marca no.
      expect(p.dirname(dev.rootDir), p.dirname(prod.rootDir));
    });

    test('ninguna ruta derivada menciona el nombre comercial nuevo', () async {
      final rutas = await AppPaths.resolve(Env.prod);
      for (final ruta in [
        rutas.rootDir,
        rutas.databaseFile,
        rutas.attachmentsDir,
        rutas.backupsDir,
        rutas.restorePendingDir,
        rutas.restoreOldDir,
        rutas.portableStagingDir,
      ]) {
        expect(
          ruta.toLowerCase(),
          isNot(contains('seventra')),
          reason: 'la marca del producto no puede aparecer en la ruta de los datos',
        );
      }
    });
  });
}
