unit GUI.OverviewController;

interface

uses
  System.Classes, System.SysUtils, System.Math,
  FMX.Objects,
  Core.Types,
  GUI.Model,
  GUI.Plot.Base,
  GUI.Plot.Overview,
  Threads.Overview,
  Threads.PeakOverview;

type
  TOverviewStatusEvent = procedure(const S: string) of object;

  { Контроллер обзорного графика. Владеет TOverviewPlot, массивами огибающей
    (общей и поканальной), а также воркерами построения обзора WAV и обзора
    EODPK (свои TEodOverviewThread/TEodPeakOverviewThread — не через
    GUI.Analysis, который после этого ведает только анализом и открытием).
    Ничего не знает о форме: статус отдаётся колбэком OnStatus, клики и
    выделения диапазона на обзоре пересылаются событиями OnClick/
    OnRangeSelected (навигацией по основному графику занимается форма).

    Перед уничтожением класса воркеры должны быть завершены: форма не
    закрывается, пока работает хотя бы один (см. FormCloseQuery). Имена
    приватных полей напоминают исторически сложившиеся имена полей формы. }
  TEodOverviewController = class
  private
    FSession: TEodGuiSession;
    FViewWidthFunc: TFunc<Int64>;
    FOverview: TOverviewPlot;

    FViewStart, FViewEnd: Int64;

    FOverviewThread: TEodOverviewThread;
    FPeakOverviewThread: TEodPeakOverviewThread;
    FClosing: Boolean;

    FOverviewMin: TFloatArray;
    FOverviewMax: TFloatArray;
    FOverviewChMin: TChannelEnvelopes;
    FOverviewChMax: TChannelEnvelopes;
    FChannelColors: Boolean;
    FLookIndex: Integer;

    FOnStatus: TOverviewStatusEvent;
    FOnClick: TOverviewClickEvent;
    FOnRangeSelected: TOverviewRangeSelectedEvent;
    FOnCloseRequest: TNotifyEvent;

    procedure Status(const S: string);
    procedure SetChannelColors(AValue: Boolean);
    function GetOverviewRunning: Boolean;
    function GetPeakOverviewRunning: Boolean;
    function GetAnyRunning: Boolean;
    function GetHasEnvelope: Boolean;

    procedure OverviewTerminated(Sender: TObject);
    procedure PeakOverviewTerminated(Sender: TObject);
    procedure RequestCloseIfClosing;

    procedure PlotClick(Sender: TObject; Frame: Int64);
    procedure PlotRangeSelected(Sender: TObject; AStart, AEnd: Int64);

    procedure OverviewProgress(Sender: TObject; Processed, Total: Int64);
    procedure OverviewFinished(Sender: TObject;
      const OverviewMin, OverviewMax: TFloatArray;
      const ChannelMin, ChannelMax: TChannelEnvelopes;
      TotalFrames: Int64; Canceled: Boolean;
      const ErrorText: string);
      procedure PeakOverviewFinished(Sender: TObject;
      const OverviewMin, OverviewMax: TFloatArray;
      const ChannelMin, ChannelMax: TChannelEnvelopes;
      TotalFrames: Int64; Canceled: Boolean;
      const ErrorText: string);


    { Общая часть обработчиков завершения обоих обзоров. }
    function OverviewOutcomeHandled(Canceled: Boolean;
      const ErrorText, CancelText, ErrorPrefix: string): Boolean;
    procedure StoreAndShowOverview(
      const OverviewMin, OverviewMax: TFloatArray;
      const ChannelMin, ChannelMax: TChannelEnvelopes;
      TotalFrames: Int64);

    procedure StartWavOverview;
    procedure StartPeakOverviewThread(const AFileName: string;
      ASpreadBuckets: Boolean);
    procedure ApplyOverviewLook;
  public
    constructor Create(ASession: TEodGuiSession;
      APaintBox: TPaintBox;
      const AViewWidthFunc: TFunc<Int64>;
      AOnStatus: TOverviewStatusEvent;
      AOnClick: TOverviewClickEvent;
      AOnRangeSelected: TOverviewRangeSelectedEvent;
      AOnCloseRequest: TNotifyEvent);
    destructor Destroy; override;

    procedure StartOverview;
    procedure StartPeakOverview(const AFileName: string; ASpreadBuckets: Boolean);
    procedure CancelAll;
    procedure SetViewRange(AViewStart, AViewEnd: Int64);
    procedure SetOverviewLook(ALookIndex: Integer);

    property Session: TEodGuiSession read FSession write FSession;
    property Closing: Boolean read FClosing;
    property OverviewRunning: Boolean read GetOverviewRunning;
    property PeakOverviewRunning: Boolean read GetPeakOverviewRunning;
    property AnyRunning: Boolean read GetAnyRunning;
    property HasEnvelope: Boolean read GetHasEnvelope;

    property EnvelopeMin: TFloatArray read FOverviewMin;
    property EnvelopeMax: TFloatArray read FOverviewMax;
    property ChannelMin: TChannelEnvelopes read FOverviewChMin;
    property ChannelMax: TChannelEnvelopes read FOverviewChMax;
    property ChannelColors: Boolean read FChannelColors write SetChannelColors;
  end;

