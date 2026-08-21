extends SceneTree

## H3.2b3 fixture: read-only shadow comparison of legacy projection against the
## H3.2b2 pure primitive.
##
## It preloads the shadow accumulator and the primitive. It never builds an
## engine, a solver or a room: the shadow consumes the projection trace as plain
## dictionaries, which is exactly why it cannot write state.
##
## Synthetic trace events stand in for real ones. Their shape is the shape
## `ZoneFireSolver.gd:291-300` emits: a `cause`, a `room_id`, an `ambient_c`, a
## `pre` snapshot taken at entry and a `post` snapshot taken after the rewrite,
## plus the volumes legacy computed for itself.

const ShadowScript = preload("res://sim/core/Phase3ResidualProjectionShadow.gd")
const ResidualProjection = preload("res://sim/core/Phase3ResidualProjection.gd")

const EXPECTED_TESTS: int = 13

const AREA_M2: float = 20.0
const HEIGHT_M: float = 2.5
const AMBIENT_C: float = 20.0

var _failed: bool = false
var _completed: Array[String] = []


func _done(label: String) -> void:
	_completed.append(label)


func _init() -> void:
	_test_off_does_not_invoke_the_primitive()
	_test_legacy_and_residual_coincide()
	_test_legacy_rewrites_lower_mass_is_measured()
	_test_upper_absent()
	_test_lower_absent()
	_test_invalid_primitive_fails_closed_and_is_counted()
	_test_cause_is_preserved()
	_test_gross_and_signed_are_separated()
	_test_pressure_labels_are_correct()
	_test_presence_mismatch_is_visible()
	_test_shadow_writes_no_state()
	_test_negative_control_applying_the_result_would_be_detected()
	_test_interface_and_volume_divergence_are_reported()
	if _completed.size() != EXPECTED_TESTS:
		push_error("H3.2b3 ABORTED: %d/%d completed; ran %s"
			% [_completed.size(), EXPECTED_TESTS, str(_completed)])
		quit(1)
		return
	if _failed:
		quit(1)
		return
	print("PHASE3_H32B3_RESIDUAL_PROJECTION_SHADOW_PASS")
	quit(0)


# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------

func _shadow(on: bool = true):
	var s = ShadowScript.new()
	s.enabled = on
	return s


func _geometry(room_id: int = 0) -> Dictionary:
	return {
		str(room_id): {"floor_area_m2": AREA_M2, "room_height_m": HEIGHT_M},
	}


func _state(um: float, ue: float, lm: float, le: float,
		layer_m: float = HEIGHT_M, tu_c: float = AMBIENT_C,
		tl_c: float = AMBIENT_C) -> Dictionary:
	return {
		"upper_gas_kg": um,
		"upper_energy_kj": ue,
		"lower_gas_kg": lm,
		"lower_energy_kj": le,
		"thermal_layer_m": layer_m,
		"temp_upper_c": tu_c,
		"temp_lower_c": tl_c,
	}


func _event(cause: String, pre: Dictionary, post: Dictionary,
		room_id: int = 0, upper_volume_m3: float = 0.0,
		lower_volume_m3: float = 0.0) -> Dictionary:
	return {
		"cause": cause,
		"room_id": room_id,
		"ambient_c": AMBIENT_C,
		"pre": pre,
		"post": post,
		"upper_volume_m3": upper_volume_m3,
		"lower_volume_m3": lower_volume_m3,
	}


func _room(summary: Dictionary, room_id: int = 0) -> Dictionary:
	return summary["by_room"][str(room_id)]


func _identical_bytes(a, b) -> bool:
	var pa: PackedByteArray = var_to_bytes(a)
	var pb: PackedByteArray = var_to_bytes(b)
	if pa.size() != pb.size():
		return false
	for i in range(pa.size()):
		if pa[i] != pb[i]:
			return false
	return true


# --------------------------------------------------------------------------
# 11. OFF does not invoke the primitive
# --------------------------------------------------------------------------

func _test_off_does_not_invoke_the_primitive() -> void:
	var s = _shadow(false)
	var pre: Dictionary = _state(10.0, 2000.0, 45.0, 90.0)
	var post: Dictionary = _state(10.0, 2000.0, 40.0, 80.0)
	s.accumulate_step([_event("final_clamp_active", pre, post)], _geometry())
	_expect(s.summary().is_empty(),
		"with the shadow off the summary does not exist at all")
	# Turning it on afterwards must still start from nothing: the OFF step was
	# not recorded anywhere.
	s.enabled = true
	var after: Dictionary = s.summary()
	_expect(int(after["totals"].get("call_count_total", 0)) == 0,
		"nothing was accumulated while the shadow was off")
	_expect(after["by_room"].is_empty(), "and no room block was created")
	_done("off_does_not_invoke")


