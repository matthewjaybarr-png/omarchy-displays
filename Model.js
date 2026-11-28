function clampBrightness(value) {
  var n = Number(value)
  if (!isFinite(n)) return 1
  return Math.max(1, Math.min(100, Math.round(n)))
}

function normalizeScale(scale) {
  var n = parseFloat(String(scale || ""))
  if (!isFinite(n)) return ""
  return String(Math.round(n * 100) / 100)
}

function gcd(a, b) {
  while (b) {
    var remainder = a % b
    a = b
    b = remainder
  }
  return a
}

function cleanScale(scale, width, height) {
  var requested = Number(scale)
  var modeWidth = Number(width)
  var modeHeight = Number(height)
  if (!isFinite(requested) || !isFinite(modeWidth) || !isFinite(modeHeight)
      || requested <= 0 || modeWidth <= 0 || modeHeight <= 0) return ""

  var divisor = gcd(Math.round(modeWidth * 120), Math.round(modeHeight * 120))
  var scaleUnits = Math.round(requested * 120)
  if (scaleUnits > divisor) scaleUnits = divisor
  while (divisor % scaleUnits !== 0) scaleUnits++
  return normalizeScale(scaleUnits / 120)
}

function matchingScaleIndex(scales, currentScale, width, height) {
  var current = Number(currentScale)
  if (!Array.isArray(scales) || !isFinite(current)) return -1

  var bestIndex = -1
  var bestDistance = Infinity
  var normalizedCurrent = normalizeScale(current)
  for (var i = 0; i < scales.length; i++) {
    if (cleanScale(scales[i], width, height) !== normalizedCurrent) continue

    var distance = Math.abs(Number(scales[i]) - current)
    if (distance < bestDistance) {
      bestIndex = i
      bestDistance = distance
    }
  }
  return bestIndex
}

function availableScales(scales, width, height) {
  if (!Array.isArray(scales) || Number(width) <= 0 || Number(height) <= 0) return scales || []

  var byEffectiveScale = {}
  for (var i = 0; i < scales.length; i++) {
    var requested = Number(scales[i])
    var effective = Number(cleanScale(requested, width, height))

    if (!isFinite(requested) || !isFinite(effective)) continue

    var key = normalizeScale(effective)
    var existing = byEffectiveScale[key]
    if (!existing || Math.abs(requested - effective) < existing.distance) {
      byEffectiveScale[key] = {
        value: String(scales[i]),
        index: i,
        distance: Math.abs(requested - effective)
      }
    }
  }

  return Object.keys(byEffectiveScale)
    .map(function(key) { return byEffectiveScale[key] })
    .sort(function(a, b) { return a.index - b.index })
    .map(function(candidate) { return candidate.value })
}

// tr is an optional translate(key, english) from the QML side (I18n.t);
// without it the English text stands, which is what the Node tests assert.
function brightnessName(percent, tr) {
  var t = typeof tr === "function" ? tr : function(key, english) { return english }
  var p = Math.round(percent)
  if (p >= 95) return t("monitor.level.sunBlast", "Sun blast")
  if (p >= 80) return t("monitor.level.solarFlare", "Solar flare")
  if (p >= 65) return t("monitor.level.goldenHour", "Golden hour")
  if (p >= 45) return t("monitor.level.evenDay", "Even day")
  if (p >= 30) return t("monitor.level.softGlow", "Soft glow")
  if (p >= 20) return t("monitor.level.lampLight", "Lamp light")
  if (p >= 10) return t("monitor.level.candlelit", "Candlelit")
  return t("monitor.level.nightOwl", "Night owl")
}

function parseDisplays(raw) {
  var displays = []
  try {
    displays = raw ? JSON.parse(String(raw)) : []
  } catch (e) {
    displays = []
  }
  if (!Array.isArray(displays)) displays = []

  var count = 0
  for (var i = 0; i < displays.length; i++) {
    if (displays[i] && displays[i].enabled) count++
  }

  return {
    displays: displays,
    enabledDisplayCount: count
  }
}

// From Omarchy's monitor panel: the refresh rates offered at the current
// resolution, one per whole rate (59.94 and 60 are the same choice), from 60Hz
// up. Empty unless one beats 60Hz, since then there's nothing to choose.
function refreshOptions(availableModes, width, height) {
  if (!Array.isArray(availableModes)) return []
  var prefix = Number(width) + "x" + Number(height) + "@"
  var rates = {}
  for (var i = 0; i < availableModes.length; i++) {
    var mode = String(availableModes[i])
    if (mode.indexOf(prefix) !== 0) continue
    var rate = parseFloat(mode.slice(prefix.length))
    if (!(rate >= 59.5)) continue
    var whole = Math.round(rate)
    if (!rates[whole] || rate > rates[whole]) rates[whole] = rate
  }
  var wholes = Object.keys(rates).map(Number).sort(function(a, b) { return a - b })
  if (wholes.length < 2 || wholes[wholes.length - 1] <= 60) return []
  return wholes.map(function(whole) {
    return { label: String(whole), rate: String(Number(rates[whole].toFixed(2))) }
  })
}

if (typeof module !== "undefined") {
  module.exports = {
    refreshOptions: refreshOptions,
    clampBrightness: clampBrightness,
    normalizeScale: normalizeScale,
    cleanScale: cleanScale,
    matchingScaleIndex: matchingScaleIndex,
    availableScales: availableScales,
    brightnessName: brightnessName,
    parseDisplays: parseDisplays
  }
}
