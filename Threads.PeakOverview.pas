unit Threads.PeakOverview;

interface

uses
  System.Classes, System.SysUtils,
  Core.Types, IO.PeakStore, Threads.OverviewBase;

type
  { Построение обзорной огибающей из кэша .eodpk: ReadEnvelope и раскладка
    бакетов кэша по бинам обзора. Общий каркас — в TEodOverviewBaseThread. }
  TEodPeakOverviewThread = class(TEodOverviewBaseThread)
  private
    FFileName: string;
    FSpreadBuckets: Boolean;
  protected
    procedure RunTask; override;
  public
    constructor Create(const AFileName: string; APoints: Integer = 2000);

    { True — бакет кэша заполняет все бины своего диапазона кадров;
      False — только бин по центру диапазона. Временный переключатель
      для визуального сравнения. Есть только у обзора EODPK. }
    property SpreadBuckets: Boolean read FSpreadBuckets write FSpreadBuckets;
  end;

implementation

uses
  System.Math;

constructor TEodPeakOverviewThread.Create(const AFileName: string;
  APoints: Integer);
begin
  inherited Create(APoints);
  FFileName := AFileName;
  FSpreadBuckets := True;
end;

procedure TEodPeakOverviewThread.RunTask;
const
  MaxDisplayPoints = 4096;
var
  Store: TEodPeakStore;
  TotalFrames: Int64;
  PeakCount: Int64;
  Envelope: TWaveEnvelope;
  BinCount, I, Ch, B, B0, B1: Integer;
  Touched: array of Boolean;
  BktMin, BktMax: array[0..3] of Single;

  { Кадр -> номер бина. Бины равномерны по времени записи (как в
    Threads.Overview), иначе обзор не совпадёт с красным прямоугольником
    текущего вида. Отрицательные/выходящие за конец кадры (окно пика у
    границы при PadWithZero) прижимаются к краям. }
  function FrameToBin(AFrame: Int64): Integer;
  begin
    Result := EnsureRange(
      Integer((AFrame * BinCount) div TotalFrames), 0, BinCount - 1);
  end;

  { Добавляет min/max текущего бакета в бин; первый вклад в бин
    просто задаёт значения (нулевая инициализация не должна
    подмешиваться в min/max). }
  procedure AddToBin(ABin: Integer);
  var
    C: Integer;
  begin
    for C := 0 to 3 do
    begin
      if (not Touched[ABin]) or (BktMin[C] < FChannelMin[C][ABin]) then
        FChannelMin[C][ABin] := BktMin[C];
      if (not Touched[ABin]) or (BktMax[C] > FChannelMax[C][ABin]) then
        FChannelMax[C][ABin] := BktMax[C];
    end;
    Touched[ABin] := True;
  end;

begin
  ResetResult;

  Store := nil;
  try
    CheckCancel;

    Store := TEodPeakStore.Open(FFileName);
    TotalFrames := Store.Header.TotalFrames;
    PeakCount := Store.Header.PeakCount;
    FTotalFrames := TotalFrames;

    if (TotalFrames <= 0) or (PeakCount <= 0) then
      raise Exception.CreateFmt(
        'Некорректные параметры peak-файла: TotalFrames=%d, PeakCount=%d',
        [TotalFrames, PeakCount]);

    if not Store.ReadEnvelope(0, PeakCount - 1, MaxDisplayPoints,
      Envelope) then
      raise Exception.Create('Не удалось прочитать огибающую из peak-файла');

    CheckCancel;

    if Length(Envelope) <= 0 then
      raise Exception.Create('Огибающая пуста');

    BinCount := FPoints;
    if TotalFrames < BinCount then
      BinCount := Integer(TotalFrames);
    if BinCount < 1 then
      BinCount := 1;

    for Ch := 0 to 3 do
    begin
      SetLength(FChannelMin[Ch], BinCount);
      SetLength(FChannelMax[Ch], BinCount);
      for I := 0 to BinCount - 1 do
      begin
        FChannelMin[Ch][I] := 0;
        FChannelMax[Ch][I] := 0;
      end;
    end;

    SetLength(Touched, BinCount);
    for I := 0 to BinCount - 1 do
      Touched[I] := False;

    for I := 0 to High(Envelope) do
    begin
      CheckCancel;

      { Пустой бакет (см. InitBucket в IO.PeakStore) — пропускаем. }
      if Envelope[I].EndPosition < Envelope[I].StartPosition then
        Continue;

      BktMin[0] := Envelope[I].Ch1Min;  BktMax[0] := Envelope[I].Ch1Max;
      BktMin[1] := Envelope[I].Ch2Min;  BktMax[1] := Envelope[I].Ch2Max;
      BktMin[2] := Envelope[I].Ch3Min;  BktMax[2] := Envelope[I].Ch3Max;
      BktMin[3] := Envelope[I].Ch4Min;  BktMax[3] := Envelope[I].Ch4Max;

      if FSpreadBuckets then
      begin
        B0 := FrameToBin(Envelope[I].StartPosition);
        B1 := FrameToBin(Envelope[I].EndPosition);
      end
      else
      begin
        B0 := FrameToBin(Envelope[I].StartPosition +
          (Envelope[I].EndPosition - Envelope[I].StartPosition) div 2);
        B1 := B0;
      end;

      for B := B0 to B1 do
        AddToBin(B);
    end;

    BuildGeneralEnvelope(FChannelMin, FChannelMax, True,
      FOverviewMin, FOverviewMax);

    FProcessed := TotalFrames;
    TThread.Synchronize(Self, DoProgress);
  finally
    { Файл закрываем до DoFinished (его вызывает база): форма может
      сразу переоткрыть этот же .eodpk. }
    Store.Free;
  end;
end;

end.
