import os
import warnings
import numpy as np
import pandas as pd
import statsmodels.formula.api as smf

# regression models - cognition (OLS) + mortality (Cox phreg)
# this is the early UNWEIGHTED version. the proper survey-weighted analysis is
# in 05_main_analysis - use that for the writeup. keeping this for the Cox part.

warnings.filterwarnings("ignore")


def prepare_data(df):
    data = df.copy()

    num_cols = ["RIDAGEYR", "acb_burden", "n_drugs", "CFDDS", "CFDAST",
                "MORTSTAT", "follow_up_years", "DMDEDUC2", "RIAGENDR"]
    for c in num_cols:
        data[c] = pd.to_numeric(data[c], errors="coerce")

    data["sex"] = data["RIAGENDR"].map({1: "Male", 2: "Female"})   # 1=M 2=F
    # 7/9 in DMDEDUC2 are refused / dont know, not real education levels
    data["education"] = data["DMDEDUC2"].where(~data["DMDEDUC2"].isin([7, 9]), np.nan)
    return data


def run_lm_model(data, formula, model_name, outcome, focal_predictors):
    needed = [outcome, "RIDAGEYR", "sex", "education", *focal_predictors]
    model_df = data[needed].dropna().copy()   # complete case

    fit = smf.ols(formula=formula, data=model_df).fit()
    ci = fit.conf_int(alpha=0.05)

    rows = []
    for pred in focal_predictors:
        if pred in fit.params.index:
            rows.append({
                "model": model_name,
                "outcome": outcome,
                "predictor": pred,
                "coefficient": float(fit.params[pred]),
                "ci_lower": float(ci.loc[pred, 0]),
                "ci_upper": float(ci.loc[pred, 1]),
                "p_value": float(fit.pvalues[pred]),
                "n_used": int(len(model_df)),
            })
    return pd.DataFrame(rows)


def run_cox_model(data, formula, model_name, focal_predictors):
    needed = ["follow_up_years", "MORTSTAT", "RIDAGEYR", "sex", "education", *focal_predictors]
    model_df = data[needed].dropna().copy()
    # need positive follow-up and a clean 0/1 status for phreg
    model_df = model_df[(model_df["follow_up_years"] > 0) & (model_df["MORTSTAT"].isin([0, 1]))]

    status = model_df["MORTSTAT"].astype(int)
    # phreg formula = duration ~ predictors, censoring passed via status
    fit = smf.phreg(formula=formula, data=model_df, status=status).fit(disp=False)

    params = np.asarray(fit.params)
    pvals  = np.asarray(fit.pvalues)
    ci_log = np.asarray(fit.conf_int())

    # exog_names lines up with params - fall back to generic names if it doesn't
    param_names = list(getattr(fit.model, "exog_names", []))
    if len(param_names) != len(params):
        param_names = [f"param_{i}" for i in range(len(params))]

    rows = []
    for pred in focal_predictors:
        if pred in param_names:
            i = param_names.index(pred)
            rows.append({
                "model": model_name,
                "predictor": pred,
                "hazard_ratio": float(np.exp(params[i])),   # HR = exp(coef)
                "ci_lower": float(np.exp(ci_log[i, 0])),
                "ci_upper": float(np.exp(ci_log[i, 1])),
                "p_value": float(pvals[i]),
                "n_used": int(len(model_df)),
                "events": int(status.sum()),
            })
    return pd.DataFrame(rows)


def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    base_dir = os.path.join(script_dir, "..")

    input_path    = os.path.join(base_dir, "outputs", "analysis_dataset_with_mortality.csv")
    cognitive_out = os.path.join(base_dir, "outputs", "cognitive_models_results.csv")
    cox_out       = os.path.join(base_dir, "outputs", "mortality_cox_results.csv")

    df = pd.read_csv(input_path)
    df = prepare_data(df)
    print(f"loaded {len(df)} rows")

    # cognitive: ACB only / drug count only / both, for DSST then fluency
    cognitive_frames = [
        run_lm_model(df, "CFDDS ~ acb_burden + RIDAGEYR + C(sex) + C(education)",
                     "ACB only", "CFDDS", ["acb_burden"]),
        run_lm_model(df, "CFDDS ~ n_drugs + RIDAGEYR + C(sex) + C(education)",
                     "Drug count only", "CFDDS", ["n_drugs"]),
        run_lm_model(df, "CFDDS ~ acb_burden + n_drugs + RIDAGEYR + C(sex) + C(education)",
                     "Both together", "CFDDS", ["acb_burden", "n_drugs"]),
        run_lm_model(df, "CFDAST ~ acb_burden + RIDAGEYR + C(sex) + C(education)",
                     "ACB only", "CFDAST", ["acb_burden"]),
        run_lm_model(df, "CFDAST ~ n_drugs + RIDAGEYR + C(sex) + C(education)",
                     "Drug count only", "CFDAST", ["n_drugs"]),
        run_lm_model(df, "CFDAST ~ acb_burden + n_drugs + RIDAGEYR + C(sex) + C(education)",
                     "Both together", "CFDAST", ["acb_burden", "n_drugs"]),
    ]
    cognitive_results = pd.concat(cognitive_frames, ignore_index=True)
    cognitive_results.to_csv(cognitive_out, index=False)

    # mortality Cox
    cox_frames = [
        run_cox_model(df, "follow_up_years ~ acb_burden + RIDAGEYR + C(sex) + C(education)",
                      "ACB only", ["acb_burden"]),
        run_cox_model(df, "follow_up_years ~ n_drugs + RIDAGEYR + C(sex) + C(education)",
                      "Drug count only", ["n_drugs"]),
        run_cox_model(df, "follow_up_years ~ acb_burden + n_drugs + RIDAGEYR + C(sex) + C(education)",
                      "Both together", ["acb_burden", "n_drugs"]),
    ]
    cox_results = pd.concat(cox_frames, ignore_index=True)
    cox_results.to_csv(cox_out, index=False)

    print("saved:", cognitive_out)
    print("saved:", cox_out)
    print("cognitive rows:", len(cognitive_results), " mortality rows:", len(cox_results))


if __name__ == "__main__":
    main()
