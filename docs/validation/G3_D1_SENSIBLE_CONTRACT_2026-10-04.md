# G3/D1 - Contrato de entalpía sensible y almacenamiento

Fecha: 2026-10-04. Entrada: `c92eb904`, rama shareable integrada en main.
**Documento de diseño y verificación de fuente; implementación posterior aparte.**
Actualización posterior: [implementación sintética aislada](G3_D1_SENSIBLE_IMPLEMENTATION_2026-10-04.md).
La primera pieza ya está cerrada técnicamente: S01-S20 / 342 checks,
19/19 mutantes, referencia 346/346, producto 168/168 y global 3630 PASS.
Su cierre no autoriza el ledger sensible, la integración o una calibración.
Continúa el [gate térmico independiente](G3_D1_POOL_THERMAL_EVIDENCE_2026-10-04.md).

## 1. Decisión y orden ejecutable

GO al siguiente cambio concreto: **`sim/fire/SensibleEnthalpyModel.gd` puro,
aislado y primero sintético**, con una sola integral canónica de Cp(T).
Después, API sensible del ledger existente; después, propietario atómico
versionado. No implementar las tres piezas en un solo cambio ni duplicar
química. NO-GO a conectar al motor, inferir evaporación, reutilizar U/R,
importar muebles o activar CO/FED. La falta de B experimental no impide
implementar y falsar un contrato sintético; sí limita su aprobación física.

## 2. Fuente primaria: qué permite y qué no

