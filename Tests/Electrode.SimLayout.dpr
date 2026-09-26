program Electrode.SimLayout;

{ Консольный симулятор раскладки электродов для подсистемы Electrode.

  Оценивает КАЧЕСТВО геометрии электродных пар на бумаге, до постановки
  физического эксперимента:

    1. Генерирует сетку истинных позиций рыбы по аквариуму (0..1).
    2. Для каждой позиции считает амплитуды 4 каналов по той же модели,
       что и реальная форма (PredictChannelValue, 1/d^n), с опциональным
       аддитивным шумом.
    3. Прогоняет события через ТОТ ЖЕ конвейер, что и приложение:
       - auto:  ScanChannelAssignment с 4 свободными каналами (полный
                подбор пары<->канал <-> полярность);
       - fixed: те же события, но каналы пар зафиксированы (подбор только
                полярности) - "как если бы пользователь уже правильно
                назначил каналы".
    4. Сравнивает найденные позиции с истинными и выдаёт ошибку в см
       (аквариум задан размерами --tank), плюс сравнение найденного
       сопоставления канал<->пара с эталонным (identity) - так численно
       виден обмен каналов на симметричных раскладках (тот самый
       "зелёный <-> оранжевый").
    5. Пишет SVG-картинку раскладки + теплокарту ошибки (--svg файл.svg).

  Использование:
    Electrode.SimLayout [--layout file.json] [--preset recommended|symmetric]
        [--grid N] [--noise frac] [--tank W H] [--exp n] [--seed n]
        [--svg out.svg] [--report out.txt]
    Electrode.SimLayout --truth marks.json [--tank W H] [--exp n]
        [--svg out.svg] [--report out.txt]

  По умолчанию без --layout берёт пресет "recommended" и записывает
  LayoutResult.svg с его теплокартой. Плохой пресет "symmetric" доступен
  через --preset symmetric - прогоните его отдельно и сравните ошибки.
  С --layout загружает реальный JSON из формы разметки (LoadElectrodeLayout-
  FromJSON) и оценивает именно вашу геометрию.

  Режим --truth анализирует реальные данные: истинные позиции рыбы,
  помеченные в форме разметки (файл *_marks.json рядом с разметкой, см.
  Electrode.Layout.SaveTruthMarksToJSON), локализует каждое событие той же
  моделью поля и сравнивает с кликом: ошибка в см, несовпадение
  «активный канал <-> ближайший электрод», зеркальная неоднозначность.
  Разметка берётся из поля layoutFile файла marks.json; аквариум - из
  marks-файла, затем из разметки, затем --tank. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Math, System.Classes, System.StrUtils,
  Electrode.Geometry, Electrode.Localization, Electrode.Matching,
  Electrode.Layout;

const
  DefExponentN = 1.5;

type
  { Контакты одной пары в относительных координатах аквариума (0..1),
    Plus = A, Minus = B (полярность эталонной конфигурации "+"). }
  TPairDef = record
    A, B: TPoint2D;
  end;
  TPairDefArray = array of TPairDef;

  TChannelColors = array [0 .. 3] of string;

  TDoubleArray = array of Double;

  TPoint2DArray = array of TPoint2D;

  TBoolArray = array of Boolean;

  TLayoutResult = record
    Name: string;
    AutoOK, FixedOK: Boolean;
    AutoConverged, FixedConverged: Integer;
    AutoErrors, FixedErrors: TDoubleArray; // ошибка в см по событиям
    AutoErrAll: TDoubleArray; // -1 = локализация не сошлась (для картинки)
    AutoIdentity, FixedIdentity: Boolean;
    AutoAssignText, FixedAssignText: string;
    AutoOrientation, FixedOrientation: string;
    AutoMeanRes, FixedMeanRes: Double;
  end;

var
  TankW, TankH: Double;
  GridN: Integer;
  NoiseFrac: Double;
  ExponentN: Double;
  Seed: Int64;
  SvgFile: string;
  ReportFile: string;
  LayoutFile: string;
  PresetName: string;
  TruthFile: string;

  ChannelColors: TChannelColors = ('#E33E2E', '#2E9E3B', '#3373D6',
    '#EF8D22');

function Fmt(AFmt: string; const AArgs: array of const): string;
begin
  Result := Format(AFmt, AArgs, TFormatSettings.Invariant);
end;

procedure SortAsc(var A: TDoubleArray);
var
  I, J: Integer;
  V: Double;
begin
  for I := 1 to High(A) do
  begin
    V := A[I];
    J := I - 1;
    while (J >= 0) and (A[J] > V) do
    begin
      A[J + 1] := A[J];
      Dec(J);
    end;
    A[J + 1] := V;
  end;
end;

procedure Stats(const AErr: TDoubleArray; out AMean, AMedian, AP90, AMax: Double);
var
  Sorted: TDoubleArray;
  I, N: Integer;
begin
  AMean := 0;
  AMedian := 0;
  AP90 := 0;
  AMax := 0;
  N := Length(AErr);
  if N = 0 then
    Exit;
  SetLength(Sorted, N);
  for I := 0 to N - 1 do
    Sorted[I] := AErr[I];
  SortAsc(Sorted);
  for I := 0 to N - 1 do
    AMean := AMean + Sorted[I];
  AMean := AMean / N;
  AMedian := Sorted[N div 2];
  AP90 := Sorted[Integer(Round(0.9 * (N - 1)))];
  AMax := Sorted[N - 1];
end;

{ ---------- Пресеты раскладок (относительные координаты 0..1) ---------- }

{ Рекомендуемая: контакты у всех четырёх стенок, оси пар разные и НЕ
  зеркальные - вертикаль слева, вертикаль справа со сдвигом, две наклонные
  снизу и сверху с разными наклонами. Каждая пара закрывает свою зону,
  слепых полос через центр нет, зеркальные сопоставления каналов не
  вырождены. }
function RecommendedDefs: TPairDefArray;
begin
  SetLength(Result, 4);
  Result[0].A := TPoint2D.Create(0.10, 0.20); // Ch1 - красный, слева
  Result[0].B := TPoint2D.Create(0.10, 0.60);
  Result[1].A := TPoint2D.Create(0.90, 0.45); // Ch2 - зелёный, справа
  Result[1].B := TPoint2D.Create(0.90, 0.85);
  Result[2].A := TPoint2D.Create(0.15, 0.15); // Ch3 - синий, низ
  Result[2].B := TPoint2D.Create(0.65, 0.05);
  Result[3].A := TPoint2D.Create(0.30, 0.85); // Ch4 - оранжевый, верх
  Result[3].B := TPoint2D.Create(0.85, 0.95);
end;

{ Симметричная (как НЕ надо): пары попарно зеркальны относительно центра -
  зеркальные сопоставления каналов неразличимы по невязке. }
function SymmetricDefs: TPairDefArray;
begin
  SetLength(Result, 4);
  Result[0].A := TPoint2D.Create(0.12, 0.35); // Ch1
  Result[0].B := TPoint2D.Create(0.12, 0.65);
  Result[1].A := TPoint2D.Create(0.88, 0.65); // Ch2 - зеркало Ch1
  Result[1].B := TPoint2D.Create(0.88, 0.35);
  Result[2].A := TPoint2D.Create(0.33, 0.12); // Ch3
  Result[2].B := TPoint2D.Create(0.67, 0.12);
  Result[3].A := TPoint2D.Create(0.33, 0.88); // Ch4 - зеркало Ch3
  Result[3].B := TPoint2D.Create(0.67, 0.88);
end;

{ ---------- Конвертация ---------- }

{ Позиции пары в см: контакты в реальной модели (Electrode.Localization)
  задаются в сантиметрах, MinDist там равен 0.5 см - поэтому 0..1 пресеты
  масштабируем на размеры аквариума. }
function DefsToWorldPairs(const Defs: TPairDefArray): TPairGeometryArray;
var
  I: Integer;
begin
  SetLength(Result, Length(Defs));
  for I := 0 to High(Defs) do
  begin
    Result[I].A := TPoint2D.Create(Defs[I].A.X * TankW, Defs[I].A.Y * TankH);
    Result[I].B := TPoint2D.Create(Defs[I].B.X * TankW, Defs[I].B.Y * TankH);
    Result[I].UserChannel := -1; // свободно, сам симулятор решает режим
  end;
end;

{ Копия пар с фиксированным сопоставлением "канал = индекс пары". }
function PairsWithIdentityChannels(const Pairs: TPairGeometryArray)
  : TPairGeometryArray;
var
  I: Integer;
begin
  SetLength(Result, Length(Pairs));
  for I := 0 to High(Pairs) do
  begin
    Result[I].A := Pairs[I].A;
    Result[I].B := Pairs[I].B;
    Result[I].UserChannel := I;
  end;
end;

{ Амплитуда канала C в точке P: эталонная полярность "+" (Plus=A, Minus=B). }
function AmpAt(const P: TPoint2D; const Pairs: TPairGeometryArray; C: Integer): Double;
var
  PR: TElectrodePair;
begin
  PR.Plus := Pairs[C].A;
  PR.Minus := Pairs[C].B;
  Result := PredictChannelValue(P, 1.0, PR, ExponentN);
end;

{ ---------- Генерация синтетических событий ---------- }

procedure GenerateEvents(const Pairs: TPairGeometryArray;
  out Events: TElectrodeEventArray; out TruePositions: array of TPoint2D);
var
  IY, IX, C, Idx: Integer;
  P: TPoint2D;
  AmpMax: Double;
begin
  SetLength(Events, GridN * GridN);
  Idx := 0;
  for IY := 0 to GridN - 1 do
    for IX := 0 to GridN - 1 do
    begin
      P.X := (IX + 0.5) / GridN * TankW;
      P.Y := (IY + 0.5) / GridN * TankH;
      TruePositions[Idx] := P;
      Events[Idx].Frame := Idx;
      AmpMax := 0;
      for C := 0 to 3 do
      begin
        Events[Idx].Amplitudes[C] := AmpAt(P, Pairs, C);
        if Abs(Events[Idx].Amplitudes[C]) > AmpMax then
          AmpMax := Abs(Events[Idx].Amplitudes[C]);
      end;
      if (NoiseFrac > 0) and (AmpMax > 0) then
        for C := 0 to 3 do
          Events[Idx].Amplitudes[C] :=
            Events[Idx].Amplitudes[C] + RandG(0, NoiseFrac * AmpMax);
      Inc(Idx);
    end;
end;

{ ---------- Один прогон (события -> ошибки) ---------- }

procedure RunScan(const Events: TElectrodeEventArray;
  const Pairs: TPairGeometryArray; const TruePositions: array of TPoint2D;
  out Converged: Integer; out Errors: TDoubleArray;
  out ErrAll: TDoubleArray;
  out IdentityMatch: Boolean; out AssignText, OrientationText: string;
  out MeanRes: Double);
var
  Res: TChannelMatchScanResult;
  I, C, N: Integer;
  Dx, Dy, E: Double;
begin
  Converged := 0;
  SetLength(Errors, 0);
  IdentityMatch := False;
  AssignText := '';
  OrientationText := '';
  MeanRes := 0;
  N := Length(Events);
  SetLength(ErrAll, N);
  for I := 0 to N - 1 do
    ErrAll[I] := -1;

  Res := ScanChannelAssignment(Events, Pairs, TankW, TankH, 5, ExponentN,
    Min(20, N), 3);
  if not Res.OK then
    Exit;

  // Сопоставление канал->пара: совпало с эталонной (identity)?
  IdentityMatch := True;
  for C := 0 to 3 do
    if Res.Assignment[C] <> C then
      IdentityMatch := False;

  AssignText := '';
  for C := 0 to 3 do
  begin
    if C > 0 then
      AssignText := AssignText + '  ';
    AssignText := AssignText + Fmt('Ch%d=>п%d', [C + 1, Res.Assignment[C] + 1]);
  end;
  OrientationText := '';
  for C := 0 to 3 do
  begin
    if C > 0 then
      OrientationText := OrientationText + ' ';
    if Res.Orientation[C] < 0 then
      OrientationText := OrientationText + Fmt('Ch%d:-', [C + 1])
    else
      OrientationText := OrientationText + Fmt('Ch%d:+', [C + 1]);
  end;
  MeanRes := Res.MeanResidual;

  // Ошибки: converged-события в см.
  for I := 0 to High(Res.Events) do
  begin
    if not Res.Events[I].Converged then
      Continue;
    Inc(Converged);
    Dx := Res.Events[I].Position.X - TruePositions[I].X;
    Dy := Res.Events[I].Position.Y - TruePositions[I].Y;
    E := Sqrt(Dx * Dx + Dy * Dy);
    ErrAll[I] := E;
    SetLength(Errors, Length(Errors) + 1);
    Errors[High(Errors)] := E;
  end;
end;

{ Печать отчёта по одной раскладке. }

function BuildReport(const R: TLayoutResult): string;
var
  S: TStringBuilder;
  Mean, Med, P90, MaxV: Double;
begin
  S := TStringBuilder.Create;
  try
    S.AppendLine;
    S.AppendLine('===== ' + R.Name + ' =====');

    S.AppendLine('--- режим auto (каналы пар НЕ знаем, полный подбор) ---');
    if R.AutoOK then
    begin
      Stats(R.AutoErrors, Mean, Med, P90, MaxV);
      S.AppendLine(Fmt(
        'найдено сопоставление: %s  (эталон: Ch1=>п1  Ch2=>п2  Ch3=>п3  Ch4=>п4)',
        [R.AutoAssignText]));
      S.AppendLine(Fmt('совпало с эталоном: %s   полярность: %s',
        [BoolToStr(R.AutoIdentity, True), R.AutoOrientation]));
      if not R.AutoIdentity then
        S.AppendLine(
          '  ! обмен каналов/зеркальная связка - источник "зелёного<->оранжевого"');
      S.AppendLine(Fmt('событий сошлось: %d из %d    средняя невязка RMS: %.4f',
        [R.AutoConverged, GridN * GridN, R.AutoMeanRes]));
      S.AppendLine(
        Fmt('ошибка локализации, см: средняя=%.2f  медиана=%.2f  P90=%.2f  макс=%.2f',
        [Mean, Med, P90, MaxV]));
    end
    else
      S.AppendLine('подбор не удался (ScanChannelAssignment вернул OK=False)');

    S.AppendLine('--- режим fixed (каналы пар заданы правильно) ---');
    if R.FixedOK then
    begin
      Stats(R.FixedErrors, Mean, Med, P90, MaxV);
      S.AppendLine(Fmt('найдено сопоставление: %s   полярность: %s',
        [R.FixedAssignText, R.FixedOrientation]));
      S.AppendLine(Fmt('совпало с эталоном: %s',
        [BoolToStr(R.FixedIdentity, True)]));
      S.AppendLine(Fmt('событий сошлось: %d из %d    средняя невязка RMS: %.4f',
        [R.FixedConverged, GridN * GridN, R.FixedMeanRes]));
      S.AppendLine(
        Fmt('ошибка локализации, см: средняя=%.2f  медиана=%.2f  P90=%.2f  макс=%.2f',
        [Mean, Med, P90, MaxV]));
    end
    else
      S.AppendLine('локализация не удалась (ScanChannelAssignment вернул OK=False)');

    Result := S.ToString;
  finally
    S.Free;
  end;
end;

procedure ReportPrint(const R: TLayoutResult);
begin
  Write(BuildReport(R));
end;

function RunCase(const AName: string; const PairsWorld: TPairGeometryArray;
  const TruePositions: array of TPoint2D;
  const Events: TElectrodeEventArray): TLayoutResult;
var
  AutoPairs: TPairGeometryArray;
  FixedPairs: TPairGeometryArray;
  FixedErrAll: TDoubleArray; // для fixed-режима картинку не рисуем
begin
  Result.Name := AName;
  Result.AutoErrors := nil;
  Result.FixedErrors := nil;

  AutoPairs := PairsWorld;
  Result.AutoOK := True;
  RunScan(Events, AutoPairs, TruePositions, Result.AutoConverged,
    Result.AutoErrors, Result.AutoErrAll, Result.AutoIdentity,
    Result.AutoAssignText, Result.AutoOrientation, Result.AutoMeanRes);
  Result.AutoOK := Result.AutoConverged > 0;

  FixedPairs := PairsWithIdentityChannels(PairsWorld);
  Result.FixedOK := True;
  RunScan(Events, FixedPairs, TruePositions, Result.FixedConverged,
    Result.FixedErrors, FixedErrAll, Result.FixedIdentity,
    Result.FixedAssignText, Result.FixedOrientation, Result.FixedMeanRes);
  Result.FixedOK := Result.FixedConverged > 0;
end;

{ ---------- SVG: раскладка + теплокарта ошибки ---------- }

procedure WriteSvg(const AFileName, ATitle: string;
  const PairsWorld: TPairGeometryArray; const Errors: TDoubleArray);
const
  CW = 760;
  CH = 540;
  MX = 46;
  MY = 96;
var
  PW, PH, CellW, CellH: Double;
  I, C: Integer;
  X0, Y0, X1, Y1: Double;
  MaxErr: Double;
  Rc, Gc, Bc, T: Double;
  S: TStringBuilder;
  PairColor: string;

  function PxX(Rel: Double): Double;
  begin
    Result := MX + Rel * PW;
  end;
  function PxY(Rel: Double): Double;
  begin
    Result := MY + (1 - Rel) * PH;
  end;

  function HeatColor(E: Double): string;
  var
    R, G, B: Integer;
  begin
    if MaxErr <= 0 then
      T := 0
    else
      T := E / MaxErr;
    if T < 0 then
      T := 0;
    if T > 1 then
      T := 1;
    // зелёный -> жёлтый -> красный
    if T < 0.5 then
    begin
      Rc := 255 * (2 * T);
      Gc := 255;
    end
    else
    begin
      Rc := 255;
      Gc := 255 * (2 * (1 - T));
    end;
    Bc := 60 * (1 - T);
    R := Round(Rc);
    G := Round(Gc);
    B := Round(Bc);
    Result := Fmt('#%2.2x%2.2x%2.2x', [R, G, B]);
  end;

begin
  PW := CW - 2 * MX;
  PH := CH - MY - 70;
  if PH > PW * (TankH / TankW) then
    PH := PW * (TankH / TankW)
  else
    PW := PH * (TankW / TankH);
  CellW := PW / GridN;
  CellH := PH / GridN;

  // Максимальная ошибка для шкалы.
  MaxErr := 0;
  for I := 0 to High(Errors) do
    if Errors[I] > MaxErr then
      MaxErr := Errors[I];

  S := TStringBuilder.Create;
  try
    S.Append('<?xml version="1.0" encoding="UTF-8"?>' + #10);
    S.Append(Fmt('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">' + #10,
      [CW, CH, CW, CH]));
    S.Append('<rect width="760" height="540" fill="#ffffff"/>' + #10);
    S.Append(Fmt('<text x="%d" y="34" font-size="22" font-family="sans-serif" ' +
      'font-weight="bold" fill="#222">%s</text>' + #10, [MX, ATitle]));

    // Ячейки сетки истинных позиций с цветом = средняя ошибка
    // (серая = локализация не сошлась).
    for I := 0 to High(Errors) do
    begin
      X0 := PxX((I mod GridN + 0.0) / GridN);
      Y0 := PxY((I div GridN + 1.0) / GridN);
      if Errors[I] < 0 then
        S.Append(Fmt('<rect x="%.2f" y="%.2f" width="%.2f" height="%.2f" ' +
          'fill="#e8e8e8" stroke="#aaa" stroke-width="1"/>' + #10,
          [X0, Y0, CellW + 0.8, CellH + 0.8]))
      else
        S.Append(Fmt('<rect x="%.2f" y="%.2f" width="%.2f" height="%.2f" ' +
          'fill="%s" stroke="#ddd" stroke-width="1"/>' + #10,
          [X0, Y0, CellW + 0.8, CellH + 0.8, HeatColor(Errors[I])]));
    end;

    // Пары электродов: линия + два контакта, цвет канала.
    for C := 0 to High(PairsWorld) do
    begin
      PairColor := '#999999';
      if PairsWorld[C].UserChannel in [0 .. 3] then
        PairColor := ChannelColors[PairsWorld[C].UserChannel];
      X0 := PxX(PairsWorld[C].A.X / TankW);
      Y0 := PxY(PairsWorld[C].A.Y / TankH);
      X1 := PxX(PairsWorld[C].B.X / TankW);
      Y1 := PxY(PairsWorld[C].B.Y / TankH);
      S.Append(Fmt('<line x1="%.2f" y1="%.2f" x2="%.2f" y2="%.2f" stroke="%s" ' +
        'stroke-width="4"/>' + #10, [X0, Y0, X1, Y1, PairColor]));
      S.Append(Fmt('<circle cx="%.2f" cy="%.2f" r="7" fill="%s" stroke="#000" ' +
        'stroke-width="1.5"/>' + #10, [X0, Y0, PairColor]));
      S.Append(Fmt('<circle cx="%.2f" cy="%.2f" r="7" fill="%s" stroke="#000" ' +
        'stroke-width="1.5"/>' + #10, [X1, Y1, PairColor]));
      S.Append(Fmt('<text x="%.2f" y="%.2f" font-size="14" font-family="sans-serif" ' +
        'fill="#000">П%d</text>' + #10,
        [(X0 + X1) / 2 - 6, (Y0 + Y1) / 2 - 10, C + 1]));
    end;

    // Легенда цветов каналов.
    for C := 0 to 3 do
    begin
      X0 := MX + C * 100;
      S.Append(Fmt('<rect x="%.2f" y="%d" width="16" height="16" fill="%s" ' +
        'stroke="#000" stroke-width="1"/>' + #10, [X0, CH - 40,
        ChannelColors[C]]));
      S.Append(Fmt('<text x="%.2f" y="%d" font-size="14" font-family="sans-serif" ' +
        'fill="#000">Ch%d</text>' + #10, [X0 + 22, CH - 27, C + 1]));
    end;
    S.Append(Fmt('<text x="%d" y="%d" font-size="14" font-family="sans-serif" ' +
      'fill="#666">максимальная ошибка на шкале: %.2f см. Цвет ячейки = средняя ' +
      'ошибка локализации (зелёный - хорошо, красный - плохо); серая = подбор ' +
      'не сошёлся.</text>' + #10, [MX, CH - 10, MaxErr]));

    S.Append('</svg>' + #10);
    with TStringStream.Create(S.ToString, TEncoding.UTF8) do
      try
        SaveToFile(AFileName);
      finally
        Free;
      end;
  finally
    S.Free;
  end;
end;

{ ---------- JSON-раскладка из формы разметки ---------- }

function LoadJsonPairs(out AName: string): TPairGeometryArray;
var
  L: TElectrodeLayoutInput;
  Calib: TAquariumCalibration;
  I: Integer;

  function RelToCm(const P: TPoint2D): TPoint2D;
  begin
    Result.X := P.X * TankW;
    Result.Y := P.Y * TankH;
  end;

begin
  SetLength(Result, 0);
  AName := '';
  L := LoadElectrodeLayoutFromJSON(LayoutFile);
  if L.TankCornersSet <> 4 then
  begin
    Writeln('В JSON не заданы 4 угла аквариума - нельзя построить калибровку.');
    Exit;
  end;
  { Размеры аквариума берём из файла разметки, если они там заполнены;
    иначе - заданный --tank (по умолчанию 60x30). }
  if (L.TankWidthCm > 0) and (L.TankHeightCm > 0) then
  begin
    TankW := L.TankWidthCm;
    TankH := L.TankHeightCm;
    Writeln('Размеры аквариума взяты из файла разметки: ' +
      Fmt('%d x %d см.', [Round(TankW), Round(TankH)]));
  end
  else
    Writeln('В файле разметки не заданы размеры аквариума - используется --tank (' +
      Fmt('%d x %d см).', [Round(TankW), Round(TankH)]));
  Calib := BuildCalibrationFromLayout(L);
  if not Assigned(Calib) then
  begin
    Writeln('Не удалось построить калибровку из углов JSON.');
    Exit;
  end;
  SetLength(Result, Length(L.Pairs));
  for I := 0 to High(L.Pairs) do
  begin
    { PixelToWorld даёт ОТНОСИТЕЛЬНЫЕ координаты 0..1 (см. комментарий у
      BuildCalibrationFromLayout), а модель поля и MinDist = 0.5 см
      (Electrode.Localization) работают в САНТИМЕТРАХ - поэтому пары
      масштабируются на размеры аквариума, как и пресеты пресетов. }
    Result[I].A := RelToCm(Calib.PixelToWorld(L.Pairs[I].PointA));
    Result[I].B := RelToCm(Calib.PixelToWorld(L.Pairs[I].PointB));
    Result[I].UserChannel := L.Pairs[I].ChannelIndex;
  end;
  AName := 'Раскладка из ' + ExtractFileName(LayoutFile);
end;

{ ---------- Анализ реальных данных: --truth ---------- }

{ Индекс пары электродов, ближайшей к точке (по любому из двух контактов),
  в относительных координатах. }
function NearestPairTo(const P: TPoint2D;
  const PairsRel: TPairGeometryArray): Integer;
var
  I: Integer;
  D, DA, DB, Best: Double;
begin
  Result := -1;
  Best := MaxDouble;
  for I := 0 to High(PairsRel) do
  begin
    DA := Sqr(PairsRel[I].A.X - P.X) + Sqr(PairsRel[I].A.Y - P.Y);
    DB := Sqr(PairsRel[I].B.X - P.X) + Sqr(PairsRel[I].B.Y - P.Y);
    D := DA;
    if DB < D then
      D := DB;
    if D < Best then
    begin
      Best := D;
      Result := I;
    end;
  end;
end;

procedure WriteTruthSvg(const AFileName, ATitle: string;
  const PairsWorld: TPairGeometryArray;
  const Marks: TTruthMarkArray;
  const ErrArr: TDoubleArray;
  const PredRel: TPoint2DArray;
  const ConvArr: TBoolArray);
const
  CW = 760;
  CH = 540;
  MX = 46;
  MY = 96;
var
  PW, PH: Double;
  I, C: Integer;
  X0, Y0, X1, Y1: Double;
  MaxErr: Double;
  T: Double;
  Rc, Gc, Bc: Double;
  S: TStringBuilder;
  PairColor: string;

  function PxX(Rel: Double): Double;
  begin
    Result := MX + Rel * PW;
  end;
  function PxY(Rel: Double): Double;
  begin
    Result := MY + (1 - Rel) * PH;
  end;
  function HeatColor(E: Double): string;
  var
    R, G, B: Integer;
  begin
    if MaxErr <= 0 then
      T := 0
    else
      T := E / MaxErr;
    if T < 0 then
      T := 0;
    if T > 1 then
      T := 1;
    if T < 0.5 then
    begin
      Rc := 255 * (2 * T);
      Gc := 255;
    end
    else
    begin
      Rc := 255;
      Gc := 255 * (2 * (1 - T));
    end;
    Bc := 60 * (1 - T);
    R := Round(Rc);
    G := Round(Gc);
    B := Round(Bc);
    Result := Fmt('#%2.2x%2.2x%2.2x', [R, G, B]);
  end;

begin
  PW := CW - 2 * MX;
  PH := CH - MY - 70;
  if PH > PW * (TankH / TankW) then
    PH := PW * (TankH / TankW)
  else
    PW := PH * (TankW / TankH);

  MaxErr := 0;
  for I := 0 to High(ErrArr) do
    if (ErrArr[I] >= 0) and (ErrArr[I] > MaxErr) then
      MaxErr := ErrArr[I];

  S := TStringBuilder.Create;
  try
    S.Append('<?xml version="1.0" encoding="UTF-8"?>' + #10);
    S.Append(Fmt('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">' + #10,
      [CW, CH, CW, CH]));
    S.Append('<rect width="760" height="540" fill="#ffffff"/>' + #10);
    S.Append(Fmt('<text x="%d" y="34" font-size="22" font-family="sans-serif" ' +
      'font-weight="bold" fill="#222">%s</text>' + #10, [MX, ATitle]));

    // Стенки аквариума.
    S.Append(Fmt('<rect x="%.2f" y="%.2f" width="%.2f" height="%.2f" ' +
      'fill="none" stroke="#555" stroke-width="2"/>' + #10,
      [PxX(0), PxY(1), PW, PH]));

    // Пары электродов: линия + два контакта, цвет канала.
    for C := 0 to High(PairsWorld) do
    begin
      PairColor := '#999999';
      if PairsWorld[C].UserChannel in [0 .. 3] then
        PairColor := ChannelColors[PairsWorld[C].UserChannel];
      X0 := PxX(PairsWorld[C].A.X / TankW);
      Y0 := PxY(PairsWorld[C].A.Y / TankH);
      X1 := PxX(PairsWorld[C].B.X / TankW);
      Y1 := PxY(PairsWorld[C].B.Y / TankH);
      S.Append(Fmt('<line x1="%.2f" y1="%.2f" x2="%.2f" y2="%.2f" stroke="%s" ' +
        'stroke-width="4"/>' + #10, [X0, Y0, X1, Y1, PairColor]));
      S.Append(Fmt('<circle cx="%.2f" cy="%.2f" r="7" fill="%s" stroke="#000" ' +
        'stroke-width="1.5"/>' + #10, [X0, Y0, PairColor]));
      S.Append(Fmt('<circle cx="%.2f" cy="%.2f" r="7" fill="%s" stroke="#000" ' +
        'stroke-width="1.5"/>' + #10, [X1, Y1, PairColor]));
    end;

    // Метки: клик - кружок цвета ошибки + линия к предсказанию (тёмная точка).
    for I := 0 to High(Marks) do
    begin
      X0 := PxX(Marks[I].PositionRel.X);
      Y0 := PxY(Marks[I].PositionRel.Y);
      if ConvArr[I] then
      begin
        X1 := PxX(PredRel[I].X);
        Y1 := PxY(PredRel[I].Y);
        S.Append(Fmt('<line x1="%.2f" y1="%.2f" x2="%.2f" y2="%.2f" ' +
          'stroke="#666" stroke-width="1.2" stroke-dasharray="4,3"/>' + #10,
          [X0, Y0, X1, Y1]));
        S.Append(Fmt('<circle cx="%.2f" cy="%.2f" r="4" fill="#222"/>' + #10,
          [X1, Y1]));
        S.Append(Fmt('<circle cx="%.2f" cy="%.2f" r="9" fill="%s" ' +
          'stroke="#000" stroke-width="1.5"/>' + #10,
          [X0, Y0, HeatColor(ErrArr[I])]));
      end
      else if Marks[I].HasAmp then
        S.Append(Fmt('<circle cx="%.2f" cy="%.2f" r="9" fill="#e8e8e8" ' +
          'stroke="#999" stroke-width="1.5"/>' + #10, [X0, Y0]))
      else
        S.Append(Fmt('<circle cx="%.2f" cy="%.2f" r="5" fill="#cccccc" ' +
          'stroke="#888" stroke-width="1"/>' + #10, [X0, Y0]));
      S.Append(Fmt('<text x="%.2f" y="%.2f" font-size="13" font-family="sans-serif" ' +
        'fill="#000">И%d</text>' + #10, [X0 + 11, Y0 - 6, I + 1]));
    end;

    // Легенда.
    S.Append(Fmt('<text x="%d" y="%d" font-size="14" font-family="sans-serif" ' +
      'fill="#666">кружок = клик ("истина"; зелёный - ошибка мала, красный - ' +
      'велика); тёмная точка = предсказание модели, пунктир = ошибка; серый ' +
      'кружок = не сошлось. Максимум шкалы: %.2f см.</text>' + #10,
      [MX, CH - 10, MaxErr]));
    S.Append(Fmt('<text x="%d" y="%d" font-size="14" font-family="sans-serif" ' +
      'fill="#666">линии пар - электроды (цвет = канал, см. раскладку).</text>' + #10,
      [MX, CH - 28]));

    S.Append('</svg>' + #10);
    with TStringStream.Create(S.ToString, TEncoding.UTF8) do
      try
        SaveToFile(AFileName);
      finally
        Free;
      end;
  finally
    S.Free;
  end;
end;

{ Загружает метки и разметку, локализует каждое событие той же моделью,
  что и приложение, сравнивает предсказание с кликом. Весь результат -
  в тексте и (опционально) в SVG. }
procedure RunTruth(const AMarksFile: string);
var
  Marks: TTruthMarkArray;
  MarksLayoutFile, LayoutPath, DirName: string;
  MarksTankW, MarksTankH: Double;
  L: TElectrodeLayoutInput;
  Calib: TAquariumCalibration;
  PairsRel, PairsCm: TPairGeometryArray;
  Assign: TChannelAssignment;
  AssignOk: Boolean;
  UseW, UseH: Double;
  I, O, C: Integer;
  ClickCm, PredCm, MirrCm, ClickRel: TPoint2D;
  Event: TElectrodeEventAmplitudes;
  Signs: TSigns4;
  Cand, Best: TLocalizedEvent;
  BestRMS: Double;
  FoundInside: Boolean;
  Err, DistPred, DistMirr: Double;
  ActiveC, NearestP: Integer;
  ErrArr: TDoubleArray;
  ErrConv: TDoubleArray; // только сошедшиеся ошибки, для сводной статистики
  PredRel: TPoint2DArray;
  ConvArr: TBoolArray;
  BestSignsArr: array of TSigns4;
  BestRMSArr: TDoubleArray; // RMS выбранной полярности для каждой метки
  Mean, Med, P90, MaxV: Double;
  ConvCount, MismatchCount, NAmp: Integer;
  S: TStringBuilder;
  SigText: string;
begin
  { ---- Загрузка меток и привязанной разметки ---- }
  Marks := LoadTruthMarksFromJSON(AMarksFile, MarksLayoutFile,
    MarksTankW, MarksTankH);
  if Length(Marks) = 0 then
  begin
    Writeln('Не удалось прочитать метки из ' + AMarksFile);
    Halt(1);
  end;
  if MarksLayoutFile = '' then
  begin
    Writeln('В marks-файле не указан "layoutFile" (JSON разметки).');
    Halt(1);
  end;
  DirName := ExtractFilePath(ExpandFileName(AMarksFile));
  LayoutPath := DirName + MarksLayoutFile;
  if not FileExists(LayoutPath) then
  begin
    Writeln('Файл разметки не найден: ' + LayoutPath);
    Halt(1);
  end;
  L := LoadElectrodeLayoutFromJSON(LayoutPath);
  if L.TankCornersSet <> 4 then
  begin
    Writeln('В разметке не заданы 4 угла аквариума - нельзя построить калибровку.');
    Halt(1);
  end;

  { Аквариум в см: размеры из marks-файла, затем из разметки, затем --tank. }
  if (MarksTankW > 0) and (MarksTankH > 0) then
  begin
    UseW := MarksTankW;
    UseH := MarksTankH;
    Writeln('Размеры аквариума: из marks-файла (' + Fmt('%d x %d см).',
      [Round(UseW), Round(UseH)]));
  end
  else if (L.TankWidthCm > 0) and (L.TankHeightCm > 0) then
  begin
    UseW := L.TankWidthCm;
    UseH := L.TankHeightCm;
    Writeln('Размеры аквариума: из файла разметки (' + Fmt('%d x %d см).',
      [Round(UseW), Round(UseH)]));
  end
  else
  begin
    UseW := TankW;
    UseH := TankH;
    Writeln('Размеры аквариума: из --tank (' + Fmt('%d x %d см).',
      [Round(UseW), Round(UseH)]));
  end;
  TankW := UseW;
  TankH := UseH;

  Calib := BuildCalibrationFromLayout(L);
  if not Assigned(Calib) then
  begin
    Writeln('Не удалось построить калибровку из углов разметки.');
    Halt(1);
  end;

  SetLength(PairsRel, Length(L.Pairs));
  SetLength(PairsCm, Length(L.Pairs));
  for I := 0 to High(L.Pairs) do
  begin
    PairsRel[I].A := Calib.PixelToWorld(L.Pairs[I].PointA);
    PairsRel[I].B := Calib.PixelToWorld(L.Pairs[I].PointB);
    PairsRel[I].UserChannel := L.Pairs[I].ChannelIndex;
    PairsCm[I].A := TPoint2D.Create(PairsRel[I].A.X * UseW,
      PairsRel[I].A.Y * UseH);
    PairsCm[I].B := TPoint2D.Create(PairsRel[I].B.X * UseW,
      PairsRel[I].B.Y * UseH);
    PairsCm[I].UserChannel := L.Pairs[I].ChannelIndex;
  end;
  if Length(PairsCm) <> 4 then
  begin
    Writeln('Нужно ровно 4 пары электродов (получено: ' +
      IntToStr(Length(PairsCm)) + ').');
    Halt(1);
  end;

  AssignOk := BuildAssignmentFromPairs(PairsCm, Assign);
  if not AssignOk then
    Writeln('ВНИМАНИЕ: каналы пар назначены не полностью - события с амплитудами локализоваться не смогут.');

  { ---- Локализация каждой метки ---- }
  SetLength(ErrArr, Length(Marks));
  SetLength(PredRel, Length(Marks));
  SetLength(ConvArr, Length(Marks));
  SetLength(BestSignsArr, Length(Marks));
  SetLength(BestRMSArr, Length(Marks));
  ConvCount := 0;
  MismatchCount := 0;

  for I := 0 to High(Marks) do
  begin
    ClickRel := Marks[I].PositionRel;
    ClickCm := TPoint2D.Create(ClickRel.X * UseW, ClickRel.Y * UseH);
    PredRel[I] := ClickRel;
    ConvArr[I] := False;
    ErrArr[I] := -1;
    for C := 0 to 3 do
      BestSignsArr[I][C] := 1;
    FoundInside := False;
    BestRMS := MaxDouble;

    if not Marks[I].HasAmp then
      Continue; // только клик, без амплитуд событие локализовать нечем

    Event.Frame := Marks[I].Frame;
    for C := 0 to 3 do
      Event.Amplitudes[C] := Marks[I].Amplitudes[C];

    { Перебор 16 полярностей: берём лучшую (минимум невязки) из позиций,
      сошедшихся внутрь аквариума, - как сделал бы «живой маркер» формы
      разметки при подборе полярности. }
    for O := 0 to 15 do
    begin
      for C := 0 to 3 do
        if (O and (1 shl C)) <> 0 then
          Signs[C] := -1
        else
          Signs[C] := 1;
      Cand := LocalizeSingleEvent(Event, PairsCm, Signs,
        UseW, UseH, ExponentN, 5);
      if Cand.Converged and IsPositionInsideTank(
        TPoint2D.Create(Cand.Position.X / UseW, Cand.Position.Y / UseH)) then
        if (not FoundInside) or (Cand.ResidualRMS < BestRMS) then
        begin
          FoundInside := True;
          BestRMS := Cand.ResidualRMS;
          Best := Cand;
          BestSignsArr[I] := Signs;
        end;
    end;

    if not FoundInside then
      Continue;

    ConvArr[I] := True;
    Inc(ConvCount);
    PredCm := Best.Position;
    PredRel[I] := TPoint2D.Create(PredCm.X / UseW, PredCm.Y / UseH);
    BestRMSArr[I] := BestRMS;
    Err := Sqrt(Sqr(PredCm.X - ClickCm.X) + Sqr(PredCm.Y - ClickCm.Y));
    ErrArr[I] := Err;
    SetLength(ErrConv, Length(ErrConv) + 1);
    ErrConv[High(ErrConv)] := Err;

    { Зеркальная неоднозначность: предсказание ближе к зеркально
      отражённому клику, чем к самому клику. }
    MirrCm := TPoint2D.Create(UseW - ClickCm.X, UseH - ClickCm.Y);
    DistPred := Abs(PredCm.X - ClickCm.X) + Abs(PredCm.Y - ClickCm.Y);
    DistMirr := Abs(PredCm.X - MirrCm.X) + Abs(PredCm.Y - MirrCm.Y);

    if AssignOk then
    begin
      ActiveC := MostActiveChannel(Event);
      NearestP := NearestPairTo(ClickRel, PairsRel);
      if (NearestP >= 0) and (NearestP <> Assign[ActiveC]) then
        Inc(MismatchCount);
    end;
  end;

  NAmp := 0;
  for I := 0 to High(Marks) do
    if Marks[I].HasAmp then
      Inc(NAmp);

  { ---- Отчёт ---- }
  S := TStringBuilder.Create;
  try
    S.AppendLine;
    S.AppendLine('===== Проверка на истинных позициях =====');
    S.AppendLine('Файл меток: ' + AMarksFile);
    S.AppendLine('Разметка: ' + MarksLayoutFile);
    S.AppendLine(Format('Аквариум: %d x %d см.  Меток: %d.',
      [Round(UseW), Round(UseH), Length(Marks)]));
    S.AppendLine(Format('С амплитудами событий: %d, из них локализовано внутрь аквариума: %d.',
      [NAmp, ConvCount]));
    if NAmp < Length(Marks) then
      S.AppendLine(Format('  %d меток БЕЗ амплитуд (только клик) - по ним предсказание не считается.',
        [Length(Marks) - NAmp]));

    for I := 0 to High(Marks) do
    begin
      ClickRel := Marks[I].PositionRel;
      S.AppendLine(Format('  #%d: клик (%.1f, %.1f) см%s', [I + 1,
        ClickRel.X * UseW, ClickRel.Y * UseH,
        IfThen(Marks[I].HasAmp, '', '  [без амплитуд]')]));
      if not Marks[I].HasAmp then
        Continue;
      if ConvArr[I] then
      begin
        SigText := Format('Ch%d:%s  Ch%d:%s  Ch%d:%s  Ch%d:%s',
          [1, IfThen(BestSignsArr[I][0] < 0, '-', '+'),
           2, IfThen(BestSignsArr[I][1] < 0, '-', '+'),
           3, IfThen(BestSignsArr[I][2] < 0, '-', '+'),
           4, IfThen(BestSignsArr[I][3] < 0, '-', '+')]);
        S.AppendLine(Format(
          '      предсказано (%.1f, %.1f) см, ошибка %.2f см, RMS %.4f, полярность %s',
          [PredRel[I].X * UseW, PredRel[I].Y * UseH, ErrArr[I],
           BestRMSArr[I], SigText]));
        if AssignOk then
        begin
          ActiveC := MostActiveChannel(Event);
          NearestP := NearestPairTo(ClickRel, PairsRel);
          if (NearestP >= 0) and (NearestP = Assign[ActiveC]) then
            S.AppendLine(Format(
              '      активный канал Ch%d = ближайший к клику электрод (пара %d): согласовано.',
              [ActiveC + 1, NearestP + 1]))
          else if NearestP >= 0 then
            S.AppendLine(Format(
              '      активный канал Ch%d, а ближайший к клику электрод - пара %d: каналы могли быть перепутаны.',
              [ActiveC + 1, NearestP + 1]))
          else
            S.AppendLine('      ближайший к клику электрод не определён.');
        end
        else
          S.AppendLine('      каналы пар не назначены - согласованность не проверяется.');
      end
      else
        S.AppendLine('      позиция не сошлась внутрь аквариума (ни при одной полярности).');
    end;

    S.AppendLine;
    if ConvCount > 0 then
    begin
      Stats(ErrConv, Mean, Med, P90, MaxV);
      S.AppendLine(Fmt('ИТОГО: ошибка локализации, см: средняя = %.2f  ' +
        'медиана = %.2f  P90 = %.2f  макс = %.2f  (по %d меткам)',
        [Mean, Med, P90, MaxV, ConvCount]));
    end
    else
      S.AppendLine('ИТОГО: ни одна метка с амплитудами не локализовалась внутрь аквариума.');

    if AssignOk and (MismatchCount > 0) then
      S.AppendLine(Format(
        'НЕСОГЛАСОВАННОСТЬ: в %d из %d сошедшихся меток самый активный канал ' +
        'не соответствует ближайшему к клику электроду - признак перепутанных ' +
        'каналов почти-симметричных пар.', [MismatchCount, ConvCount]));

    Write(S.ToString);
    if ReportFile <> '' then
      with TStringStream.Create(S.ToString, TEncoding.UTF8) do
        try
          SaveToFile(ReportFile);
        finally
          Free;
        end;
  finally
    S.Free;
  end;

  if SvgFile <> '' then
  begin
    WriteTruthSvg(SvgFile,
      Fmt('Истинные позиции - ошибка локализации (аквариум %d x %d см)',
        [Round(UseW), Round(UseH)]),
      PairsCm, Marks, ErrArr, PredRel, ConvArr);
    Writeln;
    Writeln('Картинка записана: ' + SvgFile);
  end;
end;

function GetArg(ALongName: string; var AValue: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 1 to ParamCount - 1 do
    if SameText(ParamStr(I), ALongName) then
    begin
      AValue := ParamStr(I + 1);
      Exit(True);
    end;
end;

procedure ParseArgs;
var
  V: string;
begin
  TankW := 60;
  TankH := 30;
  GridN := 8;
  NoiseFrac := 0.03;
  ExponentN := DefExponentN;
  Seed := -1;
  SvgFile := 'LayoutResult.svg';
  ReportFile := '';
  LayoutFile := '';
  PresetName := 'recommended';
  TruthFile := '';

  if GetArg('--grid', V) then
    GridN := StrToIntDef(V, 8);
  if GetArg('--noise', V) then
    NoiseFrac := StrToFloatDef(V, 0.03);
  if GetArg('--tank', V) then
  begin
    TankW := StrToFloatDef(Copy(V, 1, Pos('x', V + 'x') - 1), TankW);
    TankH := StrToFloatDef(Copy(V, Pos('x', V + 'x') + 1, 20), TankH);
  end;
  if GetArg('--exp', V) then
    ExponentN := StrToFloatDef(V, DefExponentN);
  if GetArg('--seed', V) then
    Seed := StrToInt64Def(V, -1);
  if GetArg('--svg', V) then
    SvgFile := V;
  if GetArg('--report', V) then
    ReportFile := V;
  if GetArg('--layout', V) then
    LayoutFile := V;
  if GetArg('--preset', V) then
    PresetName := V;
  if GetArg('--truth', V) then
  begin
    TruthFile := V;
    { По умолчанию для проверки - отдельный SVG, чтобы не затирать
      LayoutResult.svg обычного прогона; явный --svg не перекрываем. }
    if SvgFile = 'LayoutResult.svg' then
      SvgFile := 'TruthResult.svg';
  end;
end;

{ ---------- Главная ---------- }

var
  PairsWorld: TPairGeometryArray;
  Prs: TPairDefArray;
  Events: TElectrodeEventArray;
  TruePos: array of TPoint2D;
  Rslt: TLayoutResult;
  Name: string;

begin
  ParseArgs;

  // Режим проверки на истинных позициях: анализ меток, отчёт и SVG.
  if TruthFile <> '' then
  begin
    RunTruth(TruthFile);
    Halt(0);
  end;

  if Seed >= 0 then
    RandSeed := Integer(Seed)
  else
    Randomize;

  // Раскладка: либо из JSON, либо пресет.
  if LayoutFile <> '' then
  begin
    PairsWorld := LoadJsonPairs(Name);
    if Length(PairsWorld) = 0 then
      Halt(1);
  end
  else
  begin
    if SameText(PresetName, 'symmetric') then
      Prs := SymmetricDefs
    else
      Prs := RecommendedDefs;
    PairsWorld := DefsToWorldPairs(Prs);
    Name := 'Пресет "' + PresetName + '" (' + Fmt('%d x %d см, сетка %d, шум %.1f%%)',
      [Round(TankW), Round(TankH), GridN, NoiseFrac * 100]) + ')';
  end;

  if Length(PairsWorld) <> 4 then
  begin
    Writeln('Нужно ровно 4 пары электродов (получено: ' +
      IntToStr(Length(PairsWorld)) + ').');
    Halt(1);
  end;

  Writeln('Симулятор раскладки электродов: сетка истинных позиций ' +
    IntToStr(GridN) + 'x' + IntToStr(GridN));

  SetLength(TruePos, GridN * GridN);
  GenerateEvents(PairsWorld, Events, TruePos);

  Rslt := RunCase(Name, PairsWorld, TruePos, Events);
  ReportPrint(Rslt);

  { Отчёт в файл (UTF-8): консоль в cmd только с chcp 65001. }
  if ReportFile <> '' then
  begin
    with TStringStream.Create(BuildReport(Rslt), TEncoding.UTF8) do
      try
        SaveToFile(ReportFile);
      finally
        Free;
      end;
    Writeln;
    Writeln('Отчёт сохранён: ' + ReportFile);
  end;

  // Для auto-режима рисуем раскладку + теплокарту ошибки.
  if SvgFile <> '' then
  begin
    WriteSvg(SvgFile, Fmt('%s - ошибка локализации (auto), %d x %d см',
      [Name, Round(TankW), Round(TankH)]), PairsWorld, Rslt.AutoErrAll);
    Writeln;
    Writeln('Картинка записана: ' + SvgFile);
  end;

  end.