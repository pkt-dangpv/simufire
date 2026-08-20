# Phase 3 H3.2b2 — Pure residual projection primitive

Date: 2026-08-20 (reopened and corrected the same day after a review NO-GO)
Status: **primitive only, zero call sites, no authority.**

Created: `sim/core/Phase3ResidualProjection.gd`,
`tests/fixtures/phase3_h32b2_residual_projection.gd`,
`tests/test_phase3_h32b2_residual_projection.py`, this document, and the
CHANGELOG/HANDOFF/checklist entries.

Not created and not touched: call sites, flags, member state, `RoomModel`,
`BuildingModel`, `ZoneFireSolver`, `SimulationEngine`, `ThermalSystem`,
`GasExchangeSystem`, HVAC, CSV columns, runners, reports, legacy physics,
authority, runtime shadow, fallback, VALID_GAP, baselines, expected values and
tolerances. No scenario was run: without a call site a scenario would be empty
evidence.

---

## 0. Review NO-GO of the first issue, and the remedy

The first issue of this primitive was rejected at review. Three blockers, all in
the primitive itself, all now corrected. The original STOP gate is preserved as a
NO-GO record rather than deleted.

| # | Blocker | Why it was a blocker | Remedy |
|---:|---|---|---|
| 1 | **A second, incompatible definition of air.** The primitive hard-coded `AIR_R_SPECIFIC_J_KG_K = 287.052874`. | It made this file a competing definition of air and manufactured a **345.5 Pa** disagreement with `Phase3CoupledPressureSolver` out of nothing. H3.2b3 would have opened with a divergence created by constants, not by physics. | The canonical reference constants and gas-constant derivation of `Phase3CoupledPressureSolver.gd:78-79`, `:1115-1119`, reproduced (never imported) so the primitive stays autonomous. §2. |
| 2 | **`NaN` inside a `valid: true` result.** Absent zones carried `temperature_k: NAN` and `density_kg_m3: NAN`. | A result flagged valid was not usable without guarding every field. "Fail loud" is right for an invalid state, not for a valid one. | An absent zone now carries **only** the fields that have a meaning for it. No `valid: true` result contains `NaN` or `INF` anywhere, checked by a recursive walk. §3. |
| 3 | **The one-zone interface depended on rounding.** `lower absent` returned `+1e-16` rather than `0.0`, and the test papered over it with `is_equal_approx`. | The boundary of a one-zone room is a geometric fact known from the presence state, not a computed quantity with rounding error. | Both one-zone boundaries are now returned **exactly**, by construction, and the tests require exact equality. §5. |

A fourth review point followed from blocker 2: the determinism helper treated
`NaN` as equal to `NaN`, which is not binary identity. With `NaN` gone from valid
results, determinism is now checked by comparing **complete byte serialisations**.
§7.

> **[SUPERSEDED 2026-08-20.]** The first issue of this document stated, in its §2
> and its risk 2, that the legacy reference density implied *"100 979.5 Pa at
> 20 °C, 345.5 Pa (0.341 %) below standard sea level"*, and treated that gap as a
> **physical divergence to be quantified at H3.2b3** and as an expected baseline
> movement. **That framing is withdrawn.** The gap was not physical and was not a
> property of the engine: it was created entirely by the primitive's own choice
> of `287.052874 J/(kg·K)` against the engine's reference state. Under the
> canonical constants the primitive reproduces `AIR_PRESSURE_REF_PA = 101325.0`
> at ambient to **1.294 ulp**, and matches the canonical solver's own pressure
> form to **0.000 ulp**. There is no constant-induced divergence for H3.2b3 to
> inherit. The wording is preserved here rather than deleted so the error stays
> auditable.

---

## 1. The API, and why the geometry is sufficient

```gdscript
static func derive(
    upper_mass_kg: float, upper_energy_kj: float,
    lower_mass_kg: float, lower_energy_kj: float,
    floor_area_m2: float, room_height_m: float,
    ambient_temp_c: float
) -> Dictionary

static func floor_area_from_volume_m2(room_volume_m3: float,
                                      room_height_m: float) -> float
```

