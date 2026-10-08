extends SceneTree

## Isolated fixture of the prescribed object HRR source. NOT SimulationEngine,
## not a room fire and not a prediction: synthetic tables with analytic answers
## and the measured table of one run, judged against an exact offline oracle.
## A refusal counts only as an explicit `valid == false` with reasons; an empty
## value from a call that aborted is a failure, never a refusal.
const Source = preload("res://sim/fire/PrescribedObjectHrrSource.gd")
const REAL_FIXTURE: String = "res://tests/fixtures/g3_object_hrr_source_test016.json"
const ABS_TOL: float = 1.0e-9
const REL_TOL: float = 1.0e-12
const TRIANGLE: Array = [[0.0, 0.0], [10.0, 100.0], [20.0, 0.0]]
const UNEVEN: Array = [[0.0, 2.0], [3.0, 8.0], [4.0, 1.0], [10.0, 1.0]]
const CONFIRM_KEYS: Array = [
	"valid", "errors", "scheduled_this_step_kj", "accepted_this_step_kj", "rejected_this_step_kj", "state",
]
var _failed: bool = false
var _checks: int = 0
var _group_name: String = ""
var _groups: Array[String] = []
var _failures: Array[String] = []
var _observations: Dictionary = {}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_interpolation()
	_integration_and_units()
	_acceptance()
	_proposals()
	_support_and_duration()
	_source_validation()
	_snapshots()
	_identity()
	_measured_run()
	print("G3_OBJECT_HRR_SOURCE " + JSON.stringify({"checks": _checks, "groups": _groups,
		"failures": _failures, "observations": _observations}, "", true, true))
	if _failed:
		quit(1)
	else:
		print("G3_OBJECT_HRR_SOURCE_PASS")
		quit(0)


# ---------------------------------------------------------------- synthetic tables

func _synthetic(points: Array, owner_id: String = "synthetic_object_as_tested") -> Dictionary:
	var samples: Array = []
	for point: Array in points:
		samples.append({"time_s": point[0], "hrr_kw": point[1]})
	var unknown: Dictionary = {}
	for key: String in Source.UNKNOWN_KEYS:
		unknown[key] = null
	return {
		"schema": Source.SOURCE_SCHEMA, "owner_id": owner_id, "run_id": "synthetic_run_1",
		"quantity": "measured_calorimetric_hrr", "time_unit": "s", "hrr_unit": "kW", "energy_unit": "kJ",
		"time_origin": "documented_ignition_event", "interpolation": "piecewise_linear",
		"outside_support": "reject", "negative_samples": "none_in_source", "regime": "open_air_as_tested",
		"provenance": {
			"dataset": "synthetic analytic table, not a measurement", "dataset_version": "v1",
			"license": "none needed", "source_file": "tests/fixtures/g3_object_hrr_source.gd",
			"source_sha256": "0".repeat(64), "source_column": "hrr_kw", "support_events": "0 to the last node",
			"importer": "written by hand", "table_fingerprint": "1".repeat(64),
		},
		"unknown": unknown, "samples": samples,
	}


func _interpolation() -> void:
	_group("G01 interpolation and extremes")
	var src: RefCounted = _open(_synthetic(TRIANGLE), "triangle")
	for pair: Array in [[0.0, 0.0], [5.0, 50.0], [10.0, 100.0], [12.5, 75.0], [19.0, 10.0], [20.0, 0.0], [0, 0.0], [10, 100.0]]:
		_value(src, pair[0], pair[1], "triangle at " + str(pair[0]))
	src = _open(_synthetic(UNEVEN), "uneven")
	for pair: Array in [[0.0, 2.0], [1.5, 5.0], [3.0, 8.0], [3.5, 4.5], [3.75, 2.75], [4.0, 1.0], [7.0, 1.0], [10.0, 1.0]]:
		_value(src, pair[0], pair[1], "uneven at " + str(pair[0]))
	# The value at a node is the sample itself, from either side.
	var node: Dictionary = src.hrr_kw(3.0)
	_check(_positive(node) and node.get("hrr_kw") == 8.0, "node returns the sample bit by bit")


func _integration_and_units() -> void:
	_group("G02 integration, several segments and units")
	var triangle: Dictionary = _synthetic(TRIANGLE)
	for row: Array in [[0.0, 20.0, 1000.0], [0.0, 5.0, 125.0], [5.0, 15.0, 750.0], [15.0, 20.0, 125.0],
			[0.0, 10.0, 500.0], [2.5, 7.5, 250.0], [9.0, 11.0, 190.0]]:
		_near(_interval(triangle, row[0], row[1]), row[2], "triangle " + str(row[0]) + " to " + str(row[1]))
	var uneven: Dictionary = _synthetic(UNEVEN)
	for row: Array in [[0.0, 10.0, 25.5], [0.0, 3.0, 15.0], [3.0, 4.0, 4.5], [4.0, 10.0, 6.0],
			[1.5, 7.0, 17.25], [3.5, 3.75, 0.90625], [0.0, 1.5, 5.25], [2.0, 9.0, 16.5]]:
		_near(_interval(uneven, row[0], row[1]), row[2], "uneven " + str(row[0]) + " to " + str(row[1]))
	# Declared conversion: one kilowatt for one second is one kilojoule.
	var unit: Variant = _interval(_synthetic([[0.0, 1.0], [1.0, 1.0]]), 0.0, 1.0)
	_check(typeof(unit) == TYPE_FLOAT and unit == 1.0, "1 kW during 1 s is exactly 1 kJ")
	_near(_interval(_synthetic([[0.0, 7.0], [3600.0, 7.0]]), 0.0, 3600.0), 25200.0, "7 kW during one hour")
	_check(Source.KJ_PER_KW_S == 1.0, "conversion constant declared")
	# The same interval cut in different ways adds up to the same energy.
	for points: Array in [TRIANGLE, UNEVEN]:
		var whole: Dictionary = _campaign(_synthetic(points), [points[-1][0]], false, "whole")
		for ends: Array in [[1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, points[-1][0]],
				[0.3, 1.1, 2.7, 3.0, 3.01, 6.1, 7.7, 9.9, points[-1][0]], [9.999, points[-1][0]]]:
			var cut: Dictionary = _campaign(_synthetic(points), ends, false, "cut")
			_check(not cut.is_empty() and cut.get("scheduled_kj") == whole.get("scheduled_kj"),
				"scheduled total does not depend on the partition")
			_near(cut.get("sum_of_steps_kj"), _float(whole.get("sum_of_steps_kj")), "steps add up to the whole")
			_near(cut.get("accepted_kj"), _float(whole.get("accepted_kj")), "accepted total is the same")


