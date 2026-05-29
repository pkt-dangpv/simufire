import json, math, csv, pathlib, re

cfast_path = pathlib.Path('sim/validation/cfast/cfast_two_room_door_open_compartments.csv')
sf_log = pathlib.Path('sim/validation/reports/cfast_two_room_door_open.log')

cfast_rows = []
with open(cfast_path, newline='') as f:
    reader = csv.DictReader(f)
    for row in reader:
        try:
            t = float(row['Time'])
            temp_upper = float(row['ULT_1'])
            cfast_rows.append({'time_s': t, 'temp_upper_c': temp_upper})
        except (ValueError, KeyError):
            pass

sf_rows = []
ct = -1
for line in sf_log.read_text(encoding='utf-8', errors='replace').splitlines():
    if line.startswith('TIME='):
        try:
            ct = float(line.split('=')[1].split(' ')[0])
        except Exception:
            pass
    elif line.startswith('ROOM 0') and ct >= 0:
        m = re.search(r'Up=([0-9.]+)', line)
        if m:
            sf_rows.append({'time_s': ct, 'temp_upper_c': float(m.group(1))})

def nearest(rows, t):
    return min(rows, key=lambda r: abs(r['time_s'] - t))

errors = []
for c in cfast_rows:
    t = c['time_s']
    s = nearest(sf_rows, t)
    err = s['temp_upper_c'] - c['temp_upper_c']
    errors.append((t, s['temp_upper_c'], c['temp_upper_c'], err))

rmse = math.sqrt(sum(e[3]**2 for e in errors) / len(errors))
print('RMSE: %.4f' % rmse)
print('\nAll timesteps:')
for t, sv, cv, err in errors:
    print('  t=%3.0f  SF=%6.1f  CFAST=%6.1f  err=%+7.1f  sq=%6.0f' % (t, sv, cv, err, err**2))
