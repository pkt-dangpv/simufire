# G3/D1 - Propiedad sensible sintética aislada

Fecha: 2026-10-04. Entrada: `dda1d0ca`, rama shareable.
Estado: cierre técnico aislado completo; cadena R2-1/producto/global en verde.

## Alcance y decisión

Implementado [SensibleEnthalpyModel.gd](../../sim/fire/SensibleEnthalpyModel.gd),
conforme al [contrato predeclarado](G3_D1_SENSIBLE_CONTRACT_2026-10-04.md).
Es un helper GDScript real, no una implementación Python sustitutiva.
GO técnico a propiedades sintéticas; NO-GO a materiales calibrados,
evaporación predictiva, ledger sensible, caller sucesor o integración física.
CO/FED y perfiles de producto no cambian.

`validate_profile` acepta únicamente el esquema cerrado isobárico sintético.
`evaluate` interpola Cp por tramos e integra desde 298,15 K con signo,
sin extrapolación, calor latente ni química. Un desbordamiento se rechaza
sin candidato. La media de extremos se calcula como dos mitades para
evitar un desbordamiento artificial de la suma antes de dividirla por dos.
La procedencia debe empezar por `synthetic:`: declaración de alcance,
no verificación de autenticidad ni aprobación experimental.

`validate_profile` devuelve el perfil validado en `candidate`, con copia
profunda; `evaluate` devuelve allí Cp, entalpía específica firmada e
identidad/rango/referencia. Las declaraciones de alcance y aprobación
están en la raíz de ambas respuestas, incluso en rechazo.

Entradas intactas y copias profundas; sin estado mutable de instancia,
preloads del motor, archivos, tiempo, masa, oxidación, flags ni `@export`.
Los tres módulos previos permanecen congelados por SHA-256 normalizado LF.
Ningún código de producción carga el helper; los tests fijan ese aislamiento.

## Verificación focal y controles negativos

Oráculos Python independientes fijados y ejecutados **antes** del GDScript:
primitivas analíticas Decimal, no copia del integrador. Comparación adicional
de siete observables emitidos por Godot con esos oráculos.
[Fixture](../../tests/fixtures/g3_sensible_enthalpy.gd): S01-S20,
342 comprobaciones, incluida referencia dentro de varios tramos y ambos signos.
Malla analítica de 101 consultas; tolerancia 1e-9 absoluta + 1e-12 relativa,
sin cambiar tolerancias físicas o atribuirle incertidumbre experimental.

Primera ejecución: error de comparación bool/String en `caloric_model`;
rechazo explícito del tipo añadido, control repetido sin error de script.
Focal final helper/masa/liberación/fases/caller: **76 passed**, exit 0,
15,89 s. Tests offline del helper: 10 passed, 1 runtime excluido en esa tanda.

[Mutaciones](../../scripts/simulation/run_g3_sensible_enthalpy_mutations.py):
19 variantes predeclaradas y control, cada uno en proyecto aislado. Cubren
referencia, signo, Cp final en vez de integral, tramos omitidos, clamp,
Cp cero/negativo, bool/NaN, duplicados/orden, unidades/Csat, alias,
calor latente, referencia alterada, autoridad y desbordamiento.
No se mutan archivos del árbol de trabajo. Errores de sintaxis/runtime,
fallos del monitor o exit inesperado no cuentan como mutantes detectados.
Campaña final repetida tras adaptar el arnés: **19/19 mutantes válidos
detectados**, control PASS / 342 checks, cero supervivientes y cero muertes
por sintaxis/runtime/infraestructura. SHA-256 de originales intactos.
La campaña de 18 variantes inicial y la primera de 19 también pasaron;
el resultado de cierre es el de 19 sobre la fixture final.

Primer global: 2 failed / 3628 passed, 41 skipped, 2 xfailed y 42 subtests,
542,75 s. Fallos reales del contrato del arnés, no de Cp/integración:

- La fixture ya fallaba con salida 1 mediante ternario/lista de errores,
  demostrado por las mutaciones. El auditor histórico exige `_failed` y
  `quit(1)` explícitos: se adopta su canal con retorno antes del PASS.
- La prueba nueva de aislamiento nombraba un interruptor reservado al
  adaptador. Se sustituye esa comprobación concreta por una regla genérica:
  el único identificador `*_enabled` permitido es el campo de informe
  `integration_enabled`, probado false; ningún interruptor físico nuevo.

No se modifica ninguna prueba histórica ni su inventario de propietarios.
Focal ampliada con ambos contratos: **406 passed / 10 skipped**, 24,40 s.
El modelo conserva el SHA de la campaña previa a referencia; solo cambian
la fixture y el test nuevos. No hay tolerancias físicas relajadas.

## Cadena de cierre

Referencia completa monitorizada: **18/18 lanzamientos limpios**, informes
nuevos, exit 0, sin errores de salud. Comparador y guardarraíles exit 0:
**346/346 required PASS, 78 gaps**, ALL GUARDRAILS PASS con R2-1.
Los **160 informes de caso** conservan SHA-256 byte a byte; resumen con
solo `generated_at`, 2026-10-04T12:31:15Z -> 2026-10-04T18:47:06Z, diff 1/1.
Los baseline retirados de evidencia autoritativa, incluido el de escalera,
siguen documentados en sus logs; no se reinterpretan ni se silencian.

Producto: **168/168 PASS**, exit 0 y sin procesos/cuadros al finalizar.
Global autoritativo final: `python -m pytest tests -q -p no:cacheprovider`,
con basetemp externo nuevo: **3630 passed / 41 skipped / 2 xfailed /
42 subtests passed**, exit 0, **523,10 s**. Memoria inicial 6,726 GiB;
la primera tanda global fallida arrancó con 6,65 GiB. Secuenciales, no
interferidas por otra suite. La adaptación del arnés no altera `sim/`,
la referencia ni los caminos ejecutados por producto; R2-1 repetido PASS.

Memoria mínima 6 GiB; ningún lanzamiento Godot directo ni proceso ajeno
terminado. Temporales superiores externos; lanzadores de fixture conservan
su aislamiento propio histórico de APPDATA bajo `runs/`.
Los 80 archivos ajenos de main siguen intactos por hash antes de integrar.
`runs/`, los sidecars UID generados y los archivos ajenos quedan fuera
del commit. Estilo habitual, enlaces locales y diff verificados al cierre.

## Siguiente pieza, todavía no implementada

API sensible versionada del ledger existente: separar A/S/B/Q y conservar
la entalpía declarada, sin duplicar masas/química ni confundir Cp con Cv
o entalpía con energía interna zonal. Después propietario atómico sucesor
capaz de conservar historia térmica variable. No conectar al producto
antes de los gates científicos posteriores.