func _acceptance() -> void:
	_group("G03 acceptance, rejection without queue, single count")
	var src: RefCounted = _open(_synthetic(TRIANGLE), "triangle")
	var first: Dictionary = _proposed(src, 5.0, "first interval")
	_near(first.get("energy_kj"), 125.0, "first interval proposes its own energy")
	var done: Dictionary = src.confirm(first, 25.0)
	_check(_accepted(done) and done.keys() == CONFIRM_KEYS, "partial confirmation and exact result fields")
	_near(done.get("accepted_this_step_kj"), 25.0, "accepted part")
	_near(done.get("rejected_this_step_kj"), 100.0, "rejected part is recorded")
	_near(done.get("scheduled_this_step_kj"), 125.0, "scheduled part")
	_state(src, 5.0, 125.0, 25.0, 100.0, 1, "after a partial confirmation")
	# Rejected energy is not queued: the next interval holds only its own energy.
	var second: Dictionary = _proposed(src, 15.0, "second interval")
	_check(second.get("energy_kj") == _interval(_synthetic(TRIANGLE), 5.0, 15.0), "next interval is unaffected by the rejection")
	_near(second.get("energy_kj"), 750.0, "next interval is not enlarged by rejected energy")
	_check(_accepted(src.confirm(second, second.get("energy_kj"))), "complete confirmation")
	_state(src, 15.0, 875.0, 775.0, 100.0, 2, "after a complete confirmation")
	var third: Dictionary = _proposed(src, 20.0, "third interval")
	_check(_accepted(src.confirm(third, 0.0)), "null confirmation")
	_state(src, 20.0, 1000.0, 775.0, 225.0, 3, "after a null confirmation")
	# Confirming the same proposal again counts nothing.
	var before: Dictionary = src.snapshot()
	for proposal: Dictionary in [first, second, third]:
		_refused(src.confirm(proposal, 0.0), "second confirmation of a counted interval")
		_refused(src.confirm(proposal, proposal.get("energy_kj")), "second complete confirmation")
	_check(src.snapshot() == before, "repeated confirmations change nothing")
	_refused(src.propose(20.0), "nothing left at the end of the support")
	# A partial confirmation does not make the whole interval come back.
	src = _open(_synthetic(TRIANGLE), "triangle again")
	var whole: Dictionary = _proposed(src, 20.0, "whole support")
	_check(_accepted(src.confirm(whole, 250.0)), "partial confirmation of the whole support")
	_state(src, 20.0, 1000.0, 250.0, 750.0, 1, "after one partial confirmation")
	_refused(src.confirm(whole, 750.0), "the rejected part cannot be claimed later")
	_refused(src.propose(20.0), "the interval is not offered again")
	_state(src, 20.0, 1000.0, 250.0, 750.0, 1, "still one count")
	# What may be accepted: between nothing and the proposed energy.
	src = _open(_synthetic(TRIANGLE), "triangle limits")
	var offer: Dictionary = _proposed(src, 10.0, "limits")
	before = src.snapshot()
	for bad: Variant in [500.0000001, 1000.0, -0.001, -1, NAN, INF, -INF, true, false, null, "250", [250.0], {}]:
		_refused(src.confirm(offer, bad), "accepted energy " + str(bad))
		_check(src.snapshot() == before, "refused acceptance changes nothing: " + str(bad))
	_check(_accepted(src.confirm(offer, 500)), "an integer amount inside the interval is a number")
	_state(src, 10.0, 500.0, 500.0, 0.0, 1, "after the valid confirmation")


