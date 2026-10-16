extends RefCounted

## Funciones matemáticas deterministas del motor.
##
## Las funciones trascendentes de Godot (`exp`, `pow`, `sin`, `cos`, `tanh`)
## vienen de la biblioteca matemática de C con la que se compiló cada build: en
## Windows (MinGW) usan la FPU x87, cuya precisión cambia de un hilo a otro, y en
## Linux, Android, macOS o iOS son otras bibliotecas con otros últimos bits. El
## motor amplifica una diferencia de un bit hasta curvas visiblemente distintas
## (docs/validation/determinism/). Estas versiones usan solo + − × ÷, `sqrt` y
## comparaciones, que IEEE 754 fija bit a bit en cualquier procesador, así que
## dan el mismo resultado en cualquier máquina, sistema, hilo o build.
##
## Algoritmos: fdlibm (Sun Microsystems, la base de musl y FreeBSD): `exp`
## (e_exp.c), `log` (e_log.c), núcleos de `sin`/`cos` (k_sin.c, k_cos.c) con
## reducción de Cody-Waite (e_rem_pio2.c). `pow` = exp(y·log x) con log y el
## producto en doble-doble para mantener ~1 ulp. Error ≲ 1 ulp en el rango del
## motor (tests/test_det_math.py lo mide contra precisión arbitraria).
##
## Las constantes se construyen desde sus bits exactos: no dependen de cómo lea
## el analizador de GDScript un literal decimal.
##
## `lerpf` e `inverse_lerp` repiten la fórmula de Godot (math_funcs.h); en x86-64
## dan sus mismos bits. Están aquí porque en ARM el compilador de C++ puede fusionar
## multiplicar-sumar (FMA) dentro de la función de Godot; en GDScript cada operación
## se ejecuta por separado y no se puede fusionar.
##
## Cambiar cualquier detalle de este archivo cambia los números del motor: hay
## que regenerar la referencia y la huella de determinismo.

static var LN2_HI: float
static var LN2_LO: float
static var INV_LN2: float
static var EXP_P1: float
static var EXP_P2: float
static var EXP_P3: float
static var EXP_P4: float
static var EXP_P5: float
static var EXP_O_THRESHOLD: float
static var EXP_U_THRESHOLD: float
static var LG1: float
static var LG2: float
static var LG3: float
static var LG4: float
static var LG5: float
static var LG6: float
static var LG7: float
static var S1: float
static var S2: float
static var S3: float
static var S4: float
static var S5: float
static var S6: float
static var C1: float
static var C2: float
static var C3: float
static var C4: float
static var C5: float
static var C6: float
static var INV_PIO2: float
static var PIO2_1: float
static var PIO2_2: float
static var PIO2_2T: float
static var SQRT2: float
## 2^k exactos para k en [-1074, 1023], en el índice k + 1074.
static var POW2: PackedFloat64Array = PackedFloat64Array()

const POW2_BIAS: int = 1074
## Constante de Dekker para partir un double en dos mitades de 26 bits.
const SPLIT: float = 134217729.0


