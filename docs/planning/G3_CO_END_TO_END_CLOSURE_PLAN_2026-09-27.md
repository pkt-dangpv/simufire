# G3 — Subplan de cierre del CO, combustible, transporte y exposición

Fecha: 2026-09-27. Estado: **plan activo, con avances registrados**. Responsable científico
del cierre: pendiente de asignar. No cambia interruptores, escenarios ni
física. El selector `fed_co_zonal_enabled` permanece apagado y **NO-GO** para
producto hasta superar los gates que correspondan al alcance publicado.

Último avance del 08-10, segundo del día:
[Diseño del acoplamiento de la fuente prescrita](../validation/G3_OBJECT_HRR_SOURCE_COUPLING_DESIGN_2026-10-08.md).
Fase offline de G3-4, sin tocar `sim/` ni lanzar Godot. Ruta real del
fuego trazada en el código y fijada por 34 anclas. **Recomendación: una
fuente térmica prescrita, sola en su recinto y fuera de la ruta del fuego
de sala**; entrega calor y debita oxígeno, sin combustible ni especies, y
se invalida al salir del régimen del ensayo. **Representar el objeto que
arde es NO-GO**: faltan la serie numérica de masa, una composición
aprobada y rendimientos en recinto. Hechos: el filtro del fuego de sala
añadiría entre 5,5 y 8,9 MJ a la curva y le quitaría hasta un 6 % del
pico; la demanda de oxígeno se justifica como identidad de la
calorimetría (13,1 MJ/kg) y el total que publica la base de datos queda
un 7 % por debajo; el ensayo da una fracción radiativa de 0,52 ± 18 %,
del ensayo entero y al aire libre, frente al 0,35 del motor; una
habitación cerrada sale del régimen antes del pico. Quince decisiones
separadas: cuatro GO de diseño, un GO parcial y diez NO-GO. Siguiente
paso, pendiente del
usuario: autorizar o no ese único caso, con cambios en `sim/` bajo
interruptor apagado y cadena R2-1. Sin efecto en plazos. CO/FED siguen
OFF/NO-GO.

Avance previo del 08-10:
[Fuente aislada de HRR del objeto ensayado](../validation/G3_OBJECT_HRR_SOURCE_IMPLEMENTATION_2026-10-08.md).
Módulo aislado `sim/fire/PrescribedObjectHrrSource.gd` que reproduce el
HRR medido del Test016, sin conectarlo a nada. Tabla 115 093,655 kJ,
dentro de 115,1 ± 6,4 MJ sin ajuste; fixture 18 148 comprobaciones;
mutantes 73/73; referencia 346/346 required y 78 gaps; producto 168/168;
global 4271 passed. Reproducción de una entrada experimental, no
validación predictiva. CO/FED siguen OFF/NO-GO.

Avance previo del 07-10, tercero del día:
[Fuente de incendio por objeto: selección experimental](../validation/G3_OBJECT_FIRE_SOURCE_SELECTION_2026-10-07.md).
Revisión offline de G3-2/G3-4, sin tocar `sim/`. **La investigación de B
neto queda cerrada en esta vía como NO-GO** y se vuelve a la fuente por
objeto. Seleccionado NIST Test016, una silla sola, con su repetición
Test021 reservada. Seis decisiones separadas: reproducción prescrita de
HRR **GO** para una corrida al aire libre; pérdida de masa **NO-GO**;
energía y calor efectivo GO parcial como integrales; especies GO parcial
como totales en el escape; rendimiento temporal y extrapolación
**NO-GO**. Las repeticiones difieren más que su incertidumbre: una tabla
prescrita representa una corrida, no un objeto. Solo verificación de
reproducción, sin validación externa. Contrato de un módulo aislado que
reproduce únicamente ese HRR, propuesto y no autorizado. Siguiente paso,
pendiente del usuario: autorizar o no ese módulo, con cadena R2-1. Sin
efecto en plazos. CO/FED siguen OFF/NO-GO.

Avance previo del 07-10, segundo del día:
[Ensayo de evaporación sin llama en cono como benchmark](../validation/G3_D1_CONE_EVAPORATION_BENCHMARK_2026-10-07.md).
Revisión offline, sin tocar `sim/`. Cinco decisiones separadas:
observables GO parcial, irradiación incidente GO parcial, **calor neto
absorbido NO-GO**, calentamiento GO parcial limitado al termopar inferior
dentro del soporte, **emisión NO-GO**. El ensayo conoce la consigna del
cono, no el calor que absorbe el líquido: nueve de diez términos de
frontera sin medida ni cota, bandeja sin termopar y masa inicial sin
publicar. Solo hay figuras; la serie digitalizada no se publica. B neto
sigue NO-GO. No se autoriza ningún modelo térmico en `sim/`. Siguiente
paso, pendiente del usuario: las dos peticiones de datos, a los autores
del ensayo de cono y a Sandia, ninguna enviada. Sin efecto en plazos.
CO/FED siguen OFF/NO-GO.

Avance previo del 07-10:
[Revisión del gate de B neto](../validation/G3_D1_NET_THERMAL_BUDGET_REVIEW_2026-10-07.md).
Revisión offline, sin tocar `sim/`. **Se retira el GO parcial a B neto del
06-10:** la banda era la lectura de las galgas por un rango de reflexión.
B neto queda NO-GO, no identificado; cinco de seis términos de frontera
sin cota. Evidencia nueva del propio laboratorio (SAND2010-2511): la
lectura de la galga depende de su colocación, explora ±30 % como cuestión
abierta y su balance del heptano no cierra (−25 y −43 %). Sandia sigue
como contraste del flujo en el plano de las galgas. Corregidos el
inventario de líquido y los criterios; el almacenamiento pasa a la
demanda. Auditor extendido con la historia conservada y 31 pruebas nuevas.
El contrato de frontera térmica no queda autorizado. Siguiente paso,
pendiente del usuario: autorizar o no la petición de datos a Sandia. Sin
efecto en plazos. CO/FED siguen OFF/NO-GO.

