# G3/D1 — Ledger sensible sintético versionado

Fecha: 2026-10-04. Entrada: `06a79c64`. Implementación autorizada por el
usuario después del cierre del helper de propiedades. No es integración
en la simulación ni aprobación de CO/FED o propiedades de muebles.
**Estado: cerrado técnicamente como ledger sintético aislado.**

## 1. Contrato predeclarado

Nueva API `FuelMassBudgetModel.propose_phase_sensible`, en el dueño existente
de masa/CHO. Reutiliza sus límites, productos, balances y validación del
material de referencia declarado; no modifica Lref ni las funciones antiguas.
Cp y su integral siguen exclusivamente en `SensibleEnthalpyModel`.

Material cerrado: `schema=g3_phase_sensible_material_v1`, `component_id`,
`reference_material` (esquema anterior completo), `liquid_profile` y
`vapour_profile`. Ambos perfiles sintéticos deben tener esa identidad,
fase y referencias compatibles. Validación del material de referencia
mediante una propuesta a dt=0, con inventarios de entrada y B/Q de referencia
cero: es una auditoría de su contrato, no un paso ni una sustitución de Lref.

Estado cerrado: `schema=g3_phase_sensible_state_v1`, `component_id`, los
seis campos de masa/B/Q anteriores, `liquid_sensible_kj` y
`vapour_sensible_kj`. S y Q son cuentas firmadas de entalpía respecto a
referencia; B y masas no negativos. Q no es HRR químico. Cada cuenta S debe
pertenecer al intervalo m*h(Tmin)..m*h(Tmax) del perfil canónico. Masa cero
exige S exactamente cero; sin umbral que borre fases pequeñas, sin T ficticia.

Solicitud cerrada: `dt_s`, `release_kg`, `oxidation_kg`, `heat_liquid_kj`,
`heat_vapour_kj`, `emitted_vapour_temperature_k`. Masas y calor por paso,
no tasas; valores finitos, calor solicitado no negativo. Primero calentar,
después liberar, mezclar y oxidar. No enfriamiento/pérdidas en esta versión.
El calentamiento es una energía prescrita, no una temperatura predicha:
si su suma excede B se rechaza toda la propuesta, sin estado parcial.
También se rechaza calentar una fase ausente o salir del soporte. No se
inventa una inversión h->T ni una prioridad térmica entre fases. A dt=0
no se acepta calor ni masa y el estado queda idéntico.

Para líquido homogéneo después del calentamiento, s_l=S_l/m_l. El vapor
emitido tiene s_e obtenido por el helper a la temperatura declarada.
Coste por kg: Lref+s_e-s_l, estrictamente positivo al solicitar liberación
de líquido presente. El límite de masa usa B restante antes de oxidar.
Ausencia de liberación no exige dividir por un coste sin significado.
Mezcla: S_mix=S_v+calor_v+r*s_e; nunca media de temperaturas.
Oxidación homogénea: s_mix=S_mix/(m_v+r), S_oxid=b*s_mix,
Q_increment=b*q_vap+S_oxid. El O2 y productos están a referencia.
El signo de S_oxid/Q_increment no se recorta artificialmente.

Se verifican A, S, B y Q separados y A+S+B+Q total, además de masa/CHO;
es entalpía a presión declarada, NO energía interna de EOS. Sin Cp=Cv,
trabajo pV, transporte, evaporación predicha o calor de oxidación prestado.
Déficit de liberación y masas rechazadas explícitos. Rechazos sin candidato,
entradas intactas y todas las aprobaciones físicas/activación false.

## 2. Oráculos y falsación anteriores al GDScript

Componente CHO sintético C=.75, H=.25, O=0: O2=4 kg/kg,
CO2=2.75 kg/kg, agua vapor=2.25 kg/kg. q_l=19000, q_v=20000,
Lref=1000 kJ/kg; Cp líquido=2 y gas=1 kJ/(kg*K).

Caso caliente: m_l=1, S_l=100, m_v=.2, S_v=10, B=1000,
calentamiento líquido=20, vapor=10 kJ; emisión a 398.15 K (s_e=100),
r=.1, b=.1 kg. Coste=98 kJ; S_l final=108; mezcla S=30 en .3 kg;
S_v final=20; Q_increment=2010; B final=872. A antes=23000,
A después=21100; total antes y después=24110 kJ. Estos números son
álgebra analítica independiente, no propiedades medidas de un incendio.

Caso frío: S_l=-50, S_v=-5, sin calentamiento, emisión a 273.15 K
(s_e=-25): coste=102.5, S_l final=-45, S_v final=-5,
Q_increment=1997.5; B final=897.5. Sin clamp del sensible negativo.

