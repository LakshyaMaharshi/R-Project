import pandas as pd
import pyreadstat
import os
import sys

script_dir = os.path.dirname(os.path.abspath(__file__))
# Which cycle to explore. Matches config.R / 00_download_data.py:
#   python 02_acb_mapping.py                 -> 2013-2014
#   python 02_acb_mapping.py 2011-2012       -> the validation cycle
CYCLES = {"2013-2014": "_H", "2011-2012": "_G"}
cycle = sys.argv[1] if len(sys.argv) > 1 else "2013-2014"
if cycle not in CYCLES:
    sys.exit(f"unknown cycle {cycle!r} - known: {', '.join(CYCLES)}")
sfx = CYCLES[cycle]
data_dir = os.path.join(script_dir, '..', 'data', cycle)
scales_dir = os.path.join(script_dir, '..', 'data', 'scales')
print(f"cycle {cycle} (suffix {sfx})")

demo, _ = pyreadstat.read_xport(os.path.join(data_dir, f'DEMO{sfx}.xpt'), encoding='latin1')
rxq,  _ = pyreadstat.read_xport(os.path.join(data_dir, f'RXQ_RX{sfx}.xpt'), encoding='latin1')
cfq,  _ = pyreadstat.read_xport(os.path.join(data_dir, f'CFQ{sfx}.xpt'), encoding='latin1')

# anticholinergic burden scale - using Boustani (2008)
# aas_combined.csv has drug names + scores from the literature
acb = pd.read_csv(os.path.join(scales_dir, 'aas_combined.csv'))
print(f"ACB reference list: {len(acb)} drugs")
print(acb.head())  # check it loaded right

# build lookup dict - lowercase everything so matching works
acb_dict = dict(zip(
    acb['drug'].str.lower().str.strip(),
    acb['boustani'].fillna(0)
))

# drop rows where drug name is missing or blank
# had issues with this before - empty strings caused weird matches
rxq = rxq[rxq['RXDDRUG'].notna() & (rxq['RXDDRUG'] != '')].copy()
rxq['drug_lower'] = rxq['RXDDRUG'].str.lower().str.strip()
rxq['acb_score']  = rxq['drug_lower'].map(acb_dict).fillna(0)

# how many drugs actually matched the ACB list?
n_matched = (rxq['acb_score'] > 0).sum()
print(f"\nmatched {n_matched} / {len(rxq)} drug records to ACB list ({n_matched/len(rxq)*100:.1f}%)")

# tried using ADS scale instead but Boustani seemed more commonly cited
# acb_dict2 = dict(zip(acb['drug'].str.lower().str.strip(), acb['ads'].fillna(0)))

# sum up burden score per person
burden = rxq.groupby('SEQN').agg(
    acb_burden  = ('acb_score', 'sum'),
    n_drugs     = ('acb_score', 'count'),
    n_acb_drugs = ('acb_score', lambda x: (x > 0).sum())
).reset_index()

print(f"\nburden summary:")
print(burden['acb_burden'].describe())  # sanity check the distribution looks reasonable

# filter to 60+ and merge with cognitive scores
demo_60 = demo[demo['RIDAGEYR'] >= 60].copy()

# inner join - only keep people who completed cognitive testing
merged = demo_60.merge(cfq[['SEQN', 'CFDDS', 'CFDAST', 'CFDCSR']], on='SEQN', how='inner')
merged = merged.merge(burden, on='SEQN', how='left')

# fill in 0 for people with no prescription records at all
merged['acb_burden']  = merged['acb_burden'].fillna(0)
merged['n_drugs']     = merged['n_drugs'].fillna(0)
merged['n_acb_drugs'] = merged['n_acb_drugs'].fillna(0)

print(f"\nAnalytic sample (60+ with cognitive scores): {len(merged)}")
print(f"Mean ACB burden: {merged['acb_burden'].mean():.2f}")
print(f"Taking any anticholinergic: {(merged['acb_burden']>0).sum()} ({(merged['acb_burden']>0).mean()*100:.1f}%)")
print(f"High burden (score >= 3): {(merged['acb_burden']>=3).sum()}")
print(f"Mean DSST score: {merged['CFDDS'].mean():.1f}")

# TODO: maybe add categorical burden variable here (none/low/high) before saving
# would make the regression tables cleaner

# exploratory scratch output - not used by the pipeline, and gitignored.
# The real results are written per cycle by the R scripts.
out_dir = os.path.join(script_dir, '..', 'outputs', cycle)
os.makedirs(out_dir, exist_ok=True)
merged.to_csv(os.path.join(out_dir, 'exploratory_analysis_dataset.csv'), index=False)
print(f"Saved: outputs/{cycle}/exploratory_analysis_dataset.csv")