# --------------------------------------------------------------------------
# 1. Legacy and residual coincide
# --------------------------------------------------------------------------

func _test_legacy_and_residual_coincide() -> void:
	## Legacy rewrote nothing, so post == pre. The primitive returns M and E
	## bit-identical to pre, therefore the inventory divergence is exactly zero.
	var pre: Dictionary = _state(10.0, 2000.0, 45.0, 90.0)
	var post: Dictionary = _state(10.0, 2000.0, 45.0, 90.0)
	var s = _shadow()
	s.accumulate_step([_event("thermal_energy_projection", pre, post)], _geometry())
	var room: Dictionary = _room(s.summary())
	_expect(int(room["call_count_total"]) == 1, "the call is counted")
	_expect(int(room["primitive_valid_count_total"]) == 1, "the primitive is valid")
	for key in ["residual_vs_legacy_upper_mass_signed_net_kg_total",
			"residual_vs_legacy_lower_mass_signed_net_kg_total",
			"residual_vs_legacy_upper_energy_signed_net_kj_total",
			"residual_vs_legacy_lower_energy_signed_net_kj_total"]:
		_expect(float(room[key]) == 0.0,
			"no inventory divergence when legacy rewrote nothing: %s" % key)
	for key in ["legacy_rewrite_lower_mass_gross_absolute_kg_total",
			"legacy_rewrite_upper_mass_gross_absolute_kg_total"]:
		_expect(float(room[key]) == 0.0, "and legacy rewrote nothing: %s" % key)
	_done("coincide")


# --------------------------------------------------------------------------
# 2. Legacy rewrites lower_gas_kg
# --------------------------------------------------------------------------

func _test_legacy_rewrites_lower_mass_is_measured() -> void:
	## The defect H3.2b exists to remove: lower mass overwritten from the
	## remaining volume. Here legacy turned 45 kg into 40 kg.
	var pre: Dictionary = _state(10.0, 2000.0, 45.0, 90.0)
	var post: Dictionary = _state(10.0, 2000.0, 40.0, 80.0)
	var s = _shadow()
	s.accumulate_step([_event("final_clamp_active", pre, post)], _geometry())
	var room: Dictionary = _room(s.summary())
	_expect(is_equal_approx(
			float(room["legacy_rewrite_lower_mass_signed_net_kg_total"]), -5.0),
		"legacy removed exactly 5 kg from the lower zone")
	_expect(is_equal_approx(
			float(room["residual_vs_legacy_lower_mass_signed_net_kg_total"]), 5.0),
		"the residual keeps what legacy discarded, with the opposite sign")
	_expect(is_equal_approx(
			float(room["residual_vs_legacy_lower_mass_max_absolute_kg"]), 5.0),
		"and the maximum single divergence is recorded")
	_expect(is_equal_approx(
			float(room["residual_vs_legacy_lower_energy_signed_net_kj_total"]), 10.0),
		"the same for the energy legacy rescaled")
	_expect(float(room["residual_vs_legacy_upper_mass_signed_net_kg_total"]) == 0.0,
		"the upper zone was untouched by legacy in this call")
	_done("legacy_rewrites_lower")


# --------------------------------------------------------------------------
# 3 and 4. Absent zones
# --------------------------------------------------------------------------

func _test_upper_absent() -> void:
	var pre: Dictionary = _state(0.0, 0.0, 60.0, 600.0)
	var post: Dictionary = _state(0.0, 0.0, 58.0, 580.0)
	var s = _shadow()
	s.accumulate_step([_event("final_clamp_quiescent", pre, post)], _geometry())
	var room: Dictionary = _room(s.summary())
	_expect(int(room["primitive_valid_count_total"]) == 1,
		"an absent upper zone is a valid one-zone state for the primitive")
	_expect(float(room["residual_vs_legacy_upper_mass_signed_net_kg_total"]) == 0.0,
		"an absent upper zone contributes no mass divergence")
	_expect(is_equal_approx(
			float(room["residual_vs_legacy_lower_mass_signed_net_kg_total"]), 2.0),
		"while the lower rewrite is measured")
	_done("upper_absent")


