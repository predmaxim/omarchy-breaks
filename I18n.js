.pragma library
// Interface text in other languages, keyed by the English text itself, so a
// string missing from a table shows in English. tr("… %1", x) fills in %1, %2…
// after the lookup.
var TABLES = {
  ru: {
    "Breaks": "Перерывы",
    "Break for the eyes": "Перерыв для глаз",
    "Break for the body": "Перерыв для тела",
    "Break in a minute": "Перерыв через минуту",
    "Postpone %1 min": "Отложить на %1 мин",
    "Skip": "Пропустить",
    "Hands off: step away from the keyboard": "Руки прочь: отойди от клавиатуры",
    "Look at the main screen": "Смотри на главный экран",
    "Look out of the window for %1 s": "Посмотри в окно %1 с",
    "Today: %1 breaks": "Сегодня: %1 перерывов",
    "Streak: %1 days": "Серия: %1 дн.",
    "Next: eyes in %1 min": "Дальше: глаза через %1 мин",
    "Next: body in %1 min": "Дальше: тело через %1 мин",
    "Waiting: %1": "Ждём: %1",
    "microphone": "микрофон", "camera": "камера", "video": "видео", "fullscreen": "полный экран",
    "app": "приложение", "meeting": "встреча",
    "Breaks are off": "Перерывы выключены",
    "↑↓ choose · ←→ change · Enter toggle · Esc close": "↑↓ выбор · ←→ изменить · Enter переключить · Esc закрыть",
    "Settings": "Настройки", "Back": "Назад", "Turn on": "Включить", "Turn off": "Выключить",
    "Eyes: no earlier than, min": "Глаза: не раньше, мин", "Eyes: no later than, min": "Глаза: не позже, мин",
    "Body: every, min": "Тело: каждые, мин",
    "Break now": "Перерыв сейчас", "Pause 1 h": "Пауза на 1 ч",
    "Strictness": "Строгость", "Hard": "Жёстко", "Medium": "Средне", "Soft": "Мягко",
    "Postpones per break": "Отсрочек за перерыв", "Postpone by, min": "Отсрочка, мин",
    "Eyes": "Глаза", "Break no earlier than, min": "Перерыв не раньше, мин", "Break no later than, min": "Перерыв не позже, мин",
    "Break length, s": "Длина перерыва, с", "Micro-pauses 20-20-20": "Микропаузы 20-20-20",
    "Micro-pause every, min": "Микропауза каждые, мин", "Micro-pause length, s": "Длина микропаузы, с",
    "Body": "Тело", "Break every, min": "Перерыв каждые, мин", "Join eyes into it within, min": "Объединять с глазами в пределах, мин",
    "Do not disturb": "Не мешать", "Respect the calendar": "Учитывать календарь",
    "Movement tips during meetings": "Советы подвигаться на встречах", "Meeting tip every, min": "Совет каждые, мин",
    "Never interrupt these apps (window classes, comma separated)": "Не прерывать эти приложения (классы окон через запятую)",
    "Idle after, s": "Простой после, с", "Sounds": "Звуки", "Volume, %": "Громкость, %",
    "Minutes in the bar": "Минуты в баре",     "Debug": "Отладка", "Minutes become seconds; Super+Ctrl+Alt+Esc ends a break.": "Минуты становятся секундами; Super+Ctrl+Alt+Esc прерывает перерыв.",
    "Catch the dot": "Поймай точку", "Click the dot as soon as it jumps": "Кликай по точке, как только она прыгнет",
    "Follow the figure eight": "Следи за восьмёркой", "Only the eyes move, the head stays still": "Двигаются только глаза, голова неподвижна",
    "Look far away": "Посмотри вдаль", "Look at something 6 m away. Which number flashed in the corner?": "Смотри на предмет в 6 м. Какое число мелькнуло в углу?",
    "Near and far": "Близко и далеко", "Near: your finger": "Близко: на палец", "Far: out of the window": "Далеко: в окно",
    "Palming": "Пальминг", "Close your eyes and cover them with warm palms. The sound will tell you when to open them": "Закрой глаза и накрой тёплыми ладонями. Звук скажет, когда открыть",
    "Slow blinks": "Медленные моргания", "Close": "Закрой", "Open": "Открой",
    "Squats": "Приседания", "Calf raises": "Подъёмы на носки", "Shoulder rolls": "Вращения плечами",
    "Neck turns": "Повороты головы", "Hip flexor stretch, each side": "Растяжка бёдер, каждая сторона", "Plank": "Планка",
    "Breathing 4-7-8": "Дыхание 4-7-8", "Box breathing": "Дыхание «коробка»",
    "Inhale": "Вдох", "Hold": "Задержка", "Exhale": "Выдох",
    "%1 reps": "%1 раз",
    "Stand up for the rest of the call": "Встань до конца созвона",
    "25 calf raises while you listen": "25 подъёмов на носки, пока слушаешь",
    "10 squats with the camera off": "10 приседаний с выключенной камерой",
    "Look out of the window for 20 seconds": "Посмотри в окно 20 секунд",
    "Roll your shoulders back 10 times": "10 вращений плечами назад",
    "Drink a glass of water": "Выпей стакан воды",
    "Go to the window: daylight is good for the eyes": "Подойди к окну: дневной свет полезен глазам",
    "Walk to the kitchen and back": "Дойди до кухни и обратно",
    "Done": "Готово", "Correct": "Верно", "It was %1": "Было %1"
  }
}

// Text follows LC_MESSAGES, overridden by LC_ALL and defaulting to LANG, as
// the system splits it. env is name -> value (Quickshell.env in QML).
function textLanguage(env) {
  var names = ["LC_ALL", "LC_MESSAGES", "LANG"]
  for (var i = 0; i < names.length; i++) {
    var v = String(env(names[i]) || "").split(".")[0].split("@")[0]
    if (v && v !== "C" && v !== "POSIX") {
      var l = v.slice(0, 2).toLowerCase()
      return TABLES[l] ? l : "en"
    }
  }
  return "en"
}

function translator(lang) {
  var table = TABLES[lang] || {}
  return function(text) {
    var out = Object.prototype.hasOwnProperty.call(table, text) ? table[text] : text
    for (var i = 1; i < arguments.length; i++) out = out.split("%" + i).join(String(arguments[i]))
    return out
  }
}
