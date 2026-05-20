import csv

def read_cfast(path):
    with open(path) as f:
        reader = csv.reader(f)
        rows = list(reader)
    headers = rows[0]
    # Skip rows 1-3 (metadata), then data starts at row 4
    data = []
    for row in rows[4:]:
        try:
            data.append([float(x) if x.strip() else None for x in row])
        except:
            pass
    return headers, data

for sc in ["cfast_long_burnout_3600s", "cfast_window_break_t180", "cfast_door_close_midfire"]:
    path = f"f:/OneDrive/Documentos/GitHub/simufire/sim/validation/cfast/{sc}_compartments.csv"
    try:
        headers, data = read_cfast(path)
        print(f"\n=== {sc} ===")
        print(f"Columns: {headers[:15]}")
        # Print all rows at key times: 0, 120, 180, 300, 420, 600, 900, 1800, 3600
        key_times = [0, 60, 120, 180, 240, 300, 420, 600, 900, 1800, 3570]
        last_t = -100
        for row in data:
            t = row[0]
            if any(abs(t - kt) < 1 for kt in key_times):
                if abs(t - last_t) < 0.5: continue
                last_t = t
                # Print time + key fields (ULT_1=upper temp, LLT_1=lower temp, HGT_1=height, HRR_1, LLO2_1, ULO2_1, PRS_1)
                idx = {h: i for i,h in enumerate(headers)}
                fields = ['Time', 'ULT_1', 'LLT_1', 'HGT_1', 'HRR_1', 'LLCO_1', 'ULCO2_1', 'LLO2_1', 'PRS_1', 'ULT_2', 'LLT_2', 'LLO2_2']
                vals = {k: (row[idx[k]] if k in idx else None) for k in fields}
                print(f"  t={t:.0f}: " + ", ".join(f"{k}={v:.2f}" for k,v in vals.items() if v is not None))
    except Exception as e:
        print(f"Error processing {sc}: {e}")
