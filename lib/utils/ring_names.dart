/// Names that belong to this manufacturer's rings and bands.
///
/// A single-letter prefix such as "R" also matches headphones (Realme, Redmi,
/// Raycon). Audio products are rejected even when a prefix would otherwise hit,
/// so a previously bonded headset cannot show up as the ring.
const ringNamePrefixes = <String>[
  'R02',
  'R03',
  'R05',
  'R06',
  'R08',
  'R09',
  'R10',
  'R11',
  'R12',
  'R20',
  'R21',
  'R3L',
  'Q_',
  'O_',
  'QC',
  'T80',
  'T90',
  'T91',
  'T93',
  'T95',
  'TW68',
  'S9',
  'C60',
  'C66',
  'C67',
  'C68',
  'C80',
  'C86',
  'C88',
  'C96',
  'WXB_W4',
  'WA',
  'SUNDR',
];

const _audioNameFragments = <String>[
  'bud',
  'headphone',
  'headset',
  'airpod',
  'earpod',
  'earbud',
  'tws',
  'freebud',
  'qcy',
  'realme',
  'redmi',
  'oneplus',
  'galaxy',
  'sony',
  'jbl',
  'boat',
  'soundcore',
  'nothing',
  'wh-',
  'wf-',
  'beats',
  'bose',
  'sennheiser',
  'anker',
  'rockerz',
  'pixel bud',
];

bool isRingDeviceName(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return false;
  final lower = trimmed.toLowerCase();
  for (final fragment in _audioNameFragments) {
    if (lower.contains(fragment)) return false;
  }
  final upper = trimmed.toUpperCase();
  for (final prefix in ringNamePrefixes) {
    if (upper.startsWith(prefix)) return true;
  }
  return false;
}