Seven scalars in, one fresh Dictionary out. No object, no reference, no handle
to anything that could be written.

**Geometry form chosen: `floor_area_m2` + `room_height_m`.** The room volume is
`A · h` and the two-zone interface is the depth of the lower layer, `V_lower / A`
— the same form as the canonical solver at
`Phase3CoupledPressureSolver.gd:1261`, and algebraically identical to the legacy
`h − V_upper / A` of `ZoneFireSolver.gd:267` precisely because the volumes close.

**The assumption is named, not hidden.** That form requires the room to have a
**constant horizontal cross-section**. It is stated in the function's own doc
comment rather than buried in the arithmetic.

**Why it is sufficient here, and exactly rather than approximately.** `RoomModel`
carries only `width_m`, `length_m` and `height_m`, and defines
`floor_area_m2() = width_m * length_m` (`sim/building/RoomModel.gd:347`) and
`volume_m3() = width_m * length_m * height_m` (`:351`). So `V = A · h` is an
**identity in this codebase**, not a modelling approximation introduced here. A
room whose cross-section varied with height would break the assumption — and
cannot currently be represented. **No blocker.**

`floor_area_from_volume_m2()` is a **fallible auxiliary API, not a result**. It
returns `NAN` to signal unusable input rather than guessing, and that is the one
place in the file where `NAN` is a legitimate return value — legitimate precisely
because it is not a `valid: true` result. Callers must test it with `is_nan()`;
`derive()` rejects a non-finite area anyway.

---

## 2. The canonical equation of state

**There is no separate specific gas constant in this file, and there must never
be one.** The constants and the derivation are the canonical solver's:

```
reference_temp_k = ambient_temp_c + 273.15
gas_constant     = AIR_PRESSURE_REF_PA / (AIR_DENSITY_REF_KG_M3 * reference_temp_k)
```

with `AIR_PRESSURE_REF_PA = 101325.0` and `AIR_DENSITY_REF_KG_M3 = 1.2`, both
identical to `Phase3CoupledPressureSolver.gd:78-79`. The gas constant therefore
**depends on the ambient temperature**, exactly as it does in the canonical
solver; it is not a universal constant and is not presented as one. At 20 °C it
is 288.0335 J/(kg·K).

The convention is **reproduced, never imported**. The primitive does not call,
preload or reference `Phase3CoupledPressureSolver`; a contract forbids it. It
stays autonomous and pure while using identical arithmetic.

**Energy convention.** `E_zone` is **sensible energy measured from ambient**, in
kJ, exactly as at `ZoneFireSolver.gd:214-221`, so `E = 0` means "at ambient", not
"no energy". A negative `E` would mean a zone below ambient; no owner produces
one, so it is rejected.

**The four equations, in evaluation order** (writing `K` for `gas_constant`):

```
T_zone_k = reference_temp_k + E_zone / (M_zone · cp)
p_abs    = (K / V_room) · (M_upper · T_upper_k + M_lower · T_lower_k)
rho_zone = p_abs / (K · T_zone_k)
V_zone   = M_zone / rho_zone
```

**Constants, all explicit, none scenario-configurable:**

| constant | value | provenance |
|---|---|---|
| `AIR_CP_KJ_KG_K` | 1.0 kJ/(kg·K) | shared by `ZoneFireSolver` and `Phase3CoupledPressureSolver` |
| `AIR_PRESSURE_REF_PA` | 101325.0 Pa | `Phase3CoupledPressureSolver.gd:78` |
| `AIR_DENSITY_REF_KG_M3` | 1.2 kg/m³ | `Phase3CoupledPressureSolver.gd:79` |
| `KELVIN_OFFSET_C` | 273.15 | |
| `DOUBLE_EPSILON` | 2.220446049250313e-16 | IEEE-754 binary64 |
| `VOLUME_CLOSURE_ROUNDING_BUDGET` | 16 | derived in §6 |
| `AMBIENT_PRESSURE_ROUNDING_BUDGET` | 8 | derived in §3 |

