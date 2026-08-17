# NHANES 2013-2014 - ACB vs polypharmacy and cognition
# python version of the main analysis - mirrors 05_main_analysis.R
#
# the R survey script is the authoritative one, but R isn't installed on this
# machine so this is what actually generated the numbers for the writeup tables.
# uses samplics.SurveyGLM for the design-based (Taylor linearization) regressions
# so the weights + strata + PSU are handled properly, not just plain OLS.
#
# everything associational - recent prescription use vs cross-sectional cognition.
# can't say anything about deprescribing.

import os
import warnings
import numpy as np
import pandas as pd
import pyreadstat

warnings.filterwarnings("ignore")   # samplics is chatty about single-PSU strata

script_dir = os.path.dirname(os.path.abspath(__file__))
base_dir   = os.path.join(script_dir, "..")
data_dir   = os.path.join(base_dir, "data")
out_dir    = os.path.join(base_dir, "outputs", "v2")
os.makedirs(out_dir, exist_ok=True)


# --- 1. load raw files ---
demo, _ = pyreadstat.read_xport(os.path.join(data_dir, "DEMO_H.xpt"), encoding="latin1")
rxq,  _ = pyreadstat.read_xport(os.path.join(data_dir, "RXQ_RX_H.xpt"), encoding="latin1")
cfq,  _ = pyreadstat.read_xport(os.path.join(data_dir, "CFQ_H.xpt"), encoding="latin1")
print(f"loaded: demo={demo.shape[0]}, rxq={rxq.shape[0]}, cfq={cfq.shape[0]}")


# --- 2. ACB scoring (Boustani 2008) ---
acb = pd.read_csv(os.path.join(data_dir, "aas_combined.csv"))
acb_lookup = (
    acb.assign(drug_key=acb["drug"].str.lower().str.strip(),
               acb_score=pd.to_numeric(acb["boustani"], errors="coerce").fillna(0))
    .loc[lambda d: d["drug_key"].notna() & (d["drug_key"] != "")]
    .drop_duplicates("drug_key")
    .set_index("drug_key")["acb_score"]
    .to_dict()
)

rx = rxq[rxq["RXDDRUG"].notna() & (rxq["RXDDRUG"] != "")].copy()
rx["drug_key"]  = rx["RXDDRUG"].str.lower().str.strip()
rx["acb_score"] = rx["drug_key"].map(acb_lookup).fillna(0)
# plain lowercase matching so it undercounts a bit (brand names / combos miss).
# same caveat as the R script - fuzzy matching is a TODO.
print(f"ACB match rate: {(rx['acb_score'] > 0).mean() * 100:.1f}% of {len(rx)} records")

exposure = rx.groupby("SEQN").agg(
    n_drugs=("acb_score", "size"),
    acb_burden=("acb_score", "sum"),
    n_acb_drugs=("acb_score", lambda x: (x > 0).sum()),
    n_highpot=("acb_score", lambda x: (x == 3).sum()),
).reset_index()


# --- 3. optional comorbidity files (Dr Sami item 1) ---
# stroke / diabetes / CVD / depression / self-rated health live in separate
# NHANES files. load each only if it's actually in data/, otherwise leave NA.
# keeps the script runnable with just the 3 core files.
def yn(s):
    # 1=yes, 2=no, anything else (7/9/.) -> NaN
    return s.where(s == 1, other=np.where(s == 2, 0, np.nan)).where(s.isin([1, 2]))

como = pd.DataFrame({"SEQN": demo["SEQN"]})

mcq_path = os.path.join(data_dir, "MCQ_H.xpt")
if os.path.exists(mcq_path):
    mcq, _ = pyreadstat.read_xport(mcq_path, encoding="latin1")
    mcq["stroke"] = yn(mcq["MCQ160F"])
    # CVD = any of CHF / coronary HD / angina / heart attack (stroke kept separate)
    cvd_parts = pd.concat([yn(mcq[c]) for c in ["MCQ160B", "MCQ160C", "MCQ160D", "MCQ160E"]], axis=1)
    mcq["cvd"] = cvd_parts.max(axis=1)
    como = como.merge(mcq[["SEQN", "stroke", "cvd"]], on="SEQN", how="left")
    print("MCQ_H loaded - stroke + CVD")
else:
    como["stroke"] = np.nan; como["cvd"] = np.nan
    print("[skip] MCQ_H.xpt not found - stroke/CVD = NaN")

diq_path = os.path.join(data_dir, "DIQ_H.xpt")
if os.path.exists(diq_path):
    diq, _ = pyreadstat.read_xport(diq_path, encoding="latin1")
    diq["diabetes"] = yn(diq["DIQ010"])   # borderline (3) counts as no
    como = como.merge(diq[["SEQN", "diabetes"]], on="SEQN", how="left")
    print("DIQ_H loaded - diabetes")
