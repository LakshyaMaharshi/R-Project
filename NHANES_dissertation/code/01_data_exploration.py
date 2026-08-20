import pandas as pd
import pyreadstat
import os
import sys

script_dir = os.path.dirname(os.path.abspath(__file__))
# Which cycle to explore. Matches config.R / 00_download_data.py:
#   python 01_data_exploration.py                 -> 2013-2014
#   python 01_data_exploration.py 2011-2012       -> the validation cycle
CYCLES = {"2013-2014": "_H", "2011-2012": "_G"}
cycle = sys.argv[1] if len(sys.argv) > 1 else "2013-2014"
if cycle not in CYCLES:
    sys.exit(f"unknown cycle {cycle!r} - known: {', '.join(CYCLES)}")
sfx = CYCLES[cycle]
data_dir = os.path.join(script_dir, '..', 'data', cycle)
scales_dir = os.path.join(script_dir, '..', 'data', 'scales')
print(f"cycle {cycle} (suffix {sfx})")

# load the 3 NHANES files - took a while to figure out read_xport needs encoding
demo, demo_meta = pyreadstat.read_xport(os.path.join(data_dir, f'DEMO{sfx}.xpt'), encoding='latin1')
rxq, rxq_meta   = pyreadstat.read_xport(os.path.join(data_dir, f'RXQ_RX{sfx}.xpt'), encoding='latin1')
cfq, cfq_meta   = pyreadstat.read_xport(os.path.join(data_dir, f'CFQ{sfx}.xpt'), encoding='latin1')

print(f"loaded: demo={demo.shape}, rxq={rxq.shape}, cfq={cfq.shape}")


# --- DEMOGRAPHICS ---
print("\n=== DEMOGRAPHICS (DEMO) ===")
print(f"n = {demo.shape[0]:,}")
print(f"variables: {demo.shape[1]}")

# print all variable labels so i know what im working with
for col in demo.columns:
    lbl = demo_meta.column_names_to_labels.get(col, '')
    print(f"  {col}: {lbl}")

print(demo.head(3))

# RIDAGEYR = age in years - this is the main filter variable
print(f"\nmean age: {demo['RIDAGEYR'].mean():.1f}")
print(f"range: {demo['RIDAGEYR'].min()} - {demo['RIDAGEYR'].max()}")

n_60plus = (demo['RIDAGEYR'] >= 60).sum()
print(f"aged 60+: {n_60plus} ({n_60plus / len(demo) * 100:.1f}%)")


# --- MEDICATIONS ---
print("\n=== MEDICATIONS (RXQ_RX) ===")
# note: this is one row per drug, not per person
print(f"total records: {rxq.shape[0]:,}")
print(f"unique people: {rxq['SEQN'].nunique():,}")

for col in rxq.columns:
    lbl = rxq_meta.column_names_to_labels.get(col, '')
    print(f"  {col}: {lbl}")

print(rxq.head(3))

# quick check of most common drugs - useful context
print("\ntop drugs (by frequency):")
print(rxq['RXDDRUG'].value_counts().head(15))

# how many drugs per person on average
# rxq already has RXDCOUNT but calculating manually to double check
drugs_per_person = rxq.groupby('SEQN')['RXDDRUG'].count()
print(f"\nmean drugs per person: {drugs_per_person.mean():.2f}")
print(f"max: {drugs_per_person.max()}")


# --- COGNITIVE FUNCTION ---
print("\n=== COGNITIVE FUNCTION (CFQ) ===")
print(f"n = {cfq.shape[0]:,}")  # much smaller - only subset got tested

for col in cfq.columns:
    lbl = cfq_meta.column_names_to_labels.get(col, '')
    print(f"  {col}: {lbl}")

print(cfq.head(3))

# CFDDS = digit symbol substitution test (main outcome probably)
# CFDAST = animal fluency, CFDCSR = delayed word recall
print(f"\nCFDDS (digit symbol):   mean={cfq['CFDDS'].mean():.1f},  missing={cfq['CFDDS'].isna().sum()}")
print(f"CFDAST (animal fluency): mean={cfq['CFDAST'].mean():.1f}, missing={cfq['CFDAST'].isna().sum()}")
print(f"CFDCSR (word recall):    mean={cfq['CFDCSR'].mean():.1f}, missing={cfq['CFDCSR'].isna().sum()}")


# --- OVERLAP / MERGE CHECK ---
print("\n=== OVERLAP CHECK ===")
# how many age 60+ have cognitive scores - this is the actual analytic sample
demo_old = demo[demo['RIDAGEYR'] >= 60]
merged_check = demo_old.merge(cfq[['SEQN', 'CFDDS']], on='SEQN', how='inner')
print(f"age 60+ with cognitive data: {len(merged_check)}")

# sanity check - all these should also have med records
# TODO: double check this is actually true after the full merge
rxq_ids = set(rxq['SEQN'].unique())
overlap = merged_check['SEQN'].isin(rxq_ids).sum()
print(f"of those, have medication records: {overlap}")
print(f"missing medication records: {len(merged_check) - overlap}")

print("\ndone - look at above to understand the datasets before running 02")
