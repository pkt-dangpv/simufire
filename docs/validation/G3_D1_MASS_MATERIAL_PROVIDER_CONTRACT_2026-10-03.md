# G3-D1 — contrato del proveedor de masa y material

Estado (2026-10-03): **contrato offline verificable**, sin proveedor conectado
al motor, sin perfil experimental aprobado y sin activación de producto.
Continúa el [núcleo de balance](G3_D1_FUEL_MASS_BUDGET_2026-10-03.md).
Rama `codex/g3-fed-co-zonal-shareable`, HEAD `cbab7b05`; checkout principal
fuera de alcance. Sin commit ni push.

## Decisión y alcance

La conservación del núcleo no identifica por sí sola sus entradas. Separar
cuatro decisiones: contrato válido, dato atribuible al componente, ley
adecuada al régimen y aprobación de producto. El validador solo cierra la
primera y verifica presencia/hash de la evidencia local, no su contenido.

Primera versión: **tasa de emisión prescrita** de un único componente CHO
sin residuo. La curva es una condición de contorno, no una predicción de
pirólisis. No es todavía un proveedor por paso; su integral sirve únicamente
para auditar los datos. No genera solicitudes de oxidación ni calor, no
invoca GDScript y no modifica escenarios, objetos o cuentas U/R.

El modo térmico del núcleo sigue disponible solo en su fixture previa.
Una ley predictiva de liberación exige otro contrato: flujo de calor que
llega al objeto, coste térmico y destino de la energía, superficie,
dependencia temporal y evidencia material. No se obtiene aquí desde HRR,
O₂, temperatura de capa ni energía residual.

## Esquema ejecutable

[`validate_g3_mass_material_profile.py`](../../scripts/simulation/validate_g3_mass_material_profile.py)
valida `g3_mass_material_profile_v1`. Rechaza campos desconocidos, ausentes,
tipos inválidos, bool como número, negativos y valores no finitos. El
lector JSON rechaza claves duplicadas y tokens NaN/Infinity.

| Bloque | Contrato |
|---|---|
| Identidad | `id`, `component_id`, `scope = single_CHO_no_residue`. El mismo componente debe aparecer en masa, material, calor y emisión. Es consistencia de etiquetas, no prueba de identidad física. |
| Clase | `synthetic_control` o `external_candidate`. No existe clase de producción. |
| Masa inicial | `value`, `unit = kg`, `basis = modeled_component_mass`, componente y procedencia. No masa total de un sofá con estructura/ignitor/cojines sin atribución. |
| Composición | Fracciones másicas C/H/O explícitas, no negativas, suma 1 a `1e-12`; procedencia propia. No se deducen de rendimientos CO/CO₂. N y otros elementos quedan fuera de esta versión. |
| Energía química | Valor positivo, `kJ/kg`, `complete_oxidation_net`, componente y procedencia propia. El rótulo no acredita esa base científicamente. |
| Liberación | `mode = prescribed`, `quantity = modeled_component_emission`, `unit = kg/s`, mismo componente, origen temporal explícito. No pérdida global de espécimen intercambiable con emisión combustible. |
| Serie | Dos o más muestras `{time_s, rate_kg_s}`, tiempos no negativos estrictamente crecientes y primer tiempo 0. `piecewise_linear`, `outside_domain = reject`. |

Se integra exactamente la interpolación lineal declarada por trapecios:
`sum((t1-t0)*(r0+r1)/2)`. Esa integral no puede superar la masa inicial,
con `1e-12 kg + 1e-12 * escala`, tolerancias de contabilidad del núcleo.
No extrapola, ajusta o recorta una serie incompatible. No exige que termine
en tasa cero: el dominio puede acabar antes del agotamiento, y cualquier
uso posterior fuera de él deberá rechazarse. No integra ni interpola
peticiones del motor todavía.

Masa, composición y energía se declaran para el **componente modelado**.
La simplificación de igual composición/energía específica en sólido y
liberado sigue siendo la del núcleo aislado: no se afirma que describa
madera, polímero real o un sofá. El validador no vuelve a implementar
estequiometría ni garantiza que cualquier entrada estructuralmente válida
pase las comprobaciones numéricas/químicas del núcleo.

