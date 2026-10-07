# Indice de bibliografia sobre incendios en edificaciones

## Objetivo

Construir una biblioteca tecnica abierta y trazable para calibrar `Simufire` con estudios publicados y casos a escala real.

## Estado de recoleccion - 2026-09-16

- Biblioteca tecnica organizada en `FSRI_ULRI`, `NIST`, `Journals_OpenAccess`, `Reviews_and_Models`, `Doors` y `Glass`.
- Inventario reproducible guardado en `docs/literature/download_manifest_fire_literature.json`.
- Resultado actual: `39` documentos curados disponibles localmente en subcarpetas tematicas, mas los documentos raiz ya existentes en `docs/literature`.
- Nota operativa: los articulos abiertos sobre `HVAC` y `gas burner fires` requirieron captura a PDF desde navegador headless por protecciones anti-bot del sitio. Siguen siendo articulos abiertos, pero el binario local no proviene del boton oficial de descarga.
- Nota de trazabilidad: no encontre un PDF publico directo para `Measurement of Heat Transfer and Fire Damage Patterns on Walls for Fire Model Validation`; en su lugar se incorporo el reporte publico relacionado `Evaluation of Heat Flux Profiles Through Walls in Support of Fire Model Validation`.
- Pendientes menores: las Part I y Part II de `Search and Rescue Tactics in Single-Story Single-Family Homes` siguen catalogadas pero no localizadas todavia con URL publica estable.

## Como usar esta carpeta

- `FSRI_ULRI`: experimentos residenciales a escala real, tacticas, tenabilidad y ventilacion.
- `NIST`: modelos de compartimento, transporte de humo, especies y validacion.
- `Journals_OpenAccess`: articulos revisados por pares con PDF abierto.
- `Reviews_and_Models`: guias, revisiones y documentos de soporte para parametrizacion.
- `Doors`: deformacion termica, integridad y fuga de gases en conjuntos de puerta.
- `Glass`: fractura termica, desprendimiento y acristalamientos simples o multiples.
- `Sandia`: informes de difusion ilimitada de Sandia National Laboratories.
- `data/NIST_FSE_2008`: CSV experimental original ISOHept9, aviso NIST y
  [procedencia versionada](data/NIST_FSE_2008/PROVENANCE.json). Serie de masa
  independiente de calorimetria; **no** salida FDS ni perfil activado.
  [Revision D1 del 03-10](../validation/G3_D1_ISOHEPT9_BENCHMARK_GATE_2026-10-03.md):
  [Replay cerrado tecnicamente](../validation/G3_D1_ISOHEPT9_REPLAY_2026-10-04.md),
  no prediccion de evaporacion. Base energetica de referencia revisada en el
  [gate con fases](../validation/G3_D1_HEPTANE_PHASE_BASIS_2026-10-04.md);
  atribucion al ensayo, energia sensible, integracion y cola pendientes.
  Estos artefactos de datos se inventarian aparte de los 39 PDF curados.

## Objetivos de calibracion para Simufire

Actualizacion adicional del 07-10, tercera del dia: seleccion
experimental de la fuente de incendio por objeto,
[decision](../validation/G3_OBJECT_FIRE_SOURCE_SELECTION_2026-10-07.md).
Sin documentos nuevos en la biblioteca. NIST Fire Calorimetry Database
(doi:10.18434/mds2-2314): el registro declara la licencia abierta de
NIST, comprobado el 07-10; sus CSV y fichas ya estaban archivados. FSRI
Materials and Products Database, commit a432697e, que sigue siendo el
ultimo: sin licencia declarada. Sus tres repeticiones del sofa
(Overstuffed_Sofa_R1 a R3) quedan solo en local, con enlace, commit y
SHA-256 en el
[registro](../validation/G3_OBJECT_FIRE_SOURCE_INPUTS_2026-10-07.json); no
se incorporan ni entran en el manifiesto. Ignitor e incertidumbre de ese
ensayo no localizados en lo revisado. Manifiesto sin cambio: 50 entradas.
Ninguna activacion fisica.

