"""Report content: constants, registries, front matter. Chapters live in ch_*.py."""
import os
from pathlib import Path

IMG = Path(__file__).parent / 'img'

TITLE = 'Explainable, Safety-Aware Fall-Risk Prediction from Smart-Ring Data'
STUDENTS = [('G SIVAKUMAR', '23BCE1834'), ('KRITI SAHANA V', '23BCE1868')]
# Each student submits their own copy: both names on the cover, everything
# else (declaration, certificate, acknowledgements, biodata) for this one.
ME = STUDENTS[int(os.environ.get('REPORT_FOR', '0'))]
GUIDE = 'Dr. Sheena Christabel Pravin'
MONTH_YEAR = 'October 2026'

FIGS, TABS, HEADS = [], [], []


def chapter(w, n, title):
    HEADS.append((0, str(n), title))
    w.chapter(n, title)


def h2(w, num, title):
    HEADS.append((1, num, title))
    w.h2(f'{num} {title}')


def h3(w, num, title):
    HEADS.append((2, num, title))
    w.h3(f'{num} {title}')


def unnumbered(w, title):
    HEADS.append((0, '', title))
    w.front_title(title)


def fig(w, num, file, caption, width=14.5):
    FIGS.append((num, caption))
    w.figure(IMG / file, f'Figure {num}: {caption}', width)


def ph(w, num, caption, text):
    FIGS.append((num, caption))
    w.placeholder(text, f'Figure {num}: {caption}')


def tab(w, num, caption, header, rows, widths, **kw):
    TABS.append((num, caption))
    w.table_caption(f'Table {num}: {caption}')
    w.table(header, rows, widths, **kw)


def P(w, *paras):
    for t in paras:
        w.body(t)


# ─────────────────────────────────────────────────────────────────────────────
ABSTRACT = [
    'Falls are the leading cause of injury-related harm in older adults, yet consumer wearables mostly detect a fall '
    'after it has happened, and health chatbots built on large language models (LLMs) state health numbers they cannot '
    'be trusted with. This project develops an explainable, safety-aware system that estimates daily fall risk from '
    'smart-ring data and explains it through a conversational agent.',
    'A Flutter and Android application collects heart rate, heart-rate variability, blood oxygen, skin temperature, '
    'sleep, stress and step data from a Bluetooth smart ring and stores them in Supabase. A deterministic fall-risk '
    'engine compares each signal with the user’s own 28-day median baseline, converts robust z-score deviations into '
    'strain through a dead-zone mapping, aggregates them into physiology, recovery, motion and fall-history layers, and '
    'combines the layers with weights derived from published odds ratios (λ ∝ ln OR). For women, baselines are matched '
    'to the menstrual-cycle phase. Every point of the resulting Fall Risk Score is attributed to a measurement. An '
    'agent then explains the score: it routes each question to the data it needs, fuses keyword, LLM and ring '
    'fall-event signals to detect emergencies, and checks every number in its reply against the user’s data.',
    'On 11 scenarios the full agent detected all three emergencies, including one visible only through the ring’s fall '
    'event, with no false alarms, and achieved a strict numeric grounding of 0.979 against 0.723 for a plain LLM. On '
    'the real PhysioNet LTMM dataset of 73 older adults, an untrained gait-instability index reached an AUC of 0.686, '
    'comparable to the clinical Timed Up and Go test (0.683). Cycle-aware baselines reduced physiology risk on normal '
    'luteal days by 43%. The work shows that an untrained, evidence-weighted engine can give transparent fall-risk '
    'estimates whose every number can be traced and verified.',
]
KEYWORDS = ('Fall-risk prediction, smart ring, explainable AI, personal baselines, LLM agents, grounding, '
            'safety fusion, gait analysis, menstrual cycle')

