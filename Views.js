.pragma library

// What each page of the menu shows, built from kyrr's state (see
// README.md, "State"). A page is a title and a list of rows; Panel.qml draws
// them and walks them with the keyboard. Rows:
//   switch   on/off, Enter flips it; with `page`, → opens its settings
//   choice   one of `options`, ← → step through them, Enter takes the next
//   slider   a number from `min` to `max`, ← → move it by `step`
//   key      a key to press, Enter starts listening for it
//   action   does `cmd`, or opens `page`
//   memo     a recording: Enter or a click plays it, → or its arrow shows
//            its text, x or its bin deletes it
//   edit     a line to type into (search, a title, an address, a key with
//            `secret`: hidden, never filled in); Enter starts typing
//   editor   the text of a recording, to read, correct and select
//   section  a heading, never selected
//   info     a line of text, never selected
//   progress a bar from 0 to 1, never selected
// `cmd` is what goes to kyrr's socket; {} in it stands for the new value.

var GLYPH = {
  filter: 0xF036C, voice: 0xF0068, dictation: 0xF030C, memos: 0xF044A,
  stop: 0xF04DB, recordings: 0xF1359, update: 0xF01DA, setup: 0xF066A,
  install: 0xF01DA, mic: 0xF036C, folder: 0xF0770, play: 0xF040A,
  check: 0xF02CB, about: 0xF02FD, news: 0xF0EBB, feedback: 0xF0361,
  next: 0xF0142, search: 0xF0349, copy: 0xF018F, file: 0xF0219, trash: 0xF01B4,
  ai: 0xF06A9
}

// The languages translations go into, in the order of kyrr's list (the
// codes `ai.translate` and `sheet.rework.target` carry), with their texts.
var TARGETS = ["en", "de", "fr", "es", "it", "nl", "pt", "pl", "cs", "sk", "sv", "da", "no", "fi", "hu", "ro", "hr"]
var TARGET_KEYS = ["tEn", "tDe", "tFr", "tEs", "tIt", "tNl", "tPt", "tPl", "tCs", "tSk", "tSv", "tDa", "tNo", "tFi", "tHu", "tRo", "tHr"]

function pick(list, index) {
  return list[Math.max(0, Math.min(list.length - 1, index))]
}

// Choices as kyrr numbers them, with their labels.
function options(t, keys) {
  var list = []
  for (var i = 0; i < keys.length; i++) list.push({ value: i, label: t(keys[i]) })
  return list
}

function named(t, keys) {
  var list = []
  for (var i = 0; i < keys.length; i++) list.push({ value: keys[i], label: t(keys[i]) })
  return list
}

// Translating or not, as a choice: "off" for none, else a language's code.
function targets(t) {
  var list = [{ value: "off", label: t("off") }]
  for (var i = 0; i < TARGETS.length; i++) list.push({ value: TARGETS[i], label: t(TARGET_KEYS[i]) })
  return list
}

// Local AI (kyrr 0.8.0) is the `ai` object of the state. A kyrr without it
// has none of the pages below: they stay out of the menu.
function aiShown(k) {
  return !!(k.ai && k.ai.features)
}

function aiCaption(a, t) {
  return !a.on ? t("localAiOff") : !a.ready ? t("localAiNotSet") : t("localAiOn")
}

// What reworking does and what it translates into, once a model is set up.
function aiChoices(a, t) {
  return [
    { kind: "choice", id: "rework", label: t("rework"),
      options: options(t, ["off", "reworkFix", "reworkPolish", "reworkBusiness"]), value: a.rework, cmd: "set ai.rework {}" },
    { kind: "choice", id: "translate", label: t("translateInto"),
      options: targets(t), value: a.translate || "off", cmd: "set ai.translate {}" }
  ]
}

// Local AI on the main page, like its card in kyrr's window.
function localAiRows(a, t) {
  var rows = [{ kind: "switch", id: "localAi", icon: GLYPH.ai, page: "ai", label: t("localAi"),
    checked: a.on, caption: aiCaption(a, t), cmd: "toggle ai.on" }]
  if (a.on && !a.ready)
    rows.push({ kind: "action", id: "aiSetUp", label: t("setUp"), page: "ai", accent: true })
  else if (a.on) rows = rows.concat(aiChoices(a, t))
  return rows
}

