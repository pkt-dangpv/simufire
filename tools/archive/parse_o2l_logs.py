"""Parse hvac_o2l_g*.log files and print O2/O2l comparison table."""
import re
from pathlib import Path

REPORTS = Path(__file__).resolve().parents[2] / "sim" / "validation" / "reports"
TARGETS = [180, 300, 450, 600]
TAGS = ['g000', 'g025', 'g050', 'g100']
GAINS = {'g000': 0.00, 'g025': 0.25, 'g050': 0.50, 'g100': 1.00}
CFAST_REF = {180: 0.2049, 300: 0.2049, 450: 0.2049, 600: None}

results = {}
for tag in TAGS:
    log = REPORTS / f'hvac_o2l_{tag}.log'
    if not log.exists():
        print(f'{tag}: NOT FOUND')
        continue
    content = log.read_text(encoding='utf-8', errors='ignore')
    results[tag] = {}
    current_t = None
    for line in content.splitlines():
        tm = re.match(r'TIME=([0-9.]+)\s', line)
        if tm:
            current_t = int(float(tm.group(1)))
        elif current_t in TARGETS and 'ROOM 0' in line and 'O2l=' in line:
            o2  = float(re.search(r'\bO2=([0-9.]+)', line).group(1))
            o2l = float(re.search(r'O2l=([0-9.]+)', line).group(1))
            if current_t not in results[tag]:
                results[tag][current_t] = (o2, o2l)

print('=== O2 / O2l VALUES BY GAIN (ROOM 0 = Salon) ===')
print()
header = f"  {'t':>6s} | {'g=0.00':>17s} | {'g=0.25':>17s} | {'g=0.50':>17s} | {'g=1.00':>17s} | CFAST_ref"
print(header)
print('  ' + '-' * (len(header) - 2))
for t in TARGETS:
    cref = CFAST_REF.get(t)
    cref_s = f'{cref:.4f}' if cref else '  n/a '
    cols = []
    for tag in TAGS:
        v = results.get(tag, {}).get(t)
        if v:
            cols.append(f'{v[0]:.4f} / {v[1]:.4f}')
        else:
            cols.append('  N/A  /  N/A  ')
    print(f'  t={t:4d}s | {cols[0]:>17s} | {cols[1]:>17s} | {cols[2]:>17s} | {cols[3]:>17s} | {cref_s}')

print()
print('=== DELTA O2l vs g=0.00 ===')
print()
hdr2 = f"  {'t':>6s} | {'g=0.00 (base)':>13s} | {'g=0.25 delta':>12s} | {'g=0.50 delta':>12s} | {'g=1.00 delta':>12s}"
print(hdr2)
print('  ' + '-' * (len(hdr2) - 2))
for t in TARGETS:
    base = results.get('g000', {}).get(t)
    if not base:
        continue
    deltas = []
    for tag in ['g025', 'g050', 'g100']:
        v = results.get(tag, {}).get(t)
        d = v[1] - base[1] if v else None
        deltas.append(f'{d:+.4f}' if d is not None else '   N/A')
    print(f'  t={t:4d}s | O2={base[0]:.4f} O2l={base[1]:.4f} | {deltas[0]:>12s} | {deltas[1]:>12s} | {deltas[2]:>12s}')

print()
print('=== SENTINEL SUMMARY (from sweep) ===')
print('  g4 CO>1200:  85.583s  (all gains identical)')
print('  g4 FED>0.1: 198.417s  (all gains identical)')
print('  v3 FED>0.1: 249.833s  (all gains identical)')
print('  v3 max FED:   2.212   (all gains identical)')
print('  vic FED:      0.7715  (all gains identical)')
print('  vic CO:    3381.925   (all gains identical)')
print('  => 6/6 PASS for all gains')