ACK = [
    f'It is my pleasure to express with a deep sense of gratitude to my project guide, **{GUIDE}**, School of '
    'Electronics Engineering (SENSE), Vellore Institute of Technology, Chennai, for the constant guidance, continual '
    'encouragement and understanding extended to me throughout this work. The advice to go deeper into signal '
    'processing shaped the gait-analysis work in this report.',
    'I sincerely express my gratitude to **Dr. Ravi Sankar A**, Dean, SENSE; **Dr. Mohanaprasad K**, Associate Dean '
    '(Academics), SENSE; and **Dr. Chitra K**, Associate Dean (Research), SENSE, for providing the necessary facilities '
    'and for their constant encouragement and support throughout the project.',
    'I also extend my heartfelt thanks to **Dr. Vijayakumar P**, Head of the Department, for the continuous guidance '
    'and support during the course of this project, and to the review panel members for their feedback at each review.',
    'I thank the creators of the PhysioNet Long Term Movement Monitoring Database for making their data openly '
    'available, which allowed the methods to be validated on real recordings.',
    'I also take this opportunity to thank all the faculty of the School for their support and the knowledge imparted '
    'throughout the course. I thank my parents, family and friends for their support throughout the project and for '
    'the opportunity they provided me to undergo this course in such a prestigious institution.',
]

STANDARDS = [
    ('1. Health Software and Risk Management', [
        ('IEC 62304 – Medical device software: software life-cycle processes',
         'Guided the structured development, unit testing and traceability of the fall-risk engine and agent.'),
        ('ISO 14971 – Application of risk management to medical devices',
         'Used to reason about hazards such as missed emergencies and false alarms, which shaped the tri-modal '
         'safety fusion and the asymmetric routing.'),
        ('IEC 82304-1 – Health software: general requirements for product safety',
         'Informed the decision that the system gives screening estimates only and never a diagnosis.'),
    ]),
    ('2. Wireless Communication and Personal Health Devices', [
        ('Bluetooth Core Specification v5.x (Bluetooth Low Energy)',
         'Link between the smart ring and the phone for measurements and history download.'),
        ('ISO/IEEE 11073 – Personal health device communication',
         'Reference for naming and units of vital-sign data exchanged between device and application.'),
    ]),
    ('3. Data Protection and Security', [
        ('ISO/IEC 27001 – Information security management systems',
         'Reference for protecting stored biometric data and access credentials.'),
        ('Digital Personal Data Protection Act, 2023 (India)',
         'Health readings are personal data; consent, purpose limitation and deletion on logout were applied.'),
        ('RFC 8446 (TLS 1.3) and RFC 7519 (JSON Web Token)',
         'Encrypted transport to Supabase and token-based user authentication.'),
    ]),
    ('4. Artificial Intelligence and Software Quality', [
        ('ISO/IEC 23894 – Artificial intelligence: guidance on risk management',
         'Applied to the LLM components: the score is never generated by the LLM and every number is verified.'),
        ('ISO/IEC 25010 – Systems and software quality models',
         'Quality attributes (reliability, maintainability, usability) used when reviewing the application.'),
    ]),
    ('5. Reporting of Prediction Models', [
        ('TRIPOD statement – Transparent reporting of a multivariable prediction model',
         'Followed when reporting the LTMM experiments: pre-specified models, all results reported, '
         'subject-wise validation and stated limitations.'),
    ]),
]

SDG_ROWS = [
    ('SDG 3 – Good Health and Well-being',
     'Daily fall-risk estimates and emergency detection support older adults living independently.',
     'Earlier warning of rising fall risk and faster escalation after a fall can reduce injury and hospital stays.'),
    ('SDG 5 – Gender Equality',
     'Cycle-aware baselines stop normal menstrual-cycle changes from being flagged as risk.',
     'Fairer risk estimates for women, who are otherwise judged against a cycle-blind baseline.'),
    ('SDG 9 – Industry, Innovation and Infrastructure',
     'Combines a low-cost wearable, a cloud database and an explainable AI agent into one system.',
     'A reusable, open design for trustworthy health AI on consumer hardware.'),
    ('SDG 10 – Reduced Inequalities',
     'Runs on an affordable ring and phone, with plain-language explanations of every score.',
     'Makes continuous risk monitoring accessible beyond clinical settings.'),
]