Avance previo del 06-10, **corregido el 07-10**:
[Gate del presupuesto térmico neto del combustible](../validation/G3_D1_NET_THERMAL_BUDGET_GATE_2026-10-06.md).
Gate offline, sin tocar `sim/`. B se define como el calor neto que cruza
la frontera del líquido. Benchmark elegido entre tres: piscina abierta de
heptano de 2 m de Sandia (SAND2010-6377), con flujo y masa de la misma
corrida. B neto: GO parcial como tasa estacionaria acotada (estimación
independiente y demanda diagnóstica dentro del 12,5 %), NO-GO como valor
puntual; NO-GO transitorio, predicción térmica y predicción de emisión.
Cuatro términos sin medir, nombrados y sin rellenar. La segunda condición
(NIST 0,30 m) no cierra ni al 20 %. Auditor y 51 pruebas offline. Contrato
de la frontera térmica propuesto y no implementado. CO/FED siguen
OFF/NO-GO. Siguiente paso, pendiente de decisión del usuario. Sin efecto
en plazos.

Avance previo del 06-10:
[Composición aislada de perfiles reales, ledger sensible y propietario atómico](../validation/G3_D1_REAL_SENSIBLE_COMPOSITION_2026-10-06.md).
Los dos perfiles reales se componen con el ledger sensible y con un
propietario atómico versionado, sin conectarlos a nada: propiedades reales
con límites, química y latente de un prototipo declarado, emisión y
calentamiento prescritos y presupuesto B sintético. No es un incendio
validado ni una predicción de evaporación. El ledger gana un segundo
contrato cerrado sobre las mismas leyes y el propietario cuatro puntos de
extensión; el sucesor real hereda, no añade ninguna ley y exige un
veredicto positivo explícito antes de aceptar o escribir. Vía sintética
idéntica bit a bit (1985 resultados) y pins históricos sin mover. Fixture
real 3670 comprobaciones; mutantes composición 94/94 e históricas
helper 19/19, masa 10/10, fases 12/12, emisión 11/11, replay 11/11, caller 18/18, ledger sensible 23/23, propietario 40/40, guardas 12/12, veredicto 17/17 y adaptador real 55/55. Referencia 18/18, 346/346 required, 78 gaps, 160 informes de caso byte idénticos y resumen solo generated_at; R2-1 PASS. Producto 168/168.
Global 3981 passed / 45 skipped / 2 xfailed / 42 subtests, 675,30 s, exit 0. CO/FED siguen OFF/NO-GO; B neto NO-GO. Siguiente paso,
pendiente de decisión del usuario; esta fase no conecta la composición al
incendio activo. Sin efecto en plazos.

Avance previo del 06-10:
[Esquemas reales de Cp del heptano implementados en aislamiento](../validation/G3_D1_HEPTANE_REAL_CP_IMPLEMENTATION_2026-10-06.md).
Los dos perfiles aprobados por los gates offline se evalúan en GDScript:
el bucle de integración del helper pasa a una función compartida y un
adaptador nuevo valida de forma estricta contra el contenido aprobado y
evalúa con esa misma integral. Sin predicción, sin B, sin gas real y sin
integración; el ledger y el propietario sensible siguen rechazando
perfiles reales y la composición queda para otra fase. Esquema sintético
idéntico bit a bit (933 resultados) y campaña histórica 19/19. Fixture
real 1417 comprobaciones; mutantes en Godot 55/55; regresiones
helper 19/19, masa 10/10, fases 12/12, emisión 11/11, replay 11/11, caller 18/18, ledger sensible 23/23, propietario 40/40, guardas 12/12 y veredicto 17/17. Referencia 18/18, 346/346 required, 78 gaps, 160 informes de caso byte idénticos y resumen solo generated_at; R2-1 PASS. Producto 168/168.
Global 3946 passed / 43 skipped / 2 xfailed / 42 subtests, 623,30 s, exit 0. CO/FED siguen OFF/NO-GO; B neto NO-GO. Siguiente paso,
pendiente de decisión del usuario: composición con el ledger. Sin efecto
en plazos.

Avance previo del 06-10:
[Cp del heptano líquido y supuestos del gas](../validation/G3_D1_HEPTANE_LIQUID_ELIGIBILITY_2026-10-06.md).
Gate científico offline: sin `sim/`, sin Godot, sin física nueva. Líquido:
**GO parcial**, Cp isobárico a 100 kPa entre 280 K y el punto de ebullición,
convertido desde Csat con la identidad termodinámica completa y densidad
(p, ρ, T) del archivo ThermoML del NIST; corrección máxima 0,11 %; Csat no
se acepta como sustituto. La conversión de escala se reclasifica como
aproximada, con hasta 0,056 % de diferencia frente a la reevaluación
publicada. Gas: **GO parcial condicionado**, mismo rango; la calorimetría
original no se obtuvo y el tramo supuesto queda a un 0,13 % de una
correlación oficial. Conjunto: GO parcial de diseño, dos perfiles de una
misma familia de esquema real, sin implementar. Contrato sintético: NO-GO
por diseño. B neto: NO-GO, gate aparte. Auditor offline con 93 pruebas y
34/34 mutantes offline; gas 28/28; ALL GUARDRAILS PASS con R2-1; referencia
no regenerada. Siguiente paso, pendiente de decisión del usuario: fase de
implementación del esquema real en el helper, con cadena R2-1. CO/FED
siguen OFF/NO-GO. Sin efecto en plazos.

Avance previo del 05-10:
[Elegibilidad de propiedades térmicas reales del heptano](../validation/G3_D1_HEPTANE_REAL_PROFILE_ELIGIBILITY_2026-10-05.md).
Gate científico offline: sin `sim/`, sin Godot, sin física nueva. Gas:
**GO parcial**, Cp° de gas ideal entre 298,16 y 470 K de la fuente, con el
tramo inferior a 370 K declarado como supuesto de la fuente, sin dato por
encima de 470 K y sin corrección de gas real. Líquido: **NO-GO** como Cp
isobárico; la fuente mide Csat y falta el volumen del líquido entre 273 y
371 K para convertirlo; se conserva nativo. Escala 1948 → 1968 → 1990:
GO con dos fuentes primarias. Contrato sintético actual: NO-GO por diseño;
se propone el esquema real `g3_real_ideal_gas_cp_v1`, sin implementar.
B neto: NO-GO, gate aparte. Cuatro fuentes primarias archivadas,
manifiesto 43 → 47. Auditor offline con 107 pruebas y 28/28 mutantes
offline del auditor; focal 287 passed; ALL GUARDRAILS PASS con R2-1;
referencia no regenerada. El ledger exige ambas fases, así que aún no hay
corrida con propiedades reales. Siguiente paso, pendiente de decisión del
usuario: resolver el líquido (fuente de densidad o aceptación expresa de
un sustituto con sesgo declarado) y, después, fase de implementación del
esquema real con cadena R2-1. CO/FED siguen OFF/NO-GO. Sin efecto en
plazos.

