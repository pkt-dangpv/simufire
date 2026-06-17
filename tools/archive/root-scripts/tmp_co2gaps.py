import json
with open('sim/validation/reports/reference_checks.json') as f:
    data = json.load(f)
gaps = [c for c in data['checks'] if not c['pass'] and not c.get('required', True)]
co2_gaps = [c for c in gaps if 'co2' in c['name'].lower()]
for c in co2_gaps:
    cid = c['name']
    sv = c.get('actual', None)
    rv = c.get('expected', None)
    tol = c.get('tolerance', None)
    print(cid + ': actual=' + str(round(float(sv),4)) + ' expected=' + str(round(float(rv),4)) + ' tol=' + str(tol))
print('Total CO2 gaps: ' + str(len(co2_gaps)) + ' / Total gaps: ' + str(len(gaps)))
