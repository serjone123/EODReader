# EODReader (EOD Viewer)

Настольное приложение (Delphi 12 / FireMonkey, Win32) для просмотра и анализа
записей электрических разрядов рыб (EOD — Electric Organ Discharge).
Работает с 4-канальными записями, хранящимися как пара стерео-WAV, и с собственным
компактным форматом пиков `.eodpk`.

## Важные файлы для ИИ-агентов

Если над проектом работает ИИ-агент, **перед чтением или изменением кода обязательно обработать `AGENTS.md`, `TODO.md` и `HISTORY.md`**.

- `AGENTS.md` — обязательные правила работы с проектом.
- `TODO.md` — текущий план, порядок действий и список выполненных задач.
- `HISTORY.md` — история существенных изменений; особенно внимательно читать записи об изменениях логики обработки и математических расчётов.

После существенных изменений агент должен внести запись в `HISTORY.md`.

## Возможности

- Открытие пары WAV (Tr12 = каналы 1–2, Tr34 = каналы 3–4); чтение — в фоновом потоке.
- Фоновый анализ записи: STD по 4 каналам → FIR15-фильтрация → поиск пиков по
  prominence (O(N), монотонные стеки). Промежуточный прогресс и отмена.
- Сохранение найденных пиков в файл `.eodpk`.
- Просмотр `.eodpk`: малые диапазоны восстанавливаются точно из записей пиков,
  большие — рисуются из кэшированной огибающей (без аллокации полного буфера).
- Режимы отображения: `RAW - 4 channels`, `STD`, `FIR15`, `RAW + FIR15`,
  `RAW channels separate`, `IPI histogram`.
- Навигация: обзорный график (min/max, ~2000 бинов) с кликом и выделением диапазона,
  зум колесом, панорамирование, позиционный ползунок, список пиков (окно ±100 с
  с переходами `<<` / `>>`), кнопки Prev/Next.
- Обзорный график может рисоваться в цветах каналов (Ch1…Ch4) — включается
  свойством `OverviewChannelColors` у `TMainForm`; поканальные огибающие строятся
  в `BuildOverview` (для `.eodpk` — из кэша файла), поэтому переключение режима
  не перечитывает запись. Каждый канал масштабируется по своему максимуму.
- **Воспроизведение записи** (кнопка `Play`): плеер ведёт «виртуальное время»
  записи и показывает картинку очередного пика в тот момент, когда наступает его
  время — т.е. запись проигрывается в реальном темпе. Скорость 0.1x…10x выбирается
  рядом с кнопкой (1x = реальное время). Старт — с текущего выбранного пика;
  после последнего пика воспроизведение останавливается само. Ползунок позиции
  двигается вместе с «виртуальным временем».
- Настройки детектора в диалоге (Settings) с сохранением в JSON.

## Форматы данных

### Вход: пара стерео-WAV
`TFourChannelAudioSource` (IO.AudioSource) объединяет два стерео-WAV в один
поток 4-канальных кадров `TAudioFrame` (4 × Single). Чтение WAV — Eod.WavReader.

### Формат `.eodpk` (версия 3)
Единицы: `IO.PeakStore` (`TEodPeakStore`). Раскладка файла:

```
Header (TEodPeakFileHeader: magic, version, SampleRate, PeakCount, TotalFrames,
        SamplesPerPeak, CacheOffset, ...)
UTF-8 source name 1
UTF-8 source name 2
Пиковые записи фиксированного размера          ← RecordOffset = DataOffset + Index * RecordSize
Cache header (magic 'EODCACH3')
Cache level 0 … N
```

- Каждая запись: `TEodPeakRecordHeader` (`Position`, `StartPosition`,
  `TimeSeconds`, `PeakValue`, `Prominence`, `SampleCount`) +
  `SamplesPerPeak × TAudioFrame` сэмплов окна вокруг пика (по умолчанию 30 до / 30 после).
  Фиксированный размер записи даёт прямой произвольный доступ по индексу.
- Позиции пиков отсортированы по возрастанию (на этом построены бинарные поиски).
- Кэш огибающей: страницы по `EodPeakPageSize = 5000` записей; уровни кэша
  группируются по 4 (`EodCacheGroupFactor`), максимум 16 уровней; каждый бакет —
  `TWaveEnvelopePoint` (min/max по 4 каналам). Кэш пишет `BuildCacheForStream`,
  читает `ReadEnvelope` при больших диапазонах отображения.