### Agreement with the canonical solver

`Phase3CoupledPressureSolver.gd:1252-1254` writes the same pressure as

```
gas_constant · (M_total · T_ref + E_total / cp) / V
```

which is algebraically identical to this primitive's
`(K / V) · (M_u·T_u + M_l·T_l)` — expand the temperatures and the mass-weighted
sum collapses to `M_total·T_ref + E_total/cp` — but **rounds differently**. The
fixture recomputes the solver's form independently, over seven states spanning
−10 °C to 35 °C ambient, a 1e-9 kg zone and a 59:1 mass ratio:

```
H3.2B2_EOS_VS_SOLVER_WORST_ULP=0.000   BUDGET_ULP=8
```

**Exact agreement, 0.000 ulp.** The primitive is not a second definition of air.

---

## 3. The ambient identity — expected versus observed

A room holding exactly `M_total = AIR_DENSITY_REF_KG_M3 · V_room` at `E = 0` must
derive `p_abs = AIR_PRESSURE_REF_PA`:

```
p = (K/V)·(1.2·V)·T_ref = (P_ref / (1.2·T_ref) / V)·1.2·V·T_ref = P_ref     ∎
```

| | value |
|---|---|
| expected | **101 325.0 Pa exactly** |
| observed, worst over 48 cases | **101 325.0 Pa to within 1.294 ulp** |
| bound | 8 ulp of `AIR_PRESSURE_REF_PA` |

The 48 cases are eight rooms (floor areas 3–100 m², heights 2.2–4.0 m, ambients
−10 °C to +35 °C) × six upper/lower mass splits from 0 % to 100 %.

**The identity is exact in real arithmetic; only its floating-point evaluation
carries the 1.294 ulp.** The 8 ulp bound is derived, not fitted: the gas constant
costs two roundings, the mass-temperature product and sum two, and the final
divide and multiply two — six, rounded up to the next power of two. An
independent sweep of 200 000 random rooms during development put the worst case
at **1.940 ulp**, still 4× inside the bound.

This is precisely the check the first issue failed, by 345.5 Pa.

---

## 4. Every state, valid and invalid

Validation order is **fixed** so that a state failing several checks always
reports the same code.

| # | State | Result | `reason_code` |
|---:|---|---|---|
| 1 | any input non-finite (NaN, ±INF) | invalid | `non_finite_input` |
| 2 | `floor_area ≤ 0` or `height ≤ 0` | invalid | `invalid_geometry` |
| 3 | `T_ambient,K ≤ 0`, or a non-finite/non-positive gas constant | invalid | `invalid_ambient_temperature` |
| 4 | `M_upper < 0` or `M_lower < 0` | invalid | `negative_mass` |
| 5 | `E_upper < 0` or `E_lower < 0` | invalid | `negative_energy` |
| 6 | `M = 0` and `E > 0`, either zone | invalid | `energy_without_mass` |
| 7 | `M_upper = 0` **and** `M_lower = 0` | invalid | `both_zones_absent` |
| 8 | `M = 0` and `E = 0`, one zone only | **valid**, zone absent | `ok` |
| 9 | `M > 0`, `E = 0` | **valid**, zone at exactly ambient | `ok` |
| 10 | `M > 0`, `E > 0`, both zones | **valid** | `ok` |
| 11 | derived `p` or `V` non-finite, or a present zone's `T`/`rho` non-finite or non-positive | invalid | `non_finite_result` |
| 12 | derived `p ≤ 0` | invalid | `non_positive_pressure` |
| 13 | closure error outside the rounding budget | invalid | `volume_closure_out_of_budget` |
| 14 | two-zone interface outside `[0, h]` beyond the budget | invalid | `interface_out_of_budget` |

### Zone schema