func _test_lower_absent() -> void:
	var pre: Dictionary = _state(60.0, 600.0, 0.0, 0.0)
	var post: Dictionary = _state(60.0, 600.0, 0.0, 0.0)
	var s = _shadow()
	s.accumulate_step([_event("final_clamp_active", pre, post)], _geometry())
	var room: Dictionary = _room(s.summary())
	_expect(int(room["primitive_valid_count_total"]) == 1,
		"an absent lower zone is a valid one-zone state for the primitive")
	_expect(float(room["residual_vs_legacy_lower_mass_signed_net_kg_total"]) == 0.0,
		"and contributes no mass divergence")
	# An absent zone has no temperature, so nothing may be compared for it.
	_expect(int(room["residual_vs_legacy_lower_temp_comparable_count_total"]) == 0,
		"no temperature is compared for a zone absent in the primitive")
	_done("lower_absent")


# --------------------------------------------------------------------------
# 5. Invalid primitive fails closed, legacy continues, and it is counted
# --------------------------------------------------------------------------

func _test_invalid_primitive_fails_closed_and_is_counted() -> void:
	## Energy with no mass. The primitive rejects it. The legacy event is
	## untouched, the rejection is counted with its reason, and NOTHING is
	## substituted for the missing comparison.
	var pre: Dictionary = _state(0.0, 5.0, 45.0, 90.0)
	var post: Dictionary = _state(0.0, 0.0, 40.0, 80.0)
	var s = _shadow()
	s.accumulate_step([_event("reconcile_layer_sync", pre, post)], _geometry())
	var summary: Dictionary = s.summary()
	var room: Dictionary = _room(summary)
	_expect(int(room["call_count_total"]) == 1, "the call is still counted")
	_expect(int(room["primitive_invalid_count_total"]) == 1, "as an invalid one")
	_expect(int(room["primitive_valid_count_total"]) == 0, "and not as valid")
	_expect(int(summary["primitive_invalid_reason_counts"].get(
			ResidualProjection.REASON_ENERGY_WITHOUT_MASS, 0)) == 1,
		"the reason code is recorded")
	# The legacy rewrite is still measured -- it does not depend on the
	# primitive being able to evaluate the state.
	_expect(is_equal_approx(
			float(room["legacy_rewrite_lower_mass_signed_net_kg_total"]), -5.0),
		"what legacy did is recorded regardless")
	# But no divergence is invented for a comparison that could not be made.
	_expect(float(room["residual_vs_legacy_lower_mass_signed_net_kg_total"]) == 0.0,
		"and no divergence is fabricated for the rejected state")
	_done("invalid_fails_closed")


# --------------------------------------------------------------------------
# 6. Cause preserved
# --------------------------------------------------------------------------

func _test_cause_is_preserved() -> void:
	var pre: Dictionary = _state(10.0, 2000.0, 45.0, 90.0)
	var post: Dictionary = _state(10.0, 2000.0, 40.0, 80.0)
	var s = _shadow()
	s.accumulate_step([
		_event("gas_exchange_sync", pre, post),
		_event("gas_exchange_sync", pre, post),
		_event("thermal_post_losses_sync", pre, post),
	], _geometry())
	var by_cause: Dictionary = s.summary()["by_cause"]
	_expect(by_cause.has("gas_exchange_sync") and by_cause.has("thermal_post_losses_sync"),
		"each cause keeps its own block")
	_expect(int(by_cause["gas_exchange_sync"]["call_count_total"]) == 2,
		"with its own call count")
	_expect(int(by_cause["thermal_post_losses_sync"]["call_count_total"]) == 1,
		"and they are not merged")
	_expect(is_equal_approx(float(
			by_cause["gas_exchange_sync"]["residual_vs_legacy_lower_mass_signed_net_kg_total"]),
			10.0),
		"divergence accumulates per cause")
	_done("cause_preserved")


# --------------------------------------------------------------------------
# 7. Gross and signed separated
# --------------------------------------------------------------------------

