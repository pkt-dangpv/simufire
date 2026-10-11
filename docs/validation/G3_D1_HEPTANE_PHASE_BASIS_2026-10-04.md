# D1: base energética líquido-vapor del heptano

Fecha: 2026-10-04. Rama `codex/g3-fed-co-zonal-shareable`, HEAD `cbab7b05`.
Estado actualizado: gate de fuentes cerrado; el
[prototipo GDScript de fases está implementado](G3_D1_PHASE_LEDGER_2026-10-04.md)
y validado técnicamente, sin integrar.
Gate de fuentes/contrato, no integración. Continúa el
[replay de masa cerrado](G3_D1_ISOHEPT9_REPLAY_2026-10-04.md).

## Decisión

GO concedido al **prototipo puro con fases explícitas y energía de referencia**,
ya cerrado técnicamente en la continuación enlazada.
NO-GO a conectar ISOHept9 al motor, validar evaporación/HRR/CO, convertir U
en kg o asignar perfiles a muebles. El líquido no se introduce como sólido.
La base y el ledger de referencia ya están identificados/implementados;
faltan energía sensible y validación experimental. La
[revisión de emisión/B](G3_D1_ISOHEPT9_EMISSION_BASIS_2026-10-04.md)
delimita lo medido y lo supuesto. Este gate original no modificó `sim/`;
la continuación sí añadió la API aislada de fases.

## Fuentes revisadas y alcance