// A server of your own, language model or speech: where it is, which model,
// a key if it wants one (typed, never shown), and a test. `p` is the first
// word of its settings (`ai`, `asr`).
function serverRows(s, t, p, address) {
  var rows = []
  if (s.found) {
    rows.push({ kind: "info", label: t("aiRunning", s.found) })
    rows.push({ kind: "action", id: p + "Take", icon: GLYPH.check, label: t("useIt"), cmd: "set " + p + ".take", accent: true })
  }
  rows.push({ kind: "edit", id: p + "Url", label: t("address"), placeholder: address, value: s.url || "",
    cmd: "set " + p + ".url {}" })
  var models = s.models || []
  if (models.length) {
    var list = []
    var known = false
    for (var i = 0; i < models.length; i++) {
      list.push({ value: models[i], label: models[i] })
      if (models[i] === s.model) known = true
    }
    if (s.model && !known) list.unshift({ value: s.model, label: s.model })
    rows.push({ kind: "choice", id: p + "Model", label: t("modelLabel"), options: list, value: s.model,
      cmd: "set " + p + ".model {}" })
  } else {
    rows.push({ kind: "edit", id: p + "Model", label: t("modelLabel"), placeholder: t("modelWait"), value: s.model || "",
      cmd: "set " + p + ".model {}" })
  }
  rows.push({ kind: "info", label: t("aiKey") })
  rows.push({ kind: "edit", id: p + "Key", secret: true, placeholder: s.keySet ? "••••••••" : "", value: "",
    cmd: "set " + p + ".key {}" })
  rows.push({ kind: "action", id: p + "Connect", icon: GLYPH.check, label: t(s.busy ? "asking" : "connect"),
    enabled: !s.busy, cmd: "set " + p + ".connect" })
  if (s.note) rows.push({ kind: "info", label: s.note })
  return rows
}

// The gear of Local AI: the switch and its choices, the language model, and
// what the model is told for each task.
function ai(k, t) {
  var a = k.ai
  var rows = [{ kind: "switch", id: "localAi", label: t("localAi"), checked: a.on, caption: aiCaption(a, t), cmd: "toggle ai.on" }]
  if (a.on && a.ready) rows = rows.concat(aiChoices(a, t))
  rows.push({ kind: "section", label: t("aiModel") })
  rows.push({ kind: "info", label: t("aiRequires") })
  rows = rows.concat(serverRows(a, t, "ai", "http://192.168.1.10:11434"))
  rows.push({ kind: "section", label: t("whichModel") })
  rows.push({ kind: "info", label: t("modelTips") })
  // The instruction the language model gets for each task: read it, change
  // it and save it, or bring kyrr's own back.
  var p = a.prompt || { index: 0, own: false }
  rows.push({ kind: "separator" })
  rows.push({ kind: "info", label: t("promptsHint") })
  rows.push({ kind: "choice", id: "prompt", label: t("prompts"),
    options: options(t, ["reworkFix", "reworkPolish", "reworkBusiness", "translate"]), value: p.index,
    cmd: "set ai.prompt {}" })
  if (p.index === 3) rows.push({ kind: "info", label: t("promptTarget", "{target}") })
  rows.push({ kind: "editor", id: "promptEditor", channel: "prompt", memo: String(p.index) })
  // "Not saved yet." / "Saved." follows what is typed (Panel.qml).
  rows.push({ kind: "info", id: "promptState", live: "promptState", label: t(p.own ? "promptOwn" : "promptDefault") })
  rows.push({ kind: "buttons", id: "promptTools", buttons: [
    { id: "promptSave", icon: GLYPH.check, label: t("save"), live: "promptDirty" },
    { id: "promptReset", icon: GLYPH.update, label: t("reset"), live: "promptOwnOrDirty", cmd: "set ai.promptReset" }
  ] })
  return { title: t("localAi"), rows: rows }
}

// Dictation through a speech server of your own.
function asr(k, t) {
  var s = k.ai.asr
  var rows = [{ kind: "choice", id: "asrOn", label: t("asrTitle"),
    options: [{ value: false, label: t("builtIn") }, { value: true, label: t("ownServer") }], value: !!s.on,
    caption: t(s.on ? "asrOwn" : "asrBuiltIn"), cmd: "set asr.on {}" }]
  if (s.on) rows = rows.concat(serverRows(s, t, "asr", "http://192.168.1.10:8000"))
  return { title: t("asrTitle"), rows: rows }
}

// What the filter says on the main page and its own: switched on or off,
// or why it cannot run.
function filterCaption(k, t) {
  var f = k.filter
  switch (f.state) {
  case "settingUp": return t("filterSettingUp")
  case "passthrough": return t("filterPassthrough")
  case "notAttached": return t("filterNoMic")
  case "notInstalled": return t("filterNotInstalled")
  case "unsupported": return t("filterNoPipewire")
  case "detached": return t("filterDetached", f.mic)
  default: return t(f.on ? "filterOn" : "filterOff")
  }
}

// What the filter needs from you: a microphone, a repair, the microphone
// your system switched to.
function filterHelp(k, t) {
  var f = k.filter
  var rows = []
  if (f.state === "notAttached")
    rows.push({ kind: "action", id: "setUpMic", icon: GLYPH.mic, label: t("setUpMic"), page: "mic", accent: true })
  if (f.state === "detached")
    rows.push({ kind: "action", id: "repair", icon: GLYPH.update, label: t("repair"), cmd: "mic repair", accent: true })
  if (f.moveTo) {
    rows.push({ kind: "info", label: t(f.moveUnplugged ? "micUnplugged" : "micSwitched") })
    rows.push({ kind: "action", id: "moveTo", icon: GLYPH.mic, label: t("useInstead", f.moveTo), cmd: "mic default" })
  }
  return rows
}

