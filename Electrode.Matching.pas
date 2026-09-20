unit Electrode.Matching;

{$IFDEF FPC}
  {$MODE DELPHI}
  {$H+}
{$ENDIF}

{ Подбор соответствия «пара электродов <-> канал записи» и полярности
  (+/-) по реальным амплитудам событий + локализация событий (положение
  рыбы) в относительных координатах аквариума.

  ЗАЧЕМ НУЖЕН (см. подробный комментарий у TElectrodePairInput в
  Electrode.Layout): при ручной разметке пользователь достоверно знает
  только ГЕОМЕТРИЮ пары (два контакта одного дифференциального входа),
  но не то, какому каналу записи (Ch1..Ch4) соответствует пара и какой
  из контактов "+", а какой "−". Оба факта этот модуль определяет по
  данным, а не по догадкам:

    - назначение пар на каналы, заданное пользователем явно
      (UserChannel), используется как жёсткое ограничение;
    - свободные пары/каналы добираются перебором оставшихся
      перестановок;
    - полярность каждого канала перебирается отдельно (2^4 = 16
      комбинаций).

  Каждая комбинация оценивается суммарной невязкой модели поля
  (Electrode.Localization) на подмножестве событий; побеждает
  конфигурация с минимальной суммой. Затем все события локализуются
  лучшей конфигурацией и возвращаются для отображения. }

interface

uses
{$IFDEF FPC}
  SysUtils, Math,
{$ELSE}
  System.SysUtils, System.Math,
{$ENDIF}
  Electrode.Geometry, Electrode.Localization, Electrode.Layout;

type
  { Амплитуды одного события по 4 каналам; индекс 0..3 = Ch1..Ch4. }
  TChannelAmplitudes = array [0 .. 3] of Double;

  { Одно событие для локализации: кадр в записи + амплитуды по каналам. }
  TElectrodeEventAmplitudes = record
    Frame: Int64;
    Amplitudes: TChannelAmplitudes;
  end;
  TElectrodeEventArray = array of TElectrodeEventAmplitudes;

  { Знаки полярности каналов (+1 / -1). }
  TSigns4 = array [0 .. 3] of Double;

  { Результат локализации одного события (для отображения). Позиция — в
    ОТНОСИТЕЛЬНЫХ координатах аквариума (0..1 по каждой оси, см.
    BuildCalibrationFromLayout в Electrode.Layout). }
  TLocalizedEvent = record
    Frame: Int64;
    Position: TPoint2D;
    ResidualRMS: Double;
    Converged: Boolean;
  end;
  TLocalizedEventArray = array of TLocalizedEvent;

  { Пара электродов в относительных координатах аквариума (0..1). }
  TPairGeometry = record
    A, B: TPoint2D;
    UserChannel: Integer; // 0..3 = Ch1..Ch4, -1 = канал не назначен
  end;
  TPairGeometryArray = array of TPairGeometry;

  { Соответствие: канал 0..3 -> индекс пары в массиве Pairs. }
  TChannelAssignment = array [0 .. 3] of Integer;

  TChannelMatchScanResult = record
    OK: Boolean;
    Assignment: TChannelAssignment; // канал -> индекс пары (лучшее найденное)
    Orientation: TSigns4;           // знак полярности каждого канала
    MeanResidual: Double;           // средняя RMS по всем событиям лучшей конфигурации
    SearchCombinations: Integer;    // сколько комбинаций было оценено
    Events: TLocalizedEventArray;   // локализованные события (все переданные)
  end;

{ Сканирует комбинации «пары <-> каналы» x «знаки полярности» и локализует
  события. Требует ровно EodChannelCount (4) пар; иначе OK = False.

  TankWidth/TankHeight — границы аквариума в единицах координат Pairs
  (при относительных координатах 0..1 передавайте 1, 1 — это и есть
  границы аквариума).

  Все каналы должны быть заняты ровно одной парой: назначенные
  пользователем используются как фиксированные, на свободные каналы
  добираются свободные пары. Несовпадение числа свободных пар и
  свободных каналов, дубликат канала или пустой набор событий
  считаются ошибкой (OK = False).

  GridSize — сетка мультистарта для финальной локализации событий;
  SearchSubset — сколько первых событий участвует в оценке комбинаций;
  SearchGridSize — сетка мультистарта при этой оценке (можно грубее —
  оценка комбинаций и так ведётся по небольшому подмножеству). }