static func _static_init() -> void:
	LN2_HI = _bits("3fe62e42fee00000")
	LN2_LO = _bits("3dea39ef35793c76")
	INV_LN2 = _bits("3ff71547652b82fe")
	EXP_P1 = _bits("3fc555555555553e")
	EXP_P2 = _bits("bf66c16c16bebd93")
	EXP_P3 = _bits("3f11566aaf25de2c")
	EXP_P4 = _bits("bebbbd41c5d26bf1")
	EXP_P5 = _bits("3e66376972bea4d0")
	EXP_O_THRESHOLD = _bits("40862e42fefa39ef")
	EXP_U_THRESHOLD = _bits("c0874910d52d3051")
	LG1 = _bits("3fe5555555555593")
	LG2 = _bits("3fd999999997fa04")
	LG3 = _bits("3fd2492494229359")
	LG4 = _bits("3fcc71c51d8e78af")
	LG5 = _bits("3fc7466496cb03de")
	LG6 = _bits("3fc39a09d078c69f")
	LG7 = _bits("3fc2f112df3e5244")
	S1 = _bits("bfc5555555555549")
	S2 = _bits("3f8111111110f8a6")
	S3 = _bits("bf2a01a019c161d5")
	S4 = _bits("3ec71de357b1fe7d")
	S5 = _bits("be5ae5e68a2b9ceb")
	S6 = _bits("3de5d93a5acfd57c")
	C1 = _bits("3fa555555555554c")
	C2 = _bits("bf56c16c16c15177")
	C3 = _bits("3efa01a019cb1590")
	C4 = _bits("be927e4f809c52ad")
	C5 = _bits("3e21ee9ebdb4b1c4")
	C6 = _bits("bda8fae9be8838d4")
	INV_PIO2 = _bits("3fe45f306dc9c883")
	PIO2_1 = _bits("3ff921fb54400000")
	PIO2_2 = _bits("3dd0b4611a600000")
	PIO2_2T = _bits("3ba3198a2e037073")
	SQRT2 = _bits("3ff6a09e667f3bcd")
	POW2.resize(POW2_BIAS + 1024)
	var p: float = 1.0
	for k: int in range(0, 1024):
		POW2[POW2_BIAS + k] = p
		p *= 2.0
	p = 1.0
	for k: int in range(0, POW2_BIAS + 1):
		POW2[POW2_BIAS - k] = p
		p *= 0.5


## Double desde su patrón de bits en hexadecimal (orden de lectura habitual).
static func _bits(hex_big_endian: String) -> float:
	var bytes: PackedByteArray = hex_big_endian.hex_decode()
	bytes.reverse()
	return bytes.decode_double(0)


## Exponente k tal que 2^k <= x < 2^(k+1), para x finito y > 0 (incluye subnormales).
## Lee los 11 bits de exponente del double; un subnormal se busca en la tabla.
static func _exponent(x: float) -> int:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, x)
	var biased: int = (bytes.decode_u16(6) >> 4) & 0x7ff
	if biased != 0:
		return biased - 1023
	var lo: int = 0
	var hi: int = POW2_BIAS - 1023
	while lo < hi:
		var mid: int = (lo + hi + 1) >> 1
		if POW2[mid] <= x:
			lo = mid
		else:
			hi = mid - 1
	return lo - POW2_BIAS


## x · 2^k para cualquier k entero (escala exacta mientras el resultado sea normal).
static func _scale(x: float, k: int) -> float:
	while k > 1023:
		x *= POW2[POW2_BIAS + 1023]
		k -= 1023
	while k < -1022:
		x *= POW2[POW2_BIAS - 1022]
		k += 1022
	return x * POW2[POW2_BIAS + k]


## Llamar siempre como DetMath.exp(x): dentro de este archivo un `exp(...)` sin
## prefijo resuelve a la función global de Godot, no a esta.
static func exp(x: float) -> float:
	return _exp(x)


static func log(x: float) -> float:
	return _log(x)


static func _exp(x: float) -> float:
	if is_nan(x):
		return x
	if x > EXP_O_THRESHOLD:
		return INF
	if x < EXP_U_THRESHOLD:
		return 0.0
	var ax: float = absf(x)
	if ax < 3.725290298461914e-09:  # 2^-28: exp(x) redondea a 1 + x
		return 1.0 + x
	var k: int = 0
	var hi: float = x
	var lo: float = 0.0
	var r: float = x
	if ax > 0.34657359027997264:  # 0,5·ln 2
		if ax < 1.0397207708399179:  # 1,5·ln 2
			k = 1 if x > 0.0 else -1
		else:
			k = int(INV_LN2 * x + (0.5 if x > 0.0 else -0.5))
		hi = x - float(k) * LN2_HI
		lo = float(k) * LN2_LO
		r = hi - lo
	var t: float = r * r
	var c: float = r - t * (EXP_P1 + t * (EXP_P2 + t * (EXP_P3 + t * (EXP_P4 + t * EXP_P5))))
	if k == 0:
		return 1.0 - ((r * c) / (c - 2.0) - r)
	var y: float = 1.0 - ((lo - (r * c) / (2.0 - c)) - hi)
	return _scale(y, k)


