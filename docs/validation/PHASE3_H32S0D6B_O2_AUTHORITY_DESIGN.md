# Phase 3 H3.2-S0d6b O2 Authority and Conservative Invariant — Design

Date: 2026-08-19
Scope: **design only. Nothing was implemented.** No file under `sim/core` was
modified, no physics changed, no flag added, no campaign run. Every number below
is read-only post-processing of evidence S0d6 and S0d6a already produced.

Recommendation: **Option A (zonal O2 mass authoritative) applied through Option
C's atomic commit discipline.** Bulk becomes a derived view. The rationale is
conservation and semantics, not agreement with current baselines.

> **CORRECTION 2026-08-19 (S0d6b0.1).** Review found a blocking semantic error in
> the version of this document written earlier the same day: it conflated
> **molar/volumetric** fraction with **mass** fraction. `0.209` is a molar
> fraction; `mO2 / mgas` is a mass fraction; in dry air they differ by
> `MO2/Mair = 1.10476`, so `xO2 = 0.20946` corresponds to `YO2 = 0.23140`.
> Section 12, appended below, supersedes any statement in sections 1-11 that
> treats the two as interchangeable, and restates the `2.87x` figure correctly.
> The original text is kept unedited as the historical record; individual
> invalidated claims carry inline `[SUPERSEDED ...]` markers.

H3.2-S stays open, HVAC stays deferred, H3.2b remains an independent prerequisite
of H3.3, no integrator exists and no runtime authority is granted.

---

## 1. Phase 1 — exact semantics

### 1.1 What each value actually is

| State | Declared | What it is **in the code** | Mass base |
|---|---|---|---|
| `room.o2` | `RoomModel.gd:45`, fraction, 0.209 | fraction of a **fictitious constant-density room atmosphere** | `volume_m3() * 1.2` |
| `room.o2_upper` | `RoomModel.gd:47`, fraction | fraction of a **volume-proportional slice** of that same fictitious atmosphere | `volume_m3() * 1.2 * upper_frac` |
| `room.o2_lower` | `RoomModel.gd:49`, *"persistente; NO derivada de o2"* | idem, lower slice | `volume_m3() * 1.2 * lower_frac` |
| `room.upper_o2_mass_tracked` | `RoomModel.gd:53`, kg, `-1.0` sentinel | kg against the same fictitious base | `upper_air_mass` |

The single most important line in this phase is `OxygenExchangeSystem.gd:356`:

```gdscript
var air_density_kg_m3: float = 1.2
```

It is a **hard-coded constant**, and every O2 mass base descends from it
(`_compute_room_air_mass_kg`, `OxygenExchangeSystem.gd:1325-1328`):

```
air_mass_kg    = maxf(0.1, room.volume_m3()) * 1.2
upper_frac     = (height_m - hot_layer_m) / height_m        # VOLUMETRIC
upper_air_mass = air_mass_kg * upper_frac
lower_air_mass = air_mass_kg * lower_frac
```

So the O2 fractions are **volumetric fractions against a fixed reference
density**. They are *not* mass fractions of the gas the room actually contains.

### 1.2 The engine already contradicts that base

The two-zone model tracks real, temperature-dependent zone masses. Its own gas
law is explicit at `ZoneFireSolver.gd:257,275`, and again at
`GasExchangeSystem.gd:1781`:

```gdscript
var upper_density_kg_m3: float = AIR_DENSITY_REF_KG_M3 * ambient_k / upper_k
```

so the physical mass of a zone is smaller than its flat-1.2 mass by exactly
`T_ambient_K / T_zone_K`. Measured across the ten S0d6 cases, 20 059 room-steps:

| Case | upper p50 | upper p05 | upper min | rows > 2x inflated |
|---|---:|---:|---:|---:|
| `ppv_attack_pressurized` | 0.995 | 0.400 | 0.348 | 451 |
| `postfire_decay` | 0.999 | 0.764 | 0.352 | 304 |
| `v1_backdraft_accumulation` | 0.936 | 0.419 | 0.352 | 112 |
| `cfast_two_floor_stairwell` | 1.000 | 0.428 | 0.365 | 45 |
| `fuel_balance_diag_sealed` | 0.913 | 0.406 | 0.352 | 42 |
| `o2_stoich_diag_sealed` | 0.913 | 0.406 | 0.352 | 42 |
| `cfast_slow_growth_sealed` | 0.999 | 0.586 | 0.389 | 4 |
| `cfast_hvac_residential` | 1.000 | 0.542 | 0.535 | 0 |
| `cfast_r0_window_360` | 1.000 | 0.644 | 0.519 | 0 |
| `cfast_corridor_chain` | 1.000 | 0.731 | 0.615 | 0 |
| **ALL** | **0.998** | **0.500** | **0.348** | **1 000 (4.99 %)** |

**Worst observed inflation: 2.87x.** Five percent of all rows carry an upper-zone
O2 mass base inflated by two times or more.

