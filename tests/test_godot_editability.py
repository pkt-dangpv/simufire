"""
tests/test_godot_editability.py

Product guardrails for inspector-editable Godot knobs.

These tests keep high-impact editor, HUD, FP and 3D presentation controls
visible as @export properties. They are intentionally lightweight text checks:
the goal is to prevent accidental hardcoding regressions without requiring a
Godot process for every editability contract.
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path


_REPO_ROOT = Path(__file__).resolve().parent.parent
_EXPORT_RE = re.compile(
    r"^\s*@export(?:_[A-Za-z0-9]+)?(?:\([^)\n]*\))?\s+var\s+([A-Za-z_][A-Za-z0-9_]*)",
    re.MULTILINE,
)


def _read(rel_path: str) -> str:
    return (_REPO_ROOT / rel_path).read_text(encoding="utf-8")


def _exported_names(text: str) -> set[str]:
    return set(_EXPORT_RE.findall(text))


class TestGodotEditability(unittest.TestCase):
    def assert_exports(self, rel_path: str, expected_names: list[str]) -> None:
        names = _exported_names(_read(rel_path))
        missing = sorted(set(expected_names) - names)
        self.assertEqual(missing, [], f"Missing @export names in {rel_path}: {missing}")

    def assert_identifier_used(self, rel_path: str, name: str, min_count: int = 2) -> None:
        text = _read(rel_path)
        count = len(re.findall(rf"\b{re.escape(name)}\b", text))
        self.assertGreaterEqual(
            count,
            min_count,
            f"{name} should be declared and used in {rel_path}; found {count} occurrence(s)",
        )

    def test_editor_layout_and_typography_are_editable(self):
        rel = "editor/ScenarioEditor.gd"
        expected = [
            "load_error_dialog_title",
            "max_undo_steps",
            "pixels_per_meter",
            "hover_help_delay_s",
            "hover_help_move_tolerance_px",
            "editor_left_panel_width_px",
            "editor_right_panel_width_px",
            "editor_side_panel_top_px",
            "editor_side_panel_bottom_px",
            "editor_top_bar_height_px",
            "editor_font_size_body",
            "editor_font_size_compact",
            "editor_font_size_heading",
            "editor_font_size_button",
            "editor_font_size_status",
            "object_move_snap_m",
            "object_resize_snap_m",
            "object_rotation_snap_deg",
            "object_axis_snap_threshold_deg",
        ]
        self.assert_exports(rel, expected)
        for name in [
            "hover_help_move_tolerance_px",
            "editor_side_panel_top_px",
            "editor_top_bar_height_px",
            "editor_font_size_body",
            "editor_font_size_compact",
            "editor_font_size_heading",
            "editor_font_size_button",
            "editor_font_size_status",
        ]:
            self.assert_identifier_used(rel, name)

    def test_hud_layout_surfaces_are_editable(self):
        rel = "ui/hud.gd"
        expected = [
            "show_status_panel",
            "compact_status_panel",
            "show_openings_panel",
            "show_view_toggle",
            "keyboard_shortcuts_enabled",
            "rooms_scroll_step_px",
            "time_label_font_size",
            "shortcut_help_font_size",
            "opening_status_font_size",
            "action_button_font_size",
            "panel_content_margin_px",
            "opening_compact_h_separation_px",
            "opening_compact_v_separation_px",
            "opening_compact_label_font_size",
            "opening_compact_min_label_width_px",
            "opening_compact_wide_label_width_px",
            "openings_panel_base_height_px",
            "openings_panel_row_height_px",
            "openings_panel_min_height_px",
            "openings_panel_max_height_px",
            "font_size_header",
            "font_size_data",
            "card_margin_px",
            "card_data_color",
            "card_alert_color",
            "card_flashover_color",
            "flashover_indicator_permanent",
        ]
        self.assert_exports(rel, expected)
        for name in [
            "time_label_font_size",
            "shortcut_help_font_size",
            "opening_status_font_size",
            "action_button_font_size",
            "panel_content_margin_px",
            "opening_compact_h_separation_px",
            "opening_compact_v_separation_px",
            "opening_compact_label_font_size",
            "openings_panel_base_height_px",
        ]:
            self.assert_identifier_used(rel, name)

    def test_first_person_hud_alarm_and_visuals_are_editable(self):
        rel = "view/fp/FirstPersonController.gd"
        self.assert_exports(
            rel,
            [
                "person_height_m",
                "stand_speed_m_s",
                "interaction_range_m",
                "show_fp_detectors",
                "show_fp_victims",
                "fp_detector_alarm_enabled",
                "fp_detector_alarm_volume_db",
                "fp_detector_alarm_max_distance_m",
                "fp_detector_alarm_frequency_hz",
                "fp_detector_alarm_beep_duration_s",
                "fp_detector_alarm_interval_s",
                "show_fp_fire",
                "show_technical_overlay",
                "show_visibility_readout",
                "fp_status_panel_rect",
                "technical_overlay_panel_rect",
                "visibility_readout_panel_rect",
                "fp_prompt_panel_rect",
            ],
        )

    def test_fp_exterior_envelope_and_landing_lighting_are_editable(self):
        rel = "view/fp/FirstPersonController.gd"
        self.assert_exports(
            rel,
            [
                "exterior_own_facade_enabled",
                "own_facade_thickness_m",
                "own_facade_hole_margin_m",
                "own_facade_side_margin_m",
                "own_facade_plinth_height_m",
                "own_facade_parapet_m",
                "own_facade_storey_pitch_m",
                "landing_ambient_lights_enabled",
                "landing_ambient_light_factor",
            ],
        )
        self.assert_identifier_used(rel, "_create_own_facade")
        self.assert_identifier_used(rel, "_exterior_ground_level_m")
        self.assert_identifier_used(rel, "_add_landing_lights")

    def test_fp_surface_materials_are_editable(self):
        """FP-2 / M-1 / M-3 / R-3: el aspecto de las superficies se gobierna
        desde el inspector, no desde constantes del script."""
        rel = "view/fp/FirstPersonController.gd"
        self.assert_exports(
            rel,
            [
                "use_procedural_surface_noise",
                "material_noise_frequency",
                "material_noise_contrast",
                "material_noise_size_m",
                "material_floor_dirt_boost",
                "material_surface_roughness",
                "material_noise_texture_px",
                "material_noise_octaves",
                "material_floor_noise_octaves",
                "material_floor_noise_frequency_factor",
                "material_floor_noise_size_factor",
                "landing_tile_size_m",
                "landing_tile_grout_darkening",
                "landing_tile_texture_px",
                "landing_tile_grout_px",
                "exterior_wall_skin_enabled",
                "exterior_wall_skin_thickness_m",
                "surface_contact_ao_enabled",
                "surface_contact_ao_strength",
                "surface_contact_ao_band_m",
                "exterior_scenery_skip_landing_facades",
                "landing_height_follows_dwelling",
                "house_porch_ground_transition_enabled",
                "house_porch_curb_height_m",
                "house_porch_curb_thickness_m",
                "house_porch_gravel_apron_m",
                "house_porch_gravel_color",
            ],
        )
        for name in [
            "material_surface_roughness",
            "material_noise_texture_px",
            "material_floor_noise_size_factor",
            "landing_tile_grout_px",
            "surface_contact_ao_strength",
            "surface_contact_ao_band_m",
        ]:
            self.assert_identifier_used(rel, name)

    def test_fp_material_slots_accept_user_resources(self):
        """Se puede enchufar material o textura propios desde el editor sin
        tocar codigo; vacio = generacion procedural."""
        rel = "view/fp/FirstPersonController.gd"
        self.assert_exports(
            rel,
            [
                "wall_material_override",
                "floor_material_override",
                "ceiling_material_override",
                "exterior_facade_material_override",
                "surface_noise_texture_override",
                "floor_noise_texture_override",
                "landing_tile_texture_override",
            ],
        )
        for name in [
            "wall_material_override",
            "floor_material_override",
            "ceiling_material_override",
            "exterior_facade_material_override",
            "surface_noise_texture_override",
            "floor_noise_texture_override",
            "landing_tile_texture_override",
        ]:
            self.assert_identifier_used(rel, name)

    def test_fp_smoke_lighting_and_shell_knobs_are_editable(self):
        """FP-6 y E-4: el suelo del alcance de la luz con humo y el sellado
        entre plantas son parametros, no decisiones enterradas."""
        rel = "view/fp/FirstPersonController.gd"
        self.assert_exports(
            rel,
            [
                "room_ceiling_light_smoke_range_min_factor",
                "interstitial_ceiling_seal_enabled",
            ],
        )
        self.assert_identifier_used(rel, "room_ceiling_light_smoke_range_min_factor")
        self.assert_identifier_used(rel, "interstitial_ceiling_seal_enabled")

    def test_visual_reference_capture_is_editable(self):
        """El instrumental de capturas se maneja desde la escena: destino,
        vistas, reposo e iluminacion del piso patron."""
        rel = "tools/capture_visual_reference.gd"
        self.assert_exports(
            rel,
            [
                "output_dir",
                "output_label",
                "capture_first_person",
                "capture_dollhouse",
                "fp_views",
                "plan_center_m",
                "settle_frames_state",
                "settle_frames_view",
                "fp_room_ceiling_light_energy",
                "fp_landing_light_energy",
                "fp_landing_light_range_m",
                "fp_window_light_energy",
                "fire_hrr_kw",
                "fire_room_temp_upper_c",
                "fire_room_visibility_m",
                "fire_room_layer_m",
                "smoky_room_temp_upper_c",
                "smoky_room_visibility_m",
                "smoky_room_layer_m",
            ],
        )
        for name in ["fp_views", "settle_frames_state", "fire_room_layer_m"]:
            self.assert_identifier_used(rel, name)

    def test_3d_visualizer_overlays_camera_and_door_controls_are_editable(self):
        rel = "view/3d/Visualizer3D.gd"
        self.assert_exports(
            rel,
            [
                "meters_to_units",
                "wall_thickness_m",
                "door_leaf_max_open_angle_deg",
                "show_door_leaf_animation_3d",
                "show_layer_gradient",
                "show_wall_heatmap",
                "show_fed_labels",
                "show_smoke_volume",
                "show_smoke_geometry_in_first_person",
                "show_fire_smoke_plume",
                "show_exterior_smoke_plume",
                "layer_gradient_top_color",
                "layer_gradient_bottom_color",
                "wall_color",
                "hot_wall_color",
                "camera_distance_m",
                "camera_orbit_x_deg",
                "camera_orbit_y_deg",
                "debug_show_layer_heights",
                "debug_show_room_temps",
                "debug_show_hrr_values",
            ],
        )
        self.assert_identifier_used(rel, "smoke_exterior_plume", min_count=1)


    def test_3d_alpha_order_capture_and_picking_are_editable(self):
        """V3-1 / V3-2 / V3-4: el orden de la pila alfa, la captura tecnica y la
        tolerancia de seleccion se gobiernan desde el inspector."""
        rel = "view/3d/Visualizer3D.gd"
        self.assert_exports(
            rel,
            [
                "render_priority_smoke_volume",
                "render_priority_layer_gradient",
                "render_priority_hot_layer",
                "render_priority_layer_150c",
                "render_priority_ceiling_mask",
                "render_priority_opening_curtain",
                "render_priority_opening_inflow",
                "render_priority_exterior_plume",
                "screenshot_use_clean_viewport",
                "screenshot_size_px",
                "screenshot_transparent_background",
                "fuel_object_pick_radius_px",
                "fuel_object_pick_margin_px",
                "opening_curtain_follows_leaf",
                "opening_curtain_min_width_ratio",
                "opening_curtain_alpha_open_exponent",
                "opening_inflow_max_alpha",
            ],
        )
        for name in [
            "render_priority_ceiling_mask",
            "screenshot_use_clean_viewport",
            "fuel_object_pick_radius_px",
            "opening_curtain_alpha_open_exponent",
        ]:
            self.assert_identifier_used(rel, name)


class TestSmokeOpeningGeometry(unittest.TestCase):
    """El humo de un vano se lee desde debajo de la capa: necesita cara
    inferior, y el plano neutro solo puede recortar el lado que expulsa."""

    def test_opening_bridge_has_bottom_cap(self):
        text = _read("view/3d/smoke/SmokeBridgeMesh.gd")
        quads = text.count("_append_bridge_quad(vertices, normals, uvs, indices,")
        self.assertGreaterEqual(
            quads,
            6,
            "SmokeBridgeMesh.create must emit the four sides plus the bottom cap "
            "for both wall orientations",
        )

    def test_neutral_plane_is_side_aware_and_continuous(self):
        text = _read("view/3d/smoke/SmokeOpeningCurtain3D.gd")
        self.assertIn("_flow_limited_bottoms", text)
        self.assertIn("_effective_neutral_m", text)
        self.assertNotIn(
            "_should_limit_horizontal_smoke_to_upper",
            text,
            "the unconditional both-sides neutral clamp must stay retired",
        )

    def test_exterior_openings_get_a_rising_plume(self):
        text = _read("view/3d/smoke/SmokeOpeningCurtain3D.gd")
        self.assertIn("_update_exterior_plume", text)
        self.assertIn("show_exterior_smoke_plume", text)


if __name__ == "__main__":
    unittest.main(verbosity=2)
