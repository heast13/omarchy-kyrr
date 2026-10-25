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
  memoStart: "Aufnahme starten",
  memoStop: "Aufnahme beenden",
  memoKey: "Oder {} tippen",
  memos: "Aufzeichnungen öffnen",
  update: "Update {} installieren",
  open: "Einstellungen",
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
  memoStart: "Start recording",
  memoStop: "Stop recording",
  memoKey: "Or tap {}",
  memos: "Open recordings",
  update: "Install update {}",
  open: "Settings",
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