| field | absent zone | present zone |
|---|---|---|
| `present` | `false` | `true` |
| `mass_kg` | `0.0` | the input, bit-identical |
| `energy_kj` | `0.0` | the input, bit-identical |
| `volume_m3` | `0.0` | derived, finite |
| `temperature_k` | **omitted** | derived, finite and **strictly positive** |
| `density_kg_m3` | **omitted** | derived, finite and **strictly positive** |

An absent zone carries **only** the fields that have a meaning for it. Nothing is
invented: no ambient temperature, no reference density, no composition — the
primitive never mentions a species. A reader that wants a temperature must test
`present` first, and gets a **missing key** rather than a plausible number if it
does not. Before emission, every present zone is checked finite and positive; a
zone that cannot satisfy that makes the whole result fail closed with
`non_finite_result` rather than being emitted with a hole in it.

**No `valid: true` result contains `NaN` or `INF` anywhere.** The fixture proves
it by walking each result recursively, including nested zone dictionaries, over
seven states. The walker is **self-tested** — it must detect a nested `NAN`, a
nested `INF`, and stay quiet on finite content — so a silently broken walker
cannot make the check pass vacuously.

**Fail-closed shape.** An invalid result carries **no derived field at all** — no
pressure, temperature, density, volume, interface, gas constant or reference
temperature. Only `valid`, `reason_code`, the two exact-zero corrections and
`thermal_limit_applied`. It is impossible to read a usable-looking number off a
rejected state, and it contains no `NaN` either. The fixture asserts both
directions, so the check cannot pass merely because the keys never exist.

**One zone absent is not a special case of the algebra.** If `M_upper = 0` then
`p = (K/V)·M_l·T_l` and `V_lower = M_l·K·T_l/p = V_room` exactly, so the present
zone fills the room and the absent one occupies exactly zero.

---

## 5. The one-zone interface is exact

When one zone is absent the boundary is **not a rounded quantity**. It is a
geometric fact determined by the presence state, and it is returned exactly:

| state | `interface_height_m` | `interface_height_raw_m` |
|---|---|---|
| upper absent | **`room_height_m`, exactly** | same exact value |
| lower absent | **`0.0`, exactly** | same exact value |
| both present | `V_lower / A`, projected into `[0, h]` | the unprojected value |
| both absent | invalid — `both_zones_absent` | — |

**API shape is constant**: `interface_height_raw_m` is always present, and in the
one-zone cases it carries the same exact boundary. That keeps the result shape
stable for the recursive finiteness walk and for byte-level determinism, and it
is fixed by tests. No information is lost by doing so: the rounding that the raw
value would otherwise have exposed is still reported, in
`volume_closure_error_m3`.

**This corrects no mass and no energy.** The exact branch assigns only the
interface; contracts verify that no mass, energy or volume assignment appears
inside it, and that the exact branch contains no `clampf`, `snapped`, `round` or
`is_equal_approx`.

The tests require **exact equality** (`==`), never `is_equal_approx`, and check
it across three additional rooms (3–100 m² floor area, −5 °C to 30 °C ambient) so
the exactness cannot depend on the particular room, ambient or inventory.

For the two-zone case the projection into `[0, h]` remains bounded by the same
derived rounding budget, fails closed outside it, and is the **only** `clampf` in
the whole primitive — a contract pins that count at exactly one.

---

## 6. Volume closure and the floating-point bound

**Algebraic proof.**

```
V_upper + V_lower = M_u·K·T_u/p + M_l·K·T_l/p = (K/p)·(M_u·T_u + M_l·T_l)
```

and from the pressure equation `(M_u·T_u + M_l·T_l) = p·V_room/K`, hence

```
V_upper + V_lower = (K/p)·(p·V_room/K) = V_room                            ∎
```

identically, for **any** masses and energies satisfying the validity contract,
and **for any value of `K`** — which is why switching to the canonical gas
constant did not disturb the closure. Nothing is adjusted to make it hold. **The
lower mass is no longer derived from the geometry — the geometry is derived from
the masses.**

