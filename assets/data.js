// ============================================================
// Static reference data for the interactive map.
//
// Everything here is pure data — palette, labels, hub coordinates,
// hand-digitized route polylines. Pulled out of article.js so that
// editing route geometry or palette doesn't mean scrolling past
// hundreds of lines of map/filter logic.
//
// Exposed as global vars (no module wrapper) because article.js is
// loaded as a plain <script> after this file and reads them directly.
//
// Contents:
//   ROUTE_COLORS         — corridor name → hex color (drives both the
//                          incident dot color and the overlay polylines).
//   ROUTE_SHORT_LABELS   — corridor name → display label for the legend.
//   CAUSE_LABELS         — cause-of-death code → human label (tooltip).
//   ORIGIN_LABELS        — origin region code → human label (tooltip).
//   PRECISION_FLAGS      — date precision code → tooltip caveat.
//   HUBS                 — open-circle migration hubs on the map.
//   ROUTE_LINES          — polylines for each corridor (major / minor).
// ============================================================


// ---- Migration-corridor palette ---------------------------------------
// Death dots inherit color from the sea corridor they belong to (only the
// four sea-route values appear in the IOM data); overlaid polylines
// additionally cover the East Africa and Other land corridors as
// geographic context, following the FT/Mixed-Migration-Centre style
// reference figure.
var ROUTE_COLORS = {
  'Western Africa / Atlantic route to the Canary Islands': '#7E3FAF',
  'Western Mediterranean':                                 '#E97A2E',
  'Central Mediterranean':                                 '#2B7CC9',
  'Eastern Mediterranean':                                 '#3FA64A',
  'East Africa':                                           '#C13838',
  'Other':                                                 '#8C8C8C'
};
var ROUTE_SHORT_LABELS = {
  'Western Africa / Atlantic route to the Canary Islands': 'West Africa',
  'Western Mediterranean':                                 'Western Mediterranean',
  'Central Mediterranean':                                 'Central Mediterranean',
  'Eastern Mediterranean':                                 'Eastern Mediterranean',
  'East Africa':                                           'East Africa',
  'Other':                                                 'Other'
};


// ---- Cause-of-death labels (tooltip only) -----------------------------
// Color is now driven by route, not by cause; the cause filter dropdown
// still works as a filter, but no per-cause swatches appear on the map.
var CAUSE_LABELS = {
  drowning: 'Drowning',
  vehicle:  'Vehicle / transport',
  violence: 'Violence',
  exposure: 'Exposure / cold / starvation',
  sickness: 'Sickness',
  other:    'Other / unknown'
};


// ---- Origin region labels (tooltip) -----------------------------------
var ORIGIN_LABELS = {
  sub_saharan_africa: 'Sub-Saharan Africa',
  northern_africa:    'Northern Africa',
  middle_east:        'Middle East / Levant',
  south_central_asia: 'South / Central Asia',
  europe:             'Europe',
  other:              'Other',
  unknown:            'Unknown'
};


// ---- Date-precision flags --------------------------------------------
// IOM rows are always 'day'-precise. UNITED Against Refugee Deaths labels
// each row's precision; anything other than 'day' triggers an
// "approximate" caveat on the tooltip.
var PRECISION_FLAGS = {
  month:     'Date approximate — month only',
  year_only: 'Date approximate — year only',
  imprecise: 'Date approximate — exact day unknown'
};


// ---- Main migration hubs (open circles on the map) -------------------
// Mirrors the open-circle hubs in the reference figure (border-crossing
// nodes and big sending/receiving cities), not every black-dot route
// city. Tooltip direction is tuned per hub so labels don't collide.
var HUBS = [
  { name: 'Istanbul',     latlng: [41.0082, 28.9784], dir: 'right' },
  { name: 'Cairo',        latlng: [30.0444, 31.2357], dir: 'right' },
  { name: 'Addis Ababa',  latlng: [ 9.0250, 38.7470], dir: 'right' },
  { name: 'Tripoli',      latlng: [32.8872, 13.1913], dir: 'top'   },
  { name: 'Agadez',       latlng: [16.9740,  7.9883], dir: 'right' },
  { name: 'Tamanrasset',  latlng: [22.7850,  5.5228], dir: 'left'  },
  { name: 'Ouargla',      latlng: [31.9489,  5.3231], dir: 'right' },
  { name: 'Maghnia',      latlng: [34.8633, -1.7400], dir: 'right' },
  { name: 'Oujda',        latlng: [34.6810, -1.9080], dir: 'left'  }
];