function ScanChannelAssignment(const Events: TElectrodeEventArray;
  const Pairs: TPairGeometryArray;
  TankWidth, TankHeight: Double;
  GridSize: Integer = 5;
  AExponentN: Double = 1.5;
  SearchSubset: Integer = 20;
  SearchGridSize: Integer = 3): TChannelMatchScanResult;

{ Строит соответствие канал -> индекс пары из ручных назначений
  UserChannel. Успешно только если все 4 пары имеют каналы 0..3 без
  повторов; иначе False и Assignment содержит -1. }
function BuildAssignmentFromPairs(const Pairs: TPairGeometryArray;
  out Assignment: TChannelAssignment): Boolean;

{ Локализует ОДНО событие по текущей (ручной) конфигурации: каналы —
  из UserChannel пар, полярность — заданная Orientation. Удобно для
  «живого» маркера, следующего за курсором/воспроизведением главной формы:
  не делает перебора, только одна локализация. Ошибка (неполный набор
  каналов, пустая геометрия) даёт Converged = False. }
function LocalizeSingleEvent(const Event: TElectrodeEventAmplitudes;
  const Pairs: TPairGeometryArray; const Orientation: TSigns4;
  TankWidth, TankHeight: Double; AExponentN: Double = 1.5;
  GridSize: Integer = 5): TLocalizedEvent;

{ True, если позиция лежит внутри аквариума (относительные координаты
  0..1 с небольшим допуском). Используется оценкой конфигураций
  (конфигурации, дающие позиции вне аквариума, штрафуются) и формой
  разметки (маркеры вне аквариума не рисуются, чтобы не засорять кадр). }
function IsPositionInsideTank(const P: TPoint2D): Boolean;

{ Индекс канала (0..3) с максимальной по модулю амплитудой события.
  Для диагностики в форме разметки: «самый активный канал» должен
  соответствовать электроду, к которому рыба стоит ближе всего — если в
  большинстве событий это не так, каналы двух почти-симметричных пар
  скорее всего перепутаны (и это видно сразу в живой информации). }
function MostActiveChannel(const Event: TElectrodeEventAmplitudes): Integer;

implementation

const
  { Штраф за несошедшееся событие: одно такое событие заведомо хуже любого
    разумного набора сошедшихся, но не «убивает» всё сравнение. }
  NotConvergedPenalty = 1E6;

  { Штраф за событие, ПОЗИЦИЯ которого вылезла за пределы аквариума:
    конфигурация, дающая рыбу вне аквариума, заведомо хуже той, что даёт
    рыбу внутри, но всё же лучше конфигурации, где событие не сошлось
    вовсе. Заставляет подбор конфигурации электродов искать вариант, при
    котором маркеры не разлетаются за пределы кадра. }
  OutOfTankPenalty = 1E3;

{ True, если позиция внутри единичного квадрата (допуск - у стенки). }
function IsPositionInsideTank(const P: TPoint2D): Boolean;
const
  Tol = 0.02;
begin
  Result := (P.X >= -Tol) and (P.X <= 1 + Tol) and
    (P.Y >= -Tol) and (P.Y <= 1 + Tol);
end;

procedure FillSigns(AOrientation: Integer; var ASigns: TSigns4);
var
  C: Integer;
begin
  for C := 0 to 3 do
    if (AOrientation and (1 shl C)) <> 0 then
      ASigns[C] := -1
    else
      ASigns[C] := 1;
end;

function MostActiveChannel(const Event: TElectrodeEventAmplitudes): Integer;
var
  C, BestC: Integer;
  BestMag: Double;
begin
  BestC := 0;
  BestMag := 0;
  for C := 0 to 3 do
    if Abs(Event.Amplitudes[C]) > BestMag then
    begin
      BestMag := Abs(Event.Amplitudes[C]);
      BestC := C;
    end;
  Result := BestC;
end;

function ApplySigns(const A: TChannelAmplitudes;
  const ASigns: TSigns4): TChannelAmplitudes;
var
  C: Integer;
begin
  for C := 0 to 3 do
    Result[C] := A[C] * ASigns[C];
end;

function BuildElectrodes(const Pairs: TPairGeometryArray;
  const Assign: TChannelAssignment): TElectrodeLayout;
var
  C: Integer;