func _proposals() -> void:
	_group("G04 proposals: pure, stale, repeated, altered, foreign")
	var src: RefCounted = _open(_synthetic(TRIANGLE), "triangle")
	var before: Dictionary = src.snapshot()
	var report: String = var_to_str(src.report())
	var first: Dictionary = _proposed(src, 5.0, "first")
	_check(first == _proposed(src, 5.0, "again") and first.keys() == Source.PROPOSAL_KEYS, "proposal is deterministic and has exact fields")
	_check(src.snapshot() == before and var_to_str(src.report()) == report, "proposing delivers and counts nothing")
	_check(first.get("generation") == 0 and first.get("start_time_s") == 0.0 and first.get("dt_s") == 5.0, "proposal names its interval")
	# Altered proposals.
	for change: Array in [["energy_kj", 250.0], ["energy_kj", 0.0], ["energy_kj", 125], ["energy_kj", "125"],
			["energy_kj", NAN], ["end_time_s", 6.0], ["end_time_s", 20.0], ["end_time_s", 5], ["end_time_s", null],
			["dt_s", 4.0], ["dt_s", true], ["start_time_s", 1.0], ["start_time_s", -0.5], ["generation", 1],
			["generation", -1], ["generation", 0.0], ["generation", "0"], ["generation", null],
			["schema", "g3_prescribed_fuel_release_v1"], ["schema", 1], ["owner_id", "another_object"],
			["owner_id", null], ["run_id", "synthetic_run_2"], ["run_id", 7], ["source_fingerprint", "0".repeat(64)],
			["source_fingerprint", false]]:
		var altered: Dictionary = first.duplicate(true)
		altered[change[0]] = change[1]
		_refused(src.confirm(altered, 0.0), "altered " + change[0] + " = " + str(change[1]))
	var extra: Dictionary = first.duplicate(true)
	extra["mass_kg"] = 0.0
	_refused(src.confirm(extra, 0.0), "proposal with an extra field")
	var missing: Dictionary = first.duplicate(true)
	missing.erase("dt_s")
	_refused(src.confirm(missing, 0.0), "proposal with a missing field")
	for bad: Variant in [null, [], "proposal", 5.0, true]:
		_refused(src.confirm(bad, 0.0), "proposal that is not a record")
	_check(src.snapshot() == before, "refused proposals change nothing")
	# A proposal of another owner, run or table.
	var other_owner: RefCounted = _open(_synthetic(TRIANGLE, "another_object_as_tested"), "other owner")
	var other_run: Dictionary = _synthetic(TRIANGLE)
	other_run["run_id"] = "synthetic_run_2"
	var other_table: Array = TRIANGLE.duplicate(true)
	other_table[1] = [10.0, 100.5]
	for foreign: RefCounted in [other_owner, _open(other_run, "other run"), _open(_synthetic(other_table), "other table")]:
		var theirs: Dictionary = _proposed(foreign, 5.0, "foreign proposal")
		_refused(src.confirm(theirs, 0.0), "proposal of another owner, run or table")
		_check(_accepted(foreign.confirm(theirs, 1.0)), "it is valid for its own owner")
	_check(src.snapshot() == before, "foreign proposals change nothing")
	# Stale: two offers from the same state; confirming one retires the other.
	var longer: Dictionary = _proposed(src, 10.0, "longer")
	_check(_accepted(src.confirm(longer, 100.0)), "one of two outstanding offers is confirmed")
	_refused(src.confirm(first, 0.0), "the other offer is stale")
	_refused(src.confirm(longer, 100.0), "the confirmed offer cannot be confirmed twice")
	_state(src, 10.0, 500.0, 100.0, 400.0, 1, "one count after stale and repeated offers")
	# The genuine offer still works after all the refusals: nothing was consumed.
	var genuine: Dictionary = _proposed(src, 20.0, "genuine")
	_check(_accepted(src.confirm(genuine, genuine.get("energy_kj"))), "a fresh offer is confirmed")
	_state(src, 20.0, 1000.0, 600.0, 400.0, 2, "final counters")
	# An owner that was never opened answers nothing.
	var closed: RefCounted = Source.new()
	_check(closed.snapshot() == {} and closed.report() == {}, "unopened owner has no state")
	for result: Dictionary in [closed.propose(1.0), closed.confirm(first, 0.0), closed.hrr_kw(0.0),
			closed.restore(before), closed.reset()]:
		_refused(result, "unopened owner")
	_refused(src.open(_synthetic(UNEVEN)), "a second source for the same owner")
	_state(src, 20.0, 1000.0, 600.0, 400.0, 2, "a refused second source changes nothing")


func _support_and_duration() -> void:
	_group("G05 support and duration")
	var src: RefCounted = _open(_synthetic(TRIANGLE), "triangle")
	var before: Dictionary = src.snapshot()
	for bad: Variant in [-0.001, -1, 20.0001, 21, 1.0e9, NAN, INF, -INF, null, "5", true, false, [5.0], {}]:
		_refused(src.hrr_kw(bad), "value outside the support or not a time: " + str(bad))
		_refused(src.propose(bad), "interval end outside the support or not a time: " + str(bad))
	_refused(src.propose(0.0), "zero duration at the ignition")
	_check(src.snapshot() == before, "refused requests change nothing")
	_advance(src, 10.0, 1.0, "to the peak")
	before = src.snapshot()
	_refused(src.propose(10.0), "zero duration")
	_refused(src.propose(9.999), "time reversal")
	_refused(src.propose(0.0), "back to the ignition")
	_refused(src.propose(20.0000001), "just past the end of the support")
	_check(src.snapshot() == before, "refused intervals change nothing")
	_value(src, 20.0, 0.0, "last node is inside the support")
	_near(_proposed(src, 20.0, "to the last node").get("energy_kj"), 500.0, "the support ends at the last node")
	# No hold of the last value: a table that ends above zero ends all the same.
	src = _open(_synthetic([[0.0, 4.0], [2.0, 6.0]]), "ends above zero")
	_value(src, 2.0, 6.0, "last value")
	_refused(src.hrr_kw(2.5), "the last value is not held")
	_refused(src.propose(3.0), "the last value is not integrated past the end")
	_advance(src, 2.0, 1.0, "to the end")
	_refused(src.propose(2.5), "nothing after the end")
	_state(src, 2.0, 10.0, 10.0, 0.0, 1, "only the support was counted")


