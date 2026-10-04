# D1: atribución de emisión y presupuesto térmico de ISOHept9

Fecha: 2026-10-04. Rama `codex/g3-fed-co-zonal-shareable`, HEAD `cbab7b05`.
Estado: diagnóstico de fuentes cerrado; sin modificar ni integrar física.
Continúa el [ledger de fases cerrado](G3_D1_PHASE_LEDGER_2026-10-04.md).

## Decisión y alcance

**GO a diseñar un ensayo conjunto aislado y condicionado a masa prescrita,
con estados y energía de referencia declarados. NO-GO a presentar ese
ensayo como validación predictiva de evaporación, HRR, especies o CO/FED.**

La pérdida de masa de ISOHept9 es una base experimental razonable para ese
ensayo condicionado: los autores la usan como pérdida de combustible de
un incendio de heptano en bandeja. No es necesario exigir un certificado
de lote para comprobar un algoritmo bajo una hipótesis explícita.
Sin embargo, el dato no mide directamente la composición o fracción de
gas emitido, ni identifica el presupuesto térmico B. Esas limitaciones
impiden promocionar el resultado a una predicción del ensayo físico.

No se ajusta B para reproducir la curva. No se deriva masa de HRR/HOC ni
se toma el calor total del incendio como calor absorbido por el líquido.
Integración, activación, muebles, U histórico y CO/FED siguen NO-GO.

## Fuente primaria y revisión del montaje

