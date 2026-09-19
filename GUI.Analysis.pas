unit GUI.Analysis;

interface

uses
  System.Classes, System.SysUtils,
  Core.Types, Detection.Detector,
  Threads.Analysis, Threads.WavOpen, Threads.Overview, Threads.PeakOverview;

type
  { Держит и запускает фоновые воркеры главной формы: анализ WAV,
    открытие пары WAV, построение обзора WAV и обзора EODPK.

    Класс владеет ссылками на потоки: запускает их, при необходимости
    отменяет и сбрасывает ссылку по завершении (потоки создаются с
    FreeOnTerminate и освобождаются самостоятельно). Прогресс и результат
    отдаются наружу событиями, поэтому класс ничего не знает ни о форме,
    ни о её контролах — реакция на данные остаётся в TMainForm.

    Перед уничтожением класса воркеры должны быть завершены: форма не
    закрывается, пока работает хотя бы один (FormCloseQuery). }
  TEodAnalysisController = class
  private
    FAnalysis: TEodAnalysisThread;
    FOpenThread: TEodWavOpenThread;
    FOverviewThread: TEodOverviewThread;
    FPeakOverviewThread: TEodPeakOverviewThread;
    FClosing: Boolean;

    FOnAnalysisProgress: TAnalysisProgressEvent;
    FOnAnalysisFinished: TAnalysisFinishedEvent;
    FOnOpenProgress: TEodWavProgressProc;
    FOnOpenFinished: TEodWavOpenFinishedProc;
    FOnOverviewProgress: TOverviewProgressEvent;
    FOnOverviewFinished: TOverviewFinishedEvent;
    FOnPeakOverviewProgress: TPeakOverviewProgressEvent;
    FOnPeakOverviewFinished: TPeakOverviewFinishedEvent;
    FOnCloseRequest: TNotifyEvent;

    function GetAnalysisRunning: Boolean;
    function GetOpenRunning: Boolean;
    function GetOverviewRunning: Boolean;
    function GetPeakOverviewRunning: Boolean;

    procedure AnalysisTerminated(Sender: TObject);
    procedure OpenTerminated(Sender: TObject);
    procedure OverviewTerminated(Sender: TObject);
    procedure PeakOverviewTerminated(Sender: TObject);
    procedure RequestCloseIfClosing;
  public
    { Запуск воркеров. Повторный запуск при уже активном воркере того же
      типа игнорируется. }
    procedure StartAnalysis(const AFile1, AFile2: string;
      const AConfig: TEodDetectorConfig; AMaxFrames: Int64);
    procedure StartOpenWav(const AFile1, AFile2: string);
    procedure StartOverview(const AFile1, AFile2: string);
    procedure StartPeakOverview(const AFileName: string; ASpreadBuckets: Boolean);

    procedure CancelAnalysis;
    procedure CancelOverview;
    procedure CancelPeakOverview;
    { Отменяет все воркеры и запрещает новые запуски. После вызова каждый
      завершившийся воркер дёргает OnCloseRequest, давая форме закрыться. }
    procedure CancelAll;

    function AnyRunning: Boolean;
    property Closing: Boolean read FClosing;

    property AnalysisRunning: Boolean read GetAnalysisRunning;
    property OpenRunning: Boolean read GetOpenRunning;
    property OverviewRunning: Boolean read GetOverviewRunning;
    property PeakOverviewRunning: Boolean read GetPeakOverviewRunning;

    property OnAnalysisProgress: TAnalysisProgressEvent
      read FOnAnalysisProgress write FOnAnalysisProgress;
    property OnAnalysisFinished: TAnalysisFinishedEvent
      read FOnAnalysisFinished write FOnAnalysisFinished;
    property OnOpenProgress: TEodWavProgressProc
      read FOnOpenProgress write FOnOpenProgress;
    property OnOpenFinished: TEodWavOpenFinishedProc
      read FOnOpenFinished write FOnOpenFinished;
    property OnOverviewProgress: TOverviewProgressEvent
      read FOnOverviewProgress write FOnOverviewProgress;
    property OnOverviewFinished: TOverviewFinishedEvent
      read FOnOverviewFinished write FOnOverviewFinished;
    property OnPeakOverviewProgress: TPeakOverviewProgressEvent
      read FOnPeakOverviewProgress write FOnPeakOverviewProgress;
    property OnPeakOverviewFinished: TPeakOverviewFinishedEvent
      read FOnPeakOverviewFinished write FOnPeakOverviewFinished;
    { Вызывается завершившимся воркером, если запрошено закрытие формы. }
    property OnCloseRequest: TNotifyEvent
      read FOnCloseRequest write FOnCloseRequest;
  end;

implementation

function TEodAnalysisController.GetAnalysisRunning: Boolean;
begin
  Result := Assigned(FAnalysis);
end;

function TEodAnalysisController.GetOpenRunning: Boolean;
begin
  Result := Assigned(FOpenThread);
