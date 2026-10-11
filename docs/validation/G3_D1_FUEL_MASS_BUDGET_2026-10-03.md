# G3-D1 — núcleo puro de masa y energía

Estado 2026-10-03: **núcleo técnico implementado y validado, sin integración**.
No es calibración material ni corrección de
CO/FED de producto. Continúa el [contrato D1](G3_D1_IDENTIDAD_INQUEMADO_2026-10-03.md).
Rama `codex/g3-fed-co-zonal-shareable`, HEAD `cbab7b05`; trabajo anterior
preservado, checkout principal fuera de alcance. Sin commit ni push.

## GDScript y contrato

`sim/fire/FuelMassBudgetModel.gd`: función estática pura
`propose(state, request, material)`, sin motor, nodos, archivos, aleatoriedad
ni escritura sobre entradas. Producto no lo carga; un test fija ese límite.
Recibe por separado **liberación y oxidación en kg/paso**, acepta únicamente
lo disponible y devuelve lo rechazado y un candidato nuevo.

| Entrada | Base y campos |
|---|---|
| Estado | `initial_fuel_mass_kg`, `solid_fuel_kg`, `released_fuel_kg`, `o2_kg`. Inventario restante <= inicial; nunca kg inferidos desde MJ. |
| Solicitud | `dt_s`, `release_kg`, `oxidation_kg`, `release_mode`. Paso cero no transfiere ni oxida. |
| Material | Fracciones másicas C/H/O que suman uno, `chemical_heat_kj_per_kg` positivo, base `complete_oxidation_net` y procedencia no vacía. La etiqueta no verifica una fuente. |
| Modo prescrito | `prescribed_mass_transfer`: condición de contorno impuesta, no predicción térmica; no admite parámetros térmicos que se ignorarían. |
| Modo térmico | `thermal_budgeted`: requiere Hgas positivo y presupuesto `release_heat_budget_kj` explícito; limita emisión por presupuesto/Hgas. No reutiliza calor de oxidación producido en el mismo paso. |

Alcance: un componente CHO con masas atómicas **nominales** 12/1/16 y
oxidación completa a CO₂ y vapor de agua. No humedad inicial, char, goteo,
reacción superficial, oxidación parcial, CO/HCN, transporte ni ignición.
Rechaza composiciones sin requerimiento positivo de O₂ o elementos no
soportados. Igual energía química específica en sólido y liberado es una
**simplificación declarada**, no evidencia experimental. El coste de
liberación se devuelve como consumo de un presupuesto térmico externo;
su destino físico necesita otro contrato antes de integración.

```text
O2 requerido/kg = (8/3)c + 8h - o
CO2/kg oxidado = (11/3)c; H2O/kg oxidado = 9h
liberación = min(solicitud, sólido, límite térmico si aplica)
oxidación = min(solicitud, liberado previo + liberación, O2/requerido)
calor = masa oxidada * energía química específica declarada
```

Devuelve kg/productos/O₂/calor/coste/presupuesto restante, estados químicos
y residuos de masa, C/H/O y presupuestos energéticos. Productos incluyen
masa de oxidante. Entradas inválidas, bases ambiguas o desbordamientos dan
errores explícitos y candidato vacío. Los caps conservan el último ulp.
U/R permanecen separados y no financian ni alimentan este núcleo.

Tolerancias fijadas antes de ejecutar Godot: masa `1e-12 kg`, energía
`1e-9 kJ`, más relativo `1e-12`; suma de composición a `1e-12`.
Fixtures nominales de 0–10 kg y 0–200 000 kJ. Son precisión aritmética,
no incertidumbre experimental ni parámetros físicos.

## Evidencia y pendientes

`tests/fixtures/g3_fuel_mass_budget.gd` ejecutó el GDScript real y
reconstruyó balances desde entradas/salidas, sin confiar solo en los
residuos que el núcleo informa. Cubre: igual calor/distinta emisión,
O₂ ausente/abundante/limitante, sólido agotado con gas restante, inventario
vacío, solicitudes excesivas, paso cero, coste térmico limitado/nulo,
componentes CHO sintéticos, datos inválidos/no finitos/ausentes, HOC efectivo
rechazado, desbordamiento, determinismo y ausencia de mutación de entradas.
No se atribuyen esos casos a sofás o materiales medidos.

`run_g3_fuel_mass_budget_mutations.py`: control y diez mutantes en proyectos
copiados en `runs/`, por monitor y con >= 6 GiB. No toca el original; retiene
hashes, logs y salud. Errores de sintaxis/runtime o infraestructura no
cuentan como bajas válidas.

