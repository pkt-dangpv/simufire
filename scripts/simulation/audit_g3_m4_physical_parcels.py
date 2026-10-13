"""Independent M4-P1 receipt auditor; never proposes or calls the GD model.

Inputs are imposed synthetic physical gas and O2 masses, not live-engine
parcels, verified flow laws, complete chemistry or exposure concentrations.
"""

import math


BASIS = "physical_gas_mass_v1"
ZONES = ("upper", "lower")
ROOM_FIELDS = {"m_upper", "m_lower", "E_upper", "E_lower", "O_total", "O_upper"}
BOOK_FIELDS = {"generation", "step", "revision", "reference_temp_k", "basis", "rooms", "seen"}
EVENT_FIELDS = {"id", "cause", "generation", "step", "revision", "basis", "expected_rooms", "packets", "heat"}
PACKET_FIELDS = {"id", "kind", "source", "target", "gas_kg", "boundary"}


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def number(value, name, nonnegative=True):
    require(type(value) in (int, float), name + " type")
    try:
        valid = math.isfinite(value) and (not nonnegative or value >= 0)
    except OverflowError:
        valid = False
    require(valid, name + " range")
    return value


def text(value):
    return type(value) is str and bool(value.strip())


def schema(value, fields):
    require(type(value) is dict and set(value) == fields, "schema")


def oxygen(room, zone):
    return room["O_upper"] if zone == "upper" else room["O_total"] - room["O_upper"]


def validate_book(book):
    schema(book, BOOK_FIELDS)
    for name in ("generation", "step", "revision"):
        require(type(book[name]) is int and book[name] >= 0, "context")
    require(book["basis"] == BASIS, "basis")
    require(number(book["reference_temp_k"], "reference") > 0, "reference")
    require(type(book["rooms"]) is dict and book["rooms"], "rooms")
    require(type(book["seen"]) is list and all(text(x) for x in book["seen"]), "seen")
    require(len(book["seen"]) == len(set(book["seen"])), "seen duplicate")
    for name, room in book["rooms"].items():
        require(text(name), "room name")
        schema(room, ROOM_FIELDS)
        for key in ROOM_FIELDS:
            number(room[key], key)
        for zone in ZONES:
            mass, e, o = room["m_" + zone], room["E_" + zone], oxygen(room, zone)
            require(0 <= o <= mass, "physical oxygen capacity")
            require(mass != 0 or (e == 0 and o == 0), "absent zone")
        number(room["m_upper"] + room["m_lower"], "gas sum")
        number(room["E_upper"] + room["E_lower"], "energy sum")


def endpoint(value, book):
    schema(value, {"room", "zone"})
    require(text(value["room"]) and value["room"] in book["rooms"], "endpoint room")
    require(value["zone"] in ZONES, "endpoint zone")
    return value["room"], value["zone"]


def near(actual, expected, name, tol=1e-9):
    number(actual, name, False)
    number(expected, name, False)
    require(abs(actual - expected) <= tol, name)