ACRONYMS = [
    ('AI', 'Artificial Intelligence'), ('API', 'Application Programming Interface'),
    ('AP', 'Anteroposterior (acceleration axis)'), ('AUC', 'Area Under the ROC Curve'),
    ('BLE', 'Bluetooth Low Energy'), ('BP', 'Blood Pressure'), ('CI', 'Confidence Interval'),
    ('CV', 'Coefficient of Variation / Cross-Validation'), ('FH', 'Fall History (layer)'),
    ('FRS', 'Fall Risk Score'), ('HR', 'Heart Rate'), ('HRV', 'Heart Rate Variability'),
    ('IMU', 'Inertial Measurement Unit'), ('JSON', 'JavaScript Object Notation'),
    ('LLM', 'Large Language Model'), ('LTMM', 'Long Term Movement Monitoring (database)'),
    ('MAD', 'Median Absolute Deviation'), ('ML', 'Machine Learning / Mediolateral'),
    ('MO', 'Motion (layer)'), ('OR', 'Odds Ratio'), ('P', 'Physiology (layer)'),
    ('PPG', 'Photoplethysmography'), ('RAG', 'Retrieval-Augmented Generation'), ('RC', 'Recovery (layer)'),
    ('REST', 'Representational State Transfer'), ('RHR', 'Resting Heart Rate'),
    ('ROC', 'Receiver Operating Characteristic'), ('RR', 'Risk Ratio'),
    ('SDG', 'Sustainable Development Goal'), ('SpO₂', 'Peripheral Oxygen Saturation'),
    ('SQL', 'Structured Query Language'), ('TUG', 'Timed Up and Go (test)'), ('UI', 'User Interface'),
]


def front_matter(w, PAGES):
    pg = lambda k: PAGES.get(k, '')  # noqa: E731
    # Abstract
    w.front_title('Abstract')
    for t in ABSTRACT:
        w.body(t)
    w.body(f'**Keywords:** {KEYWORDS}')
    # Acknowledgements
    w.front_title('Acknowledgements')
    for t in ACK:
        w.body(t)
    w.spacer(240)
    w.body('Place: Chennai', after=40)
    w.body('Date:', after=40)
    w.body(f'**{ME[0].title()}** ({ME[1]})')
    # Codes and standards
    w.front_title('Codes and Standards')
    w.body(f'**Project Title:** {TITLE}')
    w.body('The system is a research prototype that gives screening estimates; it is not a certified medical device. '
           'The standards below guided its design, development, data handling and reporting.')
    for head, items in STANDARDS:
        w.h3(head)
        for name, use in items:
            w.bullets([f'**{name}** – {use}'])
    # SDGs
    w.front_title('Mapping of Sustainable Development Goals (SDGs)')
    w.body(f'**Project Title:** {TITLE}')
    w.table(['Mapped SDG', 'Justification', 'Expected Impact'], SDG_ROWS, [4.2, 6.0, 5.6], size=10)
    # TOC
    w.front_title('Table of Contents')
    for name in ('Declaration', 'Certificate', 'Abstract', 'Acknowledgements', 'Codes and Standards',
                 'Mapping of Sustainable Development Goals (SDGs)', 'List of Figures', 'List of Tables',
                 'List of Acronyms'):
        w.toc_line(name, pg(f'FM:{name}'), italic_page=True)
    prev_level = None
    for level, num, title in HEADS:
        if level == 0:
            label = f'{num} {title}' if num else title
            w.toc_line(label, pg(f'H:{num or title}'), before=100)
        else:
            w.toc_line(f'{num} {title}', pg(f'H:{num}'), indent=480 * level)
        prev_level = level
    # Lists
    w.front_title('List of Figures')
    for num, cap in FIGS:
        w.toc_line(f'{num} {cap}', pg(f'F:{num}'))
    w.front_title('List of Tables')
    for num, cap in TABS:
        w.toc_line(f'{num} {cap}', pg(f'T:{num}'))
    w.front_title('List of Acronyms')
    w.table(['Acronym', 'Full Form'], ACRONYMS, [3.0, 9.5], size=10)


def chapters(w, PAGES):
    import ch_intro
    import ch_method
    import ch_results
    ch_intro.write(w)
    ch_method.write(w)
    ch_results.write(w)