Avance previo del 05-10:
[Veredicto positivo explícito del caller cerrado técnicamente](../validation/G3_D1_POSITIVE_VERDICT_2026-10-05.md).
Cierra el límite que dejó el hotfix de guardas: el caller de referencia
aceptaba un estado cuando su validación no registraba errores, aunque no
hubiera terminado. Ahora exige un veredicto positivo explícito antes de
continuar o escribir en `initialize`, `preview_step`, `commit_step` y
`restore`. Un solo archivo de `sim/`; sin identidades, tolerancias,
esquemas, API ni fingerprints cambiados; sin integración ni física nueva.
CO/FED siguen OFF/NO-GO. Fixture 280 checks; control de aborto real
aparte; mutantes 17/17; histórica del caller 18/18; guardas de tipo 12/12
tras reforzar su fixture. Focal 977 passed / 10 skipped. Referencia
346/346, 78 gaps y 160 informes byte idénticos, resumen solo
generated_at; R2-1 PASS. Producto 168/168. Global 3727 passed / 41 skipped
/ 2 xfailed / 42 subtests, 601,26 s, exit 0. No revisa otros validadores
ni la precisión de los fingerprints heredados. Siguiente gate, sin
cambios y **no iniciado ni aprobado**: perfil Cp real de heptano y
elegibilidad de un B neto independiente. Sin efecto en plazos.

Avance previo del 05-10:
[Hotfix de guardas de tipo cerrado técnicamente](../validation/G3_D1_TYPE_GUARD_HOTFIX_2026-10-05.md).
Corrige el pendiente separado que dejó el propietario sensible: proveedor,
núcleo de masa/referencia y caller de referencia abortaban con error de
script ante un valor mal tipado donde esperaban texto, y `restore` del
caller fallaba abierto. Solo guardas de tipo: sin leyes, tolerancias,
mensajes, fingerprints ni aceptación de entradas válidas cambiados; sin
integración ni física nueva. CO/FED siguen OFF/NO-GO. Reproducción previa
777 fallos / 520 errores de script; después 3981 checks y 0 errores.
Mutantes de guardas 12/12; campañas históricas repetidas 10/10, 12/12,
11/11, 11/11, 18/18, 23/23 y 40/40. Focal 949 passed / 10 skipped.
Referencia 346/346, 78 gaps y 160 informes byte idénticos, resumen solo
generated_at; R2-1 PASS. Producto 168/168. Global 3700 passed / 41 skipped
/ 2 xfailed / 42 subtests, 593,69 s, exit 0. No cierra la precisión de
los fingerprints heredados ni los gates físicos. Siguiente gate, sin
cambios y **no iniciado ni aprobado**: perfil Cp real de heptano y
elegibilidad de un B neto independiente. Sin efecto en plazos.

Avance previo del 05-10:
[Propietario atómico sensible cerrado técnicamente](../validation/G3_D1_SENSIBLE_OWNER_2026-10-05.md).
Módulo nuevo aislado que posee contexto, progreso, fases, cuentas térmicas,
relojes y generación; no deduce el sensible de la masa acumulada. No toca
ledger, helper Cp, proveedor ni caller de referencia. No integración ni
calibración; CO/FED siguen OFF/NO-GO. W01-W22 / 4663 checks; 40/40
mutantes válidos en código final tras una primera campaña con dos
inválidos que no contó. Focal 917 passed / 10 skipped. Referencia 346/346,
78 gaps y 160 informes byte idénticos, resumen solo generated_at;
18 lanzamientos limpios y R2-1 PASS. Producto 168/168. Global 3667 passed /
41 skipped / 2 xfailed / 42 subtests, 586,90 s, exit 0; un primer intento
con nueve rechazos por memoria bajo 6 GiB no contó. Tandas secuenciales.
El fingerprint liga contenido, no firma ni autentica la historia.
Pendiente separado sin corregir: error de tipos en proveedor, referencia
y caller anterior. Con esto la cadena helper → ledger → propietario queda
completa como contrato sintético. Siguiente gate **propuesto, no iniciado
ni aprobado**: perfil Cp real de heptano y elegibilidad de un B neto
independiente. Este avance no altera plazos de publicación.

Avance previo del 04-10:
[Ledger sensible cerrado técnicamente](../validation/G3_D1_SENSIBLE_LEDGER_2026-10-04.md):
API versionada del dueño actual de masa/CHO, separa A/S/B/Q y conserva la
entalpía de mezcla y oxidación. No cambia las once funciones anteriores,
el helper Cp, provider o caller de referencia. No integración ni nueva
calibración; CO/FED siguen OFF/NO-GO. L01-L20 / 915 checks; 23/23 mutantes
válidos en código final; focal ampliada 416 passed / 10 skipped. Referencia
346/346, 78 gaps y 160 informes byte idénticos, resumen solo generated_at;
18 lanzamientos limpios y R2-1 PASS. Producto 168/168; global 3640 passed /
41 skipped / 2 xfailed / 42 subtests, 552,47 s, exit 0. Tandas secuenciales.
El propietario nuevo deberá ligar contenido e historial, no solo component_id.
Orden posterior: propietario atómico sensible versionado -> gates físicos.

Avance previo del 04-10:
[Helper sensible implementado](../validation/G3_D1_SENSIBLE_IMPLEMENTATION_2026-10-04.md):
Cp(T) isobárico sintético e integral firmada, S01-S20 / 342 checks en GDScript,
oráculos analíticos Python previos; focal con módulos congelados 76 PASS.
Sin integración física ni ledger/caller sensibles. Cierre técnico en verde:
19/19 mutantes válidos; focal ampliada 406 passed / 10 skipped; referencia
346/346, 78 gaps y 160 informes byte idénticos; R2-1 PASS; producto 168/168;
global final 3630 passed / 41 skipped / 2 xfailed / 42 subtests, 523,10 s.
Primera global con dos fallos del arnés nuevo, corregidos sin tocar tests
históricos o el modelo, y repetida completa. CO/FED siguen NO-GO.
Orden posterior: ledger sensible -> propietario versionado -> gates físicos.