else:
    como["diabetes"] = np.nan
    print("[skip] DIQ_H.xpt not found - diabetes = NaN")

dpq_path = os.path.join(data_dir, "DPQ_H.xpt")
if os.path.exists(dpq_path):
    dpq, _ = pyreadstat.read_xport(dpq_path, encoding="latin1")
    items = [f"DPQ0{n}0" for n in range(1, 10)]   # DPQ010..DPQ090
    items = [c for c in items if c in dpq.columns]
    d = dpq[["SEQN"] + items].copy()
    d[items] = d[items].replace({7: np.nan, 9: np.nan})
    d["phq9"] = d[items].sum(axis=1)
    d["depression"] = (d["phq9"] >= 10).astype(float)   # standard PHQ-9 cutoff
    como = como.merge(d[["SEQN", "depression"]], on="SEQN", how="left")
    print("DPQ_H loaded - PHQ-9 depression")
else:
    como["depression"] = np.nan
    print("[skip] DPQ_H.xpt not found - depression = NaN")

hsq_path = os.path.join(data_dir, "HSQ_H.xpt")
if os.path.exists(hsq_path):
    hsq, _ = pyreadstat.read_xport(hsq_path, encoding="latin1")
    # HSD010 1 excellent .. 5 poor. fair/poor (4,5) vs rest.
    hsq["srh_fairpoor"] = np.where(hsq["HSD010"].isin([4, 5]), 1.0,
                          np.where(hsq["HSD010"].isin([1, 2, 3]), 0.0, np.nan))
    como = como.merge(hsq[["SEQN", "srh_fairpoor"]], on="SEQN", how="left")
    print("HSQ_H loaded - self-rated health")
else:
    como["srh_fairpoor"] = np.nan
    print("[skip] HSQ_H.xpt not found - self-rated health = NaN")

health_vars = ["stroke", "cvd", "diabetes", "depression", "srh_fairpoor"]
health_available = [v for v in health_vars if como[v].notna().any()]
print("health covariates available:", health_available or "NONE yet")


# --- 4. person-level frame + covariates ---
df = demo.merge(cfq[["SEQN", "CFDDS", "CFDAST", "CFDCSR"]], on="SEQN", how="left")
df = df.merge(exposure, on="SEQN", how="left")
df = df.merge(como, on="SEQN", how="left")
for c in ["n_drugs", "acb_burden", "n_acb_drugs", "n_highpot"]:
    df[c] = df[c].fillna(0)   # no script record = 0 drugs, not missing

df["age"] = pd.to_numeric(df["RIDAGEYR"], errors="coerce")
df["sex"] = df["RIAGENDR"].map({1: "Male", 2: "Female"})

educ = df["DMDEDUC2"].where(~df["DMDEDUC2"].isin([7, 9]), np.nan)
df["education"] = educ.map({1: "<9th grade", 2: "9-11th grade", 3: "HS grad/GED",
                            4: "Some college/AA", 5: "College grad+"})

df["race"] = df["RIDRETH3"].map({3: "NH White", 1: "Mexican American", 2: "Other Hispanic",
                                 4: "NH Black", 6: "NH Asian", 7: "Other/Multi"})

df["income_pir"] = pd.to_numeric(df["INDFMPIR"], errors="coerce")
df["acb_cat"] = pd.cut(df["acb_burden"], bins=[-np.inf, 0, 2, np.inf],
                       labels=["ACB 0", "ACB 1-2", "ACB 3+"])

df["age60"]       = df["age"] >= 60
df["in_cfq"]      = df["SEQN"].isin(cfq["SEQN"])
df["has_dsst"]    = df["CFDDS"].notna()
df["has_fluency"] = df["CFDAST"].notna()

print("\nACB category counts (60+):")
print(df.loc[df["age60"], "acb_cat"].value_counts(dropna=False))


# --- 4b. sample flow ---
flow = pd.DataFrame({
    "step": ["Full NHANES 2013-2014 (DEMO_H)", "Aged 60+",
             "  ...given cognitive module (in CFQ_H)",
             "  ...with valid DSST (CFDDS)",
             "  ...with valid animal fluency (CFDAST)"],
    "n": [len(df), df["age60"].sum(),
          (df["age60"] & df["in_cfq"]).sum(),
          (df["age60"] & df["has_dsst"]).sum(),
          (df["age60"] & df["has_fluency"]).sum()],
})
flow.to_csv(os.path.join(out_dir, "table_sample_flow.csv"), index=False)
print("\n=== SAMPLE FLOW ===")
print(flow.to_string(index=False))

a = df[df["age60"] & (df["WTMEC2YR"] > 0)].copy()   # analytic subpop