> **[SUPERSEDED 2026-08-19 — see section 12.3]** `2.87x` is the inflation of the
> **gas mass base**, not of the O2 mass. The net O2-mass error is
> `0.9050 * (T/T_ambient)`: the engine **understates** physical O2 mass by 9.48 %
> at ambient and in 79.80 % of measured rows, crossing over to overstatement only
> above 50.7 C, with a worst overstatement of **2.60x**, not 2.87x.

### 1.3 This corrects the S0d6 carve-out

S0d6 certified `oes_combustion_upper_sink` as the one `completeness = true` path
because it caps and applies against the same base, `upper_air_mass`. That
internal consistency is real and the certification was correct **on its own
terms**. But the base itself is not physical, so the `-208.47 kg` reported there
are kilograms of a fictitious constant-density atmosphere, overstated by up to
2.87x whenever the layer is hot. **No O2 figure anywhere in the engine is
currently a physical kilogram.**

> **[SUPERSEDED 2026-08-19 — see section 12.3]** The conclusion stands but the
> factor is wrong. Corrected: the reported kilograms are wrong by
> `0.9050 * (T/T_ambient)`, i.e. understated by 9.48 % at ambient and overstated
> by at most 2.60x in the hottest observed layer.

### 1.4 Fraction-to-kilogram conversions

| Site | Expression | Base | Physical? |
|---|---|---|---|
| `OES:461` bulk combustion + ACH | `o2_mass_kg = air_mass_kg * room.o2` | room, flat 1.2 | no |
| `OES:512` upper sink | `upper_air_mass * o2_upper` | upper slice, flat 1.2 | no |
| `OES:597` lower sink | `air_mass_kg * o2_lower` | **room** mass on a **zone** fraction | no, and mismatched |
| `OES:633` plume sink | caps with `lower_air_mass`, applies with `air_mass_kg` | **two bases in one path** | no |
| `OES:912` exterior opening | `room_air_mass_kg` | room, flat 1.2 | no |
| `OES:947` lower replenish | `lower_mass_ext` | lower slice; same `air_in_kg` also credited to bulk | no |
| `GES:2358` room loop | `room_air_mass_kg` | room, flat 1.2 | no |
| `GES:2889` parcel delivery | `volume * 1.2` inline | room, flat 1.2 | no |
| `GES:4231` PPV | `lerpf` on the fraction | **no mass balance at all** | no |
| `Thermal:3363/3371` counterflow | declared 50/50 split, literal `0.209` ceiling | zone masses | no |
| `RoomModel:375-381` helpers | `volume * density * fraction` | flat default | **dead code, zero call sites** |

### 1.5 Where one fraction meets an incompatible mass

Three distinct classes, all confirmed in source:

1. **Zone fraction on room mass.** `OES:597` and `OES:633` update `o2_lower` by
   dividing by `air_mass_kg`. The comment at `OES:620-622` states this is
   deliberate modelling, so it cannot be dismissed as a typo.
2. **Two bases inside one path.** `OES:633` caps the plume sink with
   `lower_air_mass` and applies it with `air_mass_kg`.
3. **Flat-density base on a temperature-tracked gas.** Everywhere, per §1.2.

### 1.6 Minimum missing physical information

O2 cannot currently be conserved as mass, because:

- there is **no stored O2 mass** tied to the gas inventory the room actually
  holds — only fractions against a fictitious atmosphere;
- the fraction's denominator, `volume * 1.2 * volumetric_frac`, is **not** the
  denominator the rest of the engine uses, `upper_gas_kg` and `lower_gas_kg`;
- interior transport of O2 exists in **two independent in-flight pools** —
  `OxygenExchangeSystem._pending_o2_deliveries` with its
  `_reserved_transport_o2_delta_kg` reservation ledger (`OES:1239,1276`) and
  `GasExchangeSystem._pending_interior_deliveries` carrying `o2_kg`
  (`GES:2157`, delivered at `GES:2885`) — with different delay models, and only
  the first reserves anything;
- exterior removal is instrumented for the bulk only, and PPV moves O2 with no
  mass balance whatsoever.

**The minimum missing information is a stored O2 mass per zone, denominated
against the same gas mass the two-zone model already tracks.**

---

## 2. Phase 2 — three architectures

### Option A — zonal O2 mass authoritative

**Stored:** `mO2_upper`, `mO2_lower` in kg.
**Derived:** `mO2_total = mO2_upper + mO2_lower`;
`o2_upper = mO2_upper / upper_gas_kg`; `o2_lower = mO2_lower / lower_gas_kg`;
`o2 = mO2_total / (upper_gas_kg + lower_gas_kg)`.

> **[SUPERSEDED 2026-08-19 — see section 12.4]** These formulas yield the **mass**
> fraction `YO2`. Every consumer needs the **molar** fraction `xO2`. The corrected
> contract inserts the conversion `xO2 = YO2 * Mmix / MO2`.