implementation

procedure TEodOverviewController.Status(const S: string);
begin
  if Assigned(FOnStatus) then
    FOnStatus(S);
end;

procedure TEodOverviewController.SetChannelColors(AValue: Boolean);
begin
  FChannelColors := AValue;

  if Assigned(FOverview) then
    FOverview.ChannelColors := AValue;
end;

function TEodOverviewController.GetOverviewRunning: Boolean;
begin
  Result := Assigned(FOverviewThread);
end;

function TEodOverviewController.GetPeakOverviewRunning: Boolean;
begin
  Result := Assigned(FPeakOverviewThread);
end;

function TEodOverviewController.GetAnyRunning: Boolean;
begin
  Result := Assigned(FOverviewThread) or Assigned(FPeakOverviewThread);
end;

function TEodOverviewController.GetHasEnvelope: Boolean;
begin
  Result := Length(FOverviewMin) > 0;
end;

constructor TEodOverviewController.Create(ASession: TEodGuiSession;
  APaintBox: TPaintBox;
  const AViewWidthFunc: TFunc<Int64>;
  AOnStatus: TOverviewStatusEvent;
  AOnClick: TOverviewClickEvent;
  AOnRangeSelected: TOverviewRangeSelectedEvent;
  AOnCloseRequest: TNotifyEvent);
begin
  inherited Create;
  FSession := ASession;
  FViewWidthFunc := AViewWidthFunc;
  FOnStatus := AOnStatus;
  FOnClick := AOnClick;
  FOnRangeSelected := AOnRangeSelected;
  FOnCloseRequest := AOnCloseRequest;
  FClosing := False;
  FChannelColors := False;
  FLookIndex := 0;

  FOverview := TOverviewPlot.Create(APaintBox);
  FOverview.OnClick := PlotClick;
  FOverview.OnRangeSelected := PlotRangeSelected;
  FOverview.ChannelColors := FChannelColors;
end;

destructor TEodOverviewController.Destroy;
begin
  { Обычно к этому моменту воркеры уже завершены: FormCloseQuery не даёт
    дойти до уничтожения, пока работает хотя бы один. }
  FClosing := True;
  if Assigned(FOverviewThread) then
    FOverviewThread.Cancel;
  if Assigned(FPeakOverviewThread) then
    FPeakOverviewThread.Cancel;

  FOverview.Free;
  FOverview := nil;
  inherited;
end;

procedure TEodOverviewController.RequestCloseIfClosing;
begin
  if FClosing and Assigned(FOnCloseRequest) then
    FOnCloseRequest(Self);
end;

procedure TEodOverviewController.OverviewTerminated(Sender: TObject);
begin
  if FOverviewThread = Sender then
    FOverviewThread := nil;

  RequestCloseIfClosing;
end;

procedure TEodOverviewController.PeakOverviewTerminated(Sender: TObject);
begin
  if FPeakOverviewThread = Sender then
    FPeakOverviewThread := nil;

  RequestCloseIfClosing;
end;

procedure TEodOverviewController.PlotClick(Sender: TObject; Frame: Int64);
begin
  if Assigned(FOnClick) then
    FOnClick(Self, Frame);
end;

procedure TEodOverviewController.PlotRangeSelected(Sender: TObject;
  AStart, AEnd: Int64);
begin
  if Assigned(FOnRangeSelected) then
    FOnRangeSelected(Self, AStart, AEnd);
end;

procedure TEodOverviewController.StartOverview;
begin
  if FClosing then
    Exit;
  if not Assigned(FSession) then
    Exit;
  if FSession.Mode <> dmWav then
    Exit;

  StartWavOverview;
end;

procedure TEodOverviewController.StartPeakOverview(const AFileName: string;
  ASpreadBuckets: Boolean);
