// States of kyrr the menu has to draw. They all start from the contract's
// sample state and change what a case is about.

const clone = (value) => JSON.parse(JSON.stringify(value))

export function variants(sample) {
  const list = []
  const add = (name, change) => {
    const state = clone(sample)
    change(state)
    list.push({ name, state })
  }

  add("sample as it is", () => {})
  add("English", (k) => { k.lang = "en" })

  // First-run setup.
  add("setup step 1", (k) => { k.setupDone = false; k.setupStep = 1 })
  add("setup step 1, setting up", (k) => { k.setupDone = false; k.setupStep = 1; k.filter.setup = "settingUp" })
  add("setup step 1, failed", (k) => { k.setupDone = false; k.setupStep = 1; k.filter.setup = "error"; k.filter.error = "Kein Mikrofon" })
  add("setup step 1, no microphone", (k) => { k.setupDone = false; k.setupStep = 1; k.mic.list = [] })
  add("setup step 2", (k) => { k.setupDone = false; k.setupStep = 2 })
  for (const state of ["none", "downloading", "loading", "error"]) {
    add(`setup step 2, model ${state}`, (k) => {
      k.setupDone = false; k.setupStep = 2; k.model.state = state; k.model.progress = 0.4
    })
  }
  add("setup step 2, multi language", (k) => { k.setupDone = false; k.setupStep = 2; k.general.language = "multi" })
  add("setup step 3", (k) => { k.setupDone = false; k.setupStep = 3 })
  add("setup step 3, lean", (k) => { k.setupDone = false; k.setupStep = 3; k.general.effort = "lean" })
  add("setup step missing", (k) => { k.setupDone = false; delete k.setupStep })

  // The filter.
  for (const state of ["settingUp", "passthrough", "notAttached", "detached", "notInstalled", "unsupported"]) {
    add(`filter ${state}`, (k) => {
      k.filter.state = state
      k.filter.on = state === "passthrough"
      // As kyrr derives it: improving the voice needs the filter on a microphone.
      k.filter.attached = !["notAttached", "notInstalled", "unsupported"].includes(state)
    })
  }
  add("filter detached, moveTo set", (k) => {
    k.filter.state = "detached"; k.filter.moveTo = "Laptop-Mikrofon"
  })
  add("filter moveTo set, mic unplugged", (k) => {
    k.filter.moveTo = "Laptop-Mikrofon"; k.filter.moveUnplugged = true
  })
  add("filter off", (k) => { k.filter.on = false })
  for (const strength of [0, 2]) add(`filter strength ${strength}`, (k) => { k.filter.strength = strength })
  add("old CPU", (k) => { k.oldCpu = true })

  // Voice.
  for (const tone of ["neutral", "clear", "bright", "custom"]) add(`voice tone ${tone}`, (k) => { k.voice.tone = tone })
  for (const level of [0, 2, 3]) add(`voice compressor and de-esser ${level}`, (k) => { k.voice.comp = level; k.voice.ess = level })
  add("voice off", (k) => { k.voice.on = false })
  add("voice default, rumble off", (k) => { k.voice.isDefault = true; k.voice.rumble = false; k.voice.pops = false; k.voice.distance = false })
  add("auto level without a level", (k) => { k.voice.levelDb = null })
  add("auto level same", (k) => { k.voice.levelDb = 0.2 })
  add("auto level lower", (k) => { k.voice.levelDb = -3.14 })
  add("auto level waiting", (k) => { k.levels.active = false; k.voice.levelDb = 1 })
  add("auto level off", (k) => { k.voice.autoLevel = false })

  // Dictation.
  add("dictation off", (k) => { k.dictation.on = false })
  add("dictation not ready", (k) => { k.dictation.ready = false; k.dictation.state = "loading" })
  // The speech model's state and dictation's go together as kyrr writes them.
  const dictationStates = { off: "off", none: "noModel", downloading: "downloading", loading: "loading", error: "error" }
  for (const [model, state] of Object.entries(dictationStates)) {
    add(`dictation, model ${model}`, (k) => {
      k.dictation.ready = false; k.model.state = model; k.model.progress = 0.65
      k.dictation.state = state
      if (model === "error") k.dictation.message = "Modell kaputt"
    })
  }
  for (const state of ["recording", "transcribing"]) add(`dictation ${state}`, (k) => { k.dictation.state = state; k.mode = state === "recording" ? "listening" : "writing" })
  add("dictation error without a message", (k) => { k.dictation.state = "error"; k.dictation.message = "" })
  add("dictation message", (k) => { k.dictation.message = "Etwas ist passiert" })
  add("dictation key unbound with a button", (k) => { k.dictation.keyUnbound = true; k.dictation.keyButton = "Taste erlauben" })
  add("dictation key unbound", (k) => { k.dictation.keyUnbound = true })
  add("dictation key fixed", (k) => { k.dictation.keyFixed = true })
  add("dictation key custom, note", (k) => { k.dictation.keyCustom = true; k.memos.keyCustom = true; k.dictation.note = "Hinweis" })
  add("dictation tap, memos tap only", (k) => { k.dictation.hold = false; k.memos.hold = false; k.memos.canHold = false })
  add("memo key note", (k) => { k.memos.keyNote = "Taste belegt" })

  // Memos.
  add("memos recording", (k) => { k.memos.recording = true; k.memos.elapsed = "0:07"; k.mode = "recording" })
  add("memos off", (k) => { k.memos.on = false })
  add("memos empty list", (k) => { k.memos.count = 0; k.memos.list = []; k.memos.sheet = null })
  add("memos found nothing", (k) => { k.memos.query = "zzz"; k.memos.list = []; k.memos.sheet = null })
  add("memos message", (k) => { k.memos.message = "Ordner fehlt" })
  add("memos sheet null", (k) => { k.memos.sheet = null })
  add("memos without sheet field", (k) => { delete k.memos.sheet })
  add("memo playing", (k) => {
    k.memos.list[0].playing = true; k.memos.playTime = "0:12"; k.memos.playFraction = 0.3
  })
  add("memo pending", (k) => { k.memos.list[0].pending = true; k.memos.list[0].text = "" })
  add("memo waiting for its text", (k) => { k.memos.list[0].text = ""; k.memos.list[0].waiting = true })
  for (const text of ["", "writing", "failed"]) {
    add(`memo text '${text}'`, (k) => { k.memos.list[0].text = text; k.memos.list[0].progress = 0.5; k.memos.list[0].left = "2 Min." })
  }
  add("memo text failed, cannot write", (k) => { k.memos.list[0].text = "failed"; k.memos.canWrite = false })
  add("memo not ready, cannot write", (k) => { k.memos.list[0].text = ""; k.memos.canWrite = false })
  add("memo text failed", (k) => { k.memos.list[1].text = "failed" })
  add("memo sheet of another memo", (k) => { k.memos.sheet.id = k.memos.list[1].id })
  add("memo sheet empty", (k) => { k.memos.sheet.empty = true })
  add("memo sheet saving, copied", (k) => { k.memos.sheet.saved = false; k.memos.sheet.copied = true })
  for (const stamps of [1, 2]) add(`memo sheet stamps ${stamps}`, (k) => { k.memos.sheet.stamps = stamps })
  add("memo rework busy", (k) => { k.memos.sheet.rework.busy = true; k.memos.sheet.rework.progress = 0.3; k.memos.sheet.rework.note = "Moment" })
  add("memo rework original", (k) => { k.memos.sheet.rework.original = true; k.memos.sheet.rework.target = "en" })
  add("memo rework not ready", (k) => { k.memos.sheet.rework.ready = false })
  add("memo rework absent (older kyrr)", (k) => { delete k.memos.sheet.rework })
  add("memo with a search", (k) => { k.memos.query = "idee" })
  add("memo seen", (k) => { k.memos.list.forEach((m) => { m.isNew = false }) })
  add("many memos", (k) => {
    for (let i = 0; i < 12; i++) k.memos.list.push({ ...clone(k.memos.list[1]), id: `2026-10-0${(i % 9) + 1} 10-00 Aufnahme ${i}.opus`, title: `Aufnahme ${i}` })
    k.memos.count = k.memos.list.length
  })

  // Local AI and the own dictation server.
  add("ai missing (kyrr 0.7)", (k) => { delete k.ai })
  add("ai features off", (k) => { k.ai.features = false })
  add("ai on, not ready", (k) => { k.ai.ready = false })
  add("ai off", (k) => { k.ai.on = false })
  add("ai found a server", (k) => { k.ai.found = "Ollama"; k.ai.ready = false })
  add("ai busy, note", (k) => { k.ai.busy = true; k.ai.note = "Fragt …"; k.ai.keySet = true })
  add("ai without models", (k) => { k.ai.models = []; k.ai.model = "" })
  add("ai model not in the list", (k) => { k.ai.model = "anderes:7b" })
  add("ai translates", (k) => { k.ai.translate = "fr"; k.ai.rework = 3 })
  add("ai prompt own, translate", (k) => { k.ai.prompt = { index: 3, own: true } })
  add("ai without prompt", (k) => { delete k.ai.prompt })
  add("asr on", (k) => { k.ai.asr.on = true; k.ai.asr.url = "http://192.168.1.10:8000" })
  add("asr on, found, with models", (k) => {
    k.ai.asr.on = true; k.ai.asr.found = "speaches"; k.ai.asr.models = ["whisper-small"]; k.ai.asr.model = "whisper-small"
    k.ai.asr.busy = true; k.ai.asr.note = "Fertig"; k.ai.asr.keySet = true
  })

  // Updates.
  add("update available, installable", (k) => { k.update.installable = true })
  add("update available, not installable", (k) => { k.update.installable = false })
  add("update available, no news", (k) => { k.update.news = ""; k.news = "" })
  add("update downloading", (k) => { k.update.state = "downloading"; k.update.progress = 0.5 })
  add("update installing", (k) => { k.update.installable = true; k.update.state = "downloading"; k.update.phase = "installing" })
  // kyrr says "failed" for a failed check and a failed download alike.
  add("update download failed", (k) => { k.update.installable = true; k.update.state = "failed"; k.update.phase = "downloadFailed" })
  add("update download failed, not installable", (k) => { k.update.state = "failed"; k.update.phase = "downloadFailed" })
  add("update dismissed", (k) => { k.update.dismissed = true })
  for (const state of ["checking", "latest", "failed", "idle"]) {
    add(`update ${state}`, (k) => { k.update.state = state })
  }
  add("update checks off", (k) => { k.general.updateCheck = false; k.update.state = "latest" })

  // Notes and the rest.
  add("overload note switched", (k) => { k.overloadNote = "switched" })
  add("overload note pauses", (k) => { k.overloadNote = "pauses" })
  add("alert 4", (k) => { k.alert = 4 })
  add("note", (k) => { k.note = "Mikrofon weg"; k.noteGood = false })
  add("effort lean", (k) => { k.general.effort = "lean" })
  add("effort custom", (k) => { k.general.effort = "custom"; k.general.liveText = false })
  add("language multi", (k) => { k.general.language = "multi" })
  add("language en", (k) => { k.general.language = "en" })
  add("listen, test recording", (k) => { k.listen = true; k.probe = "recording" })
  add("test done", (k) => { k.probe = "done"; k.hasProbe = true; k.probeError = "Nicht lesbar" })
  add("levels missing", (k) => { delete k.levels })
  add("microphone not attached", (k) => { k.filter.attached = false; k.filter.state = "notAttached" })
  add("microphone in use not in the list", (k) => { k.mic.current = -1 })
  add("no microphones", (k) => { k.mic.list = []; k.mic.name = "" })
  add("no news", (k) => { k.news = "" })

  return list
}
