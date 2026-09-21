unit GUI.ViewController;

{ Показ данных на основном графике: один пик, произвольный диапазон
  (WAV — сырой вид; .eodpk — сырой вид малого диапазона или огибающая
  большого), текущий пик, переходы Prev/Next. Вынесено из TMainForm.

  Класс не владеет тем, что показывает (график, обзор, список пиков):
  их создаёт форма и передаёт в конструктор. Сессия и детектор берутся
  из свойств Session и Detector — форма обновляет их при смене сессии
  и настроек.

  Наружу класс сообщает две вещи: изменился показанный диапазон
  (OnRangeChanged) и текст для строки состояния (OnStatus). }

interface

uses
  System.SysUtils, System.Math,
  Core.Types, Detection.Detector,
  GUI.Model, GUI.Plot.Signal, GUI.PeakList, GUI.OverviewController;

type
  TEodViewRangeEvent = procedure(AStart, AEnd: Int64) of object;
  TEodViewStatusEvent = procedure(const S: string) of object;

  TEodViewController = class
  private
    FPlot: TSignalPlot;
    FSession: TEodGuiSession;
    FDetector: TEodDetector;
    FOverview: TEodOverviewController;
    FPeakList: TEodPeakList;
    FIsPlaying: TFunc<Boolean>;
    FOnRangeChanged: TEodViewRangeEvent;
    FOnStatus: TEodViewStatusEvent;

    FPlotMode: TPlotMode;
    FCurrentPeak: Integer;   // индекс показанного пика, -1 — ещё не выбран
    FCurrentCount: Integer;  // число кадров в последнем показанном диапазоне

    procedure Status(const S: string);
    procedure RangeChanged(AStart, AEnd: Int64);
    function Playing: Boolean;
    procedure SetPlotMode(AValue: TPlotMode);
    procedure ShowRawPosition(AStartFrame, AEndFrame: Int64);
    procedure ShowPeakFileRange(AStartFrame, AEndFrame: Int64);
    procedure UpdateCurrentPeakForView(AStartFrame: Int64);
  public
    constructor Create(APlot: TSignalPlot; ASession: TEodGuiSession;
      ADetector: TEodDetector; AOverview: TEodOverviewController;
      APeakList: TEodPeakList; const AIsPlaying: TFunc<Boolean>;
      AOnRangeChanged: TEodViewRangeEvent; AOnStatus: TEodViewStatusEvent);

    { Показ пика по индексу (для WAV окно читается из записи). }
    procedure ShowPeak(Index: Integer);
    procedure NextPeak;
    procedure PrevPeak;

    { Показ произвольного диапазона; вид (WAV или EODPK) зависит от режима сессии. В режиме dmNone ничего не делает. }
    procedure ShowRange(AStart, AEnd: Int64);

    { Сброс состояния при открытии новой записи. }
    procedure Reset;

    property Session: TEodGuiSession read FSession write FSession;
    property Detector: TEodDetector read FDetector write FDetector;
    property PlotMode: TPlotMode read FPlotMode write SetPlotMode;
    property CurrentPeak: Integer read FCurrentPeak write FCurrentPeak;
    property CurrentCount: Integer read FCurrentCount;
  end;

implementation

constructor TEodViewController.Create(APlot: TSignalPlot;
  ASession: TEodGuiSession; ADetector: TEodDetector;
  AOverview: TEodOverviewController; APeakList: TEodPeakList;
  const AIsPlaying: TFunc<Boolean>;
  AOnRangeChanged: TEodViewRangeEvent; AOnStatus: TEodViewStatusEvent);
begin
  inherited Create;
  FPlot := APlot;
  FSession := ASession;
  FDetector := ADetector;
  FOverview := AOverview;
  FPeakList := APeakList;
  FIsPlaying := AIsPlaying;
  FOnRangeChanged := AOnRangeChanged;
  FOnStatus := AOnStatus;
  FPlotMode := pmRaw;
  Reset;
