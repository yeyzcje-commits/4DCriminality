# 4Money — Criminality script / скрипт для Criminality

**English** · [Русский](#русский)

Build r14 · made for Solara v3 · UI library: 4D$ (loaded from GitHub)

---

## English

### What it is
A menu script for the Roblox game **Criminality**. Four tabs:

| Tab | What is inside |
|---|---|
| **Combat** | no recoil / no spread, aim lock, silent aim, triggerbot, hitmarker and damage text, weapon view |
| **Visuals** | player / loot / door / shop ESP, outlines, FOV and zoom, custom crosshair |
| **Money** | auto lockpick, auto cash, auto crowbar, allowance and bank→cash from afar |
| **Misc** | infinite stamina, no fall damage, fullbright, anti-flash, anti-AFK, alerts, optimizer, debug |

### Requirements
* An executor that can run big scripts and load a script from the internet (`game:HttpGet`) — Solara v3 works.
* Internet access (the menu library is downloaded from GitHub at start).
* Some features need executor functions. If one is missing, only that feature is affected:

| Feature | Needs |
|---|---|
| Silent aim, No fall damage learning, Bank/Allowance recording | `hookmetamethod` |
| Infinite stamina (auto learning) | `getgc` (and `debug.getupvalues` helps) |
| Aim method "Mouse move" | `mousemoverel` |
| Auto lockpick (GUI click) | `VirtualInputManager` |

### Compatibility (executors)
At start the script checks what your executor can do (the console line `[4Money] executor: … | hook=… getgc=…`, also shown in the **Help** drawer) and switches off **only** the features that need something missing. It is written for Solara, Xeno, Wave, Potassium, Volt, Delta, KRNL, Codex, Arceus X and similar executors. I could not test each of them, so what works depends on the functions your executor really has.

| Needs | Used by | If it is missing |
|---|---|---|
| `game:HttpGet` **or** `request` / `http_request` / `syn.request` | loading the menu | tries the other ways, a CDN mirror, then a local `workspace/4D$.lua` |
| `writefile`, `readfile`, `isfolder`, `makefolder` | saving settings | settings are simply not saved |
| `hookmetamethod` (or `getrawmetatable` + `setreadonly`) and `getnamecallmethod` | silent aim, fall-damage learning, Bank/Allowance recording | those features stay inactive |
| `getgc` (`debug.getupvalues` helps) | infinite stamina learning | only the simple method is used |
| `mousemoverel` | aim method "Mouse move" | use "Camera" (default) |
| `mouse1click` or `VirtualInputManager` | triggerbot, auto lockpick click | the other one is used; if neither exists these two do nothing |
| `getconnections` / `firesignal` / `keypress` | lockpick fallback input methods | other methods are used |

**Phones / tablets (Delta, Codex, Arceus X …):** there is no right mouse button and no keyboard, so Aim lock starts on *Always*, and "Hold RMB" / "zoom on a key" cannot be used. Use the toggles and the triggerbot instead. The menu itself comes from the library and its look on a small screen is up to it.
### How to run
1. Join Criminality and wait until the game has fully loaded.
2. In Solara open a **new empty tab**, paste the **whole** file `4Money.lua` (about **153 KB**) and press Execute.
   *If pasting a file this large gets cut off, put the file into Solara's `workspace` folder and run:*
   ```lua
   loadstring(readfile("4Money.lua"))()
   ```
3. Check the console. You must see `[4Money] build 2026-11-22 r14 starting`, then the menu opens and a "Loaded." notification appears.
   If the build line is missing or the size shown by Solara (`Ran script (… KB)`) is much smaller than 153 KB, you are running an old or cut-off copy.

Running the script again cleans up the previous run first, so you do not have to rejoin.

### Using the menu
* Every toggle and button has a small **key chip**. Click it and press a key to bind; `Esc` or right-click clears the bind.
* Settings are saved automatically (`4Money/config` in the executor's workspace) and restored next time.
* The **Money tools** panel (right edge) has one-click money actions. The **Help** drawer (left edge) has short tips.
* **Debug output** (Misc → Debug) prints details to the console. Turn it on before reporting a problem.

### Features

**Combat**
* **No Recoil** – cancels the camera kick while you shoot (suppression 1.0 and smoothing 0 = full cancel). It also zeroes `recoil` / `kick` numbers of the weapon you are holding. *Cancel camera recovery*: switch it off if the aim creeps UP after shooting.
* **No Spread** – zeroes `spread` / `inaccuracy` / `bloom` / `scatter` / `deviation` / `dispersion` values of your weapon. Every change is saved and put back when you die, switch it off or unload the script.
* **Aim lock** – turns the camera to the target. Pick when it works (*Hold RMB / Hold LMB / Always*), the target part, the FOV circle, smoothness, max turn speed, distance and wall check. *Aim method*: **Camera** (exact, default) or **Mouse move** (experimental, learns the mouse sensitivity).
* **Silent aim** – while you shoot, the rays the game uses to find the hit are turned to the head/torso of the enemy nearest to the crosshair; the camera does not move. Has FOV, distance, hit-chance and wall check. If bullets still miss, turn Debug on and look for `silent aim: ray turned to …`; no such line means the game aims in another way.
* **Hitmarker** – X at the crosshair and a sound when you hit someone (red on a kill). **Damage text** shows `-HP` and `-ARMOR` you took off.
* **Triggerbot** – shoots when the crosshair is on an enemy for the chosen number of ms; walls block it.
* **Weapon view** – makes your weapon see-through while aiming in first person.

**Visuals**
* **ESP → Players**: box, fill, health bar + number, held item, tracers, off-screen arrows (colour, distance). **Loot** (safes, registers, crates; optional "only not-yet-opened"), **Doors**, **Shops**, **Outlines**.
* **Camera**: custom FOV; **zoom on a key** (default `C`, hold or toggle). *Slow mouse while zoomed* removes the "too sharp" mouse when zoomed in.
* **Custom crosshair** with size, thickness, gap, centre dot and colour.

**Money**
* **Auto lockpick** – plays the lockpick minigame for you by clicking at the right moment, bar after bar (B1→B2→B3). Settings: input method, timing offset, start delay (no click right after the minigame opens), delay between presses, stop after N real misses. Keep Debug on if it misses and send the `lockpick …` lines.
* **Cash and safes** – auto pick up dropped cash, **auto crowbar** (hits the nearest safe/register; you need a Crowbar).
* **Allowance (from afar)** – collects the allowance without walking to the ATM. If the automatic way does not work, use the *Fallback* recording buttons.
* **Bank to Cash (from afar)** – press **1**, withdraw bank→cash once at an ATM, press **2**. After that **3** (or the side panel button, or the auto toggle) converts from anywhere.

**Misc**
* **Infinite stamina** – learns where the game keeps stamina. Switch it on and **sprint for 5–10 seconds**; the console says `Stamina learned`. After you die it learns again.
* **No fall damage** – limits the fall speed and, if you still get hurt, learns and blocks the damage remote (the first fall can still hurt).
* **Fullbright**, **Anti flashbang**, **Anti-AFK**, **Nearby player alert** (radius), **Smart pause** (stops the auto actions at low health or when dead).
* **Optimizer** – turns off shadows, particles and post effects for more FPS.

### Troubleshooting
| Problem | What to do |
|---|---|
| Console shows `:NNNN: …` errors without a script name | A syntax error in a **wrong, old or cut-off copy**. Check the `build … r14` line and the size (≈153 KB); paste a fresh copy into an empty tab or use `readfile`. |
| `Failed to load Lumen UI` | The menu library could not be downloaded: check your internet / GitHub access. |
| Weapons do not equip / `Requested module experienced an error while loading` | A module was broken for this server session (an old script version did it). **Rejoin the server** and use the current build. |
| Lockpick misses | Turn on Debug, raise *Start delay*, check the `lockpick press / result / MISS` lines. |
| Aim lock feels wrong | Use *Aim method = Camera*, lower *Smoothness*, raise *Max turn speed*. |
| Silent aim does nothing | Needs `hookmetamethod`; use Debug (see above). |
| Camera / sprint behave strangely after death | Rejoin once and report which features were on. |

### Notes
* Use at your own risk: scripts can get your account banned. An alt account is safer.
* Many features rely on the game's internals and may stop working after a game update.

---

## Русский

[English](#english) · **Русский**

Сборка r14 · для Solara v3 · библиотека меню: 4D$ (скачивается с GitHub)

### Что это
Скрипт с меню для игры **Criminality** (Roblox). Четыре вкладки:

| Вкладка | Что внутри |
|---|---|
| **Combat** | нет отдачи / нет разброса, аим-лок, silent aim, триггербот, хитмаркер и текст урона, вид оружия |
| **Visuals** | ESP игроков / лута / дверей / магазинов, обводка, FOV и зум, свой прицел |
| **Money** | авто-отмычки, авто-подбор денег, авто-лом, пособие и bank→cash издалека |
| **Misc** | бесконечная выносливость, без урона от падения, фулбрайт, антифлеш, анти-АФК, оповещения, оптимизатор, отладка |

### Что нужно
* Инжектор, который запускает большие скрипты и умеет грузить скрипт из интернета (`game:HttpGet`) — Solara v3 подходит.
* Интернет (библиотека меню скачивается с GitHub при запуске).
* Некоторым функциям нужны возможности инжектора. Если чего-то нет, не работает только эта функция:

| Функция | Что нужно |
|---|---|
| Silent aim, обучение No fall damage, запись Bank/Allowance | `hookmetamethod` |
| Бесконечная выносливость (автообучение) | `getgc` (и желательно `debug.getupvalues`) |
| Метод аима «Mouse move» | `mousemoverel` |
| Авто-отмычки (клик по GUI) | `VirtualInputManager` |

### Совместимость (инжекторы)
При запуске скрипт проверяет, что умеет твой инжектор (строка в консоли `[4Money] executor: … | hook=… getgc=…`, она же в разделе **Help**), и отключает **только** те функции, которым чего-то не хватает. Написан под Solara, Xeno, Wave, Potassium, Volt, Delta, KRNL, Codex, Arceus X и похожие. Проверить на каждом я не мог, поэтому что именно работает, зависит от функций, которые реально есть у твоего инжектора.

| Нужно | Для чего | Если нет |
|---|---|---|
| `game:HttpGet` **или** `request` / `http_request` / `syn.request` | загрузка меню | пробуются другие способы, зеркало CDN, затем локальный `workspace/4D$.lua` |
| `writefile`, `readfile`, `isfolder`, `makefolder` | сохранение настроек | настройки просто не сохраняются |
| `hookmetamethod` (или `getrawmetatable` + `setreadonly`) и `getnamecallmethod` | silent aim, обучение No fall damage, запись Bank/Allowance | эти функции не работают |
| `getgc` (помогает `debug.getupvalues`) | обучение бесконечной выносливости | работает только простой способ |
| `mousemoverel` | метод аима «Mouse move» | используй «Camera» (по умолчанию) |
| `mouse1click` или `VirtualInputManager` | триггербот, клик авто-отмычек | используется то, что есть; если нет ни того, ни другого — эти две функции не работают |
| `getconnections` / `firesignal` / `keypress` | запасные способы ввода отмычек | используются другие способы |

**Телефоны / планшеты (Delta, Codex, Arceus X …):** нет правой кнопки мыши и клавиатуры, поэтому аим-лок стартует в режиме *Always*, а «Hold RMB» и «зум на клавишу» недоступны. Пользуйся переключателями и триггерботом. Как выглядит само меню на маленьком экране — зависит от библиотеки.
### Как запустить
1. Зайди в Criminality и дождись полной загрузки игры.
2. В Solara открой **новую пустую вкладку**, вставь **весь** файл `4Money.lua` (около **153 KB**) и нажми Execute.
   *Если такой большой файл при вставке обрезается, положи его в папку `workspace` Solara и запусти:*
   ```lua
   loadstring(readfile("4Money.lua"))()
   ```
3. Посмотри консоль. Должна появиться строка `[4Money] build 2026-11-22 r14 starting`, затем откроется меню и придёт уведомление «Loaded.».
   Если строки сборки нет или Solara пишет `Ran script (… KB)` заметно меньше 153 KB, запущена старая или обрезанная копия.

Повторный запуск сначала убирает прошлый, перезаходить на сервер не нужно.

### Как пользоваться меню
* У каждого переключателя и кнопки есть маленькая **плашка с клавишей**. Нажми на неё и нажми нужную клавишу, чтобы назначить. `Esc` или правый клик снимает привязку.
* Настройки сохраняются сами (`4Money/config` в workspace инжектора) и восстанавливаются при следующем запуске.
* Панель **Money tools** (справа) — деньги в один клик. Выдвижной раздел **Help** (слева) — короткие подсказки.
* **Debug output** (Misc → Debug) выводит подробности в консоль. Включай его перед тем, как сообщать о проблеме.

### Функции

**Combat**
* **No Recoil** — гасит подброс камеры при стрельбе (подавление 1.0 и сглаживание 0 — полная компенсация). Ещё зануляет числа `recoil` / `kick` у оружия в руках. *Cancel camera recovery*: выключи, если после стрельбы прицел ползёт ВВЕРХ.
* **No Spread** — зануляет значения `spread` / `inaccuracy` / `bloom` / `scatter` / `deviation` / `dispersion` у твоего оружия. Каждое изменение запоминается и возвращается при смерти, выключении или выгрузке скрипта.
* **Aim lock** — поворачивает камеру на цель. Выбери, когда работает (*Hold RMB / Hold LMB / Always*), часть цели, круг FOV, плавность, макс. скорость поворота, дистанцию и проверку стен. *Aim method*: **Camera** (точный, по умолчанию) или **Mouse move** (экспериментальный, сам учится чувствительности мыши).
* **Silent aim** — пока ты стреляешь, лучи, которыми игра определяет попадание, разворачиваются на голову/торс ближайшего к прицелу врага; камера не двигается. Есть FOV, дистанция, шанс попадания и проверка стен. Если пули всё равно мимо, включи Debug и найди `silent aim: ray turned to …`; если такой строки нет, игра целится другим способом.
* **Hitmarker** — крестик у прицела и звук при попадании (красный при убийстве). **Damage text** показывает, сколько ты снёс `HP` и `ARMOR`.
* **Triggerbot** — стреляет, когда прицел на враге заданное число мс; стены блокируют.
* **Weapon view** — делает твоё оружие прозрачным при прицеливании от первого лица.

**Visuals**
* **ESP → Players**: бокс, заливка, полоска и число здоровья, предмет в руках, трейсеры, стрелки за экраном (цвет, дистанция). **Loot** (сейфы, кассы, ящики; можно «только ещё не открытые»), **Doors**, **Shops**, **Outlines**.
* **Camera**: свой FOV; **зум на клавишу** (по умолчанию `C`, удержание или переключатель). *Slow mouse while zoomed* убирает «слишком резкую» мышь при приближении.
* **Custom crosshair**: размер, толщина, зазор, точка в центре, цвет.

**Money**
* **Auto lockpick** — проходит мини-игру отмычек сам, кликая в нужный момент по очереди (B1→B2→B3). Настройки: способ ввода, смещение тайминга, стартовая задержка (не жать сразу после открытия мини-игры), пауза между нажатиями, остановка после N настоящих промахов. Если промахивается, включи Debug и пришли строки `lockpick …`.
* **Cash and safes** — авто-подбор выпавших денег, **авто-лом** (бьёт ближайший сейф/кассу; нужен Crowbar).
* **Allowance (from afar)** — собирает пособие, не подходя к банкомату. Если автоматический способ не работает, используй кнопки записи *Fallback*.
* **Bank to Cash (from afar)** — нажми **1**, один раз сними bank→cash у банкомата, нажми **2**. Дальше **3** (или кнопка в боковой панели, или авто-переключатель) конвертирует откуда угодно.

**Misc**
* **Infinite stamina** — сама ищет, где игра хранит выносливость. Включи и **побегай 5–10 секунд**; в консоли будет `Stamina learned`. После смерти учится заново.
* **No fall damage** — ограничивает скорость падения, а если урон всё равно идёт, находит и блокирует remote урона (первое падение ещё может ударить).
* **Fullbright**, **Anti flashbang**, **Anti-AFK**, **Nearby player alert** (радиус), **Smart pause** (останавливает авто-действия при низком здоровье или смерти).
* **Optimizer** — отключает тени, частицы и пост-эффекты ради FPS.

### Если что-то не так
| Проблема | Что делать |
|---|---|
| В консоли ошибки `:NNNN: …` без имени скрипта | Синтаксическая ошибка в **чужой, старой или обрезанной копии**. Проверь строку `build … r14` и размер (≈153 KB); вставь свежую копию в пустую вкладку или используй `readfile`. |
| `Failed to load Lumen UI` | Не скачалась библиотека меню: проверь интернет и доступ к GitHub. |
| Оружие не экипируется / `Requested module experienced an error while loading` | Модуль «сломан» в этой сессии сервера (это делала старая версия скрипта). **Перезайди на сервер** и используй текущую сборку. |
| Отмычки промахиваются | Включи Debug, подними *Start delay*, посмотри строки `lockpick press / result / MISS`. |
| Аим-лок работает странно | Поставь *Aim method = Camera*, понизь *Smoothness*, повысь *Max turn speed*. |
| Silent aim ничего не делает | Нужен `hookmetamethod`; используй Debug (см. выше). |
| После смерти странная камера / не работает бег | Один раз перезайди и напиши, какие функции были включены. |

### Замечания
* Используй на свой риск: за скрипты могут забанить аккаунт. Безопаснее на запасном аккаунте.
* Многие функции зависят от внутренностей игры и могут перестать работать после обновления игры.
