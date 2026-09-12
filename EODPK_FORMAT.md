# EODPK v3 — формат и архитектура хранения

Этот документ является рабочей спецификацией формата `.eodpk` версии 3.

Он описывает **фактическую структуру, которую должен поддерживать `IO.PeakStore.pas`**, и отдельно отмечает правила использования формата приложением. При расхождении между документом и кодом сначала нужно проверить код записи/чтения и зафиксировать расхождение здесь или в `HISTORY.md`, а не молча менять формат.

## 1. Назначение

EODPK v3 — компактное самодостаточное представление уже обработанной записи после первоначального анализа WAV.

Цель формата:

- не требовать WAV для обычного просмотра и работы с найденными пиками;
- поддерживать десятки и сотни миллионов исходных samples/frames;
- не загружать весь EODPK или большой диапазон waveform в RAM;
- обеспечивать быстрый поиск диапазона пиков;
- обеспечивать быстрый Overview и zoom-out через заранее построенные envelope levels;
- сохранять небольшой raw waveform вокруг каждого пика для точного zoom-in и анализа отдельного события;
- использовать `Int64` для file/frame/peak dimensions и смещений.

EODPK не является копией полного WAV. Между пиками исходный raw waveform не хранится.

## 2. Логическая структура файла

```text
Header (TEodPeakFileHeader)
UTF-8 source name 1
UTF-8 source name 2
Fixed-size peak records
Cache header (TEodPeakCacheHeader)
Cache level 0
Cache level 1
Cache level 2
...
```

`TEodPeakFileHeader.HeaderSize` указывает начало первой peak record.
`TEodPeakFileHeader.CacheOffset` указывает начало cache header.

## 3. Основной header

`TEodPeakFileHeader` — packed record.

Содержит:

- `Magic` — `EODPK003`;
- `Version` — `3`;
- `HeaderSize` — смещение до первой peak record;
- `SampleRate`;
- `ChannelCount`;
- `WindowBefore`, `WindowAfter`;
- `SamplesPerPeak` — максимальное число кадров waveform в записи пика;
- `PeakCount: Int64`;
- `TotalFrames: Int64`;
- `Source1Size`, `Source2Size`;
- `Source1SampleRate`, `Source2SampleRate`;
- `Source1Channels`, `Source2Channels`;
- `Source1NameBytes`, `Source2NameBytes`;
- `CacheOffset: Int64`;
- `CacheSize: Int64`;
- `CacheLevelCount`;
- `Reserved`.

Имена исходных WAV хранятся сразу после header в UTF-8. Размеры в байтах задаются соответствующими `*NameBytes`.

## 4. Peak records

Каждая peak record имеет фиксированный размер:

```text
SizeOf(TEodPeakRecordHeader)
+ SamplesPerPeak * SizeOf(TAudioFrame)
```

`TEodPeakRecordHeader` содержит:

- `Position: Int64` — позиция пика в исходном frame/sample coordinate space;
- `StartPosition: Int64` — начало сохранённого waveform окна;
- `TimeSeconds: Double`;
- `PeakValue: Single`;
- `Prominence: Single`;
- `SampleCount: Cardinal` — фактическое число сохранённых кадров в этой записи.

Waveform состоит из `TAudioFrame`:

```text
Ch1: Single
Ch2: Single
Ch3: Single
Ch4: Single
```

Таким образом, `TAudioFrame` занимает 16 байт, а header peak record — 36 байт. Фактический размер записи вычисляется кодом через `CheckedRecordSize`, а не хранится отдельно в каждой записи.

Фиксированный размер позволяет вычислять адрес записи напрямую:

```text
RecordOffset = DataOffset + Index * RecordSize
```

Поэтому для произвольного доступа не требуется глобальный массив `FPeakPositions`.

### Инварианты peak records

- записи должны идти в порядке возрастания `Position`;
- `PeakCount` задаёт число записей;
- `SampleCount <= SamplesPerPeak`;
- размер записи не должен переполнять `Int64`/`Integer` при расчёте буфера;
- `Position`, `StartPosition`, размеры файла и количества записей обрабатываются как `Int64`.

## 5. Поиск пиков

`TEodPeakStore.FindPeakRange(StartFrame, EndFrame)` должен находить диапазон записей по `Position` без создания массива всех позиций.

Поскольку записи имеют фиксированный размер и отсортированы, границы диапазона могут находиться бинарным поиском с прямым чтением `TEodPeakRecordHeader`.

Это принципиально важно для больших EODPK.

## 6. Envelope cache

Cache предназначен для отображения waveform без восстановления полного raw-сигнала.

Одна точка `TWaveEnvelopePoint` содержит:

- `StartPosition: Int64`;
- `EndPosition: Int64`;
- Ch1 Min/Max;
- Ch2 Min/Max;
- Ch3 Min/Max;
- Ch4 Min/Max.

Размер одной точки — **48 байт**.

Envelope хранится в `TWaveEnvelope` и читается через API `TEodPeakStore.ReadEnvelope(...)`. GUI не должен знать внутреннее расположение cache levels.

## 7. Иерархия cache levels

Первый уровень агрегирует peak records группами `BaseGroupSize`.

```text
peak records
    ↓
cache level 0
    ↓ ×4
cache level 1
    ↓ ×4
cache level 2
    ↓ ×4
...
```

`EodCacheMaxBuckets = 8192` ограничивает число bucket в самом подробном уровне.

Для большого количества пиков увеличивается `BaseGroupSize`, а не размер одного уровня. Следующие уровни используют `EodCacheGroupFactor = 4`.

