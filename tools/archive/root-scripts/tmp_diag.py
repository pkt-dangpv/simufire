import json

print("=== TWO-ROOM CO2 UPPER ===")
with open('sim/validation/reports/cfast_two_room_door_open.json') as f:
    rpt = json.load(f)
entries = rpt if isinstance(rpt, list) else rpt.get('log', rpt.get('entries', []))
for e in entries:
    t = e.get('t_s') or e.get('time_s')
    if isinstance(t, (int, float)) and t in [60, 120, 180, 240, 300, 360, 420, 480]:
        r0 = e.get('room_0') or {}
        r1 = e.get('room_1') or {}
        o2_r0 = r0.get('o2', 'N/A')
        o2_r1 = r1.get('o2', 'N/A')
        co2_up = r0.get('co2_upper', 'N/A')
        co2_up_pct = r0.get('co2_upper_pct', 'N/A')
        o2_up = r0.get('o2_upper', 'N/A')
        print(f"t={t:3.0f}: r0.o2={o2_r0} r0.o2_upper={o2_up} r0.co2_upper_pct={co2_up_pct} r1.o2={o2_r1}")

print()
print("=== FO CASE (r0_window_360) CO2 UPPER ===")
with open('sim/validation/reports/cfast_r0_window_360.json') as f:
    rpt = json.load(f)
entries = rpt if isinstance(rpt, list) else rpt.get('log', rpt.get('entries', []))
for e in entries:
    t = e.get('t_s') or e.get('time_s')
    if isinstance(t, (int, float)) and t in [120, 180, 240, 300, 350, 360, 420, 480, 510]:
        r0 = e.get('room_0') or {}
        co2_up_pct = r0.get('co2_upper_pct', 'N/A')
        o2 = r0.get('o2', 'N/A')
        print(f"t={t:3.0f}: r0.o2={o2} r0.co2_upper_pct={co2_up_pct}")

print()
print("=== SINGLE ROOM CLOSED O2 UPPER/LOWER ===")
with open('sim/validation/reports/cfast_single_room_closed.json') as f:
    rpt = json.load(f)
entries = rpt if isinstance(rpt, list) else rpt.get('log', rpt.get('entries', []))
for e in entries:
    t = e.get('t_s') or e.get('time_s')
    if isinstance(t, (int, float)) and t in [60, 120, 180, 210, 300, 360, 420, 450]:
        r0 = e.get('room_0') or {}
        o2 = r0.get('o2', 'N/A')
        o2_lo = r0.get('o2_lower', 'N/A')
        o2_up = r0.get('o2_upper', 'N/A')
        print(f"t={t:3.0f}: r0.o2={o2} r0.o2_upper={o2_up} r0.o2_lower={o2_lo}")