Se archivó el PDF oficial
[NIST TN 2126-upd1, febrero de 2026](https://doi.org/10.6028/NIST.TN.2126-upd1):
[copia local](../literature/NIST/NIST_TN_2126_upd1_Thermochemical_Properties.pdf),
10 571 808 bytes, 461 páginas, SHA-256
`c964ba6afab1f029ed666fb9768fab2e7683b57c3169814d37693c386b6db21a`.
Portada/versionado comprobados: publicado en diciembre de 2023, actualizado
en febrero de 2026. El buscador ofrecía una copia de 467 páginas de 2023;
no se le atribuyeron páginas ni versionado de la actualización.

Inspección visual de tablas 4-9(2) y 4-10 y lectura de sus encabezados/notas.
PDF p.336 = impresa p.328; PDF p.360 = impresa p.352. Tabla 4-1 p.250
define entalpías a 298,15 K; tabla 4-10 p.350 fija productos gaseosos para
el calor neto. La columna Ttrs indica transición, **no** la temperatura a
la que se evaluaron todos los calores de la fila.

| Magnitud de referencia | Valor | Localizador en TN 2126-upd1 |
|---|---:|---|
| Masa molar tabulada | 100,20 g/mol | p.9, CAS 142-82-5 |
| Calor neto, líquido | 4464,88 kJ/mol | p.352, tabla 4-10 |
| Calor neto, gas | 4501,53 kJ/mol | p.352, tabla 4-10 |
| Vaporización a referencia | 36,65 kJ/mol | p.328, tabla 4-9(2) |

Se usan magnitudes positivas para energía liberada; la fuente tabula
entalpías de reacción negativas. Referencia: 298,15 K, base de tabla 4-10
de 1 bar, oxidación completa con agua gaseosa. Es un compuesto de referencia,
**no** una medición química del lote del incendio.

[NIST TN 1603](https://nvlpubs.nist.gov/nistpubs/Legacy/TN/nbstechnicalnote1603.pdf)
se volvió a revisar visualmente en p.41, p.115 y p.125: mantiene 44,4 y
44,56 MJ/kg; no se corrigió ni promedió esa discrepancia. 44,56 coincide
numéricamente con el calor neto del líquido de la tabla nueva tras redondeo,
pero esto no demuestra la intención del autor ni certifica el lote.

El [WebBook de NIST](https://webbook.nist.gov/cgi/cbook.cgi?ID=C142825&Mask=FFFFFF)
sirvió de contraste: contiene múltiples mediciones/compilaciones, no una
única serie elegida por ajuste. Su calor de vaporización a ebullición no
sustituye al de 298,15 K. No se mezclaron medias y valores recomendados.

## Auditoría reproducible

[Entradas transcritas](G3_D1_HEPTANE_PHASE_INPUTS_2026-10-04.json) y
[resultado](G3_D1_HEPTANE_PHASE_AUDIT_2026-10-04.json).
`python -m scripts.simulation.audit_g3_heptane_phase_basis` verifica hash,
confinamiento, esquema, unidades, fases y cinco ciclos de Hess offline.
Reutiliza lector JSON estricto y verificación de archivos existentes.
No implementa pasos de simulación ni produce un perfil para el motor.

Conversiones con la masa molar redondeada de la misma tabla:
q_liq = 44 559,6806387 kJ/kg; q_vap = 44 925,4491018 kJ/kg;
L_ref = 365,7684631 kJ/kg. Los dígitos calculados no amplían precisión física.

Los ciclos de fases neto/bruto/formación cierran a cero decimal. La
conversión bruto-neto por ocho moles de agua deja -0,002 kJ/mol por redondeo.
Tolerancia fija 0,005 kJ/mol para valores impresos, **no** incertidumbre
experimental ni tolerancia nueva del motor. No se propagan como independientes
los valores correlacionados de formación, vaporización y combustión.

Un hash prueba bytes, no transcripción semántica. Una alteración coherente de
todos los calores podría pasar los ciclos: los tests fijan además los valores
revisados. La atribución a páginas fue humana, no un extractor automático.
Ni esa revisión identifica pureza, composición del vapor o temperatura de
superficie de ISOHept9. Todas las autorizaciones permanecen false.

## Contrato energético aprobado e implementado después de este gate

Definir `m_liq`, `m_vap`, energía térmica disponible B y energía depositada Q,
con una sola referencia. Contabilidad de potencial de oxidación completa:

`A = m_liq * q_liq + m_vap * q_vap`.

Al transferir r kg de líquido a vapor a referencia:

- Débito único de masa: líquido -= r; vapor += r.
- B -= r * L_ref; A aumenta exactamente r * L_ref.
- A + B + Q permanece constante; no se borra el coste ni se añade dos veces.

Al oxidar b kg de vapor:

- Vapor -= b; O₂ y productos dependen de la estequiometría canónica.
- Q += b * q_vap; A disminuye b * q_vap.
- A + B + Q permanece constante. Con O₂ cero, el vapor conserva masa/energía.

Esto es un ledger de **potencial energético de referencia**, no el U histórico,
ni toda la entalpía sensible del recinto. No sustituye la EOS zonal ni permite
depositar esa energía térmica antes de oxidar. El coste de referencia aumenta
el potencial almacenado en el vapor; no se le añade además como sensible.

Controles predeclarados: liberación sin oxidación, oxidación parcial de la
masa con química completa, O₂ cero/limitante, disponibilidad insuficiente,
rechazo sin escritura, subdivisión/reinicio y ciclo completo equivalente a
q_liq neto una vez descontado L_ref. Sin HRR como entrada de masa.

Dos errores deben morir en mutaciones: usar q_liq para el vapor mientras se
paga L_ref (pierde r*L_ref), y usar q_vap sin cargar la vaporización (crea
r*L_ref). El cierre separado de los balances no basta: probar el total.

La API v1 de `FuelMassBudgetModel.gd` conserva igual energía específica
en reservorio y liberado; su modo térmico comprueba por separado el presupuesto
de liberación. Su alcance sintético se conserva. La API de fases posterior
separa líquido/vapor y comparte la autoridad de oxidación/estequiometría.
La identidad v1 y la conservación conjunta están verificadas en el cierre
del ledger, sin convertirlo en un modelo físico validado de heptano.

### Límites antes del ensayo y del producto

1. El primer prototipo se limita a estados de referencia. Temperaturas reales
   requieren entalpías sensibles, Cp(T), presión y destino térmico explícitos;
   no asumir que la superficie está a ebullición por observar una llama.
2. El replay impone masa: su coste debe figurar como energía de contorno
   declarada o debitar una fuente identificada. Si se limita por B, ya no
   reproduce automáticamente la serie medida. No esconder déficit en el cap.
3. Masa perdida no identifica por sí sola todo el gas combustible emitido.
   La pureza/lote, pérdidas no gaseosas y tratamiento experimental siguen abiertos.
4. La masa molar tabulada no modifica las masas atómicas nominales C=12,H=1,O=16
   del núcleo sintético. Antes de combinar resultados, fijar una convención
   coherente o documentar la aproximación; no afirmar estequiometría exacta
   mezclando bases. Ninguna migración de objetos se autoriza aquí.
5. Oxidación completa no valida CO/hollín, HCN, HRR del calorímetro o FED.
   La química parcial y el transporte siguen gates separados.

## Verificación y entrega

Primera prueba offline: 28 controles pasaron y el temporal de pytest falló por
permisos; no se cuenta como corrida válida. Repetición externa: 136 PASS,
3 fixtures Godot excluidas. Tras endurecer campos de evidencia y fijar el
resultado guardado, focalizada offline final **140 passed, 3 deselected**,
exit 0: 33 pruebas nuevas del gate y 107 controles anteriores. Las tres
excluidas arrancan Godot, no son fallos ocultos. Temporal externo nuevo en
`C:/Users/dangp/AppData/Local/Temp/simufire_hept9_replay_20261004_01/pytest_phase_basis_final`.
Los controles negativos no se presentan como otra campaña de mutaciones
del motor. Guardarraíles ALL PASS, R2-1 incluido, sobre informes existentes.
Hashes idénticos al checkpoint del gate: núcleo `783c1316...`, proveedor
`89a8c5ad...`, resumen de referencia `5f4c78a3...`. Cero procesos Godot.
Manifiesto 41 entradas válido; fuente añadida una sola vez. Enlaces y diff
verificados al cerrar. No se regeneraron referencia, producto ni global.

No Godot ni cambios en `sim/`, informes, editor, escenarios, combustible
distribuido o interruptores. Sin commit/push. La referencia/global del replay
son resultados previos, no nuevas suites atribuidas a este gate.

Trabajo acordado al cerrar este gate: implementar y mutar el ledger con
fases en GDScript puro, preservando API v1, y completar R2-1 por monitor.
Continuación [implementada y cerrada técnicamente](G3_D1_PHASE_LEDGER_2026-10-04.md)
el 04-10: los recuentos posteriores pertenecen al ledger, no a este gate
offline. Todavía sin aplicador del motor ni validación del ensayo físico.
