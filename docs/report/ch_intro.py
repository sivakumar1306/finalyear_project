"""Chapter 1 (Introduction) and Chapter 2 (Literature Survey)."""
from content import chapter, h2, h3, fig, tab, P


def write(w):
    # ── CHAPTER 1 ────────────────────────────────────────────────────────────
    chapter(w, 1, 'Introduction')
    h2(w, '1.1', 'Background')
    P(w,
      'Falls are one of the most common and most serious health events in later life. In community-dwelling older '
      'adults a fall can lead to fractures, head injury, loss of independence and a lasting fear of falling. Many falls are not random accidents: they are preceded by '
      'measurable changes such as a history of earlier falls, deteriorating gait, low blood pressure on standing, poor '
      'sleep and general physiological strain [11]–[14]. If these changes can be observed continuously, rising risk '
      'can be flagged before a fall happens rather than after.',
      'Consumer smart rings now measure heart rate (HR), heart-rate variability (HRV), blood oxygen saturation '
      '(SpO₂), skin temperature, sleep and activity every day, at low cost and without user effort. Because the '
      'same person is measured for weeks, each reading can be compared with that person’s own normal range rather '
      'than with a population average, an approach that has already been used to detect illness early from '
      'wearables [15]. Smart rings therefore offer a practical way to monitor the daily factors that are linked to '
      'falls.',
      'At the same time, large language models (LLMs) have made it possible to build conversational health '
      'assistants that answer questions about a user’s own data [1]–[3]. Such assistants are attractive because they '
      'explain trends in plain language, but they also introduce new risks: an LLM can state a number that is not in '
      'the data, and a text-only safety check can miss an emergency when the user writes something calm such as '
      '“I’m fine”.')
    h2(w, '1.2', 'Motivation')
    P(w,
      'Existing fall systems are largely reactive. Wearable fall detectors raise an alarm after an impact has '
      'occurred, and clinical fall-risk assessment relies on occasional tests such as the Timed Up and Go (TUG) test '
      'performed in a clinic. Machine-learning models for fall risk often reach good accuracy on curated data, but '
      'they are usually black boxes whose output cannot be explained to the person being assessed, and they need '
      'labelled fall data that is rarely available for a new device.',
      'Health chatbots have the opposite problem: they explain fluently but are not reliable with numbers, and they '
      'decide whether a message is an emergency by reading the text alone. A person who has just fallen and replies '
      '“I’m fine, just a bit shaken” would be told they are fine. The motivation for this project is to combine the '
      'strengths of both worlds: a transparent, deterministic engine that computes risk from the ring’s data, and an '
      'agent that explains that risk in plain language while the sensors, the engine and the LLM check one another.')
    h2(w, '1.3', 'Problem Statement')
    P(w,
      'Given daily vital-sign and activity data from a smart ring, together with fall events recorded by the phone, '
      'the problem is to (i) estimate a person’s daily fall risk in a way that is personalised, explainable down to '
      'each measurement and robust to missing or stale data, without depending on a large labelled training set; '
      '(ii) explain that estimate through a conversational agent whose every number is traceable to the user’s data; '
      'and (iii) recognise emergencies even when the user’s message does not describe one.')
    h2(w, '1.4', 'Objectives')
    w.numbered([
        'To build a smart-ring application that collects, stores and displays daily vital signs (HR, HRV, SpO₂, '
        'skin temperature, blood pressure, stress, sleep and steps) and records fall events.',
        'To design a deterministic fall-risk engine based on personal robust baselines, with layer weights derived '
        'from published fall-risk evidence rather than tuned by hand.',
        'To make the score cycle-aware for women, so that normal menstrual-cycle changes are not counted as risk.',
        'To make the score fully explainable: the contribution of every measurement must add up exactly to the score.',
        'To build an agent that routes each question to the data it needs, detects emergencies from text and from '
        'ring fall events, and verifies every number in its reply against the user’s data.',
        'To validate the motion component on a real public dataset (PhysioNet LTMM) against a clinical reference, and '
        'to evaluate the agent against simpler baselines.',
    ])
    h2(w, '1.5', 'Scope of the Project')
    P(w,
      'The system covers data acquisition from a commercial Bluetooth smart ring through an Android application '
      'written in Flutter and Kotlin, storage in Supabase (PostgreSQL), a Python backend that hosts the fall-risk '
      'engine and the agent, and an application with three sections: a Home dashboard of vital signs, an AI Assist '
      'chat, and a Fall Risk page that shows the score and how it was calculated. The backend runs on a laptop on the '
      'same network as the phone, and the LLM is accessed through the Groq API.',
      'The system gives screening estimates; it does not diagnose and is not a certified medical device. Emergency '
      'SMS and automatic calling were deliberately left out of the final scope so that the prototype never contacts '
      'third parties on its own. The engine and agent are evaluated on a synthetic demonstration cohort and the '
      'motion layer on real gait recordings; a prospective clinical study of real falls is outside the scope of a '
      'one-semester project.')
    h2(w, '1.6', 'Contributions')
    P(w, 'The main contributions of this work are:')
    w.numbered([
        '**Evidence-derived, coverage-adaptive layer weights.** Each layer weight is the natural logarithm of a '
        'published odds or risk ratio, normalised to sum to one, which is equivalent to borrowing logistic-regression '
        'coefficients from meta-analyses. Weights are renormalised by data coverage so that a missing sensor is not '
        'silently read as “no risk”.',
        '**Cycle-aware personal baselines.** HRV, resting heart rate and skin temperature are compared with '
        'same-phase days of the user’s menstrual cycle.',
        '**Compute-then-explain with closed-loop grounding.** The score is computed by the engine and never by the '
        'LLM; every number in a reply is checked against the user’s data, with one corrective regeneration.',
        '**Tri-modal safety fusion.** Emergency detection combines a keyword matcher, an LLM classifier and the '
        'ring’s fall event, so a calm message after a recent fall is still escalated.',
        '**Real-data validation of the motion pipeline.** A gait-analysis pipeline validated on 73 older adults '
        'from PhysioNet LTMM, with every pre-registered model reported.',
    ])
    h2(w, '1.7', 'Organisation of the Report')
    P(w,
      'Chapter 2 reviews prior work on health agents, self-verification, fall-risk factors, personal baselines and '
      'gait analysis, and identifies the gaps this work addresses. Chapter 3 describes the system architecture, the '
      'data sources, the fall-risk engine and its formulas, the gait pipeline, the agent and the evaluation protocol. '
      'Chapter 4 presents the implementation and the results of the engine, the real-data experiments and the agent '
      'evaluation, followed by a discussion and the limitations. Chapter 5 concludes the report and outlines future '
      'work. The appendices list the engine parameters, key source code and reproduction steps.')

    # ── CHAPTER 2 ────────────────────────────────────────────────────────────
    chapter(w, 2, 'Literature Survey')
    P(w,
      'The literature relevant to this project falls into four groups: LLM agents that reason over personal '
      'wearable data; methods that make LLM outputs more reliable through reasoning and self-verification; clinical '
      'evidence on fall-risk factors and on personal-baseline monitoring; and signal-processing methods for gait '
      'analysis. Twenty-two works were reviewed. Papers [1]–[10] were studied at the first review and papers '
      '[11]–[22] were added for the fall-prediction work.')
    h2(w, '2.1', 'LLM Agents for Personal Health Data')
    P(w,
      'Mohammed et al. [1] present an agentic health-analytics pipeline that turns data from several wearables into '
      'explainable well-being insights. Its reasoning layer separates data-grounded facts, physiological rationale '
      'and small actionable habits, and keeps numerical processing separate from text generation to reduce '
      'hallucination. However, it processes all metrics for every query and has no safety layer. Merrill et al. [2] '
      'introduce the Personal Health Insights Agent (PHIA), which combines multistep reasoning, code generation and '
      'web search; in a 650-hour expert evaluation it reached 84% accuracy on objective numerical questions and 83% '
      'favourable ratings on open-ended ones. It does not, however, address emergencies or selective data retrieval.',
      'Lu, Abbasian and Rahmani [3] organise wearable metrics into a personal knowledge graph and retrieve a '
      'query-specific subgraph, winning about 70% of comparisons against baseline and standard retrieval-augmented '
      'generation (RAG) on more than 10,000 queries; retrieval is not linked to urgency or safety. Zhang et al. [4] '
      'propose RubricsTree, a taxonomy of more than 100 clinically verifiable rubrics with a router that activates '
      'the relevant subset for each query, for evaluating personal health agents. Saha et al. [5] select among '
      'task-specialised models with an attentive neural process. Together these works show that routing and '
      'grounding matter in health agents, but none couples data retrieval with safety, and none lets a physiological '
      'signal override the text of the conversation.')
    h2(w, '2.2', 'Reasoning and Self-Verification in LLMs')
    P(w,
      'ReAct [6] interleaves reasoning traces with tool actions and improves interpretability over reasoning-only or '
      'acting-only prompting. SelfCheckGPT [7] detects hallucinations by sampling a model several times and measuring '
      'inconsistency, without access to ground truth, at the cost of many extra calls. Self-Refine [8] lets the same '
      'model critique and revise its output and reports an average gain of about 20% across seven tasks. Ateia and '
      'Kruschwitz [9] apply a generate–evaluate–refine loop to biomedical question answering and find that the gains '
      'vary across models. Fu et al. [10] build a self-evolving agent that distils past correction episodes into '
      'memory to write evidence-grounded health community notes.',
      'These methods verify an answer against the model itself or against general knowledge. For a personal health '
      'assistant, a stronger and cheaper check is available: the user’s own data. This project therefore checks every '
      'number in the reply against the patient data that was given to the model, and regenerates once if any number '
      'is not found.')
    h2(w, '2.3', 'Fall-Risk Factors and Personal Baselines')
    P(w,
      'Deandrea et al. [11] pooled 74 prospective studies of community-dwelling older people. The strongest risk '
      'factors included a history of falls (odds ratio, OR, 2.8 for all fallers and 3.5 for recurrent fallers) and '
      'gait problems (OR 2.1 and 2.2). Hausdorff et al. [12] showed in a one-year prospective study that stride-time '
      'variability predicts future falls. Mol et al. [13] pooled 50 studies with 49,164 participants and found an '
      'OR of 1.73 (95% CI 1.50–1.99) between orthostatic hypotension and falls. In the Study of Women’s Health Across '
      'the Nation (SWAN), Baker et al. [14] found that women who frequently had trouble falling asleep had about a '
      '27% higher risk of a later fall (relative risk, RR, 1.27). These four effect sizes provide the weights of the '
      'four layers of our engine.',
      'Mishra et al. [15] showed that deviations from a person’s own resting-heart-rate baseline, measured by a '
      'smartwatch, flagged COVID-19 before symptoms appeared, establishing personal-baseline deviation as a '
      'practical signal. For women, the baseline itself moves with the menstrual cycle. Alzueta et al. [16] followed '
      '26 women with an Oura ring and found higher distal skin temperature and heart rate during sleep in the mid- and '
      'late-luteal phases than during menses and ovulation, and de Jager et al. [17] review how wearable-derived HRV '
      'varies across the cycle and with hormonal contraception. No wearable fall-risk score that we found adjusts its '
      'baselines to the cycle phase.')
    h2(w, '2.4', 'Gait Analysis for Fall Risk')
    P(w,
      'Askhatova et al. [18] trained a temporal convolutional network on lower-back IMU data from the PhysioNet LTMM '
      'database, using one-minute laboratory walks, three-day recordings and demographics with subject-wise '
      'cross-validation, and report an AUC of 0.749; the model is accurate but not explainable. Weiss et al. [19], '
      'who created the LTMM data, showed that gait quality measured during daily life differs between fallers and '
      'non-fallers. McCamley et al. [20] estimate initial and final foot contacts from a single lower-trunk sensor '
      'using a Gaussian continuous wavelet approach. Moe-Nilssen and Helbostad [21] derive step and stride '
      'regularity from the autocorrelation of trunk acceleration. Drover et al. [22] showed that features from turns, '
      'in addition to straight walking, help classify fallers. These methods form the building blocks of our gait '
      'pipeline (Section 3.5), which we validate on the LTMM dataset [23].')
    h2(w, '2.5', 'Comparison of Existing Approaches')
    tab(w, '2.1', 'Summary of the reviewed literature',
        ['No.', 'Work', 'Method', 'Key finding', 'Gap relevant to this project'],
        [
            ['[1]', 'Mohammed et al., 2026', 'Fact → rationale → action agent', 'Traceable insights', 'Fetches all data; no safety layer'],
            ['[2]', 'Merrill et al., 2026', 'LLM agent with code generation', '84% numeric accuracy', 'No emergency handling'],
            ['[3]', 'Lu et al., 2026', 'Query-conditioned graph retrieval', '~70% win rate vs RAG', 'Retrieval not linked to safety'],
            ['[4]', 'Zhang et al., 2026', 'Rubric router for evaluation', 'Scalable evaluation', 'Routes rubrics, not data'],
            ['[5]', 'Saha et al., 2026', 'Neural-process model selection', 'Better tool choice', 'No biometric context'],
            ['[6]', 'Yao et al., 2023', 'Reasoning + acting (ReAct)', 'More interpretable agents', 'Generic, no safety coupling'],
            ['[7]', 'Manakul et al., 2023', 'Sampling consistency', 'Detects hallucination', 'No ground-truth data; costly'],
            ['[8]', 'Madaan et al., 2023', 'Self-critique and refine', '~20% average gain', 'Not grounded in source data'],
            ['[9]', 'Ateia & Kruschwitz, 2025', 'Self-feedback for biomedical RAG', 'Gains vary by model', 'Not patient-specific'],
            ['[10]', 'Fu et al., 2026', 'Self-evolving correction memory', 'Grounded health notes', 'Public posts, not biometrics'],
            ['[11]', 'Deandrea et al., 2010', 'Meta-analysis, 74 studies', 'Falls OR 2.8; gait OR 2.1', 'Population risk, no daily trend'],
            ['[12]', 'Hausdorff et al., 2001', 'Prospective gait study', 'Stride variability predicts falls', 'Laboratory measurement'],
            ['[13]', 'Mol et al., 2019', 'Meta-analysis, 50 studies', 'Orthostatic hypotension OR 1.73', 'One-off BP test'],
            ['[14]', 'Baker et al., 2024', 'SWAN cohort', 'Poor sleep RR 1.27', 'Questionnaire sleep'],
            ['[15]', 'Mishra et al., 2020', 'Personal-baseline deviation', 'Early illness detection', 'Not falls; not explained'],
            ['[16]', 'Alzueta et al., 2022', 'Oura ring across the cycle', 'Luteal rise in temp and HR', 'Not used in risk scores'],
            ['[17]', 'de Jager et al., 2026', 'Living systematic review', 'HRV varies with cycle', 'Wearable scores ignore phase'],
            ['[18]', 'Askhatova et al., 2026', 'Temporal CNN on LTMM', 'AUC 0.749', 'Black box'],
            ['[19]', 'Weiss et al., 2013', '3-day accelerometry', 'Daily-life gait differs', 'No explanation or agent'],
            ['[20]', 'McCamley et al., 2012', 'Gaussian-derivative contacts', 'Accurate step timing', 'Detection only'],
            ['[21]', 'Moe-Nilssen & Helbostad, 2004', 'Autocorrelation regularity', 'Gait cycle from one sensor', 'No risk model'],
            ['[22]', 'Drover et al., 2017', 'Turn + straight-walk features', 'Turns help classify fallers', 'Not replicated on LTMM'],
        ], [1.0, 3.0, 3.6, 3.5, 4.0], size=8.5)
    h2(w, '2.6', 'Research Gaps Identified')
    P(w, 'The review points to four gaps, each of which is addressed by one part of this work:')
    tab(w, '2.2', 'Research gaps and how this project addresses them',
        ['Gap in existing work', 'How this project addresses it'],
        [
            ['Fall systems detect falls but do not predict or explain daily risk.',
             'A daily Fall Risk Score from ring data, with the contribution of every measurement.'],
            ['The most accurate fall-risk models are black boxes trained on labelled data.',
             'A deterministic engine with evidence-derived weights; the LLM only explains its numbers.'],
            ['Health agents decide whether a message is an emergency from the text alone.',
             'Tri-modal fusion of a keyword matcher, an LLM classifier and the ring’s fall event.'],
            ['Wearable risk scores use one baseline for every day of the menstrual cycle.',
             'Phase-matched baselines for HRV, resting heart rate and skin temperature.'],
        ], [7.5, 7.5], size=10)