def audit_receipt(receipt):
    schema(receipt, {"before", "after", "event", "parcels", "deltas"})
    before, after, event = (receipt[k] for k in ("before", "after", "event"))
    validate_book(before)
    validate_book(after)
    schema(event, EVENT_FIELDS)
    require(text(event["id"]) and text(event["cause"]), "event names")
    require(event["basis"] == BASIS and event["expected_rooms"] == before["rooms"], "snapshot/base")
    for key in ("generation", "step", "revision"):
        require(type(event[key]) is int and event[key] == before[key], "event context")
    require(event["id"] not in before["seen"], "replayed event")
    require(after["seen"] == before["seen"] + [event["id"]], "applied identities")
    require(after["revision"] == before["revision"] + 1, "revision")
    for key in ("generation", "step", "reference_temp_k", "basis"):
        require(after[key] == before[key], "changed context/reference")
    require(set(after["rooms"]) == set(before["rooms"]), "participants")
    require(type(event["packets"]) is list and type(event["heat"]) is list, "actions")
    require(event["packets"] or event["heat"], "empty event")
    require(type(receipt["parcels"]) is list, "parcels")
    require(len(event["packets"]) == len(receipt["parcels"]), "parcel coverage")
    fields = ("mass", "oxygen", "energy", "donated_mass", "donated_oxygen", "donated_energy")
    changes = {r: {z: dict.fromkeys(fields, 0.) for z in ZONES} for r in before["rooms"]}
    ids = set()
    for packet, carried in zip(event["packets"], receipt["parcels"], strict=True):
        schema(packet, PACKET_FIELDS)
        schema(carried, {"id", "kind", "source", "target", "gas_kg", "oxygen_kg", "energy_kj"})
        require(text(packet["id"]) and packet["id"] not in ids, "contribution duplicate")
        ids.add(packet["id"])
        source, target, kind = (packet[k] for k in ("source", "target", "kind"))
        require(kind in ("transfer", "boundary_in", "boundary_out"), "kind")
        require((source is None) == (kind == "boundary_in"), "source kind")
        require((target is None) == (kind == "boundary_out"), "target kind")
        require(kind != "transfer" or source != target, "self parcel")
        for key in ("id", "kind", "source", "target", "gas_kg"):
            require(carried[key] == packet[key], "parcel provenance")
        q = number(packet["gas_kg"], "q")
        if source is None:
            schema(packet["boundary"], {"Y", "e_kj_kg"})
            y = number(packet["boundary"]["Y"], "outside Y")
            require(y <= 1, "outside capacity")
            e = number(packet["boundary"]["e_kj_kg"], "outside e")
        else:
            require(packet["boundary"] is None, "unexpected boundary")
            r, z = endpoint(source, before)
            room = before["rooms"][r]
            gas = room["m_" + z]
            require(gas > 0 or q == 0, "absent donor")
            y = oxygen(room, z) / gas if gas else 0.
            e = room["E_" + z] / gas if gas else 0.
        o, energy = q * y, q * e
        near(carried["oxygen_kg"], o, "parcel donor oxygen")
        near(carried["energy_kj"], energy, "parcel donor energy", 1e-6)
        for end, sign in ((source, -1), (target, 1)):
            if end is None:
                continue
            r, z = endpoint(end, before)
            delta = changes[r][z]
            for field, amount in zip(("mass", "oxygen", "energy"), (q, o, energy), strict=True):
                delta[field] += sign * amount
                if sign == -1:
                    delta["donated_" + field] += amount
    for heat in event["heat"]:
        schema(heat, {"id", "target", "energy_kj"})
        require(text(heat["id"]) and heat["id"] not in ids, "heat duplicate")
        ids.add(heat["id"])
        r, z = endpoint(heat["target"], before)
        e = number(heat["energy_kj"], "heat", False)
        changes[r][z]["energy"] += e
        changes[r][z]["donated_energy"] += max(0., -e)
    schema(receipt["deltas"], set(before["rooms"]))
    for r, zones in changes.items():
        schema(receipt["deltas"][r], set(ZONES))
        for z, delta in zones.items():
            schema(receipt["deltas"][r][z], set(fields))
            prev, new = before["rooms"][r], after["rooms"][r]
            require(delta["donated_mass"] <= prev["m_" + z], "gross gas")
            require(delta["donated_oxygen"] <= oxygen(prev, z), "gross oxygen")
            require(delta["donated_energy"] <= prev["E_" + z], "gross energy")
            for field in fields:
                near(receipt["deltas"][r][z][field], delta[field], "recorded " + field,
                     1e-6 if "energy" in field else 1e-9)
            near(new["m_" + z] - prev["m_" + z], delta["mass"], "gas change")
            near(oxygen(new, z) - oxygen(prev, z), delta["oxygen"], "oxygen change")
            near(new["E_" + z] - prev["E_" + z], delta["energy"], "energy change", 1e-6)
    return {"rooms": len(changes), "parcels": len(event["packets"]),
            "physical_flow_validation": False, "coupled_engine": False}


def audit_payload(payload):
    require(type(payload.get("checks")) is int and payload["checks"] > 1000, "positive checks")
    require(payload.get("iterations") == 256 and payload.get("failures") == []
            and payload.get("failure_count") == 0, "fixture completion")
    samples = payload.get("samples")
    names = {"plume", "heat only", "door", "in", "out", "zero", "collapse", "reverse", "birth", "rich no ceiling"}
    require(type(samples) is list and len(samples) == len(names), "sample count")
    require({s.get("name") for s in samples} == names, "sample coverage")
    for sample in samples:
        audit_receipt(sample["receipt"])
        observed = sample["observables"]
        require(observed.get("valid") is True and observed.get("units") == "oxygen_mass_fraction", "units")
        after = sample["receipt"]["after"]
        schema(observed["rooms"], set(after["rooms"]))
        for r, room in after["rooms"].items():
            schema(observed["rooms"][r], set(ZONES))
            for z in ZONES:
                if room["m_" + z] == 0:
                    require(observed["rooms"][r][z] is None, "absent observable")
                else:
                    near(observed["rooms"][r][z], oxygen(room, z) / room["m_" + z], "observable")
    return {"samples": len(samples), "independent_audit": True, "engine_integration": False}
