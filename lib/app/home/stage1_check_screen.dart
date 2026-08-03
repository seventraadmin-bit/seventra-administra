import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_info.dart';
import '../../core/di/providers.dart';
import '../theme/theme_mode_controller.dart';

/// Pantalla mínima de verificación de la Etapa 1 (Infraestructura).
///
/// No es una pantalla de negocio ni un dashboard: solo confirma que
/// arranque, rutas, localización, tema, Riverpod, Drift y logging
/// funcionan correctamente. Se reemplaza por el Shell real en la Etapa 2.
class Stage1CheckScreen extends ConsumerWidget {
  const Stage1CheckScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final env = ref.watch(envProvider);
    final themeMode = ref.watch(themeModeControllerProvider);
    final metadataAsync = ref.watch(_appMetadataProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.appTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.appSubtitle, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 16),
                Text(l10n.stage1CheckTitle, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 12),
                Text(l10n.stage1CheckDescription),
                const SizedBox(height: 24),
                Text('APP_ENV: ${env.name}'),
                const SizedBox(height: 8),
                metadataAsync.when(
                  data: (metadata) => Text(
                    'Instalación: ${metadata.installationId}\n'
                    'Instalada: ${metadata.installedAt}\n'
                    'Último acceso: ${metadata.lastOpenedAt}\n'
                    'Versión: ${metadata.appVersion}',
                  ),
                  loading: () => const Text('Leyendo metadata de la base de datos…'),
                  error: (error, stack) => Text('Error leyendo la base de datos: $error'),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Text('${l10n.themeModeLabel}: '),
                    const SizedBox(width: 8),
                    DropdownButton<ThemeMode>(
                      value: themeMode,
                      onChanged: (mode) {
                        if (mode != null) {
                          ref.read(themeModeControllerProvider.notifier).setThemeMode(mode);
                        }
                      },
                      items: [
                        DropdownMenuItem(value: ThemeMode.light, child: Text(l10n.themeModeLight)),
                        DropdownMenuItem(value: ThemeMode.dark, child: Text(l10n.themeModeDark)),
                        DropdownMenuItem(value: ThemeMode.system, child: Text(l10n.themeModeSystem)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final _appMetadataProvider = FutureProvider.autoDispose((ref) {
  final database = ref.watch(appDatabaseProvider);
  return database.ensureMetadata(appVersion: kAppVersion);
});