// What dictation needs from you: another try, your desktop's OK for the key.
function dictationHelp(k, t) {
  var d = k.dictation
  var rows = []
  if (d.state === "error")
    rows.push({ kind: "action", id: "dictationRetry", icon: GLYPH.update, label: t("tryAgain"),
      caption: d.message || "", cmd: "model retry" })
  else if (d.message) rows.push({ kind: "info", label: d.message })
  if (d.state === "ready" && d.keyUnbound) {
    rows.push({ kind: "info", label: t("keyUnbound", d.key) })
    if (d.keyButton) rows.push({ kind: "action", id: "keyButton", icon: GLYPH.dictation, label: d.keyButton, cmd: "setup keybutton" })
  }
  return rows
}

// Whether version `a` is newer than `b` (dotted numbers).
function newer(a, b) {
  var x = String(a).split("."), y = String(b).split(".")
  for (var i = 0; i < Math.max(x.length, y.length); i++) {
    var p = parseInt(x[i], 10) || 0, q = parseInt(y[i], 10) || 0
    if (p !== q) return p > q
  }
  return false
}

// A new version of this plugin on GitHub (`plugin`: the one installed and the
// newest, "" until looked), which the menu installs on its own, kyrr as it is.
function pluginUpdate(plugin) {
  return !!(plugin && plugin.version && plugin.latest && newer(plugin.latest, plugin.version))
}

// A new version: install it (or where to get it), what is new, not now.
function updateRows(k, t, always, plugin) {
  var u = k.update
  var rows = []
  if (u.state === "downloading")
    rows.push(u.phase === "installing" ? { kind: "info", label: t("installing") }
      : { kind: "progress", label: t("downloadingUpdate", Math.round((u.progress || 0) * 100)), value: u.progress || 0 })
  else if ((u.state === "available" || u.phase === "downloadFailed") && (always || !u.dismissed)) {
    var failed = u.phase === "downloadFailed"
    if (u.installable)
      rows.push({ kind: "action", id: "update", icon: GLYPH.update, accent: true,
        label: failed ? t("tryAgain") : t("update", u.version),
        caption: failed ? t("updateFailed") : t("updateOut", u.version), cmd: "update install" })
    else
      // Not installable by kyrr itself (Linux): the plugin's own installer
      // swaps the AppImage, as it does for the first install.
      rows.push({ kind: "action", id: "install", icon: GLYPH.update, accent: true,
        label: t("update", u.version), caption: t("updateWindow", u.version) })
    if (u.news) rows.push({ kind: "action", id: "updateNews", icon: GLYPH.news, label: t("whatsNew"), page: "updateNews" })
    if (!always) rows.push({ kind: "action", id: "updateDismiss", label: t("notNow"), cmd: "update dismiss" })
  }
  // A new kyrr brings the new menu along; the menu alone has its own row.
  var withKyrr = rows.some(function(row) { return row.id === "install" })
  if (pluginUpdate(plugin) && !withKyrr)
    rows.push({ kind: "action", id: "installPlugin", icon: GLYPH.update, accent: true,
      label: t("updatePlugin"), caption: t("updatePluginHint", plugin.latest) })
  return rows
}

function main(k, t, plugin) {
  var attached = k.filter.attached !== false
  var rows = [
    { kind: "switch", id: "filter", icon: GLYPH.filter, page: "filter", label: t("filter"),
      checked: k.filter.on, caption: filterCaption(k, t), cmd: "toggle filter" }
  ].concat(filterHelp(k, t))
  rows.push({ kind: "switch", id: "voice", icon: GLYPH.voice, page: "voice", label: t("voice"),
    enabled: attached, checked: k.voice.on, caption: !attached ? t("voiceNeedsMic") : t(k.voice.on ? "voiceOn" : "voiceOff"),
    cmd: "toggle voice" })
  rows.push({ kind: "switch", id: "dictation", icon: GLYPH.dictation, page: "dictation", label: t("dictation"),
    checked: k.dictation.on, cmd: "toggle dictation",
    caption: !k.dictation.on ? t("dictationOff", k.dictation.key)
      : k.dictation.ready ? t("dictationOn", k.dictation.key) : t("dictationNotReady") })
  rows = rows.concat(dictationHelp(k, t))
  if (aiShown(k)) rows = rows.concat(localAiRows(k.ai, t))
  rows.push({ kind: "switch", id: "memos", icon: GLYPH.memos, page: "memos", label: t("memos"),
    checked: k.memos.on, cmd: "toggle memos",
    caption: !k.memos.on ? t("memosOff")
      : k.memos.recording ? t("memosRecordingKey", k.memos.key) : t("memosOnKey", k.memos.key) })
  if (k.memos.on && k.memos.recording)
    rows.push({ kind: "action", id: "stop", icon: GLYPH.stop, label: t("stop"), value: k.memos.elapsed || "", cmd: "memo stop", urgent: true })
  if (k.memos.on)
    rows.push({ kind: "action", id: "recordings", icon: GLYPH.recordings, label: t("recordings"), page: "recordings",
      value: k.memos.count ? String(k.memos.count) : "" })
  // The microphone is muted: the note at the bottom says so, this switches it on.
  if (k.alert === 4) rows.push({ kind: "action", id: "unmute", icon: GLYPH.mic, label: t("unmute"), cmd: "mic unmute", accent: true })
  if (k.overloadNote) {
    rows.push({ kind: "info", label: t(k.overloadNote === "switched" ? "overloadSwitched" : "overloadPauses") })
    rows.push({ kind: "action", id: "overloadSeen", label: t("gotIt"), cmd: "setup overloadSeen" })
  }
  rows = rows.concat(updateRows(k, t, false, plugin))
  rows.push({ kind: "separator" })
  rows.push({ kind: "action", id: "setup", icon: GLYPH.setup, label: t("setup"), page: "setup" })
  return { title: "", rows: rows }
}

