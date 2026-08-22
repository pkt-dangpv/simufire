# `zone_at_height` species probe — design

Status: **DESIGN ONLY. Nothing in this document is implemented.**
Date: 2026-08-22 (session 27/30)
Author context: pre-runtime-authority audit lane.

Primary source for every "published" figure cited here:
Ghanekar, S., *Evolution of combustion gas concentrations in full-scale
residential fire environments*, Fire Safety Journal **162** (2026) 104724,
DOI `10.1016/j.firesaf.2026.104724`, in-repo at
`docs/literature/Evolution of combustion gas concentrations in full-scale residential fire.pdf`,
SHA-256 `1B2A1B00EE4ADECEA86771694260AAF8233637E69679B794C8BA1A6B44675030`,
git blob `d91a0b8b54e33111b582e7aa0f2f779a7767f752`.

---

## 0. Scope and non-goals

**This document designs a general measurement facility**, not a fix for the
Ghanekar contracts. The Ghanekar experiment is the *first consumer* and the
motivating validation target; it is not the specification.

**Non-goals, binding:**

- Not a change to physics, transport, combustion, species or runtime authority.
- Not a change to any default flag, case, baseline, report, `expected`,
  `tolerance` or `required`.
- Not a horizontal-position model. See §3.
- Not a route to making `ghanekar_far_hall_o2_response_time_s` PASS. Any design
  choice whose justification is "this makes 198 s come out" is rejected by
  construction — see §15.
- Not a redesign of the kitchen case. That remains **NO-GO**.
- HVAC remains **deferred and out of scope**.

---

## 1. Verified call graph

Everything in this section was read from source in session 27. Names were not
trusted; every claim carries `file:line`.

### 1.1 Species storage in `RoomModel`

| species | bulk | upper | lower | lower is |
|---|---|---|---|---|
| O2 | `o2` (`RoomModel.gd:45`) | `o2_upper` (`:47`) | `o2_lower` (`:49`) | **STORED** |
| CO | `co_kg` (`:120`) | `co_upper_kg` (`:121`) | — | **DERIVED** `bulk − upper` |
| CO2 | `co2_kg` (`:124`) | `co2_upper_kg` (`:125`) mass, **and** `co2_upper` (`:63`) mole fraction | — | **DERIVED** |
| HCN | `hcn_kg` (`:128`) | `hcn_upper_kg` (`:129`) | — | **DERIVED** |

**O2 is the only species with a genuinely stored lower-zone quantity.** CO, CO2
and HCN have no `*_lower_kg` field. Any "lower" value for those three is a
difference, and the design must label it as such.

CO2 additionally has **two upper representations** with different provenance: a
tracked mole fraction (`co2_upper`) and a mass (`co2_upper_kg`). `ThermalSystem`
carries an explicit warning at the head of `compute_co2_upper_ppm` that FED
consumes the mole-fraction form and that switching to the mass form must not be
done without auditing `fed_co`/`fed_hcn`.

### 1.2 Species accessors, and their contamination

All in `sim/core/ThermalSystem.gd`.

| accessor | line | zone mass model | contamination |
|---|---|---|---|
| `compute_co_ppm` | 4340 | `volume_m3() × **1.2** ` (fixed density) | — |
| `compute_co_upper_ppm` | 4376 | `floor_area × (h − hot_h) × gas_density(T_upper)` | — |
| `compute_co_lower_ppm` | 4390 | `floor_area × hot_h × gas_density(T_lower)` | **silent bulk fallback + stratification factor** |
| `compute_co2_ppm` | 4492 | bulk | — |
| `compute_co2_upper_ppm` | 4431 | **none** — returns `room.co2_upper × 1e6` | mole fraction, not mass-derived |
| `compute_co2_upper_ppm_mass` | 4443 | geometric | alternative to the above |
| `compute_co2_lower_ppm` | 4456 | geometric | **clean** derivation |
| `compute_hcn_ppm` | 4347 | bulk | — |
| `compute_hcn_upper_ppm` | 4469 | geometric | — |
| `compute_hcn_lower_ppm` | 4480 | geometric | **clean** derivation |

**`compute_co_lower_ppm` is uniquely contaminated** and must never be consumed
raw by a probe:

```
if room.upper_gas_kg < 0.1:
    return compute_co_ppm(room)          # ThermalSystem.gd:4402-4403  -> BULK
...
var strat: float = clampf(1.0 - upper_frac * 3.0, 0.0, 1.0)
return raw_ppm * strat                    # ThermalSystem.gd:4421-4422
```

The first branch returns the **bulk** concentration under a lower-zone name, with
no signal. The second multiplies by a **non-physical shaping factor** that forces
the lower zone to exactly zero once the upper layer occupies ≥ 1/3 of the room
height. Its own source comment concedes the change is "puramente de
tracking/exportación".

**A second silent fallback, in `compute_co2_upper_ppm_mass`** (`:4446-4447`):

```
if room.upper_gas_kg < 0.1:
    return room.co2_upper * 1.0e6            # the TRACER mole-fraction definition
```

This substitutes one definition of upper CO2 for a different one, unsignalled.
Note that in both this and the CO case the **gate tests the tracked
`upper_gas_kg` while the arithmetic uses the geometric zone mass** — the guard
and the computation do not even refer to the same quantity.

**CO2 carries two divergent inventories.** `room.co2_upper` (mole fraction) is
maintained entirely outside `ThermalSystem`, in `OxygenExchangeSystem` and
`HVACSystem`, and is on a different inventory from `room.co2_kg`.
`OxygenExchangeSystem.gd:733-737` contains a `push_warning` that fires when
`co2_upper_equiv_kg > co2_kg * 5.0` — **the codebase knows the two can diverge by
more than 5×.**

**A third contamination is upstream of every accessor.** `ThermalSystem.gd:4926-4929`
clamps the *stored* upper masses:

```
var max_species_upper_frac := minf(1.0, 3.0 * upper_geom_frac)
room.co2_upper_kg = clampf(room.co2_upper_kg, 0.0, room.co2_kg * max_species_upper_frac)
room.co_upper_kg  = clampf(room.co_upper_kg,  0.0, room.co_kg  * max_species_upper_frac)
room.hcn_upper_kg = clampf(room.hcn_upper_kg, 0.0, room.hcn_kg * max_species_upper_frac)
```

Its own comment calls the 3× an allowance for real stratification and the ~5× an
"artefacto". Whatever its merits, it means **no accessor can be cleaner than its
input**: the stored upper masses are already shaped before any probe sees them.
The probe cannot fix this and must not pretend to; it records provenance and
leaves the shaping visible (§9.2, DEP-7).

**Two mutually inconsistent mass models coexist.** Bulk accessors divide by
`volume × 1.2 kg/m³` (a **fixed** density); zonal accessors divide by
`floor_area × zone_height × gas_density(T_zone)`, where
`gas_density_kg_m3(T) = 1.2 · T_ambient_K / max(T_ambient_K, T_K)` (`:2470`) — i.e.
≤ 1.2, equal to 1.2 only at ambient. Therefore `upper_ppm` and `lower_ppm` do
**not** mass-average back to `bulk_ppm`, and the discrepancy grows with
temperature. A probe must not present them as if they did.