func _source_validation() -> void:
	_group("G06 source validation")
	var base: Dictionary = _synthetic(TRIANGLE)
	var text: String = var_to_str(base)
	for bad: Variant in [null, [], "source", 5.0, true, {}]:
		_unopened(bad, "source that is not a record")
	for key: String in Source.SOURCE_KEYS:
		var without: Dictionary = base.duplicate(true)
		without.erase(key)
		_unopened(without, "source without " + key)
	for key: String in ["scale", "time_shift_s", "initial_mass_kg", "heat_of_combustion_kj_kg", "fuel_energy_MJ", "co_yield"]:
		var with_extra: Dictionary = base.duplicate(true)
		with_extra[key] = 1.0
		_unopened(with_extra, "source with " + key)
	for change: Array in [["schema", "g3_prescribed_object_hrr_source_v2"], ["quantity", "modeled_hrr"],
			["time_unit", "min"], ["time_unit", "ms"], ["hrr_unit", "W"], ["hrr_unit", "MW"], ["hrr_unit", "kw"],
			["energy_unit", "MJ"], ["energy_unit", "J"], ["time_origin", "start_of_recording"],
			["interpolation", "piecewise_constant_left"], ["interpolation", "hold_last"],
			["outside_support", "hold_last"], ["outside_support", "extrapolate"], ["outside_support", "clip"],
			["regime", "enclosure"], ["negative_samples", "allowed"], ["negative_samples", "clipped_here"],
			["hrr_unit", 1], ["hrr_unit", true], ["hrr_unit", null], ["hrr_unit", ["kW"]], ["hrr_unit", &"kW"],
			["negative_samples", 0], ["owner_id", ""], ["owner_id", "   "], ["owner_id", null], ["owner_id", 5],
			["run_id", ""], ["run_id", false], ["provenance", null], ["provenance", "NIST"], ["unknown", null],
			["unknown", []], ["samples", null], ["samples", "table"], ["samples", []],
			["samples", [{"time_s": 0.0, "hrr_kw": 1.0}]]]:
		_unopened(_changed(base, change[0], change[1]), "source with " + change[0] + " = " + str(change[1]))
	for key: String in Source.PROVENANCE_KEYS:
		for bad: Variant in ["", null, 3]:
			_unopened(_nested(base, "provenance", key, bad), "provenance." + key + " = " + str(bad))
		var without: Dictionary = base.duplicate(true)
		without["provenance"].erase(key)
		_unopened(without, "provenance without " + key)
	for bad: String in ["abc", "0".repeat(63), "0".repeat(65), "A".repeat(64), "g".repeat(64)]:
		_unopened(_nested(base, "provenance", "source_sha256", bad), "source hash " + bad)
		_unopened(_nested(base, "provenance", "table_fingerprint", bad), "table fingerprint " + bad)
	_unopened(_nested(base, "provenance", "note", "extra"), "provenance with an extra field")
	# Unknown stays unknown: a zero would be a physical statement nobody measured.
	for key: String in Source.UNKNOWN_KEYS:
		for bad: Variant in [0.0, 0, false, "", "unknown", {}, [], 0.3]:
			_unopened(_nested(base, "unknown", key, bad), "unknown." + key + " = " + str(bad))
		var without: Dictionary = base.duplicate(true)
		without["unknown"].erase(key)
		_unopened(without, "unknown without " + key)
	_unopened(_nested(base, "unknown", "soot_yield", null), "unknown with an extra field")
	# Samples.
	for bad: Variant in [-0.01, -1, -1.0e-300, NAN, INF, -INF, "0.1", true, null, [1.0], {}]:
		_unopened(_sample(base, 1, "hrr_kw", bad), "sample value " + str(bad))
		_unopened(_sample(base, 1, "time_s", bad), "sample time " + str(bad))
	_unopened(_sample(base, 0, "hrr_kw", -0.36), "negative first sample")
	_unopened(_sample(base, 2, "hrr_kw", -0.36), "negative last sample")
	_unopened(_sample(base, 1, "time_s", 0.0), "repeated time")
	_unopened(_sample(base, 2, "time_s", 10.0), "repeated time at the end")
	_unopened(_sample(base, 1, "time_s", 25.0), "times out of order")
	_unopened(_sample(base, 2, "time_s", 4.0), "last time out of order")
	_unopened(_sample(base, 0, "time_s", 1.0), "support that does not start at the ignition")
	var with_item: Dictionary = base.duplicate(true)
	with_item["samples"][1] = [10.0, 100.0]
	_unopened(with_item, "sample that is not a record")
	with_item = base.duplicate(true)
	with_item["samples"][1].erase("hrr_kw")
	_unopened(with_item, "sample without a value")
	with_item = base.duplicate(true)
	with_item["samples"][1]["mass_kg"] = 9.68
	_unopened(with_item, "sample with a mass")
	_unopened(_synthetic([[0.0, 1.0e308], [1.0e308, 1.0e308]]), "energy that overflows")
	_check(var_to_str(base) == text, "refused sources are not modified")
	# The owner keeps its own copy: later edits by the caller do not reach it.
	var src: RefCounted = _open(base, "base")
	var identity: Variant = src.report().get("source_fingerprint")
	_check(var_to_str(base) == text, "an accepted source is not modified")
	base["samples"][1]["hrr_kw"] = 999.0
	base["owner_id"] = "edited_after_opening"
	_value(src, 10.0, 100.0, "the table is the one that was opened")
	_check(src.report().get("source_fingerprint") == identity and src.report().get("owner_id") == "synthetic_object_as_tested",
		"identity and owner are the ones that were opened")
	# What the owner says about itself: unknowns are null and nothing is approved.
	var report: Dictionary = src.report()
	_check(report.get("version") == Source.VERSION and report.get("scope") == Source.SCOPE, "report names version and scope")
	_check(report.get("units") == {"time": "s", "hrr": "kW", "energy": "kJ"} and report.get("kj_per_kw_s") == 1.0, "report declares units")
	_check(report.get("support_s") == [0.0, 20.0] and report.get("samples") == 3, "report declares the support")
	_near(report.get("table_energy_kj"), 1000.0, "report gives the energy of the table")
	_check(typeof(report.get("unknown")) == TYPE_DICTIONARY and report["unknown"].keys() == Source.UNKNOWN_KEYS, "report lists the unknowns")
	for key: String in Source.UNKNOWN_KEYS:
		_check(report.get("unknown", {}).has(key) and typeof(report["unknown"][key]) == TYPE_NIL, "unknown " + key + " is null, not zero")
	for key: String in ["predictive", "valid_in_an_enclosure", "engine_integration", "product_activation", "co_fed_approval"]:
		_check(typeof(report.get(key)) == TYPE_BOOL and not report[key], "not approved: " + key)
	_check(report.get("rejected_energy") == "recorded_not_queued_no_physical_cause_attached", "rejected energy carries no physical cause")
	_check(report.get("state") == src.snapshot(), "report carries the state")