| Aspect | Assessment |
|---|---|
| Invariants | all eleven expressible; the total is a sum, so it holds by construction |
| Bulk derivation | **exact**, no extra model |
| Tick order | sources and sinks act on a named zone; transport moves zone to zone; views recomputed after the commit |
| Sources, sinks, transport | every operation is a kg on a named zone, capped by that zone's inventory |
| FED | reads derived `o2_upper` / `o2_lower`; same inventory, no change of meaning at the consumer |
| Combustion | reads a derived view; all seven modes become **view selectors**, not separate inventories |
| ILV and re-ignition | consumers unchanged, but now read a value consistent with the zones |
| Writer migration | each writer converts its fraction delta into a zone kg request; about 23 sites |
| Consumer migration | none forced: `o2`, `o2_upper`, `o2_lower` survive as derived properties |
| HVAC | a future supply or return becomes a zone kg exchange with the exterior; the contract fits without redesign |
| Double counting | parcels must debit at enqueue and credit at delivery, from one pool only |
| Projection | projection recomputes **views**, never the stored masses |
| Risk | medium: `upper_gas_kg` can reach zero, so views need a guarded denominator |
| Difficulty | medium |
| Rollback | flag off restores the legacy fractions; the shadow phase proves equality first |

**The zero-mass edge is the one real hazard.** When `upper_gas_kg` approaches
zero the derived `o2_upper` is undefined. That is physically honest — an empty
zone has no concentration — and must surface as `unknown`, never as `0.0` and
never as `0.209`.

### Option B — bulk authoritative

**Stored:** `mO2_total`. **Derived:** a partition into upper and lower.

The partition rule is the whole question, and it **cannot be defined without a
new physical model**. The evidence is direct: S0d6a measured the bulk outside the
bracket of its own zones on 74.67 % of rows, in **both** directions — 31.22 %
below, 43.45 % above. A stored total therefore carries no information about how
it splits, and any split rule, whether volumetric, mass-proportional or
temperature-weighted, would be **invented physics chosen to fit**, which this
phase is explicitly forbidden to do.

It also discards information the engine already has: the zones are driven by
distinct physical processes — plume entrainment, zone ACH, exterior replenish at
the lower band. Collapsing to a total and re-splitting loses all of them.

| Aspect | Assessment |
|---|---|
| Bulk derivation | trivial, but the **zonal** derivation is impossible without new physics |
| FED | would read a re-split value, a modelling artefact, on a life-safety metric |
| Verdict | **rejected** |

### Option C — single atomic state object

**Stored:** one component owning total and zonal masses; writers emit requests;
the component applies acceptance and conservation; one commit per timestep.

| Aspect | Assessment |
|---|---|
| Invariants | strongest: "one authority per timestep" becomes structural, not a convention |
| Bulk derivation | inherits whatever the inner representation is — **C does not answer the representation question** |
| Tick order | explicit: snapshot, collect requests, solve acceptance, single commit, recompute views |
| Double counting | best defence: a request that is not accepted cannot be applied anywhere |
| Difficulty | high alone; it touches every writer at once |
| Verdict | **adopt the commit discipline; it is orthogonal to A versus B** |

### Comparison

| Criterion | A zonal mass | B bulk | C atomic |
|---|---|---|---|
| Bulk derivable exactly | **yes** | yes | depends on inner representation |
| Zones derivable without new physics | yes | **no** | depends |
| Conserves by construction | yes | yes | yes |
| Preserves existing zonal processes | **yes** | no | yes |
| FED reads a real inventory | **yes** | no | depends |
| Forces one writer per timestep | no | no | **yes** |
| Migration cost | medium | high | high |
| Invents physics | **no** | **yes** | no |

**A and C are complementary. B is rejected because it cannot produce zonal values
without inventing a partition rule.**

---

## 3. Recommendation

**Adopt A as the representation and C as the commit discipline.**

- **Authoritative state:** `mO2_upper`, `mO2_lower` in kilograms, denominated
  against `upper_gas_kg` and `lower_gas_kg`.
- **Derived, read-only views:** `mO2_total`, `o2_upper`, `o2_lower`, `o2`.
- **One commit per timestep**, applied by a single component; every writer emits
  a request naming a zone and a kilogram amount.
- `room.o2` survives **only** as a derived property, so consumers need not change
  in the same phase that changes the representation.

Chosen because the bulk derives from the zones exactly while the zones do not
derive from the bulk at all, and because it is the only option that puts FED and
combustion on the same conserved inventory without inventing a split rule.

**It is a change of physical meaning.** Today `o2` is a fraction of a fictitious
constant-density atmosphere; under A it becomes a true mass fraction of the gas
the room holds. Baselines will move. That must be gated on its own, argued on
physical grounds, and never tuned to reproduce current CFAST agreement.

---

## 4. Proposed tick

