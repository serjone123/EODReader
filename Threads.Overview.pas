unit Threads.Overview;

interface

uses
  System.Classes, System.SysUtils, System.SyncObjs,
  Core.Types, IO.AudioSource, GUI.Plot;

type
  TOverviewProgressEvent = procedure(Sender: TObject; Processed, Total: Int64) of object;
  TOverviewFinishedEvent = procedure(Sender: TObject;
    const OverviewMin, OverviewMax: TFloatArray;
    const ChannelMin, ChannelMax: TChannelEnvelopes;
    TotalFrames: Int64; Canceled: Boolean;
    const ErrorText: string) of object;

  TEodOverviewThread = class(TThread)
  private
    FFile1: string;
    FFile2: string;
    FPoints: Integer;
    FCancelEvent: TEvent;
    FOverviewMin: TFloatArray;
    FOverviewMax: TFloatArray;
    FChannelMin: TChannelEnvelopes;
    FChannelMax: TChannelEnvelopes;
    FTotalFrames: Int64;
    FCanceled: Boolean;
    FErrorText: string;
    FProcessed: Int64;
    FOnProgress: TOverviewProgressEvent;
    FOnFinished: TOverviewFinishedEvent;
    procedure DoProgress;
    procedure DoFinished;
    function CancelRequested: Boolean;
  protected
    procedure Execute; override;
  public
    constructor Create(const AFile1, AFile2: string; APoints: Integer = 2000);
    destructor Destroy; override;
    procedure Cancel;
    property OnProgress: TOverviewProgressEvent read FOnProgress write FOnProgress;
    property OnFinished: TOverviewFinishedEvent read FOnFinished write FOnFinished;
  end;

implementation

constructor TEodOverviewThread.Create(const AFile1, AFile2: string;
  APoints: Integer);
begin
  inherited Create(True);
  FreeOnTerminate := True;
  FFile1 := AFile1;
  FFile2 := AFile2;
  FPoints := APoints;
  if FPoints < 1 then
    FPoints := 1;
  FCancelEvent := TEvent.Create(nil, True, False, '');
end;

destructor TEodOverviewThread.Destroy;
begin
  FCancelEvent.Free;
  inherited;
end;

procedure TEodOverviewThread.Cancel;
begin
  FCancelEvent.SetEvent;
end;

function TEodOverviewThread.CancelRequested: Boolean;
begin
  Result := FCancelEvent.WaitFor(0) = wrSignaled;
end;

procedure TEodOverviewThread.DoProgress;
begin
  if Assigned(FOnProgress) then
    FOnProgress(Self, FProcessed, FTotalFrames);
end;

procedure TEodOverviewThread.DoFinished;
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

procedure TEodOverviewThread.Execute;
const
  ChunkSize = 65536;
var
  Source: TFourChannelAudioSource;
  TotalFrames: Int64;
  N: Integer;
  I, J, Ch: Integer;
  BinStart, BinEnd, StartFrame, EndFrame: Int64;
  Count64: Int64;
  Data: TAudioChunk;
  V, VMax: Single;
  ChInit: Boolean;
  ChMin: array[0..3] of Single;
  ChMax: array[0..3] of Single;
  C: Integer;
  PercentStep: Int64;
  NextProgress: Int64;
begin
  FCanceled := False;
  FErrorText := '';
  FTotalFrames := 0;
  FProcessed := 0;
  SetLength(FOverviewMin, 0);
  SetLength(FOverviewMax, 0);
  for Ch := 0 to 3 do
  begin
    SetLength(FChannelMin[Ch], 0);
    SetLength(FChannelMax[Ch], 0);
  end;

  Source := nil;
  try
    if CancelRequested then
    begin
      FCanceled := True;
      Exit;
    end;

    Source := TFourChannelAudioSource.Create(FFile1, FFile2);
    TotalFrames := Source.TotalFrames;
    FTotalFrames := TotalFrames;

    if TotalFrames <= 0 then
      Exit;

    N := FPoints;
    if TotalFrames < N then
      N := Integer(TotalFrames);
    if N < 1 then
      Exit;

    SetLength(FOverviewMin, N);
    SetLength(FOverviewMax, N);
    for Ch := 0 to 3 do
    begin
      SetLength(FChannelMin[Ch], N);
      SetLength(FChannelMax[Ch], N);
    end;

    PercentStep := TotalFrames div 100;
    if PercentStep < ChunkSize then
      PercentStep := ChunkSize;
    NextProgress := PercentStep;

    for I := 0 to N - 1 do
    begin
      if CancelRequested then
      begin
        FCanceled := True;
        Exit;
      end;

      BinStart := (Int64(I) * TotalFrames) div N;
      BinEnd := (Int64(I + 1) * TotalFrames) div N - 1;
      if BinEnd < BinStart then
        BinEnd := BinStart;

      VMax := 0;
      ChInit := False;
      for C := 0 to 3 do
      begin
        ChMin[C] := 0;
        ChMax[C] := 0;
      end;

      StartFrame := BinStart;
      while StartFrame <= BinEnd do
      begin
        if CancelRequested then
        begin
          FCanceled := True;
          Exit;
        end;

        EndFrame := BinEnd;
        if EndFrame > StartFrame + ChunkSize - 1 then
          EndFrame := StartFrame + ChunkSize - 1;

        Count64 := EndFrame - StartFrame + 1;
        if Count64 > MaxInt then
          raise Exception.Create('Overview chunk is too large');

        Source.ReadFrames(StartFrame, Integer(Count64), Data);

        for J := 0 to Length(Data) - 1 do
        begin
          V := Abs(Data[J].Ch1);
          if Abs(Data[J].Ch2) > V then V := Abs(Data[J].Ch2);
          if Abs(Data[J].Ch3) > V then V := Abs(Data[J].Ch3);
          if Abs(Data[J].Ch4) > V then V := Abs(Data[J].Ch4);
          if V > VMax then
            VMax := V;

          if ChInit then
          begin
            if Data[J].Ch1 < ChMin[0] then ChMin[0] := Data[J].Ch1;
            if Data[J].Ch1 > ChMax[0] then ChMax[0] := Data[J].Ch1;
            if Data[J].Ch2 < ChMin[1] then ChMin[1] := Data[J].Ch2;
            if Data[J].Ch2 > ChMax[1] then ChMax[1] := Data[J].Ch2;
            if Data[J].Ch3 < ChMin[2] then ChMin[2] := Data[J].Ch3;
            if Data[J].Ch3 > ChMax[2] then ChMax[2] := Data[J].Ch3;
            if Data[J].Ch4 < ChMin[3] then ChMin[3] := Data[J].Ch4;
            if Data[J].Ch4 > ChMax[3] then ChMax[3] := Data[J].Ch4;
          end
          else
          begin
            ChMin[0] := Data[J].Ch1; ChMax[0] := Data[J].Ch1;
            ChMin[1] := Data[J].Ch2; ChMax[1] := Data[J].Ch2;
            ChMin[2] := Data[J].Ch3; ChMax[2] := Data[J].Ch3;
            ChMin[3] := Data[J].Ch4; ChMax[3] := Data[J].Ch4;
            ChInit := True;
          end;
        end;

        Inc(FProcessed, Length(Data));
        if FProcessed >= NextProgress then
        begin
          TThread.Synchronize(Self, DoProgress);
          while NextProgress <= FProcessed do
            Inc(NextProgress, PercentStep);
        end;

        StartFrame := EndFrame + 1;
      end;

      FOverviewMin[I] := -VMax;
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

  Source.Free;

  TThread.Synchronize(Self, DoFinished);
end;

end.