func _test_gross_and_signed_are_separated() -> void:
	## Two opposite rewrites of equal size: the signed total cancels to exactly
	## zero while the gross total does not. Collapsing them would erase the
	## churn entirely.
	var pre: Dictionary = _state(10.0, 2000.0, 45.0, 90.0)
	var s = _shadow()
	s.accumulate_step([
		_event("gas_exchange_sync", pre, _state(10.0, 2000.0, 40.0, 90.0)),
		_event("gas_exchange_sync", pre, _state(10.0, 2000.0, 50.0, 90.0)),
	], _geometry())
	var summary: Dictionary = s.summary()
	var room: Dictionary = _room(summary)
	_expect(float(room["residual_vs_legacy_lower_mass_signed_net_kg_total"]) == 0.0,
		"the signed total cancels exactly")
	_expect(is_equal_approx(
			float(room["residual_vs_legacy_lower_mass_gross_absolute_kg_total"]), 10.0),
		"while the gross total records both rewrites")
	_expect(is_equal_approx(
			float(room["residual_vs_legacy_lower_mass_max_absolute_kg"]), 5.0),
		"and the largest single one is kept")
	# A net of exactly zero is reported as such, never divided by.
	var churn: Dictionary = summary["churn"]["residual_vs_legacy_lower_mass"]
	_expect(churn["status"] == "net_exactly_zero", "net zero is named, not divided by")
	_expect(churn["gross_over_net"] == null, "and no ratio is invented for it")
	_expect(is_equal_approx(float(churn["gross_absolute"]), 10.0),
		"the gross churn is still reported")
	_expect(summary["gross_absolute_meaning"].contains("NOT a physical contribution"),
		"and gross is documented as churn, not as a contribution")
	_done("gross_and_signed")


# --------------------------------------------------------------------------
# 8. Pressure labels
# --------------------------------------------------------------------------

func _test_pressure_labels_are_correct() -> void:
	var pre: Dictionary = _state(10.0, 2000.0, 45.0, 90.0)
	var post: Dictionary = _state(10.0, 2000.0, 40.0, 80.0)
	var s = _shadow()
	s.accumulate_step([_event("final_clamp_active", pre, post)], _geometry())
	var summary: Dictionary = s.summary()
	var totals: Dictionary = summary["totals"]
	_expect(totals.has("canonical_pressure_pre_pa_sum"),
		"the primitive's own pre-state pressure is reported")
	_expect(totals.has("canonical_pressure_from_legacy_post_pa_sum"),
		"and the recomputation from the legacy post inventory, separately")
	_expect(totals.has("canonical_pressure_pre_pa_min")
			and totals.has("canonical_pressure_pre_pa_max"),
		"with extremes")
	# The two are genuinely different numbers here, so they cannot be conflated.
	_expect(float(totals["canonical_pressure_pre_pa_sum"])
			!= float(totals["canonical_pressure_from_legacy_post_pa_sum"]),
		"they differ because the inventories differ")
	# Nothing may be called a legacy pressure, because legacy stores none.
	for key in totals.keys():
		var name: String = String(key)
		_expect(not name.contains("legacy_pressure"),
			"legacy stores no pressure, so nothing may be named one: %s" % name)
	_expect(summary["pressure_label_note"].contains("NOT a pressure legacy"),
		"and the label is spelled out in the summary")
	_done("pressure_labels")


# --------------------------------------------------------------------------
# 9. Presence mismatch visible
# --------------------------------------------------------------------------

func _test_presence_mismatch_is_visible() -> void:
	## 5e-5 kg is present to the primitive (M > 0) and absent to the legacy
	## projection predicate (M > 1e-4). That is a definitional disagreement
	## between two predicates, not lost mass.
	var pre: Dictionary = _state(10.0, 2000.0, 5.0e-5, 0.0)
	var post: Dictionary = _state(10.0, 2000.0, 5.0e-5, 0.0)
	var s = _shadow()
	s.accumulate_step([_event("final_clamp_quiescent", pre, post)], _geometry())
	var summary: Dictionary = s.summary()
	var room: Dictionary = _room(summary)
	_expect(int(room["presence_predicate_mismatch_lower_total"]) == 1,
		"the lower-zone predicate disagreement is counted")
	_expect(int(room["presence_predicate_mismatch_total"]) == 1,
		"and rolled up")
	_expect(int(room["presence_predicate_mismatch_upper_total"]) == 0,
		"while the upper zone agrees")
	_expect(is_equal_approx(float(summary["legacy_presence_predicate_kg"]), 1.0e-4),
		"the legacy predicate being compared is identified")
	_expect(summary["presence_predicate_note"].contains("never evidence of lost mass"),
		"and a mismatch is not presented as a physical loss")
	_expect(summary["presence_predicate_note"].contains("blocker for H3.2b6"),
		"choosing a canonical predicate is recorded as a blocker")
	_done("presence_mismatch")


# --------------------------------------------------------------------------
# 10. The shadow cannot write state
# --------------------------------------------------------------------------