```text
step(dt)
 |- PRE-STATE SNAPSHOT                       mO2_upper, mO2_lower per room
 |                                           + in-flight parcel inventory
 |- SOURCES / SINKS  (requests, not writes)
 |    combustion      -> request(zone, -kg)   zone chosen by fire_o2_mode view
 |    CO oxidation    -> request(zone, -kg)
 |- EXTERIOR BOUNDARY (requests)
 |    ACH, vents, PPV -> request(zone, +/-kg, exterior)
 |- INTERIOR TRANSPORT (requests)
 |    doorway, counterflow, background
 |                    -> request(from_zone, -kg) + request(to_zone, +kg)
 |    delayed parcel  -> debit at enqueue, credit at delivery, ONE pool
 |- ACCEPTANCE + SINGLE COMMIT                one authority, one write
 |    cap every extraction by the donor zone inventory
 |    emit the rejected amount as numerical_correction, never silently
 |- RECOMPUTE DERIVED VIEWS                   o2_upper, o2_lower, o2
 |- PROJECTION / RECONCILE                    views only; NEVER the stored mass
 `- CONSUMERS READ VIEWS                      FED, combustion, ILV, logging
```

Two rules make it conservative: **projection never touches stored O2 mass**, and
**no state is written outside the single commit**.

---

## 5. Invariants

| # | Invariant | How A+C satisfies it |
|---|---|---|
| 1 | `mO2_total = mO2_upper + mO2_lower` | the total is derived as the sum, so it cannot drift |
| 2 | no negative O2 mass | acceptance caps every extraction at the donor inventory |
| 3 | fractions within physical range | derived; out of range implies a mass or gas-mass bug, so it fails closed |
| 4 | extraction bounded by the donor zone | requests name a zone; acceptance clamps to that zone |
| 5 | interior transport conserves building O2 | paired debit and credit inside one commit |
| 6 | exterior exit accounted | exterior requests carry a boundary marker |
| 7 | combustion consumes the inventory it reads | the mode selects a **view of the same masses** |
| 8 | FED reads a derived view of the conserved inventory | `o2_upper` and `o2_lower` are views |
| 9 | numerical reconciliation never silently creates or destroys O2 | rejected amounts are emitted as `numerical_correction` through the existing ledger |
| 10 | parcels never double-count | one pool; debit at enqueue, credit at delivery |
| 11 | one authority per timestep | structural: only the commit writes |

Invariant 3 needs an explicit `unknown` for an empty zone. Returning `0.0` or
`0.209` would be a silent invention.

---

## 6. What the design must explain in the ten cases

| Case | What it exercises | How A+C explains it |
|---|---|---|
| `cfast_hvac_residential` | worst divergence, 9.13e-02; bulk anoxic while lower at ambient | impossible under A: the bulk is the sum of the zones, so it cannot sit outside their bracket |
| `postfire_decay` | 10 396 of 11 406 rows outside, mostly bulk **above** both zones | today the bulk retains O2 the zones no longer have; under A there is one inventory to retain |
| `v1_backdraft_accumulation` | 37 decision-level disagreements at the backdraft gate | the gate reads a view of the same masses the combustion sink consumed |
| `cfast_two_floor_stairwell` | 402 excursions across a multi-storey transport chain | paired debit and credit conserve across rooms |
| `cfast_corridor_chain` | the only case where the blend fires; 4 excursions | the blend disappears, because there is nothing to re-synchronise |
| `cfast_r0_window_360` | zero excursions | unchanged behaviour is the expected outcome |
| `fuel_balance_diag_sealed`, `o2_stoich_diag_sealed` | sealed, bulk over-depleted, 242 excursions each | sealed means zero exterior requests, so building O2 is exactly conserved |
| `cfast_slow_growth_sealed` | slow depletion, 81 excursions | idem, over a longer horizon |
| `ppv_attack_pressurized` | PPV `lerpf` with no mass balance, 3 055 excursions | PPV becomes an exterior kg request like any other |

None of these were re-run. Each is explained from existing S0d6 and S0d6a
evidence.

---

## 7. Phased implementation plan — not started

| Phase | Files | Flag | Authority | Tests and fixtures | STOP gate | Rollback | Unblocks | Still blocked |
|---|---|---|---|---|---|---|---|---|
| **S0d6b0** design, this document | docs only | none | none | none | this document | delete the doc | S0d6b1 | everything else |
| **S0d6b1** pure primitive | new `sim/core/Phase3O2Inventory.gd`, no call sites | none | none | unit fixture and pytest contracts for invariants 1-4, 9, 11 | primitive proven pure, zero call sites, zero physics diff | delete the file | S0d6b2 | all |
| **S0d6b2** passive shadow | primitive plus a read-only snapshot in `SimulationEngine` | `phase3_o2_inventory_shadow_enabled`, default OFF | none, shadow only | OFF byte-identical; shadow versus legacy divergence report | quantified divergence per case, no CSV change | flag off | S0d6b3 | all |
| **S0d6b3** writer migration | one writer per sub-slice, 23 sites | same flag plus per-writer sub-flags | shadow still | per-writer equality or an explained delta | each writer migrated behind its own gate | per-writer flag | S0d6b4 | consumers |
| **S0d6b4** combustion consumers | `CombustionSystem`, `SimulationEngine` gates | `phase3_o2_inventory_authority_enabled`, OFF | still legacy | HRR, extinction, re-ignition, backdraft and LOI deltas reported honestly | baseline movement explained physically, never tuned | flag off | S0d6b5 | FED |
| **S0d6b5** FED and tenability | `ThermalSystem` FED path | same flag | still legacy | FED delta per case, life safety reviewed explicitly | FED change justified on physics | flag off | S0d6b6 | HVAC |
| **S0d6b6** HVAC boundary | contract only; HVAC still not implemented | none | none | contract tests | HVAC writes expressed as exterior kg requests, still deferred | n/a | S0d6b7 | HVAC itself |
| **S0d6b7** promotion | remove legacy states | flag removed | **inventory authoritative** | full suites, guardrails, baselines re-derived | authority granted explicitly | revert the commit | the H3.2-S source vector | H3.2b, H3.3 |

Every phase is default OFF, byte-identical when off, and independently
revertible. **No phase may start before its predecessor's STOP gate.**

---

## 8. Risks

| Risk | Severity | Mitigation |
|---|---|---|
| Baselines move because the meaning of `o2` changes | **high** | expected and correct; must be explained physically and never tuned to fit CFAST |
| An empty zone leaves a derived fraction undefined | high | return `unknown`, never `0.0` or `0.209`; fail closed |
| `upper_gas_kg` is itself not conserved by the engine today | **high** | S0d6b2 must measure this before trusting it as a denominator; if it fails, A is blocked on H3.2b |
| The two parcel pools are merged incorrectly | high | S0d6b3 migrates them last, with a conservation test across the merge |
| FED changes on a life-safety metric | high | isolated in S0d6b5 with its own review |
| The seven `fire_o2_mode` collapse into views and change behaviour | medium | S0d6b4 reports each mode separately |
| Migration stalls half-done, leaving three authorities instead of two | medium | per-writer flags plus a gate forbidding a partial default-ON state |
| Effort underestimated | medium | 23 writers and 12 consumer classes; assume several sessions per phase |

The third risk can invalidate the recommendation. **A depends on `upper_gas_kg`
and `lower_gas_kg` being conserved and non-degenerate.** The runtime authority
plan already records that mass and energy have their own ownership problems and
that `project_room_state` reconstructs rather than projects. If S0d6b2 shows the
zone gas masses are themselves unreliable, A cannot proceed until H3.2b fixes
them, and that dependency must be stated rather than worked around.

---

## 9. Legacy states and flags to retire, eventually

Not now. Listed so the plan has an explicit end state.

| Item | Site | Why |
|---|---|---|
| `room.upper_o2_mass_tracked` | `RoomModel.gd:53` | superseded by `mO2_upper` |
| `fire_o2_mass_tracking_enabled` | `OES:124` | its only purpose was the tracker above |
| `room.o2_zone_sync_kg_step/_total` | `RoomModel.gd:206-207` | nothing to re-synchronise once there is one inventory |
| `upper_o2_mass_kg()`, `lower_o2_mass_kg()` | `RoomModel.gd:375-381` | already dead code, zero call sites |
| `minf(room.o2, room.o2_upper)` | `CombustionSystem.gd:1505` | mixing inventories stops being meaningful |
| `minf(room.o2, room.o2_lower)` | `SimulationEngine.gd:4681` | idem, inside a reported metric |
| the four blend sites | `ThermalSystem.gd:3409/3426/3637/3658` | repairs with no donor |
| the fifth blend site | `OxygenExchangeSystem.gd:666` | idem |
| `phase2h_o2_doorway_two_zone_enabled`, `phase2b_canonical_combustion_enabled` | `OES:49,119` | review once zonal mass is authoritative |
| `o2_nominal` as a `const` shadowing `fire_o2_nominal` | `SimulationEngine.gd:64` versus `:217` | two different quantities exported under one key |

---

## 10. Decisive questions, answered

**1. Can the bulk be derived exactly from the zonal masses?**
Yes, by summation, and that is the core reason to prefer A. The converse is
false: S0d6a measured the bulk outside its zones' bracket on 74.67 % of rows in
both directions, so no partition rule is recoverable from a stored total.

**2. Which formula matches the real semantics of `o2`?**
Today, none that is physical: `o2` is a fraction against `volume * 1.2`. Under A
it becomes `mO2_total / (upper_gas_kg + lower_gas_kg)`, a true mass fraction.
This **changes the meaning of the field** and is therefore a physics decision.

> **[SUPERSEDED 2026-08-19 — see section 12.4]** Wrong target. `o2` must keep its
> **molar/volumetric** meaning, because FED, LOI, ILV, UI and CSV all consume
> vol%. The corrected view is `xO2 = (mO2/mgas) * Mmix / MO2`, which reproduces
> `0.20946` in ambient dry air rather than `0.2314`.

**3. Store O2 mass, or a fraction plus a gas mass?**
**Store mass.** With a stored fraction, any change to the zone gas mass for
non-O2 reasons — hot gas advecting through a doorway changes `upper_gas_kg`
without moving any oxygen — silently rewrites the O2 inventory. Storing mass
makes advection an explicit, auditable transfer.

**4. Who owns O2 in flight?**
The parcel, exclusively, and there must be exactly one pool. Today there are two,
`OES:1239` and `GES:2157`, with different delay models, and only OES reserves
in-flight O2 against the destination.

**5. How is projection prevented from changing O2?**
Projection recomputes **derived views only**. Stored masses are written solely by
the single commit. This is the O2 analogue of the `project_room_state` problem
the runtime authority plan already records for energy.

**6. Should CombustionSystem request kilograms?**
Yes. It should request a kg from a named zone and receive an accepted kg. Today
it mutates fractions indirectly and its consumption is capped four different ways
against three different bases.

**7. How are the seven `fire_o2_mode` preserved?**
They become **view selectors over one conserved inventory** rather than choices
between inventories. The selection logic at `CombustionSystem.gd:2715-2765` is
kept; only the quantity it reads changes.

**8. Which legacy modes become obsolete?**
See §9. The blends and the cross-inventory `minf` reads lose their purpose
entirely; `fire_o2_mass_tracking_enabled` and `upper_o2_mass_tracked` are
superseded.

**9. Can the bulk remain purely a derived field?**
Yes, and it should. Keeping `room.o2` as a read-only derived property lets the
representation change without forcing every consumer to change in the same phase.

**10. What is the minimum architecture that closes H3.2-S honestly?**
Stored zonal O2 masses, a single atomic commit, one parcel pool, explicit
exterior accounting, and derived views for every consumer. Anything less leaves
either two authorities or an invented partition rule.

---

## 11. What this phase did not do

No implementation. No file under `sim/core` touched. No physics, no flag, no
campaign, no HVAC work, no integrator, no `minf` reconciliation, no per-scenario
adjustment, and no expected value, tolerance, report, CTRL or VALID_GAP modified.
H3.2-S, H3.2b and H3.3 all remain open and no runtime authority was granted.

---

# 12. S0d6b0.1 — molar/mass contract correction (2026-08-19)

This section supersedes any statement in sections 1-11 that treats molar and mass
fractions as interchangeable. Nothing was implemented; `sim/`, `tests/`,
`scripts/`, `tools/` and the reports remain untouched.

## 12.1 `o2 = 0.209` is a molar/volumetric fraction — confirmed by consumers

| Consumer | Site | Uses | Therefore requires |
|---|---|---|---|
| FED hypoxia | `ThermalSystem.gd:4576, 4649` | `o2_pct = zone_fraction * 100`, deficit against `20.9` | **vol%** — the Purser / ISO 13571 hypoxia model is defined on volume percent |
| LOI ignition | `CombustionSystem.gd:2661, 3488` | `room.o2 < obj.loi_fraction` | **vol%** — Limiting Oxygen Index is defined as volume percent |
| Backdraft, pool burn, latent floor, re-ignition | `CombustionSystem.gd:1725/1803/1827/3130/3144`, `SimulationEngine.gd:3975` | compared against `0.13`, `0.122` | vol%, by convention with the above |
| CO oxidation gate | `SimulationEngine.gd:3696` | `room.o2 < co_oxidation_o2_min = 0.05` | vol% |
| CSV / UI / ILV | `SimulationStateBuilder.gd:244-246`, `SimulationLogWriter` | logs the raw fractions | vol%, as read by operators |
| **Thornton consumption** | `SimulationEngine.gd:246`, `o2_consumption_kg_per_MJ = 0.076` | `1/13.1` MJ per kg O2 | **kilograms** |

The literal `20.9` in the FED code is decisive: 20.9 is the **volume** percent of
O2 in dry air. The mass percent is 23.14. No consumer wants a mass fraction; the
only quantity that is natively a mass is the Thornton consumption.

## 12.2 Is the composition sufficient for a per-zone mixture molar mass?

**No.** `RoomModel` tracks masses for CO, CO2, HCN, HCl, acrolein, formaldehyde
and soot, plus a molar `co2_upper`. But **combustion water vapour is not tracked
at all**: the only water state is `room.steam_kg` (`RoomModel.gd:344`), which
`SimulationEngine.gd:3468` fills solely from suppression spray evaporation. Soot
is condensed phase and must not enter a gas-phase molar mass.

A rigorous dynamic mixture molar mass is therefore unavailable: H2O is the second
largest combustion product by mole count, and omitting it would bias the result
systematically, in the direction that most affects hot layers.

## 12.3 The `2.87x` figure, corrected

The earlier claim conflated two independent errors. They must be separated.

| # | Error | Magnitude | Direction |
|---|---|---|---|
| 1 | **Gas-mass base**: O2 fractions multiplied by `V * 1.2` instead of `V * 1.2 * T_amb/T` | up to **2.874x** at the hottest observed layer (`T_amb/T = 0.348`) | overstates gas mass when hot |
| 2 | **Molar-vs-mass**: `xO2` used where `YO2` belongs, missing `MO2/Mmix = 31.999/28.9647 = 1.10476` | constant **0.9050** | always understates O2 mass |

Net error on the O2 mass the engine believes it holds:

```
mO2_engine / mO2_true = (Mmix / MO2) * (T / T_ambient) = 0.9050 * (T / T_ambient)
```

with a crossover at `T / T_ambient = 1.1048`, i.e. **T = 50.7 C**. Below that the
engine **understates** physical O2 mass; above it, overstates.

Measured over the same 20 059 room-steps:

| | p05 | p50 | p95 | max |
|---|---:|---:|---:|---:|
| net factor `mO2_engine / mO2_true` | 0.905 | **0.907** | 1.809 | **2.598** |

- **79.80 % of rows (16 008 / 20 059) the engine UNDERSTATES physical O2 mass**,
  by 9.48 % at ambient.
- Worst overstatement is **2.60x**, not 2.87x.
- `2.874x` remains correct as the **gas-mass** inflation, which is what section
  1.2 actually measured. It was mislabelled as an O2-mass inflation.

**Correction to the S0d6 carve-out, restated precisely.** The `-208.47 kg` of the
`oes_combustion_upper_sink` path are wrong by `0.9050 * (T/T_ambient)` — too small
by 9.5 % in a cool layer, too large by at most 2.60x in the hottest.

## 12.4 The corrected contract

**Stored, authoritative** — per room, per zone:

```
mO2_upper [kg]      mO2_lower [kg]
```

**Derived, read-only:**

```
mO2_total = mO2_upper + mO2_lower                      (exact, by construction)

