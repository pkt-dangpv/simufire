import re, pathlib

log_dir = pathlib.Path("f:/OneDrive/Documentos/GitHub/simufire/sim/validation/reports")

for log_name, room_id, times in [
    ("cfast_r0_window_360.log", 0, [60, 120, 180, 240, 360, 420, 510]),
    ("cfast_single_room_closed.log", 0, [60, 120, 180, 210, 240]),
    ("cfast_two_room_door_open.log", 0, [120, 180, 240, 300, 450]),
    ("cfast_two_room_door_open.log", 1, [240, 360]),
]:
    log_path = log_dir / log_name
    if not log_path.exists():
        print(f"MISSING: {log_name}")
        continue
    
    time_s = None
    room_data = {}
    time_re = re.compile(r"^TIME=([0-9.]+) s")
    room_re = re.compile(rf"^ROOM {room_id}\([^)]*\) \| (.*)$")
    
    for line in log_path.read_text(encoding="utf-8", errors="replace").splitlines():
        m = time_re.match(line)
        if m:
            time_s = float(m.group(1))
            continue
        m = room_re.match(line)
        if m and time_s is not None:
            room_data[time_s] = m.group(1)
    
    print(f"\n{log_name} room={room_id}:")
    for t in times:
        if not room_data:
            break
        best_t = min(room_data.keys(), key=lambda x: abs(x - t))
        seg = room_data[best_t]
        o2 = re.search(r'\bO2=([0-9.]+)', seg)
        o2u = re.search(r'\bO2u=([0-9.]+)', seg)
        hrr = re.search(r'\bHRR=([0-9.]+)', seg)
        print(f"  t={t:4.0f}s (actual={best_t:.0f}): O2={o2.group(1) if o2 else 'N/A':7s} O2u={o2u.group(1) if o2u else 'N/A':7s} HRR={hrr.group(1) if hrr else 'N/A':7s}kW")
