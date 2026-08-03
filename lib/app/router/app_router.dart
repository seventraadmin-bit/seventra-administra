import 'package:go_router/go_router.dart';

import '../home/stage1_check_screen.dart';

/// Configuración de rutas de RISEG ONE.
///
/// Deliberadamente mínima en esta etapa: una sola ruta que confirma que el
/// arranque funciona. El Shell real (sidebar + top bar + rutas anidadas de
/// cada módulo) se construye en la Etapa 2 sobre esta misma base.
final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const Stage1CheckScreen(),
    ),
  ],
);
