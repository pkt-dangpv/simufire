# Revisión técnica: fugas, deformación de puertas y fallo de acristalamientos

> **Fecha:** 2026-09-16\
> **Alcance:** base bibliográfica y requisitos para ampliar la fase de fugas de
> puertas cerradas. No introduce todavía cambios de física en el motor.\
> **Documento de diseño relacionado:**
> [`PROMPT_MOTOR_FUGAS_PUERTA_CERRADA.md`](PROMPT_MOTOR_FUGAS_PUERTA_CERRADA.md).

## 1. Conclusión ejecutiva

La ampliación es necesaria, pero no debe resolverse con una única variable que
"abra más" toda la puerta. La evidencia distingue tres fenómenos:

1. **Fuga permanente en frío:** aire y humo pasan por las holguras de una
   puerta cerrada. Es un caudal pequeño que se representa mediante área
   efectiva de fuga (ELA) y una ley de potencia.
2. **Deformación térmica:** la hoja y el marco se curvan y generan huecos
   dinámicos localizados, sobre todo en el dintel y cerca de la cerradura. Esos
   huecos se suman a la fuga en frío, pero no convierten toda la hoja en una
   abertura uniforme.
3. **Fallo del acristalamiento:** una puerta puede contener uno o varios paños
   de vidrio. Agrietarse no equivale a ventilar. Solo el área que realmente se
   desprende crea una abertura grande, situada en la posición exacta del paño.

Por tanto, el motor necesita una noción de **integridad de la abertura**. La
puerta sigue cerrada operativamente mientras su perímetro y sus paños pueden
degradarse por separado.

## 2. Qué existe hoy y qué no representa bien

- Una puerta fría con `open_fraction == 0` es estanca.
- La deformación existente empieza a 150 °C, llega linealmente al 4 % a
  350 °C y se guarda en `thermal_gap_fraction`.
- Ese 4 % aplicado a una puerta de 0,92 × 2,05 m equivale a unos **0,075 m² o
  754 cm²**. Es unas 36 veces el ELA provisional de 21 cm² y no puede
  interpretarse como una fuga física medida.
- No se ha localizado evidencia que calibre la curva actual
  150–350 °C/4 % para puertas residenciales. Debe considerarse una heurística
  heredada, no el futuro modelo físico.
- `GlassFailureSystem` solo trata ventanas exteriores. El fallo abre
  progresivamente casi toda la ventana y no distingue grieta de
  desprendimiento, número de hojas, vidrio laminado o un paño dentro de una
  puerta.
- Las rutas actuales pueden mover humo sin mover de forma atómica su masa de
  gas, energía, O₂ y especies. La ampliación no debe reutilizar esa
  inconsistencia.

## 3. Evidencia sobre fugas de puertas cerradas

### 3.1 ELA de referencia: qué significan realmente 12 y 21 cm²