| Mutante | Fallo que debe detectarse |
|---|---|
| M01/M02 | Débito sólido ausente / emisión duplicada |
| M03/M04 | Oxidar sin O₂ / calor de masa no oxidada |
| M05 | Productos sin masa de oxidante |
| M06/M07 | Emisión sin presupuesto térmico / coste omitido |
| M08/M09 | Admitir HOC efectivo como químico / permitir un campo MJ ajeno al esquema |
| M10 | Emisión durante paso cero |

M09 comprueba una entrada con kg declarados **y** el campo extra
`fuel_energy_MJ`; no simula una conversión de MJ a kg. La ausencia de lectura
de cuentas heredadas se verifica también estáticamente. No puede detectar
una conversión falsa hecha por un futuro caller fuera del núcleo.

## Cadena ejecutada sobre el código final

Memoria liberada de 3,19/~3,00 a 6,65 GiB antes de Godot; referencia con
6,5–7,37 GiB antes de los casos. Tandas secuenciales y por monitor.
APPDATA/TEMP/TMP del padre y basetemp externos. El arnés existente
`tests/godot_runtime_launcher.py` fuerza para sus fixtures APPDATA a
`runs/godot_test_appdata`; no se ha cambiado ni se presenta como externo.

| Comprobación | Resultado |
|---|---|
| Estáticos tempranos | 26 PASS, dinámica excluida; no sirvieron para cerrar |
| Focalizada con GDScript real | 11 PASS; fixture 271 comprobaciones, 39 grupos |
| Mutaciones aisladas | Control PASS y 10/10 bajas válidas, sin sintaxis/runtime; original intacto |
| Referencia completa | 18/18 limpios, 346/346 required PASS, 78 gaps |
| Informes de caso | 18/18 idénticos byte a byte al checkpoint copiado |
| `reference_checks.json` | Diff normalizado: solo `generated_at`, 01:27:26Z → 09:00:34Z del 03-10 |
| Guardarraíles | ALL PASS, R2-1 incluido |
| Producto | 168/168, 81 lanzamientos, cero fallos de infraestructura |
| Global autoritativa | 3323 passed, 37 skipped, 2 xfailed, 42 subtests passed; exit 0, 497,69 s |

Evidencia local, sin incluir `runs/` en un commit:

- `runs/g3_d1_mass_mutations_20261003_100933/`: resultados, logs, salud y hashes.
- `runs/reference_suite_monitored_20261003_101118/`: casos, comparador y guards.
- Temporales: `C:/Users/dangp/AppData/Local/Temp/simufire_d1_kernel_dynamic_20261003_01/`.
- Modelo SHA-256: `783c13166fe9e263b470dd76b736114a6ee9e909dae27dc62ca4f6f5febcde82`.
- Fixture SHA-256: `9fdb5fbaf6137f5b387d1e30f518f7afc094839899191a497ae0405f4788b33e`.

El checker de estilo existente pasa, pero no cubre este `sim/fire`; su
compilación la demuestra la fixture real. Ninguna tolerancia o ley se cambió
tras las corridas. Tests fijan 271/39 y ausencia de carga desde producto y
`project.godot`.

## Decisión y siguiente tramo

**GO técnico al núcleo aislado**, no a una física de muebles o CO/FED.
Preparar el contrato del proveedor de masa/material con procedencia y
distinción tasa prescrita/predicha. No completar kg desde U/R ni importar
HOC efectivo como químico; no migrar los 107 objetos sin datos.
La integración requiere especie combustible y propiedades de gas, destino
zonal, coste térmico y una única fuente/débito en el aplicador canónico.
El núcleo no resuelve esas fronteras ni el gate científico de U, que sigue
en NO-GO; tampoco calibración, transporte, ignición o CO/FED.

Continuación del 03-10: el
[contrato offline del proveedor](G3_D1_MASS_MATERIAL_PROVIDER_CONTRACT_2026-10-03.md)
está escrito y probado (46 nuevas / 62 conjuntas estáticas). No cambia este
núcleo ni importa perfiles reales. El siguiente tramo es el proveedor por
intervalo y una fixture conjunta aislada; revisión material e integración
siguen pendientes.

Continuación posterior: el
[proveedor prescrito y la fixture conjunta](G3_D1_PRESCRIBED_RELEASE_2026-10-03.md)
están cerrados técnicamente con nueva referencia/global completa. Este
núcleo conserva su hash; no se integra ni calibra. Siguiente: benchmark
experimental de masa independiente antes de perfiles reales/integración.

Los archivos nuevos sin seguimiento pueden no aparecer en la frescura
basada en diff de Git: se regeneró la referencia completa, sin exención
por módulo no integrado.

No cambian interruptores ni escenarios. Sin commit ni push solicitado en
este tramo.
