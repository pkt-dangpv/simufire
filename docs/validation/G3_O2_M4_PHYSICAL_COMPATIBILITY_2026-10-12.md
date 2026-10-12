# G3 - M4-B3: compatibilidad física del gas y del oxígeno

Fecha: 2026-10-12. Base publicada: `23db7bf9`.
**Diseño y testigos analíticos, no implementación física. CO/FED OFF/NO-GO.**
Continúa la [captura real M4-B2](G3_O2_M4_PASSIVE_CAPTURE_2026-10-12.md).

## 1. Decisión

**NO-GO a conectar el reparto de referencia M4-A1 al gas térmico existente.**
No hay un factor de conversión que haga equivalentes ambos modelos en general.
Cerrar un balance con bases geométricas no corrige esa incompatibilidad.

**Ruta recomendada:** un contrato experimental de masa física de gas y O2
por zona, con masa fraccionaria `Y_z = O_z/m_z`, paquetes pareados e interfaz
derivada del estado. Conservar M1/M2-T/M2-V y sus pruebas como modo de
referencia anterior, no reinterpretar sus números ni cambiar su ley en silencio.

**GO de diseño al siguiente prototipo puro M4-P1**, con masas/paquetes
impuestos y sin consumidor del motor. No es GO a M4-C/D ni a conectar la red.
El contrato de implementación y su campaña deben fijarse antes de programar.
Elegir entre desacoplar la conservación gaseosa de la red o utilizar la red
completa es una decisión posterior; ninguna queda autorizada por este informe.

## 2. Fuentes efectivamente revisadas

