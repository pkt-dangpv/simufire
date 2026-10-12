"""Offline M4-A algebra, NOT an engine implementation or a calibrated mixing law.

One authoritative total M and one subordinate upper inventory U; L = M - U.
Bases B denote kg O2 at reference mole fraction 1, NOT hot-gas mass.
Transfers and mixing fractions are imposed test inputs, never inferred rates.
Frozen values make refusals atomic: a failed proposal cannot mutate its input.
"""

from dataclasses import dataclass
import math


TOL_KG = 1.0e-9  # budget assertion only; never permission to clip invalid state


def _number(value, name):
    if type(value) not in (int, float) or not math.isfinite(value):
        raise ValueError(f"{name}: expected a finite number")
    return float(value)


@dataclass(frozen=True)
class Partition:
    total_kg: float
    upper_kg: float
    upper_base_kg: float
    lower_base_kg: float

    def __post_init__(self):
        for name in self.__dataclass_fields__:
            _number(getattr(self, name), name)
        _number(self.base_kg, "combined_reference_base")
        if self.upper_base_kg < 0 or self.lower_base_kg < 0 or self.base_kg <= 0:
            raise ValueError("bases must be nonnegative with a positive total")
        if not 0 <= self.upper_kg <= self.total_kg:
            raise ValueError("upper inventory must lie within the room inventory")
        if self.upper_kg > self.upper_base_kg or self.lower_kg > self.lower_base_kg:
            raise ValueError("oxygen exceeds the declared reference capacity")

    @property
    def lower_kg(self):
        return self.total_kg - self.upper_kg

    @property
    def base_kg(self):
        return self.upper_base_kg + self.lower_base_kg

    def fractions(self):
        # None is absent, not zero O2 and not a synthetic epsilon-sized layer.
        upper = self.upper_kg / self.upper_base_kg if self.upper_base_kg else None
        lower = self.lower_kg / self.lower_base_kg if self.lower_base_kg else None
        return {"room": self.total_kg / self.base_kg, "upper": upper, "lower": lower}


@dataclass(frozen=True)
class Receipt:
    before: Partition
    after: Partition
    cause: str
    upper_delta_kg: float
    lower_delta_kg: float
    room_delta_kg: float


def _receipt(before, after, cause, du, dl):
    return Receipt(before, after, cause, du, dl, du + dl)


def remap(state, new_upper_base_kg):
    """Geometric remap of a piecewise-uniform REFERENCE partition, not plume flow.

    A growing upper interval takes the swept share of the old lower interval.
    A shrinking one hands its swept share to the lower interval. This is a
    proposed accounting convention, not an observed physical interface motion.
    """
    new_upper = _number(new_upper_base_kg, "new_upper_base_kg")
    if not 0 <= new_upper <= state.base_kg:
        raise ValueError("new upper base outside the room")
    difference = new_upper - state.upper_base_kg
    if new_upper == 0:
        upper_kg = 0.0
    elif new_upper == state.base_kg:
        upper_kg = state.total_kg
    elif difference >= 0:
        upper_kg = state.upper_kg + state.lower_kg * (difference / state.lower_base_kg)
    else:
        upper_kg = state.upper_kg * (new_upper / state.upper_base_kg)
    after = Partition(state.total_kg, upper_kg, new_upper, state.base_kg - new_upper)
    moved = after.upper_kg - state.upper_kg
    return _receipt(state, after, "interface_remap", moved, -moved)


def mix(state, fraction):
    """Conservative relaxation with imposed alpha in [0,1]; NO alpha(dt) law."""
    alpha = _number(fraction, "mixing_fraction")
    if not 0 <= alpha <= 1:
        raise ValueError("mixing fraction outside [0,1]")
    target = state.total_kg * (state.upper_base_kg / state.base_kg)
    upper = state.upper_kg + alpha * (target - state.upper_kg)
    after = Partition(state.total_kg, upper, state.upper_base_kg, state.lower_base_kg)
    moved = upper - state.upper_kg
    return _receipt(state, after, "imposed_mixing", moved, -moved)


def budget(state, upper_delta_kg, lower_delta_kg, cause):
    """Explicit paired budget, not a selection, sink or vent law.

    A caller has to supply EACH zonal delta. A room-only delta cannot decide
    its partition. Candidate validation rejects overdrafts rather than clipping.
    """
    du = _number(upper_delta_kg, "upper_delta_kg")
    dl = _number(lower_delta_kg, "lower_delta_kg")
    if type(cause) is not str or not cause.strip():
        raise ValueError("a nonempty cause is required")
    lower = state.lower_kg + dl
    upper = state.upper_kg + du
    after = Partition(upper + lower, upper, state.upper_base_kg, state.lower_base_kg)
    return _receipt(state, after, cause, du, dl)


def broken_invariants(receipt):
    """Audit only exposed before/after/receipt fields, without rerunning an operation.

    Specific remap/mixing outcomes need a separate oracle (see tests); budget
    closure alone does NOT distinguish a wrong yet conservative routing.
    """
    result = []
    before, after = receipt.before, receipt.after
    if abs(after.total_kg - before.total_kg - receipt.room_delta_kg) > TOL_KG:
        result.append("P1_room_budget")
    if abs(after.upper_kg - before.upper_kg - receipt.upper_delta_kg) > TOL_KG:
        result.append("P2_upper_budget")
    if abs(after.lower_kg - before.lower_kg - receipt.lower_delta_kg) > TOL_KG:
        result.append("P3_lower_budget")
    if abs(receipt.upper_delta_kg + receipt.lower_delta_kg - receipt.room_delta_kg) > TOL_KG:
        result.append("P4_pair_matches_total")
    if receipt.cause in ("interface_remap", "imposed_mixing"):
        if receipt.room_delta_kg != 0 or after.total_kg != before.total_kg:
            result.append("P5_internal_preserves_room")
    if not math.isclose(before.base_kg, after.base_kg, rel_tol=0, abs_tol=TOL_KG):
        result.append("P6_reference_base_unchanged")
    # No operation trusts NaN in a receipt: comparisons alone would overlook it.
    if any(type(value) not in (int, float) or not math.isfinite(value)
           for value in (receipt.upper_delta_kg, receipt.lower_delta_kg, receipt.room_delta_kg)):
        result.append("P7_finite_receipt")
    return result