Actualizacion adicional del 07-10, segunda del dia: gate propio del
ensayo de evaporacion sin llama en cono,
[decision](../validation/G3_D1_CONE_EVAPORATION_BENCHMARK_2026-10-07.md).
Beji, Helson, Rogaume y Luche, Fire Saf. J. 121 (2021) 103317,
[version aceptada en el repositorio de Gante](https://biblio.ugent.be/publication/8702056),
SHA-256 1c82a821...945ff. Sigue siendo solo localizador: con copyright y
sin licencia de redistribucion, no se incorpora ni entra en el manifiesto.
Version publicada no obtenida. Datos digitales y material suplementario no
localizados (Crossref, Gante, HAL, DataCite, Zenodo, OpenAlex y MaCFP). La
serie digitalizada de sus figuras tampoco se publica. Manifiesto sin
cambio: 50 entradas. Ninguna activacion fisica.

Actualizacion adicional del 07-10: revision del gate de B neto,
[decision corregida](../validation/G3_D1_NET_THERMAL_BUDGET_REVIEW_2026-10-07.md).
Luketa, Sandia SAND2010-2511 (2010), analisis del propio laboratorio de
los ensayos de piscina de 2 m: rangos de reflexion, transmision, perdida
por el fondo y lectura de las galgas, y balance del heptano sin cerrar
([fuente oficial](https://www.osti.gov/biblio/984087),
[PDF local](Sandia/SNL_SAND2010-2511_Assessment_Simulation_Hydrocarbon_Pool_Fire_Tests_2010.pdf));
difusion ilimitada segun su portada. Solo localizador: Beji, Helson,
Rogaume y Luche, Fire Saf. J. (2021), evaporacion de heptano sin llama en
cono de atmosfera controlada,
[version de autor](https://biblio.ugent.be/publication/8702056), con
copyright. Localizado y no obtenido por acceso cerrado: Suo-Anttila y
otros, Proc. Combust. Inst. 32 (2009),
[doi](https://doi.org/10.1016/j.proci.2008.06.044), espectros en la cupula
de vapor. No localizados: datos brutos de SNL011, 012 y 029 ni los ensayos
de 1 ft sobre colocacion de la galga. B neto: GO parcial retirado, NO-GO
no identificado. Manifiesto: 49 -> 50 entradas. Ninguna activacion fisica.

Actualizacion adicional del 06-10: gate del presupuesto termico neto del
combustible,
[decision y contrato](../validation/G3_D1_NET_THERMAL_BUDGET_GATE_2026-10-06.md).
Blanchat y Suo-Anttila, Sandia SAND2010-6377 (2011), piscinas de 2 m con
flujo de calor a la superficie y perdida de masa de la misma corrida
([fuente oficial](https://www.osti.gov/biblio/1018470),
[PDF local](Sandia/SNL_SAND2010-6377_Hydrocarbon_Characterization_Results_2011.pdf));
difusion ilimitada segun su portada. Solo localizador, sin archivar por
derechos no aclarados: Hamins y otros, Combust. Sci. Technol. 97 (1994),
[reimpresion servida por el NIST](https://tsapps.nist.gov/publication/get_pdf.cfm?pub_id=909794),
balance de calor de una piscina de heptano de 0,30 m; y Kim, Lee y Hamins,
Fire Saf. J. 107 (2019),
[manuscrito de autor](https://tsapps.nist.gov/publication/get_pdf.cfm?pub_id=928848).
Resultado negativo: SAND2007-2391 es el plan de ensayos, sin resultados.
B neto: GO parcial como tasa estacionaria acotada, NO-GO como valor
puntual, transitorio y prediccion. Manifiesto: 48 -> 49 entradas. Ninguna
activacion fisica.

Actualizacion adicional del 06-10: gate del Cp del heptano liquido,
[decision y requisitos](../validation/G3_D1_HEPTANE_LIQUID_ELIGIBILITY_2026-10-06.md).
Densidad (p, rho, T) del n-heptano liquido, 233 a 393 K y 0,1 a 30 MPa, del
archivo ThermoML del NIST (doi:10.18434/mds2-2422, NIST Open License):
[datos sin modificar y procedencia](data/NIST_THERMOML_HEPTANE_2008/PROVENANCE.json);
es la captura del NIST de un articulo de 2008 que no se inspecciono.
Scott, U.S. Bureau of Mines Bulletin 666 (1974), gas ideal de los alcanos
de 0 a 1500 K, valores correlacionados
([fuente oficial](https://digital.library.unt.edu/ark:/67531/metadc12811/),
[PDF local](Reviews_and_Models/USBM_Bulletin_666_Alkane_Ideal_Gas_Properties_1974.pdf)).
Solo localizador, sin archivar por derechos reservados: Zabransky y
Ruzicka, J. Phys. Chem. Ref. Data 23, 55 (1994),
[copia servida por el NIST](https://srd.nist.gov/JPCRD/jpcrd469.pdf),
reevaluacion del Csat del heptano en ITS-90; se citan veinte valores como
contraste. Resultado negativo: NBS Circular 461 solo da densidad a 20 y
25 C. No obtenidos: los dos articulos de JACS de 1937 y 1947.
Liquido: GO parcial por conversion justificada de Csat a Cp; gas: GO
parcial condicionado sin cambio de rango. Manifiesto: 47 -> 48 entradas;
los datos de densidad se inventarian aparte. Ninguna activacion fisica.

Actualizacion adicional del 05-10: cuatro fuentes primarias del NBS/NIST
para el gate de propiedades termicas reales del heptano,
[decision y contrato](../validation/G3_D1_HEPTANE_REAL_PROFILE_ELIGIBILITY_2026-10-05.md):
Douglas 1969, conversion de propiedades calorimetricas a la IPTS-68
([fuente oficial](https://nvlpubs.nist.gov/nistpubs/jres/73A/jresv73An5p451_A1b.pdf),
[PDF local](NIST/NBS_IPTS68_Conversion_Douglas_1969.pdf));
NIST TN 1265, diferencias entre ITS-90 e IPTS-68
([fuente oficial](https://nvlpubs.nist.gov/nistpubs/Legacy/TN/nbstechnicalnote1265.pdf),
[PDF local](NIST/NIST_TN_1265_ITS90_Guidelines_1990.pdf));
Osborne y Ginnings, NBS RP1841 (1947), relacion entre Csat y Cp
([fuente oficial](https://nvlpubs.nist.gov/nistpubs/jres/39/jresv39n5p453_A1b.pdf),
[PDF local](NIST/NBS_Hydrocarbon_Heat_Capacity_Osborne_Ginnings_1947.pdf));
Brooks, Howard y Crafton, NBS RP1271 (1940), densidad del liquido a 20 y 25 C
([fuente oficial](https://nvlpubs.nist.gov/nistpubs/jres/24/jresv24n1p33_A1b.pdf),
[PDF local](NIST/NBS_Aliphatic_Hydrocarbon_Properties_Brooks_1940.pdf)).
Originales del servidor de publicaciones del NIST, revision focal de las
paginas citadas, no integral. Gas ideal: GO parcial; liquido: NO-GO como Cp
isobarico. Manifiesto: 43 -> 47 entradas. No se redistribuyen compilaciones
SRD ni ecuaciones de estado con licencia. Ninguna activacion fisica.

Actualizacion adicional del 04-10: Douglas et al., NBS RP2526 (1954),
[fuente oficial](https://nvlpubs.nist.gov/nistpubs/jres/53/jresv53n3p139_A1b.pdf),
[PDF local](NIST/NBS_Heptane_Calorimetric_Properties_1954.pdf),
[contrato sensible y revision focal](../validation/G3_D1_SENSIBLE_CONTRACT_2026-10-04.md).
Propiedades calorimetricas del heptano: gas ideal y liquido sobre
saturacion, no rutas intercambiables. Escala de temperatura historica,
perfil material automatico no aprobado. Manifiesto: 42 -> 43 entradas.
No se redistribuye la compilacion SRD WebBook localizada ni el otro
articulo candidato sin revisar. Ninguna activacion fisica.

Actualizacion bibliografica adicional del 04-10: NIST TN 2162r1,
octubre de 2024, 123 paginas,
[PDF local](NIST/NIST_TN_2162r1_Medium_Scale_Pool_Fires.pdf),
[fuente oficial](https://doi.org/10.6028/NIST.TN.2162r1).
[Snapshot MaCFP, licencia e inventario](data/NIST_POOL_FIRES_2024/PROVENANCE.json)
y [revision termica focal](../validation/G3_D1_POOL_THERMAL_EVIDENCE_2026-10-04.md).
Perfil hacia sensor medido, no B neto del liquido; discrepancias de altura
y temperatura preservadas. CSV constante: contorno, no señal transitoria
ni salida FDS. Ninguna activacion. Manifiesto: 41 -> 42 entradas;
datos MaCFP inventariados aparte, licencia MIT conservada.

Actualizacion bibliografica del 04-10: NIST TN 2126-upd1, febrero 2026,
[PDF local](NIST/NIST_TN_2126_upd1_Thermochemical_Properties.pdf),
[fuente oficial](https://doi.org/10.6028/NIST.TN.2126-upd1).
Calores netos/brutos, fases y entalpias de referencia de sustancias puras;
no rendimientos de CO de muebles ni certificado del lote de ISOHept9.
Manifiesto de descargas: 40 -> 41 entradas; el recuento original de 39
documentos del apartado de 2026-09-16 es historico, no una nueva auditoria
de disponibilidad de todas las entradas. SHA y version revisada registrados.

- Tiempo a flashover y transicion a incendio limitado por ventilacion.
- Transporte de humo y gases desde recinto origen a pasillos y recintos remotos.
- Efecto de puertas interiores, puerta principal, ventanas y HVAC.
- Curvas de `O2`, `CO2`, `CO`, `H2O`, temperatura y tenabilidad/FED.
- Diferencias entre compartimentos cerrados, parcialmente ventilados y ventilados.

## Ya disponible en esta carpeta

| Estado | Documento | Ruta local |
| --- | --- | --- |
| disponible | Evolution of combustion gas concentrations in full-scale residential fire.pdf | `docs/literature/Evolution of combustion gas concentrations in full-scale residential fire.pdf` |
| disponible | NIST.SP.1018e6.pdf | `docs/literature/NIST.SP.1018e6.pdf` |
| disponible | NIST.TN.1889v1.pdf | `docs/literature/NIST.TN.1889v1.pdf` |
| disponible | nistir7080.pdf | `docs/literature/nistir7080.pdf` |

## Coleccion focal: puertas cerradas, deformacion y vidrio

La interpretacion y los limites de uso estan documentados en
[`docs/RESEARCH_PUERTAS_CRISTALES_FUGAS_2026-09-16.md`](../RESEARCH_PUERTAS_CRISTALES_FUGAS_2026-09-16.md).

| Fuente | Documento | Uso en Simufire | URL fuente | Ruta local |
| --- | --- | --- | --- | --- |
| NIST | TN 2329, *A Collection of Dwellings to Represent the U.S. Housing Stock: 2024 Update* | ELA a 4 Pa de 12/21 cm2 (p. 28, seccion 5.9 Doors). **Verificado el 2026-09-22 (F2.2D4B1):** son los *best estimates* de la tabla 1 del ASHRAE Fundamentals 2001 para puerta simple **con** y **sin** burlete; esa tabla **fue retirada** de ediciones posteriores del manual y NIST **deja de usarlos** en la coleccion de 2025. Quedan como `research_only`, nunca como calibracion | https://doi.org/10.6028/NIST.TN.2329 | `docs/literature/NIST/NIST_TN_2329_US_Housing_Stock_2025.pdf` |
| NIST | TN 1887r1, *CONTAM User Guide and Program Documentation, Version 3.4* | Convencion ELA: C_d = 1,0 con 4 Pa (o 0,6 con 10 Pa), ec. 28-29, p. 266; exponente razonable 0,6-0,7 sin dato experimental | https://doi.org/10.6028/NIST.TN.1887r1 | `docs/literature/NIST/NIST_TN_1887r1_CONTAM_User_Guide.pdf` |
| NBS/NIST | NBSIR 81-2214, *A Review of Measurements, Calculations and Specifications of Air Leakage Through Interior Door Assemblies* | Variacion experimental por holgura, sello y configuracion. **Verificado el 2026-09-22 (F2.2D4B1):** ec. [1] `Q = K A dp^n` con K = 0,827 en SI (p. 4, equivale a Cd = 0,64 con rho = 1,2); tabla 1 (p. 17) da **n = 0,50 para holguras de puerta**; tabla 2 (p. 18) da 18 puertas medidas a 25 Pa, de 0,3 a >40 m3/h.m; tabla 3 (p. 19) da ventanas domesticas a 100 Pa; p. 8: **no existe especificacion de fuga para puertas interiores en EE. UU.**; p. 10: la dp a traves de una puerta interior **no se considera probable que supere 50 Pa** | https://nvlpubs.nist.gov/nistpubs/Legacy/IR/nbsir81-2214.pdf | `docs/literature/NIST/NBSIR_81_2214_Door_Air_Leakage.pdf` |
| IAFSS/NIST | Gross y Haberman, *Analysis and Prediction of Air Leakage Through Door Assemblies* | Ley de rendijas, transicion de regimen y posicion de huecos. **Verificado el 2026-09-22 (F2.2D4B1):** tabla 1 (p. 176) da **caudales MEDIDOS** de 11 conjuntos de puerta a 25 Pa (0,013 a 0,151 m3/s), con acuerdo modelo-medida **dentro del 20 %**; tabla 2 (p. 177) tabula el caudal de una rendija recta de 40 mm a 10/25/100 Pa y 20/100/300 C, de donde se lee que el **exponente va de 0,98 (rendija de 0,5 mm) a 0,50 (10 mm)**; observacion 4 (p. 177) justifica **segmentar** las rendijas verticales en altura; las conclusiones dicen que la ley de potencia simple es **menos precisa** que su relacion | https://publications.iafss.org/publications/fss/2/169/view/fss_2-169.pdf | `docs/literature/NIST/Gross_Haberman_Door_Air_Leakage_1989.pdf` |
| TU Graz | Prieler et al., *Numerical Simulation of a Fire Resistance Test and Prediction of the Flue Gas Leakage Using CFD/FEM Coupling* | Topologia de deformacion en dintel/cerradura; no calibracion residencial | https://doi.org/10.1108/JSFE-01-2023-0011 | `docs/literature/Doors/Prieler_Door_Deformation_Flue_Gas_Leakage_2023.pdf` |
| Virginia Tech | Skelly, Roby y Beyler, *Experimental Investigation of Glass Breakage in Compartment Fires* | Tension termica centro-borde, marco y primer agrietamiento. **Verificado el 2026-09-22 (F2.2D4B1):** con borde protegido la diferencia critica centro-borde es de **unos 90 C** experimentales frente a 70 C teoricos, y el pano sufre **colapso al menos parcial**; con borde **no protegido** hubo pocas grietas y **ningun colapso en ningun ensayo** | https://vtechworks.lib.vt.edu/bitstreams/291a09f0-774f-4d6d-b978-9bd1f3f89be5/download | `docs/literature/Glass/Skelly_Glass_Breakage_Compartment_Fires_1990.pdf` |
| IAFSS | *Experimental Study on the Breakage of Toughened Glass in Enclosure Fires* | Diferencia entre vidrio flotado y templado; desprendimiento rapido tras rotura. **Verificado el 2026-09-22 (F2.2D4B1):** sala ISO 9705 con fuegos de bandeja; el templado rompe con diferencias de temperatura mayores que el flotado y despues **cae casi entero poco despues de la primera rotura**. Esto **contradice** a Peng et al., que no vio grieta alguna en templado bajo 20 kW/m2: por eso el perfil de templado queda BLOQUEADO | https://publications.iafss.org/publications/aofst/7/92 | `docs/literature/Glass/Toughened_Glass_Enclosure_Fires_2007.pdf` |
| DTU | Peng et al., *Fire-Induced Cracking of Modern Window Glazing* | 75 ensayos, tipos de vidrio y unidades de una a tres hojas. **Verificado el 2026-09-22 (F2.2D4B1):** espesores 3-8 mm, lados 200-500 mm, marco que tapa 20 mm de borde, flujo radiante constante de ~20 kW/m2; **ninguna grieta en templado** y **ningun desprendimiento en laminado**; en recocido las fracciones desprendidas son 10-25 % al agrietarse y 60-90 % cuando se retrasa (tabla 2), y **el 90 % deja 1 cm de vidrio en el borde**: no se observo nunca el 100 % | https://orbit.dtu.dk/en/publications/fire-induced-cracking-of-modern-window-glazing-an-experimental-st/ | `docs/literature/Glass/Peng_Modern_Window_Glazing_Fire_2024.pdf` |
| VTT | *Probabilistic Simulation of Glass Fracture and Fallout in Fire* | Separacion de fractura y desprendimiento; modo probabilista reproducible | https://publications.vtt.fi/pdf/workingpapers/2005/W41.pdf | `docs/literature/Glass/VTT_Probabilistic_Glass_Fracture_Fallout_2005.pdf` |

## Verificacion a nivel de pagina (F2.2D4B1, 2026-09-22)

Las seis fuentes de la coleccion focal de puertas y vidrio se releyeron pagina a
pagina para construir la matriz de calibracion de
[`docs/PROMPT_MOTOR_FUGAS_PUERTA_CERRADA.md`](../PROMPT_MOTOR_FUGAS_PUERTA_CERRADA.md)
(§21). **No se incorporo ninguna fuente nueva**: todas estaban ya en la
biblioteca. Lo que si cambio es la calificacion de varias de ellas, y las
celdas de "Uso en Simufire" de la tabla siguiente recogen ahora la pagina, la
tabla o la ecuacion exacta, el montaje del ensayo y sus limites.

El catalogo de perfiles que resulta de esa lectura vive en
`sim/building/OpeningPhysicsProfileCatalog.gd` y **no lee estos PDF**: copia las
referencias como texto.

## Coleccion focal: presion de recintos cerrados (F2.2)

La interpretacion y los limites de uso estan documentados en
[`docs/PROMPT_MOTOR_F2_2_SOBREPRESION_RECINTOS.md`](../PROMPT_MOTOR_F2_2_SOBREPRESION_RECINTOS.md).

| Fuente | Documento | Uso en Simufire | URL fuente | Ruta local |
| --- | --- | --- | --- | --- |
| NIST | TN 1889v1, *CFAST - Consolidated Fire and Smoke Transport (Version 7), Volume 1: Technical Reference Guide* | Ecuacion de presion del compartimento (ec. 2.5, p. 9), conservacion de masa y energia (ec. 2.2-2.4, p. 8), flujo por aberturas verticales con plano neutro (ec. 4.1-4.5, p. 17-18, C = 0,7) | https://doi.org/10.6028/NIST.TN.1889v1 | `docs/literature/NIST.TN.1889v1.pdf` |
| NIST | TN 1889v2, *CFAST - Consolidated Fire and Smoke Transport (Version 7), Volume 2: User's Guide* | Las fugas se declaran como aberturas explicitas, no como un termino implicito (p. 21 del texto, indice 34 del PDF) | https://doi.org/10.6028/NIST.TN.1889v2 | `docs/literature/NIST/NIST_TN_1889v2_CFAST_Users_Guide.pdf` |

Descarga registrada de TN 1889v2: 2026-09-17, 1 730 244 bytes, SHA-256
`a2f638938e83ec8008946bdbc5b2e29e3700d4cf4162a2c01fcc2532810afb85`, desde
`https://nvlpubs.nist.gov/nistpubs/TechnicalNotes/NIST.TN.1889v2.pdf`.

## Catalogo priorizado

| Pri | Fuente | Documento | Ano | Tema clave | URL fuente | Destino previsto | Estado |
| --- | --- | --- | --- | --- | --- | --- | --- |
| P1 | FSRI | Occupant Tenability in Single Family Homes Part I | 2017 | Tenabilidad, puertas interiores, fuego residencial | https://fsri.org/sites/default/files/2021-07/Occupant_Tenability_in_Single_Family_Homes_Part_I.pdf | `docs/literature/FSRI_ULRI/Occupant_Tenability_Part_I_2017.pdf` | pendiente-descarga |
| P1 | FSRI | Occupant Tenability in Single Family Homes Part II | 2017 | Tenabilidad, door control, ventilacion vertical, agua | https://fsri.org/sites/default/files/2021-07/Occupant_Tenability_in_Single_Family_Homes_Part_II.pdf | `docs/literature/FSRI_ULRI/Occupant_Tenability_Part_II_2017.pdf` | pendiente-descarga |
| P1 | Springer | Effect of Firefighting Intervention on Occupant Tenability during a Residential Fire | 2019 | FED, tacticas, exposicion ocupantes | https://link.springer.com/article/10.1007/s10694-019-00864-2 | `docs/literature/Journals_OpenAccess/Effect_of_Firefighting_Intervention_on_Occupant_Tenability_2019.pdf` | pendiente-descarga |
| P1 | FSRI | Evolution of Combustion Gas Concentrations in Full-Scale Residential Fire Environments | 2026 | Gases toxicos, pasillo, IDLH, full-scale | https://fsri.org/resource/evolution-combustion-gas-concentrations-full-scale-residential-fire-environments | `docs/literature/Evolution of combustion gas concentrations in full-scale residential fire.pdf` | disponible |
| P1 | FSRI | Analysis of Search and Rescue Tactics in Single-Story Single-Family Homes Part I: Bedroom Fires | 2025 repo / 2022 study | Bedroom fires, busqueda y rescate, gases | https://ulri.figshare.com/categories/Human_resources_and_industrial_relations/32147 | `docs/literature/FSRI_ULRI/Search_and_Rescue_Part_I_Bedroom_Fires.pdf` | pendiente-localizacion |
| P1 | FSRI | Analysis of Search and Rescue Tactics in Single-Story Single-Family Homes Part II: Kitchen and Living Room Fires | 2025 repo / 2022 study | Cocina, salon, busqueda y rescate, flujo | https://ulri.figshare.com/categories/Human_resources_and_industrial_relations/32147 | `docs/literature/FSRI_ULRI/Search_and_Rescue_Part_II_Kitchen_Living_Room.pdf` | pendiente-localizacion |
| P1 | FSRI | Analysis of Search and Rescue Tactics in Single-Story Single-Family Homes Part III: Tactical Considerations | 2025 repo | Sintesis tactica basada en datos | https://ulri.figshare.com/articles/report/Analysis_of_Search_and_Rescue_Tactics_in_Single-Story_Single-Family_Homes_Part_III_Tactical_Considerations/28075001 | `docs/literature/FSRI_ULRI/Search_and_Rescue_Part_III_Tactical_Considerations.pdf` | pendiente-descarga |
| P1 | FSRI | Analysis of the Coordination of Suppression and Ventilation in Single-Family Homes | 2020 | Coordinacion ventilacion-supresion | https://fsri.org/resource/analysis-coordination-suppression-and-ventilation-single-family-homes | `docs/literature/FSRI_ULRI/Coordination_Suppression_Ventilation_Single_Family_2020.pdf` | pendiente-descarga |
| P1 | FSRI | Analysis of the Coordination of Suppression and Ventilation in Multi-Family Dwellings | 2020 | Apartamentos, escalera comun, humo y gases | https://fsri.org/resource/analysis-coordination-suppression-and-ventilation-multi-family-dwellings | `docs/literature/FSRI_ULRI/Coordination_Suppression_Ventilation_Multi_Family_2020.pdf` | pendiente-descarga |
| P1 | FSRI | Impact of Ventilation on Fire Behavior in Legacy and Contemporary Residential Construction | 2010 / 2025 repo | Ventilacion, legado vs contemporaneo, flashover | https://ulri.figshare.com/articles/report/Impact_of_Ventilation_on_Fire_Behavior_in_Legacy_and_Contemporary_Residential_Construction/28087586 | `docs/literature/FSRI_ULRI/Impact_of_Ventilation_Legacy_and_Contemporary_Residential_Construction.pdf` | pendiente-descarga |
| P1 | FSRI | Study of the Effectiveness of Fire Service Positive Pressure Ventilation During Fire Attack in Single Family Homes Incorporating Modern Construction Practices | 2016 | PPV/PPA, dinamica de incendio, ventilacion | https://fsri.org/sites/default/files/2021-07/Positive_Pressure_Ventilation_Report_Website.pdf | `docs/literature/FSRI_ULRI/Positive_Pressure_Ventilation_Report_2016.pdf` | pendiente-descarga |
| P1 | FSRI | Understanding and Fighting Basement Fires | 2025 repo | Incendios de sotano, ventilacion limitada | https://ulri.figshare.com/articles/report/Understanding_and_Fighting_Basement_Fires/28050134 | `docs/literature/FSRI_ULRI/Understanding_and_Fighting_Basement_Fires.pdf` | pendiente-descarga |
| P1 | NIST | Modeling Smoke Movement Through Compartmented Structures (NISTIR 4872) | 1992 | Modelo multicompartment, humo, gases toxicos | https://doi.org/10.6028/NIST.IR.4872 | `docs/literature/NIST/NISTIR_4872_Modeling_Smoke_Movement_Through_Compartmented_Structures.pdf` | pendiente-descarga |
| P1 | NIST | Improvement in Predicting Smoke Movement in Compartmented Structures | 1993 | Mejoras CFAST, transporte de humo | https://tsapps.nist.gov/publication/get_pdf.cfm?pub_id=912721 | `docs/literature/NIST/Improvement_in_Predicting_Smoke_Movement_1993.pdf` | pendiente-descarga |
| P1 | NIST | Smoke Movement in Rooms of Fire Involvement and Adjacent Spaces (NBS IR 83-2748) | 1983 | Llenado de humo, recintos adyacentes | https://doi.org/10.6028/NBS.IR.83-2748 | `docs/literature/NIST/NBS_IR_83_2748_Smoke_Movement_in_Rooms_and_Adjacent_Spaces.pdf` | pendiente-descarga |
| P1 | NIST | Carbon Monoxide Production in Compartment Fires: Full-Scale Enclosure Burns (NISTIR 5499) | 1994 | Produccion de CO, recintos a escala real | https://doi.org/10.6028/NIST.IR.5499 | `docs/literature/NIST/NISTIR_5499_Carbon_Monoxide_Production_Full_Scale.pdf` | pendiente-descarga; el fichero con ese nombre es un libro de resumenes NIST de octubre de 1994, no el informe: no extraer datos |
| P1 | NIST | The Character of Burning Residential and Office Items (TN 2303) | 2025 | HRR, perdida de masa y rendimientos de CO/HCN de sofas, sillas, mesa auxiliar y alfombra; estos dos ultimos no son calibradores aislados fiables | https://doi.org/10.6028/NIST.TN.2303 | `docs/literature/NIST/NIST_TN_2303_Character_Burning_Items.pdf`, SHA-256 7844cfe9070e7385f7cfef28dde1b3740b83315ecd35be12377834d447a32c03 | tablas 6/8 de los 48 ensayos cotejadas con FCD 2026 en `docs/validation/G3_CO_FUENTES_ELEGIBILIDAD_2026-09-29.md`; masa transitoria solo Tests 1–24 y solo en figuras (ap. C); THR igual, masa cambiada en 31/35/38, causa de cambio de CO no demostrada |
| P1 | NIST | The NIST 20 MW Calorimetry Measurement System for Large-Fire Research (TN 2077) | 2019 | Metodo de medicion de HRR y CO/CO2 en escape, balance de gases, retardo y alineacion de analizadores | https://doi.org/10.6028/NIST.TN.2077 | sin copia local verificada | base del tratamiento temporal de Test029; la reconstruccion de CO kg/s sigue provisional |
| P1 | NIST | User's Guide for Fire Calorimetry Database, v4a | 2020 | Formula de CO total por fraccion volumetrica corregida de fondo, caudal de escape y masas molares; periodo ignicion-apagado | https://www.nist.gov/system/files/documents/2020/11/19/FCD_User_Guide_v4a.pdf | `docs/literature/NIST/FCD_User_Guide_v4a_2020.pdf`, SHA-256 89692794156d9a4f32ba0493e791da23d80160035877d2831d31a5317e6cee8f | revisada 23-10-2020; sigue siendo la guia enlazada el 29-09-2026; su metodo reproduce la FCD 2026 en 42/43 ensayos; no documenta el script 8.7.1 |
| P1 | NIST | Fire Calorimetry Database: Design Fires - Residential and Office Items | ficha actualizada 2026 | Fichas y CSV temporales por ensayo; versiones actuales de rendimientos de CO | https://www.nist.gov/el/fcd/design-fires-residential-and-office-items | 48 CSV crudos `docs/literature/NIST/FCD_Test001…048_2026-04-07.csv` con SHA-256 en `docs/validation/G3_NIST_TN2303_FCD_CO_PROCESSING_2026-09-29.json`; 48 fichas archivadas sin modificar en `docs/literature/NIST/FCD_DesignFires_Test001-048_pages_retrieved_2026-09-29.zip`, SHA-256 6f674d5cb61bfd398d0a541d427c5eb6fe445cd1f2cacc8eb8fce8c3cceb0851 | procesado `NFRL_Report_8.7.1` (07-04-2026) sin codigo ni notas publicas; el esquema CSV no tiene masa del especimen; 28 mezcla cojines y 18 bajo detección |
| P1 | NIST | Smoke Component Yields from Room-scale Fire Tests (TN 1453) | 2003 | Rendimientos de CO pre/post-flashover para cojines de sofa y librerias de aglomerado | https://nvlpubs.nist.gov/nistpubs/Legacy/TN/nbstechnicalnote1453.pdf | `docs/literature/NIST/NIST_TN_1453_Smoke_Component_Yields_Room_Scale.pdf`, SHA-256 3c59ee8469e50a4cf6cf8bcaf5eb9da7fe22886e36a3de4888325a31ee724324 | tabla 25 auditada; celulas de carga continuas y CO en sala/pasillo solo en figuras; series crudas remitidas a informe compañero (ref. 33) no localizado; validacion por fase |
| P1 | NIST | Smoke Component Yields from Bench-scale Fire Tests: 2. ISO 19700 Controlled Equivalence Ratio Tube Furnace (TN 1761) | 2013 | Rendimientos CO/CO2/HCN/HCl con φ controlada para el material del sofa, libreria y cable de TN 1453 | https://nvlpubs.nist.gov/nistpubs/TechnicalNotes/NIST.TN.1761.pdf | `docs/literature/NIST/NIST_TN_1761_Smoke_Yields_ISO19700_Tube_Furnace.pdf`, SHA-256 d12457f5fa2187837d1dec4702c59e428b1008c1b6db9be609eb9965f646f15a | masa total y MLR supuesta estacionaria; sin MLR(t); validacion de dependencia con φ a escala de banco |
| P1 | FSRI / ULRI | Materials and Products Database (repositorio de datos) | 2023, commit a432697e de 2026-04-23 | Cono (masa y CO cada 0,25 s, canales brutos) y calorimetro de muebles (celula de carga y HRR, sin CO) | https://github.com/ulfsri/fsri_materials_database | Solo referencia externa; los cinco archivos originales no se redistribuyen. Nombres y SHA-256 en `docs/validation/G3_CO_SOURCE_ELIGIBILITY_MATRIX_2026-09-29.json` | licencia de redistribucion no confirmada; cono = candidato solo de familia material en llama ventilada; muebles sin CO |
| P1 | NIST / Proceedings of the Combustion Institute | Towards fire safe and flame-retardant-free upholstered furniture | 2024 | HRR, masa perdida y CO temporal/global en tres salones amueblados | https://tsapps.nist.gov/publication/get_pdf.cfm?pub_id=957121 | sin copia local verificada | tablas 1 y 3 y figuras 4/6/7 auditadas; CSV de escape publicados en la FCD (https://www.nist.gov/el/fcd/room-flashover-experiments-demonstrate-effectiveness-barrier-fabrics), sin masa del especimen, no importados; reservado para validacion externa de sala |
| P1 | NIST / W. M. Pitts | Global Equivalence Ratio Concept and the Formation Mechanisms of Carbon Monoxide in Enclosure Fires | 1995 | Limites del GER y mecanismos de generacion de CO en recintos | https://www.nist.gov/publications/global-equivalence-ratio-concept-and-formation-mechanisms-carbon-monoxide-enclosure | sin copia local verificada | marco mecanistico; no convertir directamente en ley calibrada |
| P1 | NIST | Performance of Home Smoke Alarms, NIST TN 1455-1, revision 2008 | 2008 | CO a altura respiratoria y limites instrumentales en ensayos residenciales | https://nvlpubs.nist.gov/nistpubs/Legacy/TN/nbstechnicalnote1455-1r2008.pdf | sin copia local verificada | fuente localizada; fixture pendiente |
| P1 | NIST | Home Smoke Alarm Project, Report of Test FR 4016 | 2005 | Series temporales de CO, CO2, O2, humo y temperatura en 27 ensayos residenciales | https://www.nist.gov/el/nist-report-test-fr-4016 | sin copia local verificada | fuente localizada; canales pendientes de auditoria |
| P1 | NIST | Improving Smoke Alarm Performance, TN 1837 | 2014 | Muestreo superior y a 1,5 m en pasillo residencial; no usar como tabla temporal sin verificar datos | https://nvlpubs.nist.gov/nistpubs/TechnicalNotes/NIST.TN.1837.pdf | sin copia local verificada | fuente localizada |
| P1 | NIST | Experimental Study of the Effects of Fuel Type, Fuel Distribution, and Vent Size on Full-Scale Under-Ventilated Compartment Fires in an ISO 9705 Room (TN 1603) | 2008 | Fuego subventilado, especies, temperatura | https://www.nist.gov/el/fire-research-division-73300/nist-technical-note-1603 | `docs/literature/NIST/NIST_TN_1603_Underventilated_Compartment_Fires.pdf`, SHA-256 7ba8219496f8b52035fd97ed603182782e907034a94593bb51e7382c0cf453f5 (duplicado byte a byte con nombre largo `Experimental Study of the Effects...pdf.pdf`) | contenido verificado 2026-09-29; combustibles puros en bandejas con celulas de carga, CO en capa superior y escape solo en figuras; validacion de regimen subventilado, no mobiliario |
| P1 | IAFSS / Peatross y Beyler | Ventilation Effects on Compartment Fire Characterization | 1997 | 24 ensayos de recinto con diesel, cunas de madera y placas de poliuretano; O₂ local y perdida de masa muestran tasa sensible a ventilacion | https://publications.iafss.org/publications/fss/5/403/view/fss_5-403.pdf | enlace primario abierto; sin copia local | D1: contraejemplo a pirólisis constante universal; no ofrece particion de masa ni ley para sofa |
| P1 | IAFSS / Aljumaiah et al. | Air Starved Wood Crib Compartment Fire Heat Release and Toxic Gas Yields | 2011 | Cuna de pino: residuo solido a 3–5 ACH; CO e hidrocarburos sin quemar en regimen rico a 11–37 ACH; HRR por O₂ y masa | https://publications.iafss.org/publications/fss/10/1263/view/fss_10-1263.pdf | enlace primario abierto; sin copia local | D1: ambas rutas existen en la familia experimental, pero no es mobiliario ni da fraccion transferible; 5 ACH = 15 % en resumen y 17 % en cuerpo |
| P1 | IAFSS / Yamada et al. | An Experimental Study of Ejected Flames and Combustion Efficiency | 2003 | Madera, PMMA y espuma flexible en recinto 1:7; masa, calorimetria y llamas exteriores | https://publications.iafss.org/publications/fss/7/903/view/fss_7-903.pdf | enlace primario abierto; sin copia local | D1: separa liberacion del combustible de lugar de combustion; no extrapolar escala |
| P2 | IAFSS / Pau et al. | Sensitivity of Heat of Reaction for Polyurethane Foams | 2014 | Termogravimetria y calorimetria bajo nitrogeno: descomposicion de espuma sin O₂ con calor impuesto | https://publications.iafss.org/publications/fss/11/179/view/fss_11-179.pdf | enlace primario abierto; sin copia local | D1: mecanismo posible, no tasa de un sofa en recinto |
| P1 | NIST | Experimental Study of the Three Dimensional Internal Structure of Underventilated Compartment Fires in an ISO 9705 Room (TN 1736) | 2012 | Mapas 3D de temperatura y especies | https://tsapps.nist.gov/publication/get_pdf.cfm?pub_id=908944 | `docs/literature/NIST/NIST_TN_1736_Three_Dimensional_Internal_Structure.pdf` | pendiente-descarga |
| P1 | NIST | Propane Gas Fire Experiments in Residential Scale Structures (TN 1953) | 2017 | Vivienda a escala real, ventilacion, PPV | https://doi.org/10.6028/NIST.TN.1953 | `docs/literature/NIST/NIST_TN_1953_Propane_Gas_Fire_Experiments_in_Residential_Scale_Structures.pdf` | pendiente-descarga |
| P1 | NIST | Report on Residential Fireground Field Experiments (TN 1661) | 2010 | Experimentos de campo residenciales | https://tsapps.nist.gov/publication/get_pdf.cfm?pub_id=904607 | `docs/literature/NIST/NIST_TN_1661_Residential_Fireground_Field_Experiments.pdf` | pendiente-descarga |
| P1 | Fire Safety Journal | Effects of HVAC on combustion-gas transport in residential structures | 2022 | `O2`, `CO2`, `H2O`, HVAC, puertas | https://www.sciencedirect.com/science/article/pii/S0379711222000121 | `docs/literature/Journals_OpenAccess/Effects_of_HVAC_on_Combustion_Gas_Transport_2022.pdf` | pendiente-descarga |
| P1 | Data in Brief / PMC | Experimental data from gas burner fires in residential structure with HVAC system | 2023 | Datos abiertos para validacion | https://pmc.ncbi.nlm.nih.gov/articles/PMC9792339/ | `docs/literature/Journals_OpenAccess/Experimental_Data_Gas_Burner_Fires_HVAC_2023.pdf` | pendiente-descarga |
| P1 | Fire Technology | Numerical Simulations of Gas Burner Experiments in a Residential Structure with HVAC System | 2023 | Validacion FDS con HVAC residencial | https://link.springer.com/article/10.1007/s10694-023-01390-y | `docs/literature/Journals_OpenAccess/Numerical_Simulations_Gas_Burner_Experiments_HVAC_2023.pdf` | pendiente-descarga |
| P1 | Fire Technology | Analysis of Changing Residential Fire Dynamics and Its Implications on Firefighter Operational Timeframes | 2012 | Modern fuel loads, tiempos operativos | https://link.springer.com/article/10.1007/s10694-011-0249-2 | `docs/literature/Journals_OpenAccess/Changing_Residential_Fire_Dynamics_2012.pdf` | pendiente-descarga |
| P2 | NIST | Air Moving Systems and Fire Protection (NISTIR 5227) | 1993 | HVAC y control de humo | https://doi.org/10.6028/NIST.IR.5227 | `docs/literature/NIST/NISTIR_5227_Air_Moving_Systems_and_Fire_Protection.pdf` | pendiente-descarga |
| P2 | NIST | Flow Induced by Fire in a Compartment | 1982 | Flujos en abertura, entrainment | https://tsapps.nist.gov/publication/get_pdf.cfm?pub_id=106938 | `docs/literature/NIST/Flow_Induced_by_Fire_in_a_Compartment_1982.pdf` | pendiente-descarga |
| P2 | NIST | CFAST - Consolidated Model of Fire Growth and Smoke Transport, Technical Reference Guide | 2004 | Ecuaciones de zona y base comparativa | https://doi.org/10.6028/NIST.sp.1030 | `docs/literature/Reviews_and_Models/CFAST_Technical_Reference_Guide_2004.pdf` | pendiente-descarga |
| P2 | OJP / FSRI | Impact of Fixed Ventilation on Fire Damage Patterns in Full-Scale Structures | 2019 | Patrones de dano, ventilacion fija, validacion | https://ojp.gov/library/publications/impact-fixed-ventilation-fire-damage-patterns-full-scale-structures | `docs/literature/FSRI_ULRI/Impact_of_Fixed_Ventilation_on_Fire_Damage_Patterns_2019.pdf` | pendiente-descarga |
| P2 | NIJ / FSRI | Evaluation of Heat Flux Profiles Through Walls in Support of Fire Model Validation | 2024 | Validacion de modelo, flujo termico y paredes | https://www.ojp.gov/pdffiles1/nij/grants/309047.pdf | `docs/literature/FSRI_ULRI/Evaluation_of_Heat_Flux_Profiles_Through_Walls_2024.pdf` | disponible |
| P2 | Fire Technology | Design Fire Characteristics for Probabilistic Assessments of Dwellings in England | 2020 | Design fires residenciales, sensibilidad | https://link.springer.com/article/10.1007/s10694-019-00925-6 | `docs/literature/Journals_OpenAccess/Design_Fire_Characteristics_for_Dwellings_2020.pdf` | pendiente-descarga |

## Priorizacion operativa

- `P1`: util para calibrar ya el modelo de gases, ventilacion, flashover y tenabilidad en vivienda.
- `P2`: util para extender validacion, dano termico, HVAC, y comparacion con modelos de referencia.

## Hipotesis de trabajo para Simufire

- El corpus `P1` deberia bastar para definir al menos tres familias de casos de validacion: `bedroom_fire`, `kitchen_living_room_fire`, y `ventilation_or_hvac_case`.
- Los estudios FSRI ofrecen benchmarks tacticos y de vivienda completa.
- Los documentos NIST aportan base fisica y datasets de compartimento subventilado necesarios para revisar yields, mezcla y transporte.
- Los articulos abiertos sobre HVAC y gases ayudan a cerrar la brecha que hoy tenemos entre humo temprano, agotamiento de oxigeno y comportamiento del incendio.
