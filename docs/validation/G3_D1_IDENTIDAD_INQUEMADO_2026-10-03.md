# G3-D1 — identidad física del combustible no quemado

Estado (2026-10-03): **diagnóstico y núcleo aislado cerrados técnicamente,
sin integración** ([evidencia](G3_D1_FUEL_MASS_BUDGET_2026-10-03.md)).
**NO-GO para asignar identidad física a U**.
G3-4A permanece como cuenta energética en MJ (physical_inventory:
false), OFF por defecto. No es masa, gas ni combustible recuperable. Esta
revisión no cambia la simulación activa ni enciende CO/FED.

## Qué representa el motor hoy

- En explicit_objects, CombustionSystem._g3_apply_owned descuenta burn_MJ del
  objeto cuando confirma el paso, incluso si una parte no libera calor. La
  parte no quemada queda registrada como U, sin alterar ese débito. Es un
  **residuo de contabilidad del algoritmo**, no una observación de pirólisis.
- La mayoría de los objetos no declara calor de combustión utilizable: el
  valor por defecto es −1; solo cuatro objetos de dos casos de validación lo
  declaran (§16.4 del diseño). El factor global de backdraft de
  10 000 kJ/kg carece de fuente material. No se pueden deducir kg ni
  especies a partir de U en MJ.

## Evidencia primaria y alcance