Avance previo del 04-10:
[Contrato de entalpía sensible](../validation/G3_D1_SENSIBLE_CONTRACT_2026-10-04.md)
listo para primera pieza GDScript: Cp(T) sintético isobárico con integral
canónica, sin integración/masa/oxidación. Separar después A/S/B/Q y
trabajo/entalpía frente a energía interna; no usar Cp como Cv.
Fuente NBS 1954 y chequeo offline incorporados, sin convertir Csat a Cp
ni adaptar en silencio escala histórica/ref/masa molar. S01-S20 y
mutantes predeclarados, todavía no fixture de motor implementada.
Orden: helper de propiedades -> ledger sensible -> propietario versionado;
el caller de referencia actual queda congelado. NO-GO a predicción,
muebles, transporte/FED promovidos o perfiles materiales automáticos.
Focal inicial 113 PASS/30 nuevas; ampliada final 161 PASS con emisión/masa.
Guardarraíles con R2-1/estilo/enlaces/diff PASS; manifiesto 43 entradas.
No es prueba de S01-S20 ni implementación del helper todavía.

Avance previo del 04-10:
[Gate térmico independiente](../validation/G3_D1_POOL_THERMAL_EVIDENCE_2026-10-04.md)
cerrado como revisión focal y auditor offline. TN 2162r1/snapshot MaCFP
versionados; hay flujo medido hacia sensor, no solo datos invertidos de
masa. GO al observable de sensor y diseño sensible aislado; NO-GO a B
neto, evaporación predictiva o integración. Temperatura/altura de heptano
no resueltas; constantes MaCFP no son una curva transitoria medida.
50 tests nuevos, focal 131 PASS; no Godot ni cambios de `sim/`/referencia.
Siguiente: Cp(T), estados y almacenamiento con referencia común,
primero diseño y controles sintéticos. No inventar B para cerrar ese
contrato; la elegibilidad del benchmark neto se resuelve por separado.

Avance previo del 04-10:
[Caller atómico aislado](../validation/G3_D1_ATOMIC_CALLER_CONTRACT_2026-10-04.md)
implementado en GDScript y probado con datos sintéticos: 361 checks / 20
grupos, 18/18 mutantes válidos detectados, focal 524 PASS / 10 skipped.
Raíz única, generaciones/copias profundas y relojes separados; química e
integral siguen en sus dueños originales, congelados por hash. Contratos
de aislamiento adaptados únicamente al caller, sin carga desde producto.
Referencia actual 346/346, 78 gaps y 18 informes byte idénticos, resumen
solo fecha; ALL GUARDRAILS PASS con R2-1. **Cierre técnico aislado completo**:
producto 168/168, 81 lanzamientos limpios; global 3535 passed / 41 skipped /
2 xfailed / 42 subtests passed, exit 0, 516,80 s. Reanudación tras liberar
memoria: 6,032 GiB antes de producto, 6,372829 antes de global; tandas
secuenciales por monitor >=6 GiB, UTF-8 heredado y temporales nuevos.
Los intentos de producto abortados por codificación o memoria no se dan
por aprobados; se repitió la cadena pendiente sin cambiar `sim/`.
No integrar ni introducir datos reales,
evaporación predictiva, U, muebles o CO/FED. El avance técnico se confirmó
en `6f8f41b0` y se combinó con el main remoto en `a5f575b2`, sin cambios
adicionales en `sim/`. [Gate de integración Git](../validation/G3_MAIN_INTEGRATION_2026-10-04.md):
GO tras importación limpia, AI 17/17, producto 168/168 y global 3535 passed /
41 skipped / 2 xfailed / 42 subtests, 529,11 s sobre la combinación.
No confundir integrar la rama con conectar el caller al paso de simulación.
Publicación/integración Git confirmada el 04-10 en `e7a0601f`, con ambos
remotos actualizados y los 80 archivos locales ajenos preservados por hash.
Siguiente: evidencia térmica independiente y sensible, con atribución
compatible de masa/material; el caller no identifica por sí mismo B real.

Avance previo del 04-10:
[Contrato del caller atómico](../validation/G3_D1_ATOMIC_CALLER_CONTRACT_2026-10-04.md)
cerrado como diseño tras revisar las dos APIs GDScript. GO a implementar
controlador aislado con datos sintéticos: única raíz confirmada, generación,
copias profundas, contexto completo, commit recalculado y restore conjunto.
Cursor/masa/productos/B/Q comprobados con dueños canónicos; sin segunda
integral/estequiometría. Reloj de fuente separado del físico para quemar
vapor después del fin de curva. Caps válidos registran déficit sin cola;
rechazos transaccionales no avanzan. 20 grupos/18 defectos predeclarados,
no ejecutados; código del caller todavía no existe. Alcance cerrado sin
contornos/pérdidas/retorno Q a B. Próximo cambio: módulo GDScript y fixture
real, mutaciones/aislamiento y cadena R2-1 completa secuencial por monitor.
No fuente real importada, integración, U, muebles o CO/FED. Sin Godot,
commit/push ni modificación de `sim/` en el diseño.
Regresión offline del alcance existente: 155 PASS, dos fixtures Godot
excluidas; guardarraíles incluido R2-1, estilo/enlaces/diff PASS.
No confundir esta regresión con prueba del caller que falta implementar.

Avance previo del 04-10:
[Atribución de emisión y B](../validation/G3_D1_ISOHEPT9_EMISSION_BASIS_2026-10-04.md)
revisada en montaje/tablas originales de TN 1603. La pérdida de masa es
base razonable de replay bajo hipótesis explícita; no mide composición
gaseosa ni identifica calor neto absorbido/temperatura del líquido.
Los 71 canales quedan clasificados y comprobados por auditor offline.
Coste de fase de referencia condicionado: 7081,108094 kJ en 0-500 s,
no B medido ni valor a imponer para validar evaporación. 127 pruebas
offline PASS, 21 nuevas; sin Godot o cambios en `sim/`/informes.
GO al diseño de caller atómico puro con masa/energía de contorno declaradas;
NO-GO a predicción física, sensible identificado, integración, U, muebles
y CO/FED. Siguiente: contrato conjunto demanda/aceptación/cursor/masa/energía
y controles sintéticos de déficit, rechazo y reinicio. En paralelo de plan,
revisar elegibilidad de TN 2162r1 para datos térmicos independientes; solo
candidato localizado, no importado ni transferible al recinto por defecto.
Sin commit/push; no atribuir al gate las suites completas previas.

