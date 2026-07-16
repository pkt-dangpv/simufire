# Phase 3+ F3.0k.1g vertical transport audit

Date: 2026-07-16

## Decision

**NO-GO for migrating the legacy vertical net/directed helpers into one
atomic gas/enthalpy/O2/species bundle. No motor code was changed.**

The active two-zone vertical path does not need a new vertical producer: when
its shared opening flow state is active, it enters
`_apply_two_zone_opening_species_exchange()` and reuses the
`doorway_species_direct` atomic contract delivered by F3.0k.1d.

The separate `vertical_species_net_exchange` and
`vertical_species_directed_exchange` helpers are compatibility fallbacks.
They do not share one physical carrier with ThermalSystem or
OxygenExchangeSystem and cannot be promoted by manufacturing missing routes.

## Producer map

| Producer | Trigger | Legacy mutation | Atomic status |
|---|---|---|---|
| GES two-zone opening router | Shared `flow_state.active` | Zonal species deltas from `bernoulli_upper/lower_kg_s` | Already covered by F3.0k.1d |
| GES vertical net fallback | Vertical opening and temperature delta below 1 K | Net smoke/CO/CO2/HCN concentration diffusion | Species-only exact |
| GES vertical directed fallback | Vertical opening and lower-floor upper gas at least 1 K hotter | Upward smoke/toxic species | Species-only exact |
| GES vertical O2 fallback | Same directed branch, downward return | Bulk O2 delta only | Not dimensionally compatible |
| Thermal main opening transfer | Shared cached opening state | Upper gas, energy and contaminants | Separate doorway owner |
| Thermal stairwell heat bridge | Opt-in stairwell control | Energy only; may lift target lower mass first | Separate calibration mechanism |
| OES interior active flow | Shared cached opening state | Bulk/zonal O2 and tracer CO2 | Separate transport model |

## Why no atomic legacy bundle exists

### 1. Different flow solvers

The legacy GES vertical fallback recomputes:

```text
q_up = Cd * area * sqrt(2 * g * floor_height * delta_T / T_high)
```

It selects lower and upper rooms from floor elevation and only permits
directed transport when the lower floor is hotter.

ThermalSystem uses the cached opening state, selects hot and cold rooms from
temperature/pressure and applies additional engagement, gas inventory, energy
and stairwell temperature caps. OES consumes the same cache but applies its
own mass caps, background exchange and optional delay.

These values are not different quantities carried by one event. They are
different models of the same opening.

### 2. Missing gas and enthalpy writes

`_apply_species_net_exchange()` and
`_apply_directed_species_exchange()` mutate species delta dictionaries. They
do not debit or credit upper/lower gas mass or sensible energy.

Binding their species to the separately calculated Thermal mass would make
the shadow describe a transaction that legacy never applied atomically.

### 3. O2 is not the upward species payload

The directed fallback moves toxic species upward. It does not move the source
O2 with that gas. A separate downward term is calculated:

```text
o2_net = (o2_upper_floor - o2_lower_floor)
         * mass_down / upper_room_air_mass
o2_delta += o2_net * mass_down
```

The second multiplication makes the result proportional to
`mass_down^2 / room_air_mass`. It is an O2 mixing correction, not the O2 mass
contained in the downward gas stream. It therefore cannot share the upward
species accepted fraction.

### 4. Net and directed paths are alternatives over time

When the shared two-zone flow state is inactive,
`_apply_two_zone_opening_species_exchange()` returns false and the same
opening falls through to the legacy vertical helper. A run can therefore
accumulate:

- canonical doorway events while the shared flow is active;
- vertical net diffusion during weak gradients; and
- vertical directed fallback during another part of the transient.

They must remain separate identities. Combining their cumulative totals would
double count or erase the branch transition.

## Runtime evidence

All new runs used Godot 4.6.3 console, headless and sequential. Scratch output
lives under `runs/phase3_f30k1g`. No official report remains modified.

| Control | Final time | Doorway CO2 | Vertical net CO2 | Vertical directed CO2 | Thermal background | Result |
|---|---:|---:|---:|---:|---:|---|
| Stairwell, two-zone router enabled | 90.1 s | 0.00011723 kg | 0.00001609 kg | 0 | 0.00062975 kg | Both canonical and fallback identities visible |
| Stairwell, legacy router forced | 90.1 s | 0 | 0.00001905 kg | 0 | 0.00061613 kg | Legacy net branch isolated |
| Stairwell, no fire | 60.0 s | 0 | 0 | 0 | 0 | No flux fabricated |
| Horizontal corridor control | 60.0 s | active | 0 | 0 | active | Vertical metrics remain zero |

The existing valid 350.1 s F3.0k stairwell control reaches the directed
transient with the same vertical motor code:

| Metric | Final value |
|---|---:|
| Doorway CO2 request | 0.01939022 kg |
| Vertical net CO2 | 0.00468663 kg |
| Vertical directed CO2 | 1.12110743 kg |
| Vertical directed CO | 0.10497457 kg |
| Thermal doorway gas carrier | 6.18911628 kg |
| Thermal interior-background gas carrier | 1.23560450 kg |
| Bulk O2 net transport | 4.47029742 kg |

Directed species first appear at about 220 s. At that time stairwell room 2
is 49.0 C and room 6 is 29.8 C. The cumulative Thermal doorway carrier is
already 0.4514 kg while vertical directed CO2 is 0.00024562 kg. These are not
one payload with one accepted fraction.

All audited runs completed to the requested simulation time. No Godot crash,
popup, hang, incomplete CSV or unknown connection identity was observed.

## Contract disposition

| Family | Exact contract retained | Missing ownership | Decision |
|---|---|---|---|
| Active two-zone vertical opening | F3.0k.1d doorway atomic bundle | Remaining Thermal/OES overlap belongs to later authority work | Reuse existing owner |
| Vertical net fallback | CO/CO2/HCN species debit-credit | Gas, enthalpy and physical O2 carrier | Keep species-only |
| Vertical directed fallback | Upward smoke/toxic species | Matching gas, enthalpy and O2 | Keep species-only |
| Stairwell heat bridge | Energy calibration term | Species/O2 carrier by design | Keep separate |

## Next step

Proceed to **F3.1 authoritative sealed mode and the zero-O2 extinction
regression**. A sealed single-room control avoids every unresolved opening,
exterior and HVAC producer, making it the correct first authority boundary.

F3.1 must not authorize flaming when the selected combustion O2 source is at
or below the extinction threshold. Authority remains default OFF and must
fall back immediately if legacy and canonical combustion ownership diverge.

After F3.1:

1. F3.2 owns exterior pressure/leakage for Group A.
2. F3.3 resolves interior-opening authority for Group C.
3. F3.4 completes remaining non-HVAC species, suppression and FED.
4. HVAC remains deferred to F3.5.