L01-L20: referencia equivalente, calor único, mezcla/oxidación, frío,
B/O2/inventario, no autofinanciación, dt0, secuencia/restart, ausencia y
masa diminuta, perfiles/binding, tipos/esquemas, rango/overflow,
inmutabilidad, separación de química/Q y aislamiento. Mutantes: omitir
debitar calor, ignorar sensible en coste, signo, mezcla, proporcionalidad,
Q, B/O2, referencia, identidad, ausentes, rango, finitud y activación.
Solo fallos conductuales con salida 1 cuentan, no errores de parser/monitor.

## 3. Verificación y estado

Oráculos Decimal independientes fijados y ejecutados antes de añadir el
GDScript: 1 PASS. Fixture real final L01-L20: **915 comprobaciones PASS**;
diez valores contrastados también desde Python. Focal ampliada final con
APIs anteriores, contratos de fixtures y propiedad de red: **416 passed /
10 skipped**, 27,32 s. No nuevos skips para el ledger.

**23/23 mutantes válidos detectados** sobre el código final, con control
verde, ningún superviviente o baja por sintaxis/infraestructura y fuentes
intactas por SHA-256. Evidencia local:
`runs/g3_sensible_phase_mutations_20261004_220818/results.json`.
Las dos campañas previas de 22 mutantes no sustituyen a esta final.
También se ejecutaron las campañas históricas de masa **10/10**, referencia
**12/12**, caller **18/18** y fuente **11/11**, con control verde. Estas cuatro
tandas preceden al último guard de déficit, exclusivo de la API nueva;
las once funciones antiguas y el helper no cambiaron, y la regresión
focal/global final se ejecutó después del guard.

La revisión añadió dos protecciones concretas: una operación sin cambios
conserva el snapshot exacto (sin ida y vuelta S/m*m); un déficit informado
no puede desbordarse aunque el estado aceptado y las demás cuentas sean
finitas. El segundo defecto se reprodujo antes de corregir: tres fallos
conductuales en una fixture de 915 checks; L23 reinstala la omisión y muere.
El primer intento del control extremo usaba Cp subnormal y era rechazado
antes de llegar al déficit: no se contó como reproducción. Se sustituyó
por números normales que sí alcanzan la escritura incorrecta.

Los pins del archivo completo pasan a SHA-256 de las **once funciones y
constantes anteriores**, conservando sus bytes LF; solo el EOF del último
método se contabiliza ahora como separador. No se relaja ninguna ley o
tolerancia. La única dependencia nueva admitida es el helper Cp puro,
en este dueño puro; no se admite ningún consumidor en producto. Los
proyectos de mutación antiguos copian ese recurso para el parser.
Provider, caller atómico anterior y helper Cp siguen sin modificaciones.

Referencia por monitor: **18/18 ejecuciones limpias**, todas salida 0,
informe nuevo y errores de salud vacíos; 3155,6 s sumados. Comparador:
**346/346 required PASS**, **78 gaps** sin cambios, ALL GUARDRAILS PASS
incluido R2-1. Los **160 informes de caso** mantienen SHA-256 byte a byte.
En `reference_checks.json` cambia solo `generated_at`:
2026-10-04T18:47:06Z -> 2026-10-04T21:04:52Z, confirmado estructuralmente.
Evidencia: `runs/reference_suite_monitored_20261004_221211/suite_log.json`.

Producto: **168/168 PASS**, exit 0, sin procesos o cuadros Godot al terminar.
Global autoritativa: `python -m pytest tests -q -p no:cacheprovider`, con
basetemp externo nuevo: **3640 passed / 41 skipped / 2 xfailed /
42 subtests passed**, exit 0, **552,47 s**. Las tres tandas largas fueron
secuenciales; memoria inicial referencia 6,716 GiB, producto 6,616 GiB y
global 6,551 GiB. Nunca se lanzó Godot directamente ni se terminó un
proceso ajeno. Temporales superiores externos; las fixtures mantienen
su aislamiento APPDATA propio histórico bajo `runs/`.

Estilo habitual, enlaces de cinco documentos y diff se verifican al cierre.
Los 80 archivos ajenos de main se preservan por hash; `runs/`, sidecars UID
generados y cambios ajenos quedan fuera del commit. No se añaden fuentes,
perfiles reales, interruptores, escenarios o autorizaciones de producto.

## 4. Límites que siguen abiertos

La API es sin estado persistente: el material y perfiles se declaran en cada
llamada. `component_id` impide mezclar identidades distintas, pero no firma
el contenido de perfiles con el mismo nombre ni certifica el historial.
Eso corresponde al propietario sucesor, con contexto/semilla/generación y
cuentas térmicas acumuladas. No adaptar el restore de referencia desde
solo masa aceptada: dos historias de calentamiento pueden tener igual masa.
Tampoco se predicen temperatura, evaporación, enfriamiento, energía del O2
o productos calientes, trabajo pV ni energía interna de EOS.

Siguiente fase, solo tras cierre: propietario atómico sensible versionado
capaz de conservar historia térmica variable, sin integrar en producto.