function filter(k, t) {
  var hints = ["gentleHint", "mediumHint", "strongHint"]
  return { title: t("filter"), rows: [
    { kind: "switch", id: "filter", label: t("filter"), checked: k.filter.on,
      caption: filterCaption(k, t), cmd: "toggle filter" }
  ].concat(filterHelp(k, t), [
    { kind: "choice", id: "strength", label: t("filterStrength"), enabled: k.filter.on && k.filter.attached !== false,
      options: options(t, ["gentle", "medium", "strong"]), value: k.filter.strength,
      caption: t(pick(hints, k.filter.strength)), cmd: "set filter.strength {}" },
    { kind: "info", label: t("oldCpu"), hidden: !k.oldCpu }
  ]) }
}

function voice(k, t) {
  var v = k.voice
  var tones = ["neutral", "warm", "clear", "bright", "custom"]
  var comp = ["compOff", "compLight", "compMedium", "compStrong"]
  var ess = ["essOff", "essLight", "essMedium", "essStrong"]
  var rows = [
    { kind: "switch", id: "voice", label: t("voice"), checked: v.on, enabled: k.filter.attached !== false,
      caption: t(v.on ? "voiceOn" : "voiceOff"), cmd: "toggle voice" },
    { kind: "choice", id: "tone", label: t("sound"), enabled: v.on, options: named(t, tones), value: v.tone,
      caption: t(v.tone + "Hint"), cmd: "set voice.tone {}" }
  ]
  if (v.tone === "custom") {
    var bands = ["body", "presence", "air"]
    for (var i = 0; i < bands.length; i++)
      rows.push({ kind: "slider", id: bands[i], label: t(bands[i]), enabled: v.on, value: v[bands[i]],
        min: -6, max: 6, step: 1, unit: "dB", cmd: "set voice." + bands[i] + " {}" })
  }
  rows.push({ kind: "choice", id: "comp", label: t("compressor"), enabled: v.on,
    options: options(t, ["off", "light", "medium", "strong"]), value: v.comp,
    caption: t(pick(comp, v.comp)), cmd: "set voice.comp {}" })
  rows.push({ kind: "choice", id: "ess", label: t("ess"), enabled: v.on,
    options: options(t, ["off", "light", "medium", "strong"]), value: v.ess,
    caption: t(pick(ess, v.ess)), cmd: "set voice.ess {}" })
  rows.push({ kind: "section", label: t("microphone") })
  rows.push({ kind: "switch", id: "rumble", label: t("rumble"), enabled: v.on, checked: v.rumble,
    caption: v.rumble ? t("rumbleOn", v.rumbleHz) : t("rumbleOff"), cmd: "toggle voice.rumble" })
  rows.push({ kind: "switch", id: "pops", label: t("pops"), enabled: v.on, checked: v.pops,
    caption: t(v.pops ? "popsOn" : "popsOff"), cmd: "toggle voice.pops" })
  rows.push({ kind: "switch", id: "distance", label: t("distance"), enabled: v.on, checked: v.distance,
    caption: t(v.distance ? "distanceOn" : "distanceOff"), cmd: "toggle voice.distance" })
  rows.push({ kind: "switch", id: "autoLevel", label: t("autoLevel"), checked: v.autoLevel,
    caption: !v.autoLevel ? t("autoLevelOff")
      : v.levelDb === null || v.levelDb === undefined ? t("autoLevelOn")
      : k.levels && !k.levels.active ? t("autoLevelOn") + " " + t("levelWaiting")
      : Math.abs(v.levelDb) < 0.5 ? t("levelSame")
      : t("levelNow", (v.levelDb > 0 ? "+" : "−") + Math.abs(v.levelDb).toFixed(1).replace(".", t("decimal"))),
    cmd: "toggle voice.autoLevel" })
  if (v.isDefault === false) {
    rows.push({ kind: "separator" })
    rows.push({ kind: "action", id: "voiceReset", icon: GLYPH.update, label: t("reset"), caption: t("resetHint"), cmd: "set voice.reset" })
  }
  return { title: t("voice"), rows: rows }
}

// The speech model while it is not there yet: download, progress, retry.
function modelRows(k, t) {
  var m = k.model
  if (m.state === "none")
    return [{ kind: "action", id: "download", icon: GLYPH.update, label: t("modelDownload"),
      caption: t("modelSize", m.size), cmd: "model download", accent: true }]
  if (m.state === "downloading")
    return [{ kind: "progress", label: t("modelLoading", Math.round((m.progress || 0) * 100)), value: m.progress || 0 },
      { kind: "action", id: "cancelDownload", label: t("cancel"), cmd: "model cancel" }]
  if (m.state === "loading") return [{ kind: "info", label: t("modelStarting") }]
  if (m.state === "error")
    return [{ kind: "action", id: "retry", icon: GLYPH.update, label: t("tryAgain"), caption: t("modelFailed"), cmd: "model retry" }]
  return []
}