**The bound is numerical, not physical, and derived, not fitted.** The dependency
path now carries **fourteen** rounding operations: the gas constant (multiply,
divide = 2), temperature (multiply, divide, add = 3), pressure (two multiplies,
an add, a divide and a multiply = 5), density (multiply, divide = 2), volume
(divide = 1) and the final sum (1). The gas constant added two to the twelve of
the first issue; the budget is unchanged because 14 ≤ 16, and the derivation text
was updated rather than left stale.

```
|V_upper + V_lower − V_room| ≤ 16 · ε · V_room ,   ε = 2.220446049250313e-16
```

The bound **scales with the room** and is never an absolute metre-cubed
tolerance. A state outside it **fails closed** rather than being nudged.

**Measured over six closure cases** including a 1e-9 kg zone and a 59:1 mass
ratio:

```
H3.2B2_CLOSURE_WORST_ULP=0.000   BUDGET_ULP=16
```

**Exact closure, 0.000 ulp** — better than the 0.640 ulp the first issue measured
with the non-canonical constant.

---

## 7. Mass and energy, determinism, idempotence

**Nothing is corrected, because nothing needs correcting.**

| output | value |
|---|---|
| `upper.mass_kg` / `upper.energy_kj` | the inputs, **bit-identical** |
| `lower.mass_kg` / `lower.energy_kj` | the inputs, **bit-identical** |
| `mass_correction_kg` | `0.0`, a literal |
| `energy_correction_kj` | `0.0`, a literal |

Bit-identity is checked by comparing **byte serialisations** of the returned
float against the input, using long-mantissa values (`10.123456789012345 kg`,
`2000.987654321098 kJ`, …). The corrections are **literals, not computed
differences**; a contract asserts the literal form, so a future edit that started
computing a correction would fail the test rather than quietly return a small
number.

**Determinism is binary.** Two evaluations of the same input are compared by
`var_to_bytes()` over the **complete result**, byte for byte. There is no
approximate comparison and no special case for any value — with `NaN` gone from
valid results, nothing needs one. The previous `_same_dict`/`_same_float`
comparator, which treated `NaN` as equal to `NaN`, is deleted, and a contract
asserts it has not come back.

Checked for **three shapes**: two zones present, upper absent, lower absent. The
comparator is itself controlled: it must report two results differing only in the
ninth decimal of one input as **not** identical, so a comparator that always
returned true could not carry the test.

**Idempotence.** Feeding the returned `M` and `E` back in reproduces the result
**byte-identically**, for all three shapes. This is trivial *because* `M` and `E`
come back unchanged — and that is precisely what the legacy path cannot do:
`ZoneFireSolver.gd:281` overwrites `lower_gas_kg` from the remaining volume, so a
second call on the same room answers differently. H3.2b1a measured the
consequence at scale: **100 % of room-steps across the ten-topology corpus carry
more than one projection call**. Idempotence is not a theoretical nicety here; it
is the property the current path lacks in the regime it actually runs in.

---

## 8. Consumers not yet compatible with an absent zone

Enumerated, **not modified**. Unchanged from the first issue, and still open.

**There is no shared definition of an absent zone in this codebase.** Seven
different presence tests are in use, spanning eleven orders of magnitude:

| threshold for "the upper zone exists" | where |
|---|---|
| `> 0.1` kg | `ThermalSystem.gd:4553`, `:4616` — the FED hypoxia and irritant gate |
| `> 0.01` kg | `ThermalSystem.gd:4583`, `:4657` — the FED heat gate |
| `> 0.001` kg | `GasExchangeSystem.gd:1994`, `:2128`, `:3435`, `:3438` |
| `> 0.0001` kg | `ZoneFireSolver.ZONE_MASS_EPS_KG` (`:53`), used at `:214`, `:219`, `:284`; `ThermalSystem.gd:1186`, `:2951`, `:3127`, `:3468`; `GasExchangeSystem.gd:3250` |
| `> 1.0e-6` kg | `Phase3ProjectionCausalLedger.ZONE_MASS_EPS_KG` (`:67`) |
| `> 1.0e-12` kg | `Phase3CoupledPressureSolver.MASS_EPS_KG` (`:87`); `Phase3ZoneMassSystem.THERMO_MASS_EPS_KG` (`:26`) |
| `> 0.0` (strictly positive) | `HVACSystem.gd:484`; **and this primitive** |

