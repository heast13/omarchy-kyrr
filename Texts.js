.pragma library

// The menu's texts in kyrr's two languages, the same words kyrr uses in its
// window and tray menu. {} stands for a key's name or a version.
var de = {
  notInstalled: "Noch nicht installiert",
  notRunning: "Läuft gerade nicht",
  listening: "Hört zu …",
  writing: "Schreibt …",
  recording: "Nimmt auf …",
  ready: "Bereit",
  readyKey: "Bereit · Diktieren mit {}",
  filter: "Stimme isolieren",
  filterOn: "Nur deine Stimme. Tastatur, Lüfter und Hund bleiben draußen.",
  filterOff: "Aus. Dein Mikro läuft unverändert durch.",
  voice: "Stimme verbessern",
  voiceOn: "Ein bisschen Politur für deine Stimme.",
  voiceOff: "Aus. Deine Stimme bleibt, wie sie ist.",
  dictation: "Diktieren",
  dictationOn: "Mit {} diktieren, der Text landet am Cursor.",
  dictationOff: "Aus. {} tut nichts.",
  dictationNotReady: "Noch nicht bereit. Mehr dazu in den Einstellungen.",
  memos: "Sprachaufzeichnung",
  memosOff: "Aus. Deine Aufnahmen bleiben, wo sie sind.",
  memosOn: "kyrr speichert und benennt die Aufnahme selbst.",
  memosOnKey: "Mit {} aufnehmen. kyrr speichert und benennt die Aufnahme selbst.",
  memosRecording: "Aufnahme läuft. Stopp beendet sie.",
  memosRecordingKey: "Aufnahme läuft. {} oder Stopp beendet sie.",
  stop: "Stopp",
  recordings: "Aufzeichnungen öffnen",
  update: "Update {} installieren",
  setup: "Setup",
  settingsOf: "Einstellungen: {}",
  quit: "Beenden",
  start: "kyrr starten",
  startHint: "Startet im Hintergrund, die Tasten gehen gleich.",
  install: "kyrr installieren",
  installHint: "Lädt kyrr von GitHub (etwa 50 MB) und richtet es ein."
}

var en = {
  notInstalled: "Not installed yet",
  notRunning: "Not running",
  listening: "Listening …",
  writing: "Writing …",
  recording: "Recording …",
  ready: "Ready",
  readyKey: "Ready · Dictate with {}",
  filter: "Isolate your voice",
  filterOn: "Just your voice. Keyboard, fan and dog stay outside.",
  filterOff: "Off. Your mic passes through as it is.",
  voice: "Improve voice",
  voiceOn: "A bit of polish for your voice.",
  voiceOff: "Off. Your voice stays as it is.",
  dictation: "Dictation",
  dictationOn: "Dictate with {}, the text lands at your cursor.",
  dictationOff: "Off. {} does nothing.",
  dictationNotReady: "Not ready yet. More in the settings.",
  memos: "Voice memo",
  memosOff: "Off. Your recordings stay where they are.",
  memosOn: "kyrr saves and names the recording by itself.",
  memosOnKey: "Record with {}. kyrr saves and names the recording by itself.",
  memosRecording: "Recording. Stop ends it.",
  memosRecordingKey: "Recording. {} or Stop ends it.",
  stop: "Stop",
  recordings: "Open recordings",
  update: "Install update {}",
  setup: "Setup",
  settingsOf: "Settings: {}",
  quit: "Quit",
  start: "Start kyrr",
  startHint: "Starts in the background, the keys work right away.",
  install: "Install kyrr",
  installHint: "Downloads kyrr from GitHub (about 50 MB) and sets it up."
}

function text(german, key, value) {
  var table = german ? de : en
  var s = table[key] !== undefined ? table[key] : en[key]
  return value !== undefined ? s.replace("{}", String(value)) : s
}