function dictation(k, t) {
  var d = k.dictation
  var rows = [
    { kind: "switch", id: "dictation", label: t("dictation"), checked: d.on, cmd: "toggle dictation",
      caption: !d.on ? t("dictationOff", d.key) : d.ready ? t("dictationOn", d.key) : t("dictationNotReady") }
  ]
  if (d.on) rows = rows.concat(modelRows(k, t), dictationHelp(k, t))
  if (d.keyFixed) rows.push({ kind: "info", label: t("keyFixed", d.key) })
  else {
    rows.push({ kind: "key", id: "dictationKey", label: t("key"), value: d.key, enabled: d.on, cmd: "set dictation.key {}" })
    if (d.keyCustom) rows.push({ kind: "action", id: "dictationKeyReset", label: t("standardKey", "F9"), enabled: d.on, cmd: "set dictation.keyReset" })
  }
  if (d.note) rows.push({ kind: "info", label: d.note })
  rows.push({ kind: "choice", id: "dictationHow", label: t("how"), enabled: d.on,
    options: [{ value: true, label: t("hold") }, { value: false, label: t("tap") }], value: d.hold,
    caption: t(d.hold ? "dictHold" : "dictTap"), cmd: "set dictation.hold {}" })
  rows.push({ kind: "info", label: t("newLine") })
  return { title: t("dictation"), rows: rows }
}

function memos(k, t) {
  var m = k.memos
  var rows = [
    { kind: "switch", id: "memos", label: t("memos"), checked: m.on, cmd: "toggle memos",
      caption: m.on ? t("memosOnKey", m.key) : t("memosOff") }
  ]
  if (k.dictation.keyFixed) rows.push({ kind: "info", label: t("keyFixed", m.key) })
  else {
    rows.push({ kind: "key", id: "memoKey", label: t("key"), value: m.key, enabled: m.on, cmd: "set memos.key {}" })
    if (m.keyCustom) rows.push({ kind: "action", id: "memoKeyReset", label: t("standardKey", "F8"), enabled: m.on, cmd: "set memos.keyReset" })
  }
  if (m.keyNote) rows.push({ kind: "info", label: m.keyNote })
  else if (k.dictation.note) rows.push({ kind: "info", label: k.dictation.note })
  if (m.canHold === false) rows.push({ kind: "info", label: t("memoTapOnly", k.dictation.key) })
  else
    rows.push({ kind: "choice", id: "memoHow", label: t("how"), enabled: m.on,
      options: [{ value: true, label: t("hold") }, { value: false, label: t("tap") }], value: m.hold,
      caption: t(m.hold ? "memoHold" : "memoTap", k.dictation.key), cmd: "set memos.hold {}" })
  rows.push({ kind: "switch", id: "autoText", label: t("autoText"), enabled: m.on, checked: m.autoText,
    caption: t(m.autoText ? "autoTextOn" : "autoTextOff"), cmd: "toggle memos.autoText" })
  rows.push({ kind: "separator" })
  rows.push({ kind: "action", id: "recordings", icon: GLYPH.recordings, label: t("recordings"), page: "recordings",
    value: m.count ? String(m.count) : "" })
  rows.push({ kind: "action", id: "folder", icon: GLYPH.folder, label: t("openFolder"),
    caption: t("savedIn", m.folder), cmd: "memo folder" })
  rows.push({ kind: "info", label: t("privacy") })
  return { title: t("memos"), rows: rows }
}

// What a recording's text is doing, for its row and its page.
function textNote(r, t) {
  if (r.waiting) return t("textWaiting")
  if (r.text === "writing")
    return t("writingText", Math.round((r.progress || 0) * 100)) + (r.left ? " · " + r.left : "")
  return ""
}

function recordings(k, t) {
  var m = k.memos
  var rows = []
  if (m.recording)
    rows.push({ kind: "action", id: "stop", icon: GLYPH.stop, label: t("stop"), value: m.elapsed || "", cmd: "memo stop", urgent: true })
  else
    rows.push({ kind: "action", id: "new", icon: GLYPH.memos, label: t("newRecording"), value: m.key || "", cmd: "memo start" })
  if (m.count > 0)
    rows.push({ kind: "edit", id: "search", icon: GLYPH.search, placeholder: t("search"), value: m.query || "",
      cmd: "memo search {}", live: true })
  if (m.message) rows.push({ kind: "info", label: m.message })
  if (!m.count) rows.push({ kind: "info", label: t("nothingYet") })
  else if (!m.list.length) rows.push({ kind: "info", label: t("nothingFound") })
  for (var i = 0; i < m.list.length; i++) {
    var r = m.list[i]
    var note = r.pending ? "" : textNote(r, t)
    rows.push({ kind: "memo", id: "memo:" + r.id, memo: r, label: r.pending ? t("findingTitle") : r.title, isNew: r.isNew,
      playing: r.playing, value: r.playing ? m.playTime : "", bar: r.playing ? (m.playFraction || 0) : undefined,
      caption: r.when + " · " + r.length + (note ? " · " + note : r.text === "failed" ? " · " + t("textFailedShort") : ""),
      page: "text:" + r.id, play: "memo play " + r.id })
  }
  rows.push({ kind: "separator" })
  rows.push({ kind: "action", id: "folder", icon: GLYPH.folder, label: t("openFolder"), cmd: "memo folder" })
  if (m.list.length) rows.push({ kind: "info", label: t("recordingKeys") })
  return { title: t("recordings"), rows: rows }
}

