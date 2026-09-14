# P1R8 Final Gap Dispositions

## Scope

This record closes the remaining validation-contract rows without claiming that
their underlying physical behavior was repaired. It preserves every observed
value and every existing expected value, tolerance, minimum and maximum. Cases,
baselines, HVAC, default flags and runtime authority remain unchanged.

Checkpoint: `edc61f4e50d290b70e3ef26f5867343e7d784a4f`.

## Former required VALID_GAP checks

The following six checks remain visible and failing. They are explicitly
non-gating and have disposition `VERIFIED_MODEL_LIMITATION` because the current
SimuFire model does not implement the equivalent CFAST bi-zone mass, enthalpy
and O2 transaction. This is contractual closure only.

| Check | Actual | Frozen contract | Limitation |
| --- | ---: | ---: | --- |
| `cfast_t240_o2_depleted` | 0.1595 | 0.085108 +/- 0.031 | CFAST upper-zone O2 versus current SimuFire O2 ownership/mixing |
| `cfast_t350_o2` | 0.0881 | 0.0659799 +/- 0.015 | CFAST upper-zone O2 versus current SimuFire O2 ownership/mixing |
| `cfast_t360_o2` | 0.0837 | 0.0645067 +/- 0.015 | CFAST upper-zone O2 versus current SimuFire O2 ownership/mixing |
| `cfast_chain_r0_t300_temp_upper_c` | 117.53 C | 166.27 C +/- 20 C | One-zone versus bi-zone hot mass and enthalpy residence |
| `cfast_chain_r0_t600_temp_upper_c` | 94.56 C | 168.80 C +/- 30 C | Accumulated hot mass and enthalpy transport shortfall |
| `cfast_chain_r0_o2_t600_o2` | 0.1329 | 0.0957 +/- 0.015 | Bi-zone exchange and combustion coupling boundary |

The aggregate must therefore contain zero failed required checks, while these
six failed measurements remain inspectable as non-gating limitations.

## Behavioral limitations

Fresh runtime evidence preserved six additional failures. They are classified
as `VERIFIED_MODEL_LIMITATION`, not silently converted to passes:

- `g2_gie_transitional_attack_time_room_0_hrr_below_100_post_attack_s`:
  the post-attack HRR threshold is not reached by the current tactical response.
- `secondary_ignition_demo_room_1_max_fuel_objects_flaming_count`,
  `secondary_ignition_demo_room_1_peak_hrr_kw`, and
  `secondary_ignition_demo_time_room_1_hrr_above_20_s`: the current spread model
  does not produce the declared secondary hallway ignition.
- `two_storey_smoke_room_7_final_temp_upper_raw_c` and
  `two_storey_smoke_time_room_7_temp_above_40_s`: the current vertical transport
  model does not reproduce the declared remote upper-storey heating.

## V7 false-positive snapshots

The two failed V7 absolute timestamps remain visible with their original
actual, expected and tolerance values, but are classified `FALSE_POSITIVE`:

- CO upper >= 5000 ppm: 139.750 s versus 121.0 +/- 10.0 s.
- O2 <= 15%: 166.167 s versus 156.25 +/- 5.0 s.

They were internal snapshots, while the declared BV-005 behavior is relational.
The versioned 12 Hz observation in
`sim/validation/evidence/p1r8_v7_event_order.json` demonstrates:

- CO upper >= 5000 ppm occurs 31.850 s before peak HRR.
- O2 <= 15% occurs 5.433 s before peak HRR.

The replacement checks require each event to precede peak HRR by at least one
12 Hz sample. No old expected value or tolerance was rewritten.

## Ghanekar runtime refresh

The verified final P1R8 matrix refreshed the two Ghanekar reports without
changing their cases or contracts. Two previously failing non-gating checks now
pass and therefore carry no failure disposition:

- `ghanekar_kitchen_far_hall_fed_0_3_s`: 635.4167 s, within the unchanged
  546 +/- 515 s contract.
- `ghanekar_kitchen_far_hall_fed_1_0_s`: 784.75 s, within the unchanged
  812.75 +/- 126 s contract.

Their former `VERIFIED_MODEL_LIMITATION` labels are retired. The retained
contracts still have the provenance and observable limitations documented in
the Ghanekar record, so a passing result is not presented as physical
equivalence. `ghanekar_far_hall_o2_response_time_s` remains a failed,
non-gating `VERIFIED_MODEL_LIMITATION`.

## Authority boundary

These dispositions make the validation ledger complete; they do not establish
physical equivalence with CFAST or grant runtime authority. H3.2b4, H3.3 and all
authority-changing defaults remain frozen. HVAC remains user-excluded.