[NIST TN 2329](https://doi.org/10.6028/NIST.TN.2329) emplea, a una presión de
referencia de 4 Pa:

- **12 cm²** para una única puerta exterior cerrada;
- **21 cm²** para la puerta entre vivienda y garaje y para una puerta de
  sótano sin terminar.

El informe indica que son los *best estimates* de ASHRAE 2001 para puertas
completas. No son una campaña experimental de puertas interiores de vivienda.
Por eso sirven como **valores provisionales de clase**, no como verdad universal:

| clase provisional | ELA a 4 Pa | uso previsto | cautela |
|---|---:|---|---|
| `entry_tight` | 12 cm² | entrada con buen ajuste o burlete | valor de partida |
| `interior_tight` | 21 cm² | puerta interior razonablemente ajustada | extrapolación provisional |
| `custom` | explícita | puerta vieja, desajustada o ensayada | preferible cuando haya dato |
| `none` | 0 | elemento deliberadamente estanco | pruebas/validación |

Fuente local:
[`NIST_TN_2329_US_Housing_Stock_2025.pdf`](literature/NIST/NIST_TN_2329_US_Housing_Stock_2025.pdf).

### 3.2 La geometría visible no es el área efectiva

[NBSIR 81-2214](https://nvlpubs.nist.gov/nistpubs/Legacy/IR/nbsir81-2214.pdf)
recoge ensayos de conjuntos de puerta con distintas holguras, sellos y
configuraciones. La fuga cambia fuertemente con la construcción, el cierre y
el sellado; una anchura geométrica por sí sola no determina el caudal.

[Gross y Haberman (1989)](https://publications.iafss.org/publications/fss/2/169/view/fss_2-169.pdf)
modelaron rendijas rectas y con uno o dos giros. Sus conclusiones útiles para
Simufire son:

- una rendija estrecha no se comporta siempre como un orificio ideal;
- el régimen puede pasar de aproximadamente lineal con ΔP a una dependencia
  cercana a la raíz cuadrada, con exponentes intermedios;
- hay que conservar la posición de las holguras inferior, laterales y dintel;
- el modelo reprodujo caudales de puertas instaladas aproximadamente dentro
  del 20 % en los casos estudiados;
- el análisis térmico del artículo presupone deformación pequeña por debajo
  de unos 300 °C; no valida una ley de alabeo.

Fuentes locales:

- [`NBSIR_81_2214_Door_Air_Leakage.pdf`](literature/NIST/NBSIR_81_2214_Door_Air_Leakage.pdf)
- [`Gross_Haberman_Door_Air_Leakage_1989.pdf`](literature/NIST/Gross_Haberman_Door_Air_Leakage_1989.pdf)

### 3.3 Consecuencia para el modelo

La fuga en frío debe usar una ley de potencia calibrada por ELA:

`Q = ELA · sqrt(2·ΔP_ref/ρ) · (|ΔP|/ΔP_ref)^n`

con signo según ΔP y un exponente provisional del orden de 0,65, pendiente de
fijar para cada clase. El ELA total se reparte en cota para decidir el sentido
y la zona de origen del gas; ese reparto no debe alterar el ELA total.

> **Nota (2026-09-16, fase 1 del modelo puro; corregida el 2026-09-17).**
> [NIST TN 1887r1](https://doi.org/10.6028/NIST.TN.1887r1), el manual de
> CONTAM (p. 266, ec. 28 y 29), resuelve la convención: el área efectiva se
> define con dos juegos habituales, **C_d = 1,0 con 4 Pa** o C_d = 0,6 con
> 10 Pa. Los 12 y 21 cm² de TN 2329 son ELA a 4 Pa, así que van con
> **C_d = 1,0** y la fórmula de arriba ya es la correcta, sin coeficiente
> adicional. TN 1887r1 considera además razonable un **exponente de 0,6-0,7**
> cuando el ensayo no lo da; 0,65 queda como candidato provisional, no como
> calibración de puertas interiores. NBSIR 81-2214 (tabla 1) y Gross y Haberman
> muestran que en puertas depende del régimen. TN 2329 (p. 28) precisa que
> 12 y 21 cm² son los valores ASHRAE de una puerta sencilla con y sin burlete.
> La regularización cerca de ΔP = 0 del modelo es numérica, no una transición
> calibrada. Ver §12 de
> [`PROMPT_MOTOR_FUGAS_PUERTA_CERRADA.md`](PROMPT_MOTOR_FUGAS_PUERTA_CERRADA.md).
>
> Fuente local:
> [`NIST_TN_1887r1_CONTAM_User_Guide.pdf`](literature/NIST/NIST_TN_1887r1_CONTAM_User_Guide.pdf).

## 4. Evidencia sobre deformación térmica

[Prieler et al. (2023)](https://doi.org/10.1108/JSFE-01-2023-0011) ensayaron y
simularon una puerta de acero expuesta a un horno normalizado. Observaron:

- presión de horno no uniforme, aproximadamente 16 Pa en la parte alta y
  0,2 Pa en la baja;
- deformación del centro de la hoja de unos **10 mm a los 10 min**;
- formación principal de huecos en el borde superior y sobre la cerradura;
- el paso de gases aparece por esas zonas localizadas.

Esto es evidencia fuerte sobre **topología y mecanismo**, pero no calibra una
puerta interior residencial de madera: material, herrajes, marco y exposición
son distintos. No debe convertirse en una regla universal de 10 mm.

El artículo complementario de
[Prieler et al. (2020)](https://onlinelibrary.wiley.com/doi/full/10.1002/fam.2846)
informa, para su conjunto concreto, de primeros gases entre 110 y 130 s con un
hueco calculado de unos 0,83 mm, creciendo hasta unos 3,7 mm. Se usa como
orden de magnitud y forma temporal, no como curva residencial predeterminada.

Fuente local:
[`Prieler_Door_Deformation_Flue_Gas_Leakage_2023.pdf`](literature/Doors/Prieler_Door_Deformation_Flue_Gas_Leakage_2023.pdf).

### Consecuencia para el modelo

La primera implementación debe aceptar **huecos dinámicos prescritos** por
segmento (inferior, lateral de bisagras, lateral de cerradura y dintel). La ley
automática temperatura-tiempo-material se incorporará solo cuando exista una
calibración defendible para las clases de puerta del juego.

## 5. Evidencia sobre vidrio: rotura no significa abertura

### 5.1 Inicio de grieta

[Skelly, Roby y Beyler](https://vtechworks.lib.vt.edu/bitstreams/291a09f0-774f-4d6d-b978-9bd1f3f89be5/download)
estudiaron vidrio recocido expuesto a incendios de compartimento. Para vidrio
con el borde protegido encontraron una diferencia crítica centro-borde del
orden de **90 °C experimental** frente a unos 70 °C teóricos. La protección
del borde y las tensiones térmicas importan tanto como la temperatura del gas.

El histórico [modelo BREAK1 de NIST](https://www.nist.gov/el/fire/fire-modeling-programs)
refuerza esa arquitectura: calcula el campo térmico del vidrio con propiedades
del material, espesor, geometría sombreada por el marco, convección y radiación,
y determina el tiempo de primera rotura. Es mejor precedente que un umbral de
temperatura del gas de la sala.

Fuente local:
[`Skelly_Glass_Breakage_Compartment_Fires_1990.pdf`](literature/Glass/Skelly_Glass_Breakage_Compartment_Fires_1990.pdf).

### 5.2 Tipo de vidrio y desprendimiento

[Peng et al. (2024)](https://orbit.dtu.dk/en/publications/fire-induced-cracking-of-modern-window-glazing-an-experimental-st/)
realizaron 75 ensayos con vidrio recocido, templado y laminado; una, dos y tres
hojas; espesores de 3–8 mm; lados de 200–500 mm y flujo radiante cercano a
20 kW/m². En esas condiciones:

- no observaron agrietamiento del templado;
- no observaron desprendimiento del laminado;
- en unidades de vidrio recocido, la pérdida de la primera hoja modificó y
  retrasó el calentamiento y rotura de las siguientes;
- una unidad multicapas puede seguir sin aportar ventilación al llegar a
  flashover.

[Wang et al., comportamiento de vidrio templado](https://publications.iafss.org/publications/aofst/7/92)
hallaron que requiere una diferencia térmica mayor que el vidrio flotado, pero
que, una vez iniciada la rotura, puede producirse casi todo el desprendimiento
en poco tiempo.

El informe residencial de FSRI ya presente en la biblioteca define fallo como
paso abierto de al menos el 25 % del área acristalada. Sus ensayos de horno
mostraron, para las muestras concretas:

- doble acristalamiento moderno de unos 2,2 mm: promedios de fallo entre
  254 y 312 s y gases del horno del orden de 540–650 °C;
- vidrio simple legado de 2,4–2,9 mm: 577 y 846 s y gases del orden de
  650–790 °C.

Son referencias experimentales útiles, pero no justifican un único umbral:
espesor, soporte del borde, número de hojas y tipo de vidrio cambian el
resultado.

Fuentes locales:

- [`Peng_Modern_Window_Glazing_Fire_2024.pdf`](literature/Glass/Peng_Modern_Window_Glazing_Fire_2024.pdf)
- [`Toughened_Glass_Enclosure_Fires_2007.pdf`](literature/Glass/Toughened_Glass_Enclosure_Fires_2007.pdf)
- [`Impact_of_Ventilation_Legacy_and_Contemporary_Residential_Construction.pdf`](literature/FSRI_ULRI/Impact_of_Ventilation_Legacy_and_Contemporary_Residential_Construction.pdf)

### 5.3 Modelos de desprendimiento

[Hostikka et al. (VTT, 2005)](https://publications.vtt.fi/pdf/workingpapers/2005/W41.pdf)
separan fractura y caída mediante un tratamiento probabilista. Es un precedente
útil para no hacer determinista una respuesta con dispersión experimental
elevada. En la primera versión de Simufire conviene permitir dos modos:

- **determinista de validación**, con historia o instante impuesto;
- **probabilista de juego**, con semilla fija y parámetros por tipo de vidrio.

Fuente local:
[`VTT_Probabilistic_Glass_Fracture_Fallout_2005.pdf`](literature/Glass/VTT_Probabilistic_Glass_Fracture_Fallout_2005.pdf).

## 6. Arquitectura propuesta

### 6.1 Datos de una abertura

Toda puerta o ventana puede tener cero o más `glazing_panels`. Cada panel
necesita como mínimo:

- geometría local: anchura, altura y cota inferior;
- tipo: `annealed`, `toughened`, `laminated` u otro explícito;
- espesor, número de hojas y separación entre hojas;
- material del marco y profundidad de borde protegida;
- estado de daño, fracción desprendida y semilla/realización si procede.

La puerta, de forma independiente, necesita:

- clase y override de ELA en frío;
- segmentos de fuga y huecos de deformación;
- clase constructiva/material para una futura ley térmica;
- estado de hoja, marco, cierre y bisagras.

### 6.2 Estados del vidrio

`INTACT -> CRACKED -> PARTIAL_FALLOUT -> OPEN`

- `INTACT`: sin daño.
- `CRACKED`: cambia la integridad, pero el área de ventilación sigue en cero.
- `PARTIAL_FALLOUT`: abre solo la superficie realmente perdida.
- `OPEN`: se ha perdido prácticamente todo el paño.

Para acristalamiento múltiple, cada hoja conserva su estado. El paso de gas
solo existe donde hay un camino libre a través de todas las hojas que aún
cierran el mismo punto.

### 6.3 Conversión a flujos

- La fuga en frío y los huecos estrechos por deformación usan el solver de
  rendijas/ley de potencia.
- El vidrio desprendido genera una o varias aberturas rectangulares en la cota
  real del paño y usa el solver Bernoulli de abertura grande.
- Ninguno de los dos modifica `open_fraction`: ese campo sigue representando
  la apertura voluntaria de la hoja.
- No se suma un porcentaje uniforme a toda la puerta.

Todo flujo produce una única parcela atómica con masa total, entalpía, O₂,
humo, CO, CO₂, HCN, HCl, acroleína y formaldehído. Todos los consumidores leen
el mismo estado de flujo y los ledgers deben cerrar.

## 7. Orden de implementación recomendado

1. **Modelo puro de fuga fría**, con ΔP impuestas y ELA/clases provisionales.
   *Implementado y validado el 2026-09-17, sin integrar (§12 del documento de
   diseño).*
2. **Modelo puro de huecos de deformación prescritos**, sin inventar todavía
   una curva automática residencial. *Implementado el 2026-09-17, sin integrar
   (§13 del documento de diseño): topología de Prieler, magnitudes
   prescritas y no calibradas.*
3. **Modelo térmico y de estados del vidrio**, con ensayos unitarios de
   agrietamiento, desprendimiento parcial y multicapas.
4. **Conversión de daño a aberturas**: rendija localizada o rectángulo
   desprendido, sin conectar al motor principal.
5. **Resolver F2.2**, la sobrepresión irreal de recintos cerrados.
6. **Integrar una sola tubería de intercambio**, detrás de interruptores
   apagados por defecto y encendidos explícitamente por el editor.
7. **Validar por separado** puerta estanca, fuga fría, deformación, puerta con
   paño acristalado y ventana multicapa.

## 8. Criterios mínimos de aceptación

- Con todos los interruptores apagados: resultados oficiales idénticos byte a
  byte y suite de referencia completa.
- Una grieta de vidrio sin desprendimiento no cambia el intercambio gaseoso.
- El área ventilada nunca supera el área realmente desprendida.
- Una puerta deformada permanece cerrada operativamente y no activa radiación,
  propagación o lógica de puerta abierta para toda su superficie.
- Humo, especies, O₂, masa y energía viajan juntos y se conservan.
- La posición vertical cambia correctamente el sentido y la zona de origen.
- El acristalamiento múltiple no ventila mientras quede una hoja continua.
- El modo probabilista es reproducible con semilla fija.
- Los límites numéricos son guardarraíles, nunca sustitutos de una presión
  físicamente válida.

## 9. Qué queda sin calibrar

- ELA representativa de puertas interiores españolas por edad, ajuste y tipo.
- Exponente por clase de puerta (la convención de descarga ya está resuelta:
  ELA a 4 Pa con C_d = 1,0, NIST TN 1887r1).
- Reparto del ELA entre suelo, laterales y dintel.
- Ley automática de deformación de puertas residenciales según material,
  herrajes, tiempo, temperatura y presión.
- Distribución de área desprendida frente al tiempo para cada vidrio y marco.
- Efecto del impacto mecánico, chorro de manguera y acciones de bomberos.

Hasta disponer de esos datos, el motor debe permitir valores prescritos y
overrides trazables, y distinguir siempre **dato experimental**, **parámetro
provisional** y **heurística jugable**.

## 10. Fuentes enlazadas no incorporadas como PDF local

- [NIST: página histórica de BREAK1](https://www.nist.gov/el/fire/fire-modeling-programs).
- [Prieler et al. 2020: deformación y fuga de gases](https://onlinelibrary.wiley.com/doi/full/10.1002/fam.2846).
- [NIST: ensayos de fallo de ventanas en dormitorios](https://www.nist.gov/el/fire-research-division-73300/firegov-fire-service/video-impact-sprinklers-fire-hazard-dormitories).
- [de Witte et al. 2025: propagación de humo en edificio residencial real](https://journals.sagepub.com/doi/10.1177/07349041251377639).
- [Hung et al. 2024: fuga de humo en puertas residenciales](https://onlinelibrary.wiley.com/doi/10.1155/2024/2064541).

Estas páginas permanecen enlazadas para trazabilidad. Sus servidores no
ofrecieron en esta sesión un PDF abierto descargable de forma estable, por lo
que no se declara una copia local inexistente.
