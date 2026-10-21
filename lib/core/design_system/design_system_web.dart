/// El Design System para la app WEB: los mismos componentes, menos el que no
/// compila para el navegador.
///
/// **Existe por un export.** `design_system.dart` exporta
/// `riseg_entity_identity.dart`, que lee una imagen del disco con `File()` de
/// `dart:io`. Un solo `import` del barrel completo arrastra eso y la build web
/// falla — sin que nada en el código de la pantalla parezca estar mal.
///
/// **Por qué un barrel aparte y no importar componentes uno por uno.** Lo segundo
/// también funciona, pero nada impide escribir el barrel completo por costumbre
/// hasta que la build falle. Así el que no compila **no está al alcance**, y una
/// prueba de arquitectura lo exige en vez de dejarlo a la memoria.
///
/// ⏳ **Lo que lo haría innecesario:** volver `riseg_entity_identity` compatible con
/// web por importación condicional, como se hizo con `api_client`. Se decidió NO
/// hacerlo ahora: ninguna pantalla de M3 muestra un logo, y arrastrar esa limpieza
/// era justo lo que se decidió no arrastrar. El día que una pantalla lo necesite, la
/// limpieza será suya y este archivo podrá desaparecer.
library;

export 'tokens/app_breakpoints.dart';
export 'tokens/app_chart_palette.dart';
export 'tokens/app_color_scheme.dart';
export 'tokens/app_colors.dart';
export 'tokens/app_durations.dart';
export 'tokens/app_radius.dart';
export 'tokens/app_shadows.dart';
export 'tokens/app_sizes.dart';
export 'tokens/app_spacing.dart';
export 'tokens/app_typography.dart';
export 'theme_context.dart';
export 'components/riseg_actions_menu.dart';
export 'components/riseg_aging_bars.dart';
export 'components/riseg_bar_chart.dart';
export 'components/riseg_chart_card.dart';
export 'components/riseg_composition_chart.dart';
export 'components/riseg_kpi_grid.dart';
export 'components/riseg_button.dart';
export 'components/riseg_card.dart';
export 'components/riseg_checkbox.dart';
export 'components/riseg_dialog.dart';
export 'components/riseg_empty_state.dart';
export 'components/riseg_feedback.dart';
export 'components/riseg_field_grid.dart';
export 'components/riseg_foco_y_vista.dart';
export 'components/riseg_form_section.dart';
export 'components/riseg_motivo_dialog.dart';
export 'components/riseg_search_field.dart';
export 'components/riseg_search_select.dart';
export 'components/riseg_section_header.dart';
export 'components/riseg_select.dart';
export 'components/riseg_stat_card.dart';
export 'components/riseg_progress_bar.dart';
export 'components/riseg_status_badge.dart';
export 'components/riseg_table_base.dart';
export 'components/riseg_tabs.dart';
export 'components/riseg_text_field.dart';
export 'components/riseg_date_field.dart';
export 'components/riseg_eliminar_fisicamente_dialog.dart';
export 'components/riseg_time_field.dart';