## Конфигурация

`config.json` рядом с exe (`Core.ConfigStore`). Поля — `TEodDetectorConfig`:
`PeakProminence`, `CorrelationThreshold`, `WindowBefore/After`,
`ExtractionBefore/After`, `ChunkSize`, `DuplicateDistance`.
При отсутствии/повреждении файла молча используются значения по умолчанию.

## Сборка

- RAD Studio / Delphi 12 (Embarcadero Studio 23.0), FireMonkey, платформа Win32.
- Быстрый вариант — из корня проекта: `cmd /c _build.cmd`
  (вызывает `rsvars.bat` и `MSBuild.exe ReadEOD.dproj /p:Config=Debug /p:Platform=Win32`).
  Для Release поменять `Config=Release` внутри `_build.cmd`.
- Вывод: `Bin\ReadEOD.exe` (туда же попадают тестовые exe), DCU — `DCU\Win32\<Config>`.
- В `Bin\` лежат примеры `.eodpk` для ручной проверки.

Известные безвредные предупреждения компилятора (не ошибки, можно игнорировать):
`H2164 PeakPositions` (ShowPeak), `W1000 MessageDlg deprecated`,
`H2077 BestDistance` (FillPeakListAroundFrame), `H2219 ShowCurrentRange`.

## Структура проекта

| Юнит | Назначение |
|---|---|
| `ReadEOD.dpr` | Точка входа, список всех юнитов. |
| `uReadWavMain.pas` + `.fmx` | Главная форма `TMainForm`: вся логика UI, навигация, воспроизведение. |
| `GUI.Model.pas` | `TEodGuiSession` — сессия поверх WAV-пары (`dmWav`) или `.eodpk` (`dmPeakFile`); единый API чтения сегментов/пиков для GUI. |
| `GUI.Plot.pas` | `TSignalPlot` (основной график, режимы, зум/пан) и `TOverviewPlot` (обзорный график). |
| `IO.PeakStore.pas` | Формат `.eodpk` v3: чтение/запись записей пиков, страницы, многоуровневый кэш огибающей. |
| `Signal.Peaks.pas` | `FindPeaksProminence` — O(N) поиск пиков по prominence. |
| `Detection.Detector.pas` | `TEodDetector` — конвейер анализа (`AnalyzePeaks`), прогресс/отмена. |
| `Eod.Fir15.pas` | FIR-фильтр 15-го порядка. |
| `Signal.Statistics.pas` | STD по 4 каналам (покадрово). |
| `Detection.Correlation.pas`, `Detection.Templates.pas`, `Detection.Classifier.pas` | Корреляция с шаблонами и классификация типов рыбы (Gnat / Morm / Stim). |
| `IO.AudioSource.pas` | `TFourChannelAudioSource`: два стерео-WAV → поток 4-канальных кадров. |
| `IO.WavReader.pas` | Разбор WAV. |
| `IO.SignalCache.pas` | Кэш сегментов сигнала. |
| `Threads.Analysis.pas` | `TEodAnalysisThread` — фоновый анализ (FreeOnTerminate, отмена через TEvent). |
| `Threads.WavOpen.pas` | `TEodWavOpenThread` — фоновое открытие WAV-пары. |
| `Core.ConfigStore.pas` | Загрузка/сохранение `config.json`. |
| `Eod.SettingsForm.pas` | Диалог настроек детектора. |
| `Core.Types.pas` | Общие типы: `TPeak`, `TAudioFrame`, `TEodDetectorConfig`, огибающая и т.п. |

Помимо основного проекта в репозитории есть тестовые проекты
(`Eod.Tests`, `Eod.PeakTest`, `Eod.IpiTest`, `Eod.ExtractTest`, `TestPeakStoreFast`;
их exe также попадают в `Bin\`).

## Замечания

- `TODO.md` — рабочий план проекта. Выполненные пункты переносятся в его раздел `Выполнено`.
- `HISTORY.md` — журнал изменений проекта, особенно изменений алгоритмов и расчётов.
- Папки `Bin`, `DCU`, `Win32`, `__history`, `__recovery`, `*.identcache`,
  `*.dproj.local` — артефакты сборки/IDE, в git не отслеживаются.
- Правила работы для ИИ-агентов — см. `AGENTS.md`.
