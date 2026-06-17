import json

for f in ['f25','f50','f75','f100']:
    d = json.load(open(f'sim/validation/reports/cfast_post_flashover_vented_p2i_{f}.json'))
    snap = d['metrics'].get('snapshot_at', [])
    for s in snap:
        t = s.get('t', 0)
        if abs(t - 240) < 5 or abs(t - 350) < 5:
            co2 = s.get('co2_upper_pct', 'N/A')
            print(f'p2i_{f} t={t}: co2_upper_pct={co2}')
