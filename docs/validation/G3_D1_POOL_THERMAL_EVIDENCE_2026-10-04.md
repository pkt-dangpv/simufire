# G3/D1 - Gate de evidencia térmica independiente

Fecha: 2026-10-04. Checkpoint de entrada: `6273c6a8` en la rama shareable,
ya integrado en main. Alcance: revisión de fuentes y auditor offline;
sin cambios en `sim/`, física, perfiles, escenarios o informes de referencia.

Continuado el 06-10 por el
[gate de B neto](G3_D1_NET_THERMAL_BUDGET_GATE_2026-10-06.md), que examina
las dos publicaciones de las que TN 2162r1 toma el flujo del heptano y un
benchmark de 2 m. Este informe se conserva como registro del gate.

## Decisión y avance permitido

**GO a contrastar observables térmicos independientes y a diseñar el contrato
de energía sensible con referencia común. NO-GO a identificar B neto del
líquido, evaporación predictiva o integración/activación de CO/FED.**
La fuente sí contiene flujo térmico medido: no todo se deduce de la masa.
Pero el flujo hacia un sensor refrigerado no es, sin adaptación, el calor
neto absorbido por el combustible. Tampoco identifica Cp(T) ni su estado.
El caller atómico ya está implementado y validado aisladamente; este gate
no lo conecta al paso de simulación ni modifica sus leyes.

## Fuentes incorporadas y trazabilidad