**No O2 accessor exists at all.** There is no `compute_o2_ppm`/`_upper`/`_lower`
anywhere in the repository; every consumer reads `room.o2` / `o2_upper` /
`o2_lower` directly. (`RoomModel.upper_o2_mass_kg` `:375` and `lower_o2_mass_kg`
`:380` are mass helpers, not concentration accessors.) This is why O2 is the one
species the probe can read without a derivation.

**HCl, acrolein and formaldehyde have no zone variants at all** — bulk only. They
are therefore outside the probe's species set (§5.2), and no zone-resolved value
for them may be invented.

### 1.3 Height → zone: the mappings that already exist

| mapping | where | effective rule |
|---|---|---|
| binary selector | `Phase3ZoneMassSystem._canonical_zone_at_height` (`:4325`) | `UPPER if height ≥ interface_m else LOWER` |
| FED zone predicate | `ThermalSystem` (`:4553`, `:4616`) via `LayerInterfaceModel.get_breathing_zone_exposure_factor` (`:115`) | **also exactly `z ≥ interface`** — see below |
| temperature blend | `ThermalSystem.estimate_temperature_at_height_m` (`:4252`) | 3-region piecewise: floor cooling band, gradient band of finite depth centred on the interface, else zone temperature |
| raw interface | `ThermalSystem.effective_hot_layer_height_m` (`:5022`) | **`two_zone_solver_enabled` defaults to `false`** (`:26`), so the **live** branch is `min(thermal_layer_m, height − hot_depth)`, *not* `thermal_layer_m` |

**The FED "smooth ramp" is not smooth in effect.**
`get_breathing_zone_exposure_factor` returns
`inverse_lerp(interface − 0.10, interface + 0.10, z)` and advertises a "transición
suave de 20 cm", but every consumer thresholds it at `>= 0.5`, and
`inverse_lerp(i−0.10, i+0.10, z) ≥ 0.5 ⟺ z ≥ i` exactly. **The FED predicate is
therefore binary at the interface, boundary inclusive → UPPER** — identical to
`_canonical_zone_at_height`. Verified numerically in session 27.

Two further effects sit on top of it:

- `_fed_breathing_zone_thermal_exposure_factor` forces the factor to `1.0`
  whenever `z ≥ layer_150c_m` and `temp_upper_c > fed_heat_conv_min_c`.
- the predicate is conjoined with `room.upper_gas_kg > 0.1`, so an occupant
  geometrically inside the hot layer is still scored LOWER whenever upper mass is
  below 0.1 kg — **with no signal**.

**Net finding.** The two binary rules that ship agree with each other exactly.
The temperature blend is the outlier, and it is an outlier for a good reason:
temperature is continuous between zones, species are not. This *strengthens* the
choice in §4.2 rather than complicating it.

**Consequence for the design.** The existing height-resolved *temperature* probe
is **not** a zone selector — it is a smooth blend. A species probe that selects a
zone is therefore **not the analogue** of `temp_at_0_9m_c`, and must not be
described as "the same thing for species". This asymmetry is unavoidable:
temperature can be blended because both zone temperatures are intensive and
continuous; species cannot be blended without inventing a vertical concentration
profile the engine does not have.

**Interface fields are also plural**: `thermal_layer_m`, `h_layer_m`,
`hot_layer_m`, `flow_interface_m`, `layer_150c_m`, `smoke_layer_m`,
`visible_smoke_layer_m`. `MOTOR_PHYSICS_VALIDATION_CHECKLIST.md` §5 already warns
that thermal and optical layer heights "should not be blindly compared".

### 1.4 FED

`sim/core/ThermalSystem.gd`:

- `step_fed(room, dt)` (`:4607`) writes `room.fed`, and
  `room.fed += delta_co + delta_hcn + delta_hypoxia + delta_heat` (`:4684`).
- `compute_fed_delta_for_height(room, dt, height_m)` (`:4549`) **already exists**,
  is documented "sin modificar `room.fed`", and is height-parameterised — but it
  **also includes the heat term** (`:4583-4596`). It is therefore *not* an
  asphyxiant FED.
- Both use the same zone predicate:
  `in_upper = (thermal_exposure_factor ≥ 0.5) and (room.upper_gas_kg > 0.1)`.
- **The lower branch reads BULK CO**: `compute_co_ppm(room)` (`:4554`, `:4618`),
  not `compute_co_lower_ppm`. The existing FED already commits the
  bulk-for-zone substitution this design forbids.
- `fed_upper_layer_threshold_m` default **1.8 m** (`SimulationEngine.gd:643`,
  `ThermalSystem.gd:321`); the kitchen Ghanekar case overrides it to **2.0**.
- No asphyxiant-only FED exists anywhere. **`fed_asphyxiant` DOES NOT EXIST.**

### 1.5 Cadence — three different clocks

- `CaseRunner._run_validation_loop` (`:232`): `validation_step_s` default
  **1/12 s**, not overridden by either Ghanekar case.
- `engine.step(validation_step_s / time_scale)` (`:272`) and
  `dt = sim_fixed_dt if sim_fixed_dt > 0 else delta * time_scale`
  (`SimulationEngine.gd:3133`); `sim_fixed_dt` defaults to `0.0` and is not set by
  the Ghanekar cases. **Net simulated advance per iteration = exactly
  `validation_step_s` = 1/12 s (12 Hz).**
- `_update_metrics(state)` runs **once at t = 0** (`CaseRunner.gd:70`) and then
  **every iteration** (`:287`), i.e. at 12 Hz, on the **post-step** state.
- Logging is independent: `log_interval_s = 10.0` in both Ghanekar cases.
- The paper samples at **1 Hz** (p.3 §2.2).

Arithmetic confirmation that metrics really are 12 Hz, from the frozen reports:
`232.500000000009 × 12 = 2790`, `866.583333333448 = 10399/12`,
`495.333333333291 = 5944/12`. All exact.

**Four clocks must be kept distinct**: engine 12 Hz, metric evaluation 12 Hz,
logging 0.1 Hz, publication 1 Hz.

### 1.6 State building and export

- `SimulationEngine.get_state()` (`:4591`) rebuilds the state **fresh on every
  call** via `state_builder.build_state(...)`. `CaseRunner` calls it **at least
  twice per iteration** (before events and after the step).
- `SimulationStateBuilder` already emits **eight hard-coded height
  temperatures** — 0.1, 0.5, 0.9, 1.0, 1.1, 1.5, 1.8, 2.2 m (`:296-303`) — all via
  `_call_room_height_float(estimate_temperature_callable, room, z,
  room.temp_lower_c)`. Note the **fallback default is `temp_lower_c`**.
