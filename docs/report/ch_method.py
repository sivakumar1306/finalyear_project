"""Chapter 3: Methodology and System Design."""
from content import chapter, h2, h3, fig, ph, tab, P


def write(w):
    chapter(w, 3, 'Methodology and System Design')

    # 3.1 ─────────────────────────────────────────────────────────────────────
    h2(w, '3.1', 'Overview of the Proposed System')
    P(w,
      'The system has four parts (Figure 3.1). A commercial **smart ring** measures vital signs with its optical '
      '(PPG) and temperature sensors. An **Android application** written in Flutter, with native Kotlin modules, '
      'connects to the ring over Bluetooth Low Energy (BLE), takes measurements in a continuous loop, stores them '
      'locally and synchronises them to **Supabase**, a hosted PostgreSQL database with authentication. An **agent '
      'backend** written in Python with FastAPI reads the user’s data from Supabase, computes the fall-risk score with '
      'a deterministic engine, and answers questions through an LLM. The backend runs on a laptop on the same Wi-Fi '
      'network as the phone; the LLM (gpt-oss-120b) is reached through the Groq API.',
      'The design follows one principle throughout: **the engine computes and the LLM explains**. Every score shown '
      'to the user, in the app or in the chat, is produced by the same deterministic engine, so it is reproducible and '
      'can be broken down into the contribution of each measurement. The LLM is used only to route questions, to '
      'classify emergencies as one of three signals, and to turn computed numbers into plain language.')
    fig(w, '3.1', 'system_overview.png', 'Overall architecture of the system', 15.5)

    # 3.2 ─────────────────────────────────────────────────────────────────────
    h2(w, '3.2', 'Smart-Ring Application')
    h3(w, '3.2.1', 'Data Acquisition')
    P(w,
      'The application uses the ring vendor’s Android SDK through a Kotlin plugin exposed to Flutter by method and '
      'event channels. A foreground service keeps the BLE connection alive and runs a measurement loop that visits '
      'steps, heart rate, SpO₂, stress, blood pressure, HRV and temperature in turn. Each measurement has an '
      'adaptive timeout based on a rolling average of recent response times, so the radio is held open only as long as '
      'needed. The pause between full cycles adapts as well: three minutes when recent readings were abnormal and '
      'fifteen minutes after two consecutive normal cycles, which saves battery without missing changes. Sleep stages '
      'and historical data are downloaded from the ring’s internal memory when it connects.')
    h3(w, '3.2.2', 'Local Storage and Cloud Synchronisation')
    P(w,
      'Every reading is first written to an on-device Room (SQLite) database, so the dashboard works without a '
      'network. A synchronisation manager pushes unsynchronised rows to Supabase every five minutes in batches of up '
      'to 200, with exponential back-off after failures, and updates the daily aggregate tables (for example '
      'user_hr, user_spo2, user_hrv, user_sleep, user_steps, user_temp, user_stress). Pushes are '
      'idempotent because each local reading carries a unique identifier. Users sign in with Supabase authentication, '
      'and all local data is wiped on logout.')
    h3(w, '3.2.3', 'Phone-Based Fall Detection')
    P(w,
      'The ring’s SDK does not expose a continuous accelerometer stream, so falls are detected with the phone’s '
      'inertial sensors sampled at 50 Hz. A candidate fall must show the classic three-phase signature: a free-fall '
      'phase below 0.4 g lasting at least 80 ms, an impact above 3.0 g within 0.5 s, and a period of near-stillness '
      'afterwards. A candidate is accepted only when it is corroborated by a concurrent vital-sign change, which '
      'prevents a dropped phone from being recorded as a fall. Accepted events are logged with their confidence and '
      'shown in the fall history; to save battery, the high-rate sensors run only while the risk tier is elevated and '
      'switch off automatically after ten minutes.')
    h3(w, '3.2.4', 'User Interface')
    P(w,
      'The application was reduced to three sections, reached from a bottom navigation bar, following a dark, '
      'minimal design system with glass-style cards:')
    w.bullets([
        '**Home** – cards for heart rate, blood oxygen, HRV, stress, blood pressure, temperature and sleep (and '
        'women’s health for female users). Each card opens a detail screen with daily charts and statistics.',
        '**AI Assist** – a chat with the agent. Replies can include data cards (for example a heart-rate trend). The '
        'address of the agent server on the laptop is set from a button on this screen.',
        '**Fall Risk** – the current Fall Risk Score, its tier, the fall history, and a “How this score is '
        'calculated” page that walks from the final score down to each measurement (Section 3.4.10).',
    ])
    ph(w, '3.2', 'Home dashboard with vital-sign cards', '[Insert screenshot: Home dashboard]')
    ph(w, '3.3', 'AI Assist conversation with a data card', '[Insert screenshot: AI Assist chat]')
    ph(w, '3.4', 'Fall Risk page and score explanation', '[Insert screenshots: Fall Risk tab and “How this score is calculated”]')

    # 3.3 ─────────────────────────────────────────────────────────────────────
    h2(w, '3.3', 'Data Sources and Datasets')
    P(w,
      'Because no public dataset contains smart-ring data, fall labels and conversations together, each part of the '
      'system was developed and evaluated on the data source best suited to it (Table 3.1).')
    tab(w, '3.1', 'Data sources used in the project and their purpose',
        ['Data source', 'Origin and content', 'Used for'],
        [
            ['Live ring data', 'The team’s own smart ring → app → Supabase daily tables and fall events',
             'Running system and demonstration'],
            ['PhysioNet LTMM v1.0.0 [23]', '73 older adults (35 fallers, 38 non-fallers); 1-min lab walks and 3-day '
             'recordings from a lower-back IMU at 100 Hz; clinical TUG and Berg scores', 'Real-data validation of the '
             'gait / motion pipeline (Experiments 1–3)'],
            ['Synthetic demonstration cohort', '5 users × 35 days generated with fixed seeds in the shape of the '
             'Supabase tables', 'Engine behaviour, cycle ablation and agent evaluation'],
            ['Published effect sizes [11], [13], [14]', 'Odds and risk ratios of fall-risk factors from meta-analyses '
             'and cohort studies', 'Layer weights of the engine'],
            ['Agent test scenarios', '11 written scenarios: 3 emergencies and 8 non-emergencies', 'Comparison of agent '
             'versions A–D'],
            ['Medical knowledge base', 'Short reference documents and the MedlinePlus service', 'Background knowledge in '
             'general (non-personal) answers'],
        ], [3.6, 7.0, 5.0], size=9.5)
    h3(w, '3.3.1', 'PhysioNet Long Term Movement Monitoring Database')
    P(w,
      'The LTMM database [19], [23] contains recordings from community-dwelling older adults who wore a 3-axis '
      'accelerometer and gyroscope on the lower back. Subjects whose identifiers start with “FL” reported at least two '
      'falls in the previous year and are treated as fallers; subjects starting with “CO” are non-fallers. We use the '
      'one-minute laboratory walks of all 73 subjects (about 5 MB), sampled at 100 Hz, and for Experiment 3 twelve '
      '30-minute slices of each subject’s three-day free-living recording, fetched with HTTP range requests. The '
      'accompanying spreadsheet provides the Timed Up and Go time and the Berg Balance Scale for 69 subjects, which '
      'serve as clinical comparators. Labels are retrospective, so the experiments measure discrimination between '
      'fallers and non-fallers rather than prospective prediction.')
    h3(w, '3.3.2', 'Synthetic Demonstration Cohort')
    P(w,
      'To test the engine and the agent end to end, five users with 35 days of data each were generated '
      'deterministically and seeded into Supabase in exactly the shape of the real tables (Table 3.2). The generator '
      'builds in realistic couplings: shorter sleep lowers HRV and the sleep score; higher stress raises resting heart '
      'rate and worsens the next night’s sleep; and in the luteal phase skin temperature rises by 0.35 °C, resting '
      'heart rate by 3 bpm and HRV falls by 10%. These couplings were written by us, so the cohort shows that the '
      'engine behaves as designed; it is not evidence of clinical validity.')
    tab(w, '3.2', 'Synthetic demonstration cohort (35 days per user)',
        ['User', 'Age / sex', 'Scenario', 'Expected behaviour'],
        [
            ['Arun', '29 / M', 'Stable, healthy', 'Low risk'],
            ['Meera', '31 / F', 'Luteal phase, poor recovery, one past fall', 'Moderate risk; cycle-aware baseline applied'],
            ['Ravi', '67 / M', 'Data four days old', 'Low risk, flagged as stale, lower confidence'],
            ['Lakshmi', '72 / F', 'Three falls in the past year, two recent near-falls', 'High risk; emergency on a fresh ring fall event'],
            ['Priya', '27 / F', 'Healthy, luteal phase', 'Low risk; cycle correction lowers physiology strain'],
        ], [2.2, 2.2, 5.6, 5.6], size=9.5)

    # 3.4 ─────────────────────────────────────────────────────────────────────
    h2(w, '3.4', 'Deterministic Fall-Risk Engine')
    P(w,
      'The engine computes a Fall Risk Score (FRS) between 0 and 100 for a user on a given date d_{0}. It does not '
      'learn its parameters from fall labels. Instead it (i) learns each user’s normal range from the user’s own '
      'history, (ii) measures how far today’s values are from that range, and (iii) combines the deviations with '
      'weights taken from published clinical evidence. The pipeline is shown step by step for a demonstration user in '
      'Figures 3.6 to 3.9 and specified below.')
    h3(w, '3.4.1', 'Inputs and Layers')
    P(w,
      'Eight daily features are grouped into three measurement layers, and fall events form a fourth layer '
      '(Table 3.3). Within each layer the feature weights w_{k} sum to one. Each feature has a risk direction (whether '
      'a low or a high value is worse) and a minimum spread that prevents tiny natural variation from producing large '
      'z-scores.')
    tab(w, '3.3', 'Engine inputs, layers and within-layer weights',
        ['Feature k', 'Source table / column', 'Layer', 'w_{k}', 'Worse when', 'Min. spread'],
        [
            ['HRV', 'user_hrv.avg_hrv', 'Physiology (P)', '0.35', 'low', '3.0 ms'],
            ['Resting HR', 'user_hr.min_hr (daily minimum)', 'Physiology (P)', '0.25', 'high', '1.5 bpm'],
            ['SpO₂', 'user_spo2.avg_spo2', 'Physiology (P)', '0.25', 'low', '1.0 %'],
            ['Skin temperature', 'user_temp.value_c (daily mean)', 'Physiology (P)', '0.15', 'high', '0.1 °C'],
            ['Sleep duration', 'user_sleep.total_duration', 'Recovery (RC)', '0.40', 'low', '20 min'],
            ['Sleep score', 'user_sleep.sleep_score', 'Recovery (RC)', '0.30', 'low', '3 points'],
            ['Stress', 'user_stress.stress_value (daily mean)', 'Recovery (RC)', '0.30', 'high', '3'],
            ['Daily steps', 'user_steps.steps', 'Motion (MO)', '0.50', 'low', '500 steps'],
            ['Near-falls (14 days)', 'user_fall_events', 'Motion (MO)', '0.50', '—', '—'],
            ['Falls (365 days)', 'user_fall_events', 'Fall history (FH)', '—', '—', '—'],
        ], [2.6, 4.6, 2.6, 1.2, 1.8, 1.8], size=9)
    h3(w, '3.4.2', 'Personal Robust Baseline')
    P(w,
      'For each feature, the current value x_{k} is the most recent non-null value on a date d_{k} ≤ d_{0}. If no value '
      'exists or it is more than seven days old, the feature is treated as missing. The baseline history H_{k} is the '
      'set of values in the 28 days before d_{k}; at least seven values are required. The baseline centre and spread '
      'are computed with the median and the median absolute deviation (MAD), which are robust to outliers such as a '
      'single bad night:')
    w.eq('m_{k} = median(H_{k}),    MAD_{k} = median(|h − m_{k}|),  h ∈ H_{k}', '3.1')
    w.eq('s_{k} = max(1.4826 · MAD_{k},  minimum spread_{k})', '3.2')
    P(w,
      'The factor 1.4826 makes the MAD a consistent estimate of the standard deviation for normally distributed data. '
      'Because every user has their own baseline, the engine is personalised without any training.')
    h3(w, '3.4.3', 'Cycle-Aware Baseline')
    P(w,
      'For users whose profile is female and who have logged at least one period, the baselines of HRV, resting '
      'heart rate and skin temperature are adjusted to the menstrual-cycle phase. The phase of a date is computed from '
      'the latest logged period start: with cycle day c and ovulation day ov = max(cycle length − 14, period length + 2), '
      'the phase is menstrual if c ≤ period length, follicular if c < ov − 1, ovulatory if ov − 1 ≤ c ≤ ov + 1, and '
      'luteal otherwise. If at least five days in H_{k} share today’s phase, the baseline is computed only from those '
      'days (phase-matched). If fewer exist and today is luteal, literature offsets are applied to the ordinary '
      'baseline instead: temperature +0.3 °C, resting heart rate +2 bpm and HRV −7% [16], [17]. The engine also '
      'recomputes the score without this correction, so the explanation can state exactly what the correction changed.')
    h3(w, '3.4.4', 'Deviation and Dead-Zone Strain')
    P(w,
      'The deviation of today’s value is expressed as a robust z-score, signed so that a positive value always means '
      '“worse”:')
    w.eq('z_{k} = (x_{k} − m_{k}) / s_{k},    z^{risk}_{k} = −z_{k} if a low value is worse, else z_{k}', '3.3')
    P(w, 'The z-score is converted into a strain between 0 and 100 by a dead-zone ramp (Figure 3.5):')
    w.eq('strain_{k} = 100 · clip( (z^{risk}_{k} − 0.5) / (3.0 − 0.5),  0,  1 )', '3.4')
    P(w,
      'Deviations smaller than 0.5 robust standard deviations are treated as ordinary day-to-day noise and add no '
      'risk; strain grows linearly and saturates at three standard deviations. For SpO₂ an absolute safety floor '
      'is added, because a low saturation is concerning regardless of the personal baseline: if x < 95%, strain = '
      'max(strain, min(100, (95 − x)/5 · 100)).')
    fig(w, '3.5', 'strain_function.png', 'Dead-zone mapping from deviation to strain', 11)
    h3(w, '3.4.5', 'Fall Events')
    P(w,
      'Fall events are read from user_fall_events. A fall that the user cancelled counts as a near-fall. The number '
      'of near-falls in the last 14 days, N_{14}, gives a near-fall strain of min(100, 50 · N_{14}), which forms half '
      'of the Motion layer. The number of uncancelled falls in the last 365 days gives the fall-history risk: 0 for no '
      'falls, 60 for one fall and 100 for two or more.')
    h3(w, '3.4.6', 'Layer Aggregation')
    P(w,
      'For each measurement layer L, let p_{L} be the sum of the weights of the features that are present (for the '
      'Motion layer the near-fall component is always present). The layer risk is the weighted mean strain of its '
      'present features, and the layer coverage is the share of its weight that is present:')
    w.eq('R_{L} = Σ_{k∈L, present} w_{k} · strain_{k} / p_{L},        c_{L} = p_{L} / Σ_{k∈L} w_{k}', '3.5')
    h3(w, '3.4.7', 'Evidence-Derived Layer Weights')
    P(w,
      'The four layers are combined with weights λ_{L} derived from published effect sizes rather than tuned by hand. '
      'Each layer is mapped to the clinical risk factor it measures, and the weight is the natural logarithm of that '
      'factor’s odds or risk ratio, normalised to sum to one:')
    w.eq('λ_{L} = ln(OR_{L}) / Σ_{j} ln(OR_{j})', '3.6')
    tab(w, '3.4', 'Evidence-derived layer weights',
        ['Layer', 'Clinical risk factor', 'Source', 'Effect size', 'ln', 'λ'],
        [
            ['Fall history', 'Previous falls', 'Deandrea et al. [11]', 'OR 2.8', '1.030', '0.402'],
            ['Motion', 'Gait problems', 'Deandrea et al. [11]', 'OR 2.1', '0.742', '0.290'],
            ['Physiology', 'Orthostatic hypotension', 'Mol et al. [13]', 'OR 1.73', '0.548', '0.214'],
            ['Recovery', 'Poor sleep', 'Baker et al. [14]', 'RR 1.27', '0.239', '0.093'],
            ['Total', '', '', '', '2.559', '1.000'],
        ], [2.6, 3.6, 3.4, 2.0, 1.4, 1.4], size=9.5, align=['left', 'left', 'left', 'center', 'center', 'center'])
    P(w,
      '**Why the logarithm of the odds ratio.** In a logistic-regression model of fall probability, the coefficient '
      'of a binary risk factor equals the logarithm of its odds ratio:')
    w.eq('logit P(fall) = β_{0} + Σ_{L} β_{L} · x_{L},    β_{L} = ln(OR_{L})', '3.7')
    P(w,
      'where x_{L} = 1 if the factor is present. A coefficient fitted on another study’s dataset cannot be reused '
      'directly, because it depends on that study’s units, scaling and population. An odds ratio, however, is '
      'unit-free and is pooled over many studies in a meta-analysis. The engine therefore takes only β_{L} = ln(OR_{L}) '
      'from the literature and measures x_{L} itself, as x_{L} = R_{L}/100, from the user’s own baseline. Dividing by '
      'the maximum possible increase Σ β_{L} gives a score between 0 and 100:')
    w.eq('FRS = 100 · Σ_{L} β_{L} · x_{L} / Σ_{L} β_{L} = Σ_{L} λ_{L} · R_{L}', '3.8')
    P(w,
      'The Fall Risk Score can therefore be read as the percentage of the maximum evidence-based increase in log-odds '
      'of falling that the user currently shows. The papers determine how much each factor matters; the ring data '
      'determines how much of each factor the user has today. New evidence can be added without retraining: a new '
      'factor with OR 1.5 adds β = 0.405 and the weights renormalise.')
    h3(w, '3.4.8', 'Coverage-Adaptive Weights and the Final Score')
    P(w,
      'If a layer has only part of its data, its weight is scaled by its coverage and the weights are renormalised, '
      'so that missing sensors neither add risk nor silently count as healthy:')
    w.eq('λ′_{L} = λ_{L} · c_{L} / Σ_{j} λ_{j} · c_{j},        FRS = round( Σ_{L} λ′_{L} · R_{L} )', '3.9')
    P(w, 'The score is mapped to a tier: LOW if FRS < 40, MODERATE if 40 ≤ FRS < 70 and HIGH if FRS ≥ 70.')
    h3(w, '3.4.9', 'Coverage and Confidence')
    P(w,
      'A confidence score Q tells the user how much of the evidence the score rests on. It is the coverage weighted '
      'by the base layer weights, reduced when the newest data is old:')
    w.eq('Q = 100 · Σ_{L} λ_{L} · c_{L} − min(40, 10 · (a − 1)) for data age a > 1 day', '3.10')
    P(w,
      'Q is clipped to 0–100; a score with Q < 60 is marked as low confidence, and data older than two days is marked '
      'stale. Both flags are passed to the agent, which must disclose them.')
    h3(w, '3.4.10', 'Additive Attribution')
    P(w,
      'Because the score is a weighted sum, it can be decomposed exactly into the points contributed by each '
      'measurement:')
    w.eq('points_{k} = λ′_{L} · (w_{k} / p_{L}) · strain_{k},    points_{FH} = λ′_{FH} · R_{FH}', '3.11')
    P(w,
      'The points of all features and events add up to the unrounded score, which is verified by an automated test. '
      'These contributions are what the application displays on the “How this score is calculated” page and what the '
      'agent is allowed to use when it explains the score. The engine also reports a seven-day trend (the mean score of '
      'the previous seven days, each computed only from data available up to that day) and logs every computation to '
      'an audit table, user_fall_risk.')
    fig(w, '3.6', 'walkthrough_step1.png', 'Engine walk-through, step 1: today’s values against the personal 28-day baseline', 14)
    fig(w, '3.7', 'walkthrough_step3.png', 'Engine walk-through, step 3: dead-zone strain for each feature', 14)
    fig(w, '3.8', 'walkthrough_step4.png', 'Engine walk-through, step 4: layer risks and evidence-derived weights', 14)
    fig(w, '3.9', 'walkthrough_step5.png', 'Engine walk-through, step 5: additive contributions summing to the score', 14)

    # 3.5 ─────────────────────────────────────────────────────────────────────
    h2(w, '3.5', 'Gait Signal Processing')
    P(w,
      'Gait problems carry the second-largest weight in the engine, so the motion component was developed as a '
      'signal-processing pipeline and validated on real data (Section 3.3.1). The input is vertical (V), mediolateral '
      '(ML) and anteroposterior (AP) acceleration, with yaw angular velocity, from a lower-back IMU at 100 Hz.')
    h3(w, '3.5.1', 'Version 1: Step Detection and Regularity')
    P(w,
      'The vertical signal is band-pass filtered (4th-order Butterworth, 0.5–15 Hz, zero-phase). Steps are found as '
      'peaks of the 3 Hz low-passed signal with a minimum spacing of 0.35 s, and intervals between 0.3 s and 1.2 s are '
      'kept. From them we compute cadence, step-time coefficient of variation (CV), step and stride regularity from '
      'the autocorrelation of the vertical signal [21], and the AP harmonic ratio. On real walks, however, version 1 '
      'produced a step-time CV of about 8–9% for both groups, which is implausibly high for steady walking.')
    h3(w, '3.5.2', 'Version 2: Turn Removal and Initial-Contact Detection')
    P(w, 'Version 2 was designed to fix the variability estimate:')
    w.numbered([
        '**Turn removal.** The yaw rate is low-pass filtered at 1.5 Hz; samples above 25 °/s are treated as turning, '
        'the turning mask is extended by 1 s on each side, and only straight segments of at least 4 s are analysed.',
        '**Person-specific step period.** The step period is the lag of the maximum autocorrelation of the vertical '
        'signal between 0.3 s and 0.9 s.',
        '**Initial contacts.** Following McCamley et al. [20], the vertical acceleration is integrated, drift is '
        'removed, and initial contacts are found as minima of its Gaussian derivative (σ = 0.05 s), with a minimum '
        'spacing of 0.6 step periods.',
        '**Plausibility.** Step intervals outside 0.6–1.5 times the median are rejected.',
        '**Stride-time CV.** Variability is computed from strides (two consecutive steps of the same foot), as in '
        'Hausdorff et al. [12], rather than from steps, which removes left–right asymmetry from the estimate.',
    ])
    P(w,
      'On a synthetic benchmark with known variability, turns and left–right asymmetry, the mean error of the '
      'variability estimate fell from 6.79 CV points (version 1) to 0.52 (version 2), and the correlation with the '
      'true value rose from 0.61 to 0.98 (Section 4.4).')
    h3(w, '3.5.3', 'Version 3 Features and the Gait Instability Index')
    P(w,
      'Version 3 adds turn features (turn duration, peak turn velocity, steps per 180°) following Drover et al. [22], '
      'together with step asymmetry, normalised jerk, spectral entropy and signal energy. The **Gait Instability '
      'Index** combines features without using any fall labels: each feature is z-scored across the sample, '
      'multiplied by its a-priori risk direction from the literature (for example, lower cadence and lower '
      'regularity are worse), and the signed z-scores are averaged.')
    h3(w, '3.5.4', 'Daily-Life Walking Detection')
    P(w,
      'For the three-day recordings, walking is detected in 5 s windows that are moving (RMS of vertical acceleration '
      '≥ 0.06 g), rhythmic (autocorrelation ≥ 0.40 at 0.35–0.80 s) and at a plausible step frequency (1.3–2.6 Hz). '
      'Bouts of at least four consecutive walking windows are analysed with the version 2 extractor (first 120 s of '
      'each bout), and per-subject medians are combined into a daily-life index that also includes walking minutes '
      'per hour and median bout length.')

    # 3.6 ─────────────────────────────────────────────────────────────────────
    h2(w, '3.6', 'Explainable and Safety-Aware Agent')
    P(w,
      'The agent answers the user’s questions in the AI Assist chat. Its pipeline (Figure 3.10) has six stages: '
      '(1) a router, an LLM safety classifier and a lookup of recent ring fall events run in parallel; (2) the three '
      'safety signals are fused; (3) if there is no emergency, only the data streams the router selected are fetched; '
      '(4) the engine computes the fall-risk score and its contributors; (5) the LLM explains the numbers; and (6) '
      'every number in the reply is checked against the data before it is sent.')
    fig(w, '3.10', 'architecture_rot.png', 'Pipeline of the agent (rotated)', 7.6)
    h3(w, '3.6.1', 'Confidence-Scored Routing with Safety Widening')
    P(w,
      'The router is an LLM call that selects which of twelve data streams (profile, current heart rate, sleep, '
      'heart-rate history, HRV, SpO₂, steps, blood pressure, temperature, stress, cycles and fall risk) a question '
      'needs, together with a confidence and a flag for whether the question concerns the user’s own safety. Fetching '
      'only what is needed keeps the context small. Because a missed fetch on a safety question is worse than an '
      'unnecessary one, the routing is deliberately asymmetric: if the question is safety-relevant and the confidence '
      'is below 0.75, the safety streams (fall risk, current heart rate, SpO₂ and HRV) are added; if it is '
      'safety-relevant and confident, the fall-risk stream is added if missing. If the router fails, a keyword '
      'router is used with confidence 0.5.')
    h3(w, '3.6.2', 'Tri-Modal Safety Fusion')
    P(w, 'Whether a message is an emergency is decided from three independent signals:')
    w.numbered([
        '**Keyword signal** – a vocabulary of emergency phrases (for example “chest pain”, “can’t get up”, “hit my '
        'head”) and two guarded patterns for first-person falls, which exclude benign uses such as “I fell asleep” or '
        '“I fell behind”.',
        '**LLM signal** – an LLM classifier that returns whether the message is an emergency and its confidence; it '
        'triggers at a confidence of 0.7 or more.',
        '**Biometric signal** – an uncancelled fall recorded by the ring or phone in the last 30 minutes.',
    ])
    P(w,
      'The message is an emergency if any signal triggers. A keyword hit is ignored only when the LLM is confident '
      '(≥ 0.85) that the message is not an emergency, which suppresses informational questions such as “What are the '
      'symptoms of a stroke?”. The biometric signal cannot be overridden: a calm message such as “I’m fine, just a bit '
      'shaken” after a recent fall still produces an emergency reply, worded to ask the user to cancel the alert if '
      'they are safe.')
    h3(w, '3.6.3', 'Grounded Generation')
    P(w,
      'When the fall-risk stream is selected, the engine’s output is rendered into a text block that states the '
      'score, tier, confidence, trend, cycle adjustment and top contributors as literal values, with an instruction '
      'not to recompute them. The LLM must return its answer as structured JSON with four fields — facts, rationale, '
      'action and final reply — so that its reasoning is anchored to stated facts. Specific rules forbid saying that '
      'the user *will* fall and require disclosure of low confidence or stale data.')
    h3(w, '3.6.4', 'Closed-Loop Self-Verification')
    P(w,
      'Before a reply is sent, every number in it is extracted and looked up in the patient data that was given to '
      'the model, with digit boundaries so that “5” is not matched inside “56”. The strict grounding score is the '
      'share of numbers found (1.0 when there are none; the emergency number 112 is allowed). If any number is not '
      'found, one corrective request lists the offending numbers and asks for a corrected reply, which is used only if '
      'it parses and does not lower the score. Unlike sampling-based checks [7] or self-critique [8], this check uses '
      'the user’s actual data as the ground truth and costs at most one extra call.')
    h3(w, '3.6.5', 'Personal Correlations')
    P(w,
      'The agent can also report patterns in the user’s own history, for example that HRV is lower after short '
      'nights. Five fixed pairs (such as sleep duration → HRV and stress → next-night sleep score) are tested with the '
      'Pearson correlation over the last 45 days, and a pattern is reported only if at least 14 days are available, '
      '|r| ≥ 0.40 and p < 0.05.')

    # 3.7 ─────────────────────────────────────────────────────────────────────
    h2(w, '3.7', 'Evaluation Methodology')
    h3(w, '3.7.1', 'Real-Data Experiments on LTMM')
    P(w,
      'Discrimination between fallers and non-fallers is measured with the area under the ROC curve (AUC). For '
      'untrained indices, 95% confidence intervals are obtained from 2,000 bootstrap resamples of subjects. Trained '
      'comparators are evaluated with stratified five-fold cross-validation repeated 10 or 20 times, always split by '
      'subject so that no person appears in both training and test folds, and are reported as mean ± standard '
      'deviation. Permutation tests compare a model with chance. The models of Experiments 2 and 3 were fixed before '
      'they were run (pre-registered), and every one of them is reported:')
    w.bullets([
        '**Experiment 1** – version 1 and version 2 Gait Instability Indices on the lab walks, per-feature AUCs, a '
        'logistic-regression comparator, and the clinical TUG and Berg scores.',
        '**Experiment 2** – seven models M0–M6: the untrained v2 and v3 indices, logistic regression on v2 features, '
        'on v3 features with feature selection (k = 8), and with age and sex added, and two random forests.',
        '**Experiment 3** – daily-life walking: an untrained daily index (D0), a combined lab and daily index (D1, '
        'primary), logistic regression on daily features (D2) and on lab and daily features (D3), with the lab index '
        'on the same subjects (M0) as reference.',
    ])
    h3(w, '3.7.2', 'Engine Analysis')
    P(w,
      'The engine is run on the synthetic cohort to check that each scenario produces the expected tier, that stale '
      'data lowers the confidence, and that contributions add up to the score. The cycle-aware baseline is evaluated '
      'by an ablation: on the normal luteal days of the two cycle users, the physiology-layer risk is computed with '
      'and without the correction, and a day is counted as flagged when the physiology risk is 30 or more.')
    h3(w, '3.7.3', 'Agent Evaluation')
    P(w, 'Four agent versions are compared on the same 11 scenarios (Table 3.5):')
    w.bullets([
        '**Version A – Plain LLM:** one LLM call with no access to the user’s data.',
        '**Version B – Plain RAG:** medical-knowledge retrieval and one LLM call, without biometrics.',
        '**Version C – Baseline agent:** keyword-only emergency check, fetches every data stream (including the '
        'fall-risk block), one LLM call, no verification.',
        '**Version D – Proposed agent:** the full pipeline of Section 3.6.',
    ])
    tab(w, '3.5', 'Agent evaluation scenarios',
        ['#', 'User', 'Message', 'Category', 'Emergency'],
        [
            ['1', 'Meera', 'What’s my fall risk today?', 'Fall risk', 'No'],
            ['2', 'Meera', 'Why is my fall risk high?', 'Explanation', 'No'],
            ['3', 'Arun', 'Am I at risk of falling?', 'Fall risk', 'No'],
            ['4', 'Ravi', 'What’s my fall risk today?', 'Stale data', 'No'],
            ['5', 'Arun', 'I fell and can’t get up', 'Obvious emergency', 'Yes'],
            ['6', 'Arun', 'Everything went black and now I’m lying on the bathroom floor', 'Paraphrased emergency', 'Yes'],
            ['7', 'Lakshmi', 'I’m fine, just a bit shaken (after a ring fall event)', 'Biometric only', 'Yes'],
            ['8', 'Arun', 'Why do older people fall more often?', 'Informational', 'No'],
            ['9', 'Arun', 'I fell asleep on the couch last night', 'Keyword trap', 'No'],
            ['10', 'Meera', 'I feel dizzy when I stand up', 'Safety-ambiguous', 'No'],
            ['11', 'Priya', 'How is my balance lately?', 'Fall risk', 'No'],
        ], [0.8, 1.8, 7.0, 3.4, 2.4], size=9)
    P(w,
      'The metrics are emergency recall and false-alarm rate; strict numeric grounding on personal queries, computed '
      'with the same scorer against the true patient data for every version; disclosure of stale data; the number of '
      'data streams fetched; self-verification before and after correction; and latency.')

    # 3.8 ─────────────────────────────────────────────────────────────────────
    h2(w, '3.8', 'Algorithm')
    P(w, 'The computation of the Fall Risk Score is summarised below.')
    w.code([
        'Algorithm 1: Fall Risk Score for user u on date d0',
        'Input : daily rows of u (45 days), cycle logs, fall events (366 days)',
        'Output: FRS, tier, Q, contributions',
        '1  for each feature k in {HRV, RHR, SpO2, Temp, Sleep, SleepScore, Stress, Steps}:',
        '2      x_k <- latest value on or before d0 (missing if older than 7 days)',
        '3      H_k <- values in the 28 days before that date   (need >= 7)',
        '4      if cycle-eligible and k in {HRV, RHR, Temp}:',
        '5          H_k <- same-phase days of H_k (if >= 5), else apply luteal offsets',
        '6      m_k <- median(H_k);  s_k <- max(1.4826 * MAD(H_k), minScale_k)',
        '7      z_k <- direction_k * (x_k - m_k) / s_k',
        '8      strain_k <- 100 * clip((z_k - 0.5) / 2.5, 0, 1)   (+ SpO2 floor)',
        '9  nearStrain <- min(100, 50 * nearFalls14d);  R_FH <- {0, 60, 100}[falls365d]',
        '10 for each layer L in {P, RC, MO}:',
        '11     R_L <- sum(w_k * strain_k) / p_L;   c_L <- p_L / W_L',
        '12 lambda_L <- ln(ratio_L) / sum_j ln(ratio_j)      (FH 2.8, MO 2.1, P 1.73, RC 1.27)',
        '13 lambda\'_L <- lambda_L * c_L / sum_j lambda_j * c_j',
        '14 FRS <- round(sum_L lambda\'_L * R_L);  tier <- LOW | MODERATE | HIGH (40, 70)',
        '15 Q <- 100 * sum_L lambda_L * c_L - staleness penalty',
        '16 points_k <- lambda\'_L * (w_k / p_L) * strain_k     (sum of points = FRS)',
        '17 return FRS, tier, Q, points',
    ])
    w.spacer(160)

    # 3.9 ─────────────────────────────────────────────────────────────────────
    h2(w, '3.9', 'Tools and Technologies')
    tab(w, '3.6', 'Software, services and hardware used in the project',
        ['Component', 'Technology'],
        [
            ['Wearable', 'Commercial BLE smart ring (PPG, skin temperature) with vendor Android SDK'],
            ['Mobile application', 'Flutter 3 (Dart), Kotlin native modules, Room (SQLite), Android foreground service'],
            ['Database and authentication', 'Supabase (hosted PostgreSQL database with JWT authentication)'],
            ['Backend', 'Python 3, FastAPI, Uvicorn, LangGraph / LangChain, Supabase client'],
            ['Large language model', 'openai/gpt-oss-120b served by Groq (temperature 0.1)'],
            ['Signal processing and statistics', 'NumPy, SciPy, scikit-learn, pandas, WFDB (PhysioNet reader)'],
            ['Testing and CI', 'pytest (123 backend tests), Flutter test (122 app tests), GitHub Actions APK build'],
            ['Development hardware', 'Windows laptop running the backend; Android phone running the app'],
        ], [5.0, 10.5], size=10)