YO2_zone  = mO2_zone / mgas_zone                       (mass fraction)
xO2_zone  = YO2_zone * Mmix / MO2                      (molar / volumetric)

             (mO2_upper + mO2_lower) / MO2
xO2_bulk  =  --------------------------------------    (mole-weighted)
             (mgas_upper + mgas_lower) / Mmix
```

with `MO2 = 31.999 g/mol` and `Mmix` per option A below. Under a common `Mmix`
the bulk molar fraction reduces to `Y_bulk * Mmix / MO2`; **if `Mmix` is ever
made per-zone, the mole-weighted form above is mandatory** and the mass-weighted
shortcut becomes invalid.

`room.o2`, `room.o2_upper` and `room.o2_lower` keep their present meaning —
**molar / volumetric** — and become derived views. No consumer changes units.

### Choosing `Mmix`

| | Option | `Mmix` | Error vs a true mixture | Verdict |
|---|---|---|---|---|
| **A** | fixed dry-air molar mass | `28.9647 g/mol` | `-3.15 %` (H2O-rich flaming) to `+5.00 %` (CO2-rich smouldering); typically under `1 %` | **recommended** |
| B | dynamic mixture, tracked species with N2 by difference | computed | **unbounded**: H2O is untracked and is the product that most shifts `Mmix` | blocked until H2O is tracked |
| C | store total moles per zone as an extra state | exact | zero, but adds a second conserved quantity with its own transport, sources and sinks | deferred; revisit only if A proves insufficient |

Quantified sensitivity, which is why A is adequate:

| Composition | `Mmix` | vs dry air |
|---|---:|---:|
| dry air | 28.848 | −0.40 % |
| vitiated, CO2 and H2O balanced (10/10/10) | 29.012 | +0.16 % |
| heavily vitiated, balanced (5/15/15) | 29.112 | +0.51 % |
| smouldering, CO2-rich and dry | 30.412 | **+5.00 %** |
| flaming, H2O-rich, CH4-like 2:1 | 28.052 | **−3.15 %** |

CO2 (44.01) and H2O (18.02) sit on opposite sides of N2 (28.01), so in flaming
combustion they largely cancel. The residual few percent is far smaller than the
9.5 %-to-160 % errors this contract removes, and it is a **named, bounded**
approximation rather than a hidden one.

### Round trip

> **CORRECTED 2026-08-19 (PASO 0).** An earlier draft of this subsection claimed
> the round trip was "exact to floating point" with "a bound of 0". That was
> wrong and is replaced by the measured statement below. **Bit-identity must
> never be assumed.**

Under option A the round trip `xO2 -> mO2 -> xO2` uses the same constants in both
directions:

```
store:  mO2  = xO2 * (MO2/Mmix) * mgas
derive: xO2' = (mO2 / mgas) * (Mmix/MO2)
```

- **Mathematical identity: exact.** The constants cancel algebraically, and the
  result is independent of temperature and composition.
- **Numerical behaviour: not exact, and not bit-identical.** Four rounded
  operations sit between `xO2` and `xO2'`. Measured over 400 000 samples spanning
  `xO2` in `[1e-6, 0.2095]` and `mgas` in `[1e-4, 5e3] kg`:

