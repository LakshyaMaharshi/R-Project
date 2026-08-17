# reference/

This folder is intentionally empty in the repository.

`08_extract_iacb.py` reads the IACB drug list from the preprint

> Fleetwood, K. et al. (2021). *Anticholinergic burden and cognition.*
> SSRN preprint 3777231 — https://papers.ssrn.com/abstract=3777231

The PDF is not redistributed here because it is the authors' copyright. To
re-run the extraction, download it from SSRN and save it in this folder as
`ssrn-3777231 (1).pdf`.

You do not need to. The extracted list is already supplied as
`../data/iacb_scores.csv` (205 drugs), and every script in the pipeline reads
that file rather than the PDF. `08_extract_iacb.py` is included only so the
extraction is auditable.

The BIO-7057X assessment brief also lived here and is likewise not included,
being a University of East Anglia course document.
