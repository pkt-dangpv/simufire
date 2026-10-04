# D1: serie medida ISOHept9 y alcance del primer benchmark

Fecha: 2026-10-03. Rama `codex/g3-fed-co-zonal-shareable`, HEAD
`cbab7b05`. **GO parcial a preparar un replay de masa aislado; NO-GO a
aprobar el benchmark físico completo o integrar en producto.**

Estado actualizado del 04-10: replay y ledger de fases cerrados técnicamente,
sin integrar; [gate de emisión/B](G3_D1_ISOHEPT9_EMISSION_BASIS_2026-10-04.md)
cerrado como diagnóstico. GO al diseño de caller puro condicionado,
no a evaporación predictiva, HRR, especies o CO/FED.

## Fuente y trazabilidad

Se revisó [NIST TN 1603](https://nvlpubs.nist.gov/nistpubs/Legacy/TN/nbstechnicalnote1603.pdf),
ya disponible en la biblioteca. Sus células de carga proporcionan masa
independiente de la calorimetría. El apéndice A, p.145, identifica `Mass1`
como kg del quemador central; §2.5 fija tiempo cero en ignición. Tabla 3.1
identifica ISOHept9: líquido, una bandeja de 0,5 m² y puerta de 0,2 x 2 m.
No es pirólisis de un sólido ni un sofá compuesto.

La serie numérica está en el repositorio experimental
[Firemodels/exp, revisión fijada](https://github.com/firemodels/exp/blob/e5de6811036d252b4f9085866f08da66efdda7d3/NIST_FSE_2008/ISOHept9.csv),
**no** en una salida calculada de FDS ni en su archivo de entrada. Se
archivó [CSV original](../literature/data/NIST_FSE_2008/ISOHept9.csv),
sin cambiar sus valores o columnas. Es el **dato reducido publicado**,
no los voltajes crudos de adquisición: no confundir ausencia de procesado
nuestro con ausencia de postprocesado previo de NIST. SHA-256
`66ad9437f81e93750e1d53b7f08b9e5c1068218ec809ed29d308fd9360dccce3`.
El [manifiesto local](../literature/data/NIST_FSE_2008/PROVENANCE.json)
registra revisión, blob Git, hashes, unidades y localizadores. Se conserva
íntegro el [aviso del repositorio](../literature/data/NIST_FSE_2008/LICENSE_FIREMODELS_EXP.md);
solo se añadió LF final al archivo de aviso, con hashes original/local
separados. Atribución a NIST. No se importaron datos FSRI.

Lectura del PDF: inspección visual de tablas y apéndice, no solo extracción
automática. En la copia local, página PDF = página impresa + 14. Los avisos
de Poppler por fuentes Symbol/ArialUnicode no impidieron leer las tablas.

## Auditoría reproducible, sin transformación física

`scripts/simulation/audit_g3_measured_mass_candidate.py` comprueba fuentes,
licencia y PDF por hash; solo normaliza CRLF a LF en artefactos de texto.
Un cambio de contenido sigue fallando; el PDF usa hash binario exacto.
Exige `Time`/`Mass1` finitos, orden estricto y unidades revisadas s/kg.
Los NaN de canales no utilizados se conservan y no invalidan la masa.
No rellena, ordena, recorta, filtra ni deriva masa de HRR/HOC.

Antes de ejecutar el auditor se fijaron tres ventanas en el manifiesto:
0-500 s para crecimiento/depleción, 150-500 s por la ventana de la tabla
3.3 y 500-840 s para la cola. Son controles diagnósticos, **no** un filtro
de aceptación escogido para ocultar muestras. El informe audita también
los 187 puntos originales, desde -90 hasta 840 s, separados 5 s; el CSV
íntegro, no el JSON de métricas, conserva los valores de cada punto.

[Resultado reproducible](G3_D1_ISOHEPT9_MASS_AUDIT_2026-10-03.json):

| Ventana (s) | Descenso neto medido (kg) | Suma de aumentos (kg) | Intervalos con aumento | Muestras negativas |
| --- | ---: | ---: | ---: | ---: |
| -90 a 840 | 19,564673 | 0,500412 | 53 | 19 |
| 0 a 500 | 19,359537 | 0 | 0 | 0 |
| 150 a 500 | 14,336033 | 0 | 0 | 0 |
| 500 a 840 | 0,210308 | 0,485504 | 44 | 19 |

La masa a ignición es **19,665829 kg**, frente a los 20 kg nominales de la
tabla. No se reemplaza una por otra ni se atribuye la diferencia a una
causa sin demostrar. A 500 s quedan 0,306292 kg medidos. En la cola, sumar
solo descensos positivos da 0,695812 kg en vez del descenso neto 0,210308:
recortar tasas negativas añade 0,485504 kg a la cuenta. La precisión de
±1 g citada para el instrumento no es toda la incertidumbre del ensayo.
No se han separado deriva, ruido, tara o efectos térmicos.

El auditor no entrega un perfil al motor. `scientific_approval`,
`engine_integration`, `production_activation` y `profile_generated` son
false. La compatibilidad de signos de 0-500 s solo permite estudiar ese
tramo; no acredita composición de emisión o energía, ni todo el registro.

## Qué falta antes de usar el núcleo

Actualización del 04-10: [replay de masa cerrado técnicamente](G3_D1_ISOHEPT9_REPLAY_2026-10-04.md)
y [base energética de referencia revisada](G3_D1_HEPTANE_PHASE_BASIS_2026-10-04.md).
El [prototipo con fases](G3_D1_PHASE_LEDGER_2026-10-04.md) ya está cerrado.
No validan evaporación ni el lote: faltan energía sensible, caller conjunto
y benchmark físico completo antes de integrar. La atribución de emisión/B
está delimitada por el gate posterior, no promovida a medición completa.

1. **Representación temporal.** Diferencias de masas / 5 s son medias por
   intervalo. No son tasas instantáneas en los extremos: colocarlas como
   nodos de una curva lineal y volver a integrar puede cambiar la masa.
   Predeclarar una representación que conserve cada incremento sin
   suavizar: por ejemplo, tasas constantes por intervalo con su propia
   versión de contrato. A fecha 03-10 el proveedor solo aceptaba tasas lineales;
   el replay posterior añade la representación constante por intervalo,
   validada y aislada, sin aprobar emisión física.
2. **Fase y alcance.** Puede probarse primero el integrador puro con el
   tramo 0-500 s. Llamarlo replay numérico condicionado a masa medida,
   no predicción experimental independiente de la emisión. Comparar
   integral de tasas derivadas de Mass1 contra Mass1 comprueba conversión
   e integración, no una ley de evaporación. La API v1 original llama
   `solid_fuel_kg` al reservorio y conserva la misma energía antes/después
   de liberar: no etiquetar el líquido como sólido para pasar el esquema.
   La API de fases posterior resuelve ese contrato de referencia, sin
   sustituir v1 ni validar evaporación física.
3. **Energía y composición.** TN 1603 p.41 usa 44,4 MJ/kg y las tablas 6.1
   y 6.2 usan 44,56, con fórmula aproximada C7H16 y referencia al SFPE.
   Mantener ambas citas, no promediarlas ni elegir según ajuste. El
   [NIST Chemistry WebBook](https://webbook.nist.gov/cgi/cbook.cgi?ID=C142825&Type=HCOMBL)
   proporciona datos termoquímicos y fórmula de n-heptano, pero su ficha
   de combustión líquida no certifica el lote ni define por sí sola la
   energía del vapor liberado en nuestro contrato. Resolver fases,
   agua producto, temperatura de referencia y coste de vaporización sin
   contar dos veces energía ni duplicar fórmulas canónicas.
4. **Dominio y observables.** HRR de calorímetro comprende combustión
   dentro y fuera del recinto (§3.2). Un núcleo de oxidación completa sin
   CO/hollín no tiene que reproducirla en este ensayo subventilado. No
   ajustar masa o energía para forzar Q = masa x H, ni hacer desaparecer
   combustible al agotarse O₂. Comparar química parcial/transporte exige
   otro contrato y observables con bases seca/húmeda y demoras resueltas.
5. **Cola.** Para un replay de 0-500 s no tocar ninguna muestra posterior.
   Para ampliar hasta agotamiento hace falta predeclarar tratamiento e
   incertidumbre de la señal. No confundir final de ventana con fuego
   extinguido o inventario agotado.

El artículo de
[quemador de propano/HVAC](https://pmc.ncbi.nlm.nih.gov/articles/PMC9792339/)
local describe control de alimentación en LPM. Es candidato a fuentes
gaseosas/transporte, no sustituye la medición de liberación de un sólido;
sin revisar condiciones volumétricas y trazas no convertir LPM a kg/s.
TN 1953 también emplea quemadores de gas, no una ley de muebles. En este
tramo se priorizó ISOHept9; esas series no se importaron ni validaron.

## Verificaciones de este tramo

27 pruebas nuevas offline PASS: reproducción exacta del informe, señales
con signo, no recorte, canales inválidos, duplicados, orden, dominio,
unidades, hashes, confinamiento y prohibición de afirmar aprobación.
Primera corrida: 16 PASS y 11 errores de permisos del temporal de pytest;
repetición completa con basetemp externo nuevo: **27/27, exit 0**.
No se cuenta la primera como una suite completada.

No se modifica `sim/`, las fixtures GDScript, perfiles ni escenarios en
este tramo. No se lanza Godot ni se atribuye una nueva referencia/global.
La cadena 346/346, producto 168/168 y global 3382 corresponde al proveedor
cerrado anteriormente, no a este auditor. Sin commit/push.

Regresión offline conjunta final: **97 passed, 2 deselected**, exit 0,
1,55 s; las dos excluidas son las fixtures que arrancan Godot, no fallos
ocultos. Guardarraíles ALL PASS, R2-1 incluido, sobre informes existentes.
Enlaces de los cuatro documentos de este tramo y `git diff --check` PASS.
Hashes de ambos módulos GDScript iguales a los registrados en el cierre
anterior; no se ha regenerado ningún informe de simulación.

## Contrato histórico del replay, ya completado el 04-10

El encargo original fue diseñar y después probar **solo el replay de masa medido 0-500 s** del
proveedor aislado, preservando cada incremento y el estado de avance.
Predeclarar errores de representación y subdivisión antes de medirlos.
Si se cambia `sim/`: fixtures, mutaciones, identidad OFF y cierre completo
R2-1 secuencial por monitor con memoria suficiente. No integración ni
activación. Resolver fase/base energética antes de conectar el benchmark
al núcleo. U, ley de muebles, química parcial y CO/FED siguen NO-GO.

Contrato previo del replay siguiente:

- Mantener 0-500 s y la masa a ignición medida, no sustituir por 20 kg.
- Cada tramo conserva `Mass1(t_k) - Mass1(t_k+1)`; no exigir coincidencia
  instantánea con una tasa física no medida entre esas muestras.
- Error de representación/integración acumulado <=1e-9 kg en nodos,
  criterio **numérico predeclarado**, no incertidumbre experimental.
- Repetir con pasos coincidentes, subdivididos e irregulares que crucen
  fronteras; mismo débito acumulado, sin pérdida o duplicación al reiniciar.
- Restaurar cursor e inventario juntos; demanda rechazada no se reemite.
- Control negativo: invertir unidades, alterar masa, omitir un intervalo
  o cambiar regla temporal debe ser rechazado/detectado, nunca compensado
  con HRR, O₂ o tolerancia relajada.
- La prueba solo del proveedor no acredita el núcleo, ni evaporación
  predictiva, gas combustible de composición medida o concentración CO.

Trabajo actual: diseño de caller atómico puro según el
[gate posterior de emisión/B](G3_D1_ISOHEPT9_EMISSION_BASIS_2026-10-04.md),
con hipótesis/contorno declarados y sin integración. No repetir el replay
como si no estuviera implementado.
