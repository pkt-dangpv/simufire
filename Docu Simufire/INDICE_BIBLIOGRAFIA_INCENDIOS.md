# Indice de bibliografia sobre incendios en edificaciones

## Objetivo

Construir una biblioteca tecnica abierta y trazable para calibrar `Simufire` con estudios publicados y casos a escala real.

## Estado de recoleccion - 2026-04-19

- Biblioteca tecnica organizada en `FSRI_ULRI`, `NIST`, `Journals_OpenAccess` y `Reviews_and_Models`.
- Inventario reproducible guardado en `Docu Simufire/download_manifest_fire_literature.json`.
- Resultado actual: `30` documentos curados disponibles localmente en subcarpetas tematicas, mas los documentos raiz ya existentes en `Docu Simufire`.
- Nota operativa: los articulos abiertos sobre `HVAC` y `gas burner fires` requirieron captura a PDF desde navegador headless por protecciones anti-bot del sitio. Siguen siendo articulos abiertos, pero el binario local no proviene del boton oficial de descarga.
- Nota de trazabilidad: no encontre un PDF publico directo para `Measurement of Heat Transfer and Fire Damage Patterns on Walls for Fire Model Validation`; en su lugar se incorporo el reporte publico relacionado `Evaluation of Heat Flux Profiles Through Walls in Support of Fire Model Validation`.
- Pendientes menores: las Part I y Part II de `Search and Rescue Tactics in Single-Story Single-Family Homes` siguen catalogadas pero no localizadas todavia con URL publica estable.

## Como usar esta carpeta

- `FSRI_ULRI`: experimentos residenciales a escala real, tacticas, tenabilidad y ventilacion.
- `NIST`: modelos de compartimento, transporte de humo, especies y validacion.
- `Journals_OpenAccess`: articulos revisados por pares con PDF abierto.
- `Reviews_and_Models`: guias, revisiones y documentos de soporte para parametrizacion.

## Objetivos de calibracion para Simufire

- Tiempo a flashover y transicion a incendio limitado por ventilacion.
- Transporte de humo y gases desde recinto origen a pasillos y recintos remotos.
- Efecto de puertas interiores, puerta principal, ventanas y HVAC.
- Curvas de `O2`, `CO2`, `CO`, `H2O`, temperatura y tenabilidad/FED.
- Diferencias entre compartimentos cerrados, parcialmente ventilados y ventilados.

## Ya disponible en esta carpeta

| Estado | Documento | Ruta local |
| --- | --- | --- |
| disponible | Evolution of combustion gas concentrations in full-scale residential fire.pdf | `Docu Simufire/Evolution of combustion gas concentrations in full-scale residential fire.pdf` |
| disponible | NIST.SP.1018e6.pdf | `Docu Simufire/NIST.SP.1018e6.pdf` |
| disponible | NIST.TN.1889v1.pdf | `Docu Simufire/NIST.TN.1889v1.pdf` |
| disponible | nistir7080.pdf | `Docu Simufire/nistir7080.pdf` |

## Catalogo priorizado