Douglas, Furukawa, McCoskey y Ball, 1954, *Calorimetric Properties of
Normal Heptane From 0° to 520° K*, NBS Research Paper 2526:
[original oficial](https://nvlpubs.nist.gov/nistpubs/jres/53/jresv53n3p139_A1b.pdf),
[copia local](../literature/NIST/NBS_Heptane_Calorimetric_Properties_1954.pdf).
15 páginas, 17 614 982 bytes; SHA-256
`40138b0b81980477244431bd66c9b55adb775edbaf3d4e218f4f2d7b434bd3f9`.
`.gitattributes` declara PDF binario: este escaneado tiene metadatos XML
largos antes del primer NUL y el detector de diff lo confundía con texto.
Se verifica igualdad entre blob staged y bytes originales, sin normalizar.
Lectura focal/visual de pp.140,146-147,149,151-152; PDF = impresa - 138.
Datos [transcritos](G3_D1_HEPTANE_SENSIBLE_INPUTS_2026-10-04.json) y
[auditoría guardada](G3_D1_HEPTANE_SENSIBLE_AUDIT_2026-10-04.json).

| Evidencia | Clasificación |
| --- | --- |
| Tabla 5 / ecuaciones 5,8,9 | Csat y entalpía del líquido sobre saturación; dH incluye V*dP. No es un perfil Cp isobárico sin adaptación. |
| Ecuación 23 / tabla 10 | Cp del gas ideal; correlación ajustada, no medición de un incendio. Comprobación de nueve filas en escala nativa. |
| §2.1 | Escala internacional de 1948; referencia histórica 298,16 K, estado gas ideal a 1 atm. No convertir por un simple desplazamiento de 0,01 K. |

El chequeo de la ecuación 23 da DeltaH(298,16 -> 370) =
13 011,88953856 J/mol; el ajuste de tabla redondeada difiere como máximo
0,006 J/(mol*K) en Cp y 0,57953856 J/mol en DeltaH. Límites predeclarados
de consistencia de impresión: 0,02 y 2 respectivamente, **no incertidumbre
experimental ni tolerancias nuevas del motor**. Las ecuaciones 22/23
difieren -0,002236 J/(mol*K) en la unión impresa; no se fuerza continuidad.
No convertir mol a kg ni sustituir la referencia de TN 2126-upd1.
Propiedades a referencia y base nominal CHO siguen separadas; falta el
adaptador de escala/ruta/unidades para un perfil real compatible.

El [WebBook NIST](https://webbook.nist.gov/cgi/cbook.cgi?ID=C142825&Mask=FFFFFF)
localiza distintas mediciones; un Cp puntual no define Cp(T). No se archiva
ni redistribuye su compilación SRD completa. Tampoco se incorpora el otro
PDF de recopilación localizado, sin revisión/licencia de redistribución.

## 3. Primera pieza GDScript: propiedades, no paso físico

`SensibleEnthalpyModel.gd`, `RefCounted`, API estática:

- `validate_profile(profile: Variant) -> Dictionary`.
- `evaluate(profile: Variant, temperature_k: Variant) -> Dictionary`.

Sin estado persistente, tiempos, masa liberada, oxidación, B, Q, archivos,
preloads del motor, temperaturas ambientales globales o flags. Respuesta
rechazada: `valid=false`, errores y `candidate={}`. Respuesta válida:
`cp_kj_kg_k`, `specific_sensible_enthalpy_kj_kg`, identidad/rango/referencia,
`scope=synthetic_isobaric_property_not_material_calibration`; todas las
aprobaciones físicas e integración false. Copias profundas, entradas intactas.

Perfil cerrado, sin claves adicionales:

| Campo | Contrato del primer prototipo |
| --- | --- |
| schema | `g3_synthetic_isobaric_cp_v1` |
| component_id | cadena no vacía; no identidad de lote experimental |
| phase | `liquid` o `gas`; fase declarada, no predicha |
| caloric_model | `declared_liquid` para líquido, `ideal_gas` para gas |
| pressure_path | `constant_pressure` |
| reference_temperature_k | 298,15; referencia común del ledger futuro |
| reference_pressure_pa | 100 000; no presión del recinto en ejecución |
| temperature_scale | `synthetic_kelvin` |
| quantity / quantity_unit | `isobaric_specific_heat` / `kJ/(kg*K)` |
| interpolation | `piecewise_linear` |
| samples | lista >=2 de objetos exactos `{temperature_k, cp_kj_kg_k}` |
| provenance | cadena no vacía, explícitamente sintética |
| calibration_status | `synthetic_not_material_calibration` |

Temperatura positiva finita, Cp estrictamente positivo finito, orden
estrictamente creciente y referencia dentro del soporte. Rechazar bool,
NaN/infinito, unidades alternativas, claves ausentes/extra, fase/modelo
incompatibles, Csat, duplicados y desorden; no ordenar/recortar/extrapolar.
No admitir un perfil medido por cambiarle la etiqueta de calibración:
este esquema solo demuestra álgebra, no aprueba procedencia científica.

Cp lineal por tramo; integrar exactamente cada tramo recortado a [Tref,T]:
`Delta_h = (Cp(a)+Cp(b))*(b-a)/2`, sumando también tramos parciales.
Para T<Tref devolver el signo negativo, no clamp a cero; h(Tref)=0 exacto.
Cp en un nudo es único; en los extremos no se extrapola. Validar finitud
de operaciones/resultados y rechazar desbordamiento. Sin Lref incorporado
en esa integral, sin calor de combustión ni conversión molar dentro del API.
No pedir todavía inversión h->T ni una predicción de velocidad térmica.

Oráculos sintéticos predeclarados, sin tomar como patrón otra función .gd:

| Perfil en kJ/(kg*K), temperaturas K | T consultada | s esperada kJ/kg |
| --- | ---: | ---: |
| Cp=2, soporte 273,15-373,15 | 273,15 / 298,15 / 348,15 | -50 / 0 / 100 |
| Cp=2+0,01*(T-298,15), mismo soporte | 273,15 / 323,15 | -46,875 / 53,125 |
| Nudos (298,15;1), (348,15;3), (398,15;2) | 373,15 / 398,15 | 168,75 / 225 |

Estos números prueban la integral, no una propiedad del heptano.
Usar 1e-9 kJ/kg absoluto + 1e-12 relativo en la fixture analítica,
sin cambiar tolerancias del motor ni confundirlas con incertidumbre de datos.

## 4. Contrato del ledger posterior, no autorizado en este primer cambio

Mantener **A** (potencial químico/de fase de referencia), **S** (sensible
del combustible), **B** (presupuesto térmico independiente) y **Q** (energía
entregada al reservorio receptor) separados. `A + S + B + Q` es aquí una
cuenta de **entalpía a presión declarada**, no energía interna del gas zonal.
No escribirla en la EOS: gas compresible requiere distinguir h de u y
trabajo pV/flujo antes de integrar. No usar Cp como Cv por conveniencia.

S = m_liq*s_liq + m_vap*s_vap; s(Tref)=0. S puede ser negativa.
Al calentar sin cambiar masa: DeltaS positivo se debita una vez de B.
Para r kg de líquido a temperatura Tl y vapor emitido a Tv declaradas:

`C_release = r * [Lref + s_v(Tv) - s_l(Tl)]`.

DeltaA = r*Lref; DeltaS = r*[s_v(Tv)-s_l(Tl)]; DeltaB = -C_release.
Comprobar el total, no solo los balances separados. El alcance inicial
requiere coste positivo y estado dentro de perfiles válidos; coste no
positivo exige otro contrato físico, nunca dividir por él o usar abs().
Masa aceptada limitada por inventario y B previo a oxidar, igual que ahora;
no financiar este paso con Q producido en él. B insuficiente no reproduce
automáticamente toda la pérdida de masa prescrita: déficit explícito.

Si vapor nuevo se mezcla con vapor previo, conservar la **suma de entalpías
sensibles**, no promediar temperaturas. Llevar S_v como cuenta y, en fase
posterior, derivar T del Cp canónico. Oxidar b kg de vapor homogéneo retira
su sensible proporcional y lo entrega al reservorio junto con b*q_vap.
Oxidación/O2/productos siguen en `FuelMassBudgetModel`, sin otra química.
Oxidante/productos a referencia en este primer contrato: Q es energía hacia
ese reservorio, no HRR químico ni temperatura real de llama. Oxígeno caliente
y productos calientes requieren sus propios términos antes de generalizar.
Una fase ausente tiene masa/S cero y T no definida; no se le inventa
temperatura ni se borra una entalpía finita por un umbral de masa pequeño.

Se añadirá una API versionada al núcleo existente, no una segunda ley de
masas. No invocar `propose_phase_reference` con Lref falsificado para
simular sensible: rompería el vínculo q_vap=q_liq+Lref. v1/reference siguen
byte idénticos y congelados durante la primera pieza de propiedades.

## 5. Propietario posterior y límite del caller actual

`PrescribedPhaseBudgetController` recompone historia desde masa aceptada
acumulada a referencia. **Eso deja de bastar cuando varían temperaturas**:
igual masa puede haber requerido distintos calentamientos/costes. No añadir
dos campos y dar su restore por correcto. Sucesor versionado, con cuentas
de calentamiento/transferencia/sensible y presupuesto acumulados vinculados
a contexto, generaciones y estado; verificaciones canónicas sin duplicar
la integral o la estequiometría. Fuente y reloj físico siguen separados.
Queda para otra etapa tras el ledger sensible, sin carga desde producto.

## 6. Falsación predeclarada de la primera pieza

| Grupo | Fixture GDScript que deberá probarlo |
| --- | --- |
| S01-S04 | Cp constante/lineal, referencia cero y signo por debajo |
| S05-S08 | Varios tramos, nudos/extremos, tramo parcial, subdivisión |
| S09-S12 | Esquema/tipos/unidades, orden/duplicados, Cp no positivo, rango |
| S13-S16 | No finitos/desbordamiento, fase/modelo, presión/ref, Csat rechazado |
| S17-S20 | Inmutabilidad/copia profunda, sin autoridad, precisión analítica, perfiles independientes |

20 grupos, recuento de comprobaciones determinado por la fixture, no
inventado en este diseño. Mutantes obligatorios: omitir sustracción de
referencia; perder signo; sustituir integral por Cp(T)*(T-Tref); omitir
tramo parcial/intermedio; extrapolar; admitir Cp cero/negativo, bool o NaN;
ordenar duplicados; confundir unidades/Csat; compartir copia; añadir Lref;
alterar la referencia. Declarar anclas válidas antes de ejecutar campaña.
No contar errores de sintaxis/launcher como muertes. Concretar oráculos
analíticos independientes en Python antes de implementar .gd.

## 7. Verificación y siguiente ejecución

Auditor offline: ecuación/tabla de gas en escala nativa, no simulación,
sin modificar entradas ni informes. No mide B, pérdidas o temperaturas de
ISOHept9 ni se convierte automáticamente en perfil material.
Primera focal de fuentes sensible/piscina/fases: **113 PASS**, incluidas
**30 nuevas**, exit 0, 1,24 s, basetemp externo nuevo. Regresión ampliada
final con emisión y masa: **161 PASS**, exit 0, 1,96 s, otro basetemp externo.
Auditor reproduce resultado guardado;
controles negativos de atribución, extrapolación, finitud y signos, no
mutantes de GDScript. ALL GUARDRAILS PASS (R2-1 incluido), estilo PASS;
enlaces de cuatro documentos PASS, manifiesto válido con 43 entradas y
diff limpio. Sin repetir una suite global ni atribuirle los tests añadidos.
No Godot ni cambios de `sim/`; no referencia/producto/global nuevos
en este gate de diseño. La cadena previa pertenece a `c92eb904` y anteriores.

**Siguiente ejecución al cerrar este diseño (histórico):** implementar solo `SensibleEnthalpyModel.gd` y
fixture S01-S20; controles analíticos, mutaciones, aislamiento y preservación
de los tres módulos anteriores. Al tocar `sim/`, cerrar R2-1 por monitor,
producto y global secuencialmente con memoria suficiente. No integrar el
ledger sensible o su caller todavía. Este orden reduce el riesgo sin
presentar el cierre sintético como validación del incendio completo.