1. **The primitive and the FED gate disagree by six orders of magnitude.** A zone
   holding 0.05 kg is *present* to the primitive and *absent* to
   `ThermalSystem.gd:4553`. Any call site added at H3.2b6 inherits that
   disagreement unless it is resolved first.
2. **A missing key now, not a `NaN`.** Since blocker 2 was fixed, a consumer that
   reads `temperature_k` without checking `present` gets a **missing-key error**
   rather than a silently propagating `NaN`. That is a strictly better failure
   mode, and it still means every future consumer must branch on `present`.
3. **No consumer currently divides by zone mass unguarded.** `ZoneFireSolver.gd:216`,
   `:221`, `:285`, `Phase3CoupledPressureSolver.gd:1247` and
   `Phase3ZoneMassSystem.gd:2430` are each guarded by their own epsilon. The
   incompatibility is definitional, not a division-by-zero hazard.
4. **`SimulationStateBuilder.gd:430-431` computes its EOS columns from the legacy
   reference density** with a `maxf(0.05, density)` floor, so those columns
   measure a different model and must not be compared naively at H3.2b3.

Resolving the presence predicate is a prerequisite for H3.2b6, alongside the
H3.2b1b transition-counter repair.

---

## 9. Zero call sites, zero physical change

- **Zero call sites.** `git grep -l --untracked Phase3ResidualProjection` returns
  only the primitive, its fixture, its test, the changelog and documentation. A
  contract enforces it, using `--untracked` specifically so that a call site
  added in a new, not-yet-committed file cannot slip past vacuously.
- **Zero physical change.** `git status --porcelain -- sim/` lists **no modified
  tracked file** — the only entry under `sim/` is the new, untracked
  `Phase3ResidualProjection.gd`.
- **No flag**, **no member state**, **no `class_name`**, every function `static`.
- **No coupling.** The primitive's code mentions no `RoomModel`, `BuildingModel`,
  `SimulationEngine`, `ZoneFireSolver`, `ThermalSystem`, `GasExchangeSystem` or
  `HVACSystem`, performs no `preload`, `load`, `get_node` or `get_tree`, and does
  not reference `Phase3CoupledPressureSolver` — whose *convention* it reproduces
  and whose *code* it never touches.
- **No forbidden vocabulary.** No `alpha`, `blend`, `backfill`, `seed`, `cap` or
  `tuning` as an identifier in comment-stripped source.

---

## 10. Verification

Godot 4.7.1 console headless, editor closed, sequential, explicit logs.

| check | result |
|---|---|
| H3.2b2 fixture | **22/22 PASS** |
| volume closure, measured worst | **0.000 ulp** vs 16 ulp budget |
| EOS vs canonical solver form, measured worst | **0.000 ulp** vs 8 ulp budget |
| ambient reference pressure, measured worst | **1.294 ulp** vs 8 ulp budget |
| structural contracts | **57/57 PASS** |
| all Godot fixtures in the repository | **60/60 PASS** |
| residual Godot processes | **0** |

**External negative control.** The absent-zone `NaN` of blocker 2 was
deliberately reinjected into the primitive and the fixture was re-run. It failed
with four distinct assertions — *"a valid result carries no NAN and no INF
anywhere"* (twice) and *"an absent zone omits temperature_k / density_kg_m3
entirely"* — and the primitive was then restored and re-verified. The harness
demonstrably catches the exact class of defect that was corrected.