func _test_shadow_writes_no_state() -> void:
	## It is handed dictionaries, never a RoomModel, and it must not even mutate
	## those. The inputs are compared byte for byte before and after.
	var pre: Dictionary = _state(10.0, 2000.0, 45.0, 90.0)
	var post: Dictionary = _state(10.0, 2000.0, 40.0, 80.0)
	var events: Array = [_event("final_clamp_active", pre, post)]
	var geometry: Dictionary = _geometry()
	var events_before: PackedByteArray = var_to_bytes(events)
	var geometry_before: PackedByteArray = var_to_bytes(geometry)
	var s = _shadow()
	s.accumulate_step(events, geometry)
	_expect(_identical_bytes(events, bytes_to_var(events_before)),
		"the trace events are byte-identical after the comparison")
	_expect(_identical_bytes(geometry, bytes_to_var(geometry_before)),
		"and so is the geometry it was handed")
	_expect(bool(s.summary()["shadow_applied"]) == false,
		"the summary states explicitly that nothing was applied")
	_done("writes_no_state")


# --------------------------------------------------------------------------
# 12. Negative control: applying the result would be detected
# --------------------------------------------------------------------------

func _test_negative_control_applying_the_result_would_be_detected() -> void:
	## The control has two halves. First, a state where legacy really did rewrite
	## the lower zone produces a NON-ZERO divergence, so "apply the residual" and
	## "keep legacy" are distinguishable outcomes. Second, the legacy post in the
	## event is unchanged by the comparison, so the shadow did not apply it.
	##
	## If a future edit made the shadow write the residual back into `post`, the
	## measured divergence would collapse to zero and the first half would fail.
	var pre: Dictionary = _state(10.0, 2000.0, 45.0, 90.0)
	var post: Dictionary = _state(10.0, 2000.0, 40.0, 80.0)
	var event: Dictionary = _event("final_clamp_active", pre, post)
	var s = _shadow()
	s.accumulate_step([event], _geometry())
	var room: Dictionary = _room(s.summary())
	var divergence: float = float(
		room["residual_vs_legacy_lower_mass_signed_net_kg_total"])
	_expect(divergence != 0.0,
		"applying the residual instead of legacy would change the state")
	_expect(is_equal_approx(divergence, 5.0),
		"and the size of that change is exactly what is reported")
	_expect(float(event["post"]["lower_gas_kg"]) == 40.0,
		"the legacy post value in the event is untouched by the comparison")
	_expect(float(event["pre"]["lower_gas_kg"]) == 45.0,
		"and so is the pre value")
	# Simulating the forbidden write proves the check above can actually fail.
	var applied: Dictionary = _event("final_clamp_active", pre,
		_state(10.0, 2000.0, 45.0, 90.0))
	var s2 = _shadow()
	s2.accumulate_step([applied], _geometry())
	_expect(float(_room(s2.summary())[
			"residual_vs_legacy_lower_mass_signed_net_kg_total"]) == 0.0,
		"had the residual been applied, the divergence would read zero -- which"
		+ " is what makes the non-zero reading above meaningful")
	_done("negative_control")


# --------------------------------------------------------------------------
# Interface, volumes, temperatures
# --------------------------------------------------------------------------

func _test_interface_and_volume_divergence_are_reported() -> void:
	var pre: Dictionary = _state(10.0, 2000.0, 45.0, 90.0, 1.5, 220.0, 22.0)
	var post: Dictionary = _state(10.0, 2000.0, 40.0, 80.0, 1.5, 220.0, 22.0)
	var s = _shadow()
	s.accumulate_step([_event("final_clamp_active", pre, post, 0, 12.0, 38.0)],
		_geometry())
	var room: Dictionary = _room(s.summary())
	_expect(float(room["residual_vs_legacy_interface_gross_absolute_m_total"]) > 0.0,
		"the interface divergence against the stored layer height is reported")
	_expect(float(room["residual_vs_legacy_upper_volume_gross_absolute_m3_total"]) > 0.0,
		"the upper volume divergence against the legacy volume is reported")
	_expect(float(room["residual_vs_legacy_lower_volume_gross_absolute_m3_total"]) > 0.0,
		"and the lower volume divergence too")
	# Temperatures are compared only where both models have the zone.
	_expect(int(room["residual_vs_legacy_upper_temp_comparable_count_total"]) == 1,
		"the upper temperature is comparable here")
	_expect(int(room["residual_vs_legacy_lower_temp_comparable_count_total"]) == 1,
		"and so is the lower one")
	_expect(float(room["residual_vs_legacy_upper_temp_gross_absolute_k_total"]) >= 0.0,
		"the temperature divergence is accumulated")
	_done("interface_and_volumes")


func _expect(condition: bool, label: String) -> void:
	if condition:
		return
	_failed = true
	push_error("H3.2b3 ASSERTION FAILED: %s" % label)
