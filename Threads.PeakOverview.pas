unit Threads.PeakOverview;

interface

uses
  System.Classes, System.SysUtils, System.SyncObjs,
  Core.Types, IO.PeakStore;

type
  TPeakOverviewProgressEvent = procedure(Sender: TObject; Processed, Total: Int64) of object;
  TPeakOverviewFinishedEvent = procedure(Sender: TObject;
    const OverviewMin, OverviewMax: TFloatArray;
    const ChannelMin, ChannelMax: TChannelEnvelopes;
    TotalFrames: Int64; Canceled: Boolean;
    const ErrorText: string) of object;

  TEodPeakOverviewThread = class(TThread)
  private
    FFileName: string;
    FPoints: Integer;
    FCancelEvent: TEvent;
    FOverviewMin: TFloatArray;
    FOverviewMax: TFloatArray;
    FChannelMin: TChannelEnvelopes;
    FChannelMax: TChannelEnvelopes;
    FTotalFrames: Int64;
    FProcessed: Int64;
    FCanceled: Boolean;
    FErrorText: string;
    FOnProgress: TPeakOverviewProgressEvent;
    FOnFinished: TPeakOverviewFinishedEvent;
    procedure DoProgress;
    procedure DoFinished;
    function CancelRequested: Boolean;
  protected
    procedure Execute; override;
  public
    constructor Create(const AFileName: string; APoints: Integer = 2000);
    destructor Destroy; override;
    procedure Cancel;
    property OnProgress: TPeakOverviewProgressEvent read FOnProgress write FOnProgress;
    property OnFinished: TPeakOverviewFinishedEvent read FOnFinished write FOnFinished;
  end;

implementation

constructor TEodPeakOverviewThread.Create(const AFileName: string;
  APoints: Integer);
begin
  inherited Create(True);
  FreeOnTerminate := True;
  FFileName := AFileName;
  FPoints := APoints;
  if FPoints < 1 then
    FPoints := 1;
  FCancelEvent := TEvent.Create(nil, True, False, '');
end;

destructor TEodPeakOverviewThread.Destroy;
begin
  FCancelEvent.Free;
  inherited;
end;

procedure TEodPeakOverviewThread.Cancel;
begin
  FCancelEvent.SetEvent;
end;

function TEodPeakOverviewThread.CancelRequested: Boolean;
begin
  Result := FCancelEvent.WaitFor(0) = wrSignaled;
end;

procedure TEodPeakOverviewThread.DoProgress;
begin
  if Assigned(FOnProgress) then
    FOnProgress(Self, FProcessed, FTotalFrames);
end;

procedure TEodPeakOverviewThread.DoFinished;
var
  OverviewMin, OverviewMax: TFloatArray;
  ChannelMin, ChannelMax: TChannelEnvelopes;
begin
  OverviewMin := FOverviewMin;
  OverviewMax := FOverviewMax;
  ChannelMin := FChannelMin;
  ChannelMax := FChannelMax;

  if Assigned(FOnFinished) then
    FOnFinished(Self, OverviewMin, OverviewMax,
      ChannelMin, ChannelMax, FTotalFrames, FCanceled, FErrorText);
end;

procedure TEodPeakOverviewThread.Execute;
const
  MaxDisplayPoints = 4096;
var
  Store: TEodPeakStore;
  TotalFrames: Int64;
  PeakCount: Int64;
  FirstIdx, LastIdx: Int64;
  L, R, M: Int64;
  P: TPeak;
  StartFrame: Int64;
  Envelope: TWaveEnvelope;
  N, I, Ch: Integer;
  VMin, VMax: Single;
  ChMin, ChMax: array[0..3] of Single;
  ChInit: Boolean;
  PercentStep: Int64;
  NextProgress: Int64;
  SourceIndex: Integer;
  BinStart, BinEnd, BinCount: Integer;
  EStart, EEnd: Int64;