// The language model on a recording's text, as under the text in kyrr's
// window: rework, translate, apply, and the original back (the comparison of
// the two texts is a view of the recording's page). An older kyrr says nothing
// of it.
function memoRework(sheet, t) {
  var w = sheet.rework
  var rows = []
  if (!w) return rows
  if (w.ready) {
    rows.push({ kind: "choice", id: "memoRework", label: t("rework"), enabled: !w.busy,
      options: options(t, ["off", "reworkFix", "reworkPolish", "reworkBusiness"]), value: w.action, cmd: "set memos.reworkAction {}" })
    rows.push({ kind: "choice", id: "memoTranslate", label: t("translateInto"), enabled: !w.busy,
      options: targets(t), value: w.target || "off", cmd: "set memos.reworkTarget {}" })
  }
  var buttons = []
  if (w.ready)
    buttons.push({ id: "rework", icon: GLYPH.ai, label: t(w.busy ? "cancel" : "apply"),
      cmd: w.busy ? "memo stoprework" : "memo rework", enabled: w.busy || (!sheet.empty && (w.action > 0 || !!w.target)) })
  if (w.original && !w.busy)
    buttons.push({ id: "restore", icon: GLYPH.update, label: t("restoreOriginal"), cmd: "memo restore" })
  if (buttons.length) rows.push({ kind: "buttons", id: "reworkTools", buttons: buttons })
  if (w.ready && w.busy)
    rows.push({ kind: "progress", label: Math.round((w.progress || 0) * 100) + " %", value: w.progress || 0 })
  if (w.note) rows.push({ kind: "info", label: w.note })
  return rows
}

// One recording, like the text view of kyrr's window: its title to rename,
// playing, the text to read, correct and copy, and the rest.
function memoText(k, t, id) {
  var m = k.memos
  var sheet = m.sheet || null
  var r = null
  for (var i = 0; i < m.list.length; i++) if (m.list[i].id === id) r = m.list[i]
  // Renamed: the file has a new name, the open text follows it.
  if (!r && sheet)
    for (var j = 0; j < m.list.length; j++) if (m.list[j].id === sheet.id) r = m.list[j]
  if (!r) return { title: t("recordings"), rows: [{ kind: "info", label: t("memoGone") }] }
  var rows = [
    { kind: "edit", id: "title", label: t("title"), value: r.title, rename: r.id },
    { kind: "action", id: "play", icon: r.playing ? GLYPH.stop : GLYPH.play, label: r.playing ? t("stop") : t("play"),
      value: r.playing ? m.playTime : r.length, caption: r.when, cmd: "memo play " + r.id,
      bar: r.playing ? (m.playFraction || 0) : undefined }
  ]
  // The rows around the text stay put while it plays or saves, so the text
  // field is never made anew under the cursor.
  var open = sheet && sheet.id === r.id
  if (r.text === "ready" && open) {
    var w = sheet.rework
    // After a rework the text can be read beside the one before it.
    var comparing = !!(w && w.original && !w.busy && sheet.view === 1)
    if (w && w.original && !w.busy)
      rows.push({ kind: "choice", id: "view", label: t("view"), options: options(t, ["viewText", "viewCompare"]),
        value: comparing ? 1 : 0, cmd: "memo view {}" })
    if (comparing) {
      rows.push({ kind: "compare", id: "compare", memo: r.id })
      rows.push({ kind: "info", label: t("compareHint") })
    } else {
      // The language model at work: the text is not typed into meanwhile.
      rows.push({ kind: "editor", id: "editor", memo: r.id, locked: !!(w && w.busy) })
      rows.push({ kind: "info", label: sheet.empty ? t("nothingUnderstood") : sheet.saved ? t("copyHint") : t("saving") })
      // A row of buttons each, so the whole page fits without scrolling.
      rows.push({ kind: "buttons", id: "textTools", buttons: [
        { id: "copy", icon: GLYPH.copy, label: sheet.copied ? "✓ " + t("copied") : t("copy") },
        { id: "here", icon: GLYPH.play, label: t("playHere") + (sheet.here ? " " + sheet.here : "") },
        { id: "opentext", icon: GLYPH.file, label: t("textFile"), cmd: "memo opentext" }
      ] })
      rows.push({ kind: "choice", id: "stamps", label: t("times"),
        options: options(t, ["stampsOff", "stampsPosition", "stampsClock"]), value: sheet.stamps, cmd: "memo stamps {}" })
    }
    rows = rows.concat(memoRework(sheet, t))
  } else if (r.text === "writing" || r.waiting) {
    rows.push({ kind: "progress", label: textNote(r, t), value: r.progress || 0 })
    rows.push({ kind: "action", id: "cancelText", label: t("cancel"), cmd: "memo cancel " + r.id })
  } else if (r.text === "failed") {
    rows.push({ kind: "action", id: "write", icon: GLYPH.dictation, label: t("tryAgain"),
      caption: t(m.canWrite ? "textFailed" : "needsModel"), cmd: "memo text " + r.id, enabled: !!m.canWrite })
  } else if (r.text !== "ready") {
    rows.push({ kind: "action", id: "write", icon: GLYPH.dictation, label: t("writeText"),
      caption: m.canWrite ? "" : t("needsModel"), cmd: "memo text " + r.id, enabled: !!m.canWrite })
  }
  rows.push({ kind: "buttons", id: "fileTools", memo: r, buttons: [
    { id: "reveal", icon: GLYPH.folder, label: t("showInFolder"), cmd: "memo reveal " + r.id },
    { id: "deleteMemo", icon: GLYPH.trash, label: t("delete"), urgent: true }
  ] })
  return { title: r.pending ? t("findingTitle") : r.title, rows: rows }
}