| Pri | Fuente | Documento | Ano | Tema clave | URL fuente | Destino previsto | Estado |
| --- | --- | --- | --- | --- | --- | --- | --- |
| P1 | FSRI | Occupant Tenability in Single Family Homes Part I | 2017 | Tenabilidad, puertas interiores, fuego residencial | https://fsri.org/sites/default/files/2021-07/Occupant_Tenability_in_Single_Family_Homes_Part_I.pdf | `Docu Simufire/FSRI_ULRI/Occupant_Tenability_Part_I_2017.pdf` | pendiente-descarga |
| P1 | FSRI | Occupant Tenability in Single Family Homes Part II | 2017 | Tenabilidad, door control, ventilacion vertical, agua | https://fsri.org/sites/default/files/2021-07/Occupant_Tenability_in_Single_Family_Homes_Part_II.pdf | `Docu Simufire/FSRI_ULRI/Occupant_Tenability_Part_II_2017.pdf` | pendiente-descarga |
| P1 | Springer | Effect of Firefighting Intervention on Occupant Tenability during a Residential Fire | 2019 | FED, tacticas, exposicion ocupantes | https://link.springer.com/article/10.1007/s10694-019-00864-2 | `Docu Simufire/Journals_OpenAccess/Effect_of_Firefighting_Intervention_on_Occupant_Tenability_2019.pdf` | pendiente-descarga |
| P1 | FSRI | Evolution of Combustion Gas Concentrations in Full-Scale Residential Fire Environments | 2026 | Gases toxicos, pasillo, IDLH, full-scale | https://fsri.org/resource/evolution-combustion-gas-concentrations-full-scale-residential-fire-environments | `Docu Simufire/Evolution of combustion gas concentrations in full-scale residential fire.pdf` | disponible |
| P1 | FSRI | Analysis of Search and Rescue Tactics in Single-Story Single-Family Homes Part I: Bedroom Fires | 2025 repo / 2022 study | Bedroom fires, busqueda y rescate, gases | https://ulri.figshare.com/categories/Human_resources_and_industrial_relations/32147 | `Docu Simufire/FSRI_ULRI/Search_and_Rescue_Part_I_Bedroom_Fires.pdf` | pendiente-localizacion |
| P1 | FSRI | Analysis of Search and Rescue Tactics in Single-Story Single-Family Homes Part II: Kitchen and Living Room Fires | 2025 repo / 2022 study | Cocina, salon, busqueda y rescate, flujo | https://ulri.figshare.com/categories/Human_resources_and_industrial_relations/32147 | `Docu Simufire/FSRI_ULRI/Search_and_Rescue_Part_II_Kitchen_Living_Room.pdf` | pendiente-localizacion |
| P1 | FSRI | Analysis of Search and Rescue Tactics in Single-Story Single-Family Homes Part III: Tactical Considerations | 2025 repo | Sintesis tactica basada en datos | https://ulri.figshare.com/articles/report/Analysis_of_Search_and_Rescue_Tactics_in_Single-Story_Single-Family_Homes_Part_III_Tactical_Considerations/28075001 | `Docu Simufire/FSRI_ULRI/Search_and_Rescue_Part_III_Tactical_Considerations.pdf` | pendiente-descarga |
| P1 | FSRI | Analysis of the Coordination of Suppression and Ventilation in Single-Family Homes | 2020 | Coordinacion ventilacion-supresion | https://fsri.org/resource/analysis-coordination-suppression-and-ventilation-single-family-homes | `Docu Simufire/FSRI_ULRI/Coordination_Suppression_Ventilation_Single_Family_2020.pdf` | pendiente-descarga |
| P1 | FSRI | Analysis of the Coordination of Suppression and Ventilation in Multi-Family Dwellings | 2020 | Apartamentos, escalera comun, humo y gases | https://fsri.org/resource/analysis-coordination-suppression-and-ventilation-multi-family-dwellings | `Docu Simufire/FSRI_ULRI/Coordination_Suppression_Ventilation_Multi_Family_2020.pdf` | pendiente-descarga |
| P1 | FSRI | Impact of Ventilation on Fire Behavior in Legacy and Contemporary Residential Construction | 2010 / 2025 repo | Ventilacion, legado vs contemporaneo, flashover | https://ulri.figshare.com/articles/report/Impact_of_Ventilation_on_Fire_Behavior_in_Legacy_and_Contemporary_Residential_Construction/28087586 | `Docu Simufire/FSRI_ULRI/Impact_of_Ventilation_Legacy_and_Contemporary_Residential_Construction.pdf` | pendiente-descarga |
| P1 | FSRI | Study of the Effectiveness of Fire Service Positive Pressure Ventilation During Fire Attack in Single Family Homes Incorporating Modern Construction Practices | 2016 | PPV/PPA, dinamica de incendio, ventilacion | https://fsri.org/sites/default/files/2021-07/Positive_Pressure_Ventilation_Report_Website.pdf | `Docu Simufire/FSRI_ULRI/Positive_Pressure_Ventilation_Report_2016.pdf` | pendiente-descarga |
| P1 | FSRI | Understanding and Fighting Basement Fires | 2025 repo | Incendios de sotano, ventilacion limitada | https://ulri.figshare.com/articles/report/Understanding_and_Fighting_Basement_Fires/28050134 | `Docu Simufire/FSRI_ULRI/Understanding_and_Fighting_Basement_Fires.pdf` | pendiente-descarga |
| P1 | NIST | Modeling Smoke Movement Through Compartmented Structures (NISTIR 4872) | 1992 | Modelo multicompartment, humo, gases toxicos | https://doi.org/10.6028/NIST.IR.4872 | `Docu Simufire/NIST/NISTIR_4872_Modeling_Smoke_Movement_Through_Compartmented_Structures.pdf` | pendiente-descarga |
| P1 | NIST | Improvement in Predicting Smoke Movement in Compartmented Structures | 1993 | Mejoras CFAST, transporte de humo | https://tsapps.nist.gov/publication/get_pdf.cfm?pub_id=912721 | `Docu Simufire/NIST/Improvement_in_Predicting_Smoke_Movement_1993.pdf` | pendiente-descarga |
| P1 | NIST | Smoke Movement in Rooms of Fire Involvement and Adjacent Spaces (NBS IR 83-2748) | 1983 | Llenado de humo, recintos adyacentes | https://doi.org/10.6028/NBS.IR.83-2748 | `Docu Simufire/NIST/NBS_IR_83_2748_Smoke_Movement_in_Rooms_and_Adjacent_Spaces.pdf` | pendiente-descarga |
| P1 | NIST | Carbon Monoxide Production in Compartment Fires: Full-Scale Enclosure Burns (NISTIR 5499) | 1994 | Produccion de CO, recintos a escala real | https://doi.org/10.6028/NIST.IR.5499 | `Docu Simufire/NIST/NISTIR_5499_Carbon_Monoxide_Production_Full_Scale.pdf` | pendiente-descarga |
| P1 | NIST | Experimental Study of the Effects of Fuel Type, Fuel Distribution, and Vent Size on Full-Scale Under-Ventilated Compartment Fires in an ISO 9705 Room (TN 1603) | 2008 | Fuego subventilado, especies, temperatura | https://www.nist.gov/el/fire-research-division-73300/nist-technical-note-1603 | `Docu Simufire/NIST/NIST_TN_1603_Underventilated_Compartment_Fires.pdf` | pendiente-descarga |
| P1 | NIST | Experimental Study of the Three Dimensional Internal Structure of Underventilated Compartment Fires in an ISO 9705 Room (TN 1736) | 2012 | Mapas 3D de temperatura y especies | https://tsapps.nist.gov/publication/get_pdf.cfm?pub_id=908944 | `Docu Simufire/NIST/NIST_TN_1736_Three_Dimensional_Internal_Structure.pdf` | pendiente-descarga |
| P1 | NIST | Propane Gas Fire Experiments in Residential Scale Structures (TN 1953) | 2017 | Vivienda a escala real, ventilacion, PPV | https://doi.org/10.6028/NIST.TN.1953 | `Docu Simufire/NIST/NIST_TN_1953_Propane_Gas_Fire_Experiments_in_Residential_Scale_Structures.pdf` | pendiente-descarga |
| P1 | NIST | Report on Residential Fireground Field Experiments (TN 1661) | 2010 | Experimentos de campo residenciales | https://tsapps.nist.gov/publication/get_pdf.cfm?pub_id=904607 | `Docu Simufire/NIST/NIST_TN_1661_Residential_Fireground_Field_Experiments.pdf` | pendiente-descarga |
| P1 | Fire Safety Journal | Effects of HVAC on combustion-gas transport in residential structures | 2022 | `O2`, `CO2`, `H2O`, HVAC, puertas | https://www.sciencedirect.com/science/article/pii/S0379711222000121 | `Docu Simufire/Journals_OpenAccess/Effects_of_HVAC_on_Combustion_Gas_Transport_2022.pdf` | pendiente-descarga |
| P1 | Data in Brief / PMC | Experimental data from gas burner fires in residential structure with HVAC system | 2023 | Datos abiertos para validacion | https://pmc.ncbi.nlm.nih.gov/articles/PMC9792339/ | `Docu Simufire/Journals_OpenAccess/Experimental_Data_Gas_Burner_Fires_HVAC_2023.pdf` | pendiente-descarga |
| P1 | Fire Technology | Numerical Simulations of Gas Burner Experiments in a Residential Structure with HVAC System | 2023 | Validacion FDS con HVAC residencial | https://link.springer.com/article/10.1007/s10694-023-01390-y | `Docu Simufire/Journals_OpenAccess/Numerical_Simulations_Gas_Burner_Experiments_HVAC_2023.pdf` | pendiente-descarga |
| P1 | Fire Technology | Analysis of Changing Residential Fire Dynamics and Its Implications on Firefighter Operational Timeframes | 2012 | Modern fuel loads, tiempos operativos | https://link.springer.com/article/10.1007/s10694-011-0249-2 | `Docu Simufire/Journals_OpenAccess/Changing_Residential_Fire_Dynamics_2012.pdf` | pendiente-descarga |
| P2 | NIST | Air Moving Systems and Fire Protection (NISTIR 5227) | 1993 | HVAC y control de humo | https://doi.org/10.6028/NIST.IR.5227 | `Docu Simufire/NIST/NISTIR_5227_Air_Moving_Systems_and_Fire_Protection.pdf` | pendiente-descarga |
| P2 | NIST | Flow Induced by Fire in a Compartment | 1982 | Flujos en abertura, entrainment | https://tsapps.nist.gov/publication/get_pdf.cfm?pub_id=106938 | `Docu Simufire/NIST/Flow_Induced_by_Fire_in_a_Compartment_1982.pdf` | pendiente-descarga |
| P2 | NIST | CFAST - Consolidated Model of Fire Growth and Smoke Transport, Technical Reference Guide | 2004 | Ecuaciones de zona y base comparativa | https://doi.org/10.6028/NIST.sp.1030 | `Docu Simufire/Reviews_and_Models/CFAST_Technical_Reference_Guide_2004.pdf` | pendiente-descarga |
| P2 | OJP / FSRI | Impact of Fixed Ventilation on Fire Damage Patterns in Full-Scale Structures | 2019 | Patrones de dano, ventilacion fija, validacion | https://ojp.gov/library/publications/impact-fixed-ventilation-fire-damage-patterns-full-scale-structures | `Docu Simufire/FSRI_ULRI/Impact_of_Fixed_Ventilation_on_Fire_Damage_Patterns_2019.pdf` | pendiente-descarga |
| P2 | NIJ / FSRI | Evaluation of Heat Flux Profiles Through Walls in Support of Fire Model Validation | 2024 | Validacion de modelo, flujo termico y paredes | https://www.ojp.gov/pdffiles1/nij/grants/309047.pdf | `Docu Simufire/FSRI_ULRI/Evaluation_of_Heat_Flux_Profiles_Through_Walls_2024.pdf` | disponible |
| P2 | Fire Technology | Design Fire Characteristics for Probabilistic Assessments of Dwellings in England | 2020 | Design fires residenciales, sensibilidad | https://link.springer.com/article/10.1007/s10694-019-00925-6 | `Docu Simufire/Journals_OpenAccess/Design_Fire_Characteristics_for_Dwellings_2020.pdf` | pendiente-descarga |

## Priorizacion operativa

- `P1`: util para calibrar ya el modelo de gases, ventilacion, flashover y tenabilidad en vivienda.
- `P2`: util para extender validacion, dano termico, HVAC, y comparacion con modelos de referencia.

## Hipotesis de trabajo para Simufire

- El corpus `P1` deberia bastar para definir al menos tres familias de casos de validacion: `bedroom_fire`, `kitchen_living_room_fire`, y `ventilation_or_hvac_case`.
- Los estudios FSRI ofrecen benchmarks tacticos y de vivienda completa.
- Los documentos NIST aportan base fisica y datasets de compartimento subventilado necesarios para revisar yields, mezcla y transporte.
- Los articulos abiertos sobre HVAC y gases ayudan a cerrar la brecha que hoy tenemos entre humo temprano, agotamiento de oxigeno y comportamiento del incendio.