end;

procedure TEodViewController.Reset;
begin
  FCurrentPeak := -1;
  FCurrentCount := 201;
end;

{ Когда пользователь вручную двигает «курсор» (ползунок позиции, клик на
  обзоре, диапазон) при остановленном воспроизведении, текущий пик нужно
  подстроить под начало видимой области. Иначе повторный Play стартует с
  последнего ПОКАЗАННОГО пика (т.е. с места, где воспроизведение было
  остановлено), а не с того места, где стоит курсор. Во время PLAY не
  трогаем: пик ведёт сам плеер. }
procedure TEodViewController.UpdateCurrentPeakForView(AStartFrame: Int64);
var
  FirstIdx, LastIdx: Int64;
  AfterIdx, BeforeIdx: Integer;
  PA, PB: Int64;
begin
  if Playing then
    Exit;
  FCurrentPeak := -1;
  if FSession.PeakCount = 0 then
    Exit;

  { Первый пик с позицией >= AStartFrame; конец поиска - последний сэмпл. }
  AfterIdx := -1;
  if FSession.FindPeakRangeIndices(AStartFrame, FSession.TotalFrames - 1, 0,
    FirstIdx, LastIdx) then
    AfterIdx := Integer(FirstIdx);

  if AfterIdx < 0 then
  begin
    { От курсора и до конца пиков уже нет — берём последний пик. }
    FCurrentPeak := FSession.PeakCount - 1;
    Exit;
  end;

  { Берём ближайший к курсору пик из «следующего» и «предыдущего». }
  BeforeIdx := AfterIdx - 1;
  if BeforeIdx >= 0 then
  begin
    PA := FSession.GetPeakPosition(AfterIdx);
    PB := FSession.GetPeakPosition(BeforeIdx);
    if Abs(AStartFrame - PB) <= Abs(PA - AStartFrame) then
      FCurrentPeak := BeforeIdx
    else
      FCurrentPeak := AfterIdx;
  end
  else
    FCurrentPeak := AfterIdx;
end;

procedure TEodViewController.Status(const S: string);
begin
  if Assigned(FOnStatus) then
    FOnStatus(S);
end;

procedure TEodViewController.RangeChanged(AStart, AEnd: Int64);
begin
  if Assigned(FOnRangeChanged) then
    FOnRangeChanged(AStart, AEnd);
end;

function TEodViewController.Playing: Boolean;
begin
  Result := Assigned(FIsPlaying) and FIsPlaying();
end;

procedure TEodViewController.SetPlotMode(AValue: TPlotMode);
begin
  FPlotMode := AValue;
  FPlot.SetMode(FPlotMode);
end;

procedure TEodViewController.NextPeak;
begin
  if FSession.PeakCount = 0 then
    Exit;

  if FCurrentPeak < FSession.PeakCount - 1 then
    Inc(FCurrentPeak)
  else
    FCurrentPeak := FSession.PeakCount - 1;

  ShowPeak(FCurrentPeak);
end;

procedure TEodViewController.PrevPeak;
begin
  if FSession.PeakCount = 0 then
    Exit;

  if FCurrentPeak > 0 then
    Dec(FCurrentPeak)
  else
    FCurrentPeak := 0;

  ShowPeak(FCurrentPeak);
end;

procedure TEodViewController.ShowRange(AStart, AEnd: Int64);
begin
  case FSession.Mode of
    dmWav: ShowRawPosition(AStart, AEnd);
    dmPeakFile: ShowPeakFileRange(AStart, AEnd);
  end;
end;

procedure TEodViewController.ShowPeak(Index: Integer);
var
  Peak: TPeak;
  StartFrame, EndFrame: Int64;
  Data: TAudioChunk;
  Std: TFloatArray;
  Fir: TFloatArray;
  Range: Integer;
