-- cities.lua
-- Curated city list for v1.0 (ADR-0003), targeted by audience + latitude
-- spread rather than equal counts per country. Large countries with big Muslim
-- populations and real latitude range get more entries (DE/FR/UK/TR/RU); small
-- or compact countries get 1-2 (their whole territory shares ~one schedule).
-- A city earns a row only if it serves a distinct audience OR differs enough in
-- latitude to shift times noticeably. Balkans kept well-covered for the target
-- audience; Russia includes eastern fixed-offset zones.
-- Fields: name, country, latitude, longitude (deg, 4 dp ~ 11 m),
--   baseUtcOffset (standard-time offset in MINUTES), dstRule ("EU" | "none").
-- Names are plain ASCII (display-diacritics field deferred). Coordinates are
-- city-centre values; prayer timing needs nothing finer.
-- NOTE: no city above the Arctic circle (~66.5N) -- PolarCircleResolution is
-- out of scope (ADR-0003); the northernmost here is ~60N (Helsinki/St. P.).

local CITIES = {
  -- ===== UTC+0, EU DST =====
  { name = "London", country = "United Kingdom", latitude = 51.5074, longitude = -0.1278, baseUtcOffset = 0, dstRule = "EU" },
  { name = "Birmingham", country = "United Kingdom", latitude = 52.4862, longitude = -1.8904, baseUtcOffset = 0, dstRule = "EU" },
  { name = "Manchester", country = "United Kingdom", latitude = 53.4808, longitude = -2.2426, baseUtcOffset = 0, dstRule = "EU" },
  { name = "Bradford", country = "United Kingdom", latitude = 53.7960, longitude = -1.7594, baseUtcOffset = 0, dstRule = "EU" },
  { name = "Glasgow", country = "United Kingdom", latitude = 55.8642, longitude = -4.2518, baseUtcOffset = 0, dstRule = "EU" },
  { name = "Dublin", country = "Ireland", latitude = 53.3498, longitude = -6.2603, baseUtcOffset = 0, dstRule = "EU" },
  { name = "Lisbon", country = "Portugal", latitude = 38.7223, longitude = -9.1393, baseUtcOffset = 0, dstRule = "EU" },

  -- ===== UTC+1, EU DST =====
  -- France
  { name = "Paris", country = "France", latitude = 48.8566, longitude = 2.3522, baseUtcOffset = 60, dstRule = "EU" },
  { name = "Lille", country = "France", latitude = 50.6292, longitude = 3.0573, baseUtcOffset = 60, dstRule = "EU" },
  { name = "Strasbourg", country = "France", latitude = 48.5734, longitude = 7.7521, baseUtcOffset = 60, dstRule = "EU" },
  { name = "Lyon", country = "France", latitude = 45.7640, longitude = 4.8357, baseUtcOffset = 60, dstRule = "EU" },
  { name = "Marseille", country = "France", latitude = 43.2965, longitude = 5.3698, baseUtcOffset = 60, dstRule = "EU" },
  { name = "Toulouse", country = "France", latitude = 43.6047, longitude = 1.4442, baseUtcOffset = 60, dstRule = "EU" },
  -- Spain
  { name = "Madrid", country = "Spain", latitude = 40.4168, longitude = -3.7038, baseUtcOffset = 60, dstRule = "EU" },
  { name = "Barcelona", country = "Spain", latitude = 41.3874, longitude = 2.1686, baseUtcOffset = 60, dstRule = "EU" },
  { name = "Malaga", country = "Spain", latitude = 36.7213, longitude = -4.4214, baseUtcOffset = 60, dstRule = "EU" },
  -- Benelux
  { name = "Amsterdam", country = "Netherlands", latitude = 52.3676, longitude = 4.9041, baseUtcOffset = 60, dstRule = "EU" },
  { name = "Rotterdam", country = "Netherlands", latitude = 51.9244, longitude = 4.4777, baseUtcOffset = 60, dstRule = "EU" },
  { name = "Brussels", country = "Belgium", latitude = 50.8503, longitude = 4.3517, baseUtcOffset = 60, dstRule = "EU" },
  -- Germany
  { name = "Hamburg", country = "Germany", latitude = 53.5511, longitude = 9.9937, baseUtcOffset = 60, dstRule = "EU" },
  { name = "Berlin", country = "Germany", latitude = 52.5200, longitude = 13.4050, baseUtcOffset = 60, dstRule = "EU" },
  { name = "Cologne", country = "Germany", latitude = 50.9375, longitude = 6.9603, baseUtcOffset = 60, dstRule = "EU" },
  { name = "Frankfurt", country = "Germany", latitude = 50.1109, longitude = 8.6821, baseUtcOffset = 60, dstRule = "EU" },
  { name = "Stuttgart", country = "Germany", latitude = 48.7758, longitude = 9.1829, baseUtcOffset = 60, dstRule = "EU" },
  { name = "Munich", country = "Germany", latitude = 48.1351, longitude = 11.5820, baseUtcOffset = 60, dstRule = "EU" },
  -- Alpine / Central
  { name = "Vienna", country = "Austria", latitude = 48.2082, longitude = 16.3738, baseUtcOffset = 60, dstRule = "EU" },
  { name = "Zurich", country = "Switzerland", latitude = 47.3769, longitude = 8.5417, baseUtcOffset = 60, dstRule = "EU" },
  { name = "Prague", country = "Czechia", latitude = 50.0755, longitude = 14.4378, baseUtcOffset = 60, dstRule = "EU" },
  { name = "Warsaw", country = "Poland", latitude = 52.2297, longitude = 21.0122, baseUtcOffset = 60, dstRule = "EU" },
  { name = "Budapest", country = "Hungary", latitude = 47.4979, longitude = 19.0402, baseUtcOffset = 60, dstRule = "EU" },
  -- Italy
  { name = "Milan", country = "Italy", latitude = 45.4642, longitude = 9.1900, baseUtcOffset = 60, dstRule = "EU" },
  { name = "Rome", country = "Italy", latitude = 41.9028, longitude = 12.4964, baseUtcOffset = 60, dstRule = "EU" },
  -- Nordics (EU)
  { name = "Gothenburg", country = "Sweden", latitude = 57.7089, longitude = 11.9746, baseUtcOffset = 60, dstRule = "EU" },
  { name = "Stockholm", country = "Sweden", latitude = 59.3293, longitude = 18.0686, baseUtcOffset = 60, dstRule = "EU" },
  { name = "Malmo", country = "Sweden", latitude = 55.6050, longitude = 13.0038, baseUtcOffset = 60, dstRule = "EU" },
  { name = "Oslo", country = "Norway", latitude = 59.9139, longitude = 10.7522, baseUtcOffset = 60, dstRule = "EU" },
  { name = "Copenhagen", country = "Denmark", latitude = 55.6761, longitude = 12.5683, baseUtcOffset = 60, dstRule = "EU" },
  -- Balkans (target audience: kept well-covered)
  { name = "Zagreb", country = "Croatia", latitude = 45.8150, longitude = 15.9819, baseUtcOffset = 60, dstRule = "EU" },
  { name = "Tuzla", country = "Bosnia and Herzegovina", latitude = 44.5384, longitude = 18.6766, baseUtcOffset = 60, dstRule = "EU" },
  { name = "Zenica", country = "Bosnia and Herzegovina", latitude = 44.2017, longitude = 17.9047, baseUtcOffset = 60, dstRule = "EU" },
  { name = "Sarajevo", country = "Bosnia and Herzegovina", latitude = 43.8563, longitude = 18.4131, baseUtcOffset = 60, dstRule = "EU" },
  { name = "Belgrade", country = "Serbia", latitude = 44.7866, longitude = 20.4489, baseUtcOffset = 60, dstRule = "EU" },
  { name = "Novi Pazar", country = "Serbia", latitude = 43.1367, longitude = 20.5122, baseUtcOffset = 60, dstRule = "EU" },
  { name = "Podgorica", country = "Montenegro", latitude = 42.4304, longitude = 19.2594, baseUtcOffset = 60, dstRule = "EU" },
  { name = "Pristina", country = "Kosovo", latitude = 42.6629, longitude = 21.1655, baseUtcOffset = 60, dstRule = "EU" },
  { name = "Skopje", country = "North Macedonia", latitude = 41.9981, longitude = 21.4254, baseUtcOffset = 60, dstRule = "EU" },
  { name = "Tirana", country = "Albania", latitude = 41.3275, longitude = 19.8187, baseUtcOffset = 60, dstRule = "EU" },

  -- ===== UTC+2, EU DST =====
  { name = "Thessaloniki", country = "Greece", latitude = 40.6401, longitude = 22.9444, baseUtcOffset = 120, dstRule = "EU" },
  { name = "Athens", country = "Greece", latitude = 37.9838, longitude = 23.7275, baseUtcOffset = 120, dstRule = "EU" },
  { name = "Helsinki", country = "Finland", latitude = 60.1699, longitude = 24.9384, baseUtcOffset = 120, dstRule = "EU" },
  { name = "Bucharest", country = "Romania", latitude = 44.4268, longitude = 26.1025, baseUtcOffset = 120, dstRule = "EU" },
  { name = "Sofia", country = "Bulgaria", latitude = 42.6977, longitude = 23.3219, baseUtcOffset = 120, dstRule = "EU" },
  { name = "Kyiv", country = "Ukraine", latitude = 50.4501, longitude = 30.5234, baseUtcOffset = 120, dstRule = "EU" },

  -- ===== UTC+3, no DST (Turkey / western Russia / Belarus) =====
  { name = "Istanbul", country = "Turkey", latitude = 41.0082, longitude = 28.9784, baseUtcOffset = 180, dstRule = "none" },
  { name = "Bursa", country = "Turkey", latitude = 40.1885, longitude = 29.0610, baseUtcOffset = 180, dstRule = "none" },
  { name = "Ankara", country = "Turkey", latitude = 39.9334, longitude = 32.8597, baseUtcOffset = 180, dstRule = "none" },
  { name = "Izmir", country = "Turkey", latitude = 38.4237, longitude = 27.1428, baseUtcOffset = 180, dstRule = "none" },
  { name = "Antalya", country = "Turkey", latitude = 36.8969, longitude = 30.7133, baseUtcOffset = 180, dstRule = "none" },
  { name = "Saint Petersburg", country = "Russia", latitude = 59.9311, longitude = 30.3609, baseUtcOffset = 180, dstRule = "none" },
  { name = "Moscow", country = "Russia", latitude = 55.7558, longitude = 37.6173, baseUtcOffset = 180, dstRule = "none" },
  { name = "Kazan", country = "Russia", latitude = 55.7963, longitude = 49.1088, baseUtcOffset = 180, dstRule = "none" },
  { name = "Minsk", country = "Belarus", latitude = 53.9006, longitude = 27.5590, baseUtcOffset = 180, dstRule = "none" },

  -- ===== UTC+5, no DST (Urals) =====
  { name = "Ufa", country = "Russia", latitude = 54.7388, longitude = 55.9721, baseUtcOffset = 300, dstRule = "none" },
  { name = "Yekaterinburg", country = "Russia", latitude = 56.8389, longitude = 60.6057, baseUtcOffset = 300, dstRule = "none" },

  -- ===== UTC+7, no DST (Siberia) =====
  { name = "Novosibirsk", country = "Russia", latitude = 55.0084, longitude = 82.9357, baseUtcOffset = 420, dstRule = "none" },
}

if PrayerTimesNS then PrayerTimesNS.modules.cities = CITIES end
return CITIES