[NIST TN 2162r1, octubre de 2024](https://doi.org/10.6028/NIST.TN.2162r1),
[PDF oficial](https://nvlpubs.nist.gov/nistpubs/TechnicalNotes/NIST.TN.2162r1.pdf),
[copia local](../literature/NIST/NIST_TN_2162r1_Medium_Scale_Pool_Fires.pdf):
123 páginas PDF, 9 787 494 bytes; SHA-256
`c0ba84b39fa6e790f1242bdf594492010c9463b8f5cb61a3616036d6958d11ba`.
Para las páginas impresas citadas aquí, página PDF (base uno) = impresa + 16.
Lectura focal del montaje, instrumentación y tablas pertinentes;
no se declara revisión integral de los 123 folios.

[Compilación MaCFP/NIST fijada por commit](https://github.com/MaCFP/macfp-db/tree/213206ec45b91b2bd7d5f344ebd519662404892b/Liquid_Pool_Fires/NIST_Pool_Fires):
revisión `213206ec45b91b2bd7d5f344ebd519662404892b`. Se conserva el
README original, inventario API de 81 archivos, CSV de condiciones de
heptano y licencia MIT completa. El README reúne publicaciones distintas;
no demuestra que todos los canales sean un único ensayo sincronizado.
[Procedencia y transcripción revisada](../literature/data/NIST_POOL_FIRES_2024/PROVENANCE.json).
PDF: hash binario; textos: hash normalizado LF, independiente del checkout.
No se añaden originales FSRI ni se altera su límite de redistribución.
README/licencia originales conservan sus espacios finales y líneas vacías;
dos atributos de whitespace limitados a esas copias archivadas permiten
comprobar el diff sin alterar los hashes de origen. No eximen código ni
documentos propios. El README conserva enlaces originales a imágenes no
descargadas: es una copia de fuente, no un nuevo documento de diseño.

## Qué se puede contrastar y qué se excluye

| Evidencia y localizador | Clasificación y límite |
| --- | --- |
| TN §2.1, pp. 4-5 | Piscina de 0,301 m, alimentación por gravedad a nivel constante y bandeja refrigerada. Control de combustible abierto, no depósito cerrado de ISOHept9. |
| TN §2.9, p. 15; §3.8, p. 45; tabla F38, pp. 97-98 | Flujo total local hacia Gardon refrigerado, independiente de invertir la pérdida de masa. Transcripción manual del perfil publicado, no adquisición bruta. |
| TN tabla 10, p. 46 | Fracción de retroalimentación: numerador de flujo medido, denominador HRR derivado de masa. No constituye un presupuesto neto independiente del líquido. |
| CSV MaCFP de heptano | Dos extremos iguales a 0 y 600 s: condiciones constantes de contorno, no señal transitoria medida. HRR 112,6 kW no sustituye 106,6 kW de tabla 2 de TN. |
| Inventario MaCFP de heptano | Solo HRR/MLR, termopar de gas en eje y velocidad en eje. El termopar no es temperatura del líquido; no aparece una serie térmica del líquido de heptano. |

El enfriamiento citado pertenece al montaje experimental: no implementa
agua en el videojuego. No transferir aire libre/estado estacionario a
recintos subventilados o muebles por analogía sin validar la transferencia.

## Discrepancias conservadas, no corregidas por intuición

- Tabla 12 (p. 50): heptano 65 +/- 1 °C; tabla 13 (p. 51): Tsurf `na`.
  Apéndice G no aporta serie de líquido de heptano. Se conserva la
  discrepancia: temperatura aceptada `null`, no 65 ni un punto de ebullición
  impuesto. Tablas verificadas visualmente, no solo por extracción OCR.
- §2.9 sitúa el sensor a 3 mm sobre el borde; §3.8 menciona 3 mm sobre la
  superficie; F38 consigna z = 1,3 cm. Falta reconciliar las referencias
  geométricas; altura aceptada para comparación física `null`.
- Tabla 10 rotula diámetro en cm pero consigna 0,30; el montaje declara
  0,301 m. Se conserva el literal y se usa el montaje para el diagnóstico
  geométrico, sin reinterpretar silenciosamente la tabla.

No se declara errata de NIST ni se corrige una atribución sin fuente.
El auditor fija por separado hashes de los artefactos y de la revisión
semántica: cambiar juntos dato y aprobación no evita el rechazo.

## Diagnóstico espacial reproducible, no B físico

Los 11 puntos F38 de heptano tienen una repetición por posición y desviación
estándar no publicada (`null`, nunca cero). Se integra q(r) lineal por tramos
con peso 2*pi*r sobre r = 0 a 0,15 m, sin extrapolar al radio 0,1505 m.

Resultado: **1,2414317529925425 kW** sobre **99,33665191333428 %** del área.
Es una integral diagnóstica del perfil hacia el sensor, bajo simetría axial;
no observación del calor neto del líquido, incertidumbre propagada ni entrada
de B al ledger. No multiplicar por una duración para financiar el replay.
El método tiene controles analíticos de perfil constante/lineal, subdivisión,
soporte parcial, unidades y rechazo de valores no finitos.
[Resultado reproducible](G3_D1_POOL_THERMAL_AUDIT_2026-10-04.json).

## Verificación del alcance

`python -m scripts.simulation.audit_g3_pool_thermal_evidence` reproduce el
resultado guardado sin escribir archivos ni invocar Godot.
Focal conjunta: **131 passed**, incluidas **50 pruebas nuevas**, exit 0,
1,48 s. Prueba fuentes, semántica, licencias, conflictos, cálculo e
inmutabilidad; son controles negativos offline, no mutantes del motor.
Primera corrida inválida por permisos Windows del basetemp dentro del
worktree; repetida con basetemp externo nuevo y permisos adecuados.

No se reejecuta aquí la suite global, producto o referencia Godot:
el alcance nuevo es bibliográfico/offline y `sim/` permanece idéntico.
La cadena 3535/168/346 corresponde al checkpoint anterior, no a estos
50 tests. Referencia actual conservada: SHA-256
`ee5a7b18a0710f0bfd15f51468f45255301f6088c6b59cc09d91745d934f3da9`.
Cierre: ALL GUARDRAILS PASS, incluido R2-1, estilo GDScript PASS,
enlaces de los cinco documentos propios PASS, manifiesto válido con
42 entradas y `git diff --check` limpio. Focal repetida sobre los archivos
finales: 131 PASS, exit 0, 1,48 s. No se atribuye nueva suite global.

## Siguiente gate: sensible explícito, sin detener todo por B ausente

1. Contrato aislado de Cp(T), temperatura y entalpías de líquido/vapor con
   referencia común, usando el ledger canónico. Separar almacenamiento,
   coste de transición y energía externa; no duplicar química/integrales.
   Declarar primero parámetros y controles sintéticos. No inventar una
   curva experimental de B para poder implementar este contrato.
2. Elegir fuentes primarias de propiedades para heptano y comprobar fases,
   rango, unidades y compatibilidad con TN 2126-upd1. El contrato puede
   aprobarse sintéticamente sin afirmar validación experimental térmica.
3. Por separado, reconciliar montaje/altura/temperatura en la publicación
   original de retroalimentación y definir un observable comparable al
   sensor. Una transformación de sensor frío a B del líquido requiere
   pérdidas, estado y propiedades verificadas; no un coeficiente ajustado
   para reproducir la masa. Si falta evidencia, limitar ese benchmark.

Antes de modificar `sim/`, cerrar diseño y pruebas del siguiente gate;
si se autoriza implementación, aislamiento OFF y cadena R2-1 secuencial
por monitor. No activar evaporación predictiva, muebles o CO/FED.