| Metric | Value |
|---|---|
| bit-identical round trips | **62.18 %** |
| **not** bit-identical | **37.82 %** |
| worst relative error | **4.416e-16** (about `2 * eps`) |
| worst error in ULP | **3** |
| machine epsilon | 2.220e-16 |

**Declared bound: `|xO2' - xO2| / xO2 <= 1e-15`, and at most 4 ULP.** Any test
must assert that tolerance, never equality. Asserting bit-identity would fail on
roughly two of every five values.

The physical `Mmix` approximation is a **separate** error with a bound of about
`5 %`. The two must never be conflated in a test: one is `1e-15` relative, the
other `5e-2`.

A near-zero denominator is a distinct failure mode and is not covered by this
bound: `mgas -> 0` degrades and then produces `nan`, which is why invariant 15
requires `unknown` rather than a number.

### Initialisation without moving FED or LOI

```
mO2_zone(t=0) = xO2_ambient * (MO2 / Mmix) * mgas_zone
              = 0.20946 * 1.10476 * mgas_zone
              = 0.23140 * mgas_zone
```

Deriving back gives `xO2 = 0.20946` exactly, so FED, LOI, ILV, the CSV and the UI
see the same number they see today at `t = 0`. **Seeding `mO2 = 0.209 * mgas`
would be exactly the bug this section exists to prevent**: it would start every
scenario 9.5 % lean and shift FED and LOI from the first step.