func _snapshots() -> void:
	_group("G07 snapshot, restore and reset")
	var source: Dictionary = _synthetic(TRIANGLE)
	var src: RefCounted = _open(source, "triangle")
	_advance(src, 5.0, 0.2, "to 5 s")
	var saved: Dictionary = src.snapshot()
	_check(saved.keys() == Source.SNAPSHOT_KEYS, "snapshot has exact fields")
	saved["accepted_kj"] = 999.0
	_check(src.snapshot().get("accepted_kj") != 999.0 and src.snapshot().get("generation") == 1, "a snapshot is a copy")
	saved = src.snapshot()
	var at_five: Dictionary = _proposed(src, 15.0, "offer issued at 5 s")
	var continued: Dictionary = _advance(src, 15.0, 1.0, "to 15 s")
	var outstanding: Dictionary = _proposed(src, 20.0, "outstanding offer")
	# Rewind: explicit, and every earlier offer is retired.
	var restored: Dictionary = src.restore(saved)
	_check(_accepted(restored), "restore")
	_state(src, 5.0, 125.0, 25.0, 100.0, 3, "restored clock and counters, new generation")
	_refused(src.confirm(outstanding, 0.0), "an offer issued before the restore is stale")
	_refused(src.confirm(at_five, 0.0), "an offer issued at the restored time, before the restore, is stale")
	_state(src, 5.0, 125.0, 25.0, 100.0, 3, "stale offers change nothing after a restore")
	var replayed: Dictionary = _advance(src, 15.0, 1.0, "replay to 15 s")
	_check(replayed.get("scheduled_this_step_kj") == continued.get("scheduled_this_step_kj"), "the replay is deterministic")
	_state(src, 15.0, 875.0, 775.0, 100.0, 4, "after the replay")
	# Rebuild: a new owner of the same source takes over from the snapshot.
	var rebuilt: RefCounted = _open(source, "rebuilt")
	var early: Dictionary = _proposed(rebuilt, 5.0, "offer of the new owner before taking over")
	_check(_accepted(rebuilt.restore(saved)), "rebuild from a snapshot")
	_state(rebuilt, 5.0, 125.0, 25.0, 100.0, 2, "rebuilt owner")
	_refused(rebuilt.confirm(early, 0.0), "an offer of the new owner before the takeover is stale")
	_advance(rebuilt, 15.0, 1.0, "rebuilt to 15 s")
	_advance(rebuilt, 20.0, 0.0, "rebuilt to the end")
	_advance(src, 20.0, 0.0, "original to the end")
	for key: String in ["time_s", "scheduled_kj", "accepted_kj", "rejected_kj"]:
		_check(rebuilt.snapshot().get(key) == src.snapshot().get(key), "rebuilt and original agree on " + key)
	# Snapshots that are refused, each without any change.
	var before: Dictionary = src.snapshot()
	var foreign: RefCounted = _open(_synthetic(TRIANGLE, "another_object_as_tested"), "foreign")
	_advance(foreign, 5.0, 0.2, "foreign to 5 s")
	_refused(src.restore(foreign.snapshot()), "snapshot of another owner")
	for change: Array in [["accepted_kj", 125.0], ["accepted_kj", 0.0], ["rejected_kj", 0.0], ["scheduled_kj", 500.0],
			["scheduled_kj", 0.0], ["time_s", 10.0], ["time_s", 20.5], ["time_s", -1.0], ["time_s", NAN],
			["time_s", "5"], ["accepted_kj", -25.0], ["accepted_kj", INF], ["rejected_kj", true],
			["generation", -1], ["generation", 1.0], ["generation", "1"], ["generation", null],
			["schema", "g3_prescribed_object_hrr_proposal_v1"], ["owner_id", "another_object_as_tested"],
			["run_id", "synthetic_run_2"], ["source_fingerprint", "f".repeat(64)], ["source_fingerprint", 5]]:
		_refused(src.restore(_changed(saved, change[0], change[1])), "snapshot with " + change[0] + " = " + str(change[1]))
	var extra: Dictionary = saved.duplicate(true)
	extra["mass_kg"] = 9.68
	_refused(src.restore(extra), "snapshot with an extra field")
	for bad: Variant in [null, [], "snapshot", {}]:
		_refused(src.restore(bad), "snapshot that is not a record")
	_check(src.snapshot() == before, "refused snapshots change nothing")
	# Restart: back to the ignition with empty counters and a new generation.
	src = _open(source, "for reset")
	var at_ignition: Dictionary = _proposed(src, 4.0, "offer issued at the ignition")
	var steps: Array = [_advance(src, 4.0, 0.5, "before reset 1"), _advance(src, 11.0, 0.25, "before reset 2")]
	var pending: Dictionary = _proposed(src, 20.0, "pending at reset")
	_check(_accepted(src.reset()), "reset")
	_state(src, 0.0, 0.0, 0.0, 0.0, 3, "reset state")
	_refused(src.confirm(pending, 0.0), "an offer issued before the reset is stale")
	_refused(src.confirm(at_ignition, 0.0), "an offer issued at the ignition, before the reset, is stale")
	_state(src, 0.0, 0.0, 0.0, 0.0, 3, "stale offers change nothing after a reset")
	var again: Array = [_advance(src, 4.0, 0.5, "after reset 1"), _advance(src, 11.0, 0.25, "after reset 2")]
	for index: int in range(2):
		for key: String in ["scheduled_this_step_kj", "accepted_this_step_kj", "rejected_this_step_kj"]:
			_check(again[index].get(key) == steps[index].get(key), "the run after a reset repeats " + key)