### Procedencia por magnitud

Cada bloque lleva `type`, `reference`, `locator`, `uncertainty`, `regime` y
`scale`, sin textos vacíos. La incertidumbre debe declararse, incluso como
no disponible; un texto no implica que se haya cuantificado correctamente.

- Control sintético: `type = synthetic` y referencia `synthetic:...`.
  Nunca queda promovido a medición por cumplir el esquema.
- Candidato externo: `measured` o `declared_model`, enlace HTTPS, versión,
  archivo local relativo y SHA-256 de sus bytes. Se comprueban existencia,
  hash y confinamiento al root declarado, también tras resolver symlinks.
  No hay descargas ni redistribución de datos nuevos.

El hash fija un artefacto/versionado concreto, no demuestra que el locator
contenga la magnitud declarada o que corresponda al componente. No sustituye
licencia, revisión de unidades/procesado, sincronización, atribución,
incertidumbre o validez de escala/régimen. Fuentes de distinta procedencia
requieren justificar su compatibilidad física en revisión científica.

Salidas válidas: `synthetic_contract_complete` o
`external_contract_complete_pending_scientific_review`. Ambas mantienen
`production_activation`, `engine_integration` y `scientific_approval` en
false. No se escribe un payload para el motor ni un catálogo calibrado.

## Qué se puede importar hoy, y qué no

Basado en los inventarios locales ya auditados; no es una nueva búsqueda
ni certificación de ausencia de datos fuera de esos artefactos.

| Candidato | Limitación concreta para este contrato |
|---|---|
| 107 objetos declarados de producto | No declaran kg iniciales, MLR temporal, composición ni base química; no se generan desde sus MJ. |
| 14 objetos de validación | Cuatro tienen Hgas/Hcomb, pero no contrato de masa ni base química. Tener esos escalares no basta para migrar. |
| NIST TN 2303, E01/E02 | Masa temporal publicada en figuras, no serie numérica en los CSV auditados; composición del componente emitido/base química no establecidas aquí. |
| Sofás FCD, E04 | Espécimen compuesto con almohadas, masa total inicial/final y HRR/CO de escape. No curva de emisión de un componente aislado. |
| FSRI cono, E11 | Canal bruto de masa de un material, exige procesado y distinción pérdida/emisión. Archivos originales externos; no se redistribuyen ni se declaran calibrados. |
| FSRI sofá, E12 | Puede contrastar pérdida de masa/HRR de objeto; no identifica emisión CHO única. Ausencia de CO limita química, **no** invalida por sí sola un futuro control de masa. |