// ---- Route polylines (hand-digitized from the reference figure) -------
// Geometry is approximate and represents the dominant flow direction for
// each corridor — actual journeys are individual and varied. Each entry:
//
//   { route: <key in ROUTE_COLORS>, major: <bool>, coords: [[lat,lon], …] }
//
// `major: true` renders as a thick line, `false` as a thinner connecting
// (minor) line. Coordinates are [lat, lon] of well-known waypoint cities
// so the polylines bend through real transit hubs rather than cutting
// straight across the Sahara or Mediterranean.
var ROUTE_LINES = [
  // ============================================================
  // WEST AFRICA  (purple) — coastal & inland feeders + Atlantic arc
  // to the Canary Islands. Data key kept verbose for backwards
  // compat with the GeoJSON property values.
  // ============================================================
  // Atlantic crossing: Senegal/Mauritania coast → out into Atlantic →
  // Canary Islands (the long curving offshore route)
  { route: 'Western Africa / Atlantic route to the Canary Islands', major: true, coords: [
    [14.6928, -17.4467],   // Dakar
    [18.0735, -15.9582],   // Nouakchott
    [20.9410, -17.0379],   // Nouadhibou
    [23.6900, -17.5000],   // offshore Dakhla
    [26.5000, -17.8000],   // mid-Atlantic curve
    [28.1235, -15.4363]    // Las Palmas (Canary Islands)
  ]},
  // Coastal land route: Senegal → Mauritania → W. Sahara → Morocco
  { route: 'Western Africa / Atlantic route to the Canary Islands', major: true, coords: [
    [14.6928, -17.4467],   // Dakar
    [18.0735, -15.9582],   // Nouakchott
    [20.9410, -17.0379],   // Nouadhibou
    [23.6848, -15.9579],   // Dakhla
    [27.1536, -13.2033],   // Layoune
    [28.4380, -11.1030],   // Tan-Tan
    [30.4202,  -9.5982]    // Agadir
  ]},
  // Inland Sahel feeder: Banjul → Bamako → Ouagadougou → Niamey
  { route: 'Western Africa / Atlantic route to the Canary Islands', major: false, coords: [
    [13.4549, -16.5790],   // Banjul
    [12.6392,  -8.0029],   // Bamako
    [12.3714,  -1.5197],   // Ouagadougou
    [13.5117,   2.1098]    // Niamey
  ]},
  // West African coast: Bissau → Conakry → Freetown → Monrovia
  { route: 'Western Africa / Atlantic route to the Canary Islands', major: false, coords: [
    [11.8636, -15.5977],   // Bissau
    [ 9.5092, -13.7122],   // Conakry
    [ 8.4844, -13.2344],   // Freetown
    [ 6.3007, -10.7969]    // Monrovia
  ]},
  // Saharan crossover: Bamako → Gao (toward Niger)
  { route: 'Western Africa / Atlantic route to the Canary Islands', major: false, coords: [
    [12.6392, -8.0029],    // Bamako
    [14.4843, -4.1956],    // Mopti
    [16.2735, -0.0445]     // Gao
  ]},
  // Coastal short hop: Nouadhibou → offshore feeder to Canary arc
  { route: 'Western Africa / Atlantic route to the Canary Islands', major: false, coords: [
    [16.7700, -22.9000],   // open Atlantic
    [22.0000, -20.5000],
    [26.0000, -17.5000]
  ]},

  // ============================================================
  // WESTERN MEDITERRANEAN  (orange)
  // ============================================================
  // Major spine: Tamanrasset → Ouargla → Maghnia (trans-Sahara)
  { route: 'Western Mediterranean', major: true, coords: [
    [22.7850,  5.5228],    // Tamanrasset
    [27.8743,  5.7000],    // mid-Sahara
    [31.9489,  5.3231],    // Ouargla
    [34.8633, -1.7400]     // Maghnia
  ]},
  // Sea crossing west: Maghnia → Oujda → Tangier → Algeciras
  { route: 'Western Mediterranean', major: true, coords: [
    [34.8633, -1.7400],    // Maghnia
    [34.6810, -1.9080],    // Oujda
    [35.7595, -5.8340],    // Tangier
    [36.1408, -5.4561]     // Algeciras (Spain)
  ]},
  // Sea crossing east: Oran → Almería → Madrid
  { route: 'Western Mediterranean', major: true, coords: [
    [35.6976, -0.6337],    // Oran
    [36.8381, -2.4597],    // Almería
    [40.4168, -3.7038]     // Madrid
  ]},
  // Algerian coastal: Algiers → Oran → Maghnia
  { route: 'Western Mediterranean', major: false, coords: [
    [36.7538,  3.0588],    // Algiers
    [35.6976, -0.6337],    // Oran
    [34.8633, -1.7400]     // Maghnia
  ]},
  // Saharan feeder: Agadez → Tamanrasset (shared trans-Sahara node)
  { route: 'Western Mediterranean', major: false, coords: [
    [16.9740,  7.9883],    // Agadez
    [19.5000,  6.5000],    // mid-Sahara
    [22.7850,  5.5228]     // Tamanrasset
  ]},
  // Algiers approach: Tamanrasset → Algiers (alt western branch)
  { route: 'Western Mediterranean', major: false, coords: [
    [22.7850,  5.5228],    // Tamanrasset
    [29.0500,  3.9000],    // Sahara
    [32.7700,  3.3000],    // Laghouat area
    [36.7538,  3.0588]     // Algiers
  ]},

  // ============================================================
  // CENTRAL MEDITERRANEAN  (blue)
  // ============================================================
  // Major spine: Agadez → Dirkou → Al Qatrun → Sebha → Tripoli
  { route: 'Central Mediterranean', major: true, coords: [
    [16.9740,  7.9883],    // Agadez
    [18.9684, 12.9293],    // Dirkou
    [22.0000, 14.0000],    // Sahara waypoint
    [24.9381, 14.6489],    // Al Qatrun
    [27.0377, 14.4283],    // Sebha
    [30.5000, 13.7000],    // central Libyan desert
    [32.8872, 13.1913]     // Tripoli
  ]},
  // Sea crossing main: Tripoli → Lampedusa → Sicily (Catania)
  { route: 'Central Mediterranean', major: true, coords: [
    [32.8872, 13.1913],    // Tripoli
    [34.5000, 12.8000],
    [35.5119, 12.6033],    // Lampedusa
    [37.0759, 14.7300],    // Pozzallo
    [37.5079, 15.0830]     // Catania
  ]},
  // Alternate trans-Sahara: Agadez → Tamanrasset → Sebha
  { route: 'Central Mediterranean', major: true, coords: [
    [16.9740,  7.9883],    // Agadez
    [22.7850,  5.5228],    // Tamanrasset
    [25.5000,  9.0000],    // Sahara waypoint
    [27.0377, 14.4283]     // Sebha
  ]},
  // Tunisian alt: Tamanrasset → Ghadames → Tripoli
  { route: 'Central Mediterranean', major: false, coords: [
    [22.7850,  5.5228],    // Tamanrasset
    [27.0000,  8.5000],    // mid-Sahara
    [30.1346,  9.5008],    // Ghadames
    [32.8872, 13.1913]     // Tripoli
  ]},
  // Tunisian sea: Tunis → Lampedusa
  { route: 'Central Mediterranean', major: false, coords: [
    [33.8869,  9.5375],    // Sfax area
    [36.8065, 10.1815],    // Tunis
    [35.5119, 12.6033]     // Lampedusa
  ]},
  // Southern feeder: Lagos → Abuja → Niamey → Agadez
  { route: 'Central Mediterranean', major: false, coords: [
    [ 6.5244,  3.3792],    // Lagos
    [ 9.0820,  7.4000],    // Abuja
    [13.5117,  2.1098],    // Niamey
    [16.9740,  7.9883]     // Agadez
  ]},
  // Sahel west feeder: Niamey → Agadez (separate connector)
  { route: 'Central Mediterranean', major: false, coords: [
    [13.5117,  2.1098],    // Niamey
    [15.4500,  5.5000],
    [16.9740,  7.9883]     // Agadez
  ]},
  // Malta crossing: Tripoli → Malta
  { route: 'Central Mediterranean', major: false, coords: [
    [32.8872, 13.1913],    // Tripoli
    [35.9000, 14.5100]     // Malta
  ]},

  // ============================================================
  // EASTERN MEDITERRANEAN  (green)
  // ============================================================
  // Asia approach: Tehran → eastern Turkey → Ankara → Istanbul
  { route: 'Eastern Mediterranean', major: true, coords: [
    [35.6892, 51.3890],    // Tehran
    [38.5012, 43.3729],    // Van
    [39.9208, 41.2769],    // Erzurum
    [39.9334, 32.8597],    // Ankara
    [41.0082, 28.9784]     // Istanbul
  ]},
  // Iraq approach: Baghdad → Mosul → eastern Turkey → Istanbul
  { route: 'Eastern Mediterranean', major: true, coords: [
    [33.3152, 44.3661],    // Baghdad
    [36.3450, 43.1450],    // Mosul
    [37.9145, 40.2306],    // Diyarbakır
    [37.0662, 37.3833],    // Gaziantep
    [39.9334, 32.8597],    // Ankara
    [41.0082, 28.9784]     // Istanbul
  ]},
  // Levantine: Damascus → Aleppo → Gaziantep → Istanbul
  { route: 'Eastern Mediterranean', major: true, coords: [
    [33.5138, 36.2765],    // Damascus
    [36.2021, 37.1343],    // Aleppo
    [37.0662, 37.3833],    // Gaziantep
    [41.0082, 28.9784]     // Istanbul
  ]},
  // Aegean sea crossings: Istanbul → Izmir → Lesbos / Samos
  { route: 'Eastern Mediterranean', major: true, coords: [
    [41.0082, 28.9784],    // Istanbul
    [39.6500, 27.8800],    // Ayvalık area
    [38.4192, 27.1287],    // Izmir
    [39.1100, 26.5550]     // Lesbos
  ]},
  { route: 'Eastern Mediterranean', major: true, coords: [
    [38.4192, 27.1287],    // Izmir
    [37.7900, 26.9700],    // Samos
    [36.8920, 27.2900]     // Kos
  ]},
  // Balkans: Istanbul → Edirne → Sofia → Belgrade → Vienna
  { route: 'Eastern Mediterranean', major: true, coords: [
    [41.0082, 28.9784],    // Istanbul
    [41.6770, 26.5557],    // Edirne
    [42.6977, 23.3219],    // Sofia
    [44.7866, 20.4489]     // Belgrade
  ]},
  // Cyprus arc: Lebanon → Cyprus → mainland Greece
  { route: 'Eastern Mediterranean', major: false, coords: [
    [33.8938, 35.5018],    // Beirut
    [35.1264, 33.4299],    // Nicosia (Cyprus)
    [37.9838, 23.7275]     // Athens
  ]},

  // ============================================================
  // EAST AFRICA  (red) — Horn of Africa, trans-Sudan, Red Sea
  // ============================================================
  // East African feeder: Nairobi → Addis Ababa
  { route: 'East Africa', major: true, coords: [
    [-1.2921, 36.8219],    // Nairobi
    [ 4.0500, 38.5000],    // northern Kenya
    [ 9.0250, 38.7470]     // Addis Ababa
  ]},
  // Nile Valley connector: Addis Ababa → Khartoum → Aswan → Cairo
  // (thinner than the trans-Sahel direct route to Tripoli, which
  // carries the bulk of the East-Africa flow in the figure)
  { route: 'East Africa', major: false, coords: [
    [ 9.0250, 38.7470],    // Addis Ababa
    [15.4540, 36.4000],    // Kassala
    [15.5007, 32.5599],    // Khartoum
    [21.8000, 31.3400],    // Wadi Halfa
    [24.0889, 32.8998],    // Aswan
    [30.0444, 31.2357]     // Cairo
  ]},
  // Trans-Libya coastal: Cairo → Salloum → Tobruk → Benghazi → Tripoli
  // (the long red line going west across N. Africa in the figure)
  { route: 'East Africa', major: true, coords: [
    [30.0444, 31.2357],    // Cairo
    [31.5500, 25.1500],    // Salloum (Egypt-Libya border)
    [32.0826, 23.9763],    // Tobruk
    [32.1167, 20.0667],    // Benghazi
    [32.8872, 13.1913]     // Tripoli
  ]},
  // Trans-Sahel direct Addis → Tripoli (bypassing Cairo / the Nile
  // Valley): Addis Ababa → Khartoum → Kufra → Al Qatrun → Sebha →
  // Tripoli. This is the thick red line in the reference figure that
  // cuts west across southern Sudan/Chad/Libya.
  { route: 'East Africa', major: true, coords: [
    [ 9.0250, 38.7470],    // Addis Ababa
    [15.5007, 32.5599],    // Khartoum
    [19.5000, 28.0000],    // Sudanese desert (Northern Darfur edge)
    [24.1816, 23.2854],    // Kufra (SE Libya oasis)
    [24.9381, 14.6489],    // Al Qatrun
    [27.0377, 14.4283],    // Sebha
    [32.8872, 13.1913]     // Tripoli
  ]},
  // Sinai exit: Cairo → Suez → Sinai → Israel border
  { route: 'East Africa', major: true, coords: [
    [30.0444, 31.2357],    // Cairo
    [29.9700, 32.5300],    // Suez
    [29.5577, 34.9519],    // Eilat / Sinai border
    [31.0461, 34.8516]     // southern Israel
  ]},
  // Arabian Peninsula → Israel: Mecca → Medina → Tabuk → Aqaba → Eilat
  { route: 'East Africa', major: true, coords: [
    [21.3891, 39.8579],    // Mecca
    [24.4709, 39.6111],    // Medina
    [28.3835, 36.5662],    // Tabuk
    [29.5320, 35.0080],    // Aqaba (Jordan)
    [29.5577, 34.9519],    // Eilat (Israel)
    [31.7683, 35.2137]     // Jerusalem area
  ]},
  // Horn → Yemen: Addis Ababa → Djibouti → Aden → Sanaa
  { route: 'East Africa', major: true, coords: [
    [ 9.0250, 38.7470],    // Addis Ababa
    [11.5886, 43.1453],    // Djibouti
    [12.7800, 45.0367],    // Aden
    [15.3694, 44.1910]     // Sanaa
  ]},
  // Yemen → Saudi Arabia: Sanaa → Mecca → Riyadh
  { route: 'East Africa', major: false, coords: [
    [15.3694, 44.1910],    // Sanaa
    [21.3891, 39.8579],    // Mecca
    [24.7136, 46.6753]     // Riyadh
  ]},
  // Eritrea/Somalia connectors
  { route: 'East Africa', major: false, coords: [
    [15.3229, 38.9251],    // Asmara
    [15.4540, 36.4000],    // Kassala
    [15.5007, 32.5599]     // Khartoum
  ]},
  // Horn of Africa spine: Mogadishu → Hargeisa → Dire Dawa → Addis Ababa
  // (Somali plateau corridor — primary transit from Somalia/Somaliland
  // into Ethiopia and onward toward Sudan or Yemen)
  { route: 'East Africa', major: true, coords: [
    [ 2.0469, 45.3182],    // Mogadishu
    [ 5.5000, 44.0000],    // central Somalia
    [ 9.5611, 44.0680],    // Hargeisa (Somaliland)
    [ 9.5907, 41.8662],    // Dire Dawa
    [ 9.0250, 38.7470]     // Addis Ababa
  ]},

  // ============================================================
  // OTHER  (grey) — Northern & Eastern European corridors that
  // don't terminate at a Mediterranean sea crossing
  // ============================================================
  // Eastern Europe → West: Moscow → Minsk → Warsaw → Berlin
  { route: 'Other', major: true, coords: [
    [55.7558, 37.6173],    // Moscow
    [53.9000, 27.5667],    // Minsk
    [52.2297, 21.0122],    // Warsaw
    [52.5200, 13.4050]     // Berlin
  ]},
  // Berlin → Hamburg → Copenhagen → Stockholm
  { route: 'Other', major: true, coords: [
    [52.5200, 13.4050],    // Berlin
    [53.5511,  9.9937],    // Hamburg
    [55.6761, 12.5683],    // Copenhagen
    [59.3293, 18.0686]     // Stockholm
  ]},
  // Central Europe → Paris: Vienna → Munich → Paris
  { route: 'Other', major: true, coords: [
    [48.2082, 16.3738],    // Vienna
    [48.1351, 11.5820],    // Munich
    [48.8566,  2.3522]     // Paris
  ]},
  // Channel: Paris → Calais → London
  { route: 'Other', major: true, coords: [
    [48.8566,  2.3522],    // Paris
    [50.9513,  1.8587],    // Calais
    [51.5074, -0.1278]     // London
  ]},
  // Kiev → Warsaw connector
  { route: 'Other', major: false, coords: [
    [50.4501, 30.5234],    // Kiev
    [52.2297, 21.0122]     // Warsaw
  ]},
  // Balkans alt: Belgrade → Budapest → Vienna
  { route: 'Other', major: false, coords: [
    [44.7866, 20.4489],    // Belgrade
    [47.4979, 19.0402],    // Budapest
    [48.2082, 16.3738]     // Vienna
  ]}
];