Avance previo del 04-10:
[Ledger de fases](../validation/G3_D1_PHASE_LEDGER_2026-10-04.md) implementado
en el núcleo GDScript aislado, sin integración. Coste de fase y potenciales
líquido/vapor explícitos; A+B+Q cerrado en controles sintéticos. 502 checks,
12/12 mutantes nuevos y 10/10 históricos; 1298 propuestas v1 byte idénticas.
Focal conjunta 473 PASS / 10 skipped. **Cierre R2-1 completo sobre este
núcleo**: referencia 346/346 y 78 gaps, 18 informes byte idénticos, resumen
solo timestamp, ALL GUARDRAILS PASS; producto 168/168 y 81 solicitudes
limpias; global 3484 passed / 41 skipped / 2 xfailed / 42 subtests, exit 0.
Todo secuencial por monitor, con umbral 6 GiB antes de cada lanzamiento.
NO-GO a integración, evaporación predictiva, lote ISOHept9, U, muebles y CO/FED.
Sin commit/push; solo worktree de G3. No confundir ledger con validación
experimental del incendio o corrección activa en escenarios.
Siguiente gate: masa realmente emitida, energía sensible y origen térmico
independiente de B antes de unir replay/ledger. No inventar presupuesto
para forzar la curva medida ni interpretar el cap como predicción física.

Avance previo del 04-10, después del replay:
[Base energética con fases](../validation/G3_D1_HEPTANE_PHASE_BASIS_2026-10-04.md)
identificada para n-heptano de referencia: fuente 2026 archivada, ciclos de
Hess offline y contrato de potencial/energía térmica sin doble cuenta.
140 pruebas offline PASS, 3 fixtures Godot excluidas; guardarraíles intactos.
GO al prototipo GDScript puro con fases y oxidación canónica compartida;
NO-GO a ensayo físico completo, integración y CO/FED. Falta energía sensible,
atribución del lote y masa emitida. No cambios en `sim/` ni nuevas suites Godot.

Avance previo del 04-10:
[Replay numérico de masa](../validation/G3_D1_ISOHEPT9_REPLAY_2026-10-04.md)
cerrado técnicamente; focalizada 110 PASS, fixture real 2459 checks, error ~1,1e-14
kg. Formato constante por intervalo con identidad/cantidad separadas; modo
lineal anterior byte idéntico. Mutantes 11 nuevos + 11 históricos detectados.
**Cierre R2-1 completo**: referencia 346/346, 78 gaps, 18 informes byte
idénticos; producto 168/168; global final 3426 passed, 39 skipped,
2 xfailed, 42 subtests. Auditoría/focalizada final 415 PASS, 8 skipped tras
adaptar la bandera de fallo de la fixture; once mutantes nuevos repetidos.
No integración/activación, commit/push ni prueba de una ley de evaporación.
Siguiente: fases/base
energética antes del núcleo; U, muebles, química parcial y CO/FED NO-GO.

Avance previo del 03-10:
[serie medida ISOHept9](../validation/G3_D1_ISOHEPT9_BENCHMARK_GATE_2026-10-03.md)
localizada/archivada con procedencia NIST, 187 muestras a 5 s, sin procesar.
Auditor nuevo 27/27 PASS. GO parcial a preparar replay de masa 0-500 s
del proveedor aislado, no benchmark físico completo: líquido no es sólido,
medias de intervalo no son nodos de tasas lineales y fase/energía siguen
pendientes. La cola tiene aumentos/masas negativas y no se recorta. No se
toca `sim/` ni se lanza Godot; no nueva referencia/global, commit/push o
perfil activable. No cambia el NO-GO de CO/FED, U, muebles e integración.

Avance previo posterior del 03-10:
[proveedor GDScript prescrito](../validation/G3_D1_PRESCRIBED_RELEASE_2026-10-03.md)
cerrado técnicamente y sin integración: demanda kg por intervalo, confirmación
separada, rechazo sin cola, cursor/fingerprint y reinicio conjunto con masa.
Fixture conjunta 247 checks / 83 grupos, 72 pruebas PASS, 11/11 mutantes
válidos detectados. Referencia nueva 346/346 y 78 gaps, 18 informes de caso
idénticos byte a byte; producto 168/168; global 3382 passed, 37 skipped,
2 xfailed y 42 subtests. Todo secuencial por monitor, sin commit/push.
Siguiente gate: benchmark experimental de masa independiente y alcance
estrecho, no integrar ni asignar perfiles reales antes de revisar fuentes,
composición y base energética. Coherencia del dueño atómico, especie/zona,
coste térmico, rendimiento con curvas reales y química siguen pendientes.

Último avance del 03-10:
[contrato del proveedor de masa/material](../validation/G3_D1_MASS_MATERIAL_PROVIDER_CONTRACT_2026-10-03.md)
verificable offline, 46 pruebas nuevas y diez mutantes válidos contrastados;
62 PASS con auditor y tests estáticos del núcleo. Masa inicial independiente,
composición CHO/base química y emisión prescrita se atribuyen al mismo
componente, con procedencia por magnitud. No datos reales importados ni
perfil de producto aprobado: hash y esquema no son validación científica.
No cambia `sim/` ni se repiten referencia/global; no se lanza Godot.
Siguiente: proveedor aislado por intervalo y fixture GDScript conjunta,
antes de integración y de cualquier ley de muebles o CO/FED. La identidad
de U y la migración automática siguen NO-GO.

