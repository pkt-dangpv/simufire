import re

path = r"f:\OneDrive\Documentos\GitHub\simufire\sim\validation\reports\cfast_window_break_t180.log"

time_re = re.compile(r"^TIME=([0-9.]+) s")
room_re = re.compile(r"^ROOM 0\([^)]*\) \| (.*)$")

time_s = None
samples = []
try:
    for line in open(path, encoding="utf-8", errors="replace"):
        m = time_re.match(line)
        if m:
            time_s = float(m.group(1))
            continue
        m = room_re.match(line)
        if m and time_s is not None:
            sample = {"time_s": time_s}
            for seg in m.group(1).split(" | "):
                if "=" not in seg: continue
                k, v = seg.split("=", 1)
                v = v.split()[0].replace("ppm","").replace("Pa","").replace("%","").replace("m","")
                try: sample[k] = float(v)
                except: pass
            samples.append(sample)

    if not samples:
        print("No samples found.")
    else:
        for t in [60, 120, 150, 170, 180, 190, 200, 210, 240, 300, 360, 420, 510, 590]:
            best = min(samples, key=lambda x: abs(x["time_s"] - t))
            print(f"t={best['time_s']:.0f}s: Up={best.get('Up','?'):.1f}C O2={best.get('O2','?'):.4f} HRR={best.get('HRR','?'):.1f}kW P={best.get('P','?'):.1f}Pa")

        print(f"\nTotal samples: {len(samples)}, first={samples[0]['time_s']:.0f}, last={samples[-1]['time_s']:.0f}")
except Exception as e:
    print(f"Error: {e}")