- Species in the state dict (`:343-351`): `co_ppm`, `co_upper_ppm`,
  `co_lower_ppm`, `co2_ppm`, `co2_upper_ppm`, `co2_upper_ppm_mass`, `hcn_ppm`,
  `hcn_upper_ppm`. **`co2_lower_ppm` and `hcn_lower_ppm` are NOT exported** to
  the state dict or the CSV, although the callables are wired
  (`SimulationEngine.gd:2772, 2775`) and FED consumes them.
- Every species goes through `_call_room_float(callable, room, **0.0**)` —
  **unknown becomes zero** at the export boundary.
- **CSV species columns are written at `%.0f`** (`SimulationLogWriter.gd`), i.e.
  integer ppm. Any CO concentration in `(0, 0.5)` ppm therefore prints as exactly
  `0` — and is then **indistinguishable from three other zeros**: the
  `strat = 0` shaping zero (§1.2), the `_call_room_float(..., 0.0)` absent-value
  zero, and a genuine zero. **Four meanings collapse onto one glyph.** By
  contrast O2 is written at `%.5f` and FED components at `%.5f`.
  This alone makes the CSV unusable as a measurement surface for species, and is
  the strongest single argument for the probe owning its own artefact (§11.5).
- Report write is **fail-closed**: `_write_json_file` returns `false` →
  `get_tree().quit(1)` (`CaseRunner.gd:1208-1210`, `:1404-1409`).
  JSON serialisation itself is lossless (~15 significant digits), but per-case
  reports and `summary.json` use **two different rounding regimes** for the same
  quantities (`_snap_metric`, `SimulationEngine.gd:5172-5175`).
- Report schema: `case`, `comparison_contract_version`, `duration_s`,
  `sim_time_s`, `metrics`, `baseline` (`:1192-1200`), plus `engine_mode`,
  `fire_o2_mode`, `two_zone_v1_profile` observed in the frozen reports.
- There is **no case-JSON schema and no key allowlist**; unrecognised top-level
  keys are simply never read.
- CSV header tests use `assertIn`, not equality, so adding a column would not
  break them — but the shared CSV surface is still off-limits by default (§11).
- **No test anywhere references `temp_at_0_9m_c`.** The existing height probe is
  entirely unpinned.

---

## 2. What the design must therefore not assume

1. That a lower-zone concentration exists for CO/CO2/HCN. It is a difference.
2. That `upper` and `lower` average back to `bulk`. They do not — different mass
   models (§1.2).
3. That selecting a zone at a height is well-defined. **Four** incompatible rules
   already ship (§1.3).
4. That the existing temperature-at-height probe is a precedent for zone
   selection. It is a blend, not a selection (§1.3).
5. That `room.fed` is comparable with the published FED. It contains a thermal
   term the paper's FED does not (§1.4, and session 26).
6. That logging cadence is measurement cadence. They are independent (§1.5).

---

## 3. Representational limit — stated once, propagated everywhere

The published sampling point (p.2 §2.1) is characterised by **four** properties:

1. at the **end of the hallway**;
2. **0.9 m** above the floor;
3. **not in the direct flow path** between fire compartment and external vents;
4. **gas stagnates against the wall** there, which is why the author expects
   toxic exposure to dominate thermal exposure at that location.

SimuFire's representation is **room × height**. It can express (2). It cannot
express (1), (3) or (4): a two-zone room has no horizontal coordinate, no flow
path geometry within the room, and no stagnation sub-volume. A well-mixed zone
is, by construction, the negation of a stagnation region.

**Binding consequence.** The facility is named `zone_at_height` — never
"0.9 m probe", never "sampling point", never "sonda". Every artefact it produces
carries a machine-readable limitation record (§10.3) stating that horizontal
position and stagnation are **not represented**. A contract that consumes probe
output and omits this record is malformed.

This is not a caveat to be retired by better calibration. It is a property of the
zone model, and it survives until SimuFire has sub-room resolution.

---

## 4. Probe semantics

### 4.1 Identity

```
probe_id      : string, unique within a case, author-assigned
room_id       : int
height_m      : float, metres above that room's floor
species       : ordered list from {o2, co, co2, hcn}
sample_period_s : float, nominal sampling period
```

No default height. No default room. A probe with an implicit 0.9 m would invite
exactly the reading §3 forbids.

### 4.2 Zone selection rule

**Rule.** With `interface_m = ThermalSystem.effective_hot_layer_height_m(room)`:

```
zone = UPPER  if height_m >= interface_m
zone = LOWER  otherwise
```

**`height == interface` resolves to UPPER.** This is not an arbitrary tie-break:
it matches **both** binary rules that ship — `_canonical_zone_at_height`
(`Phase3ZoneMassSystem.gd:4325`) and, once the `>= 0.5` threshold is applied, the
FED zone predicate as well (§1.3). Choosing anything else would put the probe in
disagreement with every existing consumer.

**Why binary and not blended.** A blend would require a vertical concentration
profile. The engine has exactly two species reservoirs per room; any profile
between them would be invented. Temperature can be blended (§1.3) because both
endpoint temperatures are physical; species cannot. The probe therefore reports a
**zone-resolved** value and says so.

**Which interface.** `effective_hot_layer_height_m` is chosen because it is the
accessor the species zone-mass computations already use (`:4382`, `:4406`,
`:4471`, `:4482`), so probe and accessor agree on where the boundary is. The
probe records **which** interface accessor it used, and its value, in every
sample (§10.2) — because §1.3 shows the choice is not unique.

**Mode dependence, recorded not hidden.** `effective_hot_layer_height_m` returns
a different quantity depending on `two_zone_solver_enabled`. The probe records
the flag's value per sample.

### 4.3 Degenerate cases — all resolve to `unknown`, never to a substitute

| condition | result |
|---|---|
| `room_id` does not exist | `unknown`, reason `room_absent` |
| `height_m < 0` or `> room.height_m` | `unknown`, reason `height_out_of_bounds` |
| selected zone mass below the declared presence epsilon | `unknown`, reason `zone_degenerate` |
| species not represented for that zone | `unknown`, reason `observable_absent` |
| interface invalid (`< 0` or `> room.height_m`) | `unknown`, reason `interface_invalid` |
| `room == null` | `unknown`, reason `room_null` |

`unknown` is a **first-class value**, serialised as JSON `null` with a mandatory
sibling `reason` string. It is never `0.0`, never the bulk value, never the other
zone's value, never the previous sample's value.

**No silent fallback, ever.** This is the single most important rule in the
design. §1.2 and §1.6 show the codebase currently violates it in three places
(`compute_co_lower_ppm`'s bulk branch, `_call_room_float(..., 0.0)`, and
`_call_room_height_float(..., temp_lower_c)`). The probe does not inherit those
behaviours, and does not call `compute_co_lower_ppm` at all (§5.2).

**Presence epsilon.** The disagreement here is worse than "a few thresholds".
A constant *literally named* `ZONE_MASS_EPS_KG` holds **three different values in
three files** — `1.0e-4` (`ZoneFireSolver.gd:53`), `1.0e-6`
(`Phase3ProjectionCausalLedger.gd:77`), `1.0e-12` (`Phase3ZoneMassSystem.gd:26`,
as `THERMO_MASS_EPS_KG`) — with `1.0e-4` again under a fourth name
(`Phase3ResidualProjectionShadow.gd:75`), and the FED/species gate at `> 0.1` kg.
That spans **nine orders of magnitude of disagreement about when an upper zone
exists**, and no predicate is authoritative.

