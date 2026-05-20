import re, math

path = r"f:\OneDrive\Documentos\GitHub\simufire\sim\validation\reports\cfast_long_burnout_3600s.log"

time_re = re.compile(r"^TIME=([0-9.]+) s")
room_re = re.compile(r"^ROOM 0\([^)]*\) \| (.*)$")

time_s = None
samples = []
for line in open(path, encoding='utf-8', errors='replace'):
    m = time_re.match(line)
    if m:
        try:
            time_s = float(m.group(1))
        except:
            pass
        continue
    m = room_re.match(line)
    if m and time_s is not None:
        sample = {'time_s': time_s}
        for seg in m.group(1).split(' | '):
            if '=' not in seg: continue
            k, v_str = seg.split('=', 1)
            v_val = v_str.split()[0].replace('ppm','').replace('Pa','').replace('%','').replace('m','')
            try: sample[k] = float(v_val)
            except: pass
        samples.append(sample)

# Print specific time points
for t in [60, 120, 180, 210, 240, 300, 360, 600, 900, 1800, 3570]:
    if not samples: break
    best = min(samples, key=lambda x: abs(x['time_s'] - t))
    
    def fmt(val):
        if isinstance(val, (int, float)):
            if abs(val) < 0.0001 and val != 0: return f"{val:.4e}"
            if val == int(val): return f"{int(val)}"
            return f"{val:.1f}" if abs(val) > 0.1 else f"{val:.4f}"
        return str(val)

    print(f"t={best['time_s']:.0f}s: Up={fmt(best.get('Up','?'))}C O2={fmt(best.get('O2','?'))} HRR={fmt(best.get('HRR','?'))}kW P={fmt(best.get('P','?'))}Pa CO2u={fmt(best.get('CO2u','?'))}ppm phase={fmt(best.get('SmokeLayer','?'))}")

if samples:
    print(f"\nTotal samples: {len(samples)}, first t={samples[0]['time_s']}, last t={samples[-1]['time_s']}")
else:
    print("No samples found.")
