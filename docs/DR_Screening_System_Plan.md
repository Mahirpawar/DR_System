# Explainable AI for Diabetic Retinopathy Screening — System Plan

**Problem Statement Owner:** MathWorks | **Theme:** MedTech / HealthTech
**Target:** Working MATLAB/Simulink prototype, validated on public benchmarks

---

## 1. Problem Recap (one paragraph)

Build a fundus-image analysis pipeline that screens for Diabetic Retinopathy in rural India, where portable cameras produce variable-quality images and there is ~1 ophthalmologist per 100,000 people. The system must grade DR severity (ICDR 0–4) at >90% sensitivity / >85% specificity for referable DR (grade 2+), explain every decision well enough for a doctor to sign off in under 30 seconds, and model a Simulink workflow that plans staffing/bandwidth for screening 100,000+ patients/year.

---

## 2. System Architecture

```
Raw Fundus Image
      │
      ▼
[1] Image Quality Assessment ──reject──> Recapture Feedback Loop
      │ pass/enhance
      ▼
[2] Preprocessing & Enhancement (CLAHE, denoise, illumination norm)
      │
      ▼
[3] Structure Segmentation
      ├── Optic Disc / Fovea localization
      ├── Vessel segmentation
      ├── Microaneurysm detection
      ├── Exudate segmentation
      ├── Hemorrhage classification
      └── Neovascularization detection
      │
      ▼
[4] Severity Grading (fusion model)
      ├── Path A: End-to-end CNN (transfer learning)
      └── Path B: Lesion-count rule/SVM from Stage 3
      → Fused, calibrated ICDR grade (0–4)
      │
      ▼
[5] Explainability Module
      ├── Grad-CAM overlay anchored to lesion masks
      ├── Confidence calibration (Platt/temperature scaling)
      └── Auto-generated annotated report
      │
      ▼
Ophthalmologist Review (<30s) — Accept / Override
      │
      ▼
[6] Simulink Workflow Model (parallel track)
      Acquisition rate → Bandwidth → AI processing → Review capacity
      → Resource allocation recommendation for district program
```

---

## 3. Module-by-Module Plan

### Module 1 — Image Quality Assessment (IQA)
| Item | Detail |
|---|---|
| Inputs | Raw fundus image (any resolution) |
| Metrics | Laplacian variance (focus), histogram spread (illumination), vessel-visibility ratio in periphery (field of view) |
| Classifier | Rule-based thresholds first; optional lightweight CNN trained on EyeQ/DeepDRiD quality labels if time allows |
| Outputs | `good` / `borderline` / `ungradeable` + specific reason code |
| Toolbox | Image Processing Toolbox |
| MVP scope | Rule-based thresholding is enough to demo; CNN quality classifier is a stretch goal |

### Module 2 — Enhancement
| Item | Detail |
|---|---|
| Techniques | CLAHE on L-channel (Lab space), adaptive gamma correction, non-local-means denoising |
| Trigger | Only applied to `borderline` images |
| Toolbox | Image Processing Toolbox |

### Module 3 — Structure Segmentation
| Structure | Method | Dataset for training/testing |
|---|---|---|
| Optic disc / fovea | CNN + anatomical prior (fovea ≈ 2.5 disc-diameters temporal to disc) | IDRiD (has OD/fovea coordinates) |
| Vessels | U-Net (Deep Learning Toolbox) + Gabor matched-filter baseline for comparison | DRIVE |
| Microaneurysms | Top-hat morphology + Radon transform candidates → small CNN classifier | IDRiD (pixel-level lesion masks) |
| Exudates | Color+texture threshold or segmentation net, hard vs. soft classification | IDRiD |
| Hemorrhages | Segmentation + shape classifier | IDRiD |
| Neovascularization | Vessel tortuosity/caliber irregularity features → classifier | IDRiD (limited positives — flag as known limitation) |
| Toolbox | Image Processing Toolbox, Computer Vision Toolbox, Deep Learning Toolbox |

### Module 4 — Severity Grading
| Item | Detail |
|---|---|
| Path A | Transfer-learned CNN (e.g., ResNet/EfficientNet import) trained on combined APTOS + Messidor-2 + IDRiD |
| Path B | Lesion-count-based rule/SVM using Module 3 outputs |
| Fusion | Calibrated logistic layer combining both paths |
| Primary metric | Sensitivity/specificity for **binary referable-DR (grade ≥2)** — this is the number the problem statement scores you on |
| Secondary metric | 5-class ICDR accuracy / quadratic weighted kappa (standard for APTOS) |
| Toolbox | Deep Learning Toolbox, Statistics and Machine Learning Toolbox |

### Module 5 — Explainability
| Item | Detail |
|---|---|
| Visual explanation | Grad-CAM from CNN path, overlaid with actual lesion segmentation masks (not just heatmap alone) |
| Confidence calibration | Platt scaling or temperature scaling so confidence score reflects true empirical accuracy |
| Report | Single-screen layout: annotated image + lesion table + ICDR grade + confidence + referral flag |
| Success criterion | Ophthalmologist (or proxy reviewer) can accept/override in <30 seconds — test this with a simple timed UI walkthrough |
| Toolbox | Deep Learning Toolbox, Statistics and Machine Learning Toolbox |

### Module 6 — Simulink Workflow Simulation
| Item | Detail |
|---|---|
| Model type | Discrete-event / queueing simulation |
| Inputs | Image acquisition rate (camera throughput), bandwidth constraint (image transfer to central hub), AI processing latency per image, ophthalmologist review rate |
| Output | Resource allocation recommendation, e.g. "X cameras + Y reviewing ophthalmologists needed to screen 100,000 patients/year within a 2-week referral SLA" |
| Toolbox | Simulink, Statistics and Machine Learning Toolbox |
| Why it matters | This is the piece that turns the project from "a classifier" into "a deployable program plan" — don't skip it |