Se leyó la copia local de [NIST TN 1889v1](../literature/NIST.TN.1889v1.pdf),
páginas impresas 7-9 y 12-13 (PDF local 21-23 y 26-27), y se revisaron
visualmente 9 y 13. SHA-256 local:
`5e31db4d31618ab5c1cd7618e531920a5c079db3d3060fa8e6069d4cc0c27cef`.
[Fuente oficial](https://nvlpubs.nist.gov/nistpubs/TechnicalNotes/NIST.TN.1889v1.pdf).
No se ha leído entero el informe ni ejecutado CFAST en esta entrega.

TN 1889v1, §§2.1-2.2 y 3.2-3.3: conservación de masa/energía, EOS con
peso molecular aproximado del aire, transporte de especies por capa,
limitación por O2 de la zona fuente y arrastre de gas/especies por penacho.
Es respaldo de estructura, no calibración de nuestras tasas o muebles.
Sus ecuaciones energéticas incluyen trabajo de expansión: nuestra energía
sensible afín no se declara idéntica a la formulación CFAST.

Código oficial consultado de nuevo en **CFAST-7.7.7**:

- [solve.f90, update_data](https://github.com/firemodels/cfast/blob/CFAST-7.7.7/Source/CFAST/solve.f90):
  rama `foxygen`, masas O2 por zona y fracciones másicas desde masa zonal;
  en otras ramas normaliza con productos. No generalizar una rama a todas.
- [fire.f90, do_fire](https://github.com/firemodels/cfast/blob/CFAST-7.7.7/Source/CFAST/fire.f90):
  química desde O2 de la capa fuente y especies del arrastre sumadas arriba
  y restadas abajo. No copiar clamps/normalizaciones ni suponer que sus
  supuestos y los de SimuFire son iguales.

Las conclusiones siguientes son deducciones del código de SimuFire y de
los controles algebraicos declarados, no resultados experimentales NIST.
No se incorpora bibliografía nueva: el PDF ya existe en la biblioteca.

## 3. Tres representaciones diferentes

`kappa = M_O2/M_air = 0.031998/0.0289647`.

| Representación | Definición | Qué permite afirmar |
| --- | --- | --- |
| M1, referencia fija | `C_ref = 1.2 V`, `B_ref = kappa C_ref`, `x_ref = M/B_ref` | Contenido de referencia; no concentración real de gas caliente |
| Gas físico aproximado | `Y_z = O_z/m_z`; `x_air_proxy = Y_z/kappa` | Fracción másica; conversión molar solo con peso molecular impuesto |
| Composición molar | `x_O2 = (O/M_O2)/sum(m_s/M_s)` | Requiere especies, humedad y denominador completos/declarados |

Una EOS con R/Cp constantes no aporta por sí sola composición química.
Conservar gas con la red tampoco valida automáticamente el O2 que transporta.
No usar `x_air_proxy` como fracción molar exacta ni como FED validado.

La restricción física es `0 <= O_z <= m_z`, además de los balances de especies
que se admitan. `O <= kappa*m` **no basta**: permite O2 mayor que todo el gas.
Una zona `m=0` exige `O=0` y concentración ausente. Sin floors ni inventario
fantasma. La aproximación de aire no es un modelo de oxígeno puro.

## 4. Testigos que cierran la incompatibilidad

Reproducibles en
[tests/test_g3_m4_physical_compatibility.py](../../tests/test_g3_m4_physical_compatibility.py).
Son cuentas Decimal sintéticas, independientes del motor y del oráculo M4.
No son corridas térmicas, mutaciones ni datos medidos.

1. **Gas caliente isobárico:** 30 kg de referencia a 300 K; a 600 K quedan
   15 kg físicos en el mismo volumen/presión. Con x impuesto de 0,209,
   el O2 físico dividido por B_ref da 0,1045, no 0,209. Es un control
   isobárico con frontera, no una sala sellada que pueda perder masa.
2. **Solo calor, sala sellada:** m_alta=10, m_baja=20 kg, O_alta=1,
   O_baja=4 kg, ambas a 300 K. Calentar alta a 600 K cambia V_alta/V
   de 1/3 a 1/2 y sube la presión; las masas de gas/O2 no cambian.
   Un remap de base fija proporcional al volumen trasladaría **1 kg O2**
   hacia arriba sin paquete físico. El total aún cierra: ese check no lo ve.
3. **Penacho impuesto:** 2 kg desde lower con Y=0,20 llevan 0,4 kg O2.
   Donante zonal, no promedio; masa/energía/O2 comparten el mismo paquete.
4. **Puerta estratificada:** dos parcelas de 10 kg en sentidos opuestos,
   sala a (40 kg gas, 7 kg O2), donante alto Y=0,10 y b uniforme Y=0,20.
   Promedio de sala aporta delta a=0,25 kg; donante zonal, delta a=1 kg.
   Ambos conservan total. Elegir capa cambia M2-T, no es solo instrumentar.
5. **Exterior:** diluir (30 kg gas, 3 kg O2) con 1 kg exterior a x=0,209
   y salida de 1 kg de mezcla aumenta O2 y mantiene gas. Sacar 1 kg del
   donante sin entrada deja (29 kg, 2,9 kg O2). No intercambiar estas leyes.
6. **Proyección:** mantener 3 kg O2 mientras el cierre geométrico baja gas
   30->20 kg aumenta Y de 0,10 a 0,15. Borrar 1 kg O2 lo disimula, pero
   inventa una salida salvo que exista un paquete físico identificado.

Otros testigos: composición N2/CO2 distinta con igual masa y O2; conversión
molar frente a másica; dos salidas que gastan el mismo donante; zona ausente.
No implican que el motor haya ejecutado estas trayectorias.

## 5. Qué obliga a cambiar el modo físico futuro

| Ruta | Contrato necesario | Comportamiento anterior que se preserva fuera del modo nuevo |
| --- | --- | --- |
| Geometría/EOS | Gas conservado; volumen/presión/interfaz derivados | ZoneFireSolver aún proyecta lower con red OFF |
| Penacho/siembra | O2 proporcional al gas aceptado del donante y misma transacción | Transferencia de gas/energía sin O2 físico canónico |
| Puertas | Rutas/sentidos/capas, cantidades post-cap, donaciones agregadas | M2-T mezcla simétrica de referencia de sala |
| Exterior/ACH | Entradas y salidas físicas separadas con donantes/destinos | M2-V dilución equivalente agregada; ACH de referencia |
| Fuego/sumidero | Misma selección y reserva zonal; un débito; productos/fuel declarados | M3 usa depósito entero y paquete energético aceptado |
| Interfaz | Calor no mueve O2; transferencia explícita cambia ambos inventarios | Remap de perfil de referencia es solo una convención |

La red candidata ya conserva gas, pero `PressureNetworkTransportSystem`
construye O2 con `o2_upper * upper_gas_kg` y devuelve ese cociente al trazador;
el exterior usa `outside.o2 * q`. Es una convención másica para campos usados
como molares en M1. **No conectar ambos propietarios ni añadir kappa solo en
una frontera.** Hará falta semántica uniforme, O2 desde kg canónicos y un
solo aplicador, con campaña propia. La red sigue rechazada por M3 actual.

M2-V recibe `air_in_kg = smoke_out_kg * 0.40`, y `smoke_out_kg` está limitado
por masa de humo. No llamar a esa cantidad masa física de aire admitida.
Reetiquetar el recibo no convierte ese venteo en intercambio gaseoso físico.
No cambiar 0,40, caps, leyes o tiempos para hacer pasar este gate.

El prototipo futuro no aplicará remap geométrico tras penacho. Un cambio de
representación que sí redistribuya gas requerirá paquete simultáneo de gas,
energía y especies, o representación nula con inventarios invariantes.
El núcleo M4-A1 queda congelado: sus bases/operaciones impuestas no se
reutilizan como autoridad física general con bases totales variables.

## 6. Entrega siguiente acotada: M4-P1

Antes de implementación, cerrar esta especificación con su campaña:

1. Núcleo puro, estado impuesto `m_u,m_l,O_total,O_u` y energía si se
   transporta; sin leer RoomModel, sin generar caudales ni consumir fuego.
   `O_l = O_total-O_u`, Y derivadas; tipos/bases explícitos, finitud,
   donaciones conjuntas desde snapshot, no crédito futuro ni doble aplicación.
2. Paquetes impuestos de penacho, entrada/salida y puerta de dos sentidos;
   masa, energía específica y O2 pareados. Calor sin masa separado.
   Transacción atómica de todos los participantes y recibo auditable.
   No ampliar la API reference_dry_air_v1 para fingir paquetes físicos.
3. Controles puros: solo calor, entrainment, contraflujo estratificado,
   outflow/inflow, renacimiento/colapso de zona, agotamiento, salidas múltiples,
   rechazo sin escritura, revisión/identidad y unidades incompatibles.
   Auditor independiente y mutaciones sobre la implementación real.
4. Después: decidir autoridad gaseosa de producto y probarla aislada con
   calentador prescrito sin combustible. No usar fuego/muebles para ocultar
   residuos de gas. Comparar cierre masa/energía/volumen y fuente exterior.
5. Solo después, contrato gas/O2/productos del paquete de combustión,
   M4-C/D con reserva común, y M4-E (CFAST equivalente + ensayos medidos).
   HRR impuesto no prueba yields; el calor no puede crear masa de combustible.

HVAC/PPV, varios fuegos, composiciones no declaradas y combinaciones sin
contrato siguen rechazadas. Activación, editor, muebles y CO/FED quedan fuera.
El mínimo inicial evita obligar a implementar toda la química para verificar
un transporte de gas sin fuego; no autoriza luego llamar composición real
a la aproximación ni introducir combustible sin balance de fuente.

## 7. Verificación y retomada

**14 testigos analíticos nuevos; focal offline M4: 255 passed**, 4,03 s,
cero fallos. Incluye los 241 controles anteriores de las cinco suites M4 y
repite sus testigos/falsación Python; no hay campaña nueva de mutación GD.
Primera selección parcial: 228 passed; faltaba la suite de protecciones del
runner, no había fallos. La selección final incluye las seis suites.
AST Python y enlaces de los cuatro documentos: cero errores.
Guardarraíles ALL PASS, R2-1 verde sobre 346/346 y 78 gaps vigentes.
No se necesita Godot: no cambia sim/, la captura, sus consumidores, informes
o monitor común. No se repiten ni se adjudican PASS nuevos de
referencia/producto/global. Estilo y `git diff --check` limpios.
Inventario LF de 64 GD del motor idéntico a M4-B2:
`a03f8b50343d7598882a9da949b4b9fa8b563c96eeaab16fdf3aeea73110e771`.
79 UID sin seguimiento y cuatro stashes preservados; ningún Godot en marcha.
Main limpio antes de integración. Solo cinco archivos propios de diseño,
testigos y seguimiento se publican; sin registros runs/ ni historia privada.
Revisión staged: detectó una línea vacía extra al final del test nuevo,
invisible al diff de archivos aún sin seguimiento. Se retiró antes del commit;
sin cambio de las cuentas y con comprobación staged repetida.

El diseño termina aquí. El siguiente trabajo es la especificación/prototipo
puro M4-P1, no wiring del fuego ni activación. La corrección física viva
implica un cambio de modelo declarado, no un adaptador que conserve todas
las leyes actuales y pretenda además concentraciones reales.
