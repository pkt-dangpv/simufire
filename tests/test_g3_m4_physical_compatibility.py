"""M4-B3 analytic design witnesses; NOT engine tests or calibrated fire laws.

No simulation import, Godot, source mutation, new physical owner or runtime
consumer. Decimal examples make the fixed-reference/physical distinction
reproducible independently of the engine and of the M4 reference oracle.
"""

from decimal import Decimal as D, localcontext

import pytest


KAPPA = D("0.031998") / D("0.0289647")


@pytest.mark.parametrize("temperature", ["300", "450", "600", "900"])
def test_fixed_reference_disagrees_with_hot_isobaric_gas(temperature):
    # Imposed single-zone ideal-gas control, NOT a measured engine run.
    ref_gas = D("30")
    t = D(temperature)
    gas = ref_gas * D("300") / t
    physical_oxygen = gas * KAPPA * D("0.209")
    physical_proxy = physical_oxygen / (KAPPA * gas)
    reference_fraction = physical_oxygen / (KAPPA * ref_gas)
    assert abs(physical_proxy - D("0.209")) < D("1e-25")
    assert abs(reference_fraction - D("0.209") * D("300") / t) < D("1e-25")
    assert (physical_proxy == reference_fraction) == (t == D("300"))


def test_heating_moves_interface_without_moving_oxygen():
    # Closed two-zone control: m_u=10, m_l=20 kg; only T_u doubles.
    # EOS gives V_u/V = m_u*T_u / sum(m_z*T_z). No mass parcel exists.
    gas_u, gas_l = D("10"), D("20")
    before_share = gas_u * D("300") / ((gas_u + gas_l) * D("300"))
    after_share = gas_u * D("600") / (gas_u * D("600") + gas_l * D("300"))
    assert abs(before_share - D(1) / D(3)) < D("1e-25")
    assert after_share == D("0.5")
    oxygen_u, oxygen_l = D("1"), D("4")
    # Counterfactual geometric remap transfers exactly 1 kg from lower.
    swept = oxygen_l * (after_share - before_share) / (1 - before_share)
    assert abs(swept - D("1")) < D("1e-25")
    assert oxygen_u + swept != oxygen_u
    assert gas_u * (oxygen_u / gas_u) == oxygen_u
    assert oxygen_u + oxygen_l == D("5")  # budget alone misses wrong U


def test_physical_plume_carries_donor_mass_fraction_not_room_average():
    gas_l, oxygen_l, parcel = D("20"), D("4"), D("2")
    oxygen_u, gas_u = D("1"), D("10")
    carried = parcel * oxygen_l / gas_l
    assert carried == D("0.4")
    assert parcel * (oxygen_u + oxygen_l) / (gas_u + gas_l) != carried
    after_u, after_l = oxygen_u + carried, oxygen_l - carried
    assert after_u + after_l == oxygen_u + oxygen_l
    assert after_l / (gas_l - parcel) == oxygen_l / gas_l


def test_same_mole_number_cannot_be_used_as_a_mass_fraction():
    q, x = D("2"), D("0.209")
    correct_reference_packet = q * x * KAPPA
    counterfactual_packet = q * x
    assert correct_reference_packet != counterfactual_packet
    assert abs(correct_reference_packet / counterfactual_packet - KAPPA) < D("1e-25")


def test_reference_capacity_is_not_a_physical_species_mass_bound():
    gas, oxygen = D("1"), D("1.05")
    assert oxygen <= KAPPA * gas  # reference-core capacity would allow this
    assert oxygen > gas  # impossible physical mass fraction: must reject


def test_exact_molar_fraction_requires_mixture_composition():
    # Same 1 kg O2 + 4 kg diluent, but N2 versus CO2.
    # Fixed-air proxy is the same; actual mole fraction is not.
    oxygen_mol = D("1") / D("0.031998")
    with_n2 = oxygen_mol / (oxygen_mol + D("4") / D("0.02802"))
    with_co2 = oxygen_mol / (oxygen_mol + D("4") / D("0.04401"))
    assert with_n2 != with_co2
    proxy = D("1") / (KAPPA * D("5"))
    assert proxy != with_n2 and proxy != with_co2


def test_whole_room_transport_is_not_stratified_donor_transport():
    # Same 10 kg in both directions, so gas total of either room is unchanged.
    # a.upper Y=.10, a.lower Y=.20; b homogeneous Y=.20.
    room_a_gas, room_a_o2 = D("40"), D("7")
    q, b_y, a_upper_y = D("10"), D("0.20"), D("0.10")
    legacy_delta = q * (b_y - room_a_o2 / room_a_gas)
    physical_delta = q * (b_y - a_upper_y)
    assert legacy_delta == D("0.25")
    assert physical_delta == D("1.00")
    assert physical_delta != legacy_delta


def test_equivalent_dilution_is_not_pure_outflow():
    gas, oxygen, q, outside_x = D("30"), D("3"), D("1"), D("0.209")
    with localcontext() as ctx:
        ctx.prec = 50
        incoming = q * outside_x * KAPPA
        mixed_y = (oxygen + incoming) / (gas + q)
        dilution_after = oxygen + incoming - q * mixed_y
        physical_outflow_oxygen = oxygen - q * oxygen / gas
        assert dilution_after > oxygen
        assert physical_outflow_oxygen == D("2.9")
        assert gas + q - q == gas  # equivalent dilution keeps carrier mass
        assert gas - q == D("29")  # pure venting does not
        # Neither operation is universal: actual in/out streams must be declared.


def test_projection_loss_without_species_flux_changes_concentration():
    gas, oxygen = D("30"), D("3")
    projected_gas = D("20")
    assert oxygen / projected_gas == D("0.15")
    assert oxygen / gas == D("0.10")
    assert oxygen - (gas - projected_gas) * oxygen / gas == D("2")
    # The last number applies ONLY if there is a declared physical outflow.
    # It must not be used to erase oxygen to repair a numerical projection.


def test_outgoing_streams_cannot_spend_same_snapshot_twice():
    gas, oxygen = D("10"), D("2")
    outgoing = (D("6"), D("6"))
    assert all(q <= gas for q in outgoing)  # each local cap looks legal
    assert sum(outgoing) > gas
    assert sum(q * oxygen / gas for q in outgoing) > oxygen


def test_absent_zone_does_not_have_a_synthetic_concentration():
    gas, oxygen = D("0"), D("0")
    concentration = None if gas == 0 and oxygen == 0 else oxygen / gas
    assert concentration is None
    assert D("0.1") > gas  # oxygen in an absent zone cannot be valid
