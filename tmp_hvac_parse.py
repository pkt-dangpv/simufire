import re
lines = open('f:/OneDrive/Documentos/GitHub/simufire/sim/validation/reports/cfast_hvac_residential.log', encoding='utf-8', errors='ignore').readlines()
current_t = 0
room0_entries = []
for L in lines:
    tm = re.search(r'TIME=(\d+(?:\.\d+)?)', L)
    if tm:
        current_t = float(tm.group(1))
    if 'ROOM 0' in L:
        room0_entries.append((current_t, L.rstrip()))

print(f"Total Room 0 entries: {len(room0_entries)}")
print("\nAll entries:")
for t, entry in room0_entries:
    hrr = re.search(r'HRR=(\S+)', entry)
    up = re.search(r'Up=(\S+)', entry)
    o2 = re.search(r'\| O2=(\S+)', entry)
    print(f"  t={t}: HRR={hrr.group(1) if hrr else '?'}, Up={up.group(1) if up else '?'}, O2={o2.group(1) if o2 else '?'}")
