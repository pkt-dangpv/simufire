# Calibration Sources

This file records source-derived calibration targets used by the validation cases.

## UL/FSRI and NIST residential fire behavior

- Governors Island Experiments, FSRI/NIST/FDNY:
  https://fsri.org/research/governors-island-experiments
  - Ventilating a ventilation-limited fire can rapidly increase fire hazard and can lead to flashover.
  - Interrupting inlet/exhaust flow paths limits fire growth.
  - Exterior water applied into the fire compartment improves conditions throughout the structure.

- `docs/literature/NIST/NS_FS_Article_Interrupting_Flow_Path1.pdf`
  - Modern ventilation-limited fires can reach flashover about 2 min after tactical ventilation, versus about 8 min for legacy furnishings.
  - In a Governors Island flow-path experiment, the front door temperature rose from about 75 F to over 550 F in less than 90 s after ventilation.
  - Closing a bedroom door reversed severe gas conditions in about 2 min: O2 rose from about 8% to 16%, CO2 dropped from about 9% to 4%.
  - Closing the front door after basement flashover reduced room temperatures by up to about 70%.

- `docs/literature/NIST/UL-FSRI-2010-DHS-Report_Comp.pdf`
  - Modern synthetic fuel loads produce faster, less forgiving ventilation response.
  - Door control delays flashover by minutes by limiting air supply.
  - A 4 ft by 8 ft vertical vent over a ventilation-limited fire did not improve conditions by itself.
  - Applying water quickly to the fire compartment improved conditions and did not push fire.

- `docs/literature/NIST/UL-Study-Binder-TransitionalFireAttack.pdf`
  - 25 gal applied into a second-floor fire room reduced fire-room temperature from about 1792 F to 632 F in 10 s.
  - The adjacent hallway dropped from about 273 F to 104 F in the same 10 s interval.

- `docs/literature/NIST/nbstechnicalnote1629.pdf`
  - Wind-driven flow paths rapidly force hot gases from the fire apartment into corridors/stairs.
  - Wind control, exterior water, and coordinated tactics reduce the thermal hazard.

## Supplemental model references

- RISE Research Institutes of Sweden, CFD modeling and fluid mechanics:
  https://www.ri.se/en/fire-safety/expertise/cfd-modeling-and-fluid-mechanics
  - RISE highlights full-scale and small-scale fire-test databases for model calibration.
  - It identifies fire growth definition, material thermal properties, smoke/fire spread, and toxic gas production as critical modeling inputs.

- Brandweeracademie/IFV smoke propagation lessons from Oudewater residential-building field experiments:
  https://www.brandveilig.com/nieuws/brandweeracademie-publiceert-lessen-onderzoek-naar-rookverspreiding-67682
  - Synthetic foam furniture can affect other dwellings through smoke and CO spread.
  - Door closing plus limiting synthetic fuel or active suppression is identified as highly effective.

- TNO, Dutch approach to large-compartment ASET/RSET modeling:
  https://repository.tno.nl/SingleDoc?docId=16052
  - Zone models are extended for smoke cooling on ceilings/walls and unstratified smoke spread in large spaces.

- NIST TN 1603, full-scale underventilated ISO 9705 experiments:
  https://www.nist.gov/publications/experimental-study-effects-fuel-type-fuel-distribribution-and-vent-size-full-scale
  - Fuel type, fuel distribution, and vent size are explicit variables in ventilation-limited experiments.
  - Fuels include natural gas, liquid fuels, polypropylene, Nylon, and polystyrene; measured outputs include HRR, soot, CO, CO2, O2, hydrocarbons, gas temperatures, and heat flux.

## Simufire calibration hooks

- `suppression_events` in validation JSON apply water by room, duration, flow and effectiveness.
- `suppression_heat_absorption_kj_per_l`, `suppression_hrr_decay_per_l`, and related fractions model short exterior/interior water knockdown.
- Door/window `opening_events` remain the calibration hook for flow-path and ventilation timing.
- Object-level `smoke_yield_kg_per_MJ` and `co_yield_kg_per_MJ` are now used during combustion.
- `hot_gas_species_carry_fraction` and related thermal-system settings couple CO/CO2 transport to hot-gas parcels crossing openings.
- `thermal_smoke_bridge_*` settings bridge visible smoke-layer spill with the hotter two-zone layer. Defaults are conservative; Ghanekar uses stronger case overrides for the ranch hallway flow path.
- The Ghanekar bedroom case treats the near/far hallway split as a computational subdivision, so the internal near/far opening uses a wide virtual boundary rather than a normal door.
