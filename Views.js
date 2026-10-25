.pragma library

// What each page of the menu shows, built from kyrr's state (see
// README.md, "State"). A page is a title and a list of rows; Panel.qml draws
// them and walks them with the keyboard. Rows:
//   switch   on/off, Enter flips it; with `page`, → opens its settings
//   choice   one of `options`, ← → step through them, Enter takes the next
//   slider   a number from `min` to `max`, ← → move it by `step`
//   key      a key to press, Enter starts listening for it
//   action   does `cmd`, or opens `page`
//   memo     a recording: Enter plays it, → shows its text, x deletes it
//   section  a heading, never selected
//   info     a line of text, never selected
//   progress a bar from 0 to 1, never selected
// `cmd` is what goes to kyrr's socket; {} in it stands for the new value.

var GLYPH = {
  filter: 0xF036C, voice: 0xF0068, dictation: 0xF030C, memos: 0xF044A,
  stop: 0xF04DB, recordings: 0xF1359, update: 0xF01DA, setup: 0xF066A,
  install: 0xF01DA, mic: 0xF036C, folder: 0xF0770, play: 0xF040A,
  check: 0xF02CB, about: 0xF02FD, news: 0xF0EBB, feedback: 0xF0361,
  next: 0xF0142
}

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

function main(k, t) {
  var rows = [
    { kind: "switch", id: "filter", icon: GLYPH.filter, page: "filter", label: t("filter"),
      checked: k.filter.on, caption: t(k.filter.on ? "filterOn" : "filterOff"), cmd: "toggle filter" },
    { kind: "switch", id: "voice", icon: GLYPH.voice, page: "voice", label: t("voice"),
      enabled: k.filter.attached !== false, checked: k.voice.on, caption: t(k.voice.on ? "voiceOn" : "voiceOff"), cmd: "toggle voice" },
    { kind: "switch", id: "dictation", icon: GLYPH.dictation, page: "dictation", label: t("dictation"),
      checked: k.dictation.on, cmd: "toggle dictation",
      caption: !k.dictation.on ? t("dictationOff", k.dictation.key)
        : k.dictation.ready ? t("dictationOn", k.dictation.key) : t("dictationNotReady") },
    { kind: "switch", id: "memos", icon: GLYPH.memos, page: "memos", label: t("memos"),
      checked: k.memos.on, cmd: "toggle memos",
      caption: !k.memos.on ? t("memosOff")
        : k.memos.recording ? t("memosRecordingKey", k.memos.key) : t("memosOnKey", k.memos.key) }
  ]
  if (k.memos.on && k.memos.recording)
    rows.push({ kind: "action", id: "stop", icon: GLYPH.stop, label: t("stop"), cmd: "memo stop", urgent: true })
  if (k.memos.on)
    rows.push({ kind: "action", id: "recordings", icon: GLYPH.recordings, label: t("recordings"), page: "recordings",
      value: k.memos.list.length ? String(k.memos.list.length) : "" })
  if (k.update.state === "available")
    rows.push({ kind: "action", id: "update", icon: GLYPH.update, label: t("update", k.update.version), cmd: "update install" })
  rows.push({ kind: "separator" })
  rows.push({ kind: "action", id: "setup", icon: GLYPH.setup, label: t("setup"), page: "setup" })
  return { title: "", rows: rows }
}

function filter(k, t) {
  var hints = ["gentleHint", "mediumHint", "strongHint"]
  return { title: t("filter"), rows: [
    { kind: "switch", id: "filter", label: t("filter"), checked: k.filter.on,
      caption: t(k.filter.on ? "filterOn" : "filterOff"), cmd: "toggle filter" },
    { kind: "choice", id: "strength", label: t("filterStrength"), enabled: k.filter.on,
      options: options(t, ["gentle", "medium", "strong"]), value: k.filter.strength,
      caption: t(pick(hints, k.filter.strength)), cmd: "set filter.strength {}" }
  ] }
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
      : Math.abs(v.levelDb) < 0.5 ? t("levelSame")
      : t("levelNow", (v.levelDb > 0 ? "+" : "−") + Math.abs(v.levelDb).toFixed(1).replace(".", t("decimal"))),
    cmd: "toggle voice.autoLevel" })
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
  if (d.on) rows = rows.concat(modelRows(k, t))
  rows.push({ kind: "key", id: "dictationKey", label: t("key"), value: d.key, enabled: d.on, cmd: "set dictation.key {}" })
  if (d.note) rows.push({ kind: "info", label: d.note })
  rows.push({ kind: "choice", id: "dictationHow", label: t("how"), enabled: d.on,
    options: [{ value: true, label: t("hold") }, { value: false, label: t("tap") }], value: d.hold,
    caption: t(d.hold ? "dictHold" : "dictTap"), cmd: "set dictation.hold {}" })
  rows.push({ kind: "info", label: t("newLine") })
  return { title: t("dictation"), rows: rows }
}