end;

function TEodAnalysisController.GetOverviewRunning: Boolean;
begin
  Result := Assigned(FOverviewThread);
end;

function TEodAnalysisController.GetPeakOverviewRunning: Boolean;
begin
  Result := Assigned(FPeakOverviewThread);
end;

function TEodAnalysisController.AnyRunning: Boolean;
begin
  Result := Assigned(FAnalysis) or Assigned(FOpenThread) or
    Assigned(FOverviewThread) or Assigned(FPeakOverviewThread);
end;

procedure TEodAnalysisController.RequestCloseIfClosing;
begin
  if FClosing and Assigned(FOnCloseRequest) then
    FOnCloseRequest(Self);
end;

procedure TEodAnalysisController.AnalysisTerminated(Sender: TObject);
begin
  { Поток работает с FreeOnTerminate=True. OnTerminate нужен только чтобы
    сбросить нашу ссылку и, если запрошено, дать форме закрыться. }
  if FAnalysis = Sender then
    FAnalysis := nil;

  RequestCloseIfClosing;
end;

procedure TEodAnalysisController.OpenTerminated(Sender: TObject);
begin
  if FOpenThread = Sender then
    FOpenThread := nil;

  RequestCloseIfClosing;
end;

procedure TEodAnalysisController.OverviewTerminated(Sender: TObject);
begin
  if FOverviewThread = Sender then
    FOverviewThread := nil;

  RequestCloseIfClosing;
end;

procedure TEodAnalysisController.PeakOverviewTerminated(Sender: TObject);
begin
  if FPeakOverviewThread = Sender then
    FPeakOverviewThread := nil;

  RequestCloseIfClosing;
end;

procedure TEodAnalysisController.StartAnalysis(const AFile1, AFile2: string;
  const AConfig: TEodDetectorConfig; AMaxFrames: Int64);
begin
  if FClosing or Assigned(FAnalysis) then
    Exit;

  FAnalysis := TEodAnalysisThread.Create(AFile1, AFile2, AConfig, AMaxFrames);
  FAnalysis.OnProgress := FOnAnalysisProgress;
  FAnalysis.OnFinished := FOnAnalysisFinished;
  FAnalysis.OnTerminate := AnalysisTerminated;
  FAnalysis.Start;
end;

procedure TEodAnalysisController.StartOpenWav(const AFile1, AFile2: string);
begin
  if FClosing or Assigned(FOpenThread) then
    Exit;

  FOpenThread := TEodWavOpenThread.Create(AFile1, AFile2,
    FOnOpenProgress, FOnOpenFinished);
  FOpenThread.OnTerminate := OpenTerminated;
  FOpenThread.Start;
end;

procedure TEodAnalysisController.StartOverview(const AFile1, AFile2: string);
begin
  if FClosing then
    Exit;

  { Предыдущий обзор (если остался) отменяем — так же поступала форма. }
  if Assigned(FOverviewThread) then
    FOverviewThread.Cancel;

  FOverviewThread := TEodOverviewThread.Create(AFile1, AFile2);
  FOverviewThread.OnProgress := FOnOverviewProgress;
  FOverviewThread.OnFinished := FOnOverviewFinished;
  FOverviewThread.OnTerminate := OverviewTerminated;
  FOverviewThread.Start;
end;

procedure TEodAnalysisController.StartPeakOverview(const AFileName: string;
  ASpreadBuckets: Boolean);
begin
  if FClosing or (AFileName = '') then
    Exit;

  { Предыдущий расчёт (например, при смене режима бакетов) отменяем. }
  if Assigned(FPeakOverviewThread) then
    FPeakOverviewThread.Cancel;

  FPeakOverviewThread := TEodPeakOverviewThread.Create(AFileName, 2000);
  FPeakOverviewThread.SpreadBuckets := ASpreadBuckets;
  FPeakOverviewThread.OnProgress := FOnPeakOverviewProgress;
  FPeakOverviewThread.OnFinished := FOnPeakOverviewFinished;
  FPeakOverviewThread.OnTerminate := PeakOverviewTerminated;
  FPeakOverviewThread.Start;
end;

procedure TEodAnalysisController.CancelAnalysis;
begin
  if Assigned(FAnalysis) then
    FAnalysis.Cancel;
end;

procedure TEodAnalysisController.CancelOverview;
begin
  if Assigned(FOverviewThread) then
    FOverviewThread.Cancel;
end;

procedure TEodAnalysisController.CancelPeakOverview;
begin
  if Assigned(FPeakOverviewThread) then
    FPeakOverviewThread.Cancel;
end;

procedure TEodAnalysisController.CancelAll;
begin
  FClosing := True;
  CancelAnalysis;
  CancelOverview;
  CancelPeakOverview;

  if Assigned(FOpenThread) then
    FOpenThread.Cancel;
end;

end.