begin
  Store := nil;
  FCanceled := False;
  FErrorText := '';
  FProcessed := 0;
  FTotalFrames := 0;
  SetLength(FOverviewMin, 0);
  SetLength(FOverviewMax, 0);
  for Ch := 0 to 3 do
  begin
    SetLength(FChannelMin[Ch], 0);
    SetLength(FChannelMax[Ch], 0);
  end;

  try
    if CancelRequested then
    begin
      FCanceled := True;
      Exit;
    end;

    Store := TEodPeakStore.Open(FFileName);
    TotalFrames := Store.Header.TotalFrames;
    PeakCount := Store.Header.PeakCount;
    FTotalFrames := TotalFrames;

    if (TotalFrames <= 0) or (PeakCount <= 0) then
      Exit;

    { Find the complete peak range once. The cache reader then supplies a
      compact envelope instead of walking every waveform sample. }
    FirstIdx := 0;
    LastIdx := PeakCount - 1;

    { ReadEnvelope may return more points than requested only when the
      selected cache level cannot represent a narrower range. Limit the
      result after reading. }
    if not Store.ReadEnvelope(FirstIdx, LastIdx, MaxDisplayPoints,
      Envelope) then
      Exit;

    if CancelRequested then
    begin
      FCanceled := True;
      Exit;
    end;

    N := Length(Envelope);
    if N <= 0 then
      Exit;

    if N > FPoints then
    begin
      { Downsample the already compact envelope to the GUI point count. }
      BinCount := FPoints;
      SetLength(FOverviewMin, BinCount);
      SetLength(FOverviewMax, BinCount);
      for Ch := 0 to 3 do
      begin
        SetLength(FChannelMin[Ch], BinCount);
        SetLength(FChannelMax[Ch], BinCount);
      end;

      for I := 0 to BinCount - 1 do
      begin
        BinStart := (I * N) div BinCount;
        BinEnd := ((I + 1) * N) div BinCount - 1;
        if BinEnd < BinStart then
          BinEnd := BinStart;

        VMin := MaxSingle;
        VMax := -MaxSingle;
        ChInit := False;
        for Ch := 0 to 3 do
        begin
          ChMin[Ch] := MaxSingle;
          ChMax[Ch] := -MaxSingle;
        end;

        for SourceIndex := BinStart to BinEnd do
        begin
          if CancelRequested then
          begin
            FCanceled := True;
            Exit;
          end;

          VMin := Min(VMin, Envelope[SourceIndex].Ch1Min);
          VMin := Min(VMin, Envelope[SourceIndex].Ch2Min);
          VMin := Min(VMin, Envelope[SourceIndex].Ch3Min);
          VMin := Min(VMin, Envelope[SourceIndex].Ch4Min);

          VMax := Max(VMax, Envelope[SourceIndex].Ch1Max);
          VMax := Max(VMax, Envelope[SourceIndex].Ch2Max);
          VMax := Max(VMax, Envelope[SourceIndex].Ch3Max);
          VMax := Max(VMax, Envelope[SourceIndex].Ch4Max);

          ChMin[0] := Min(ChMin[0], Envelope[SourceIndex].Ch1Min);
          ChMax[0] := Max(ChMax[0], Envelope[SourceIndex].Ch1Max);
          ChMin[1] := Min(ChMin[1], Envelope[SourceIndex].Ch2Min);
          ChMax[1] := Max(ChMax[1], Envelope[SourceIndex].Ch2Max);
          ChMin[2] := Min(ChMin[2], Envelope[SourceIndex].Ch3Min);
          ChMax[2] := Max(ChMax[2], Envelope[SourceIndex].Ch3Max);
          ChMin[3] := Min(ChMin[3], Envelope[SourceIndex].Ch4Min);
          ChMax[3] := Max(ChMax[3], Envelope[SourceIndex].Ch4Max);
          ChInit := True;
        end;

        FOverviewMin[I] := VMin;
        FOverviewMax[I] := VMax;
        for Ch := 0 to 3 do
        begin
          FChannelMin[Ch][I] := ChMin[Ch];
          FChannelMax[Ch][I] := ChMax[Ch];
        end;
      end;
    end
    else
    begin
      SetLength(FOverviewMin, N);
      SetLength(FOverviewMax, N);
      for Ch := 0 to 3 do
      begin
        SetLength(FChannelMin[Ch], N);
        SetLength(FChannelMax[Ch], N);
      end;

      for I := 0 to N - 1 do
      begin
        FOverviewMin[I] := Min(
          Min(Envelope[I].Ch1Min, Envelope[I].Ch2Min),
          Min(Envelope[I].Ch3Min, Envelope[I].Ch4Min));
        FOverviewMax[I] := Max(
          Max(Envelope[I].Ch1Max, Envelope[I].Ch2Max),
          Max(Envelope[I].Ch3Max, Envelope[I].Ch4Max));

        FChannelMin[0][I] := Envelope[I].Ch1Min;
        FChannelMax[0][I] := Envelope[I].Ch1Max;
        FChannelMin[1][I] := Envelope[I].Ch2Min;
        FChannelMax[1][I] := Envelope[I].Ch2Max;
        FChannelMin[2][I] := Envelope[I].Ch3Min;
        FChannelMax[2][I] := Envelope[I].Ch3Max;
        FChannelMin[3][I] := Envelope[I].Ch4Min;
        FChannelMax[3][I] := Envelope[I].Ch4Max;
      end;
    end;

    FProcessed := TotalFrames;
    PercentStep := TotalFrames div 100;
    if PercentStep < 1 then
      PercentStep := 1;
    NextProgress := PercentStep;
    TThread.Synchronize(Self, DoProgress);
  except
    on E: Exception do
    begin
      FErrorText := E.Message;
      FCanceled := CancelRequested;
    end;
  end;

  Store.Free;
  Store := nil;

  TThread.Synchronize(Self, DoFinished);
end;

end.