Referencias de la revisión anterior:
[inventario declarado](G3_D1_DECLARED_MASS_INPUTS_2026-10-03.json),
[matriz de fuentes](G3_CO_SOURCE_ELIGIBILITY_MATRIX_2026-09-29.json),
[bases y limitaciones](G3_D1_IDENTIDAD_INQUEMADO_2026-10-03.md),
[elegibilidad G3-2](G3_CO_FUENTES_ELEGIBILIDAD_2026-09-29.md).
Fuentes primarias enlazadas allí:
[CFAST TN 1889v1](https://nvlpubs.nist.gov/nistpubs/TechnicalNotes/NIST.TN.1889v1.pdf),
[NIST TN 2303](https://nvlpubs.nist.gov/nistpubs/TechnicalNotes/NIST.TN.2303.pdf),
[FCD](https://www.nist.gov/el/fcd/design-fires-residential-and-office-items),
[FSRI MaPD](https://github.com/ulfsri/fsri_materials_database).

## Pruebas y criterio de cierre

Fixture **sintética**, no sofá: 1 kg declarado, composición CHO supuesta,
energía supuesta 20 000 kJ/kg; triángulo de 0 a 10 s con pico 0,1 kg/s.
Integral analítica 0,5 kg, independiente del calor declarado. Caso asimétrico
0,195 kg y control de masa/emisión cero. No contienen parámetros medidos.

Pruebas focalizadas cubren tipos, números, bases, identidad, dominios,
límites de inventario, overflow, procedencia, confinamiento, parser y CLI.
Diez mutantes Python compilados en memoria retiran respectivamente una
protección: campos extra, kg, componente, base química, base de emisión,
bool, tope de masa integrada, orden temporal, extrapolación y hash.
Se comprueba que el mismo oráculo rechaza el control incompatible en el
original y deja de rechazarlo en cada mutante válido. No se modifican
archivos ni se cuentan errores de sintaxis como bajas. Esta comprobación
es del validador offline, **no** otra campaña de física GDScript.

```powershell
python scripts/simulation/validate_g3_mass_material_profile.py tests/fixtures/g3_mass_material_profile_synthetic.json
python -m pytest tests/test_g3_mass_material_profile.py -q -p no:cacheprovider
```

Resultados: **46 pruebas nuevas PASS**, incluidas las diez comprobaciones
de mutantes válidos; **62 PASS** al unir auditor de masa y tests estáticos
del núcleo, con una prueba dinámica de Godot excluida expresamente.
CLI sintética: 1 kg inicial, integral 0,5 kg, activación/integración y
aprobación científica false. No escritura sobre las entradas.

La primera corrida conjunta dio 60 PASS y dos errores de permisos al crear
`tmp_path` en el sandbox, no fallos de contabilidad. La repetición con
basetemp externo nuevo pasó 62/62, exit 0. Guardarraíles ALL PASS, R2-1
incluido; enlaces y `git diff --check` limpios. No se ha tocado `sim/`:
no se atribuye una nueva referencia completa ni otra suite global a este
contrato. Los resultados del núcleo siguen en su documento, con código
preservado. Ningún Godot se ha lanzado en este tramo.

## Orden siguiente

Actualización del 04-10: [replay de masa](G3_D1_ISOHEPT9_REPLAY_2026-10-04.md)
cerrado y [fuentes/base energética con fases](G3_D1_HEPTANE_PHASE_BASIS_2026-10-04.md)
revisadas. Este esquema v1 no se ha ampliado para representar líquidos ni
convertido en perfil experimental. Siguiente: ledger puro versionado con
fases explícitas, API v1 preservada y sin integración.

Pasos 1–2 hechos y validados después de este contrato, con
[cadena nueva completa](G3_D1_PRESCRIBED_RELEASE_2026-10-03.md):
247 checks / 83 grupos, 72 pruebas conjuntas PASS, 11/11 mutantes,
referencia 346/346 y 78 gaps, producto 168/168 y global 3382 passed.
El adaptador `prepare_prescribed_program` copia un programa independiente
manteniendo elegibilidad y autorizaciones false; no lo carga el motor.
Siguiente trabajo pendiente: paso 3, benchmark experimental.

1. Proveedor puro **prescrito** por intervalo (hecho, sin integración):
   leer el contrato, integrar cada intervalo dentro del dominio sin
   extrapolar, y entregar solo demanda de liberación kg/paso. El núcleo
   mantiene la autoridad sobre débito y topes; ninguna masa recortada se
   presenta como emitida. Fijar cómo se representa tiempo/progreso aceptado
   para no reemitir demanda rechazada ni saltarse masa al reiniciar.
2. Fixture GDScript sintética que una proveedor y núcleo (hecha): independencia de
   HRR, conservación al subdividir pasos, dominio agotado, reinicio,
   O₂ cero/limitante y solicitudes superiores al sólido. No es integración
   del motor ni validación de un mueble; exige memoria/monitor y R2-1 si se
   añade o cambia código bajo `sim/`.
3. Primer benchmark experimental de alcance estrecho con flujo de masa
   independiente y energía/composición atribuibles; revisar sus fuentes
   antes de importar valores. No tiene que ser un sofá compuesto para
   contrastar primero el balance. Separar validación de masa de CO/FED.
4. Solo después, contrato de especie combustible, propiedades del gas,
   zona, energía térmica y fuente/débito únicos en el aplicador; ley de
   muebles/materiales y química parcial necesitan evidencia propia.

**GO técnico al contrato y al proveedor aislado validado; NO-GO a importación
automática de muebles, identidad de U, ley predictiva, integración o CO/FED.**