# --- 5. survey-weighted Table 1 (point estimates; design SEs come from R) ---
def wmean(frame, var, w="WTMEC2YR"):
    s = frame[[var, w]].dropna()
    return np.average(s[var], weights=s[w]) if len(s) else np.nan

def wprop(frame, var, w="WTMEC2YR"):
    s = frame[[var, w]].dropna()
    return s.groupby(var)[w].sum() / s[w].sum() * 100

cont_vars = ["age", "income_pir", "n_drugs", "acb_burden", "n_acb_drugs",
             "n_highpot", "CFDDS", "CFDAST"]
t1c = pd.DataFrame({
    "variable": cont_vars,
    "weighted_mean": [round(wmean(a, v), 3) for v in cont_vars],
    "unweighted_mean": [round(a[v].mean(), 3) for v in cont_vars],
    "n_nonmiss": [int(a[v].notna().sum()) for v in cont_vars],
})
t1c.to_csv(os.path.join(out_dir, "table1_continuous.csv"), index=False)

t1cat_rows = []
for v in ["sex", "race", "education", "acb_cat"]:
    for lvl, pct in wprop(a, v).items():
        t1cat_rows.append({"variable": v, "level": lvl,
                           "weighted_pct": round(pct, 2),
                           "n": int((a[v] == lvl).sum())})
pd.DataFrame(t1cat_rows).to_csv(os.path.join(out_dir, "table1_categorical.csv"), index=False)
print("\n=== TABLE 1 (survey-weighted means) ===")
print(t1c.to_string(index=False))


# --- 6. missingness: DSST present vs absent (Dr Sami item 3) ---
from scipy import stats
miss_rows = []
for v in ["age", "n_drugs", "acb_burden", "income_pir"]:
    g0 = a.loc[~a["has_dsst"], v].dropna()
    g1 = a.loc[a["has_dsst"], v].dropna()
    t, p = stats.ttest_ind(g0, g1, equal_var=False)
    miss_rows.append({"variable": v,
                      "mean_DSST_missing": round(g0.mean(), 3),
                      "mean_DSST_present": round(g1.mean(), 3),
                      "p_value_unweighted": round(p, 4)})
miss = pd.DataFrame(miss_rows)
miss.to_csv(os.path.join(out_dir, "missingness_continuous.csv"), index=False)
print("\n=== MISSINGNESS: DSST present vs absent ===")
print(miss.to_string(index=False))
# the missing ones come out older / on more meds / higher ACB -> not random,
# which is why the IPW check below exists.


# --- 7. survey-weighted regression (samplics SurveyGLM) ---
from samplics.regression import SurveyGLM
from samplics.utils.types import ModelType, SinglePSUEst


def survey_lm(frame, outcome, cont_preds, cat_preds, focal, model_name, w="WTMEC2YR"):
    # fit one survey-weighted linear model, return rows for the focal terms only
    needed = [outcome, w, "SDMVSTRA", "SDMVPSU"] + cont_preds + cat_preds
    d = frame[needed].dropna().copy()
    n_used = len(d)

    glm = SurveyGLM(model=ModelType.LINEAR)
    glm.estimate(
        y=d[outcome].to_numpy(float),
        x=d[cont_preds].to_numpy(float) if cont_preds else None,
        x_labels=cont_preds if cont_preds else None,
        x_cat=d[cat_preds] if cat_preds else None,
        x_cat_labels=cat_preds if cat_preds else None,
        samp_weight=d[w].to_numpy(float),
        stratum=d["SDMVSTRA"].to_numpy(),
        psu=d["SDMVPSU"].to_numpy(),
        add_intercept=True,
        single_psu=SinglePSUEst.skip,
        remove_nan=True,
    )
    b = glm.beta
    labels = list(glm.x_labels)

    rows = []
    for f in focal:
        idx = [i for i, lab in enumerate(labels) if lab == f or str(lab).startswith(f + "_")]
        for i in idx:
            rows.append({"model": model_name, "outcome": outcome, "term": labels[i],
                         "estimate": round(float(b["point_est"][i]), 4),
                         "se": round(float(b["stderror"][i]), 4),
                         "ci_lower": round(float(b["lower_ci"][i]), 4),
                         "ci_upper": round(float(b["upper_ci"][i]), 4),
                         "p_value": float(b["p_value"][i]), "n_used": n_used})
    return rows


BASE_CONT = ["age", "income_pir"]
BASE_CAT  = ["sex", "race", "education"]