begin
  if (Index < 0) or (Index >= FSession.PeakCount) then
    Exit;

  if FSession.Mode = dmPeakFile then
    Data := FSession.ReadPeak(Index, Peak, StartFrame)
  else
  begin
    if not FSession.GetPeak(Index, Peak) then
      Exit;
    Range := 30;
    StartFrame := Peak.Position - Range;
    Data := FSession.ReadSegment(StartFrame, Range * 2 + 1, True);
  end;

  EndFrame := StartFrame + Length(Data) - 1;
  FCurrentCount := Length(Data);
  FCurrentPeak := Index;

  RangeChanged(StartFrame, EndFrame);

  Std := FSession.CalculateStd(Data);
  Fir := FDetector.ApplyFir15(Std);

  FPlot.SetChannels(Data, StartFrame, FSession.SampleRate, Peak.Position,
    Format('Peak #%d  sample %d', [Index + 1, Peak.Position]));

  FPlot.SetStd(Std, StartFrame, FSession.SampleRate, Peak.Position,
    'STD around peak');

  FPlot.SetFir(Fir, StartFrame, FSession.SampleRate, Peak.Position,
    'FIR15 around peak');

  FPlot.SetMode(FPlotMode);
  FPlot.SetViewRange(StartFrame, EndFrame);

  { Красный прямоугольник обзора ставим по показанному пику. SetViewRange
    графика не вызывает OnViewChanged, поэтому обзор обновляем явно. }
  FOverview.SetViewRange(StartFrame, EndFrame);

  Status(Format('Peak %d/%d: sample %d, time %.6f s, prominence %.6f',
    [Index + 1, FSession.PeakCount, Peak.Position,
    Peak.Position / FSession.SampleRate, Peak.Prominence]));

  { Во время воспроизведения список пиков не перестраиваем: подсветка прыгала
    бы на каждом пике. После остановки плеера форма синхронизирует список один
    раз. }
  if not Playing then
    FPeakList.FillAroundFrame(Peak.Position);
end;

procedure TEodViewController.ShowRawPosition(AStartFrame, AEndFrame: Int64);
var
  StartFrame, EndFrame: Int64;
  Data: TAudioChunk;
  Std: TFloatArray;
  Fir: TFloatArray;
  PeakPositions: TArray<Int64>;
  FirstIdx, LastIdx: Int64;
  I, N: Integer;
  CountText: string;
begin
  if FSession.Mode <> dmWav then
    Exit;

  if FSession.TotalFrames <= 0 then
    Exit;

  StartFrame := EnsureRange(AStartFrame, Int64(0), FSession.TotalFrames - 1);
  EndFrame := EnsureRange(AEndFrame, StartFrame, FSession.TotalFrames - 1);

  Data := FSession.ReadSegment(StartFrame, EndFrame - StartFrame + 1, True);

  FCurrentCount := Length(Data);

  Std := FSession.CalculateStd(Data);
  Fir := FDetector.ApplyFir15(Std);

  FPlot.SetChannels(Data, StartFrame, FSession.SampleRate, -1,
    Format('Samples %d .. %d', [StartFrame, EndFrame]));

  FPlot.SetStd(Std, StartFrame, FSession.SampleRate, -1, 'STD');

  FPlot.SetFir(Fir, StartFrame, FSession.SampleRate, -1, 'FIR15');

  { Пики берём только из видимого диапазона, а не проходом по всему списку: иначе каждый шаг зума или панорамы читал бы все пики. }
  N := 0;
  SetLength(PeakPositions, 0);
  if FSession.FindPeakRangeIndices(StartFrame, EndFrame, 0, FirstIdx, LastIdx) then
  begin
    N := Integer(LastIdx - FirstIdx + 1);
    SetLength(PeakPositions, N);
    for I := 0 to N - 1 do
      PeakPositions[I] := FSession.GetPeakPosition(Integer(FirstIdx) + I);
  end;

  FPlot.SetPeakPositions(PeakPositions);
  FPlot.SetSelectedPosition(StartFrame);
  FPlot.SetViewRange(StartFrame, EndFrame);
  FPlot.SetHistogramRange(StartFrame, EndFrame);

  RangeChanged(StartFrame, EndFrame);
  UpdateCurrentPeakForView(StartFrame);

  if N <= 1000 then
    CountText := Format('; %d peaks in selection', [N])
  else
    CountText := Format('; >1000 peaks in selection (%d, not listed)', [N]);

  Status(Format('Samples %d .. %d  (%d samples, %.6f s .. %.6f s)%s',
    [StartFrame, EndFrame, Length(Data), StartFrame / FSession.SampleRate,
    EndFrame / FSession.SampleRate, CountText]));

  FPlot.SetMode(FPlotMode);