static func _log(x: float) -> float:
	if is_nan(x) or x < 0.0:
		return NAN
	if x == 0.0:
		return -INF
	if x == INF:
		return INF
	var k: int = _exponent(x)
	var m: float = x * POW2[POW2_BIAS - k] if k >= -1022 else _scale(x, -k)
	if m > SQRT2:
		m *= 0.5
		k += 1
	var f: float = m - 1.0
	var dk: float = float(k)
	var s: float = f / (2.0 + f)
	var z: float = s * s
	var w: float = z * z
	var t1: float = w * (LG2 + w * (LG4 + w * LG6))
	var t2: float = z * (LG1 + w * (LG3 + w * (LG5 + w * LG7)))
	var big_r: float = t2 + t1
	var hfsq: float = 0.5 * f * f
	return dk * LN2_HI - ((hfsq - (s * (hfsq + big_r) + dk * LN2_LO)) - f)


static func _is_integer(y: float) -> bool:
	return is_finite(y) and floor(y) == y


static func _is_odd_integer(y: float) -> bool:
	return _is_integer(y) and absf(y) < 9007199254740992.0 and fmod(y, 2.0) != 0.0


static func pow(x: float, y: float) -> float:
	# Atajos exactos o de una sola operación IEEE; fijos: cambiarlos cambia el motor.
	if y == 2.0:
		return x * x
	if y == 1.0:
		return x
	if y == 0.0 or x == 1.0:
		return 1.0
	if is_nan(x) or is_nan(y):
		return NAN
	if y == 0.5 and x > 0.0 and x != INF:
		return sqrt(x)
	if y == 4.0:
		var x2: float = x * x
		return x2 * x2
	if y == 1.5 and x > 0.0 and x != INF:
		return x * sqrt(x)
	if y == -1.0:
		return 1.0 / x
	var sign: float = 1.0
	if x < 0.0:
		if not _is_integer(y):
			return NAN
		if _is_odd_integer(y):
			sign = -1.0
		x = -x
	if x == 0.0:
		if y < 0.0:
			return sign * INF
		return sign * 0.0
	if x == INF:
		return sign * (INF if y > 0.0 else 0.0)
	if is_inf(y):
		return INF if (x > 1.0) == (y > 0.0) else 0.0
	# log(x) en doble-doble (l_hi + l_lo), error relativo ~2^-60.
	var k: int = _exponent(x)
	var m: float = x * POW2[POW2_BIAS - k] if k >= -1022 else _scale(x, -k)
	if m > SQRT2:
		m *= 0.5
		k += 1
	# log(m) = 2·atanh(s), s = (m - 1)/(m + 1). Solo 2s necesita doble-doble: el
	# resto de la serie pesa menos de un 1 % de s.
	var f: float = m - 1.0
	var d: float = 2.0 + f
	var s: float = f / d
	# Resto exacto de la división, f - s·d, con el producto de Dekker.
	var cs: float = SPLIT * s
	var s_hi: float = cs - (cs - s)
	var s_lo: float = s - s_hi
	var cd: float = SPLIT * d
	var d_hi: float = cd - (cd - d)
	var d_lo: float = d - d_hi
	var sd: float = s * d
	var sd_err: float = ((s_hi * d_hi - sd) + s_hi * d_lo + s_lo * d_hi) + s_lo * d_lo
	var q_lo: float = ((f - sd) - sd_err) / d
	var z: float = s * s
	var w: float = z * z
	var t1: float = w * (LG2 + w * (LG4 + w * LG6))
	var t2: float = z * (LG1 + w * (LG3 + w * (LG5 + w * LG7)))
	var tail: float = s * (t2 + t1) + 2.0 * q_lo
	var dk: float = float(k)
	# k·ln2: k·LN2_HI es exacto (LN2_HI acaba en 11 ceros).
	var a_hi: float = dk * LN2_HI
	var two_s: float = 2.0 * s
	var sum: float = a_hi + two_s
	var bb: float = sum - a_hi
	var sum_err: float = (a_hi - (sum - bb)) + (two_s - bb)
	var l_lo: float = sum_err + tail + dk * LN2_LO
	var l_hi: float = sum + l_lo
	l_lo = l_lo - (l_hi - sum)
	# y·log(x) en doble-doble.
	var p_hi: float = y * l_hi
	var p_lo: float = 0.0
	if absf(y) < 1.0e290 and absf(l_hi) < 1.0e290:
		var cy: float = SPLIT * y
		var y_hi: float = cy - (cy - y)
		var y_lo: float = y - y_hi
		var cl: float = SPLIT * l_hi
		var l_hi_hi: float = cl - (cl - l_hi)
		var l_hi_lo: float = l_hi - l_hi_hi
		p_lo = ((y_hi * l_hi_hi - p_hi) + y_hi * l_hi_lo + y_lo * l_hi_hi) + y_lo * l_hi_lo
		p_lo += y * l_lo
		var h: float = p_hi + p_lo
		p_lo = p_lo - (h - p_hi)
		p_hi = h
	if p_hi > EXP_O_THRESHOLD:
		return sign * INF
	if p_hi < EXP_U_THRESHOLD:
		return sign * 0.0
	var e: float = _exp(p_hi)
	return sign * (e + e * p_lo)