[NIST TN 1603, octubre de 2008](https://nvlpubs.nist.gov/nistpubs/Legacy/TN/nbstechnicalnote1603.pdf),
[PDF local](../literature/NIST/NIST_TN_1603_Underventilated_Compartment_Fires.pdf),
SHA-256 `7ba8219496f8b52035fd97ed603182782e907034a94593bb51e7382c0cf453f5`.
Lectura de §2.1.4, §2.2.1, §2.2.6, §2.3-2.6 y §3.2; inspección visual de
figuras 2.4-2.5, tablas 2.5, 2.6 y 3.1 y apéndice A. Página PDF = impresa +14.
Los avisos de fuentes de Poppler no impidieron revisar las tablas.

- §2.1.4, pp.9-10: bandejas de acero de 0,635 cm de espesor, borde de
  10 cm, unidas a células de carga a través del suelo. Dos posiciones:
  centro del recinto y fondo. La configuración de spray puede recoger
  combustible y ganar masa; no transferirla al caso de combustión libre.
- Tabla 3.1, p.38: ISOHept9, 28-02-2008, heptano, 20 kg nominales,
  una bandeja de 0,5 m² y puerta de un cuarto de 80 cm. Masa realmente
  leída a ignición: 19,665829 kg, no sustituida por la nominal.
- §3.2, pp.40-41 y figura 3.3: la potencia ideal se obtiene de la pérdida
  de masa del quemador; la calorimetría por consumo de oxígeno proporciona
  otra magnitud. No son dos mediciones independientes de la emisión.
- Apéndice A, pp.145-146: `Mass1` corresponde al quemador central en kg.
  `Mass2` pertenece a otra célula de carga, no a otra especie combustible.

Los valores de 44,4 y 44,56 MJ/kg citados en distintas partes de TN 1603
siguen separados; no se promedian. La base termoquímica de referencia
proviene del [gate TN 2126-upd1](G3_D1_HEPTANE_PHASE_BASIS_2026-10-04.md),
no de un ajuste de esos dos valores al resultado del motor.

## Qué miden los canales térmicos

La tabla 2.5, p.32, y el apéndice A permiten distinguir las magnitudes.
El [CSV experimental fijado](https://github.com/firemodels/exp/blob/e5de6811036d252b4f9085866f08da66efdda7d3/NIST_FSE_2008/ISOHept9.csv)
contiene 71 columnas; no es una simulación FDS ni adquisición cruda.

| Canales | Objeto medido | No sustituye a |
| --- | --- | --- |
| `TR*`, `TF*` | Árboles de termopares del recinto | Temperatura del líquido |
| `TFSampPtRh`, `TRSampPtRh`, `TRMoveSamp` | Sondas de muestreo de gas | Temperatura de la superficie del combustible |
| `THF*` | Temperatura del propio medidor de flujo | Temperatura de la bandeja o del líquido |
| `TSHF*`, `TSXHF*` | Superficie interior/exterior del cerramiento | Energía sensible del combustible |
| `HFRFL`, `HFFFL`, `HFOFL` | Flujo hacia sensores en suelo/interior-exterior | Flujo neto absorbido por toda la bandeja |
| `HFRCE`, `HFCCE`, `HFFCE` | Flujo hacia sensores del techo | Retroalimentación térmica al combustible |
| `IHRR` | Potencia ideal derivada del combustible | Entrada térmica independiente B |
| `HRR2` | Calorimetría del escape | Potencia absorbida por el líquido |

Ejemplo de localización: sensores de suelo a x=119,5 cm,
y=266/90/-20 cm, z=0; techo a z=233 cm. La bandeja ocupa el centro
del recinto. Multiplicar una lectura de suelo por 0,5 m² no demuestra
que sea el calor recibido por su superficie: cambian posición, orientación,
temperatura, conducción, absorción y pérdidas.

§2.2.6, pp.29-30: medidores enfriados por agua, depósitos de hollín y
respuesta/calibración revisados; no son una calorimetría de la bandeja.
En los canales publicados/revisados no se identifica una serie de
temperatura del líquido, estado térmico de la bandeja o calor neto
absorbido que permita reconstruir B independientemente.
Es una limitación de esta fuente y de este alcance, no una afirmación
de que no existan experimentos adecuados en otra parte.

## Incertidumbre: no intercambiar presupuestos

§2.1.4 cita precisión de célula de carga ±1 g; no es la incertidumbre
total de cada pérdida de masa diferenciada a 5 s. Tabla 2.6, p.36,
resume incertidumbres expandidas: potencia ideal ±6 %, calorimetría
±14 %, flujo de calor -16 %/+12 %, temperatura -20 %/+6 %.
Los autores incluyen pureza del combustible en el presupuesto de
potencia ideal; esto no mide una fracción emitida ni certifica el lote.
No aplicar ±6 % a B, ±1 g al ensayo completo, ni la incertidumbre de un
sensor de suelo al calor neto absorbido por el combustible.

## Cálculo condicionado, no presupuesto observado

Para la ventana previamente declarada 0-500 s:

`Delta m = 19,359537 kg`.

Si **se supone** que todo ese descenso es n-heptano de referencia transferido
de líquido a vapor a 298,15 K y 1 bar, el coste de fase del ledger es:

`W_ref = Delta m * L_ref = 7081,108094 kJ`, con
`L_ref = 365,768463 kJ/kg`.

Es una magnitud **calculada y condicionada**; no calor medido, calor a
ebullición, calor sensible, valor inicial de B ni validación del lote.
Ni los dígitos calculados ni la identidad decimal aumentan precisión física.
Financiar el ledger con ese importe demostraría una identidad contable,
no que el incendio real haya recibido esa cantidad por esa ruta.

La energía sensible exige una referencia común: para cada fase,
`s_j(T) = integral desde T_ref hasta T de cp_j(T) dT`.
La diferencia de entalpía entre vapor y líquido a temperaturas distintas
es `L_ref + s_v(T_v) - s_l(T_l)`. Esto no es por sí solo todo el calor
externo: también cuentan almacenamiento térmico del líquido restante y
de la bandeja, conducción, pérdidas y posibles entradas/salidas.
El ledger actual solo prueba estados de referencia; no se le añade Cp o
una temperatura inventada para hacerlo pasar por evaporación predictiva.

## Auditoría reproducible y controles

[Resultado guardado](G3_D1_ISOHEPT9_EMISSION_AUDIT_2026-10-04.json).
`python -m scripts.simulation.audit_g3_isohept9_emission_basis`:

- Reutiliza los auditores de masa y de fases; verifica CSV/licencia/PDF,
  revisión y hashes. Rechaza atribuir otra serie al montaje revisado.
- Clasifica las 71 columnas revisadas; canal ausente, renombrado,
  duplicado o adicional requiere revisión, no una inferencia silenciosa.
- Conserva ventanas y signos originales. Solo calcula el coste de
  referencia bajo la hipótesis indicada; no formula un solver paralelo.
- B observado, temperatura del líquido y fracción emitida permanecen
  `null`, no cero. Todas las aprobaciones físicas/activaciones son false.

**127 pruebas offline PASS**, incluidas **21 nuevas**, exit 0, 1,33 s.
La primera invocación usó el Python empaquetado, sin pytest; no ejecutó
pruebas ni se cuenta como corrida válida. Se repitió con el Python
instalado y basetemp externo nuevo en `simufire_emission_basis_20261004_2c30j5hu`.
Estos controles negativos no se presentan como mutaciones nuevas del motor.

No cambios de `sim/`, proveedor, informes, escenarios o perfiles; no
Godot, nueva referencia/global, commit ni push en esta fase. La cadena
346/346, 168/168 y global 3484 corresponde al ledger cerrado antes.

Comprobación final: guardarraíles ALL PASS, incluido R2-1 sobre los informes
existentes; estilo GDScript visual PASS, enlaces de siete documentos PASS
y `git diff --check` limpio. SHA-256 del núcleo `1a25b848...`, proveedor
`89a8c5ad...` y resumen de referencia `b5c57953...` intactos. No se
repite ni atribuye una suite global después de añadir estos tests offline.

## Siguiente trabajo, sin integración

1. Diseñar el **caller atómico puro** que une replay y ledger de referencia:
   [Diseño completado en la continuación](G3_D1_ATOMIC_CALLER_CONTRACT_2026-10-04.md),
   implementado y validado aisladamente en la continuación (§10 del
   contrato); no conectado al motor. Controles sintéticos cerrados.
   demanda, aceptación, cursor, inventario, coste de fase, oxidación y
   productos se confirman juntos o no se confirma nada. Mantener identidad
   v1 y no derivar emisión de U/HRR. Hipótesis de emisión y energía de
   contorno declaradas, nunca escondidas dentro del cap.
2. Controles sintéticos predeclarados: B independiente suficiente,
   insuficiente y cero; O₂ cero/limitante; rechazo/reinicio/subdivisión.
   El caso condicionado ISOHept9 verifica masa y contabilidad; no una
   ley de evaporación. Si B limita la aceptación, registrar el déficit:
   no seguir afirmando reproducción de toda la masa observada.
3. Para energía sensible/evaporación predictiva, revisar un experimento
   que mida superficie/líquido y retroalimentación al combustible.
   Candidato localizado: [NIST, Structure of Medium-Scale Pool Fires](https://www.nist.gov/el/fcd/structure-medium-scale-pool-fires),
   [TN 2162r1, octubre de 2024](https://nvlpubs.nist.gov/nistpubs/TechnicalNotes/NIST.TN.2162r1.pdf)
   y [datos MaCFP](https://github.com/MaCFP/macfp-db/tree/master/Liquid_Pool_Fires/NIST_Pool_Fires).
   [Revisión focal posterior completada](G3_D1_POOL_THERMAL_EVIDENCE_2026-10-04.md):
   fuente/snapshot incorporados; perfil hacia sensor medido e independiente
   de masa, pero B neto/temperatura del líquido no identificados. No revisión
   integral del PDF ni replay térmico aprobado. Aire libre/estacionario/enfriamiento
   del quemador no validan por transferencia ISOHept9 subventilado o muebles.

Antes de cambiar `sim/`: contrato del caller revisado, controles/mutantes
declarados y cierre R2-1 completo por monitor. No integrar en producto
ni convertir este GO diagnóstico en aprobación de CO/FED.
