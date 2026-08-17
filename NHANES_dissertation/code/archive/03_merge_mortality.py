import os
import glob
import pandas as pd

# merge the NHANES linked mortality file onto the analysis dataset.
# the mortality file is a fixed-width .dat (no header), so it needs manual
# parsing - the public-use layout PDF has the column positions.
# this took ages to get right, the spacing on the right side is annoying.


def parse_mortality_dat(file_path):
    # parse one NHANES linked mortality public .dat file into a dataframe.
    # front fields are fixed width, but the follow-up months on the right have
    # variable spacing so i split those on whitespace instead of slicing.
    records = []

    with open(file_path, "r", encoding="latin1") as handle:
        for raw_line in handle:
            line = raw_line.rstrip("\r\n")
            if not line:
                continue

            seqn_raw = line[0:14].strip()
            elig_raw = line[14:15].strip()
            mort_raw = line[15:16].strip()

            # follow-up months are off in the right tail, spacing varies
            tail = line[42:].strip() if len(line) >= 43 else ""
            toks = tail.split()
            permth_exm_raw = toks[0] if len(toks) >= 1 else ""
            permth_int_raw = toks[1] if len(toks) >= 2 else ""

            records.append({
                "SEQN": seqn_raw,
                "ELIGSTAT": elig_raw,
                "MORTSTAT": mort_raw,
                "PERMTH_EXM": permth_exm_raw,
                "PERMTH_INT": permth_int_raw,
            })

    mort = pd.DataFrame(records)

    # '.' is the missing marker in these files
    for col in ["SEQN", "ELIGSTAT", "MORTSTAT", "PERMTH_EXM", "PERMTH_INT"]:
        mort[col] = pd.to_numeric(mort[col].replace(".", pd.NA), errors="coerce")

    return mort


def select_best_mortality_file(data_dir, analysis_seqn):
    # i had a few mortality .dat files lying around from different cycles and
    # wasn't sure which one matched 2013-2014. so just pick whichever overlaps
    # the most SEQNs with the analysis sample. bit hacky but works.
    pattern = os.path.join(data_dir, "NHANES_*_MORT_2019_PUBLIC.dat")
    candidates = sorted(glob.glob(pattern))
    if not candidates:
        raise FileNotFoundError(f"no mortality .dat files found in: {data_dir}")

    analysis_seqn_set = set(analysis_seqn.dropna().astype(int).tolist())

    best_path = None
    best_overlap = -1
    best_df = None

    print("mortality file overlap scan:")
    for path in candidates:
        mort = parse_mortality_dat(path)
        mort_eligible = mort[mort["ELIGSTAT"] == 1].copy()   # only mortality-eligible
        mort_seqn_set = set(mort_eligible["SEQN"].dropna().astype(int).tolist())
        overlap = len(analysis_seqn_set & mort_seqn_set)

        print(f"  {os.path.basename(path)} -> overlap {overlap:,}")

        if overlap > best_overlap:
            best_overlap = overlap
            best_path = path
            best_df = mort_eligible

    if best_overlap <= 0 or best_df is None or best_path is None:
        raise ValueError("no overlap with any mortality file - wrong NHANES cycle?")

    print(f"selected: {os.path.basename(best_path)} (overlap {best_overlap:,})")
    best_df = best_df.drop_duplicates(subset=["SEQN"])
    return best_path, best_df


def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    base_dir = os.path.join(script_dir, "..")

    analysis_path = os.path.join(base_dir, "outputs", "analysis_dataset.csv")
    data_dir      = os.path.join(base_dir, "data")
    output_path   = os.path.join(base_dir, "outputs", "analysis_dataset_with_mortality.csv")

    analysis = pd.read_csv(analysis_path)
    analysis["SEQN"] = pd.to_numeric(analysis["SEQN"], errors="coerce")

    mortality_path, mortality = select_best_mortality_file(data_dir, analysis["SEQN"])

    merged = analysis.merge(
        mortality[["SEQN", "MORTSTAT", "PERMTH_EXM", "PERMTH_INT"]],
        on="SEQN", how="left",
    )

    merged["follow_up_years"] = merged["PERMTH_EXM"] / 12.0   # months -> years
    merged["MORTSTAT"] = merged["MORTSTAT"].astype("Int64")

    # QC - make sure the merge didn't drop rows or do something weird
    print("=== merge QC ===")
    print(f"rows before merge: {len(analysis):,}")
    print(f"rows after merge:  {len(merged):,}")   # should be the same (left join)
    print(f"mortality source: {os.path.basename(mortality_path)}")

    missing_mort  = merged["MORTSTAT"].isna().sum()
    death_count   = (merged["MORTSTAT"] == 1).sum()
    matched_count = merged["MORTSTAT"].notna().sum()

    print(f"matched mortality records: {matched_count:,} / {len(merged):,}")
    print(f"missing MORTSTAT: {missing_mort:,}")
    print(f"deaths in sample (MORTSTAT=1): {death_count:,}")

    follow_up = merged["follow_up_years"].dropna()
    if len(follow_up) > 0:
        print("follow-up years:")
        print(f"  n: {len(follow_up):,}  mean: {follow_up.mean():.2f}  "
              f"median: {follow_up.median():.2f}  max: {follow_up.max():.2f}")
    else:
        print("follow-up years: no non-missing values (something's off)")

    merged.to_csv(output_path, index=False)
    print(f"saved: {output_path}")


if __name__ == "__main__":
    main()