## Reducción de x a r = x - n·π/2 (r en doble-doble) para |x| moderado.
static func _rem_pio2(x: float) -> Array[float]:
	var n: int = int(x * INV_PIO2 + (0.5 if x >= 0.0 else -0.5))
	var fn: float = float(n)
	# Dos pasos de Cody-Waite (π/2 en tres trozos): exacto para |n| < 2^20.
	var t: float = x - fn * PIO2_1
	var w: float = fn * PIO2_2
	var r: float = t - w
	w = fn * PIO2_2T - ((t - r) - w)
	var y0: float = r - w
	var y1: float = (r - y0) - w
	return [y0, y1, float(n)]


static func _k_sin(x: float, y: float) -> float:
	var z: float = x * x
	var v: float = z * x
	var r: float = S2 + z * (S3 + z * (S4 + z * (S5 + z * S6)))
	return x - ((z * (0.5 * y - v * r) - y) - v * S1)


static func _k_cos(x: float, y: float) -> float:
	var z: float = x * x
	var r: float = z * (C1 + z * (C2 + z * (C3 + z * (C4 + z * (C5 + z * C6)))))
	var hz: float = 0.5 * z
	var w: float = 1.0 - hz
	return w + (((1.0 - w) - hz) + (z * r - x * y))


static func sin(x: float) -> float:
	if not is_finite(x):
		return NAN
	if absf(x) < 0.7853981633974483:  # π/4
		return _k_sin(x, 0.0)
	var r: Array[float] = _rem_pio2(x)
	match int(r[2]) & 3:
		0:
			return _k_sin(r[0], r[1])
		1:
			return _k_cos(r[0], r[1])
		2:
			return -_k_sin(r[0], r[1])
		_:
			return -_k_cos(r[0], r[1])


static func cos(x: float) -> float:
	if not is_finite(x):
		return NAN
	if absf(x) < 0.7853981633974483:
		return _k_cos(x, 0.0)
	var r: Array[float] = _rem_pio2(x)
	match int(r[2]) & 3:
		0:
			return _k_cos(r[0], r[1])
		1:
			return -_k_sin(r[0], r[1])
		2:
			return -_k_cos(r[0], r[1])
		_:
			return _k_sin(r[0], r[1])


## exp(x) - 1 con el truco de Kahan (exacto en relativo también para x pequeño).
static func expm1(x: float) -> float:
	var u: float = _exp(x)
	if u == 1.0:
		return x
	var um1: float = u - 1.0
	if um1 == -1.0:
		return -1.0
	return um1 * x / _log(u)


static func tanh(x: float) -> float:
	if is_nan(x):
		return x
	var ax: float = absf(x)
	var t: float
	if ax >= 22.0:
		t = 1.0
	elif ax >= 1.0:
		t = 1.0 - 2.0 / (_exp(2.0 * ax) + 1.0)
	else:
		var e: float = expm1(2.0 * ax)
		t = e / (e + 2.0)
	return -t if x < 0.0 else t


static func lerpf(from: float, to: float, weight: float) -> float:
	return from + (to - from) * weight


static func inverse_lerp(from: float, to: float, value: float) -> float:
	return (value - from) / (to - from)