Avance del 27-09: G3-0 tiene cinco controles dinámicos terminados y un
defecto de atribución de CO reproducido (objeto sin arder → 2,92 veces más
CO); G3-1 tiene inventario estático de los 14 JSON y 13 pruebas focalizadas.
Avance del 28-09: G3-0 añade cuatro [controles de topología](../validation/G3_CO_TOPOLOGY_BASELINE_2026-09-28.md)
con puerta cerrada/abierta, apertura escalonada de puerta y ventana y
camino entre plantas. Los balances de sala cierran a la resolución del
CSV. Un snapshot opt-in posterior midió directamente el CO pendiente de
entrega: explica el residuo global final de los cuatro casos con error
máximo `4,6e-8 kg`. No cierra todavía el presupuesto por paso/zona ni
valida la concentración frente a un ensayo. G3-0 sigue parcial.
G3-2 tiene una primera [ficha FCD versionada](../validation/G3_NIST_FCD_FURNITURE_SUMMARY_2026-09-27.json)
de cuatro ensayos: dos sofás completos candidatos solo para aire libre,
una alfombra con cojines no aislable y una mesa bajo límite de detección.
Los resúmenes por sí solos **no** son curvas de emisión. Los cuatro CSV
crudos están [importados y auditados](../validation/G3_CO_PRODUCCION_COMBUSTIBLES_ESTANCIA_2026-09-27.md):
reproducen picos e integrales HRR; la fórmula de la guía FCD permite una
reconstrucción **provisional** de CO neto en el escape. Los totales de 29,
30 y 28 concuerdan con sus fichas dentro de la incertidumbre; 28 mezcla
alfombra y cojines, y 18 está bajo detección y con piloto activo. La
versión 2026 del procesado y el fondo elegido no están verificados, y no
hay pérdida de masa temporal para calcular `Y_CO(t)`. HCN, regímenes
subventilados y familias restantes siguen pendientes. El
[cotejo TN 2303/FCD](../validation/G3_NIST_TN2303_FCD_RECONCILIATION_2026-09-28.md)
fija que 29/30 conservaron masa y THR mientras cambió `Y_CO`; TN 2303
midió masa transitoria solo en Tests 1–24. HCN global existe en la tabla
2025, **no** en los CSV/fichas 2026: se mantiene separado y no calibrado.
Avance del 29-09 ([procesado y elegibilidad](../validation/G3_CO_FUENTES_ELEGIBILIDAD_2026-09-29.md)):
NIST no publica código ni notas de `NFRL_Report_8.7.1`; con los 48 CSV y
fichas archivados, el método de la guía reproduce la FCD 2026 en 42/43
ensayos, THR no cambia entre versiones, la masa sí en 31/35/38, y la causa
del cambio de CO sigue **sin demostrar** (integrar hasta fin de archivo
explica 10 de 13 desfases, no todos). Una matriz de 14 fuentes no encuentra
`MLR(t)` numérica y CO(t) del mismo ensayo a escala de objeto: G3-2 queda
**NO-GO para `Y_CO(t)` por objeto**. Falta la masa numérica de TN 2303
Tests 1–13/16/17/19–24, las series crudas de TN 1453 (o equivalentes en
recinto ventilado y viciado) y las exportaciones 2025 o su registro de
cambios. El único candidato de calibración es material a escala de banco
(cono FSRI), sin validez por objeto ni subventilada.
G3-3 se ha iniciado con un libro **pasivo** de combustible y CO por paso:
confirma que la silla consume 0 MJ en los 1.081 pasos del control, aunque
altere el CO de la sala. La ampliación v2 registra también CO₂/HCN, humo,
O₂ y gas zonal; CO y humo cierran sus contadores de sala por paso en el
corpus, y la silla fría altera el humo generado en −7,11 %. Aún no hay
fuente por objeto ni cierre elemental/de transporte de todas las especies.
G3-1 añade un control dinámico con cargas desiguales: estancia 3 MJ / sofá
1 MJ libera otros 1,998060 MJ **después** de agotarse el sofá; estancia
1 MJ / sofá 3 MJ se limita a 1 MJ y deja ≈2 MJ en el objeto. Confirma la
precedencia de la estancia, no la procedencia de las 23 diferencias reales.
Véase [gate G3-1](../validation/G3_FUEL_OWNERSHIP_DYNAMIC_GATE_2026-09-27.md).
La [matriz de procedencia](../validation/G3_FUEL_PROVENANCE_MATRIX_2026-09-27.md)
ubica los 23 valores: 17 literales en tres JSON de referencia y seis
reproducidos por la plantilla de dos plantas. Su **significado físico**
sigue sin declararse; ninguna fila se promociona de `legacy_unknown`.
**No** se ha clasificado aún la procedencia de las cargas ni se ha cambiado
la física. Véanse [baseline G3-0](../validation/G3_FUEL_SOURCE_DYNAMIC_BASELINE_2026-09-27.md)
y [checkpoint G3-1](../validation/G3_FUEL_SOURCE_OWNERSHIP_AUDIT_2026-09-27.md).
Avance del 29-09 ([cierre G3-1](../validation/G3_FUEL_OWNERSHIP_CLOSURE_2026-09-29.md)):
matriz individual de 23 discrepancias (`legacy_unknown`, bloqueadas) y 7
presets sin objetos (`legacy_lumped`, se mantienen); 0 migrables. Nueve
casos dinámicos demuestran energía sin dueño tras agotarse un objeto
(1,998 MJ), un objeto frío que entra en los topes de energía y HRR del
fuego (+2,996 MJ de inventario contado dos veces, HRR 168 kW, CO ×14,05),
la carga de sala que trunca al objeto (2,0 MJ sin quemar) y HRR por objeto
por encima de su máximo declarado; no hay doble conteo de HRR por paso.
Contrato de propiedad C1–C9 propuesto y fijado en pruebas. **GO** para
instrumentar G3-3 como libro pasivo; **NO-GO** para cerrarlo o migrar sin
autorizar un cambio del motor bajo interruptor OFF.
Avance posterior del 29-09 ([G3-3 y propiedad energética](../validation/G3_FUEL_LEDGER_OWNERSHIP_2026-09-29.md)),
tres decisiones separadas: **G3-3 instrumentado** (libro v3 por paso y
propietario, inerte byte a byte y con cierre numérico `1e-9 MJ`/paso en 9
casos); **propiedad energética corregida en `explicit_objects`** detrás de
`fire_explicit_object_fuel_ownership_enabled` (OFF por defecto; solo salas
sin carga de sala; 0 MJ sin dueño, sin calor sin combustible y topes por
objeto respetados; OFF idéntico en 9/9; 4/4 mutantes detectados); y **CO/FED
no validados**: C6 sigue fallando (CO ×2,92 con silla fría y mismo
combustible) porque la química no se ha tocado.
Revisión Gate A/B del 29-09: la [procedencia del informe de referencia](../validation/G3_REFERENCE_PROVENANCE_PORTABILITY_2026-09-29.md)
se normaliza a LF canónico y rutas relativas tras probar las 38 diferencias
CRLF/LF archivo por archivo; es un cambio de metadatos, no de checks. El
[presupuesto energético](../validation/G3_ENERGY_BUDGET_DIAGNOSIS_2026-09-29.md)
localiza en los nueve controles todo el desfase `consumido − calor sólido`
en el suavizado del HRR, con generación de pool cero. El modo ON deja
0,933784 MJ de pirólisis del sofá sin destino modelado; **NO-GO para
declarar cerrada la física energética o activar el modo en producto**.
Diseñar y falsar un inventario intermedio, una pérdida explícita o una
liberación distinta requiere una fase propia, antes de G3-4 química.
Revisión posterior del 29-09: los 26 fallos «nativos» de la suite global
fueron cuadros obsoletos de un `check_product` lanzado en el sandbox, que el
monitor atribuía a cada ejecución sana y mataba ([diagnóstico](../validation/G3_GODOT_NATIVE_POPUP_DIAGNOSIS_2026-09-29.md));
el lanzador se niega ahora a arrancar con un cuadro previo y la suite
global pasa una vez (3062 passed, 35 skipped, 2 xfailed). El
[diseño del destino de la energía retrasada](../validation/G3_ENERGY_DELAY_DESIGN_2026-09-29.md)
mide el origen del cociente (subida τ≈10,8 s frente a bajada τ=20 s) y
propone inventario `R` por objeto con liberación en la cola y paso al pool
al extinguirse, con pruebas F1–F7; **pendiente de aprobación, sin implementar**.