def run_outcome(frame, outcome):
    out = []
    out += survey_lm(frame, outcome, ["n_drugs"], [], ["n_drugs"], "M1: count alone")
    out += survey_lm(frame, outcome, ["acb_burden"], [], ["acb_burden"], "M2: ACB alone")
    out += survey_lm(frame, outcome, ["acb_burden", "n_drugs"], [],
                     ["acb_burden", "n_drugs"], "M3: ACB + count")
    out += survey_lm(frame, outcome, ["acb_burden", "n_drugs"] + BASE_CONT, BASE_CAT,
                     ["acb_burden", "n_drugs"], "M4: fully adjusted")
    out += survey_lm(frame, outcome, ["n_drugs"] + BASE_CONT, ["acb_cat"] + BASE_CAT,
                     ["acb_cat"], "M5a: ACB category")
    out += survey_lm(frame, outcome, ["n_highpot", "n_drugs"] + BASE_CONT, BASE_CAT,
                     ["n_highpot"], "M5b: high-potency")

    # M4+ fully adjusted + comorbidities, only if those files were loaded.
    # the health flags are 0/1 so feed them in as continuous predictors.
    if health_available:
        out += survey_lm(frame, outcome,
                         ["acb_burden", "n_drugs"] + BASE_CONT + health_available, BASE_CAT,
                         ["acb_burden", "n_drugs"], "M4+: + comorbidities")
    return pd.DataFrame(out)


print("\n=== PRIMARY OUTCOME: DSST (survey-weighted) ===")
dsst = run_outcome(a, "CFDDS")
print(dsst.to_string(index=False))
dsst.to_csv(os.path.join(out_dir, "models_dsst_primary.csv"), index=False)

print("\n=== SECONDARY OUTCOME: animal fluency (survey-weighted) ===")
fluency = run_outcome(a, "CFDAST")
print(fluency.to_string(index=False))
fluency.to_csv(os.path.join(out_dir, "models_fluency_secondary.csv"), index=False)


# --- 8. IPW sensitivity for informative DSST missingness (Dr Sami item 3) ---
# reweight responders by 1/P(has DSST). if acb_burden barely moves vs M4 then
# the complete-case result holds up. (multiple imputation would be the heavier
# alternative - leaving that as a next step.)
import statsmodels.formula.api as smf

ipw_cov = ["age", "income_pir", "acb_burden", "n_drugs", "sex", "race", "education"]
ipw_df = a.dropna(subset=ipw_cov).copy()
resp_mod = smf.logit(
    "has_dsst ~ age + income_pir + acb_burden + n_drugs + C(sex) + C(race) + C(education)",
    data=ipw_df.assign(has_dsst=ipw_df["has_dsst"].astype(int))
).fit(disp=False)
ipw_df["phat"] = resp_mod.predict(ipw_df)
# combined weight = base MEC weight * 1/phat, responders only
ipw_df["ipw_w"] = ipw_df["WTMEC2YR"] * (1.0 / ipw_df["phat"])
resp = ipw_df[ipw_df["has_dsst"] & np.isfinite(ipw_df["ipw_w"])].copy()

ipw_rows = survey_lm(resp, "CFDDS", ["acb_burden", "n_drugs"] + BASE_CONT, BASE_CAT,
                     ["acb_burden", "n_drugs"], "M4-IPW: DSST", w="ipw_w")
ipw = pd.DataFrame(ipw_rows)
ipw.to_csv(os.path.join(out_dir, "models_dsst_ipw.csv"), index=False)
print("\n=== IPW-WEIGHTED DSST (compare acb_burden to M4) ===")
print(ipw.to_string(index=False))


# --- 9. stroke-exclusion sensitivity (Dr Sami item 2) ---
if "stroke" in health_available:
    print("\nrunning stroke-exclusion sensitivity...")
    ns = a[(a["stroke"] == 0) | (a["stroke"].isna())].copy()
    sens_rows = survey_lm(ns, "CFDDS", ["acb_burden", "n_drugs"] + BASE_CONT, BASE_CAT,
                          ["acb_burden", "n_drugs"], "M6: exclude stroke")
    sens = pd.DataFrame(sens_rows)
    sens.to_csv(os.path.join(out_dir, "models_dsst_exclude_stroke.csv"), index=False)
    print(sens.to_string(index=False))
else:
    print("\n[skip] no stroke variable (MCQ_H.xpt not loaded) - "
          "download it to run the stroke-exclusion sensitivity.")


# --- 10. save cleaned analytic dataset (60+) ---
clean_cols = ["SEQN", "age", "sex", "race", "education", "income_pir",
              "n_drugs", "acb_burden", "acb_cat", "n_acb_drugs", "n_highpot",
              "stroke", "cvd", "diabetes", "depression", "srh_fairpoor",
              "CFDDS", "CFDAST", "CFDCSR", "WTMEC2YR", "SDMVPSU", "SDMVSTRA",
              "has_dsst", "has_fluency"]
clean_cols = [c for c in clean_cols if c in df.columns]
df[df["age60"]][clean_cols].to_csv(
    os.path.join(out_dir, "analysis_dataset_clean.csv"), index=False)

print(f"\ndone. outputs in {os.path.abspath(out_dir)}")