func _identity() -> void:
	_group("G08 identity of the whole content")
	var base: Dictionary = _synthetic(TRIANGLE)
	var reference: String = _fingerprint(base, "base")
	_check(reference.length() == 64 and reference == _fingerprint(base.duplicate(true), "copy"), "identity is a SHA-256 of the content")
	var integers: Dictionary = _synthetic([[0, 0], [10, 100], [20, 0]])
	_check(_fingerprint(integers, "integers") == reference, "integer and float spellings of a number are one content")
	var reordered: Dictionary = {}
	var keys: Array = base.keys()
	keys.reverse()
	for key: String in keys:
		reordered[key] = base[key]
	_check(_fingerprint(reordered, "reordered") == reference, "key order is not content")
	var seen: Dictionary = {reference: "base"}
	var variants: Dictionary = {
		"owner": _changed(base, "owner_id", "synthetic_object_as_tested_2"),
		"run": _changed(base, "run_id", "synthetic_run_2"),
		"negative declaration": _changed(base, "negative_samples", "clipped_to_zero_offline"),
		"value by one bit": _sample(base, 1, "hrr_kw", 100.0 + 100.0 * pow(2.0, -52.0)),
		"time by one bit": _sample(base, 1, "time_s", 10.0 + 10.0 * pow(2.0, -52.0)),
		"first value": _sample(base, 0, "hrr_kw", 0.5),
		"last time": _sample(base, 2, "time_s", 21.0),
		"one sample more": _synthetic([[0.0, 0.0], [10.0, 100.0], [20.0, 0.0], [30.0, 0.0]]),
		"one sample less": _synthetic([[0.0, 0.0], [20.0, 0.0]]),
	}
	for key: String in Source.PROVENANCE_KEYS:
		var value: String = "2".repeat(64) if key in Source.DIGEST_KEYS else "changed " + key
		variants["provenance " + key] = _nested(base, "provenance", key, value)
	_check(100.0 + 100.0 * pow(2.0, -52.0) != 100.0 and 10.0 + 10.0 * pow(2.0, -52.0) != 10.0, "the one-bit variants differ")
	for variant: String in variants:
		var identity: String = _fingerprint(variants[variant], variant)
		_check(identity.length() == 64 and not seen.has(identity), "identity changes with " + variant)
		seen[identity] = variant
	_check(seen.size() == variants.size() + 1, "every variant has its own identity")
	_observations["synthetic_identity"] = reference


# ---------------------------------------------------------------- measured run

