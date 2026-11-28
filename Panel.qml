import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import qs.Commons as Commons
import "Model.js" as Model

Panel {
  id: root
  moduleName: "omarchy.monitor"
  ipcTarget: "omarchy.monitor"
  manageIpc: false

  // manageIpc: false so this panel can own the single IpcHandler the target
  // permits — needed for the brightness + state methods below.
  property int brightnessPercent: 0
  property int pendingBrightnessPercent: 0
  property bool brightnessSetQueued: false
  property bool brightnessAvailable: false
  property string internalMonitor: ""
  property string externalMonitor: ""
  property string focusedMonitor: ""
  // Monitor the SCALE row acts on; empty = follow the focused one. Click the name to cycle.
  property string targetMonitor: ""
  property var monitorInfo: ({})
  // Layout items in list order: ["DP-3", "eDP-2", "^HDMI-A-1"]; "^" = stacked above the one before.
  // A mirror is enabled but sits on its source and isn't in `hyprctl monitors`, so it has no place to arrange.
  function arranged(d) { return d && d.enabled && !d.mirror }
  property int arrangedCount: 0
  function layoutItems(list) {
    return list.filter(arranged).map(function(d) { return (d.stacked ? "^" : "") + d.name })
  }
  function runAction(cmd) {
    // One action at a time: a click while one is still running is ignored, never retargeted.
    if (actionProc.running) return
    actionProc.command = cmd
    actionProc.running = true
  }
  function applyLayout(flags, list) {
    var script = decodeURIComponent(Qt.resolvedUrl("layout.py").toString().replace(/^file:\/\//, ""))
    runAction(["timeout", "-k", "1", "10", script].concat(flags, layoutItems(list)))
  }
  // Move a display `delta` places along the list (list order = screen order, top = left).
  // The arrows move one place; a drag moves as far as it was dropped.
  function moveDisplay(name, delta) {
    var list = displays.filter(arranged).map(function(d) { return Object.assign({}, d) })
    var i = list.findIndex(function(d) { return d.name === name }), j = i + delta
    if (i < 0 || j < 0 || j >= list.length || j === i) return
    list.splice(j, 0, list.splice(i, 1)[0])
    list[0].stacked = false
    applyLayout([], list)
  }
  // What a display copies when mirrored: the built-in screen, else the first one in the list.
  function mirrorSource(name) {
    var others = displays.filter(function(d) { return arranged(d) && d.name !== name }).map(function(d) { return d.name })
    return others.indexOf(internalMonitor) >= 0 ? internalMonitor : (others[0] || "")
  }
  function toggleMirror(name) {
    var d = displays.find(function(x) { return x && x.name === name })
    if (!d) return
    if (d.mirror) {
      // Back to extended: it joins the end of the row.
      applyLayout(["--mirror", name, "none"], displays.filter(arranged).concat([Object.assign({}, d, { stacked: false, mirror: false })]))
    } else {
      var src = mirrorSource(name)
      if (!src) return
      applyLayout(["--mirror", name, src], displays.filter(function(x) { return x.name !== name }))
    }
  }
  readonly property var refreshValues: {
    var m = monitorInfo[targetName()]
    return m ? Model.refreshOptions(m.availableModes, m.width, m.height) : []
  }
  function activeRefreshIndex() {
    var m = monitorInfo[targetName()]
    if (!m) return -1
    var now = Math.round(Number(m.refreshRate))
    return refreshValues.findIndex(function(o) { return Number(o.label) === now })
  }
  function setRefresh(rate) {
    var name = targetName(), m = monitorInfo[name]
    if (!m) return
    applyLayout(["--mode", name, m.width + "x" + m.height + "@" + rate], displays)
  }
  function toggleStacked(name) {
    applyLayout([], displays.map(function(d) { return d.name === name ? Object.assign({}, d, { stacked: !d.stacked }) : d }))
  }
  function toggleRotation(name) {
    var info = monitorInfo[name] || {}
    // Flip only the 90° bit (0↔1, 2↔3, 4↔5, 6↔7) so an upside-down or mirrored monitor keeps that.
    applyLayout(["--transform", name, String((info.transform | 0) ^ 1)], displays)
  }
  function targetName() {
    for (var i = 0; i < displays.length; i++)
      if (displays[i] && displays[i].enabled && displays[i].name === targetMonitor) return targetMonitor
    return focusedMonitor
  }
  // The displays the switcher at the top offers, in list order.
  readonly property var targetChoices: displays.filter(function(d) { return d && d.enabled }).map(function(d) { return d.name })

  // Aliases live in ~/.config/omarchy/displays-aliases.json, keyed by the monitor's
  // make/model/serial so a name follows the screen when it moves to another port.
  property var aliases: ({})
  property bool editingAlias: false
  // Keyed by the screen's description so a name follows it to another port. Two identical
  // monitors (same make and model, no serial) share a description, so they add their port.
  function aliasKey(name) {
    var desc = (monitorInfo[name] || {}).description || ""
    if (!desc) return name
    for (var other in monitorInfo) {
      if (other !== name && (monitorInfo[other] || {}).description === desc) return desc + " @ " + name
    }
    return desc
  }
  function aliasFor(name) { var a = aliases[aliasKey(name)]; return typeof a === "string" ? a : "" }
  function labelFor(name) { return aliasFor(name) || name }
  function setAlias(name, text) {
    var next = Object.assign({}, aliases), key = aliasKey(name)
    var clean = String(text || "").replace(/[\u0000-\u001f]/g, "").trim().slice(0, 40)
    if (clean && clean !== name) next[key] = clean
    else delete next[key]
    aliases = next
    aliasFile.setText(JSON.stringify(next, null, 2) + "\n")
  }
  function loadAliases(raw) {
    var parsed = {}
    try { parsed = JSON.parse(raw || "{}") } catch (e) { parsed = {} }
    var clean = {}
    if (parsed && typeof parsed === "object" && !Array.isArray(parsed))
      for (var k in parsed)
        if (typeof parsed[k] === "string" && k.length <= 200) clean[k] = parsed[k].slice(0, 40)
    aliases = clean
  }
  function orientationText(t) {
    t = t | 0
    return (t % 2 ? "Portrait" : "Landscape") + ((t & 2) ? ", upside down" : "") + (t >= 4 ? ", flipped" : "")
  }

  property bool internalEnabled: false
  property bool mirrorEnabled: false
  property string monitorScale: ""
  property var displays: []
  property int enabledDisplayCount: 0

  // Carry sub-notch touchpad deltas between wheel events.
  property real wheelAccumulator: 0

  // Cursor model shared by keyboard and mouse. Sections:
  //   "brightness" - single slider row, selectedIndex = -1 sentinel
  //                  (mirrors Audio's slider rows). Only present if a
  //                  controllable backlight was detected.
  //   "scale"      - 6 Button scale presets; treated as a single
  //                  horizontal row from j/k's perspective. h/l moves
  //                  between presets, identical to bluetooth's header.
  //   "monitors"   - vertical display row list for enabling/disabling displays;
  //                  j/k walks each row.
  // Mouse hover on a target updates root state via the components' `hovered`
  // signal so keyboard cursor and pointer share one highlight.
  readonly property var scalePresets: ["1", "1.25", "1.333333", "1.6", "2", "3", "4"]
  readonly property var scaleValues: {
    for (var i = 0; i < displays.length; i++) {
      var display = displays[i]
      if (display && display.name === root.targetName())
        return Model.availableScales(scalePresets, display.width, display.height)
    }
    return scalePresets
  }
  property string focusSection: "scale"
  property int selectedIndex: 0
  property bool cursorActive: false

  // Text size slider — curated macOS-style notches (px). The panel snaps to
  // these stops; the CLI (omarchy-display-text-size) accepts any integer in range.
  readonly property var textSizeStops: [9, 10, 11, 12, 14, 16, 20]
  // While a change is in flight, the chosen stop index overrides the live
  // base-size so the knob doesn't snap back during the file round-trip. -1 =
  // no pending change; follow Style.font.baseSize.
  property int textSizePreviewIndex: -1

  // A text-size change reflows the whole panel (both font and spacing scale),
  // which slides rows under a stationary pointer and fires synthetic hover.
  // While true, hover is not allowed to hijack the keyboard focus section —
  // otherwise h/l on the text-size slider can jump focus to another row.
  property bool reflowingText: false
  function markReflowing() {
    root.reflowingText = true
    reflowSettle.restart()
  }

  readonly property var visibleSections: {
    var list = []
    if (targetChoices.length > 1) list.push("target")
    if (brightnessAvailable) list.push("brightness")
    list.push("textsize")
    list.push("scale")
    if (refreshValues.length) list.push("refresh")
    if (displays.length > 1) list.push("monitors")
    return list
  }

  function sectionCount(section) {
    if (section === "brightness") return 0  // only the slider sentinel at -1
    if (section === "textsize") return 0    // slider sentinel at -1, like brightness
    if (section === "target") return targetChoices.length
    if (section === "scale") return scaleValues.length
    if (section === "refresh") return refreshValues.length
    if (section === "monitors") return displays.length
    return 0
  }

  function sectionIsSingleRow(section) {
    // brightness and text size are lone sliders; scale presets sit horizontally.
    return section === "brightness" || section === "textsize" || section === "scale" || section === "refresh" || section === "target"
  }

  function sectionFirstIndex(section) {
    if (section === "brightness" || section === "textsize") return -1
    return 0
  }

  function moveCursor(delta) {
    var sections = visibleSections
    if (!sections || sections.length === 0) return
    var sIdx = sections.indexOf(focusSection)
    if (sIdx < 0) {
      focusSection = sections[0]
      selectedIndex = sectionFirstIndex(focusSection)
      return
    }
    var inSingleRow = sectionIsSingleRow(focusSection)
    var max = inSingleRow ? 0 : sectionCount(focusSection) - 1

    if (delta > 0) {
      if (!inSingleRow && selectedIndex < max) { selectedIndex = selectedIndex + 1; return }
      if (sIdx < sections.length - 1) {
        focusSection = sections[sIdx + 1]
        selectedIndex = sectionFirstIndex(focusSection)
      }
    } else {
      if (!inSingleRow && selectedIndex > 0) { selectedIndex = selectedIndex - 1; return }
      if (sIdx > 0) {
        var prev = sections[sIdx - 1]
        focusSection = prev
        // Coming up from below — land on the last navigable row of the prev
        // section, or its sentinel for single-row sections.
        selectedIndex = sectionIsSingleRow(prev) ? sectionFirstIndex(prev) : sectionCount(prev) - 1
      }
    }
  }

  // h/l: in scale section, walks the preset row; everywhere else, no-op
  // because adjustBrightness handles horizontal motion on the brightness
  // slider.
  function moveCursorH(delta) {
    if (focusSection !== "scale" && focusSection !== "refresh" && focusSection !== "target") return
    var next = selectedIndex + delta
    if (next < 0) next = 0
    if (next > sectionCount(focusSection) - 1) next = sectionCount(focusSection) - 1
    selectedIndex = next
  }

  function adjustBrightness(delta) {
    if (focusSection !== "brightness") return
    if (!brightnessAvailable) return
    setBrightness(root.brightnessPercent + delta)
  }

  function activateCursor() {
    if (focusSection === "target" && selectedIndex >= 0 && selectedIndex < targetChoices.length) {
      targetMonitor = targetChoices[selectedIndex]
      return
    }
    if (focusSection === "scale" && selectedIndex >= 0 && selectedIndex < scaleValues.length) {
      setScale(scaleValues[selectedIndex])
      return
    }
    if (focusSection === "refresh" && selectedIndex >= 0 && selectedIndex < refreshValues.length) {
      setRefresh(refreshValues[selectedIndex].rate)
      return
    }
    if (focusSection === "monitors" && selectedIndex >= 0 && selectedIndex < displays.length) {
      var d = displays[selectedIndex]
      if (d) toggleDisplay(d.name, d.enabled)
    }
    // brightness: no separate action; the slider value is the action.
  }

  function clampCursor() {
    var sections = visibleSections
    if (!sections || !sections.length) return
    if (sections.indexOf(focusSection) < 0) {
      focusSection = sections[0]
      selectedIndex = sectionFirstIndex(focusSection)
      return
    }
    var count = sectionCount(focusSection)
    if (sectionIsSingleRow(focusSection)) {
      // brightness/text size use the -1 sentinel; scale clamps into the presets.
      if (focusSection === "brightness" || focusSection === "textsize") selectedIndex = -1
      else if (selectedIndex < 0 || selectedIndex >= count) selectedIndex = 0
      return
    }
    if (count === 0) {
      var sIdx = sections.indexOf(focusSection)
      focusSection = sIdx > 0 ? sections[sIdx - 1] : sections[0]
      selectedIndex = sectionFirstIndex(focusSection)
      return
    }
    if (selectedIndex > count - 1) selectedIndex = count - 1
    if (selectedIndex < 0) selectedIndex = 0
  }

  // Keep the keyboard-focused row inside the viewport when the panel grows
  // taller than its allotted height (lots of displays). Mirrors audio's
  // ensureCursorVisible helper.
  function ensureCursorVisible(item) {
    var scrollArea = panel.loadedContent ? panel.loadedContent.scrollArea : null
    if (!item || !scrollArea) return
    var flick = scrollArea.contentItem
    if (!flick || flick.contentY === undefined) return
    var pt = item.mapToItem(flick.contentItem || flick, 0, 0)
    var top = pt.y
    var bottom = top + (item.height || 0)
    var viewTop = flick.contentY
    var viewBottom = viewTop + flick.height
    var margin = 6
    if (top < viewTop + margin) flick.contentY = Math.max(0, top - margin)
    else if (bottom > viewBottom - margin)
      flick.contentY = bottom + margin - flick.height
  }

  function brightnessIpc(percent) {
    var value = Number(percent)
    root.setBrightness(value)
    return "got " + root.pendingBrightnessPercent
  }

  function stateIpc() {
    return JSON.stringify({
      brightness: root.brightnessPercent,
      brightnessAvailable: root.brightnessAvailable,
      focusedMonitor: root.focusedMonitor,
      scale: root.monitorScale,
      displays: root.displays
    })
  }

  ShellIpc {
    target: "omarchy.monitor"

    function brightness(percent: string): string { return root.brightnessIpc(percent) }
    function state(): string { return root.stateIpc() }
    function open() { root.open() }
    function close() { root.close() }
    function toggle() { root.toggle() }
    function show() { root.open() }
    function hide() { root.close() }
  }

  function refresh() {
    if (!stateProc.running) stateProc.running = true
  }

  function setBrightness(value) {
    var percent = Model.clampBrightness(value)
    root.brightnessPercent = percent
    root.pendingBrightnessPercent = percent

    if (setBrightnessProc.running) {
      root.brightnessSetQueued = true
      return
    }

    root.brightnessSetQueued = false
    setBrightnessProc.command = ["timeout", "-k", "1", "5", "omarchy-brightness-display", "--no-osd", "--monitor", root.focusedMonitor, percent + "%"]
    setBrightnessProc.running = true
  }

  function previewBrightness(value) {
    root.brightnessPercent = Model.clampBrightness(value)
    brightnessDebounce.restart()
  }

  function showBrightnessOsd(percent) {
    if (!bar || !bar.shell) return
    bar.shell.summon("omarchy.osd", JSON.stringify({
      icon: "brightness",
      value: percent
    }))
  }

  function normalizeScale(scale) {
    return Model.normalizeScale(scale)
  }

  function activeScaleIndex() {
    for (var i = 0; i < displays.length; i++) {
      var display = displays[i]
      if (display && display.name === root.targetName())
        return Model.matchingScaleIndex(scaleValues, (monitorInfo[display.name] || {}).scale, display.width, display.height)
    }
    return -1
  }

  function effectiveScale(scale) {
    for (var i = 0; i < displays.length; i++) {
      var display = displays[i]
      if (display && display.name === root.targetName())
        return Model.cleanScale(scale, display.width, display.height)
    }
    return normalizeScale(scale)
  }

  // Playful mood-name for a given brightness percent. Bands intentionally
  // span ~10–20 points so casual tweaks change the label, while small
  // nudges within one band don't.
  function brightnessName(percent) {
    return Model.brightnessName(percent, Commons.I18n.t)
  }

  function updateDisplays(displaysJson) {
    var parsed = Model.parseDisplays(displaysJson)
    // List order = screen order: columns left to right, and within a column bottom first,
    // so a monitor sitting above the previous row is marked stacked. Disabled ones go last.
    var info = root.monitorInfo
    function box(d) {
      var m = info[d.name]
      if (!d.enabled || !m || m.disabled || (m.mirrorOf && m.mirrorOf !== "none")) return null
      var w = Math.round(m.width / m.scale), h = Math.round(m.height / m.scale)
      return m.transform % 2 ? { x: m.x, y: m.y, w: h, h: w } : { x: m.x, y: m.y, w: w, h: h }
    }
    var on = parsed.displays.filter(box).sort(function(a, b) { return box(a).x - box(b).x })
    var columns = []
    on.forEach(function(d) {
      var b = box(d), col = columns[columns.length - 1]
      if (col && b.x < col.right) { col.items.push(d); col.right = Math.max(col.right, b.x + b.w) }
      else columns.push({ right: b.x + b.w, items: [d] })
    })
    var ordered = []
    columns.forEach(function(col) {
      col.items.sort(function(a, b) { return box(b).y - box(a).y })
      col.items.forEach(function(d, i) { ordered.push(Object.assign({}, d, { stacked: i > 0 })) })
    })
    // Enabled with no box: a mirror, drawn on its source's screen.
    var rest = parsed.displays.filter(function(d) { return !box(d) })
      .map(function(d) { return d.enabled ? Object.assign({}, d, { mirror: true }) : d })
    root.displays = ordered.concat(rest)
    root.arrangedCount = ordered.length
    root.enabledDisplayCount = parsed.enabledDisplayCount
  }

  function toggleDisplay(name, enabled) {
    if (!name) return
    if (enabled && root.enabledDisplayCount <= 1) return

    // hyprctl keyword is rejected under the Lua config ("non-legacy parsers"),
    // so drive the monitor through the hl.monitor eval API instead.
    var output = '"' + name.replace(/[\\"]/g, "\\$&") + '"'
    // hl.monitor updates the existing rule. Keep its mode, position and scale
    // when bringing the display back.
    var expr = enabled
      ? 'hl.monitor({ output = ' + output + ', disabled = true })'
      : 'hl.monitor({ output = ' + output + ', disabled = false })'
    runAction(["timeout", "-k", "1", "5", "hyprctl", "eval", expr])
  }

  function setScale(scale) {
    var name = targetName()
    if (!name) return
    // effectiveScale is rounded for display ("1.33"); save Hyprland's exact multiple of 1/120
    // (1.333333) or layout.py computes 1444px instead of 1440 and leaves a gap.
    var units = Math.round(Number(effectiveScale(scale)) * 120)
    applyLayout(["--scale", name, String(Math.round(units / 120 * 1e6) / 1e6)], displays)
  }

  // ---- Text size (shell base font + GTK text-scaling, via one CLI) ----
  function nearestTextStop(px) {
    var best = 0
    var bestDist = 1e9
    for (var i = 0; i < textSizeStops.length; i++) {
      var d = Math.abs(textSizeStops[i] - px)
      if (d < bestDist) { bestDist = d; best = i }
    }
    return best
  }

  // Effective stop index: the pending choice while a change is in flight,
  // otherwise whatever Style's live base-size rounds to.
  function currentTextIndex() {
    return textSizePreviewIndex >= 0 ? textSizePreviewIndex : nearestTextStop(Style.font.baseSize)
  }

  // px shown in the header: the pending stop if any, else the true base-size
  // (which may be an off-notch value set from the CLI).
  function displayedTextPx() {
    return textSizePreviewIndex >= 0 ? textSizeStops[textSizePreviewIndex] : Style.font.baseSize
  }

  function setTextSize(px) {
    if (textScaleProc.running) return
    textScaleProc.command = ["timeout", "-k", "1", "5", "omarchy-display-text-size", String(px)]
    textScaleProc.running = true
  }

  function adjustTextSize(deltaSteps) {
    var idx = currentTextIndex() + deltaSteps
    if (idx < 0) idx = 0
    if (idx > textSizeStops.length - 1) idx = textSizeStops.length - 1
    markReflowing()
    textSizePreviewIndex = idx
    setTextSize(textSizeStops[idx])
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: refresh()

  // KeyboardPanel primes focus at open-time, so SUPER-bound IPC summons land
  // with j/k ready to navigate. Keep a default landing point, but don't paint
  // the cursor until hover or the first navigation key.
  onOpenedChanged: {
    if (!opened) editingAlias = false
    if (opened) {
      refresh()
      if (brightnessAvailable) {
        focusSection = "brightness"
        selectedIndex = -1
      } else {
        focusSection = "scale"
        selectedIndex = 0
      }
      cursorActive = false
    }
  }

  onBrightnessAvailableChanged: clampCursor()
  onDisplaysChanged: clampCursor()
  onScaleValuesChanged: clampCursor()
  onVisibleSectionsChanged: clampCursor()

  // Only poll while the panel is open; the bar glyph tracks monitor count via
  // Quickshell.screens, and open-time refresh + Component.onCompleted cover the
  // rest. External brightness changes are reflected whenever the panel is open.
  Timer {
    interval: 5000
    running: root.opened
    repeat: true
    onTriggered: root.refresh()
  }

  // Our own strings: Omarchy renamed its monitor.* keys once already.
  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  FileView {
    id: aliasFile
    path: Quickshell.env("HOME") + "/.config/omarchy/displays-aliases.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.loadAliases(text())
    onLoadFailed: root.loadAliases("")
  }

  Process {
    id: stateProc
    // Bounded and all-or-nothing: on any failure or timeout it prints nothing and the panel
    // keeps its previous state.
    command: ["bash", "-c", "set -o pipefail; s=$(timeout -k 1 5 omarchy-monitor-state) && j=$(timeout -k 1 5 hyprctl monitors all -j | jq -c 'map({key: .name, value: {scale, x, y, width, height, transform, refreshRate, availableModes, description, mirrorOf, disabled}}) | from_entries') && printf '%s\\n%s\\n' \"$s\" \"$j\" | head -c 65536"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").split("\n")
        if (lines.length < 9) return
        var brightness = String(lines[0] || "").trim()
        root.brightnessAvailable = brightness !== "unavailable" && brightness !== ""
        root.brightnessPercent = root.brightnessAvailable ? Math.max(0, Math.min(100, parseInt(brightness, 10))) : 0
        root.internalMonitor = String(lines[1] || "").trim()
        root.externalMonitor = String(lines[2] || "").trim()
        root.internalEnabled = String(lines[3] || "").trim() !== ""
        root.mirrorEnabled = String(lines[4] || "").trim() === root.externalMonitor && root.externalMonitor !== ""
        root.focusedMonitor = String(lines[5] || "").trim()
        root.monitorScale = root.normalizeScale(String(lines[6] || "").trim())
        try { root.monitorInfo = JSON.parse(String(lines[8] || "{}")) } catch (e) { root.monitorInfo = {} }
        root.updateDisplays(String(lines[7] || "[]").trim())
      }
    }
  }

  Timer {
    id: brightnessDebounce
    interval: 180
    repeat: false
    onTriggered: root.setBrightness(root.brightnessPercent)
  }

  Process {
    id: setBrightnessProc
    stdout: StdioCollector { waitForEnd: true }
    // Do NOT call refresh() after a brightness set completes. The local
    // brightnessPercent we just wrote is authoritative; re-reading via
    // `omarchy-brightness-display` races the hardware/driver and can
    // return an empty string, which the parser then coerces to 0 —
    // visible as a "bounce to zero" after h/l keypresses. External
    // brightness changes are still picked up by the 5s periodic refresh,
    // the open-time refresh, and Component.onCompleted.
    onRunningChanged: {
      if (running) return
      if (root.brightnessSetQueued) {
        root.setBrightness(root.pendingBrightnessPercent)
      }
    }
  }

  Process {
    id: actionProc
    stdout: StdioCollector { waitForEnd: true }
    onRunningChanged: if (!running) root.refresh()
  }

  // Applies text size via the CLI, which rewrites the shell override file;
  // Style picks the new base-size up through its own file watch, so there's
  // nothing to refresh here.
  Process {
    id: textScaleProc
    stdout: StdioCollector { waitForEnd: true }
  }

  // Clears the hover-suppression flag once the reflow triggered by a text-size
  // change has settled.
  Timer {
    id: reflowSettle
    interval: 300
    repeat: false
    onTriggered: root.reflowingText = false
  }

  // Once Style's base-size catches up to the pending choice, drop the preview
  // so the slider tracks the live value again. The change itself reflows the
  // panel, so suppress hover for a beat while it lands.
  Connections {
    target: Style
    function onFontBaseSizeChanged() {
      root.markReflowing()
      if (root.textSizePreviewIndex >= 0
          && root.nearestTextStop(Style.font.baseSize) === root.textSizePreviewIndex)
        root.textSizePreviewIndex = -1
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: Quickshell.screens.length > 1 ? "󰍺" : "󰍹"
    onPressed: function(b) { root.toggle() }
    onWheelMoved: function(delta) {
      if (!root.brightnessAvailable) return
      var wheel = Util.wheelSteps(root.wheelAccumulator, delta)
      root.wheelAccumulator = wheel.remainder
      if (wheel.steps === 0) return
      root.setBrightness(root.brightnessPercent + wheel.steps * 5)
      root.showBrightnessOsd(root.brightnessPercent)
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, Style.space(560))

    content: PanelKeyCatcher {
      id: keyCatcher
      property alias scrollArea: scrollArea
      implicitHeight: panelColumn.implicitHeight
      anchors.fill: parent
      blocked: root.editingAlias
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dy !== 0) root.moveCursor(dy)
        else if (dx !== 0) {
          if (root.focusSection === "brightness") root.adjustBrightness(dx * 5)
          else if (root.focusSection === "textsize") root.adjustTextSize(dx)
          else root.moveCursorH(dx)
        }
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      ScrollView {
        id: scrollArea
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: panelColumn.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
        Binding {
          target: scrollArea.contentItem
          property: "interactive"
          value: panelColumn.implicitHeight > scrollArea.height
        }

        Column {
          id: panelColumn
          width: scrollArea.availableWidth
          spacing: Style.space(14)

          // ---------- Hero: display icon · title/status ----------
          Item {
            width: parent.width
            implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

            Text {
              id: heroIcon
              textFormat: Text.PlainText
              text: root.displays.length > 1 ? "󰍺" : "󰍹"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.display
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            Column {
              id: heroLabels
              anchors.left: heroIcon.right
              anchors.leftMargin: Style.space(14)
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                text: "Displays"
                textFormat: Text.PlainText
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                elide: Text.ElideRight
                width: parent.width
              }

              Text {
                id: heroLabel
                textFormat: Text.PlainText
                text: {
                  if (root.brightnessAvailable) {
                    return root.brightnessName(brightnessSlider.dragging ? brightnessSlider.liveValue : root.brightnessPercent).toUpperCase()
                  }
                  return strings.t("fixedBrightness")
                }
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
                elide: Text.ElideRight
                width: parent.width
              }
            }
          }

          // ---------- The monitor the settings below act on ----------
          PanelSeparator {
            visible: root.targetName() !== ""
            foreground: root.bar.foreground
          }

          Column {
            id: targetCard
            visible: root.targetName() !== ""
            width: parent.width
            spacing: Style.space(8)

            readonly property string name: root.targetName()
            readonly property var info: root.monitorInfo[name] || {}

            Row {
              id: targetRow
              visible: root.targetChoices.length > 1
              width: parent.width
              spacing: Style.spacing.xs
              readonly property real cellWidth: (width - spacing * (root.targetChoices.length - 1)) / Math.max(1, root.targetChoices.length)

              Repeater {
                model: root.targetChoices

                ChoicePill {
                  required property string modelData
                  required property int index

                  section: "target"
                  choiceIndex: index
                  text: root.labelFor(modelData)
                  active: modelData === targetCard.name
                  width: targetRow.cellWidth
                  onClicked: root.targetMonitor = modelData
                }
              }
            }

            // Name (click the pencil to give it an alias) and connector.
            Item {
              width: parent.width
              implicitHeight: Math.max(aliasTitle.implicitHeight, aliasField.implicitHeight)

              Text {
                id: aliasTitle
                visible: !root.editingAlias
                textFormat: Text.PlainText
                text: root.labelFor(targetCard.name)
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.subtitle
                font.bold: true
                elide: Text.ElideRight
                width: Math.min(implicitWidth, parent.width - aliasEdit.width - connectorText.implicitWidth - Style.space(16))
                anchors.left: parent.left
                anchors.leftMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: aliasEdit
                visible: !root.editingAlias
                textFormat: Text.PlainText
                text: "󰏫"
                color: root.bar.foreground
                opacity: aliasEditArea.containsMouse ? 1.0 : 0.5
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
                anchors.left: aliasTitle.right
                anchors.leftMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                Accessible.name: "Rename"
                MouseArea {
                  id: aliasEditArea
                  anchors.fill: parent
                  anchors.margins: -Style.space(4)
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    root.editingAlias = true
                    aliasField.text = root.aliasFor(targetCard.name)
                    Qt.callLater(function() { aliasField.selectAll(); aliasField.forceActiveFocus() })
                  }
                }
              }

              TextField {
                id: aliasField
                visible: root.editingAlias
                width: parent.width - connectorText.implicitWidth - Style.space(16)
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                placeholderText: targetCard.name
                maximumLength: 40
                foreground: root.bar.foreground
                font.family: root.bar.fontFamily
                function finish(save) {
                  if (save) root.setAlias(targetCard.name, text)
                  root.editingAlias = false
                  Qt.callLater(function() { if (panel.loadedContent) panel.loadedContent.forceActiveFocus() })
                }
                Keys.onPressed: function(event) {
                  if (event.key === Qt.Key_Escape) { finish(false); event.accepted = true }
                  else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { finish(true); event.accepted = true }
                }
              }

              Text {
                id: connectorText
                textFormat: Text.PlainText
                // The connector only when an alias hides it; the title already says it otherwise.
                text: [root.aliasFor(targetCard.name) ? targetCard.name : "", targetCard.name === root.internalMonitor ? "built-in" : ""].filter(Boolean).join(" · ")
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: parent.right
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            Repeater {
              // Each line only when hyprctl reported what it needs.
              model: {
                var m = targetCard.info, lines = []
                if (m.description) lines.push(m.description)
                if (m.width) {
                  var s = Number(m.scale) || 1
                  var w = Math.round(m.width / s), h = Math.round(m.height / s)
                  if (m.transform % 2) { var t = w; w = h; h = t }
                  lines.push(m.width + "×" + m.height + " @ " + Commons.I18n.formatNumber(Math.round(Number(m.refreshRate))) + " Hz · "
                             + Commons.I18n.formatNumber(root.normalizeScale(s)) + "x, looks like " + w + "×" + h)
                  lines.push(root.orientationText(m.transform) + " · "
                             + (m.mirrorOf && m.mirrorOf !== "none" ? "mirroring " + root.labelFor(m.mirrorOf) : "at " + m.x + ", " + m.y)
                             + (targetCard.name === root.focusedMonitor ? " · focused" : ""))
                }
                return lines
              }

              Text {
                required property string modelData
                textFormat: Text.PlainText
                text: modelData
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
                width: parent.width - Style.space(12)
                x: Style.space(6)
              }
            }
          }

          // ---------- Brightness ----------
          PanelSeparator {
            visible: root.brightnessAvailable
            foreground: root.bar.foreground
          }

          Column {
            visible: root.brightnessAvailable
            width: parent.width
            spacing: Style.space(6)

            Item {
              width: parent.width
              implicitHeight: Math.max(brightnessHeader.implicitHeight, brightnessPercent.implicitHeight)

              PanelSectionHeader {
                id: brightnessHeader
                text: Commons.I18n.t("monitor.brightness")
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: brightnessPercent
                textFormat: Text.PlainText
                text: Commons.I18n.formatNumber(Math.round(brightnessSlider.dragging ? brightnessSlider.liveValue : root.brightnessPercent)) + "%"
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: parent.right
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            CursorSurface {
              id: brightnessRow
              width: parent.width
              height: brightnessSlider.implicitHeight + Style.spacing.controlGap
              hasCursor: root.cursorActive && root.focusSection === "brightness" && root.selectedIndex === -1
              onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(brightnessRow)
              foreground: root.bar.foreground
              outline: true

              PanelSlider {
                id: brightnessSlider
                bar: root.bar
                anchors.fill: parent
                anchors.leftMargin: Style.space(6)
                anchors.rightMargin: Style.space(6)
                minimum: 1
                maximum: 100
                step: 1
                value: root.brightnessPercent
                integer: true
                onMoved: function(v) { root.previewBrightness(v) }
                onReleased: function(v) {
                  brightnessDebounce.stop()
                  root.setBrightness(v)
                }
              }

              HoverHandler {
                onHoveredChanged: if (hovered && !root.reflowingText) {
                  root.cursorActive = true
                  root.focusSection = "brightness"
                  root.selectedIndex = -1
                }
              }
            }
          }

          // ---------- Text size ----------
          PanelSeparator {
            foreground: root.bar.foreground
          }

          Column {
            width: parent.width
            spacing: Style.space(6)

            Item {
              width: parent.width
              implicitHeight: Math.max(textSizeHeader.implicitHeight, textSizePx.implicitHeight)

              PanelSectionHeader {
                id: textSizeHeader
                text: Commons.I18n.t("monitor.textSize")
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: textSizePx
                textFormat: Text.PlainText
                text: Commons.I18n.formatNumber(textSizeSlider.dragging
                       ? root.textSizeStops[Math.round(textSizeSlider.liveValue)]
                       : root.displayedTextPx()) + "px"
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: parent.right
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            CursorSurface {
              id: textSizeRow
              width: parent.width
              height: textSizeSlider.implicitHeight + Style.spacing.controlGap
              hasCursor: root.cursorActive && root.focusSection === "textsize" && root.selectedIndex === -1
              onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(textSizeRow)
              foreground: root.bar.foreground
              outline: true

              PanelSlider {
                id: textSizeSlider
                bar: root.bar
                anchors.fill: parent
                anchors.leftMargin: Style.space(6)
                anchors.rightMargin: Style.space(6)
                minimum: 0
                maximum: root.textSizeStops.length - 1
                step: 1
                integer: true
                tickCount: root.textSizeStops.length
                value: root.currentTextIndex()
                onReleased: function(v) { root.setTextSize(root.textSizeStops[Math.round(v)]) }
              }

              HoverHandler {
                onHoveredChanged: if (hovered && !root.reflowingText) {
                  root.cursorActive = true
                  root.focusSection = "textsize"
                  root.selectedIndex = -1
                }
              }
            }
          }

          // ---------- Scale ----------
          PanelSeparator {
            foreground: root.bar.foreground
          }

          Column {
            width: parent.width
            spacing: Style.space(10)

            Item {
              width: parent.width
              implicitHeight: Math.max(scaleHeader.implicitHeight, scaleMonitor.implicitHeight)

              PanelSectionHeader {
                id: scaleHeader
                text: Commons.I18n.t("monitor.scale")
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              // Name the monitor SCALE targets, since it only applies to the
              // focused one.
              Text {
                id: scaleMonitor
                textFormat: Text.PlainText
                text: root.labelFor(root.targetName())
                // Only worth naming when more than one display is in play.
                visible: root.targetName() !== "" && root.enabledDisplayCount > 1
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: parent.right
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            Grid {
              id: scaleRow
              width: parent.width
              columns: root.scaleValues.length
              spacing: Style.spacing.xs

              readonly property real cellWidth: root.scaleValues.length > 0
                ? (width - spacing * (columns - 1)) / columns
                : 0

              Repeater {
                model: root.scaleValues

                ChoicePill {
                  required property string modelData
                  required property int index

                  section: "scale"
                  choiceIndex: index
                  text: Commons.I18n.formatNumber(root.effectiveScale(modelData)) + "x"
                  active: root.activeScaleIndex() === index
                  width: scaleRow.cellWidth
                  onClicked: root.setScale(modelData)
                }
              }
            }
          }

          // ---------- Refresh rate ----------
          PanelSeparator {
            visible: root.refreshValues.length > 0
            foreground: root.bar.foreground
          }

          Column {
            visible: root.refreshValues.length > 0
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: Commons.I18n.t("monitor.refreshRate")
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
            }

            Row {
              id: refreshRow
              width: parent.width
              spacing: Style.spacing.xs
              readonly property real cellWidth: (width - spacing * (root.refreshValues.length - 1)) / Math.max(1, root.refreshValues.length)

              Repeater {
                model: root.refreshValues

                ChoicePill {
                  required property var modelData
                  required property int index

                  section: "refresh"
                  choiceIndex: index
                  text: Commons.I18n.formatNumber(Number(modelData.label)) + " Hz"
                  active: root.activeRefreshIndex() === index
                  width: refreshRow.cellWidth
                  onClicked: root.setRefresh(modelData.rate)
                }
              }
            }
          }

          // ---------- Monitors ----------
          PanelSeparator {
            visible: root.displays.length > 1
            foreground: root.bar.foreground
          }

          Column {
            width: parent.width
            spacing: Style.space(10)
            visible: root.displays.length > 1

            PanelSectionHeader {
              text: strings.t("displays")
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
            }

            Repeater {
              model: root.displays

              MonitorRow {
                required property var modelData
                required property int index

                width: panelColumn.width
                display: modelData
                rowIndex: index
              }
            }
          }

          Item {
            width: parent.width
            height: Style.space(4)
          }
        }
      }
    }
  }

  // One choice in a row of buttons (monitor, scale, refresh rate), sharing the keyboard cursor.
  component ChoicePill: Button {
    id: pill
    required property string section
    required property int choiceIndex

    fontSize: Style.font.caption
    foreground: root.bar.foreground
    fontFamily: root.bar.fontFamily
    horizontalPadding: Style.spacing.sm
    verticalPadding: Style.spacing.controlPaddingY
    bordered: true

    hasCursor: root.cursorActive && root.focusSection === section && root.selectedIndex === choiceIndex
    onHovered: function(isHovered) {
      if (!isHovered || root.reflowingText) return
      root.cursorActive = true
      root.focusSection = pill.section
      root.selectedIndex = pill.choiceIndex
    }
  }

  component MonitorRow: CursorSurface {
    id: monitorRow
    required property var display
    required property int rowIndex

    readonly property bool isFocused: display && display.focused
    readonly property bool canToggle: display && (!display.enabled || root.enabledDisplayCount > 1)
    readonly property bool canMove: root.arranged(display) && root.arrangedCount > 1
    readonly property real arrowsWidth: Style.space(130)
    // Rows of arranged displays come first, so a row's index is its place in the layout.
    property real dragOffset: 0
    readonly property real rowStep: height + Style.space(10)
    z: dragOffset !== 0 ? 1 : 0
    transform: Translate { y: monitorRow.dragOffset }

    hasCursor: root.cursorActive && root.focusSection === "monitors" && root.selectedIndex === rowIndex
    onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(monitorRow)
    current: isFocused
    foreground: root.bar.foreground
    fill: Style.hoverFillFor(root.bar.foreground, Commons.Color.accent)
    currentFill: Style.selectedFillFor(root.bar.foreground, Commons.Color.accent)
    implicitHeight: monitorInner.implicitHeight + Style.spacing.xl
    opacity: canToggle ? 1.0 : 0.45

    Row {
      id: monitorInner
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(8)

      Text {
        textFormat: Text.PlainText
        text: "󰍹"
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.title
        width: Style.space(22)
        horizontalAlignment: Text.AlignHCenter
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        textFormat: Text.PlainText
        text: monitorRow.display.focused
          ? strings.t("displayFocused").arg(root.labelFor(monitorRow.display.name))
          : monitorRow.display.mirror ? strings.t("mirror").arg(root.labelFor(monitorRow.display.name)) : root.labelFor(monitorRow.display.name)
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
        width: parent.width - Style.space(22) - Style.space(14) - Style.space(16) - monitorRow.arrowsWidth
        anchors.verticalCenter: parent.verticalCenter
      }

      // Room for the move arrows, which overlay this spot (they need their own clicks).
      Item { width: monitorRow.arrowsWidth - Style.space(8); height: 1 }

      Text {
        textFormat: Text.PlainText
        text: monitorRow.display.enabled ? "󰄬" : ""
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.subtitle
        width: Style.space(14)
        horizontalAlignment: Text.AlignRight
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    // Click toggles the display; press and drag up or down moves it along the layout.
    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      preventStealing: true
      property real pressY: 0
      property bool dragged: false
      cursorShape: dragged ? Qt.ClosedHandCursor : monitorRow.canToggle ? Qt.PointingHandCursor : Qt.ArrowCursor
      onContainsMouseChanged: if (containsMouse && !root.reflowingText) {
        root.cursorActive = true
        root.focusSection = "monitors"
        root.selectedIndex = monitorRow.rowIndex
      }
      onPressed: function(mouse) { pressY = mouse.y; dragged = false }
      onPositionChanged: function(mouse) {
        if (!pressed || !monitorRow.canMove) return
        var dy = mouse.y - pressY
        if (!dragged && Math.abs(dy) < Style.space(6)) return
        dragged = true
        // Stay within the arranged rows.
        var lo = -monitorRow.rowIndex * monitorRow.rowStep, hi = (root.arrangedCount - 1 - monitorRow.rowIndex) * monitorRow.rowStep
        monitorRow.dragOffset = Math.max(lo, Math.min(hi, dy))
      }
      onReleased: {
        if (!dragged) return
        var k = Math.round(monitorRow.dragOffset / monitorRow.rowStep)
        monitorRow.dragOffset = 0
        if (k !== 0) root.moveDisplay(monitorRow.display.name, k)
      }
      onCanceled: { monitorRow.dragOffset = 0; dragged = false }
      onClicked: if (!dragged && monitorRow.canToggle) root.toggleDisplay(monitorRow.display.name, monitorRow.display.enabled)
    }

    Row {
      visible: monitorRow.canMove || !!monitorRow.display.mirror
      anchors.right: parent.right
      anchors.rightMargin: Style.space(6) + Style.space(14) + Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      width: monitorRow.arrowsWidth

      Repeater {
        model: [
          { glyph: "󰁝", act: "left", tip: "Move left" },
          { glyph: "󰁅", act: "right", tip: "Move right" },
          { glyph: "⤒", act: "stack", tip: "Stack above the display before it" },
          { glyph: "rotate", act: "rotate", tip: "Portrait / landscape" },
          { glyph: "⧉", act: "mirror", tip: "Mirror / extend" }
        ]

        Text {
          required property var modelData
          required property int index
          readonly property bool portrait: (root.monitorInfo[monitorRow.display.name] || {}).transform % 2 === 1
          // A mirror can only be extended again; mirroring needs another display to copy.
          readonly property bool usable: modelData.act === "mirror" ? !!monitorRow.display.mirror || monitorRow.canMove
            : !monitorRow.canMove ? false
            : modelData.act === "left" || modelData.act === "stack" ? monitorRow.rowIndex > 0
            : modelData.act === "right" ? monitorRow.rowIndex < root.arrangedCount - 1 : true
          // Toggles (stack, rotate) show their state: bright when on.
          readonly property bool on: modelData.act === "stack" ? !!monitorRow.display.stacked
            : modelData.act === "rotate" ? portrait
            : modelData.act === "mirror" ? !!monitorRow.display.mirror : false
          textFormat: Text.PlainText
          text: modelData.act === "rotate" ? (portrait ? "▯" : "▭") : modelData.glyph
          color: root.bar.foreground
          opacity: !usable ? 0.15 : (on || arrowArea.containsMouse) ? 1.0 : 0.6
          font.bold: on
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.subtitle
          width: monitorRow.arrowsWidth / 5
          horizontalAlignment: Text.AlignHCenter
          Accessible.name: modelData.tip

          MouseArea {
            id: arrowArea
            anchors.fill: parent
            anchors.margins: -Style.space(4)
            hoverEnabled: true
            enabled: parent.usable
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              var n = monitorRow.display.name, act = parent.modelData.act
              if (act === "left") root.moveDisplay(n, -1)
              else if (act === "right") root.moveDisplay(n, 1)
              else if (act === "stack") root.toggleStacked(n)
              else if (act === "rotate") root.toggleRotation(n)
              else root.toggleMirror(n)
            }
          }
        }
      }
    }
  }
}