**Internal negative controls.** The recursive finiteness walker must detect a
nested `NAN` and a nested `INF` and stay quiet on finite content; the byte
comparator must separate two results differing in the ninth decimal; and the
invalid-result check is paired with its inverse so it cannot pass because keys
never exist.

Suite-level: the full pytest run shows **exactly one new failure** against the
pre-existing HEAD baseline, and it is the **R2-1 reports-freshness** guardrail,
whose verbose output names a single cause:

```
R2-1: cambios sin commitear en motor/casos y el reporte NO fue regenerado:
    ?? sim/core/Phase3ResidualProjection.gd
```

That is the expected state of this phase: R2-1 fires whenever anything under
`sim/core` is uncommitted while the reference report is clean. **The R2-1 refresh
is explicitly out of scope here** and is not performed. Counterflow, ILV and gaps
show no regression; the one ILV failure predates this work at HEAD.

---

## 11. Risks

1. **The primitive is unexercised by any scenario.** By construction: without a
   call site a scenario would be empty evidence. Everything here is
   function-level. The first contact with real trajectories is H3.2b3's shadow
   comparison.
2. **The real divergence at H3.2b3 is the density model, not the constants.** The
   legacy path is not an equation of state at all: it scales a fixed reference
   density by an ambient/zone temperature ratio (`ZoneFireSolver.gd:257`), which
   makes each zone's density independent of the other zone. The primitive
   couples them through a shared room pressure. Now that the constants agree
   exactly, whatever H3.2b3 measures is that structural difference — which is the
   thing worth measuring. Baselines may still move at H3.2b6, and that must be
   explained physically, never tuned.
3. **The presence predicate is unresolved** (§8). Seven definitions, eleven
   orders of magnitude.
4. **A missing key is a hard failure for a careless consumer.** Correct for a
   primitive with no consumers; every H3.2b6 call site must branch on `present`.
5. **The rounding budgets are arguments plus measurements, not formal error
   analyses.** 14 roundings → 16 ulp with 0.000 ulp measured; 6 roundings → 8 ulp
   with 1.294 ulp measured and 1.940 ulp over a 200 000-case sweep. A
   pathological input could in principle exceed them — in which case the
   primitive fails closed rather than returning a wrong volume.
6. **`E < 0` is rejected, and that is a modelling choice.** No current owner
   produces a below-ambient zone. If S0d2 writes `lower_energy_kj` for
   suppression cooling, this contract must be revisited deliberately rather than
   relaxed in passing.

---

## 12. Decision

**GO for the pure primitive only.**

All three review blockers are corrected and each is now pinned by a contract and
a measurement rather than by assertion: the equation of state is the canonical
one and agrees with the solver's own form to **0.000 ulp** while reproducing
101 325 Pa at ambient to **1.294 ulp**; no `valid: true` result contains `NaN` or
`INF` anywhere, verified by a self-tested recursive walk and an external negative
control; and both one-zone interfaces are **exact by construction**, required by
tests using exact equality. Determinism is now **byte-level**, across two-zone
and both one-zone shapes.

Everything preserved as required: negative energy rejected, `energy_without_mass`
fail-closed, zero M/E corrections, thermal limit deferred to H3.2b5, purity,
prismatic geometry, zero call sites, and the closure budget unchanged at 16 ulp
with its derivation updated from twelve to fourteen roundings.

**NO-GO for everything else.** No call site, no flag, no shadow, no authority, no
scenario evidence. H3.2b3 is not started.

Two prerequisites remain on the record ahead of the later phases:

- **H3.2b1b**, repairing the zone-transition counters, before H3.2b4 can gate on
  them — H3.2b1a measured them missing at least 29 real births.
- **A single presence predicate**, before H3.2b6 wires anything — §8.

H3.2-S, H3.2b and H3.3 remain open; S0d6b1 stays blocked; HVAC stays deferred;
the thermal limit remains H3.2b5's; no runtime authority is granted.