begin
  if FClosing then
    Exit;

  if AFileName = '' then
    Exit;

  { Обзор WAV от предыдущей сессии больше не нужен: отменяем и запускаем
    обзор EODPK. Предыдущий расчёт EODPK (смена режима бакетов) отменяет
    сам StartPeakOverviewThread. }
  if Assigned(FOverviewThread) then
    FOverviewThread.Cancel;

  StartPeakOverviewThread(AFileName, ASpreadBuckets);
end;

procedure TEodOverviewController.StartWavOverview;
begin
  FOverview.Clear;

  Status('Building overview in background...');

  { Предыдущий обзор (если остался) отменяем — так же поступала форма. }
  if Assigned(FOverviewThread) then
    FOverviewThread.Cancel;

  { Обзор EODPK от предыдущей сессии тоже больше не нужен. }
  if Assigned(FPeakOverviewThread) then
    FPeakOverviewThread.Cancel;

  FOverviewThread := TEodOverviewThread.Create(FSession.File1, FSession.File2);
  FOverviewThread.OnProgress := OverviewProgress;
  FOverviewThread.OnFinished := OverviewFinished;
  FOverviewThread.OnTerminate := OverviewTerminated;
  FOverviewThread.Start;
end;

procedure TEodOverviewController.StartPeakOverviewThread(const AFileName: string;
  ASpreadBuckets: Boolean);
var
  Ch: Integer;
begin
  FOverviewMin := nil;
  FOverviewMax := nil;

  for Ch := 0 to 3 do
  begin
    FOverviewChMin[Ch] := nil;
    FOverviewChMax[Ch] := nil;
  end;

  FOverview.Clear;

  Status('Building EODPK overview...');

  { Предыдущий расчёт (например, при смене режима бакетов) отменяем. }
  if Assigned(FPeakOverviewThread) then
    FPeakOverviewThread.Cancel;

  FPeakOverviewThread := TEodPeakOverviewThread.Create(AFileName, 2000);
  FPeakOverviewThread.SpreadBuckets := ASpreadBuckets;
    { Прогресс у обоих обзоров одинаковый. }
  FPeakOverviewThread.OnProgress := OverviewProgress;
  FPeakOverviewThread.OnFinished := PeakOverviewFinished;
  FPeakOverviewThread.OnTerminate := PeakOverviewTerminated;
  FPeakOverviewThread.Start;
end;

procedure TEodOverviewController.OverviewProgress(Sender: TObject;
  Processed, Total: Int64);
var
  Percent: Integer;
begin
  if FClosing then
    Exit;

  if Total > 0 then
    Percent := Round(Processed * 100.0 / Total)
  else
    Percent := 0;

  if Percent < 0 then
    Percent := 0
  else if Percent > 100 then
    Percent := 100;

  Status(Format('Building overview: %d%%', [Percent]));
end;

{ Общая часть обработчиков завершения: закрытие формы, отмена, ошибка.
  Возвращает True, если результат применять не нужно — статус отмены или
  ошибки уже показан (либо форма закрывается и статус не нужен). Тексты
  статусов у обзора WAV и обзора EODPK разные, поэтому приходят параметрами. }
function TEodOverviewController.OverviewOutcomeHandled(Canceled: Boolean;
  const ErrorText, CancelText, ErrorPrefix: string): Boolean;
begin
  Result := True;

  if FClosing then
    Exit;

  if Canceled then
  begin
    Status(CancelText);
    Exit;
  end;

  if ErrorText <> '' then
  begin
    Status(ErrorPrefix + ErrorText);
    Exit;
  end;

  Result := False;
end;

{ Сохраняет готовые огибающие и отдаёт их графику. Вид (красный
  прямоугольник) здесь не трогаем: у обзора WAV и обзора EODPK он
  выставляется по-разному, см. обработчики завершения. }
procedure TEodOverviewController.StoreAndShowOverview(
  const OverviewMin, OverviewMax: TFloatArray;
  const ChannelMin, ChannelMax: TChannelEnvelopes;
  TotalFrames: Int64);
begin
  FOverviewMin := Copy(OverviewMin);
  FOverviewMax := Copy(OverviewMax);
  FOverviewChMin := ChannelMin;
  FOverviewChMax := ChannelMax;

  { Для WAV эта проверка всегда истинна (поток сам бросает ошибку при
    TotalFrames <= 0 и строит минимум один бин); для EODPK она защищает
    от пустого результата. }
  if (TotalFrames <= 0) or (Length(FOverviewMin) = 0) then
    Exit;

  FOverview.SetData(FOverviewMin, FOverviewMax, 0, TotalFrames - 1);
  FOverview.SetChannelData(FOverviewChMin, FOverviewChMax, 0,
    TotalFrames - 1);