The probe therefore **does not choose one silently**: `zone_presence_epsilon_kg`
is a declared parameter with **no default**, and its value is recorded in every
sample. Unifying the predicates is DEP-1 and is not this design's to settle —
but the probe must not quietly inherit whichever value happens to be nearest.

---

## 5. Observables

### 5.1 Provenance classes

Every sample value carries exactly one provenance tag:

- **`measured`** — read from a stored per-zone field.
- **`derived`** — computed from stored quantities by a stated formula (e.g.
  `lower = bulk − upper` over a geometric zone mass).
- **`unrepresentable`** — the quantity has no representation for that zone;
  emitted as `unknown` with a reason.

### 5.2 Availability matrix

| species | UPPER | LOWER |
|---|---|---|
| O2 | `room.o2_upper` — **measured** (no accessor exists; read directly) | `room.o2_lower` — **measured** |
| CO | `compute_co_upper_ppm` — **derived** (geometric zone mass; input already clamped, DEP-7) | **derived**, computed *by the probe* as `(co_kg − clamp(co_upper_kg,0,co_kg))` over the geometric lower-zone mass |
| CO2 | **derived, provenance ambiguous** — `compute_co2_upper_ppm` (mole-fraction inventory) and `compute_co2_upper_ppm_mass` (mass inventory, itself carrying a silent fallback) disagree by design; the probe must **declare which it used** (DEP-8) | `compute_co2_lower_ppm` — **derived**, clean |
| HCN | `compute_hcn_upper_ppm` — **derived** (input clamped, DEP-7) | `compute_hcn_lower_ppm` — **derived**, clean |
| HCl, acrolein, formaldehyde | **unrepresentable** — bulk only, no zone variant exists | **unrepresentable** |

The probe's species set is therefore exactly `{o2, co, co2, hcn}`. Requesting any
other species is a declaration error, not an `unknown` at runtime.

**CO lower is recomputed by the probe rather than delegated.** `compute_co_lower_ppm`
cannot be used: it substitutes bulk below `upper_gas_kg < 0.1` and applies a
non-physical stratification factor (§1.2). The probe applies the same clean
derivation the CO2 and HCN accessors already use, and where that derivation is
not valid it emits `unknown` — it does not fall back.

**This is a measurement decision, not a physics change.** No stored field is
written. The engine's own `co_lower_ppm` export is left exactly as it is; the
probe simply does not consume it. If the project later wants the two to agree,
that is a separate, physics-owning change — recorded as dependency **DEP-3**.

### 5.3 `fed_asphyxiant` — a measurement quantity, defined separately

The published FED (p.4 §2.3) is the **Purser asphyxiant dose over O2, CO2, CO and
HCN**, with **no thermal term**. `room.fed` includes `fed_heat` (§1.4).

Define, **for probe output only**:

```
fed_asphyxiant = FED_CO + FED_HCN + FED_hypoxia
```

using the model already in `step_fed`, evaluated at the probe's zone, with:

- the **existing CO2 treatment preserved exactly** — CO2 enters only as the
  Purser hyperventilation multiplier `V_CO2 = exp(0.1903·CO2% + 2.0004)/7.1`
  applied above 2 vol%, never as a dose term. This matches both the paper and the
  current model; no reinterpretation.
- the **existing hypoxia constants preserved** (`fed_hypoxia_a`,
  `fed_hypoxia_b`, ambient 20.9 vol%).
- **no thermal term**, because the paper has none.

**`room.fed` is not modified, not reinterpreted, and not read by the probe.** The
existing field, its components and the checklist contract
`fed = fed_co + fed_hcn + fed_hypoxia + fed_heat` (§7 of the checklist) all stand
untouched. `fed_asphyxiant` is a **separate, additional, probe-scoped**
accumulator with its own name.

Quantified justification, from the frozen kitchen report, far hallway (R2):
`0.0971317 + 0.0121828 + 0.1059437 + 0.0215422 = 0.2368004`, so the
asphyxiant-only value is **0.2152582** and the thermal term is **9.10 %** of the
total. Removing the term the paper does not have moves the far hallway **further**
from the 0.3 threshold, not closer.

**Implementation note.** `compute_fed_delta_for_height` (§1.4) is the right
function to generalise: it is already non-mutating and height-parameterised. The
minimal change is a parameter selecting whether the thermal term is included,
defaulting to the current behaviour. That is preferable to a new parallel
implementation, which would fork the CO/HCN/hypoxia formulas. **But note it
currently reads BULK CO on the lower branch** (§1.4); the probe's asphyxiant FED
must use the probe's own zone-resolved CO (§5.2), or emit `unknown`.

### 5.4 Dry/wet basis — declared, not converted

The paper's concentrations are **dry-basis**: the sampling train removes moisture
**without quantifying it** (p.8 §4). SimuFire has no dry/wet handling anywhere.

**No conversion is designed, because no humidity datum exists** on either side.
Instead every probe sample carries `basis: "wet_unquantified"` and every artefact
records that published values are `dry_unquantified`. The mismatch is made
**visible and machine-readable**, never silently reconciled. Recorded as
dependency **DEP-4**.

---

## 6. Sampling scheduler

### 6.1 Requirements

Deterministic, drift-free, independent of logging, and provably non-mutating.

### 6.2 Nominal grid

Sample times are **nominal and integer-generated**, never accumulated:

```
t_k = k · sample_period_s,   k = 0, 1, 2, …
```

Never `t += period`. Accumulation drifts; multiplication does not. `k` is stored
in the sample so the grid is reconstructable.

### 6.3 Step/sample interaction

The engine advances in `dt = 1/12 s` (§1.5). A sample instant may fall inside a
step, and a single step may span several instants if `sample_period_s < dt`.

**Policy: sample-and-hold at the first post-step observation, with explicit
labelling.** For each step advancing `[t_prev, t_now]`, emit a sample for **every**
nominal `t_k ∈ (t_prev, t_now]`, each carrying:

- `t_nominal` = `k · sample_period_s`
- `t_observed` = `t_now` (the state actually read)
- `t_skew` = `t_now − t_k` ≥ 0

**No interpolation in v1.** Interpolating species between engine states would
manufacture values the engine never held, and the zone selection is discrete —
interpolating across a zone change is meaningless. `t_skew` is bounded by `dt`
(≤ 1/12 s ≈ 0.083 s), which is two orders of magnitude below the ≥ 3.4 s
transport-measurement uncertainty in the source, so sample-and-hold is not the
limiting error. Interpolation is deferred as **OPEN-2**.

If `sample_period_s < dt`, several `t_k` share one `t_observed`; each is emitted
with its own increasing `t_skew` and a `duplicate_observation: true` flag. The
alternative — silently dropping instants — would make the series non-uniform
without saying so.

### 6.4 Ordering within a frame