| Fuente | Qué se midió o modeló | Qué permite afirmar para D1 | Lo que **no** permite |
|---|---|---|---|
| [CFAST, NIST TN 1889v1, §3.2](https://nvlpubs.nist.gov/nistpubs/TechnicalNotes/NIST.TN.1889v1.pdf) | Su especificación prescribe la pirólisis y, al limitar O₂, mantiene esa tasa y transporta combustible no quemado por pluma y aberturas. | Existe un precedente de **modelo A** coherente internamente. | No mide ni predice la tasa real de pérdida de masa de un sofá subventilado. |
| [Pau et al. (2014), espuma de poliuretano](https://publications.iafss.org/publications/fss/11/179/view/fss_11-179.pdf) | Termogravimetría/calorimetría de espuma y fundido bajo nitrógeno con calentamiento impuesto. Hay pérdida de masa por descomposición sin O₂. | La ausencia de oxígeno **no obliga** a que toda la masa permanezca en el sólido si recibe calor. | Ensayo pequeño y térmicamente impuesto; no da la tasa en un recinto ni un sofá completo. |
| [Peatross y Beyler (1997)](https://publications.iafss.org/publications/fss/5/403/view/fss_5-403.pdf) | 24 ensayos de recinto: diésel, cunas de madera y placas de poliuretano; célula de carga, O₂ local y ventilación variable. Menor O₂ en la base acompañó menor pérdida de masa; en placas de poliuretano y bandejas, las temperaturas de capa superior eran próximas entre ventilaciones. | La tasa de liberación de combustible del objeto **puede cambiar** con la ventilación; mantenerla fija no es ley universal. | La pérdida de masa no separa por sí sola volátiles, char, hollín y oxidación superficial; no entrega una ley calibrada por mueble. |
| [Aljumaiah et al. (2011)](https://publications.iafss.org/publications/fss/10/1263/view/fss_10-1263.pdf) | Cunas de pino de 4,6–4,8 kg en un recinto de 1,6 m³, 3–37 renovaciones/h; célula de carga, HRR por O₂ y CO/hidrocarburos. A 3 renovaciones/h el fuego se autoextinguió; a 5 solo se consumió aproximadamente 15–17 % de la masa inicial. A 11–37 hubo combustión rica y salidas de CO e hidrocarburos no quemados. A 37, el pico estimado desde masa fue 170 kW frente a 50 kW medidos por consumo de O₂. | En la misma familia experimental existen **masa que permanece en el combustible** y **masa que sale sin oxidarse totalmente**; la ventilación condiciona ambas rutas. | Cuna de madera y ventilación forzada, no sofá residencial; los resultados a 5 y 11–37 renovaciones/h son condiciones distintas, no una fracción universal simultánea. El resumen da 15 % y el cuerpo 17 % para 5 renovaciones/h; los 170 kW presuponen combustión completa de la masa perdida. |
| [Yamada et al. (2003)](https://publications.iafss.org/publications/fss/7/903/view/fss_7-903.pdf) | Recinto a escala 1:7 con madera, PMMA y espuma flexible; pérdida de masa, calorimetría y llamas que salen por la abertura. | En combustibles sólidos puede salir combustible y quemarse fuera; HRR interior no determina por sí solo cuánto abandonó el sólido. | Escala y geometría reducidas; no ofrece un reparto aplicable directamente a muebles reales. |
| [NIST TN 1603 (2008)](https://nvlpubs.nist.gov/nistpubs/Legacy/TN/nbstechnicalnote1603.pdf) | Sala ISO 9705 subventilada con combustibles definidos. Con puerta a 1/8 y heptano, al subir el HRR ideal de 750 a 1500 kW la fracción que ardió fuera pasó de 0 a cerca de 60 %. Para tolueno, polipropileno y poliestireno se midieron pocos hidrocarburos sin quemar en la capa superior; el carbono apareció principalmente como CO, CO₂ y hollín. | La energía no liberada **dentro** no equivale necesariamente a un depósito de hidrocarburo gaseoso: importan el lugar de oxidación y las especies. | El 60 % es de un caso de heptano pulverizado, no una regla para muebles ni para el inventario U. |
| [NIST TN 2303 (2025)](https://nvlpubs.nist.gov/nistpubs/TechnicalNotes/NIST.TN.2303.pdf) | Ensayos de objetos residenciales y de oficina en abierto y plenamente ventilados; masa, HRR, CO y hollín. | Base de propiedades y curva ventilada para tipos de objeto. | No resuelve el reparto de fases ni la evolución subventilada. |

Los PDF de TN 1889v1, TN 1603 y TN 2303 ya constan en la biblioteca local;
los trabajos IAFSS se enlazan en el índice bibliográfico sin fingir que son
copias locales. No se importan parámetros de una configuración a otra.

## Inferencia y decisión revisada

La recomendación anterior «**todo U es gas pirolizado**» queda **retirada**.
Era coherente con el débito actual y con CFAST, pero la evidencia no la
valida para todos los objetos. La alternativa contraria «todo U permanece
en el sólido» tampoco explica los volátiles, CO y otros productos
combustibles que salen sin liberar toda su energía en la sala.

Las dos rutas pueden coexistir y variar con material, geometría, historia
térmica y ventilación. Además, la descomposición del objeto no es idéntica
a gas combustible disponible: puede dejar char en el objeto, emitir
volátiles, CO y hollín, y parte de lo emitido puede arder fuera de la sala.
**U no mide ninguna de esas
particiones.** Es una inferencia de las fuentes, no una nueva ley del motor.

El contrato físico mínimo, si se decide modelarlo, necesita distinguir:

1. masa aún en el objeto (incluidos residuos sólidos/char declarados);
2. masa que sale del objeto por pirólisis, goteo u otra ruta modelada;
3. de esa masa, lo que se oxida localmente, lo que queda como especies
   combustibles y lo que sale por las aberturas;
4. calor liberado **en cada lugar**, O₂ consumido, especies y carbono.

La tasa de salida del objeto y la eficiencia/lugar de oxidación son procesos
separados. Una simplificación tipo CFAST, con pirólisis prescrita, podría ser
una **decisión explícita de alcance** para ciertos casos, pero no debe
presentarse como hecho experimental ni convertir U entero a gas por defecto.

## Gate para continuar

**NO-GO** para convertir U en kg, sumarlo a una zona o permitirle arder.
Antes hay que fijar un contrato de masa por objeto y una matriz de casos con
al menos pérdida de masa/residuo sólido, HRR interior y exterior, O₂ local,
CO/CO₂/hidrocarburos y, si se pretende cerrar carbono, hollín/char. Separar
validación de madera, espuma y muebles compuestos; no calibrar sofás con el
heptano de TN 1603. Los datos de TN 2303 solo sirven como base ventilada.

Ese diagnóstico se ha realizado y se documenta debajo. No se ha implementado
una ley de pirólisis ni de especies. El núcleo puro de balance en GDScript
se implementó y validó según §Contrato mínimo, sin integrarlo ni atribuir
sus entradas sintéticas a muebles reales. CO/FED siguen en NO-GO.

## Diagnóstico reproducible del motor

Checkpoint: `codex/g3-fed-co-zonal-shareable`, HEAD `cbab7b05`. Auditoría
estática sobre código y declaraciones JSON, sin ejecutar Godot. Se conserva
el trabajo documental anterior y no se toca el checkout principal.

Inventario completo, con JSON pointers y SHA-256 de cada archivo:
[G3_D1_DECLARED_MASS_INPUTS_2026-10-03.json](G3_D1_DECLARED_MASS_INPUTS_2026-10-03.json).
Se reproduce con:

```powershell
python scripts/simulation/audit_g3_d1_mass_identifiability.py
```

Los hashes son de bytes físicos de este checkout, no hashes canónicos de
procedencia de la suite de referencia. Se cuentan declaraciones, **no**
objetos añadidos por plantillas en tiempo de ejecución; presencia de un
campo no acredita fuente, unidades válidas ni soporte del cargador.

| Declaraciones revisadas | JSON | Objetos | CO kg/MJ | Hgas y Hcomb | Masa inicial/restante, MLR temporal, composición o base de Hcomb |
|---|---:|---:|---:|---:|---:|
| `scenarios/*.json` | 14 | 107 en 7 archivos | 107 | 0 | 0 |
| `sim/validation/cases/*.json` | 101 | 14 en 9 archivos | 14 | 4 | 0 |

Los cuatro valores de Hcomb son: `wood_panel_char` (17 500 kJ/kg),
`pasillo_alfombra_pu` (26 200 kJ/kg), `pasillo_mueble_madera` y
`pasillo_resto_madera` (17 500 kJ/kg). Están en `char_layer_loi_wood.json`
y `secondary_ignition_demo.json`. No son cuatro mediciones nuevas ni una
calibración experimental demostrada en esta revisión.

| Camino real inspeccionado | Qué existe | Qué falta o qué no demuestra |
|---|---|---|
| `FuelObjectModel.gd`, definición y `reset_dynamic_state` | Inventario MJ, HRR, temperatura, flujo recibido, Hgas/Hcomb opcionales y rendimientos kg/MJ. Char como espesor; líquidos como área de pool. | Inventario de masa del objeto/residuo; flujo emitido persistente; composición y base experimental de la energía. Espesor no es masa de char; área no es masa de líquido. |
| `BuildingModel.gd`, `_build_fuel_objects` | Carga esos parámetros energéticos y térmicos. | No carga un contrato de masa/composición/MLR medida. Añadir campos al JSON por sí solo no cambia el motor. |
| `CombustionSystem.gd`, líneas 2980–3016 | Calcula localmente `mlr_kg_s = qnet * A / Hgas` y lo convierte a HRR limitado durante preignición, si hay parámetros positivos. | No conserva ese caudal como emisión ni descuenta kg; el guard LOI puede impedir esta rama aunque exista calentamiento. No es una predicción de pirólisis sin O₂ validada. |
| `_g3_object_weight`, líneas 4376–4416 | La misma forma de MLR interviene como **peso relativo**; t²/curva HRR tienen precedencia. | No determina el total que sale del objeto. Aquí no se aplica la atenuación por char de la rama anterior. No se ha corregido ni validado esa diferencia. |
| Ruta G3, líneas 1738, 1799 y `_g3_allocate_owned` | Demanda energética calculada desde HRR ideal de sala y reparto entre objetos activos con topes. | No es una suma de tasas independientes de pérdida de masa de objetos. La extinción por O₂ puede anular también la demanda de pirólisis. |
| `_g3_apply_owned`, líneas 4720–4733 | Debita MJ, anota U y aumenta espesor de char con un equivalente `MJ/Hcomb`. | No acredita fase, kg emitidos ni carbono del char. No autoriza reutilizar esa conversión como emisión real. |
| `SimulationStateBuilder.gd`, `_build_fuel_object_snapshots` | Exporta estado energético/térmico y Hgas/Hcomb. | No hay estado de masa por objeto que observar desde este snapshot. |
| `Phase3ZoneMassSystem.gd`, `PARCEL_SPECIES` y fuente canónica de combustión | Sí existen inventarios/transportes de gas y especies zonales; la lista incluye CO, CO₂, HCN, humo e irritantes. | Esa lista no incluye combustible volátil genérico. La fuente canónica recibe productos kg calculados desde MJ; no prueba un débito de masa desde el objeto ni cierre elemental completo. |

Esta conclusión es acotada: **no** dice que el motor carezca de toda masa.
Dice que la ruta inspeccionada no enlaza un inventario de masa del objeto
con masa emitida y oxidada. Los balances zonales existentes no cubren por
sí solos ese origen físico.

## Por qué HRR, O₂ y U no identifican la masa

Contraejemplo algebraico, **sintético, no calibración**: con Hc supuesto de
20 000 kJ/kg, un HRR de 50 kW puede corresponder a 0,0025 kg/s liberados y
oxidación completa, o a 0,005 kg/s liberados con eficiencia energética 0,5.
Ambos satisfacen `Q = eta * Hc * mlr`; la masa emitida es distinta. Si además
O₂ se calcula desde Q con un factor fijo, tampoco aporta una medición
independiente. En condiciones reales hay más incógnitas: composición,
oxidación parcial, calor fuera de sala y residuo sólido.

La cuenta U no elimina esa indeterminación: procede del reparto energético
actual, no de medir masa o fases. Tampoco se debe usar como condición inicial
de un futuro inventario físico. Los valores de §16.7 del diseño son
resultados previos, no una campaña nueva ejecutada en esta revisión.

## Qué datos contrastan cada término

| Término a contrastar | Evidencia candidata ya localizada | Limitación que conserva el gate |
|---|---|---|
| Masa inicial y residuo final de objetos ventilados | TN 2303, tablas y descripciones de espécimen. | Separar cojines/ignitores y masa inerte de masa combustible; no reconstruir fases solo del total. |
| Pérdida de masa temporal de objetos | TN 2303, gráficos de Tests 1–24. | No se dispone aquí de serie numérica cruda; los sofás 29/30 no tienen ese registro temporal en el informe. Digitalizar sería un producto derivado con incertidumbre propia. |
| Respuesta a ventilación y O₂ | Peatross/Beyler y Aljumaiah: masa, O₂ y HRR en sus configuraciones. | Materiales/escala/ventilación concretos; no transferir una fracción a todo mueble. |
| Energía y productos que salen o arden fuera | Yamada, TN 1603 y Aljumaiah. | HRR del escape no es automáticamente HRR interior; faltan todas las rutas para cerrar fases/elementos en un sofá. |
| Pirólisis con calor y sin O₂ | Pau: espuma/fundido bajo N₂. | Demuestra que el proceso existe, no una ley de tasa para objetos completos. |
| CO/CO₂/HCN y hollín | TN 2303 y fuentes de elegibilidad G3-2, con sus bases y regímenes separados. | No se declara validada `Y_CO(t)` por objeto ni su extensión a subventilación. |

**Base de energía:** TN 2303 §2.2.1 y tabla 6 llama al parámetro *net
effective heat of combustion*, calculado a partir de calor liberado y masa
perdida en el ensayo. Se distingue de una energía química declarada para
combustión completa y de Hgas. Inferencia para el diseño: no importar ese
HOC efectivo como energía química de volátiles y multiplicarlo otra vez
por una eficiencia sin explicar la base. El cargador actual no declara
esa distinción. [Fuente primaria](https://nvlpubs.nist.gov/nistpubs/TechnicalNotes/NIST.TN.2303.pdf).

## Contrato mínimo (núcleo ya implementado y validado)

**GO técnico** para un núcleo puro, sin cargarlo desde `SimulationEngine`.
**NO-GO científico** para una ley material, integración/producto, conversión
de U o calibración CO/FED. Son decisiones distintas: se puede verificar el
balance antes de disponer de una ley predictiva de muebles compuestos.

1. Crear `sim/fire/FuelMassBudgetModel.gd` (hecho y validado) con entrada y propuesta de salida
   explícitas, sin escribir `RoomModel`, `FuelObjectModel` ni estados globales.
   Primera versión: un componente combustible, sin char, humedad, goteo ni
   reacción superficial; esas exclusiones deben figurar en el resultado.
   No presentarla como modelo de madera ni de sofá compuesto.
2. Entradas independientes: kg iniciales/restantes de sólido y combustible
   liberado, solicitud de liberación kg/paso, solicitud de oxidación kg/paso,
   inventario O₂, composición/estequiometría y energía química con base
   declarada. Si se exige coste térmico de liberación, declarar además Hgas
   y el presupuesto térmico que lo paga; no tomar energía de U o R.
3. Separar conservación de ley constitutiva. La primera fixture impone los
   flujos; el núcleo solo acepta cantidades disponibles y devuelve lo
   rechazado. No inferir MLR de HRR, ni llamar a una curva HRR «MLR medida».
   Una ley térmica o una curva MLR con procedencia será un proveedor posterior.
4. Propuesta atómica: masa que permanece, masa liberada, masa oxidada,
   combustible no oxidado, O₂ debitado, productos y calor local. Auditar
   elementos según composición declarada y recordar que masa de productos
   incluye O₂: no puede igualarse solo a la masa de combustible. Distinguir
   energía química retenida, liberada y convertida en calor; si hay coste de
   pirólisis, cerrar también su presupuesto térmico explícito.
5. No transportar ni encender todavía ese combustible. Rechazar entradas
   sin base material en vez de completar kg desde `fuel_energy_MJ`; mantener
   U/R como cuentas históricas separadas. La integración posterior requerirá
   contrato de especies/zona y una única fuente de masa para evitar duplicados.

Controles predeclarados para el núcleo:

- Igual calor con distinta liberación/oxidación deja distinta masa no oxidada;
  se mantiene el contraejemplo de arriba, no se fuerza un resultado único.
- Liberación impuesta con O₂ cero puede transferir masa de sólido a liberado,
  pero no oxidarla ni producir calor de oxidación; no afirma que la tasa
  impuesta sea la real sin un proveedor térmico y su energía.
- O₂ abundante, O₂ limitante, sólido agotado, combustible liberado agotado,
  paso cero, datos negativos/no finitos y propiedad material ausente.
- Balance por paso de masa total (incluye oxidante), elementos y energía
  declarada; no negatividad y propuesta sin efectos laterales.
- Mutaciones que omitan el débito sólido, dupliquen emisión, oxiden sin O₂,
  pierdan energía química o inventen una conversión desde U deben fallar.

Antes de implementar, fijar tolerancias numéricas desde la escala de las
fixtures y precisión, no desde el resultado candidato. Si se toca `sim/`,
aplicar R2-1, referencia completa por monitor, guardarraíles, producto y
pytest secuenciales; no iniciar Godot con memoria insuficiente. Este núcleo
aislado no necesita un interruptor activo porque no se integra; cualquier
integración física futura será OFF por defecto y exigirá identidad OFF.

## Verificación de la revisión estática anterior

- Auditor estático reproducible; informe con 115 JSON y cinco hashes de código.
- Seis pruebas del auditor PASS, sin Godot: declaraciones en overrides y
  salas, rechazo de estructuras inválidas, ausencia de conversión implícita,
  repetibilidad y detección de cambios reales de contenido.
- Auditor nuevo e inventario G3 existente: 16 pruebas estáticas PASS.
  Informe archivado idéntico al emitido al normalizar finales de línea;
  enlaces Markdown y `git diff --check` limpios.
- Dos intentos de pytest en sandbox dieron error de permisos de su carpeta
  temporal (4 pruebas pasaron y 2 no se ejecutaron); no se cuentan como suite
  válida. La repetición fuera del sandbox pasó 6/6.
- Sin cambios de comportamiento, parámetros, interruptores ni escenarios.
  No se regeneró la referencia ni se atribuyen a esta revisión sus resultados
  anteriores. Sin commit ni push en este tramo.