Максимум уровней в текущей реализации — 16.

Примерная модель для 30 000 000 peaks:

```text
BaseGroupSize ≈ ceil(30 000 000 / 8192) ≈ 3663
level 0       ≈ 8192 buckets
level 1       ≈ 2048
level 2       ≈ 512
level 3       ≈ 128
...
```

Последний уровень не обязан содержать ровно один bucket: его размер определяется количеством peak records и `GroupSize`.

## 8. Cache header

`TEodPeakCacheHeader` — packed record.

Содержит:

- `Magic = EODCACH3`;
- `Version = 3`;
- `LevelCount`;
- `RecordSize = SizeOf(TWaveEnvelopePoint)`;
- `BaseGroupSize`;
- массив `Levels[0..15]`.

Каждый `TEodPeakCacheLevelInfo` содержит:

- `Offset: Int64` — начало уровня в файле;
- `Count: Int64` — число bucket;
- `GroupSize: Int64` — сколько peak records соответствует одному bucket этого уровня.

`Header.CacheLevelCount` и `CacheHeader.LevelCount` должны описывать одно и то же число уровней.

## 9. Построение cache

Cache строится при создании/перезаписи EODPK v3.

Построение должно:

- читать peak records последовательно;
- не создавать массив всех waveform samples;
- агрегировать min/max по четырём каналам;
- записывать несколько компактных cache levels;
- использовать ограниченное RAM, зависящее от размера cache, а не от полного WAV.

Текущая реализация допускает хранение самих cache levels во временных небольших массивах во время построения. Это не нарушает основную цель формата: cache ограничен `8192` bucket на уровень и максимумом уровней.

## 10. Чтение envelope

Публичный API:

```pascal
ReadEnvelope(
  FirstPeakIndex,
  LastPeakIndex,
  MaxPoints,
  Envelope
)
```

Выбор cache level является внутренней ответственностью `TEodPeakStore`.

GUI должен задавать диапазон и желаемое количество точек, а не вычислять `Offset`, `GroupSize` или номер cache level самостоятельно.

Для zoom-out нельзя читать все raw waveform samples выбранного диапазона и затем строить envelope в UI.

## 11. Raw и envelope режимы

Формат поддерживает два принципиально разных сценария:

### Точный просмотр небольшого диапазона

Используются сохранённые raw waveform samples вокруг отдельных peaks.

### Большой диапазон

Используется envelope cache. Полный raw `TAudioChunk` большого региона не создаётся.

Граница вроде «до 10 000 samples» относится к политике GUI/режима отображения, а не к бинарному формату. Её можно менять без изменения EODPK v3.

## 12. STD/FIR

Envelope — отдельное представление для отображения.

Его нельзя автоматически превращать обратно в `TAudioChunk` и использовать как эквивалент raw-сигнала для STD/FIR или другого анализа, требующего исходных samples.

STD/FIR применяются только там, где действительно доступны raw samples подходящего диапазона.

Если в будущем потребуется статистика для больших диапазонов, её следует хранить как отдельные cache levels/индексы, а не восстанавливать из min/max envelope.

## 13. Самодостаточность

После создания EODPK обычный просмотр и навигация по найденным пикам не должны требовать повторного чтения WAV.

Имена и основные параметры исходных WAV сохраняются для идентификации источника, но отсутствие исходных WAV не должно мешать работе с уже созданным EODPK в поддерживаемых режимах.

## 14. Совместимость

Версия 3 не обязана поддерживать v1/v2.

В текущем проекте предпочтительна простая проверка `Magic`/`Version` и отказ от открытия неподдерживаемого формата.

Старый EODPK при необходимости пересоздаётся из WAV.

## 15. Что пока НЕ является частью v3

Следующие идеи не должны считаться обязательными полями текущего формата:

- отдельный компактный peak index;
- cache prominence;
- detector statistics cache;
- IPI histogram cache;
- mmap;
- LRU cache viewport;
- асинхронная загрузка envelope при zoom;
- хранение версии алгоритма/конфигурации анализа внутри файла.

Это возможные расширения будущих версий.

## 16. Проверки при изменении формата

Любое изменение EODPK должно проверяться минимум по следующим сценариям:

1. маленький EODPK — корректное чтение отдельных peak records;
2. большой EODPK — отсутствие загрузки всех peak positions в RAM;
3. большой диапазон — корректный выбор envelope cache;
4. zoom-in — корректное чтение raw waveform вокруг пика;
5. zoom-out — отсутствие чтения полного raw региона;
6. пустой EODPK — корректный cache header с нулём уровней;
7. очень большое `PeakCount`/`TotalFrames` — отсутствие `Integer` overflow;
8. проверка совпадения `CacheLevelCount`, `LevelCount`, `Offset`, `Count`, `GroupSize`;
9. чтение файла без исходных WAV;
10. проверка, что изменение cache не меняет `Position` пиков и результаты детектора.

## 17. Связь с кодом

Основной владелец формата: `IO.PeakStore.pas` (`TEodPeakStore`).

Общие типы: `Core.Types.pas` (`TWaveEnvelopePoint`, `TWaveEnvelope`, `TAudioFrame`).

GUI должен работать через API `TEodPeakStore`, а не через прямое чтение структур cache.

При добавлении нового поля в бинарный формат необходимо одновременно обновить:

- эту спецификацию;
- writer/reader в `IO.PeakStore.pas`;
- проверки совместимости версии;
- тестовые данные или regression tests;
- `HISTORY.md`.