Exactly one observation point, in `CaseRunner._run_validation_loop` **between the
post-step `get_state()` (`:273`) and `_update_metrics` (`:287`)**, reading room
state directly.

Rationale, from §1.5–§1.6: `_update_metrics` already runs on the post-step state,
so the probe sees exactly what metrics see; and `get_state()` rebuilds the whole
state dictionary on every call, so routing the probe through it would either cost
a third full rebuild per iteration or couple measurement to the export schema.
The probe reads `RoomModel` fields and calls pure accessors, so it needs no state
dictionary. **This placement requires zero engine changes.**

**Alternatives considered and rejected** (session 27 established there is *no*
generic observer registry, no `step_completed` signal and no pre/post-step hook
list in `SimulationEngine`):

| candidate | why rejected |
|---|---|
| `add_target` / `_step_targets` (`SimulationEngine.gd:3223`, `:3885-3904`) — the closest existing extension point, already driven from case JSON, verified not to write `RoomModel` | Runs **inside** `engine.step()`, so measurement would sit in the physics loop and a probe fault would throw mid-solve; targets are stateful accumulators exported through the **shared** `get_state()` surface, which §11.5 forbids. Honest caveat: `fed_asphyxiant` *is* accumulator-shaped, so this mechanism is a reasonable model for that one quantity — but not for sampling. |
| `SimulationEngine._maybe_log_state` (`:5413-5418`) | Gated by `log_interval_s` — would silently deliver the 10 s cadence. Exactly threat #8. |
| `SimulationEngine._update_peak_tracking` (`:3297`, `:4890-4904`) | Read-only, but its output is never exported; would need a new export path anyway. |
| `CaseRunner._process` (`:54-74`) | **Dead code** — always early-returns. |

### 6.5 Non-mutation

The observer takes `RoomModel` by reference and writes **nothing**. Enforcement:

- the sampler holds no reference to any system that can write room state;
- all accessors it calls are pure reads (verified for each in §1.2);
- a test hashes the full room state before and after a sampling call and asserts
  bit-equality (§13, T-NOMUT);
- a campaign test asserts that a run with probes enabled produces **byte-identical**
  per-case report and CSV to a run without (§11).

### 6.6 Independence from logging

`sample_period_s` is a probe property. It is never read from `log_interval_s`,
and the probe never writes to the CSV path. Sampling a 1 Hz publication target
from a 10 s log would alias by a factor of ten; the design makes that
structurally impossible rather than merely discouraged.

---

## 7. Sampling-line delay

### 7.1 What the source actually says

- Transport time measured before each experiment, **16–23 s** (p.3 §2.2).
- It is **end-to-end**: it times the analyser's response to a calibration-gas
  discharge **at the sampling port**, so it bundles line transit with instrument
  response. **It cannot be decomposed**, and the line length is never published.
- Uncertainty in measuring it: **"at least 3.4 s"** — a lower bound, not a ±.
- The article **neither states that reported times were corrected for it, nor
  that they were not**. Verdict: **NOT STATED**.

### 7.2 Design consequence

**No default delay.** Not 16, not 19.5, not 23. Choosing a central value would
fabricate a number the source does not supply, and choosing any value at all
would silently pick a side of a question the article leaves open.

**Raw output is authoritative.** The probe emits `t_nominal` in the **simulation
frame**, with no delay applied, always.

**Delay is post-processing over measurement, never physics.** It never shifts a
sample, never enters the engine, never touches transport. It is applied by an
offline analyser to an already-written raw series.

### 7.3 Envelope, not a point estimate

Where a delay-aware comparison is wanted, the analyser produces an **envelope**
over a declared set, e.g. `{16, 23}` s as stated bounds, optionally widened by the
≥ 3.4 s measurement uncertainty. Output is an interval
`[t_raw + δ_min, t_raw + δ_max]` plus the declared `δ` set, **never a single
delayed time**.

**Sign discipline.** The direction must be declared explicitly per analysis:
adding δ to a simulated time models "the analyser responds later than the gas
arrives at the probe"; subtracting δ from a published time models "the published
figure already contains the lag". These are different hypotheses about the
source. The analyser records which one it applied and refuses to run without it.
Silently choosing the sign that improves agreement is the failure mode in §15.6.

### 7.4 What must not be claimed

That line transit and instrument response can be separated. §7.1 shows they
cannot, from this source. Any artefact asserting a pure "line delay" is wrong.

---

## 8. `tΔ` initial-response analyser — **BLOCKED / EXPERIMENTAL**

### 8.1 The published method (p.4 §2.3)

1. `change` = absolute difference between measured concentration and the
   **average background concentration**;
2. a **linear baseline** is inferred over the window from the start of background
   to the time of intervention;
3. using an **iterative polynomial fit algorithm**;
4. the **last time index prior to intervention at which the change intersects
   that baseline** is the time of initial response.

Computed **per gas**. `t_ΔO2` additionally anchors the rate-averaging window for
every gas.

**It is not a threshold.** No vol% or ppm cut defines initial response anywhere in
the article. The design does not introduce one.

### 8.2 Parameters the article does not publish

| parameter | status |
|---|---|
| polynomial degree | **NOT PUBLISHED** |
| iteration / rejection rule | **NOT PUBLISHED** |
| convergence criterion, iteration count | **NOT PUBLISHED** |
| numerical tolerance for "intersects" | **NOT PUBLISHED** (exact equality is unattainable on sampled noisy data) |
| background averaging window | **NOT PUBLISHED** (only "at least 2 min" of background is recorded) |
| intervention time for a simulated run | **NOT DEFINED** — there are no firefighters in the simulation |

The last row is the deepest problem: the estimator's fit window **ends at
intervention**, so the published `tΔ` is conditioned on when firefighters entered.
A simulation has no such event. Any surrogate — end of run, a fixed time, a
physical trigger — is an invention that changes the estimator's output.

### 8.3 Verdict

**The analyser cannot be specified deterministically without inventing data, so
it is declared BLOCKED/EXPERIMENTAL.** It is designed as an **offline,
parametric, non-gating** analyser over already-written raw series. It is **never**
a required metric, never a contract input, and never runs inside the engine.

### 8.4 Required form

Every invocation declares the full parameter vector; there are **no defaults**.
Output is never a single time: it is a **sensitivity surface** over the plausible
parameter ranges, reporting the distribution of `tΔ` and its dependence on each
parameter, alongside the fraction of parameter combinations for which the fit
fails to converge or finds no intersection.

**Prohibited by construction:** selecting any parameter set because it reproduces
198 s, or reporting the subset of the surface that agrees with the publication.
The surface is reported whole, or not at all.

Before it may be trusted at all, the analyser must reproduce **synthetic** series
with known injected response times (§13, T-TD-SYNTH). If it cannot recover a
planted answer, it cannot be used on real data.

---

## 9. JSON schemas

All schemas are versioned. Examples are illustrative and appear **only** in this
document; no case, schema or report file is edited.

### 9.1 Probe declaration (case-level, default absent)

