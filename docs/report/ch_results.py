"""Chapter 4 (Results), Chapter 5 (Conclusion), Appendix, Bibliography, Biodata."""
from content import chapter, h2, h3, fig, ph, tab, P, unnumbered, ME

REFS = [
    'H. H. Mohammed, G. Kiss, J. A. Serrano, and F. Lindseth, “Agentic health analytics for personalized insights from '
    'wearable data,” in *Proc. 18th Int. Conf. Agents and Artificial Intelligence (ICAART)*, Marbella, Spain, vol. 3, '
    'pp. 2050–2061, 2026.',
    'M. A. Merrill *et al.*, “Transforming wearable data into personal health insights using large language model '
    'agents,” *Nature Communications*, vol. 17, Art. no. 1143, 2026.',
    'Z. Lu, M. Abbasian, and A. M. Rahmani, “Query-conditioned graph retrieval for contextualized LLM reasoning in '
    'personalized wearable data,” arXiv:2605.18763, 2026.',
    'W. Zhang *et al.*, “RubricsTree: Scalable and evolving open-ended evaluation of personal health agents across '
    'health memory and medical skills,” arXiv:2606.18203, 2026.',
    'P. Saha *et al.*, “Picking the right specialist: Attentive neural process-based selection of task-specialized '
    'models as tools for agentic healthcare systems,” arXiv:2602.14901, 2026.',
    'S. Yao *et al.*, “ReAct: Synergizing reasoning and acting in language models,” in *Proc. Int. Conf. Learning '
    'Representations (ICLR)*, 2023.',
    'P. Manakul, A. Liusie, and M. J. F. Gales, “SelfCheckGPT: Zero-resource black-box hallucination detection for '
    'generative large language models,” in *Proc. Conf. Empirical Methods in Natural Language Processing (EMNLP)*, '
    'pp. 9004–9017, 2023.',
    'A. Madaan *et al.*, “Self-Refine: Iterative refinement with self-feedback,” in *Advances in Neural Information '
    'Processing Systems (NeurIPS)*, vol. 36, 2023.',
    'S. Ateia and U. Kruschwitz, “Can language models critique themselves? Investigating self-feedback for retrieval '
    'augmented generation at BioASQ 2025,” in *CLEF 2025 Working Notes (BioASQ Lab)*, 2025.',
    'Z. Fu, F. Li, J. Gu, H. Wang, P. Nakov, B. Hooi, M.-Y. Kan, and J. Wu, “Better with experience: Self-evolving LLM '
    'agents for evidence-grounded health community notes,” arXiv:2606.02215, 2026.',
    'S. Deandrea, E. Lucenteforte, F. Bravi, R. Foschi, C. La Vecchia, and E. Negri, “Risk factors for falls in '
    'community-dwelling older people: A systematic review and meta-analysis,” *Epidemiology*, vol. 21, no. 5, '
    'pp. 658–668, 2010.',
    'J. M. Hausdorff, D. A. Rios, and H. K. Edelberg, “Gait variability and fall risk in community-living older adults: '
    'A 1-year prospective study,” *Arch. Phys. Med. Rehabil.*, vol. 82, no. 8, pp. 1050–1056, 2001.',
    'A. Mol, P. T. Bui Hoang, S. Sharmin, E. M. Reijnierse, R. J. van Wezel, C. G. Meskers, and A. B. Maier, '
    '“Orthostatic hypotension and falls in older adults: A systematic review and meta-analysis,” *J. Am. Med. Dir. '
    'Assoc.*, vol. 20, no. 5, pp. 589–597, 2019, doi: 10.1016/j.jamda.2018.11.003.',
    'J. Baker, M. Hood, L. Swanson, C. Kline, K. Ylitalo, J. Cauley, R. Green, and C. Karvonen-Gutierrez, “Sleep '
    'quality and duration and risk of falls in older adult women: The Study of Women’s Health Across the Nation '
    '(SWAN),” *Innovation in Aging*, vol. 8, suppl. 1, p. 112, 2024, doi: 10.1093/geroni/igae098.0360.',
    'T. Mishra *et al.*, “Pre-symptomatic detection of COVID-19 from smartwatch data,” *Nature Biomedical '
    'Engineering*, vol. 4, no. 12, pp. 1208–1220, 2020.',
    'E. Alzueta *et al.*, “Tracking sleep, temperature, heart rate, and daily symptoms across the menstrual cycle with '
    'the Oura ring in healthy women,” *Int. J. Women’s Health*, vol. 14, pp. 491–503, 2022, '
    'doi: 10.2147/IJWH.S341917.',
    'E. de Jager, B. Caulfield, E. Angelidi, B. MacNamee, and S. Holden, “Wearable-derived heart rate variability '
    'across the menstrual cycle, hormonal contraceptive use, and reproductive life stages in females: A living '
    'systematic review,” *Sports Medicine*, vol. 56, no. 5, pp. 1153–1173, 2026, doi: 10.1007/s40279-025-02388-y.',
    'A. Askhatova *et al.*, “A temporal convolutional network approach for gait-based fall risk prediction to support '
    'safe sport participation in older adults,” *MethodsX*, vol. 16, Art. no. 103845, 2026, '
    'doi: 10.1016/j.mex.2026.103845.',
    'A. Weiss, M. Brozgol, M. Dorfman, T. Herman, S. Shema, N. Giladi, and J. M. Hausdorff, “Does the evaluation of gait '
    'quality during daily life provide insight into fall risk? A novel approach using 3-day accelerometer recordings,” '
    '*Neurorehabil. Neural Repair*, vol. 27, no. 8, pp. 742–752, 2013.',
    'J. McCamley, M. Donati, E. Grimpampi, and C. Mazzà, “An enhanced estimate of initial contact and final contact '
    'instants of time using lower trunk inertial sensor data,” *Gait & Posture*, vol. 36, no. 2, pp. 316–318, 2012.',
    'R. Moe-Nilssen and J. L. Helbostad, “Estimation of gait cycle characteristics by trunk accelerometry,” *J. '
    'Biomechanics*, vol. 37, no. 1, pp. 121–126, 2004.',
    'D. Drover, J. Howcroft, J. Kofman, and E. D. Lemaire, “Faller classification in older adults using wearable '
    'sensors based on turn and straight-walking accelerometer-based features,” *Sensors*, vol. 17, no. 6, Art. no. '
    '1321, 2017.',
    'J. M. Hausdorff, “Long Term Movement Monitoring Database (LTMM), version 1.0.0,” PhysioNet, '
    'doi: 10.13026/C2S59C.',
]


