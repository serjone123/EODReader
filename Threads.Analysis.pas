unit Threads.Analysis;

interface

uses
  System.Classes, System.SysUtils, System.SyncObjs,
  Core.Types, Detection.Detector, Threads.Base;

type
  TAnalysisProgressEvent = procedure(Sender: TObject; Processed, Total: Int64) of object;
  TAnalysisFinishedEvent = procedure(Sender: TObject; const Peaks: TPeakArray;
    Canceled: Boolean; const ErrorText: string) of object;

  { Фоновый анализ записи. Отмену, тексты ошибок и гарантированный вызов
    DoFinished (в главном потоке, до выхода из Execute) обеспечивает
    TEodBackgroundThread. Главный поток никогда не вызывает WaitFor на
    этом воркере, поэтому Synchronize из потока безопасен; OnTerminate
    форма использует только для учёта времени жизни потока. }
  TEodAnalysisThread = class(TEodBackgroundThread)
  private
    FFile1: string;
    FFile2: string;
    FMaxFrames: Int64;
    FConfig: TEodDetectorConfig;
    FPeaks: TPeakArray;
    FProcessed: Int64;
    FTotal: Int64;
    FOnProgress: TAnalysisProgressEvent;
    FOnFinished: TAnalysisFinishedEvent;
    procedure DetectorProgress(Sender: TObject; Processed, Total: Int64);
    function DetectorCancel(Sender: TObject): Boolean;
  protected
    procedure RunTask; override;
    procedure DoProgress; override;
    procedure DoFinished; override;
  public
    constructor Create(const AFile1, AFile2: string;
      const AConfig: TEodDetectorConfig; AMaxFrames: Int64 = 0);
    property OnProgress: TAnalysisProgressEvent read FOnProgress write FOnProgress;
    property OnFinished: TAnalysisFinishedEvent read FOnFinished write FOnFinished;
  end;

implementation

constructor TEodAnalysisThread.Create(const AFile1, AFile2: string;
  const AConfig: TEodDetectorConfig; AMaxFrames: Int64);
begin
  inherited Create;
  FFile1 := AFile1;
  FFile2 := AFile2;
  FConfig := AConfig;
  FMaxFrames := AMaxFrames;
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

procedure TEodAnalysisThread.DoFinished;
begin
  if Assigned(FOnFinished) then
    FOnFinished(Self, FPeaks, FCanceled, FErrorText);
end;

procedure TEodAnalysisThread.RunTask;
var
  Detector: TEodDetector;
begin
  SetLength(FPeaks, 0);

  Detector := TEodDetector.Create(FConfig);
  try
    { Отмена приходит в детектор колбэком DetectorCancel: детектор сам
      решает, когда выйти, поэтому здесь CheckCancel не нужен. }
    FPeaks := Detector.AnalyzePeaks(
      FFile1,
      FFile2,
      FMaxFrames,
      DetectorProgress,
      DetectorCancel);
  finally
    Detector.Free;
  end;

  { Финальные 100% показываем только если анализ не отменяли. }
  if not CancelRequested then
  begin
    FProcessed := FTotal;
    if Assigned(FOnProgress) then
      TThread.Synchronize(Self, DoProgress);
  end;
end;

end.