function memos(k, t) {
  var m = k.memos
  return { title: t("memos"), rows: [
    { kind: "switch", id: "memos", label: t("memos"), checked: m.on, cmd: "toggle memos",
      caption: m.on ? t("memosOnKey", m.key) : t("memosOff") },
    { kind: "key", id: "memoKey", label: t("key"), value: m.key, enabled: m.on, cmd: "set memos.key {}" },
    { kind: "info", label: k.dictation.note || "", hidden: !k.dictation.note },
    { kind: "choice", id: "memoHow", label: t("how"), enabled: m.on,
      options: [{ value: true, label: t("hold") }, { value: false, label: t("tap") }], value: m.hold,
      caption: t(m.hold ? "memoHold" : "memoTap", k.dictation.key), cmd: "set memos.hold {}" },
    { kind: "switch", id: "autoText", label: t("autoText"), enabled: m.on, checked: m.autoText,
      caption: t(m.autoText ? "autoTextOn" : "autoTextOff"), cmd: "toggle memos.autoText" },
    { kind: "separator" },
    { kind: "action", id: "recordings", icon: GLYPH.recordings, label: t("recordings"), page: "recordings",
      value: m.list.length ? String(m.list.length) : "" },
    { kind: "action", id: "folder", icon: GLYPH.folder, label: t("openFolder"),
      caption: t("savedIn", m.folder), cmd: "memo folder" },
    { kind: "info", label: t("privacy") }
  ] }
}

function recordings(k, t) {
  var m = k.memos
  var rows = []
  if (m.recording)
    rows.push({ kind: "action", id: "stop", icon: GLYPH.stop, label: t("stop"), cmd: "memo stop", urgent: true })
  else
    rows.push({ kind: "action", id: "new", icon: GLYPH.memos, label: t("newRecording"), cmd: "memo start" })
  if (m.message) rows.push({ kind: "info", label: m.message })
  if (!m.list.length) rows.push({ kind: "info", label: t("nothingYet") })
  for (var i = 0; i < m.list.length; i++) {
    var r = m.list[i]
    rows.push({ kind: "memo", id: "memo:" + r.id, memo: r, label: r.title, isNew: r.isNew,
      caption: r.when + " · " + r.length
        + (r.text === "writing" ? " · " + t("writingText", Math.round((r.progress || 0) * 100)) : ""),
      page: "text:" + r.id, cmd: "memo play " + r.id })
  }
  if (m.list.length) rows.push({ kind: "info", label: t("recordingKeys") })
  return { title: t("recordings"), rows: rows }
}

function memoText(k, t, id) {
  var r = null
  for (var i = 0; i < k.memos.list.length; i++) if (k.memos.list[i].id === id) r = k.memos.list[i]
  if (!r) return { title: t("recordings"), rows: [] }
  var rows = [{ kind: "action", id: "play", icon: GLYPH.play, label: t("play"), caption: r.when + " · " + r.length,
    cmd: "memo play " + r.id }]
  if (r.text === "ready") rows.push({ kind: "info", label: r.transcript || "", body: true })
  else if (r.text === "writing") rows.push({ kind: "progress", label: t("writingText", Math.round((r.progress || 0) * 100)), value: r.progress || 0 })
  else rows.push({ kind: "action", id: "write", icon: GLYPH.dictation, label: t("writeText"), cmd: "memo text " + r.id })
  return { title: r.title, rows: rows }
}

function setup(k, t) {
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
  rows.push({ kind: "section", label: t("check") })
  rows.push({ kind: "switch", id: "listen", label: t("listen"), checked: k.listen, caption: t("listenHint"), cmd: "toggle listen" })
  rows.push({ kind: "action", id: "test", icon: GLYPH.check, label: t("test"),
    caption: k.probe === "recording" ? t("recording") : t("testHint"), cmd: k.probe === "idle" ? "test start" : "" })
  if (k.hasProbe) {
    rows.push({ kind: "action", id: "before", icon: GLYPH.play, label: t("testBefore"), caption: t("testBeforeHint"), cmd: "test before" })
    rows.push({ kind: "action", id: "after", icon: GLYPH.play, label: t("testAfter"), caption: t("testAfterHint"), cmd: "test after" })
  }
  rows.push({ kind: "section", label: t("updates") })
  rows.push({ kind: "switch", id: "updateCheck", label: t("updateAuto"), checked: g.updateCheck,
    caption: t(g.updateCheck ? "updateAutoOn" : "updateAutoOff"), cmd: "toggle general.updateCheck" })
  if (u.state === "available")
    rows.push({ kind: "action", id: "update", icon: GLYPH.update, label: t("updateNow"), caption: t("updateOut", u.version), cmd: "update install" })
  else if (u.state === "downloading")
    rows.push({ kind: "progress", label: t("downloadingUpdate", Math.round((u.progress || 0) * 100)), value: u.progress || 0 })
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
    rows.push({ kind: "radio", id: "mic:" + m.id, label: m.name, checked: m.name === k.mic.name, cmd: "mic " + m.id })
  }
  return { title: t("microphone"), rows: rows }
}

function about(k, t) {
  return { title: t("about"), rows: [
    { kind: "info", label: t("version", k.version) },
    { kind: "action", id: "feedback", icon: GLYPH.feedback, label: t("feedback"), cmd: "open feedback" },
    { kind: "info", label: t("aboutLine") },
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

function build(page, k, t) {
  var view = page_(page, k, t)
  view.rows = view.rows.filter(function(row) { return !row.hidden })
  return view
}

function page_(page, k, t) {
  if (!k.setupDone) return welcome(k, t)
  if (page.indexOf("text:") === 0) return memoText(k, t, page.slice(5))
  switch (page) {
  case "filter": return filter(k, t)
  case "voice": return voice(k, t)
  case "dictation": return dictation(k, t)
  case "memos": return memos(k, t)
  case "recordings": return recordings(k, t)
  case "setup": return setup(k, t)
  case "mic": return mic(k, t)
  case "about": return about(k, t)
  default: return main(k, t)
  }
}

// Rows the keyboard cursor can stop on.
function selectable(row) {
  return row.kind !== "section" && row.kind !== "info" && row.kind !== "progress" && row.kind !== "separator"
}