function setup(k, t, plugin) {
  var g = k.general
  var effortHint = { best: "bestHint", lean: "leanHint", custom: "effortCustomHint" }
  var u = k.update
  var rows = [
    { kind: "choice", id: "language", label: t("language"),
      options: [{ value: "de", label: t("german") }, { value: "en", label: t("english") }, { value: "multi", label: t("multi") }],
      value: g.language, caption: t(g.language === "multi" ? "multiHint" : "languageHint"), cmd: "set general.language {}" },
    { kind: "action", id: "mic", icon: GLYPH.mic, label: t("microphone"), value: k.mic.name, page: "mic" },
    // A mix of the two (set in kyrr's window elsewhere) shows as a third
    // choice only while it is the one in use.
    { kind: "choice", id: "effort", label: t("effort"),
      options: named(t, g.effort === "custom" ? ["lean", "best", "custom"] : ["lean", "best"]), value: g.effort,
      caption: t(effortHint[g.effort]), cmd: "set general.effort {}" }
  ]
  if (g.effort === "custom") {
    rows.push({ kind: "switch", id: "liveText", label: t("liveText"), checked: g.liveText,
      caption: t(g.liveText ? "liveTextOn" : "liveTextOff"), cmd: "toggle general.liveText" })
  }
  rows.push({ kind: "switch", id: "overload", label: t("overload"), checked: g.overload,
    caption: t(g.overload ? "overloadOn" : "overloadOff"), cmd: "toggle general.overload" })
  if (k.ai && k.ai.asr) {
    rows.push({ kind: "action", id: "ownDictation", icon: GLYPH.dictation, label: t("ownDictation"),
      value: k.ai.asr.on ? t("ownServer") : "", caption: t("ownDictationHint"), page: "asr" })
    rows.push({ kind: "switch", id: "aiFeatures", label: t("experimental"), checked: k.ai.features,
      caption: t(k.ai.features ? "experimentalOn" : "experimentalOff"), cmd: "toggle ai.features" })
  }
  rows.push({ kind: "section", label: t("check") })
  if (k.filter.attached !== false && k.levels) {
    rows.push({ kind: "progress", label: t("levelYourMic"), value: k.levels.before || 0 })
    rows.push({ kind: "progress", label: t("levelApps"), value: k.levels.after || 0 })
    rows.push({ kind: "info", label: t("levelHint") })
  }
  rows.push({ kind: "switch", id: "listen", label: t("listen"), checked: k.listen, caption: t("listenHint"), cmd: "toggle listen" })
  rows.push({ kind: "action", id: "test", icon: GLYPH.check, label: t("test"),
    caption: k.probe === "recording" ? t("recording") : t("testHint"), cmd: k.probe === "idle" ? "test start" : "" })
  if (k.hasProbe) {
    rows.push({ kind: "action", id: "before", icon: GLYPH.play, label: t("testBefore"), caption: t("testBeforeHint"), cmd: "test before" })
    rows.push({ kind: "action", id: "after", icon: GLYPH.play, label: t("testAfter"), caption: t("testAfterHint"), cmd: "test after" })
    rows.push({ kind: "action", id: "testDelete", icon: GLYPH.trash, label: t("testDelete"), cmd: "test delete" })
  }
  if (k.probeError) rows.push({ kind: "info", label: k.probeError })
  rows.push({ kind: "section", label: t("updates") })
  rows.push({ kind: "switch", id: "updateCheck", label: t("updateAuto"), checked: g.updateCheck,
    caption: t(g.updateCheck ? "updateAutoOn" : "updateAutoOff"), cmd: "toggle general.updateCheck" })
  var updates = updateRows(k, t, true, plugin)
  if (updates.length) rows = rows.concat(updates)
  else
    rows.push({ kind: "action", id: "checkUpdate", icon: GLYPH.update, label: t("checkUpdates"),
      caption: u.state === "checking" ? t("checking") : u.state === "latest" ? t("latest") : u.state === "failed" ? t("checkFailed") : "",
      cmd: "update check" })
  rows.push({ kind: "separator" })
  rows.push({ kind: "action", id: "about", icon: GLYPH.about, label: t("about"), value: k.version, page: "about" })
  return { title: t("setup"), rows: rows }
}