func _measured_run() -> void:
	_group("G09 measured run against the exact oracle")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(REAL_FIXTURE))
	if typeof(parsed) != TYPE_DICTIONARY or typeof(parsed.get("source")) != TYPE_DICTIONARY or typeof(parsed.get("oracle")) != TYPE_DICTIONARY:
		_check(false, "measured fixture is readable")
		return
	var source: Dictionary = parsed["source"]
	var oracle: Dictionary = parsed["oracle"]
	var text: String = var_to_str(source)
	# Two parsers read these decimals; they are compared as declared values, not bit by bit.
	_check(is_equal_approx(oracle["numerical_tolerance"]["abs_kj"] / ABS_TOL, 1.0)
		and is_equal_approx(oracle["numerical_tolerance"]["rel"] / REL_TOL, 1.0)
		and Source.ENERGY_ABS_TOL_KJ == ABS_TOL and Source.REL_TOL == REL_TOL, "numerical tolerances are the declared ones")
	var src: RefCounted = _open(source, "measured run")
	var report: Dictionary = src.report()
	_check(report.get("source_fingerprint") == parsed["expected_identity"], "identity equals the one computed offline")
	_check(report.get("owner_id") == "nist_tn2303_stackable_chair_a_as_tested" and report.get("run_id") == "Test016", "owner is the whole object of the run")
	_check(report.get("support_s") == [0.0, 3768.0] and report.get("samples") == 3769, "approved support")
	_check(report.get("negative_samples") == "clipped_to_zero_offline", "negative readings were clipped offline and declared")
	_near(report.get("table_energy_kj"), oracle["total_energy_kj"], "total energy of the table")
	for key: String in Source.UNKNOWN_KEYS:
		_check(report.get("unknown", {}).has(key) and typeof(report["unknown"][key]) == TYPE_NIL, "measured run: " + key + " is null")
	for node: Dictionary in oracle["nodes"]:
		var at_node: Dictionary = src.hrr_kw(node["time_s"])
		_check(_positive(at_node) and at_node.get("hrr_kw") == node["hrr_kw"], "node at " + str(node["time_s"]) + " s")
	for point: Dictionary in oracle["between_nodes"]:
		_value(src, point["time_s"], point["hrr_kw"], "between nodes at " + str(point["time_s"]) + " s")
	_value(src, oracle["peak"]["time_s"], oracle["peak"]["hrr_kw"], "peak")
	for interval: Dictionary in oracle["intervals"]:
		_near(_interval_of(src, interval["start_s"], interval["end_s"]), interval["energy_kj"],
			"interval " + str(interval["start_s"]) + " to " + str(interval["end_s"]) + " s")
	_refused(src.hrr_kw(3768.001), "after Fire Out")
	_refused(src.hrr_kw(-1.0), "before the ignition")
	var campaigns: Dictionary = {}
	for partition: String in ["whole", "minutes", "irregular", "seconds"]:
		campaigns[partition] = {}
		for partial: bool in [false, true]:
			var mode: String = "partial" if partial else "full"
			var tag: String = partition + " " + mode
			var expected: Dictionary = oracle["campaigns"][partition][mode]
			var got: Dictionary = _campaign_on(src, oracle["partitions"][partition], partial, tag)
			_check(got.get("intervals") == int(expected["intervals"]) and got.get("time_s") == expected["end_time_s"], tag + ": every interval counted once")
			_check(got.get("scheduled_kj") == report.get("table_energy_kj"), tag + ": scheduled total is the table, whatever the partition")
			for key: String in ["scheduled_kj", "accepted_kj", "rejected_kj"]:
				_near(got.get(key), expected[key], tag + " " + key)
			_near(got.get("sum_of_steps_kj"), oracle["total_energy_kj"], tag + ": steps add up to the total")
			_near(_float(got.get("accepted_kj")) + _float(got.get("rejected_kj")), _float(got.get("scheduled_kj")), tag + ": accepted plus rejected is scheduled")
			_check(_float(got.get("accepted_kj")) >= 0.0 and _float(got.get("rejected_kj")) >= 0.0, tag + ": no negative counter")
			_refused(src.propose(3769.0), tag + ": nothing after the support")
			campaigns[partition][mode] = got
	_check(var_to_str(source) == text, "the measured source is not modified")
	_observations["measured"] = {"identity": report.get("source_fingerprint"), "table_energy_kj": report.get("table_energy_kj"),
		"peak_kw": src.hrr_kw(oracle["peak"]["time_s"]).get("hrr_kw"), "campaigns": campaigns}


# ---------------------------------------------------------------- helpers

func _campaign(source: Dictionary, ends: Array, partial: bool, label: String) -> Dictionary:
	return _campaign_on(_open(source, label), ends, partial, label)


## Replays one partition from the ignition. Shares follow the declared rule of
## the offline oracle: by interval index modulo 5, all, half, none, a quarter, all.
func _campaign_on(src: RefCounted, ends: Array, partial: bool, label: String) -> Dictionary:
	var restarted: Dictionary = src.reset()
	if not _accepted(restarted):
		_check(false, label + ": reset")
		return {}
	var shares: Array = [1.0, 0.5, 0.0, 0.25, 1.0]
	var total: float = 0.0
	for index: int in range(ends.size()):
		var offer: Dictionary = src.propose(ends[index])
		if not _positive(offer):
			_check(false, label + ": offer " + str(index) + " " + str(offer.get("errors")))
			return {}
		var proposal: Variant = offer.get("proposal")
		if typeof(proposal) != TYPE_DICTIONARY:
			_check(false, label + ": offer " + str(index) + " carries no proposal")
			return {}
		var share: float = shares[index % 5] if partial else 1.0
		var done: Dictionary = src.confirm(proposal, share * _float(proposal.get("energy_kj")))
		if not _accepted(done):
			_check(false, label + ": confirmation " + str(index) + " " + str(done.get("errors")))
			return {}
		total += _float(done.get("scheduled_this_step_kj"))
	_checks += 2 * ends.size()
	var state: Dictionary = src.snapshot()
	return {"intervals": ends.size(), "time_s": state.get("time_s"), "scheduled_kj": state.get("scheduled_kj"),
		"accepted_kj": state.get("accepted_kj"), "rejected_kj": state.get("rejected_kj"), "sum_of_steps_kj": total}


