unit Threads.PeakOverview;

interface

uses
  System.Classes, System.SysUtils, System.SyncObjs,
  Core.Types, IO.PeakStore, GUI.Plot;

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

uses
  System.Math;

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
  Envelope: TWaveEnvelope;
  N, I, Ch: Integer;
  VMin, VMax: Single;
  ChMin, ChMax: array[0..3] of Single;
  SourceIndex: Integer;
  BinStart, BinEnd, BinCount: Integer;
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
      begin
        FErrorText := Format(
          'Некорректные параметры peak-файла: TotalFrames=%d, PeakCount=%d',
          [TotalFrames, PeakCount]);
        Exit;
      end;

      if not Store.ReadEnvelope(0, PeakCount - 1, MaxDisplayPoints,
        Envelope) then
      begin
        FErrorText := 'Не удалось прочитать огибающую из peak-файла';
        Exit;
      end;

      if CancelRequested then
      begin
        FCanceled := True;
        Exit;
      end;

      N := Length(Envelope);
      if N <= 0 then
      begin
        FErrorText := 'Огибающая пуста';
        Exit;
      end;

      BinCount := N;
      if BinCount > FPoints then
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
        end;

        FOverviewMin[I] := VMin;
        FOverviewMax[I] := VMax;
        for Ch := 0 to 3 do
        begin
          FChannelMin[Ch][I] := ChMin[Ch];
          FChannelMax[Ch][I] := ChMax[Ch];
        end;
      end;

      FProcessed := TotalFrames;
      TThread.Synchronize(Self, DoProgress);
    except
      on E: Exception do
      begin
        FErrorText := E.Message;
        FCanceled := CancelRequested;
      end;
    end;
  finally
    Store.Free;

    if CancelRequested then
      FCanceled := True;

    TThread.Synchronize(Self, DoFinished);
  end;
end;

end.