## 12.5 Updated invariants

Replacing the section 5 list where they differ.

| # | Invariant | Note |
|---|---|---|
| 1 | `mO2_total = mO2_upper + mO2_lower` | unchanged |
| 2 | no negative O2 mass | unchanged |
| 3 | **`xO2 = 0.209` is never interpreted as `YO2 = 0.209`** | new; the central correction |
| 4 | **in ambient dry air, `xO2 = 0.20946` implies `YO2 = 0.23140`** | new; seeding test |
| 5 | **round trip `xO2 -> mO2 -> xO2` closes to a declared numerical bound under a common `Mmix`** | new; exact as an identity, but **not** bit-identical: measured worst 4.416e-16 relative and 3 ULP, so the declared bound is `1e-15` relative / 4 ULP |
| 6 | **FED, LOI, ILV, UI and CSV keep receiving molar / volumetric fraction** | new; no consumer changes units |
| 7 | **transport of gas mass with no explicit O2 never creates or destroys `mO2`** | new; consequence of storing mass |
| 8 | **changing temperature alone never changes `mO2`** | new; the property the present design lacks |
| 9 | extraction bounded by the donor zone inventory | unchanged |
| 10 | interior transport conserves building O2; exterior exit accounted | unchanged |
| 11 | combustion consumes the inventory it reads; FED reads a view of it | unchanged |
| 12 | numerical reconciliation never silently creates or destroys O2 | unchanged |
| 13 | parcels never double-count; one pool | unchanged |
| 14 | one authority per timestep | unchanged |
| 15 | **a zone with no gas mass returns `unknown`, never `0.0` and never `0.209`** | strengthened |
| 16 | **no conversion depends on a per-scenario knob**; `Mmix` is a physical constant, not a tunable | new |
| 17 | **every molar-mass approximation is named and quantified in the export** | new |