---

## 4. Datasets

| Dataset | Use | Link |
|---|---|---|
| APTOS 2019 | Severity grading (5-class, image-level labels) | kaggle.com/c/aptos2019-blindness-detection |
| IDRiD | Lesion-level ground truth (MA, exudates, hemorrhages), OD/fovea coordinates | ieeedataport.org (Indian Diabetic Retinopathy Image Dataset) |
| DRIVE | Vessel segmentation ground truth | drive.grand-challenge.org |
| Messidor-2 | Cross-dataset validation for grading | adcis.net/en/third-party/messidor2 |

**Split strategy:** Train/validate lesion detectors and grading model on IDRiD + Messidor-2 (lesion-level ground truth available). Test cross-dataset generalization on APTOS. This directly supports the "validated against published benchmarks" requirement.

---

## 5. Build Timeline (suggested, adjust to your actual deadline)

| Phase | Tasks | Approx. effort |
|---|---|---|
| Phase 0 — Setup | Get datasets, set up MATLAB toolboxes, define file structure | 0.5 day |
| Phase 1 — IQA + Enhancement | Rule-based quality scoring, CLAHE/denoise pipeline | 1 day |
| Phase 2 — Segmentation | Vessel U-Net on DRIVE, OD/fovea localization, MA/exudate/hemorrhage detectors on IDRiD | 3–4 days |
| Phase 3 — Grading | Transfer-learned CNN on APTOS+Messidor-2, lesion-rule classifier, fusion layer | 2–3 days |
| Phase 4 — Explainability | Grad-CAM, calibration, report generator | 1–2 days |
| Phase 5 — Simulink model | Build queueing model, define one concrete 100k-patient scenario | 1–2 days |
| Phase 6 — Validation & benchmarking | Cross-dataset testing, compute sensitivity/specificity, compare fused vs. single-technique | 1–2 days |
| Phase 7 — Packaging | Report, demo script, README, limitations section | 1 day |

**Total: ~10–15 working days** for a solo/small-team prototype. Compress by parallelizing segmentation and grading work if team size allows.

---

## 6. Validation Plan (how you prove it works)

1. **Referable DR detection** — report sensitivity, specificity, ROC-AUC on held-out IDRiD/Messidor-2 test split. Target: >90% sensitivity, >85% specificity.
2. **Cross-dataset generalization** — train on IDRiD+Messidor-2, test on APTOS (or vice versa) to show the model isn't overfit to one imaging device/population.
3. **Ablation study** — compare (a) CNN-only grading, (b) lesion-rule-only grading, (c) fused pipeline. This is your direct evidence for "integrated pipeline outperforms any single technique."
4. **Explainability usefulness** — qualitative: show 5–10 Grad-CAM examples correctly highlighting actual lesion regions (cross-check against IDRiD lesion masks). Quantitative if time allows: IoU between Grad-CAM high-attention region and ground-truth lesion mask.
5. **Review time proxy** — time how long it takes a reviewer (even non-ophthalmologist) to accept/override a report using your generated UI; target <30s.
6. **Simulink scenario output** — produce one concrete staffing/bandwidth number for a stated patient volume, and sanity-check it against real district population figures.

---

## 7. Honest Scoping — What's Achievable vs. What to Flag as Limitation

### Fully achievable in prototype timeframe
- IQA + enhancement
- Vessel segmentation (DRIVE is a mature, well-benchmarked task)
- CNN-based severity grading hitting target sensitivity/specificity (published work already clears these numbers on these exact datasets)
- Grad-CAM explainability
- Simulink queueing/resource model

### Hard — scope down and state explicitly as limitations
- **Sub-pixel microaneurysm detection**: even published research shows modest scores here; don't claim SOTA, show a reasonable detector and note the limitation.
- **Neovascularization detection**: too few positive examples in public datasets for a robust classifier; propose as future work needing PDR-specific data.
- **Real field validation**: you're validating on curated benchmark datasets, not actual rural camera captures. State this directly — "validated on public benchmarks; field validation with portable cameras is future work" — rather than implying deployment-grade robustness.
- **Beating published SOTA**: achievable to show fusion beats single-technique *within your own pipeline*; don't claim to beat external papers unless you literally reproduce their numbers for comparison.

---

## 8. Deliverables Checklist

- [ ] MATLAB scripts/functions for all 5 pipeline modules
- [ ] Trained models (vessel U-Net, MA/exudate/hemorrhage detectors, grading CNN) with saved weights
- [ ] Simulink model file (.slx) with at least one documented scenario run
- [ ] Validation report: sensitivity/specificity table, ablation study, cross-dataset results
- [ ] Sample Grad-CAM explainability outputs (5–10 annotated examples)
- [ ] Auto-generated sample report (the doctor-facing single-screen output)
- [ ] README with setup instructions, toolbox dependencies, and how to reproduce results
- [ ] Limitations section (see Section 7) included in final writeup — this strengthens credibility rather than weakening it

---

## 9. Answer to "Can it be achieved?"

**Yes, as a validated prototype demonstrating the full pipeline on public benchmark data — not as a clinically deployed, field-proven product.** Every module maps to mature, well-documented MATLAB toolbox capabilities and established public datasets; the sensitivity/specificity targets are realistic given published baselines on these same datasets. The two genuinely research-grade challenges (sub-pixel MA detection, neovascularization detection with scarce data) should be built to a reasonable standard and explicitly flagged as limitations rather than oversold — this is normal practice even in published clinical AI work and will read as rigor, not weakness.
