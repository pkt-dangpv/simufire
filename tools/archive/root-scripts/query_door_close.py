import re

path = r"f:\OneDrive\Documentos\GitHub\simufire\sim\validation\reports\cfast_door_close_midfire.log"

time_re = re.compile(r"^TIME=([0-9.]+) s")
room_re0 = re.compile(r"^ROOM 0\([^)]*\) \| (.*)$")
room_re1 = re.compile(r"^ROOM 1\([^)]*\) \| (.*)$")

time_s = None
samples_r0 = []
samples_r1 = []

def parse_sample(time_s, m):
    sample = {'time_s': time_s}
    for seg in m.group(1).split(' | '):
        if '=' not in seg: continue
        k, v = seg.split('=', 1)
        v = v.split()[0].replace('ppm','').replace('Pa','').replace('%','').replace('m','')
        try: sample[k] = float(v)
        except: pass
    return sample

for line in open(path, encoding='utf-8', errors='replace'):
    m = time_re.match(line)
    if m:
        time_s = float(m.group(1))
        continue
    m = room_re0.match(line)
    if m and time_s is not None:
        samples_r0.append(parse_sample(time_s, m))
        continue
    m = room_re1.match(line)
    if m and time_s is not None:
        samples_r1.append(parse_sample(time_s, m))

print("=== ROOM 0 (fire) ===")
for t in [60, 90, 120, 150, 180, 240, 300, 420, 590]:
    best = min(samples_r0, key=lambda x: abs(x['time_s'] - t))
    print(f"t={best['time_s']:.0f}s: Up={best.get('Up',float('nan')):.1f}C O2={best.get('O2',float('nan')):.4f} HRR={best.get('HRR',float('nan')):.1f}kW P={best.get('P',float('nan')):.2f}Pa CO2u={best.get('CO2u',float('nan')):.0f}ppm")

print()
print("=== ROOM 1 (hall) ===")
for t in [60, 90, 120, 150, 180, 240, 300, 420, 590]:
    best = min(samples_r1, key=lambda x: abs(x['time_s'] - t))
    print(f"t={best['time_s']:.0f}s: Up={best.get('Up',float('nan')):.1f}C O2={best.get('O2',float('nan')):.4f} HRR={best.get('HRR',float('nan')):.1f}kW P={best.get('P',float('nan')):.2f}Pa")

print()
print(f"R0 samples: {len(samples_r0)}, R1 samples: {len(samples_r1)}")
