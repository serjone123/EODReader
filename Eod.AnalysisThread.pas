unit Eod.AnalysisThread;

interface

uses
  System.Classes, System.SysUtils, System.SyncObjs,
  Eod.Types, Eod.Detector;

type
  TAnalysisProgressEvent = procedure(Sender: TObject; Processed, Total: Int64) of object;
  TAnalysisFinishedEvent = procedure(Sender: TObject; const Peaks: TPeakArray;
    Canceled: Boolean; const ErrorText: string) of object;

  TEodAnalysisThread = class(TThread)
  private
    FFile1: string;
    FFile2: string;
    FMaxFrames: Int64;
    FConfig: TEodDetectorConfig;
    FCancelEvent: TEvent;
    FPeaks: TPeakArray;
    FCanceled: Boolean;
    FErrorText: string;
    FProcessed: Int64;
    FTotal: Int64;
    FOnProgress: TAnalysisProgressEvent;
    FOnFinished: TAnalysisFinishedEvent;
    procedure DoProgress;
    function CancelRequested: Boolean;
    procedure DetectorProgress(Sender: TObject; Processed, Total: Int64);
    function DetectorCancel(Sender: TObject): Boolean;
  protected
    procedure Execute; override;
    procedure DoTerminate; override;
  public
    constructor Create(const AFile1, AFile2: string;
      const AConfig: TEodDetectorConfig; AMaxFrames: Int64 = 0);
    destructor Destroy; override;
    procedure Cancel;
    property OnProgress: TAnalysisProgressEvent read FOnProgress write FOnProgress;
    property OnFinished: TAnalysisFinishedEvent read FOnFinished write FOnFinished;
  end;

implementation

constructor TEodAnalysisThread.Create(const AFile1, AFile2: string;
  const AConfig: TEodDetectorConfig; AMaxFrames: Int64);
begin
  inherited Create(True);
  FreeOnTerminate := True;
  FFile1 := AFile1;
  FFile2 := AFile2;
  FConfig := AConfig;
  FMaxFrames := AMaxFrames;
  FCancelEvent := TEvent.Create(nil, True, False, '');
end;

destructor TEodAnalysisThread.Destroy;
begin
  FCancelEvent.Free;
  inherited;
end;

procedure TEodAnalysisThread.Cancel;
begin
  FCancelEvent.SetEvent;
end;

function TEodAnalysisThread.CancelRequested: Boolean;
begin
  Result := FCancelEvent.WaitFor(0) = wrSignaled;
end;

procedure TEodAnalysisThread.DetectorProgress(Sender: TObject; Processed,
  Total: Int64);
begin
  FProcessed := Processed;
  FTotal := Total;
  if Assigned(FOnProgress) then
    TThread.Synchronize(Self, DoProgress);
end;

function TEodAnalysisThread.DetectorCancel(Sender: TObject): Boolean;
begin
  Result := CancelRequested;
end;

procedure TEodAnalysisThread.DoProgress;
begin
  if Assigned(FOnProgress) then
    FOnProgress(Self, FProcessed, FTotal);
end;

procedure TEodAnalysisThread.DoTerminate;
begin
  { Do not call GUI callbacks here. Execute runs in the worker thread,
    while OnTerminate is dispatched by TThread in the main thread. }
  inherited DoTerminate;
end;

procedure TEodAnalysisThread.Execute;
var
  Detector: TEodDetector;
begin
  FCanceled := False;
  FErrorText := '';
  SetLength(FPeaks, 0);
  try
    Detector := TEodDetector.Create(FConfig);
    try
      FPeaks := Detector.AnalyzePeaks(
        FFile1,
        FFile2,
        FMaxFrames,
        DetectorProgress,
        DetectorCancel);
    finally
      Detector.Free;
    end;

    FCanceled := CancelRequested;
    if not FCanceled then
    begin
      FProcessed := FTotal;
      if Assigned(FOnProgress) then
        TThread.Synchronize(Self, DoProgress);
    end;
  except
    on E: Exception do
    begin
      FErrorText := E.Message;
      FCanceled := CancelRequested;
    end;
  end;

  { Deliver the final result in the main thread before Execute returns.
    This is safe because the main thread never calls WaitFor on this worker.
    OnTerminate will only perform lifetime bookkeeping. }
  if Assigned(FOnFinished) then
    TThread.Synchronize(Self,
      procedure
      begin
        if Assigned(FOnFinished) then
          FOnFinished(Self, FPeaks, FCanceled, FErrorText);
      end);
end;

end.
