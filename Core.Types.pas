unit Core.Types;

interface

uses
  System.SysUtils;

type

  TWaveEnvelopePoint = packed record
    StartPosition: Int64;
    EndPosition: Int64;

    Ch1Min: Single;
    Ch1Max: Single;

    Ch2Min: Single;
    Ch2Max: Single;

    Ch3Min: Single;
    Ch3Max: Single;

    Ch4Min: Single;
    Ch4Max: Single;
  end;

  TWaveEnvelope = array of TWaveEnvelopePoint;

  TFloatArray = array of Single;

  { Поканальные min/max огибающие; индекс 0..3 — канал 1..4.
    (Комментарий перенесён из GUI.Plot.pas при чистке дублирующего
    закомментированного объявления этого типа там же.) }
  TChannelEnvelopes = array[0..3] of TFloatArray;

  TAudioFrame = packed record
    Ch1: Single;
    Ch2: Single;
    Ch3: Single;
    Ch4: Single;
  end;

  TAudioChunk = array of TAudioFrame;

  TFishType = (ftUnknown, ftGnat, ftMorm, ftStim);

  TPeak = record
    Position: Int64;
    Value: Single;
    Prominence: Single;
  end;

  TCorrelationResult = record
    Correlation: Single;
    Position: Integer; // zero-based inside the Test window
    Channel: Integer;  // zero-based
  end;

  { Событие классификации. Position — нулевой кадр CENTRA шаблона
    (середины EOD-выброса) в исходной записи, т.е.
    (начало окна) + (сдвиг шаблона) + Length(шаблон) div 2 —
    соответствует матлаб-эталону xx_locs = c_et + xb + corr_ind(chan).
    Это НЕ позиция максимума STD-пика (TPeak.Position) и не начало шаблона,
    а точка, где расположен сам разряд. }
  TEodEvent = record
    Position: Int64;
    FishType: TFishType;
    Correlation: Single;
    Channel: Integer;  // zero-based
  end;

  TPeakArray = array of TPeak;
  TEodEventArray = array of TEodEvent;

  TEodDetectorConfig = record
    PeakProminence: Single;
    CorrelationThreshold: Single;
    WindowBefore: Integer;
    WindowAfter: Integer;
    ExtractionBefore: Integer;
    ExtractionAfter: Integer;
    ChunkSize: Integer;
    DuplicateDistance: Int64;
    { При клике по обзору переводить вид к ближайшему пику, а не к точке
      клика. По умолчанию включено (настраивается в config.json). }
    OverviewSnapToPeak: Boolean;
  end;

function DefaultEodDetectorConfig: TEodDetectorConfig;
function FishTypeToString(AType: TFishType): string;
{ Строит общую (одноцветную) огибающую обзора из поканальных.
  ASymmetric = True: ±max(|min|, |max|) по всем каналам (амплитудный вид);
  False: настоящие min/max по всем каналам. Бины без данных остаются нулевыми. }
procedure BuildGeneralEnvelope(const AChMin, AChMax: TChannelEnvelopes;
  ASymmetric: Boolean; out AMin, AMax: TFloatArray);

implementation

function DefaultEodDetectorConfig: TEodDetectorConfig;
begin
  Result.PeakProminence := 0.002;
  Result.CorrelationThreshold := 0.9;
  Result.WindowBefore := 200;
  Result.WindowAfter := 200;
  Result.ExtractionBefore := 30;
  Result.ExtractionAfter := 30;
  Result.ChunkSize := 65536;
  Result.DuplicateDistance := 5;
  Result.OverviewSnapToPeak := True;
end;

function FishTypeToString(AType: TFishType): string;
begin
  case AType of
    ftGnat: Result := 'Gnat';
    ftMorm: Result := 'Morm';
    ftStim: Result := 'Stim';
  else
    Result := 'Unknown';
  end;
end;

procedure BuildGeneralEnvelope(const AChMin, AChMax: TChannelEnvelopes;
  ASymmetric: Boolean; out AMin, AMax: TFloatArray);
var
  N, I, Ch: Integer;
  VMin, VMax, V: Single;
begin
  { Длина результата — минимальная длина среди всех поканальных массивов. }
  N := Length(AChMin[0]);
  for Ch := 0 to 3 do
  begin
    if Length(AChMin[Ch]) < N then N := Length(AChMin[Ch]);
    if Length(AChMax[Ch]) < N then N := Length(AChMax[Ch]);
  end;

  SetLength(AMin, N);
  SetLength(AMax, N);

  for I := 0 to N - 1 do
  begin
    VMin := AChMin[0][I];
    VMax := AChMax[0][I];
    for Ch := 1 to 3 do
    begin
      if AChMin[Ch][I] < VMin then VMin := AChMin[Ch][I];
      if AChMax[Ch][I] > VMax then VMax := AChMax[Ch][I];
    end;

    if ASymmetric then
    begin
      V := Abs(VMin);
      if Abs(VMax) > V then V := Abs(VMax);
      AMin[I] := -V;
      AMax[I] := V;
    end
    else
    begin
      AMin[I] := VMin;
      AMax[I] := VMax;
    end;
  end;
end;

end.