Avance del 03-10 ([D1 y su identificabilidad](../validation/G3_D1_IDENTIDAD_INQUEMADO_2026-10-03.md)):
G3-4A tiene cuenta energética U implementada y verificada, sin asignar masa
ni fase. Se retira la inferencia «todo U es gas». El diagnóstico estático
confirma que no hay inventario de kg por objeto ni curva MLR declarada en
los 107 objetos distribuidos; las fórmulas MLR existentes no debitan masa.
El siguiente trabajo técnico es un núcleo puro en GDScript con masa
liberada y oxidada independientes y balances, sin integración ni ley
material. Mantener separados HOC efectivo de ensayo y energía química.
G3-2, la física de U y CO/FED permanecen limitados/NO-GO; no se ha validado
una emisión por material ni migrado los escenarios distribuidos. Este
avance sustituye como trabajo pendiente la propuesta histórica de pasar
R al pool, no altera los informes anteriores.

Continuación del 03-10: escrito el
[núcleo puro GDScript](../validation/G3_D1_FUEL_MASS_BUDGET_2026-10-03.md),
sin integración, con fixture real 271 checks / 39 grupos y 10/10 mutantes
válidos detectados. Tras liberar memoria se cerró secuencialmente R2-1
(346/346, 78 gaps, 18 informes idénticos), producto (168/168) y global
(3323 passed, 37 skipped, 2 xfailed, 42 subtests). GO técnico al núcleo,
no a la física de U ni a la calibración de muebles/CO/FED. Siguiente:
contrato del proveedor de masa/material con procedencia y bases explícitas;
no migración ni integración automática.

## Objetivo y definición de cierre

Poder explicar, reproducir y contrastar, en el alcance de viviendas y
combustibles que se declare para producto, esta cadena completa:

```text
inventario combustible → pérdida de masa/pirólisis y HRR → CO/CO₂/HCN/humo
→ oxidación y transporte de gas/especies → concentración por zona y altura
→ dosis FED y presentación de SVV
```

«Cerrado» no significa que todos los 38 arquetipos tengan datos medidos o
que SimuFire coincida exactamente con CFAST. Significa que **cada afirmación
de producto** tiene un rango de validez y evidencia explícitos; cada caso
distribuido tiene una fuente de combustible inequívoca; los balances y las
regresiones cierran; y los casos fuera de alcance están identificados, no
ocultos detrás de un rendimiento global. Si falta un ensayo indispensable,
la rama afectada termina como **LIMITADA/NO-GO**, nunca como validada por
suponer un número. La fecha de publicación depende de este resultado.

## Baseline y reglas para todas las fases

- Tomar checkpoint de Git, flags, escenarios, Godot y memoria antes de correr
  nada. Preservar los cambios locales ajenos. Ejecutar Godot de una sola
  tanda, bajo el monitor seguro usado por el proyecto; no iniciar la suite
  completa con memoria insuficiente ni dejar procesos residuales.
- Congelar antes de modificar física las trazas de escenarios con y sin
  muebles, estados de cada objeto, HRR, O₂, temperatura, flujos, especies por
  zona y FED. Etiquetar si cada referencia es experimento NIST, salida CFAST,
  fixture interno o escenario de producto: no son patrones intercambiables.
- Todo cambio físico nuevo va detrás de un interruptor OFF por defecto. OFF
  debe conservar salidas byte a byte; ON exige presupuesto, pruebas de casos
  límite y mutaciones válidas. Mantener los 346 required PASS y los 78 gaps
  sin reclasificarlos en silencio; aplicar R2-1 y suite global cuando se toque
  `sim/core`. Las cifras son el último baseline conocido, no una dispensa
  para no medir de nuevo.
- No fijar tolerancias empíricas después de ver el resultado candidato.
  Establecerlas en el protocolo a partir de incertidumbre experimental,
  resolución y sensibilidad; informar sesgo, dispersión y fallo por caso.

## Orden de ejecución