```json
{
  "probes_schema_version": 1,
  "probes": [
    {
      "probe_id": "hall_far_z090",
      "room_id": 2,
      "height_m": 0.9,
      "species": ["o2", "co", "co2", "hcn"],
      "sample_period_s": 1.0,
      "zone_presence_epsilon_kg": 1.0e-6,
      "interface_source": "effective_hot_layer_height_m",
      "fed_asphyxiant": true
    }
  ]
}
```

Absent key, `null`, or `[]` ⇒ the facility is completely inert (§11).
`zone_presence_epsilon_kg` and `interface_source` have **no defaults** and must be
stated (§4.3, §4.2).

### 9.2 Raw sample series (separate artefact, never the case report)

```json
{
  "probe_samples_schema_version": 1,
  "case": "ghanekar_bedroom_hallway",
  "probe_id": "hall_far_z090",
  "declaration": { "...": "verbatim copy of the declaration above" },
  "engine": {
    "validation_step_s": 0.08333333333333333,
    "sim_fixed_dt": 0.0,
    "time_scale": 5.0,
    "two_zone_solver_enabled": true
  },
  "limitations": { "...": "see 9.3" },
  "samples": [
    {
      "k": 232,
      "t_nominal_s": 232.0,
      "t_observed_s": 232.0,
      "t_skew_s": 0.0,
      "duplicate_observation": false,
      "zone": "lower",
      "interface_m": 1.2043,
      "zone_mass_kg": 41.87,
      "values": {
        "o2":  { "value": 0.2061, "unit": "vol_frac", "provenance": "measured" },
        "co":  { "value": 61.4,   "unit": "ppm",      "provenance": "derived",
                 "derivation": "(co_kg - clamp(co_upper_kg,0,co_kg)) / geometric_lower_zone_mass" },
        "co2": { "value": 1043.0, "unit": "ppm",      "provenance": "derived" },
        "hcn": { "value": null,   "unit": "ppm",      "provenance": "unrepresentable",
                 "reason": "zone_degenerate" }
      },
      "basis": "wet_unquantified"
    }
  ]
}
```

`value: null` **always** carries `reason`. A consumer encountering `null` without
`reason` must treat the artefact as malformed.

### 9.3 Limitation record — mandatory, machine-readable

```json
{
  "limitations_schema_version": 1,
  "horizontal_position": "not_represented",
  "stagnation_region": "not_represented",
  "published_probe_context": "end of hallway, outside the direct flow path, gas stagnates at the wall (p.2 s2.1)",
  "zone_selection": "binary; height >= interface resolves to UPPER",
  "vertical_profile": "none; species have exactly two reservoirs per room",
  "basis": "wet_unquantified vs published dry_unquantified",
  "bulk_zone_mass_models_inconsistent": true
}
```

### 9.4 Delay envelope (analysis artefact)

```json
{
  "delay_envelope_schema_version": 1,
  "source_statement": "16-23 s end-to-end, NOT decomposable; correction status NOT STATED (p.3 s2.2)",
  "delta_set_s": [16.0, 23.0],
  "measurement_uncertainty_lower_bound_s": 3.4,
  "sign_convention": "added_to_simulated",
  "sign_convention_declared_by": "analysis author",
  "t_raw_s": 232.0,
  "interval_s": [248.0, 255.0],
  "point_estimate": null,
  "point_estimate_reason": "no default delay may be chosen; the source does not supply one"
}
```

### 9.5 `tΔ` analysis (experimental)

```json
{
  "t_delta_analysis_schema_version": 1,
  "status": "EXPERIMENTAL_NON_GATING",
  "blocked_parameters": ["polynomial_degree", "iteration_rule", "convergence",
                         "intersection_tolerance", "background_window", "intervention_time"],
  "parameter_grid": { "polynomial_degree": [1, 2, 3], "intersection_tolerance": ["..."] },
  "results": [ { "params": {"...": "..."}, "t_delta_s": 0.0, "converged": true } ],
  "summary": { "n_combinations": 0, "n_converged": 0,
               "t_delta_s_min": null, "t_delta_s_max": null, "t_delta_s_median": null },
  "selected_parameters": null,
  "selected_parameters_reason": "selection is prohibited; the surface is reported whole"
}
```

### 9.6 `fed_asphyxiant` (separate from `fed`)

```json
{
  "fed_asphyxiant_schema_version": 1,
  "definition": "FED_CO + FED_HCN + FED_hypoxia; CO2 enters only as the Purser V_CO2 multiplier; NO thermal term",
  "distinct_from_room_fed": true,
  "room_fed_untouched": true,
  "zone_resolved": true,
  "components": { "fed_co": 0.0, "fed_hcn": 0.0, "fed_hypoxia": 0.0 },
  "fed_asphyxiant": 0.0
}
```

---

## 10. Compatibility contract

1. **Absent probes ⇒ byte-identical.** No probe declaration, `null`, or `[]`
   means no sampler is constructed, no artefact is written, no state field is
   added, no CSV column appears. Enforced by a byte-comparison test (§13, T-INV).
2. **Default OFF.** The facility is opt-in per case. No engine `@export` default
   changes.
3. **No official case enables it during D1–D4.** The two Ghanekar cases and every
   other case in `sim/validation/cases/` stay untouched. D5 may propose a *new,
   non-official* case; it may not modify an existing one.
4. **No feedback path.** Probe output never reaches physics, transport,
   combustion, `room.fed`, existing metrics, contracts, UI or runtime authority.
   It is write-only, to its own artefact.
5. **Shared surfaces untouched.** No new CSV column and no new key in the
   existing per-case report. Probe output is a **separate file**, for two
   reasons: the CSV and report are consumed by guardrails, baselines and the
   aggregate; and the CSV writes species at `%.0f`, which destroys exactly the
   sub-ppm resolution a probe exists to capture and collapses four distinct
   meanings onto the glyph `0` (§1.6). The probe artefact carries full precision
   and explicit `null`s.
6. **Fail-closed preserved.** Probe artefact write failure must abort the run with
   a non-zero exit, matching `_write_json_file`'s existing contract
   (`CaseRunner.gd:1208-1210`). Measurement that silently fails to record is worse
   than no measurement.
7. **Never substitute bulk for a zone** (§4.3, §5.2).
8. **The aggregate is untouched.** 530 checks, `required_count` 350,
   `failed_required_count` 6, `known_gap_count` 76 all unchanged through D4.

---

## 11. Ownership and module placement