Invariants 7 and 8 are the two properties the present engine most clearly lacks,
and they are exactly what storing kilograms buys.

## 12.6 Revised plan — S0d6b1 is reordered

The contract in 12.4 divides by `mgas_zone`. If `upper_gas_kg` and `lower_gas_kg`
are not themselves conserved and non-degenerate, every derived `xO2` is
meaningless no matter how carefully `mO2` is stored. The original plan placed
that audit at S0d6b2, **after** the primitive. That order is wrong.

| Phase | What | Status |
|---|---|---|
| S0d6b0 | authority design | done; partly superseded by this section |
| **S0d6b0.1** | **molar/mass contract, this section** | **done** |
| **S0d6b0.2** | **zonal gas-mass reliability audit, read-only** | **NEW, now a prerequisite of S0d6b1** |
| S0d6b1 | pure `Phase3O2Inventory` primitive, no call sites | **blocked on S0d6b0.2** |
| S0d6b2 | passive shadow from a pre-step snapshot | unchanged |
| S0d6b3 | writer migration, per-writer flags | unchanged |
| S0d6b4 | combustion consumers | unchanged |
| S0d6b5 | FED and tenability | unchanged |
| S0d6b6 | HVAC boundary contract, HVAC still deferred | unchanged |
| S0d6b7 | promotion, legacy removal | unchanged |

**S0d6b0.2 must answer**, read-only and without a new campaign where possible:
is `upper_gas_kg + lower_gas_kg` conserved under interior transport; does
`project_room_state` rewrite it; how often does `upper_gas_kg` reach zero or near
zero; and does it agree with `volume * rho(T)`. If it fails, S0d6b1 defers to
H3.2b.

## 12.7 Decision

**NO-GO for S0d6b1 as previously scheduled. GO for S0d6b0.2.**

The composition question is **resolved**: option A gives a named, bounded molar
mass and makes storing kilograms and exposing 20.9 %vol compatible to a declared
numerical bound of `1e-15` relative (4 ULP) — an exact algebraic identity, but
**not** bit-identity. That half of the success criterion is met.

The second half — *explicitly verifiable* — is **not** met, because the
denominator `mgas_zone` has never been audited. Storing kilograms against an
unverified gas mass would move the unowned error from the numerator to the
denominator without removing it.

Unblocking condition, in one sentence: **S0d6b1 proceeds once S0d6b0.2 shows the
zonal gas masses are conserved, non-degenerate and consistent with the engine's
own gas law, or once the primitive is redefined to carry its own gas-mass
reference.**