| Fase | Trabajo y entrega | Gate de salida |
| --- | --- | --- |
| G3-0. Mapa causal y baseline | Corpus mínimo: sala vacía, sofá solo, sofá + mueble frío, sala amueblada, agregado `legacy_lumped`, dos salas/puerta, puerta y ventana variables, y edificio de dos plantas. Trazas OFF actuales y matriz de dueños de cada término de CO. | Resultados reproducibles, rutas y unidades identificadas; ningún ajuste de física. |
| G3-1. Propiedad del combustible | Inventario de los 14 JSON distribuidos, plantillas/editor y casos de referencia. Clasificar carga de sala, objetos, acabados y contenido no dibujado, con procedencia y modo `explicit_objects`, `legacy_lumped` o `legacy_unknown`. Resolver manualmente las 23 discrepancias y los 7 presets sin objetos antes de migrarlos. Diseñar carga adicional **nombrada**, no inferida por tipo de habitación. | Un solo propietario por MJ y por kg de combustible; ningún escenario de producto ambiguo presentado como validado. Casos de referencia agregados intactos. |
| G3-2. Datos por material/objeto | Fichas versionadas con fuente y unidades para masa/energía, HRR o MLR temporal, calor efectivo, O₂, CO, CO₂, HCN, humo/hollín y condiciones de ventilación/fase. Importar curvas NIST TN 2303/FCD y TN 1453 con checksum, revisar ignitores mezclados y discrepancias entre versiones. Preparar una sala amueblada **reservada para validación externa**. | Familias/materiales del alcance publicado tienen intervalo y procedencia; campos desconocidos son explícitos. No atribuir a mesa/alfombra una medición que incluye cojines; no convertir kg/kg a kg/MJ sin calor correspondiente. |
| G3-3. Libro contable pasivo | Instrumentar sin autoridad física, por objeto y paso: masa perdida, pirólisis, energía, HRR, O₂, CO/CO₂/HCN/humo generados, oxidación y retención. Por sala/zona: entradas, salidas, inventario, proyección y clamps. Comparar fuente agregada con suma de objetos. | Cierre por paso y acumulado de combustible, elementos/especies y energía según tolerancias numéricas predeclaradas. Mueble frío no emite ni altera la química del que arde; sala vacía no crea combustible; OFF idéntico. |
| G3-4. Fuente de incendio y especies | Corregir primero el dueño de HRR/energía (`FireModel` frente a objetos) sin mezclarlo con transporte. Nueva producción por objeto activo y régimen: llama ventilada, ventilación limitada, pirólisis/latencia; separar energía liberada de masa perdida. Usar la misma asignación de combustible para CO, CO₂, HCN, humo, carbono y O₂. Mantener vía agregada explícita para validación. | Sin combustible/CO fantasma ni doble conteo. Curvas HRR, MLR, tasa y acumulado de CO contrastadas contra ensayos individuales y sala amueblada; sensibilidad y errores reportados. El modelo no se aprueba por igualar un único total final. |
| G3-5. Transporte y zonas | Solo tras cerrar la fuente, seguir gas y cada especie por penacho, puerta, huecos, ventana, HVAC, deposición de capa, chorro, oxidación y mezclas. Corregir propietarios canónicos de gas y especie, no imponer una transferencia exclusiva de CO. Contrastar dos salas, multipiso y fixture residencial con sensores a alturas conocidas. | `final − inicial = producción − oxidación + entradas − salidas` por sala y zona; cierre simultáneo de gas, CO, CO₂, O₂ y energía. Comparación temporal con varios casos CFAST **y** al menos un ensayo medido NIST, con geometría/ventilación/sensores homologados. |
| G3-6. FED/SVV y observables | Con concentración zonal validada, probar 0,9/1,5/1,8 m, interfaz móvil y sin capa; aislar CO, HCN, hipoxia, CO₂ y calor con concentraciones impuestas. Revisar `co_lower_ppm`, selector FED, doble representación de CO₂, unidades y acumulación. Separar valor actual, peor histórico, dosis y heurística SVV en UI/log/CSV. | Fórmulas reproducidas independientemente con entradas impuestas; continuidad y monotonía física donde proceda; ningún `SVV=%` presentado como probabilidad médica ni FED como garantía de supervivencia. |
| G3-7. Promoción y producto | Migrar solo escenarios cuyo inventario y familias estén respaldados; revisar visualmente objetos y contenido no dibujado. Ejecutar corpus ON/OFF, mutaciones, producto, global y referencia. Revisar documentación de límites y observables. Decidir activación por perfil, no global. | Acta GO/NO-GO por perfil con evidencia, incertidumbre y exclusiones. Si algún gate falla, flag OFF y salida etiquetada experimental/no cuantitativa. |

## Dependencias que no se pueden saltar

G3-1 y G3-2 pueden avanzar en paralelo **como tareas de documentación/datos**.
G3-3 necesita el inventario de fuentes; G3-4 necesita G3-2 y G3-3; G3-5
necesita una fuente trazable; G3-6 necesita concentraciones fiables. Antes de
promover G3-4/5, cerrar o acotar los defectos de O₂ y energía que alteren
combustión y flujos; en particular no interpretar una curva de CO como error
del rendimiento si su O₂ o su combustible no conservan masa. Un experimento
puede medir fases posteriores antes, pero no convertirlas en física canónica
fuera de orden.

## Matriz mínima de falsación

- Inventario: vacío; un combustible; dos iguales; segundo objeto frío;
  agotado; contenido adicional declarado; legacy agregado; JSON ambiguo.
- Química: mismo objeto con distinta ventilación y O₂; precalentamiento sin
  llama; pirólisis con HRR bajo; transición a flashover; fuego que decae;
  carbono/nitrógeno disponibles; CO generado frente a CO oxidado.
- Transporte: cerrado/abierto; ventana y viento; hueco vertical; HVAC OFF/ON;
  masas zonales casi nulas; cambio de interfaz; especie sin fuente; comparación
  de suma de zonas con total de recinto.
- Exposición: sensor impuesto arriba/abajo, cruce de interfaz, tiempo de
  exposición, reinicio, CO₂ dual, pérdida de visibilidad y calor aislados.
  Ninguna prueba debe tomar como oráculo otra función del mismo motor cuando
  pueda usarse una cuenta independiente.

## Resultados y decisiones que debe entregar cada fase

Cada fase termina con: checkpoint inicial/final; hipótesis y controles;
dataset/versión/checksum; ecuaciones y unidades; trazas antes/después;
presupuesto con residuo máximo y acumulado; sensibilidad; fixtures y
mutaciones; resultado OFF/ON; suites; archivos tocados; limitaciones;
decisión **GO, NO-GO o LIMITADA**. Un NO-GO es un cierre honesto de la
investigación de esa rama, pero **no** autorización de publicación de una
métrica cuantitativa de CO/FED para ella. Commit/push solo con autorización
y según el protocolo de la fase; este plan no los ejecuta.

## Fuentes y documentos de entrada

- [Auditoría de propietarios de combustible](../validation/G3_FUEL_SOURCE_OWNERSHIP_AUDIT_2026-09-27.md).
- [Producción de CO por combustible y estancia](../validation/G3_CO_PRODUCCION_COMBUSTIBLES_ESTANCIA_2026-09-27.md).
- [Procesado CO 2025/2026 y elegibilidad de fuentes G3-2](../validation/G3_CO_FUENTES_ELEGIBILIDAD_2026-09-29.md).
- [Gate de transporte CFAST/NIST](../validation/G3_CO_CFAST_NIST_TRANSPORT_GATE_2026-09-27.md).
- [Diagnóstico de FED/SVV](../validation/G3_FED_SVV_DIAGNOSTICO_2026-09-26.md).
- [Hoja de ruta general](MASTER_ROADMAP_CURRENT.md).