| responsibility | placement | why |
|---|---|---|
| pure zone-at-height selection + zone-resolved species | **new** `sim/core/ZoneAtHeightProbe.gd`, static/pure | It is a *measurement* primitive. Putting it in `ThermalSystem` would mix measurement with the system that owns and mutates thermal state; `ThermalSystem` is already 5 247 lines and its accessors carry export-shaping behaviour (§1.2) the probe must not inherit. Pure and static so it is unit-testable without an engine. |
| `fed_asphyxiant` | **generalise** `ThermalSystem.compute_fed_delta_for_height` (`:4549`) with an include-thermal parameter defaulting to today's behaviour | It already exists, is already non-mutating and height-parameterised. A parallel implementation would fork the CO/HCN/hypoxia formulas and guarantee drift. This is the one place the instruction "generalise rather than abstract" clearly applies. |
| sampling schedule + non-mutating observation | **new** `sim/validation/ProbeSampler.gd` | Sampling is a *validation-harness* concern, not an engine concern. Living under `sim/validation/` keeps it out of the engine's step path and makes it structurally impossible for it to be called by physics. |
| serialisation | **new** `sim/validation/ProbeSeriesWriter.gd` | Mirrors the existing separation between `CaseRunner` (orchestration) and `_write_json_file` (I/O), and keeps the schema in one place. |
| offline `tΔ` analyser | **new** `scripts/simulation/analyze_probe_response.py` | It is offline post-processing over a written artefact. Python, like every other analyser in `scripts/simulation/`. It must not be a Godot component, because that would put an experimental estimator inside the runtime. |
| CaseRunner integration | **minimal edit** to `sim/validation/CaseRunner.gd` | One construction site guarded by the declaration being non-empty, one observation call after `engine.step()` and before `_update_metrics` (§6.4), one write in the finalise path. Nothing else. |

**No new abstraction is proposed where an existing function can be generalised.**
The only genuinely new concepts are: the probe primitive, the schedule, the
serializer and the offline analyser — each of which has no existing home that
would not mix measurement with physics.

---

## 12. Implementation gates

Each gate is independently revertible and ends at a STOP.

### D0 — design and contracts *(this document)*
- **Files:** this document only.
- **Evidence:** verified call graph (§1); §1 claims carry `file:line`.
- **STOP if:** any §1 claim is refuted on review.
- **GO/NO-GO:** GO to commit the design. **Separate** GO required for D1.

### D1 — pure `zone_at_height` primitive
- **Files:** `sim/core/ZoneAtHeightProbe.gd`; fixture
  `tests/fixtures/zone_at_height_probe.gd`; static contract test.
- **Tests:** T-UNIT, T-ZONE, T-DEGEN, T-NOMUT.
- **Evidence:** every degenerate case returns `unknown` with a reason; no call to
  `compute_co_lower_ppm`; zero writes to `RoomModel`.
- **STOP if:** any path returns a bulk value, a zero, or the other zone's value in
  place of `unknown`.
- **GO/NO-GO:** GO only with a full degenerate matrix green.

### D2 — sampler (default OFF) and serialisation
- **Files:** `ProbeSampler.gd`, `ProbeSeriesWriter.gd`, minimal `CaseRunner`
  integration, schema contract tests.
- **Tests:** T-SCHED, T-SER, T-INV, T-FAILCLOSED.
- **Evidence:** with no declaration, per-case report and CSV are **byte-identical**
  to the pre-D2 artefacts; nominal grid drift-free over a long synthetic run;
  write failure exits non-zero.
- **STOP if:** any official case is modified; any shared surface gains a field;
  byte-identity fails.
- **GO/NO-GO:** GO only if byte-identity holds on the full official corpus.

### D3 — `fed_asphyxiant`
- **Files:** parameter added to `compute_fed_delta_for_height`; probe consumption.
- **Tests:** T-FED-ASPH, T-FED-UNCHANGED.
- **Evidence:** `room.fed` and its four components bit-identical on the corpus;
  `fed = fed_co + fed_hcn + fed_hypoxia + fed_heat` still holds; asphyxiant value
  reproduces the hand-computed 0.2152582 on the frozen kitchen state.
- **STOP if:** `room.fed` changes anywhere, by any amount.
- **GO/NO-GO:** GO only with the existing FED provably untouched.

### D4 — parametric `tΔ` analyser *(experimental, non-gating)*
- **Files:** `scripts/simulation/analyze_probe_response.py`; synthetic tests.
- **Tests:** T-TD-SYNTH, T-TD-SENS, T-DELAY.
- **Evidence:** recovers planted response times on synthetic series; emits a full
  sensitivity surface; refuses to run without a declared parameter vector and a
  declared delay sign.
- **STOP if:** any default parameter is introduced, or any output selects a
  preferred parameter set.
- **GO/NO-GO:** GO only if the analyser is incapable of emitting a single
  "the answer" without an explicit, recorded parameter choice.

### D5 — Ghanekar reproduction *(still non-gating)*
- **Files:** a **new** exploratory case; comparison report. **No official case, no
  contract, no `expected`, no `tolerance`, no `required` may change.**
- **Evidence:** raw series, delay envelope, sensitivity surface, limitation record.
- **STOP if:** any result is proposed as a contract, or any existing contract is
  edited.
- **GO/NO-GO:** explicitly **not** a gate to requalify the Ghanekar checks.
  Requalification is a separate decision with its own authorisation.

---

## 13. Test matrix

| id | layer | asserts |
|---|---|---|
| T-STATIC | static contract (Python, text) | this document exists; schema versions declared; no default height, delay or `tΔ` parameter appears in any committed schema |
| T-UNIT | pure unit (Godot fixture, no engine) | zone selection at, above and below the interface; `height == interface → UPPER` |
| T-ZONE | pure unit | probe interface value equals `effective_hot_layer_height_m`; recorded per sample |
| T-DEGEN | pure unit | full degenerate matrix (§4.3) → `unknown` + correct reason; **never** 0.0, bulk or other-zone |
| T-NOMUT | pure unit | full room-state hash identical before/after sampling |
| T-SCHED | scheduler (pure) | `t_k = k·period` exactly over 10⁵ samples; multi-instant steps emit all instants with increasing skew; `t_skew ≤ dt` |
| T-SER | parser/serialisation (Python) | round-trip; `null` always accompanied by `reason`; unknown schema version rejected |
| T-INV | invariance campaign | probes absent ⇒ per-case report and CSV **byte-identical** across the official corpus |
| T-FAILCLOSED | integration | probe write failure ⇒ non-zero exit |
| T-FED-ASPH | unit | asphyxiant sum excludes thermal; reproduces 0.2152582 on the frozen kitchen state |
| T-FED-UNCHANGED | regression | `room.fed` and components bit-identical; checklist §7 identity holds |
| T-TD-SYNTH | offline synthetic | planted response times recovered on noise-free and noisy synthetic series |
| T-TD-SENS | offline | sensitivity surface emitted; no parameter set selected; non-convergence reported |
| T-DELAY | offline | envelope only, no point estimate; sign convention mandatory and recorded |
| T-GODOT-RT | Godot runtime *(future)* | end-to-end sampling under a real run — **deferred**, requires a Godot gate |
| T-GHANEKAR | comparison *(future)* | **non-blocking**; publishes divergence, never a PASS |

**Layer separation is explicit.** T-STATIC/T-SER/T-TD-* are pure Python and never
touch a runtime. T-UNIT/T-ZONE/T-DEGEN/T-NOMUT/T-SCHED are Godot fixtures with no
engine. T-INV and T-FAILCLOSED are campaign/integration. T-GODOT-RT and
T-GHANEKAR are future runtime work and are **not** part of D1–D4.