begin
  { Знаки полярности накладываются на измеренные амплитуды (ApplySigns),
    поэтому здесь Plus/Minus берутся как есть: смена знака канала
    эквивалентна обмену Plus<->Minus местами. }
  for C := 0 to 3 do
  begin
    Result[C].Plus := Pairs[Assign[C]].A;
    Result[C].Minus := Pairs[Assign[C]].B;
  end;
end;

{ Оценивает одну перестановку (фиксированный набор пар на каналах) по
  всем 16 комбинациям знаков полярности. Возвращает минимальную суммарную
  невязку и лучшую комбинацию знаков для ЭТОЙ перестановки. }
function ScoreAssignment(const ALocalizer: TSourceLocalizer;
  const Events: TElectrodeEventArray; FirstEvents: Integer;
  TankWidth, TankHeight: Double; GridSize: Integer;
  var ABestOrientation: TSigns4): Double;
var
  Orient, E: Integer;
  Signs: TSigns4;
  Amps: TChannelAmplitudes;
  Res: TLocalizationResult;
  Total: Double;
begin
  Result := MaxDouble;
  for Orient := 0 to 15 do
  begin
    FillSigns(Orient, Signs);
    Total := 0;
    for E := 0 to FirstEvents - 1 do
    begin
      Amps := ApplySigns(Events[E].Amplitudes, Signs);
      Res := ALocalizer.LocalizeMultiStart(Amps, TankWidth, TankHeight,
        GridSize);
      if Res.Converged then
        if IsPositionInsideTank(Res.Position) then
          Total := Total + Res.ResidualRMS
        else
          Total := Total + OutOfTankPenalty
      else
        Total := Total + NotConvergedPenalty;
    end;
    if Total < Result then
    begin
      Result := Total;
      ABestOrientation := Signs;
    end;
  end;
end;

function BuildAssignmentFromPairs(const Pairs: TPairGeometryArray;
  out Assignment: TChannelAssignment): Boolean;
var
  P, C: Integer;
begin
  Result := False;
  for C := 0 to 3 do
    Assignment[C] := -1;

  for P := 0 to High(Pairs) do
  begin
    C := Pairs[P].UserChannel;
    if (C < 0) or (C > 3) then
      Exit;
    if Assignment[C] >= 0 then
      Exit; // два пары на один канал
    Assignment[C] := P;
  end;

  for C := 0 to 3 do
    if Assignment[C] < 0 then
      Exit;
  Result := True;
end;

function LocalizeSingleEvent(const Event: TElectrodeEventAmplitudes;
  const Pairs: TPairGeometryArray; const Orientation: TSigns4;
  TankWidth, TankHeight: Double; AExponentN: Double;
  GridSize: Integer): TLocalizedEvent;
var
  Assignment: TChannelAssignment;
  Layout: TElectrodeLayout;
  Amp: TChannelAmplitudes;
  Localizer: TSourceLocalizer;
  Res: TLocalizationResult;
begin
  Result.Converged := False;
  Result.Frame := Event.Frame;
  Result.Position := TPoint2D.Create(0, 0);
  Result.ResidualRMS := 0;

  if Max(TankWidth, TankHeight) <= 0 then
    Exit;
  if not BuildAssignmentFromPairs(Pairs, Assignment) then
    Exit;

  Layout := BuildElectrodes(Pairs, Assignment);
  Amp := ApplySigns(Event.Amplitudes, Orientation);

  Localizer := TSourceLocalizer.Create(Layout, AExponentN);
  try
    Res := Localizer.LocalizeMultiStart(Amp, TankWidth, TankHeight, GridSize);
    Result.Converged := Res.Converged;
    Result.Position := Res.Position;
    Result.ResidualRMS := Res.ResidualRMS;
    Result.Frame := Event.Frame;
  finally
    Localizer.Free;
  end;
end;

function ScanChannelAssignment(const Events: TElectrodeEventArray;
  const Pairs: TPairGeometryArray;
  TankWidth, TankHeight: Double;
  GridSize: Integer;
  AExponentN: Double;
  SearchSubset: Integer;
  SearchGridSize: Integer): TChannelMatchScanResult;