end;

procedure TEodOverviewController.OverviewFinished(Sender: TObject;
  const OverviewMin, OverviewMax: TFloatArray;
  const ChannelMin, ChannelMax: TChannelEnvelopes;
  TotalFrames: Int64; Canceled: Boolean;
  const ErrorText: string);
var
  InitialWidth: Int64;
begin
  if OverviewOutcomeHandled(Canceled, ErrorText,
    'Overview building cancelled.', 'Overview error: ') then
    Exit;

  StoreAndShowOverview(OverviewMin, OverviewMax, ChannelMin, ChannelMax,
    TotalFrames);

  { Особенность обзора WAV: вида ещё нет, поэтому начальный красный
    прямоугольник — от нуля шириной текущего вида основного графика. }
  InitialWidth := 0;
  if Assigned(FViewWidthFunc) then
    InitialWidth := FViewWidthFunc();

  FOverview.SetViewRange(
    0,
    Min(TotalFrames - 1, InitialWidth));

  ApplyOverviewLook;

  if Assigned(FSession) then
    Status(Format(
      'WAV: %.3f sec, %d Hz, %d frames',
      [FSession.TotalFrames / FSession.SampleRate,
       FSession.SampleRate,
       FSession.TotalFrames]));
end;

procedure TEodOverviewController.PeakOverviewFinished(Sender: TObject;
  const OverviewMin, OverviewMax: TFloatArray;
  const ChannelMin, ChannelMax: TChannelEnvelopes;
  TotalFrames: Int64; Canceled: Boolean;
  const ErrorText: string);
begin
  if OverviewOutcomeHandled(Canceled, ErrorText,
    'EODPK overview cancelled.', 'EODPK overview error: ') then
    Exit;

  StoreAndShowOverview(OverviewMin, OverviewMax, ChannelMin, ChannelMax,
    TotalFrames);

  { Особенность обзора EODPK: пока строился обзор, форма уже выставила вид
    (первый пик, клик, диапазон) — восстанавливаем запомненный. }
  if (TotalFrames > 0) and (Length(FOverviewMin) > 0) then
    FOverview.SetViewRange(FViewStart, FViewEnd);

  ApplyOverviewLook;

  { Весь файл показываем только как запасной вариант, если вид никто не
    задавал. Раньше этот вызов был безусловным и после построения обзора
    затирал вид, выставленный формой. }
  if (TotalFrames > 0) and (Length(FOverviewMin) > 0) and
     (FViewEnd <= FViewStart) then
    SetViewRange(0, TotalFrames - 1);

  Status(Format('EODPK overview ready: %d frames', [TotalFrames]));
end;

procedure TEodOverviewController.SetViewRange(AViewStart, AViewEnd: Int64);
begin
  FViewStart := AViewStart;
  FViewEnd := AViewEnd;

  if not Assigned(FOverview) then
    Exit;

  if not Assigned(FSession) then
    Exit;

  if FSession.Mode = dmNone then
    Exit;

  FOverview.SetViewRange(AViewStart, AViewEnd);
end;

procedure TEodOverviewController.SetOverviewLook(ALookIndex: Integer);
begin
  FLookIndex := ALookIndex;
  ApplyOverviewLook;
end;

procedure TEodOverviewController.ApplyOverviewLook;
begin
  if not Assigned(FOverview) then
    Exit;

  { Обзор ещё не построен — запоминаем только режим цвета. }
  if not Assigned(FSession) then
    Exit;

  if (Length(FOverviewChMin[0]) = 0) or (FSession.TotalFrames <= 0) then
  begin
    SetChannelColors(FLookIndex = 0);
    Exit;
  end;

  if FLookIndex = 0 then
    SetChannelColors(True)
  else
  begin
    { Общая огибающая выводится из поканальной — пересчёт обзора не нужен. }
    BuildGeneralEnvelope(FOverviewChMin, FOverviewChMax,
      FLookIndex = 1, FOverviewMin, FOverviewMax);
    FOverview.SetData(FOverviewMin, FOverviewMax, 0,
      FSession.TotalFrames - 1);
    SetChannelColors(False);
  end;
end;

procedure TEodOverviewController.CancelAll;
begin
  FClosing := True;
  if Assigned(FOverviewThread) then
    FOverviewThread.Cancel;
  if Assigned(FPeakOverviewThread) then
    FPeakOverviewThread.Cancel;
end;

end.