function mic(k, t) {
  var rows = []
  for (var i = 0; i < k.mic.list.length; i++) {
    var m = k.mic.list[i]
    rows.push({ kind: "radio", id: "mic:" + m.id, label: m.name, checked: m.id === k.mic.current, cmd: "mic " + m.id })
  }
  return { title: t("microphone"), rows: rows }
}

function about(k, t) {
  return { title: t("about"), rows: [
    { kind: "info", label: t("version", k.version) },
    { kind: "action", id: "feedback", icon: GLYPH.feedback, label: t("feedback"), cmd: "open feedback" },
    { kind: "action", id: "licenses", icon: GLYPH.file, label: t("licenses"), cmd: "open licenses" },
    { kind: "info", label: t("aboutLine") },
    { kind: "section", label: t("credits") },
    { kind: "info", label: t("creditsNoise") },
    { kind: "info", label: t("creditsDe") },
    { kind: "info", label: t("creditsEn") },
    { kind: "info", label: t("creditsMore") },
    { kind: "section", label: t("news", k.version), hidden: !k.news },
    { kind: "info", label: k.news || "", body: true, hidden: !k.news }
  ] }
}

// The first start: three steps, like kyrr's window elsewhere.
function welcome(k, t) {
  var step = k.setupStep || 1
  var rows = [{ kind: "info", label: t("step", step), dim: true }]
  if (step === 1) {
    rows.push({ kind: "info", label: t("welcomeMic") })
    for (var i = 0; i < k.mic.list.length; i++) {
      var m = k.mic.list[i]
      rows.push({ kind: "radio", id: "mic:" + m.id, label: m.name, checked: m.id === k.mic.index, cmd: "mic " + m.id })
    }
    rows.push({ kind: "info", label: t("welcomeMicNote") })
    if (k.filter.setup === "error" && k.filter.error) rows.push({ kind: "info", label: k.filter.error })
    rows.push({ kind: "action", id: "next", icon: GLYPH.next, accent: true,
      label: k.filter.setup === "settingUp" ? t("settingUp") : t("next"),
      cmd: k.filter.setup === "settingUp" ? "" : "setup next" })
    rows.push({ kind: "action", id: "skip", label: t("setupSkip"), cmd: "setup skip" })
  } else if (step === 2) {
    rows.push({ kind: "choice", id: "language", label: t("language"),
      options: [{ value: "de", label: t("german") }, { value: "en", label: t("english") }, { value: "multi", label: t("multi") }],
      value: k.general.language, caption: t(k.general.language === "multi" ? "multiHint" : "languageHint"), cmd: "set general.language {}" })
    rows = rows.concat(modelRows(k, t))
    if (k.model.state === "ready") rows.push({ kind: "info", label: t("modelReady") })
    rows.push({ kind: "info", label: t("welcomeDictation", k.dictation.key) })
    rows.push({ kind: "action", id: "next", icon: GLYPH.next, label: t("next"), cmd: "setup next", accent: true })
  } else {
    rows.push({ kind: "info", label: t("performanceQuestion") })
    rows.push({ kind: "radio", id: "best", label: t("best"), caption: t("bestSetup"),
      checked: k.general.effort !== "lean", cmd: "set general.effort best" })
    rows.push({ kind: "radio", id: "lean", label: t("lean"), caption: t("leanSetup"),
      checked: k.general.effort === "lean", cmd: "set general.effort lean" })
    rows.push({ kind: "info", label: t("welcomeDone") })
    rows.push({ kind: "action", id: "done", icon: GLYPH.next, label: t("done"), cmd: "setup done", accent: true })
  }
  return { title: t(step === 1 ? "welcome" : step === 2 ? "languageModel" : "performance"), rows: rows }
}

function updateNews(k, t, plugin) {
  return { title: t("whatsNew"), rows: [
    { kind: "info", label: t("news", k.update.version) },
    { kind: "info", label: k.update.news || "", body: true }
  ].concat(updateRows(k, t, true, plugin).filter(function(row) { return row.id !== "updateNews" })) }
}

function build(page, k, t, plugin) {
  var view = page_(page, k, t, plugin)
  view.rows = view.rows.filter(function(row) { return !row.hidden })
  return view
}

function page_(page, k, t, plugin) {
  if (!k.setupDone) return welcome(k, t)
  if (page.indexOf("text:") === 0) return memoText(k, t, page.slice(5))
  switch (page) {
  case "filter": return filter(k, t)
  case "voice": return voice(k, t)
  case "dictation": return dictation(k, t)
  case "memos": return memos(k, t)
  case "recordings": return recordings(k, t)
  case "setup": return setup(k, t, plugin)
  case "mic": return mic(k, t)
  case "about": return about(k, t)
  case "updateNews": return updateNews(k, t, plugin)
  case "ai": return aiShown(k) ? ai(k, t) : main(k, t, plugin)
  case "asr": return k.ai && k.ai.asr ? asr(k, t) : main(k, t, plugin)
  default: return main(k, t, plugin)
  }
}

// Rows the keyboard cursor can stop on.
function selectable(row) {
  return row.kind !== "section" && row.kind !== "info" && row.kind !== "progress" && row.kind !== "separator"
}