end;

procedure TEodViewController.ShowPeakFileRange(AStartFrame, AEndFrame: Int64);
const
  RawLimit = 10000;
  MaxEnvelopePoints = 4096;
var
  StartFrame, EndFrame: Int64;
  Envelope: TWaveEnvelope;
  Data: TAudioChunk;
  Std: TFloatArray;
  Fir: TFloatArray;
begin
  if FSession.Mode <> dmPeakFile then
    Exit;

  if FSession.TotalFrames <= 0 then
    Exit;

  StartFrame := EnsureRange(AStartFrame, Int64(0), FSession.TotalFrames - 1);
  EndFrame := EnsureRange(AEndFrame, StartFrame, FSession.TotalFrames - 1);

  UpdateCurrentPeakForView(StartFrame);

  { Малый диапазон рисуем точно: сырой сигнал из окон пиков. Порог RawLimit — политика GUI, а не формата. }
  if FSession.TryReadPeakFileRawRange(StartFrame, EndFrame,
    RawLimit, RawLimit, Data) then
  begin
    FPlot.SetChannels(Data, StartFrame, FSession.SampleRate, -1,
      Format('Samples %d .. %d', [StartFrame, EndFrame]));

    Std := FSession.CalculateStd(Data);
    Fir := FDetector.ApplyFir15(Std);

    FPlot.SetStd(Std, StartFrame, FSession.SampleRate, -1, 'STD');
    FPlot.SetFir(Fir, StartFrame, FSession.SampleRate, -1, 'FIR15');

    FPlot.SetSelectedPosition(StartFrame);
    FPlot.SetViewRange(StartFrame, EndFrame);
    FPlot.SetHistogramRange(StartFrame, EndFrame);

    FPlot.SetMode(FPlotMode);
    Exit;
  end;

  { Большой диапазон рисуем огибающей: полный TAudioChunk для него не создаётся. }
  if not FSession.ReadPeakEnvelope(StartFrame, EndFrame, MaxEnvelopePoints,
    Envelope) then
  begin
    FPlot.ClearData;
    Exit;
  end;

  FPlot.SetEnvelope(Envelope, StartFrame, EndFrame, FSession.SampleRate,
    Format('EODPK envelope %d .. %d', [StartFrame, EndFrame]));

  FPlot.SetSelectedPosition(StartFrame);
  FPlot.SetViewRange(StartFrame, EndFrame);
  FPlot.SetHistogramRange(StartFrame, EndFrame);

  { STD и FIR считаются только по восстановленному сырому сигналу, поэтому для огибающей их очищаем. }
  FPlot.SetStd(nil, StartFrame, FSession.SampleRate, -1, 'STD');
  FPlot.SetFir(nil, StartFrame, FSession.SampleRate, -1, 'FIR15');

  FPlot.SetMode(FPlotMode);

  Status(Format(
    'EODPK envelope %d .. %d  (%d samples, %d display buckets)',
    [StartFrame, EndFrame, EndFrame - StartFrame + 1, Length(Envelope)]));
end;

end.