func _open(source: Variant, label: String) -> RefCounted:
	var src: RefCounted = Source.new()
	var opened: Dictionary = src.open(source)
	_check(_accepted(opened) and typeof(opened.get("report")) == TYPE_DICTIONARY, label + ": source opens " + str(opened.get("errors")))
	return src


func _unopened(source: Variant, label: String) -> void:
	var src: RefCounted = Source.new()
	_refused(src.open(source), label)
	_check(src.snapshot() == {} and src.report() == {}, label + ": the owner stays unopened")
	var later: Dictionary = src.propose(1.0)
	_check(typeof(later.get("valid")) == TYPE_BOOL and not later["valid"], label + ": nothing can be proposed")


func _fingerprint(source: Dictionary, label: String) -> String:
	var value: Variant = _open(source, label).report().get("source_fingerprint")
	return value if typeof(value) == TYPE_STRING else ""


func _proposed(src: RefCounted, end: float, label: String) -> Dictionary:
	var offer: Dictionary = src.propose(end)
	_check(_accepted(offer) and typeof(offer.get("proposal")) == TYPE_DICTIONARY, label + ": valid proposal " + str(offer.get("errors")))
	return offer.get("proposal", {}) if typeof(offer.get("proposal")) == TYPE_DICTIONARY else {}


func _advance(src: RefCounted, end: float, share: float, label: String) -> Dictionary:
	var offer: Dictionary = _proposed(src, end, label)
	if offer.is_empty():
		return {}
	var done: Dictionary = src.confirm(offer, share * _float(offer.get("energy_kj")))
	_check(_accepted(done), label + ": confirmed " + str(done.get("errors")))
	return done


## Energy of one interval of a source, on a fresh owner.
func _interval(source: Dictionary, start: float, end: float) -> Variant:
	return _interval_of(_open(source, "interval"), start, end)


func _interval_of(src: RefCounted, start: float, end: float) -> Variant:
	if not _accepted(src.reset()):
		return null
	if start > 0.0 and _advance(src, start, 1.0, "advance to the start").is_empty():
		return null
	return _proposed(src, end, "interval").get("energy_kj")


func _value(src: RefCounted, time_s: Variant, expected: float, label: String) -> void:
	var result: Dictionary = src.hrr_kw(time_s)
	_check(_accepted(result), label + ": value is given " + str(result.get("errors")))
	_near(result.get("hrr_kw"), expected, label)


func _state(src: RefCounted, time_s: float, scheduled: float, accepted: float, rejected: float, generation: int, label: String) -> void:
	var state: Dictionary = src.snapshot()
	_check(state.get("time_s") == time_s and typeof(state.get("generation")) == TYPE_INT and state["generation"] == generation,
		label + ": clock and generation")
	_near(state.get("scheduled_kj"), scheduled, label + ": scheduled")
	_near(state.get("accepted_kj"), accepted, label + ": accepted")
	_near(state.get("rejected_kj"), rejected, label + ": rejected")
	_near(_float(state.get("accepted_kj")) + _float(state.get("rejected_kj")), _float(state.get("scheduled_kj")),
		label + ": accepted plus rejected is scheduled")


func _changed(base: Dictionary, key: String, value: Variant) -> Dictionary:
	var result: Dictionary = base.duplicate(true)
	result[key] = value
	return result


func _nested(base: Dictionary, group: String, key: String, value: Variant) -> Dictionary:
	var result: Dictionary = base.duplicate(true)
	result[group][key] = value
	return result


func _sample(base: Dictionary, index: int, key: String, value: Variant) -> Dictionary:
	var result: Dictionary = base.duplicate(true)
	result["samples"][index][key] = value
	return result


## A number as a float. Anything else is NAN, which no comparison accepts, so a
## missing value becomes a counted failure and never an aborted fixture.
func _float(value: Variant) -> float:
	return float(value) if typeof(value) in [TYPE_FLOAT, TYPE_INT] else NAN


func _positive(result: Variant) -> bool:
	return typeof(result) == TYPE_DICTIONARY and typeof(result.get("valid")) == TYPE_BOOL and result["valid"]


## A positive verdict with no error reported.
func _accepted(result: Variant) -> bool:
	return _positive(result) and typeof(result.get("errors")) == TYPE_ARRAY and result["errors"].is_empty()


## An explicit refusal with its reasons and nothing else.
func _refused(result: Variant, label: String) -> void:
	_check(typeof(result) == TYPE_DICTIONARY and typeof(result.get("valid")) == TYPE_BOOL and not result["valid"],
		label + ": refused explicitly")
	_check(typeof(result) == TYPE_DICTIONARY and typeof(result.get("errors")) == TYPE_ARRAY and not result["errors"].is_empty(),
		label + ": with reasons")
	_check(typeof(result) == TYPE_DICTIONARY and result.size() == 2, label + ": and nothing else")


func _near(actual: Variant, expected: float, label: String) -> void:
	var ok: bool = typeof(actual) == TYPE_FLOAT and not is_nan(actual) and not is_inf(actual)
	_check(ok and absf(actual - expected) <= ABS_TOL + REL_TOL * maxf(absf(actual), absf(expected)), label)


func _group(title: String) -> void:
	_group_name = title.substr(0, 3)
	_groups.append(title)


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failed = true
		_failures.append(_group_name + " " + label)