var
  Fixed: TChannelAssignment;
  Assign: TChannelAssignment;
  ChannelTaken: array [0 .. 3] of Boolean;
  FreePairs: array [0 .. 3] of Integer;
  FreeChannels: array [0 .. 3] of Integer;
  FreeCount: Integer;
  PairUsed: array [0 .. 3] of Boolean;
  BestAssignment: TChannelAssignment;
  BestOrientation: TSigns4;
  BestTotal: Double;
  SubsetN: Integer;
  C, P: Integer;
  Localizer: TSourceLocalizer;
  Amp: TChannelAmplitudes;
  Res: TLocalizationResult;
  Total: Double;

  procedure EnumerateAt(Level: Integer);
  var
    J: Integer;
    Loc: TSourceLocalizer;
    TmpOrientation: TSigns4;
    Score: Double;
  begin
    if Level = FreeCount then
    begin
      { Все свободные каналы заполнены — оцениваем эту перестановку. }
      Loc := TSourceLocalizer.Create(BuildElectrodes(Pairs, Assign),
        AExponentN);
      try
        Score := ScoreAssignment(Loc, Events, SubsetN, TankWidth, TankHeight,
          SearchGridSize, TmpOrientation);
      finally
        Loc.Free;
      end;
      Inc(Result.SearchCombinations);
      if (Result.SearchCombinations = 1) or (Score < BestTotal) then
      begin
        BestTotal := Score;
        BestAssignment := Assign;
        BestOrientation := TmpOrientation;
      end;
      Exit;
    end;

    for J := 0 to FreeCount - 1 do
      if not PairUsed[J] then
      begin
        PairUsed[J] := True;
        Assign[FreeChannels[Level]] := FreePairs[J];
        EnumerateAt(Level + 1);
        Assign[FreeChannels[Level]] := -1;
        PairUsed[J] := False;
      end;
  end;

begin
  Result.OK := False;
  Result.SearchCombinations := 0;
  SetLength(Result.Events, 0);

  if Length(Pairs) <> EodChannelCount then
    Exit;
  if Length(Events) = 0 then
    Exit;
  if Max(TankWidth, TankHeight) <= 0 then
    Exit;

  for C := 0 to 3 do
  begin
    Fixed[C] := -1;
    Assign[C] := -1;
    ChannelTaken[C] := False;
  end;

  { Фиксированные назначения пользователя: фиксируем и пару (Fixed
    для контроля дублей), и саму канальную перестановку (Assign — ею
    пользуется BuildElectrodes). }
  for P := 0 to High(Pairs) do
    if (Pairs[P].UserChannel >= 0) and (Pairs[P].UserChannel <= 3) then
    begin
      C := Pairs[P].UserChannel;
      if ChannelTaken[C] then
        Exit; // две пары на один канал — ошибка
      ChannelTaken[C] := True;
      Fixed[C] := P;
      Assign[C] := P;
    end;

  { Списки свободных каналов и свободных пар. }
  FreeCount := 0;
  for C := 0 to 3 do
    if not ChannelTaken[C] then
    begin
      FreeChannels[FreeCount] := C;
      Inc(FreeCount);
    end;

  for C := 0 to 3 do
    FreePairs[C] := -1;
  P := 0;
  for C := 0 to High(Pairs) do
    if (Pairs[C].UserChannel < 0) or (Pairs[C].UserChannel > 3) then
    begin
      FreePairs[P] := C;
      Inc(P);
    end;

  if P <> FreeCount then
    Exit; // число свободных пар не совпадает с числом свободных каналов

  for C := 0 to 3 do
    PairUsed[C] := False;

  SubsetN := Min(SearchSubset, Length(Events));
  BestTotal := MaxDouble;
  EnumerateAt(0);

  if Result.SearchCombinations = 0 then
    Exit;

  Result.OK := True;
  Result.Assignment := BestAssignment;
  Result.Orientation := BestOrientation;

  { Финальная локализация всех событий лучшей конфигурацией. }
  Localizer := TSourceLocalizer.Create(BuildElectrodes(Pairs,
    Result.Assignment), AExponentN);
  try
    SetLength(Result.Events, Length(Events));
    Total := 0;
    for P := 0 to High(Events) do
    begin
      Amp := ApplySigns(Events[P].Amplitudes, Result.Orientation);
      Res := Localizer.LocalizeMultiStart(Amp, TankWidth, TankHeight, GridSize);
      Result.Events[P].Frame := Events[P].Frame;
      Result.Events[P].Position := Res.Position;
      Result.Events[P].ResidualRMS := Res.ResidualRMS;
      Result.Events[P].Converged := Res.Converged;
      Total := Total + Res.ResidualRMS;
    end;
    if Length(Events) > 0 then
      Result.MeanResidual := Total / Length(Events);
  finally
    Localizer.Free;
  end;
end;

end.