def write(w):
    # ── CHAPTER 4 ────────────────────────────────────────────────────────────
    chapter(w, 4, 'Implementation, Results and Discussion')
    h2(w, '4.1', 'Implementation Overview')
    P(w,
      'All parts of the system described in Chapter 3 were implemented. Table 4.1 lists the main components and how '
      'each was verified. The application was reduced to the three sections required by the project (Home, AI Assist '
      'and Fall Risk); unrelated features of the earlier prototype, as well as emergency SMS and automatic calling, '
      'were removed, which shrank the Dart code base from about 63,000 to 39,000 lines.')
    tab(w, '4.1', 'Implemented components and their verification',
        ['Component', 'Implementation', 'Verification'],
        [
            ['Ring data acquisition', 'Kotlin BLE plugin, adaptive measurement loop, Room store', 'Running on the team’s ring and phone'],
            ['Cloud storage', 'Supabase tables, 5-minute batched sync', 'Data visible in the Supabase dashboard'],
            ['Fall-risk engine', 'agent/fall_risk.py', 'Unit tests; contributions sum to the score'],
            ['Gait pipeline v1–v3', 'agent/gait_features.py, agent/daily_gait.py', 'Synthetic benchmark; LTMM Experiments 1–3'],
            ['Agent (Version D)', 'Router, safety fusion, grounded generation, self-verification', '11-scenario evaluation; unit tests'],
            ['Application UI', 'Home, AI Assist, Fall Risk and score-explanation pages', 'Widget tests at small widths and large text'],
            ['Build pipeline', 'GitHub Actions: analyse, test, build APK', 'Green build; installable APK'],
        ], [3.6, 6.4, 5.6], size=9.5)
    h2(w, '4.2', 'Evidence-Derived Layer Weights')
    P(w,
      'Applying Equation (3.6) to the published effect sizes gives the weights in Figure 4.1. Fall history receives '
      'the largest weight (0.402), followed by motion (0.290), physiology (0.214) and recovery (0.093). The ordering '
      'matches clinical experience — a previous fall is the strongest single predictor of the next — and was obtained '
      'without fitting any parameter to our own data.')
    fig(w, '4.1', 'evidence_weights.png', 'Evidence-derived layer weights, λ ∝ ln(published risk ratio)', 12)
    h2(w, '4.3', 'Fall-Risk Engine on the Demonstration Cohort')
    P(w,
      'Table 4.2 shows the scores of the five demonstration users on the evaluation date, and Table 4.3 their layer '
      'risks and top contributors. Every user falls in the expected tier. Lakshmi, with three falls in the past year '
      'and two recent near-falls, is HIGH (71); fall history alone contributes 40.2 points. Meera is MODERATE (47), '
      'driven by one past fall and poor recovery. Ravi’s newest data is four days old, so his score is flagged as '
      'stale and his confidence drops to 70%. For the two luteal-phase users the cycle-aware baseline lowers the score '
      '(Meera 48 → 47, Priya 6 → 4).')
    tab(w, '4.2', 'Fall Risk Scores of the demonstration cohort',
        ['User', 'FRS', 'Tier', 'Q', 'Stale', 'Cycle phase', 'FRS without cycle correction'],
        [
            ['Arun (low risk)', '6', 'LOW', '100', 'No', '—', '—'],
            ['Meera (luteal + poor recovery)', '47', 'MODERATE', '100', 'No', 'Luteal', '48'],
            ['Ravi (stale data)', '3', 'LOW', '70', 'Yes', '—', '—'],
            ['Lakshmi (recent fall)', '71', 'HIGH', '100', 'No', '—', '—'],
            ['Priya (healthy luteal)', '4', 'LOW', '100', 'No', 'Luteal', '6'],
        ], [4.0, 1.2, 2.6, 2.0, 1.3, 1.9, 3.0], size=9,
        align=['left', 'center', 'center', 'center', 'center', 'center', 'center'])
    tab(w, '4.3', 'Layer risks (0–100) and top contributors (points)',
        ['User', 'P', 'RC', 'MO', 'FH', 'Top contributors'],
        [
            ['Arun', '5.0', '0.1', '18.0', '0.0', 'daily steps +5.2, SpO₂ +1.1'],
            ['Meera', '61.7', '100.0', '0.0', '60.0', 'falls in past year +24.1, HRV +7.5, resting HR +4.6, sleep duration +3.7'],
            ['Ravi', '6.2', '12.6', '0.0', '0.0', 'HRV +1.3, sleep duration +1.2'],
            ['Lakshmi', '42.3', '52.0', '59.5', '100.0', 'falls in past year +40.2, near-falls +14.5, SpO₂ +5.4, HRV +3.7'],
            ['Priya', '11.7', '12.5', '0.0', '0.0', 'HRV +2.5, sleep score +0.8, sleep duration +0.4'],
        ], [2.0, 1.3, 1.3, 1.3, 1.3, 8.6], size=9, align=['left', 'center', 'center', 'center', 'center', 'left'])
    fig(w, '4.2', 'fall_risk_trend.png', '21-day Fall Risk Score trajectory of each demonstration user', 14)
    fig(w, '4.3', 'contribution_breakdown.png', 'Additive attribution: contributions sum exactly to the score', 15)
    h2(w, '4.4', 'Cycle-Aware Baseline Ablation')
    P(w,
      'Table 4.4 and Figure 4.4 compare the physiology-layer risk with and without the cycle-aware baseline on the '
      'normal luteal days of the two cycle users. For Priya, the healthy user, the mean physiology risk on nine luteal '
      'days fell from 18.1 to 10.2, a reduction of 43.4%. For Meera, the strained user, it fell from 19.3 to 11.5 and '
      'the number of falsely flagged days dropped from two to zero. Importantly, the correction did not hide genuine '
      'strain: Meera’s last three days, when her recovery really deteriorated, remained high (63, 60 and 62). One of '
      'Priya’s days remained flagged with and without the correction, which we report as it is.')
    tab(w, '4.4', 'Physiology-layer risk on normal luteal days, with and without the cycle-aware baseline',
        ['User', 'Luteal days', 'Mean risk without', 'Mean risk with', 'Reduction', 'Flagged without', 'Flagged with'],
        [
            ['Priya (healthy)', '9', '18.1', '10.2', '43.4%', '1', '1'],
            ['Meera (strained)', '5', '19.3', '11.5', '40.4%', '2', '0'],
        ], [3.0, 1.8, 2.4, 2.2, 2.3, 2.2, 2.0], size=9.5,
        align=['left'] + ['center'] * 6)
    fig(w, '4.4', 'cycle_ablation.png', 'Cycle-aware baselines suppress normal luteal changes but keep genuine strain', 15)
    h2(w, '4.5', 'Gait Detector Validation')
    P(w,
      'Before using real data, the gait detectors were checked on synthetic walks with known stride variability, '
      'turns and left–right asymmetry (Figure 4.5). Version 1 overestimated variability by 6.79 CV points on average '
      'and correlated only moderately with the truth (r = 0.61), because turns and asymmetry inflated the step-time '
      'variability. Version 2 reduced the error to 0.52 points (r = 0.98). On the real LTMM walks (Figure 4.6), the '
      'median variability fell from an implausible 8.36% (version 1 step-time CV) to 3.00% (version 2 stride-time CV), '
      'in the range reported for healthy older adults. Version 2 kept 73% of each walk as straight walking, rejected '
      'almost no step intervals, and its cadence agreed with an independent autocorrelation estimate to within 0.78%.')
    fig(w, '4.5', 'gait_detector_bench.png', 'Detector validation on synthetic ground truth', 11)
    fig(w, '4.6', 'ltmm_quality_fix.png', 'Gait variability on real LTMM walks before and after the signal-quality fix', 10)
    h2(w, '4.6', 'Experiment 1: Untrained Gait Index on Real Data')
    P(w,
      'Table 4.5 reports how well each measure separates the 35 fallers from the 38 non-fallers. The untrained version '
      '2 Gait Instability Index reached an AUC of 0.686 (95% CI 0.561–0.808) without seeing any fall label. The '
      'clinical Timed Up and Go test, the standard bedside screening tool, reached 0.683 on the 69 subjects who had it, '
      'and our index reached 0.684 on the same subjects. The Berg Balance Scale reached 0.618. A logistic regression '
      'trained on the same features with cross-validation reached 0.713 ± 0.017.')
    tab(w, '4.5', 'Experiment 1: discrimination of fallers and non-fallers (LTMM lab walks, n = 73)',
        ['Measure', 'AUC', '95% CI / spread', 'n'],
        [
            ['v1 Gait Instability Index (untrained)', '0.676', '0.553 – 0.796', '73'],
            ['v2 Gait Instability Index (untrained)', '0.686', '0.561 – 0.808', '73'],
            ['v1 logistic regression (5-fold CV × 10)', '0.674', '± 0.019', '73'],
            ['v2 logistic regression (5-fold CV × 10)', '0.713', '± 0.017', '73'],
            ['Timed Up and Go (clinical)', '0.683', 'v2 index on same subjects: 0.684', '69'],
            ['Berg Balance Scale (clinical)', '0.618', 'v2 index on same subjects: 0.684', '69'],
        ], [6.4, 1.6, 5.2, 1.2], size=9.5, align=['left', 'center', 'center', 'center'])
    P(w,
      'Among single features (Table 4.6, Figure 4.8), cadence was the strongest marker (AUC 0.770, p = 0.0001): '
      'fallers walked at a median of 107 steps per minute against 115 for non-fallers. Step regularity and the '
      'anteroposterior harmonic ratio were also significant (AUC 0.647 and 0.645). Stride-time variability did not '
      'separate the groups in these one-minute walks (AUC 0.492), which suggests that longer recordings are needed '
      'for variability to be informative.')
    tab(w, '4.6', 'Experiment 1: per-feature AUC of the version 2 gait features',
        ['Feature', 'Worse when', 'Median fallers', 'Median non-fallers', 'AUC', 'p'],
        [
            ['Cadence (steps/min)', 'lower', '107.1', '115.4', '0.770', '0.0001'],
            ['Stride-time CV (%)', 'higher', '3.00', '2.95', '0.492', '0.908'],
            ['Step regularity', 'lower', '0.764', '0.818', '0.647', '0.031'],
            ['Stride regularity', 'lower', '0.814', '0.828', '0.569', '0.312'],
            ['Harmonic ratio (AP)', 'lower', '2.77', '3.66', '0.645', '0.034'],
            ['ML/V RMS ratio', 'higher', '0.605', '0.589', '0.550', '0.470'],
        ], [4.2, 2.0, 2.4, 2.8, 1.4, 1.6], size=9.5, align=['left'] + ['center'] * 5)
    fig(w, '4.7', 'ltmm_roc.png', 'ROC curves on real LTMM data: gait indices against clinical tests', 11.5)
    fig(w, '4.8', 'ltmm_feature_auc.png', 'Per-feature AUC of the version 2 gait features (no training on labels)', 12)
    h2(w, '4.7', 'Experiment 2: Pre-Registered Models')
    P(w,
      'Experiment 2 asked whether more features or more complex models could beat the simple index. Seven models were '
      'fixed in advance and all are reported (Table 4.7, Figure 4.9). The best was a logistic regression on the five '
      'version 2 features (M2, AUC 0.721 ± 0.019). Adding turn features to the untrained index lowered the AUC '
      '(M1, 0.634), and random forests did worse than logistic regression (0.593 and 0.586), as expected on only 73 '
      'subjects. The pre-registered primary model M4 reached 0.651; a permutation test confirmed that it is better '
      'than chance (single-split AUC 0.677 against a null mean of 0.511, p = 0.030). The confidence interval of the '
      'untrained index overlaps all trained models, so the explainable index is competitive with trained models on '
      'this dataset.')
    tab(w, '4.7', 'Experiment 2: pre-registered models on the LTMM lab walks (n = 73)',
        ['Model', 'Description', 'AUC', 'Spread', 'Trained'],
        [
            ['M0', 'v2 Gait Index (untrained)', '0.686', '95% CI 0.561 – 0.808', 'No'],
            ['M1', 'v3 Index: gait + turns (untrained)', '0.634', '95% CI 0.508 – 0.761', 'No'],
            ['M2', 'Logistic regression: v2 features', '0.721', '± 0.019', 'Yes'],
            ['M3', 'Logistic regression: v3 gait + turns (k = 8)', '0.661', '± 0.030', 'Yes'],
            ['M4', 'Logistic regression: v3 + age + sex (k = 8) — primary', '0.651', '± 0.031', 'Yes'],
            ['M5', 'Random forest: v3 gait + turns', '0.593', '± 0.023', 'Yes'],
            ['M6', 'Random forest: v3 + age + sex', '0.586', '± 0.026', 'Yes'],
        ], [1.6, 6.9, 1.4, 3.6, 1.6], size=9.5, align=['center', 'left', 'center', 'center', 'center'])
    fig(w, '4.9', 'ltmm_exp2_models.png', 'Experiment 2: all pre-registered models (subject-wise cross-validation)', 13)
    h2(w, '4.8', 'Experiment 3: Daily-Life Walking')
    P(w,
      'Experiment 3 tested whether gait measured during three days of free living adds information to the one-minute '
      'lab walk (Table 4.8, Figure 4.10). It did not: on the 64 subjects who had both, the best model with daily-life '
      'features (D3, 0.650) did not improve on the lab index alone (M0, 0.655), and the pre-registered combined index '
      'D1 reached 0.636 (permutation p = 0.030). Daily-life features alone were weak (D0 0.587, D2 0.519). Cadence was '
      'again the most consistent marker (daily-life AUC 0.659). We report this negative result because it was '
      'pre-registered and because it shows that more data does not automatically mean better discrimination.')
    tab(w, '4.8', 'Experiment 3: adding daily-life walking from 3-day recordings',
        ['Model', 'Description', 'n', 'AUC', 'Spread'],
        [
            ['M0', 'Lab v2 index, same subjects (reference)', '64', '0.655', '95% CI 0.506 – 0.793'],
            ['D0', 'Daily-life index (untrained)', '71', '0.587', '95% CI 0.447 – 0.721'],
            ['D1', 'Combined lab + daily index (untrained) — primary', '64', '0.636', '95% CI 0.491 – 0.775'],
            ['D2', 'Logistic regression: daily features', '71', '0.519', '± 0.042'],
            ['D3', 'Logistic regression: lab + daily (k = 6)', '64', '0.650', '± 0.028'],
        ], [1.6, 7.1, 1.0, 1.4, 4.0], size=9.5, align=['center', 'left', 'center', 'center', 'center'])
    fig(w, '4.10', 'ltmm_daily_models.png', 'Experiment 3: lab and daily-life gait models', 13)
    h2(w, '4.9', 'Agent Evaluation')
    P(w,
      'Table 4.9 compares the four agent versions on the 11 scenarios (one run each). The proposed agent D detected '
      'all three emergencies, the baseline agent C detected two, and the plain LLM (A) and plain RAG (B) detected '
      'none. The scenario that separated D from C was scenario 7, “I’m fine, just a bit shaken”, sent by a user with '
      'an uncancelled ring fall event: only the biometric signal caught it, as the text alone was calm. No version '
      'raised a false alarm, including on the keyword trap “I fell asleep on the couch last night”.')
    tab(w, '4.9', 'Agent versions A–D on the 11 fall scenarios',
        ['Version', 'Emergencies caught', 'False alarms', 'Strict grounding', 'Stale data disclosed', 'Mean latency (s)'],
        [
            ['A – Plain LLM', '0/3', '0/8', '0.723', '0/1', '2.90'],
            ['B – Plain RAG', '0/3', '0/8', '0.606', '0/1', '16.82'],
            ['C – Baseline agent', '2/3', '0/8', '0.955', '0/1', '15.98'],
            ['D – Proposed agent', '3/3', '0/8', '0.979', '1/1', '19.61'],
        ], [3.4, 2.9, 1.9, 2.2, 2.6, 2.4], size=9.5, align=['left'] + ['center'] * 5)
    P(w,
      'Strict grounding measures the share of numbers in a reply that appear in the user’s actual data. Versions A '
      'and B have no access to the data and invent numbers (0.723 and 0.606). Version D reached 0.979. Its '
      'self-verification loop fired on one reply, raising that reply’s grounding from 0.80 to 1.00. Only version D '
      'told the user with four-day-old data that the estimate was less reliable (Figure 4.13). Version D fetched on '
      'average 0.88 data streams per non-emergency reply, whereas version C always fetches all twelve. Its average '
      'latency (19.6 s) was higher than C’s (16.0 s) in this batch run, because it makes extra router, safety and '
      'verification calls and the run included API rate-limit retries; on the three emergencies, D replied in 2.6 to '
      '4.4 s because the safety path returns before data is fetched. The safety-widening rule did not fire, because '
      'the router’s confidence was between 0.90 and 0.99 on every query; it is covered by unit tests only.')
    fig(w, '4.11', 'fall_emergency_detection.png', 'Emergency recall and false-alarm rate of the four versions', 12.5)
    fig(w, '4.12', 'fall_grounding.png', 'Strict numeric grounding on personal fall-risk queries', 12)
    fig(w, '4.13', 'ravi_stale.png', 'Demonstration: the stale-data user is told that the estimate is less reliable', 14)
    h2(w, '4.10', 'Testing and Validation')
    P(w,
      'Correctness was checked with automated tests at every level (Table 4.10). The backend tests require no '
      'network and run in seconds; the application tests include widget tests that render the screens at a 320 px '
      'width with enlarged text to catch layout overflow. A continuous-integration pipeline analyses the code, runs '
      'the tests and builds an installable APK on every change.')
    tab(w, '4.10', 'Automated checks and their outcomes',
        ['Check', 'What it verifies', 'Outcome'],
        [
            ['Engine unit tests', 'Baselines, strain, cycle phases, coverage, staleness, tiers', 'Pass'],
            ['Contribution-sum test', 'Points of all features add up to the score', 'Pass'],
            ['Safety tests', 'Keyword guards (“fell asleep”), LLM override, biometric escalation', 'Pass'],
            ['Grounding tests', 'Digit-boundary matching and the correction rule', 'Pass'],
            ['Routing tests', 'Safety widening at low confidence', 'Pass'],
            ['Backend total', '123 tests', 'All pass'],
            ['Application total', '122 tests, incl. layout tests at 320 px and 1.3× text', 'All pass'],
            ['Static analysis', 'flutter analyze', 'No issues'],
            ['Build', 'GitHub Actions APK build', 'Success'],
        ], [3.6, 8.4, 2.6], size=9.5)
    h2(w, '4.11', 'Discussion')
    P(w,
      'The results support the central idea of the project: that useful fall-risk estimates can be produced without '
      'training on fall labels, while keeping every number explainable. On real data, the untrained gait index matched '
      'the clinical Timed Up and Go test, and trained models did not improve on it beyond the width of the confidence '
      'intervals. This is consistent with the small sample: with 73 subjects, a model with more parameters has more '
      'room to overfit than to learn. The deep network of Askhatova et al. [18] reports a higher AUC (0.749) on the '
      'same database, but it uses three-day data, demographics and a model that cannot be explained; our index is '
      'transparent and needs no training.',
      'The engine’s behaviour on the demonstration cohort shows the value of the design choices individually. Personal '
      'baselines make the same reading mean different things for different people. Coverage-adaptive weights and the '
      'confidence score prevent missing or stale data from being mistaken for good health. The cycle-aware baseline '
      'removes false strain on normal luteal days while preserving real deterioration. Additive attribution makes it '
      'possible to show, on the score page and in the chat, exactly which measurement contributed how many points.',
      'In the agent evaluation the most important result is scenario 7. A text-only assistant, however capable, '
      'cannot know that a user who writes “I’m fine” has just fallen; a sensor can. Coupling the ring’s fall event to '
      'the conversation turned this case from a miss into a detection. Grounding against the user’s own data reduced '
      'invented numbers substantially compared with a plain LLM, at the cost of higher latency on non-emergency '
      'questions.')
    h2(w, '4.12', 'Limitations')
    w.numbered([
        '**Retrospective labels.** LTMM fallers are defined by their fall history over the previous year, so the '
        'experiments measure discrimination, not prospective prediction.',
        '**Sensor placement.** LTMM uses a lower-back IMU. The results validate the signal-processing method, not a '
        'finger-worn ring, whose motion signal is dominated by hand movement; the live Motion layer currently uses '
        'daily steps and near-fall events rather than gait features.',
        '**Small samples.** With n = 73, confidence intervals are wide and differences of a few hundredths in AUC are '
        'within noise. The agent evaluation used 11 scenarios with one run each.',
        '**Synthetic cohort.** The engine and the agent were evaluated on five generated users; this shows that the '
        'engine behaves as designed but is not evidence of clinical validity.',
        '**Approximate evidence weights.** The four effect sizes come from different studies, mix odds ratios and a '
        'risk ratio, are not mutually adjusted, and were mostly measured in older adults. The physiology layer uses '
        'orthostatic hypotension as a proxy although the ring does not measure blood pressure on standing. Several '
        'thresholds (dead zone 0.5, full strain at 3.0, tiers 40 and 70) are design choices.',
        '**Fall events.** Phone-detected falls are stored on the device; in the evaluation, the backend’s biometric '
        'signal used fall events seeded into Supabase.',
        '**Security.** The backend trusts the user identifier sent by the application and accesses Supabase with a '
        'service key; verifying the user’s token on every request is required before any real deployment.',
    ])

    # ── CHAPTER 5 ────────────────────────────────────────────────────────────
    chapter(w, 5, 'Conclusion and Future Work')
    h2(w, '5.1', 'Summary of Work Completed')
    P(w,
      'This project built an end-to-end system for explainable, safety-aware fall-risk estimation from smart-ring '
      'data. A Flutter and Kotlin application collects vital signs from a Bluetooth ring, stores them locally and in '
      'Supabase, detects falls with the phone’s motion sensors, and presents three sections: a vital-sign dashboard, '
      'an AI assistant and a Fall Risk page. A deterministic engine computes a daily Fall Risk Score from personal '
      'robust baselines, cycle-aware adjustments and evidence-derived layer weights, and decomposes it into the '
      'contribution of each measurement. An agent explains the score through a pipeline that routes each question to '
      'the data it needs, fuses keyword, LLM and ring fall-event signals to detect emergencies, and verifies every '
      'number before replying. A gait-analysis pipeline for the motion component was validated on real data.')
    h2(w, '5.2', 'Major Findings')
    w.bullets([
        'An untrained, explainable gait index separated fallers from non-fallers with an AUC of 0.686 on real data, '
        'comparable to the clinical Timed Up and Go test (0.683); trained models did not improve on it beyond noise.',
        'Cadence was the most consistent single marker of fall history, in the laboratory (AUC 0.770) and in daily life '
        '(0.659).',
        'Cycle-aware baselines reduced physiology risk on normal luteal days by 43% and removed false flags, without '
        'hiding genuine strain.',
        'Tri-modal safety fusion detected all three emergencies, including one that only the ring could see, with no '
        'false alarms; text-only versions missed it.',
        'Closed-loop grounding against the user’s data achieved a strict numeric grounding of 0.979, compared with '
        '0.723 for a plain LLM.',
    ])
    h2(w, '5.3', 'Conclusion')
    P(w,
      'The project shows that a fall-risk system does not need to be a black box to be useful. By learning each '
      'person’s normal from their own data, weighting deviations with published clinical evidence, and letting the LLM '
      'explain rather than compute, the system produces scores that can be traced to individual measurements and '
      'checked against the data. By letting the ring’s sensors speak alongside the user’s words, it recognises '
      'emergencies that a text-only assistant would miss.')
    h2(w, '5.4', 'Future Enhancements')
    w.numbered([
        'Port the validated gait pipeline to the phone or ring IMU so that the Motion layer uses real gait features.',
        'Upload phone-detected fall events to the backend so that the biometric safety signal works on real falls.',
        'Collect labelled data prospectively and fit the layer weights, comparing them with the evidence-derived '
        'weights; calibrate the score to an absolute probability of falling.',
        'Validate the cycle-aware layer on an open menstrual-cycle wearable dataset.',
        'Verify the user’s authentication token on every backend request and query Supabase with row-level security.',
        'Run repeated agent evaluations with more scenarios and real users, and measure latency on dedicated hardware.',
    ])

    # ── APPENDIX ─────────────────────────────────────────────────────────────
    unnumbered(w, 'Appendix')
    w.h3('Appendix 1: Engine Parameters')
    w.table(['Parameter', 'Value', 'Meaning'], [
        ['BASELINE_DAYS', '28', 'Length of the personal baseline window (days)'],
        ['MIN_BASELINE_POINTS', '7', 'Minimum number of days needed for a baseline'],
        ['MISSING_AFTER_DAYS', '7', 'A value older than this is treated as missing'],
        ['MAD factor', '1.4826', 'Makes the MAD consistent with the standard deviation'],
        ['DEAD_ZONE_Z', '0.5', 'Deviation below this adds no strain'],
        ['FULL_STRAIN_Z', '3.0', 'Deviation at which strain reaches 100'],
        ['SpO₂ floor', '95%', 'Absolute threshold below which strain is added'],
        ['MIN_PHASE_POINTS', '5', 'Same-phase days needed for a phase-matched baseline'],
        ['Luteal offsets', '+0.3 °C, +2 bpm, −7%', 'Temperature, resting HR and HRV fallback offsets'],
        ['Near-fall strain', '50 per event (14 days)', 'Motion component from near-falls'],
        ['Fall-history risk', '0 / 60 / 100', 'For 0, 1 and ≥ 2 falls in 365 days'],
        ['EVIDENCE_RATIOS', 'FH 2.8, MO 2.1, P 1.73, RC 1.27', 'Published effect sizes for the layer weights'],
        ['Tiers', '< 40 LOW, < 70 MODERATE, else HIGH', 'Mapping of the score to a tier'],
        ['Low confidence', 'Q < 60', 'Score is marked as low confidence'],
        ['Stale', 'data > 2 days old', 'Score is marked as stale'],
        ['Router threshold', '0.75', 'Below this, safety questions widen the data fetch'],
        ['LLM safety threshold', '0.70 / 0.85', 'Trigger / keyword-override confidence'],
        ['Biometric window', '30 min', 'Ring fall events that escalate any message'],
    ], [4.0, 5.0, 6.4], size=9)
    w.h3('Appendix 2: Key Source Code')
    w.body('Robust baseline and dead-zone strain (agent/fall_risk.py):')
    w.code([
        'EVIDENCE_RATIOS = {"FH": 2.8, "MO": 2.1, "P": 1.73, "RC": 1.27}',
        '_LN = {k: math.log(v) for k, v in EVIDENCE_RATIOS.items()}',
        'BASE_LAYER_WEIGHTS = {k: v / sum(_LN.values()) for k, v in _LN.items()}',
        '',
        'def _robust_baseline(values, min_scale):',
        '    """Median and MAD-based spread (1.4826*MAD ~ SD for normal data)."""',
        '    med = statistics.median(values)',
        '    mad = statistics.median([abs(v - med) for v in values])',
        '    return med, max(1.4826 * mad, min_scale)',
        '',
        'def _strain_from_z(z_risk):',
        '    """Map a risk-direction z-score to 0-100 strain with a noise dead-zone."""',
        '    s = (z_risk - DEAD_ZONE_Z) / (FULL_STRAIN_Z - DEAD_ZONE_Z)',
        '    return max(0.0, min(1.0, s)) * 100.0',
    ])
    w.spacer(160)
    w.body('Tri-modal safety fusion (agent/tools.py, abridged):')
    w.code([
        'def check_emergency_fused(message, llm_res, biometric_event=None):',
        '    triggered_kw = match_emergency_keywords(message)',
        '    is_llm_emerg, llm_reason, llm_conf = llm_res',
        '    llm_triggered = is_llm_emerg and llm_conf >= 0.7',
        '    # a keyword hit is ignored only if the LLM confidently disagrees',
        '    if triggered_kw and not is_llm_emerg and llm_conf >= 0.85:',
        '        effective_kw = []',
        '    else:',
        '        effective_kw = triggered_kw',
        '    # an uncancelled ring fall in the last 30 min escalates ANY message',
        '    biometric_triggered = bool(biometric_event)',
        '    is_emergency = bool(effective_kw) or llm_triggered or biometric_triggered',
        '    ...',
    ])
    w.spacer(160)
    w.body('Strict numeric grounding used by self-verification (agent/graph.py):')
    w.code([
        'def compute_grounding_score_strict(final_reply, patient_data):',
        '    numbers = re.findall(r"\\d+(?:\\.\\d+)?", final_reply or "")',
        '    checked = [n for n in numbers if n not in _GROUNDING_ALLOWLIST]',
        '    if not checked:',
        '        return {"grounding_score": 1.0, "ungrounded_numbers": []}',
        '    ungrounded = [n for n in checked if not re.search(',
        '        r"(?<![\\d.])" + re.escape(n) + r"(?![\\d]|\\.\\d)", patient_data)]',
        '    score = (len(checked) - len(ungrounded)) / len(checked)',
        '    return {"grounding_score": round(score, 4), "ungrounded_numbers": ungrounded}',
    ])
    w.spacer(160)
    w.h3('Appendix 3: Reproducing the Results')
    w.numbered([
        'Backend: create a Python virtual environment, install requirements.txt and create a .env file with '
        'SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY and GROQ_API_KEY.',
        'Run schema.sql and schema_fall.sql once in the Supabase SQL editor, then seed the demonstration cohort with '
        '“python seed_fall_demo.py”.',
        'Run the offline tests with “pytest tests” and the engine analysis with “python run_fall_engine_analysis.py”.',
        'Run the LTMM experiments with “python run_ltmm_validation.py”, “python run_ltmm_experiment2.py” and '
        '“python run_ltmm_daily.py”; the data is downloaded from PhysioNet automatically.',
        'Run the agent evaluation with “python run_fall_evaluation.py”, then regenerate the results summary with '
        '“python scripts/make_review2_summary.py”.',
        'Start the server with “uvicorn main:app --host 0.0.0.0 --port 8000”, install the application APK, and enter '
        'the laptop’s Wi-Fi address in the AI Assist server dialog.',
    ])

    # ── BIBLIOGRAPHY ─────────────────────────────────────────────────────────
    unnumbered(w, 'Bibliography')
    for r in REFS:
        w.bib(r)

    # ── BIODATA ──────────────────────────────────────────────────────────────
    unnumbered(w, 'Biodata')
    for name, reg in (ME,):
        w.placeholder('[Photo – insert here]', '')
        for line in (f'Name: {name.title()} ({reg})', 'Mobile No.:', 'E-mail:', 'Permanent Address:'):
            w.body(line, after=40)
        w.spacer(360)
