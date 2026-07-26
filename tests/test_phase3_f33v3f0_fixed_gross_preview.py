from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SYSTEM = (ROOT / "sim" / "core" / "Phase3ZoneMassSystem.gd").read_text(
    encoding="utf-8"
)
FIXTURE = (
    ROOT / "tests" / "fixtures" / "phase3_f33v3f0_fixed_gross_preview.gd"
).read_text(encoding="utf-8")


def test_preview_is_pure_and_not_called_by_runtime():
    name = "preview_fixed_gross_interior_pressure_skew"
    assert f"func {name}(" in SYSTEM
    assert SYSTEM.count(name) == 1


def test_preview_preserves_gross_and_caps_directional_skew():
    assert "requested_half_skew_kg" in SYSTEM
    assert "accepted_half_skew_kg" in SYSTEM
    assert "-low_to_high_kg, high_to_low_kg" in SYSTEM
    assert "preview_gross_kg - opening_gross_kg" in SYSTEM


def test_preview_scales_atomic_payloads_together():
    for quantity in ("gas_mass_kg", "sensible_enthalpy_kj", "o2_kg"):
        assert f'"{quantity}"' in SYSTEM
    assert 'scaled_route["species_kg"] = scaled_species' in SYSTEM


def test_runtime_fixture_covers_closure_cap_and_payloads():
    assert "PHASE3_F33V3F0_FIXED_GROSS_PREVIEW_PASS" in FIXTURE
    assert '"mass closure"' in FIXTURE
    assert '"energy closure"' in FIXTURE
    assert '"out O2 scaled"' in FIXTURE
    assert '"out species scaled"' in FIXTURE
    assert '"cap count"' in FIXTURE