---

## 14. Threat model — enumerated ways this could deceive us

Each threat names its structural mitigation. A mitigation that is only a
convention is marked as such.

| # | self-deception | mitigation |
|---|---|---|
| 1 | **Bulk substituted for a missing zone.** Already live in `compute_co_lower_ppm` (§1.2) and in the FED lower branch (§1.4). | Probe never calls `compute_co_lower_ppm`; `unknown` is a first-class value; T-DEGEN forbids substitution |
| 2 | **Threshold or polynomial chosen to yield 198 s.** | No threshold exists in the design (§8.1); no default parameters; whole sensitivity surface reported (§8.4); T-TD-SENS |
| 3 | **Delay sign chosen for convenience.** | Sign convention mandatory, recorded, and refused if absent (§7.3); envelope only, no point estimate; T-DELAY |
| 4 | **Calling it a "0.9 m probe".** | Named `zone_at_height`; mandatory machine-readable limitation record (§9.3) declaring horizontal position and stagnation unrepresented (§3) |
| 5 | **Adding heat to the paper's FED.** | `fed_asphyxiant` defined without a thermal term (§5.3); `room.fed` untouched; T-FED-ASPH and T-FED-UNCHANGED |
| 6 | **Changing `expected`/`tolerance`/`required`.** | Out of scope in every gate; D5 explicitly forbidden from touching contracts; aggregate invariants in §11.8 |
| 7 | **Probes enabled by default.** | Default OFF; T-INV byte-identity; no official case enabled through D4 |
| 8 | **Sampling from the 10 s log.** | Sampler attached to the 12 Hz step, structurally unable to read the log (§6.4, §6.6) |
| 9 | **`unknown` silently becoming 0.** | Already live at `_call_room_float(..., 0.0)` (§1.6). Probe serialises `null` + `reason`; T-DEGEN and T-SER |
| 10 | **Measurement feeding physics.** | Sampler lives under `sim/validation/`, holds no writable reference; T-NOMUT; §11.4 |
| 11 | **Reading k = 1 as 95 %.** | Uncertainty semantics recorded in every comparison artefact: sample SD, k = 1, ≈ 68 %, n = 10 bedroom / 6 kitchen |
| 12 | **Calibrating the kitchen against a non-equivalent control volume.** | Kitchen redesign is NO-GO; §12 D5 forbids contract edits; the control-volume problem is recorded in the committed contract notes |
| 13 | **Blending species to mimic the temperature probe.** | Binary selection with stated rationale (§4.2); blending would invent a vertical profile |
| 14 | **Treating `upper`/`lower` as averaging to `bulk`.** | Inconsistent mass models recorded (§1.2) and flagged in the limitation record (§9.3) |
| 15 | **Silently picking a presence epsilon.** | Epsilon is a required declaration with no default and is recorded per sample (§4.3) |
| 16 | **Dry/wet reconciled by an invented humidity.** | No conversion designed; basis declared on both sides (§5.4) |
| 17 | **Presenting a probe value as clean when its input was already shaped.** The stored upper masses are clamped upstream (DEP-7). | Provenance recorded per value; DEP-7 recorded in the design and in the limitation record; the probe never claims to have removed the shaping |
| 18 | **Silently picking one of CO2's two divergent inventories** (DEP-8). | The CO2 provenance actually used is recorded per sample; the >5× divergence warning is cited in the design |
| 19 | **Treating the FED ±0.10 m ramp as a smooth mapping** and building a blended probe on it. | §1.3 records that `>= 0.5` collapses it to exactly `z ≥ interface`; the probe is binary and says so |

---

## 15. Dependencies and open questions

**Dependencies — recorded, NOT acted on in this session.**

- **DEP-1 — zone-presence predicate fragmentation.** At least four thresholds
  coexist (`> 0.1` kg, `> 1e-4`, `> 1e-6`, `> 0`). The probe defers by requiring an
  explicit epsilon, but a project-level decision is owed.
- **DEP-2 — interface definition fragmentation.** Four height→zone mappings and
  seven layer-height fields (§1.3). The checklist §5 already flags this.
- **DEP-3 — `compute_co_lower_ppm` is contaminated.** Silent bulk fallback plus a
  non-physical stratification factor (§1.2). The probe routes around it; the
  exported `co_lower_ppm` column remains as it is. Fixing it is a physics/export
  decision with contract impact and is **not** authorised here.
- **DEP-4 — dry/wet basis.** No humidity datum on either side (§5.4).
- **DEP-5 — FED lower branch reads bulk CO** (`ThermalSystem.gd:4554`, `:4618`).
  Affects `room.fed`, therefore contracts. Recorded only.
- **DEP-6 — `co2_lower_ppm` and `hcn_lower_ppm` are computed but never exported**
  (§1.6). No action proposed.
- **DEP-7 — stored upper species masses are shaped upstream of every accessor.**
  `ThermalSystem.gd:4926-4929` clamps `co_upper_kg`, `co2_upper_kg` and
  `hcn_upper_kg` to `3 × upper_geom_frac` of bulk, plus a decay clamp at
  `:4920-4922`. No measurement layer can be cleaner than this input. Recorded
  only; changing it is a physics decision with contract impact.
- **DEP-8 — CO2 has two divergent inventories.** `room.co2_upper` (mole fraction,
  owned by `OxygenExchangeSystem`/`HVACSystem`) versus `room.co2_kg`/`co2_upper_kg`
  (mass). The codebase already warns when they diverge by > 5×
  (`OxygenExchangeSystem.gd:733-737`). The probe must record which CO2 provenance
  it used; it cannot reconcile them.
- **DEP-9 — orphan duplicate `RoomModel`.** `sim/models/RoomModel.gd` declares a
  competing `h_layer_m` default (1.8 vs 2.5 in `sim/building/RoomModel.gd`) and is
  referenced by nothing. Dead but confusing; flagged, not removed.

**Open questions.**

- **OPEN-1 — intervention surrogate.** The published `tΔ` estimator's window ends
  at intervention; simulations have none (§8.2). Unresolved, and it is the reason
  §8 is BLOCKED.
- **OPEN-2 — interpolation.** Deferred (§6.3); revisit only if a consumer needs
  sub-`dt` resolution, which no current target does.
- **OPEN-3 — multi-probe aggregation.** Out of scope for v1.
- **OPEN-4 — should the probe record both a binary zone and the FED-style
  ±0.10 m exposure factor**, so the sensitivity of results to the zone rule is
  measurable? Attractive, deferred to D1 review.
- **OPEN-5 — UL FSRI technical reports** [25] `doi:10.54206/102376/DPTN2682` and
  [26] `doi:10.54206/102376/ZKXW6893` may publish the sampling-line length and
  per-line delays the article omits. Not obtained.

---

## 16. Status

**D0 complete. D1 not started and not authorised by this document.**

The three Ghanekar contracts remain **provisionally demoted, not closed**.
Kitchen redesign remains **NO-GO**. H3.2b4, H3.3 and runtime authority remain
**NO-GO and frozen**. HVAC remains **deferred**.
