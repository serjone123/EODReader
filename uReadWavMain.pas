unit uReadWavMain;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Diagnostics,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.StdCtrls, FMX.Objects, FMX.Edit,
  FMX.ListBox, FMX.Layouts, FMX.Dialogs, FMX.SpinBox
, System.Classes, FMX.Controls.Presentation
, Threads.Analysis
, Core.Types
, Detection.Detector
, IO.PeakStore
, GUI.Model
, GUI.Plot
, Threads.WavOpen
, Core.ConfigStore, GUI.SettingsForm
, GUI.FileNaming
 ;

type
  TMainForm = class(TForm)
    Layout1: TLayout;
    FOpenWavButton: TButton;
    FOpenPeakButton: TButton;
    FAnalyzeButton: TButton;
    FSaveButton: TButton;
    FPrevButton: TButton;
    FNextButton: TButton;
    FOpenFolderButton: TButton;
    FApplyButton: TButton;
    FPositionBar: TTrackBar;
    FPeakList: TListBox;
    edStartSample: TEdit;
    edRange: TEdit;
    FStatus: TLabel;
    FModeBox: TComboBox;
    PaintBox: TPaintBox;
    LayIMG: TLayout;
    LayNavi: TLayout;
    edEndSample: TEdit;
    OverviewPaintBox: TPaintBox;
    FSettingsButton: TButton;
    FPlayButton: TButton;
    FPlaySpeedBox: TComboBox;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FAnalyzeButtonClick(Sender: TObject);
    procedure FApplyButtonClick(Sender: TObject);
    procedure FModeBoxChange(Sender: TObject);
    procedure FNextButtonClick(Sender: TObject);
    procedure FOpenPeakButtonClick(Sender: TObject);
    procedure FOpenWavButtonClick(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure FPeakListClick(Sender: TObject);
    procedure FPeakListMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Single);
    procedure FPositionBarChange(Sender: TObject);
    procedure FPrevButtonClick(Sender: TObject);
    procedure FSaveButtonClick(Sender: TObject);
    procedure FOpenFolderButtonClick(Sender: TObject);
    procedure edStartSampleMouseWheel(Sender: TObject; Shift: TShiftState;
      WheelDelta: Integer; var Handled: Boolean);
    procedure edStartSampleChange(Sender: TObject);
    procedure edEndSampleChange(Sender: TObject);
    procedure FSettingsButtonClick(Sender: TObject);
    procedure FPlayButtonClick(Sender: TObject);
    procedure PlaySpeedBoxChange(Sender: TObject);
  private
    FSession: TEodGuiSession;
    FDetector: TEodDetector;
    FConfig: TEodDetectorConfig;
    FPlot: TSignalPlot;
    FUpdating: Boolean;
    FCurrentPeak: Integer;
    FCurrentStart: Int64;
    FCurrentCount: Integer;
    FAnalysis: TEodAnalysisThread;
    FOpenThread: TEodWavOpenThread;
    FClosing: Boolean;

    FOverview: TOverviewPlot;

    FOverviewMin: TFloatArray;
    FOverviewMax: TFloatArray;

    { Поканальные огибающие обзорного графика (индекс 0..3 — канал 1..4)
      для режима OverviewChannelColors. }
    FOverviewChMin: TChannelEnvelopes;
    FOverviewChMax: TChannelEnvelopes;
    FOverviewChannelColors: Boolean;

    FPeakListFirstIndex: Integer;

    FPeakListRealCount: Integer;

    FWheelAccumulator: Integer;

    FLastDir: string;

    { ------------------------- Воспроизведение ------------------------- }
    { Плеер "проигрывает" запись как последовательность пиков: таймер
      ведёт виртуальное время (сэмплы), а в момент, когда наступает время
      очередного пика, этот пик отображается на графике.
      FPlayButton/FPlaySpeedBox и их обработчики — published (см. выше),
      т.к. они связаны с компонентами из uReadWavMain.fmx. }
    FPlayTimer: TTimer;
    FPlayActive: Boolean;        // идёт воспроизведение
    FPlayIndex: Integer;         // индекс следующего пика к показу
    FPlayStartPos: Int64;        // виртуальное "сейчас" в сэмплах на старте
    FPlayClock: TStopwatch;      // реальное время с момента старта
    FPlaySpeed: Double;          // множитель скорости (сэмплы/сек умножаются)

    procedure PlayTimerTick(Sender: TObject);
    procedure StartPlayback;
    procedure StopPlayback(Finished: Boolean);
    procedure ApplyPlaybackSpeed;

    procedure OverviewClick(Sender: TObject; Frame: Int64);
    procedure OverviewRangeSelected(Sender: TObject; AStart, AEnd: Int64);

    procedure BuildOverview;

    procedure UpdateOverviewView(ViewStart, ViewEnd: Int64);

    procedure SetOverviewChannelColors(AValue: Boolean);

    procedure FillPeakListAroundFrame(AFrame: Int64);
    procedure UpdateStatus(const S: string);
    procedure UpdateCaption;
    procedure ShowPeak(Index: Integer);
    procedure ShowRawPosition(AStartFrame, AEndFrame: Int64);
    procedure ShowPeakFileRange(AStartFrame, AEndFrame: Int64);
    procedure ShowCurrentRange;
    function CurrentFrame: Int64;
    function ReadInt64Edit(AEdit: TEdit; const ADefault: Int64): Int64;
    procedure SetRangeEdits(AStart, AEnd: Int64);
    procedure UpdateRangeDisplay;
    procedure PopulatePeakListRange(const Peaks: TPeakArray; FirstIndex: Int64;
      Total: Int64);
    procedure FillPeakList;
    procedure StartAnalysis(MaxFrames: Int64);
    procedure AnalysisProgress(Sender: TObject; Processed, Total: Int64);
    procedure AnalysisFinished(Sender: TObject; const Peaks: TPeakArray;
      Canceled: Boolean; const ErrorText: string);
    procedure AnalysisThreadTerminated(Sender: TObject);
    procedure OpenProgress(Sender: TObject; Stage: Integer; const Text: string);
    procedure OpenFinished(Sender: TObject; Session: TEodGuiSession;
      Canceled: Boolean; const ErrorText: string);
    procedure OpenThreadTerminated(Sender: TObject);
    procedure SetAnalysisUiState(Analyzing: Boolean);
    procedure UpdatePlotMode;
    procedure PlotViewChanged(Sender: TObject; ViewStart, ViewEnd: Int64);
    // function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; var Handled: Boolean): Boolean; override;
  public
    { Обзорный график в цветах каналов 1..4 (как у основного графика).
      Поканальные огибающие строит BuildOverview, поэтому переключение
      не перечитывает файл. }
    property OverviewChannelColors: Boolean
      read FOverviewChannelColors write SetOverviewChannelColors;
  end;

var
  MainForm: TMainForm;

implementation

uses
  System.Math
  {$IFDEF MSWINDOWS}
  , Winapi.Windows, Winapi.ShellAPI
  {$ENDIF};

{$R *.fmx}

procedure TMainForm.FormCreate(Sender: TObject);
begin
  Position := TFormPosition.ScreenCenter;
  UpdateCaption;

  if not LoadDetectorConfig(GetDefaultConfigFileName, FConfig) then
    FConfig := DefaultEodDetectorConfig;
  FSession := TEodGuiSession.Create;
  FDetector := TEodDetector.Create(FConfig);

  FCurrentPeak := -1;
  FAnalysis := nil;
  FOpenThread := nil;
  FClosing := False;

  FModeBox.Items.Clear;
  FModeBox.Items.Add('RAW - 4 channels');
  FModeBox.Items.Add('STD');
  FModeBox.Items.Add('FIR15');
  FModeBox.Items.Add('RAW + FIR15');
  FModeBox.Items.Add('RAW channels separate');
  FModeBox.Items.Add('IPI histogram');

  FModeBox.ItemIndex := 0;

  FPlot := TSignalPlot.Create(PaintBox);
  FPlot.OnViewChanged := PlotViewChanged;

  FOverview := TOverviewPlot.Create(OverviewPaintBox);
  FOverview.OnClick := OverviewClick;
  FOverview.OnRangeSelected := OverviewRangeSelected;
  FOverview.ChannelColors := FOverviewChannelColors;

  { edRange is a derived/read-only indicator: End - Start.
    Wired in code (not the .dfm) so this doesn't depend on the form
    designer having these OnChange handlers assigned already. }
  edRange.ReadOnly := True;
  edStartSample.OnChange := edStartSampleChange;
  edEndSample.OnChange := edEndSampleChange;

  FPeakListFirstIndex := 0;
  FPeakListRealCount := 0;
  FWheelAccumulator := 0;

  { Код позиционного ползунка использует Value/1000, поэтому Max обязан
    быть 1000 (у FMX TTrackBar по умолчанию Max=10 — ползунок бы работал
    только в пределах первого процента файла). }
  FPositionBar.Max := 1000;

  { --------------------- Воспроизведение --------------------- }
  FPlaySpeedBox.Items.Clear;
  FPlaySpeedBox.Items.Add('0.1x');
  FPlaySpeedBox.Items.Add('0.25x');
  FPlaySpeedBox.Items.Add('0.5x');
  FPlaySpeedBox.Items.Add('1x');
  FPlaySpeedBox.Items.Add('2x');
  FPlaySpeedBox.Items.Add('5x');
  FPlaySpeedBox.Items.Add('10x');
  FPlaySpeedBox.ItemIndex := 3;
  FPlaySpeedBox.OnChange := PlaySpeedBoxChange;
  ApplyPlaybackSpeed;

  FPlayTimer := TTimer.Create(Self);
  FPlayTimer.Interval := 30;
  FPlayTimer.OnTimer := PlayTimerTick;
  FPlayTimer.Enabled := False;

  FPlayActive := False;
  FPlayIndex := 0;
  FPlayStartPos := 0;
  FPlaySpeed := 1.0;

  FStatus.Text := '';

  OverviewChannelColors :=true;
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  FClosing := True;

  { Normally FAnalysis is already nil here. The close query prevents us
    from reaching FormDestroy while a worker is active. }
  if Assigned(FAnalysis) then
    FAnalysis.Cancel;
  if Assigned(FOpenThread) then
    FOpenThread.Cancel;

  FOverview.Free;
  FOverview := nil;

  FPlot.Free;
  FPlot := nil;

  FDetector.Free;
  FSession.Free;
end;

procedure TMainForm.AnalysisFinished(Sender: TObject; const Peaks: TPeakArray;
  Canceled: Boolean; const ErrorText: string);
begin
  if FClosing then
    Exit;

  if Canceled then
  begin
    FSession.SetPeaks(nil);
    FCurrentPeak := -1;
    FPeakList.Clear;
    UpdateStatus('Analysis cancelled.');
  end
  else if ErrorText <> '' then
  begin
    FSession.SetPeaks(nil);
    FCurrentPeak := -1;
    FPeakList.Clear;
    UpdateStatus('Analysis error: ' + ErrorText);
  end
  else
  begin
    FSession.SetPeaks(Peaks);
    FillPeakListAroundFrame(FSession.GetPeakPosition(0));

    if Length(Peaks) > 0 then
      ShowPeak(0);

    UpdateStatus(Format('Analysis complete: %d peaks', [Length(Peaks)]));
  end;

  SetAnalysisUiState(False);
end;

procedure TMainForm.AnalysisProgress(Sender: TObject; Processed, Total: Int64);
var
  Percent: Integer;
begin
  if FClosing then
    Exit;

  if Total > 0 then
  begin
    Percent := Round(Processed * 100.0 / Total);
    if Percent < 0 then
      Percent := 0
    else if Percent > 100 then
      Percent := 100;
  end
  else
    Percent := 0;

  UpdateStatus(Format('Analyzing: %d%%  (%d / %d frames)',
    [Percent, Processed, Total]));
end;

procedure TMainForm.AnalysisThreadTerminated(Sender: TObject);
begin
  { The worker uses FreeOnTerminate=True. OnTerminate is only for clearing
    our reference and, when requested, allowing the form to close. }
  if FAnalysis = Sender then
    FAnalysis := nil;

  if FClosing then
    Close;
end;

procedure TMainForm.SetAnalysisUiState(Analyzing: Boolean);
begin
  if Analyzing then
    { Анализ/открытие WAV ломает текущую сессию — плей останавливаем. }
    StopPlayback(False);

  FOpenWavButton.Enabled := not Analyzing and not Assigned(FOpenThread);
  FOpenPeakButton.Enabled := not Analyzing;
  FSaveButton.Enabled := not Analyzing and (FSession.PeakCount > 0);
  FPrevButton.Enabled := not Analyzing;
  FNextButton.Enabled := not Analyzing;
  FApplyButton.Enabled := not Analyzing;
  FModeBox.Enabled := not Analyzing;
  edStartSample.Enabled := not Analyzing;
  edEndSample.Enabled := not Analyzing;
  FPositionBar.Enabled := not Analyzing;
  FPlayButton.Enabled := not Analyzing and (FSession.Mode <> dmNone);
  FPlaySpeedBox.Enabled := not Analyzing;

  FAnalyzeButton.Enabled := True;

  if Analyzing then
    FAnalyzeButton.Text := 'Cancel analysis'
  else
    FAnalyzeButton.Text := 'Analyze WAV';
end;

procedure TMainForm.OpenProgress(Sender: TObject; Stage: Integer;
  const Text: string);
begin
  if FClosing then
    Exit;
  UpdateStatus(Format('Opening WAV: %d%% - %s', [Stage, Text]));
end;

procedure TMainForm.OpenFinished(Sender: TObject; Session: TEodGuiSession;
  Canceled: Boolean; const ErrorText: string);
var
  OldSession: TEodGuiSession;
begin
  if FClosing then
  begin
    Session.Free;
    Exit;
  end;

  if Canceled then
  begin
    Session.Free;
    UpdateStatus('WAV opening cancelled.');
    Exit;
  end;

  if ErrorText <> '' then
  begin
    Session.Free;
    UpdateStatus('WAV opening error: ' + ErrorText);
    Exit;
  end;

  OldSession := FSession;
  FSession := Session;
  if FSession.TotalFrames > 0 then
  begin
    { WAV mode allocates a raw buffer matching the view, so the maximum
      view width must stay bounded to avoid huge allocations on zoom-out. }
    FPlot.SetMaxViewSamples(MaxViewSamples);
    FPlot.SetFullRange(0, FSession.TotalFrames - 1);
  end;

  BuildOverview;
  OldSession.Free;

  FSession.SetPeaks(nil);
  FCurrentPeak := -1;
  FCurrentStart := 0;
  FCurrentCount := 201;

  FillPeakList;
  SetAnalysisUiState(False);

  SetRangeEdits(0, 200);

  ShowRawPosition(0, 200);

  UpdateStatus(Format('WAV: %.3f sec, %d Hz, %d frames',
    [FSession.TotalFrames / FSession.SampleRate, FSession.SampleRate,
    FSession.TotalFrames]));

  UpdateCaption;
end;

procedure TMainForm.OpenThreadTerminated(Sender: TObject);
begin
  if FOpenThread = Sender then
    FOpenThread := nil;

  if FClosing then
    Close;
end;

procedure TMainForm.PlotViewChanged(Sender: TObject; ViewStart, ViewEnd: Int64);
begin
  if FSession.Mode = dmNone then
    Exit;

  UpdateOverviewView(ViewStart, ViewEnd);

  SetRangeEdits(ViewStart, ViewEnd);

  if FSession.Mode = dmWav then
    ShowRawPosition(ViewStart, ViewEnd)
  else if FSession.Mode = dmPeakFile then
    ShowPeakFileRange(ViewStart, ViewEnd);
end;

procedure TMainForm.UpdateStatus(const S: string);
begin
  FStatus.Text := S;
end;

procedure TMainForm.UpdateCaption;
var
  NameText: string;
begin
  if assigned (FSession) then

    case FSession.Mode of
      dmWav:
        if FSession.File1 <> '' then
          NameText := ExtractFileName(FSession.File1) + ' + ' +
            ExtractFileName(FSession.File2);
      dmPeakFile:
        if FSession.PeakFile <> '' then
          NameText := ExtractFileName(FSession.PeakFile);
    end;

  if NameText = '' then
    Caption := 'EOD Viewer'
  else
    Caption := 'EOD Viewer - ' + NameText;

  FOpenFolderButton.Enabled := NameText <> '';
end;

procedure TMainForm.FillPeakList;
const
  MaxListPeaks = 1000;
var
  Total: Int64;
  Count: Int64;
  Peaks: TPeakArray;
begin
  Total := FSession.PeakCount;

  if Total <= 0 then
  begin
    FPeakList.Clear;
    FPeakListFirstIndex := 0;
    FPeakListRealCount := 0;
    Exit;
  end;

  Count := Min(Total, Int64(MaxListPeaks));

  if not FSession.ReadPeakInfoRange(0, Count, Peaks) then
    Exit;

  PopulatePeakListRange(Peaks, 0, Total);
end;

function TMainForm.ReadInt64Edit(AEdit: TEdit; const ADefault: Int64): Int64;
var
  V: Int64;
begin
  if TryStrToInt64(Trim(AEdit.Text), V) then
    Result := V
  else
    Result := ADefault;
end;

procedure TMainForm.SetRangeEdits(AStart, AEnd: Int64);
begin
  if AEnd < AStart then
    AEnd := AStart;

  FUpdating := True;
  try
    edStartSample.Text := AStart.ToString;
    edEndSample.Text := AEnd.ToString;
    edRange.Text := (AEnd - AStart).ToString;
  finally
    FUpdating := False;
  end;
end;

procedure TMainForm.UpdateRangeDisplay;
var
  S, E: Int64;
begin
  S := ReadInt64Edit(edStartSample, 0);
  E := ReadInt64Edit(edEndSample, S);
  if E < S then
    E := S;
  edRange.Text := (E - S).ToString;
end;

procedure TMainForm.edStartSampleChange(Sender: TObject);
begin
  if FUpdating then
    Exit;
  UpdateRangeDisplay;
end;

procedure TMainForm.edEndSampleChange(Sender: TObject);
begin
  if FUpdating then
    Exit;
  UpdateRangeDisplay;
end;

function TMainForm.CurrentFrame: Int64;
begin
  Result := ReadInt64Edit(edStartSample, 0);

  if FSession.TotalFrames > 0 then
    Result := EnsureRange(Result, 0, FSession.TotalFrames - 1)
  else
    Result := 0;
end;

// procedure TMainForm.edStartSampleMouseWheel(Sender: TObject; Shift: TShiftState;
// WheelDelta: Integer; var Handled: Boolean);
// begin
// case WheelDelta>0 of
// true : FPrevButtonClick(self) ;
// false: FNextButtonClick(self) ;
// end;
// Handled:=false;
// end;
procedure TMainForm.edStartSampleMouseWheel(Sender: TObject; Shift: TShiftState;
  WheelDelta: Integer; var Handled: Boolean);
const
  WHEEL_THRESHOLD = 120; // один "щелчок" колеса = 120
begin
  Inc(FWheelAccumulator, WheelDelta);

  while FWheelAccumulator >= WHEEL_THRESHOLD do
  begin
    FWheelAccumulator := FWheelAccumulator - WHEEL_THRESHOLD;
    FPrevButtonClick(Self);
  end;

  while FWheelAccumulator <= -WHEEL_THRESHOLD do
  begin
    FWheelAccumulator := FWheelAccumulator + WHEEL_THRESHOLD;
    FNextButtonClick(Self);
  end;

  Handled := True;
end;

procedure TMainForm.ShowPeak(Index: Integer);
var
  Peak: TPeak;
  StartFrame: Int64;
  Data: TAudioChunk;
  Std: TFloatArray;
  Fir: TFloatArray;
  Range: Integer;
  PeakPositions: TArray<Int64>;
begin
  if (Index < 0) or (Index >= FSession.PeakCount) then
    Exit;

  { Убран ручной ItemIndex — теперь делает FillPeakListAroundFrame }

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

  FCurrentStart := StartFrame;
  FCurrentCount := Length(Data);

  SetRangeEdits(StartFrame, StartFrame + Length(Data) - 1);

  FCurrentPeak := Index;

  Std := FSession.CalculateStd(Data);
  Fir := FDetector.ApplyFir15(Std);

  FPlot.SetChannels(Data, StartFrame, FSession.SampleRate, Peak.Position,
    Format('Peak #%d  sample %d', [Index + 1, Peak.Position]));

  FPlot.SetStd(Std, StartFrame, FSession.SampleRate, Peak.Position,
    'STD around peak');

  FPlot.SetFir(Fir, StartFrame, FSession.SampleRate, Peak.Position,
    'FIR15 around peak');

  // PeakPositions := FSession.PeakPositions;
  // FPlot.SetPeakPositions(PeakPositions);
  // FPlot.SetPeakPositions(nil);
  UpdatePlotMode;

  FPlot.SetViewRange(StartFrame, StartFrame + Length(Data) - 1);

  { Синхронизируем красный прямоугольник выделения на обзорном графике
    с новым диапазоном отображения. SetViewRange не вызывает OnViewChanged,
    поэтому обновляем обзор вручную. }
  UpdateOverviewView(StartFrame, StartFrame + Length(Data) - 1);

  UpdateStatus(Format('Peak %d/%d: sample %d, time %.6f s, prominence %.6f',
    [Index + 1, FSession.PeakCount, Peak.Position,
    Peak.Position / FSession.SampleRate, Peak.Prominence]));

  { Перезаполняем ListBox только если нужно, иначе просто подсвечиваем }
  FillPeakListAroundFrame(Peak.Position);
end;

procedure TMainForm.ShowPeakFileRange(AStartFrame, AEndFrame: Int64);
const
  RawLimit = 10000;
  MaxEnvelopePoints = 4096;
var
  StartFrame, EndFrame: Int64;
  Count64: Int64;

  Envelope: TWaveEnvelope;

  FirstIdx, LastIdx: Int64;
  PeakCountInRange: Int64;

  Data: TAudioChunk;
  Std: TFloatArray;
  Fir: TFloatArray;

  Peak: TPeak;
  PeakStart: Int64;
  Temp: TAudioChunk;

  CopyStart, CopyEnd: Int64;
  DestOffset, SourceOffset: Int64;
  CopyCount: Int64;

  I: Int64;
begin
  if FSession.Mode <> dmPeakFile then
    Exit;

  if FSession.TotalFrames <= 0 then
    Exit;

  StartFrame := EnsureRange(AStartFrame, Int64(0), FSession.TotalFrames - 1);

  EndFrame := EnsureRange(AEndFrame, StartFrame, FSession.TotalFrames - 1);

  Count64 := EndFrame - StartFrame + 1;

  { ------------------------------------------------------------ }
  { Small range: keep exact waveform behaviour. }
  { ------------------------------------------------------------ }

  if Count64 <= RawLimit then
  begin
    if FSession.FindPeakRangeIndices(StartFrame, EndFrame, 30, FirstIdx, LastIdx)
    then
    begin
      PeakCountInRange := LastIdx - FirstIdx + 1;
    end
    else
      PeakCountInRange := 0;

    if PeakCountInRange <= RawLimit then
    begin
      SetLength(Data, Integer(Count64));

      if Length(Data) > 0 then
        FillChar(Data[0], NativeInt(Length(Data)) * SizeOf(TAudioFrame), 0);

      if PeakCountInRange > 0 then
      begin
        for I := FirstIdx to LastIdx do
        begin
          Temp := FSession.ReadPeak(Integer(I), Peak, PeakStart);

          CopyStart := Max(StartFrame, PeakStart);

          CopyEnd := Min(EndFrame, PeakStart + Length(Temp) - 1);

          if CopyEnd < CopyStart then
            Continue;

          DestOffset := CopyStart - StartFrame;

          SourceOffset := CopyStart - PeakStart;

          CopyCount := CopyEnd - CopyStart + 1;

          Move(Temp[Integer(SourceOffset)], Data[Integer(DestOffset)],
            NativeInt(CopyCount) * SizeOf(TAudioFrame));
        end;
      end;

      FPlot.SetChannels(Data, StartFrame, FSession.SampleRate, -1,
        Format('Samples %d .. %d', [StartFrame, EndFrame]));

      Std := FSession.CalculateStd(Data);
      Fir := FDetector.ApplyFir15(Std);

      FPlot.SetStd(Std, StartFrame, FSession.SampleRate, -1, 'STD');

      FPlot.SetFir(Fir, StartFrame, FSession.SampleRate, -1, 'FIR15');

      FPlot.SetSelectedPosition(StartFrame);
      FPlot.SetViewRange(StartFrame, EndFrame);
      FPlot.SetHistogramRange(StartFrame, EndFrame);

      UpdatePlotMode;
      Exit;
    end;
  end;

  { ------------------------------------------------------------ }
  { Large range: NEVER allocate TAudioChunk for the range. }
  { ------------------------------------------------------------ }

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

  { STD/FIR are not meaningful here without reconstructing raw data. }
  FPlot.SetStd(nil, StartFrame, FSession.SampleRate, -1, 'STD');

  FPlot.SetFir(nil, StartFrame, FSession.SampleRate, -1, 'FIR15');

  UpdatePlotMode;

  UpdateStatus
    (Format('EODPK envelope %d .. %d  (%d samples, %d display buckets)',
    [StartFrame, EndFrame, Count64, Length(Envelope)]));
end;

procedure TMainForm.ShowRawPosition(AStartFrame, AEndFrame: Int64);
var
  StartFrame, EndFrame: Int64;
  Data: TAudioChunk;
  Std: TFloatArray;
  Fir: TFloatArray;
  PeakPositions: TArray<Int64>;
  I, N: Integer;
  Peak: TPeak;
  CountText: string;
begin
  if FSession.Mode <> dmWav then
    Exit;

  if FSession.TotalFrames <= 0 then
    Exit;

  StartFrame := EnsureRange(AStartFrame, Int64(0), FSession.TotalFrames - 1);
  EndFrame := EnsureRange(AEndFrame, StartFrame, FSession.TotalFrames - 1);

  Data := FSession.ReadSegment(StartFrame, EndFrame - StartFrame + 1, True);

  FCurrentStart := StartFrame;
  FCurrentCount := Length(Data);

  Std := FSession.CalculateStd(Data);
  Fir := FDetector.ApplyFir15(Std);

  FPlot.SetChannels(Data, StartFrame, FSession.SampleRate, -1,
    Format('Samples %d .. %d', [StartFrame, EndFrame]));

  FPlot.SetStd(Std, StartFrame, FSession.SampleRate, -1, 'STD');

  FPlot.SetFir(Fir, StartFrame, FSession.SampleRate, -1, 'FIR15');

  N := 0;
  for I := 0 to FSession.PeakCount - 1 do
    if FSession.GetPeak(I, Peak) then
      if (Peak.Position >= StartFrame) and (Peak.Position <= EndFrame) then
        Inc(N);

  SetLength(PeakPositions, N);
  N := 0;
  for I := 0 to FSession.PeakCount - 1 do
    if FSession.GetPeak(I, Peak) then
      if (Peak.Position >= StartFrame) and (Peak.Position <= EndFrame) then
      begin
        PeakPositions[N] := Peak.Position;
        Inc(N);
      end;

  FPlot.SetPeakPositions(PeakPositions);
  FPlot.SetSelectedPosition(StartFrame);
  FPlot.SetViewRange(StartFrame, EndFrame);
  FPlot.SetHistogramRange(StartFrame, EndFrame);

  SetRangeEdits(StartFrame, EndFrame);

  if N <= 1000 then
    CountText := Format('; %d peaks in selection', [N])
  else
    CountText := Format('; >1000 peaks in selection (%d, not listed)', [N]);

  UpdateStatus(Format('Samples %d .. %d  (%d samples, %.6f s .. %.6f s)%s',
    [StartFrame, EndFrame, Length(Data), StartFrame / FSession.SampleRate,
    EndFrame / FSession.SampleRate, CountText]));

  UpdatePlotMode;
end;

procedure TMainForm.UpdatePlotMode;
var
  StartFrame, EndFrame: Int64;
begin
  if not Assigned(FPlot) then
    Exit;

  FPlot.SetMode(TPlotMode(FModeBox.ItemIndex));

  StartFrame := ReadInt64Edit(edStartSample, 0);
  EndFrame := ReadInt64Edit(edEndSample, StartFrame);
  if EndFrame < StartFrame then
    EndFrame := StartFrame;
  FPlot.SetViewRange(StartFrame, EndFrame);
end;

procedure TMainForm.StartAnalysis(MaxFrames: Int64);
begin
  if Assigned(FAnalysis) then
    Exit;

  FPeakList.Clear;
  FSession.SetPeaks(nil);
  FCurrentPeak := -1;

  SetAnalysisUiState(True);
  UpdateStatus('Starting analysis...');

  FAnalysis := TEodAnalysisThread.Create(FSession.File1, FSession.File2,
    FConfig, MaxFrames);

  FAnalysis.OnProgress := AnalysisProgress;
  FAnalysis.OnFinished := AnalysisFinished;
  FAnalysis.OnTerminate := AnalysisThreadTerminated;
  FAnalysis.Start;
end;

procedure TMainForm.ShowCurrentRange;
begin
  if FSession.Mode = dmWav then
    ShowRawPosition(CurrentFrame, CurrentFrame + Max(0, FCurrentCount - 1))
  else if FSession.Mode = dmPeakFile then
    ShowPeakFileRange(ReadInt64Edit(edStartSample, 0),
      ReadInt64Edit(edEndSample, ReadInt64Edit(edStartSample, 0)));
end;

procedure TMainForm.FAnalyzeButtonClick(Sender: TObject);
var
  SecondsText: string;
  MaxFrames: Int64;
begin
  { The same button is used as an immediate cancel command while the
    worker is running. We never WaitFor here, so the GUI remains responsive. }
  if Assigned(FAnalysis) then
  begin
    FAnalysis.Cancel;
    FAnalyzeButton.Enabled := False;
    UpdateStatus('Cancel requested...');
    Exit;
  end;

  if FSession.Mode <> dmWav then
  begin
    UpdateStatus('Open a WAV pair first.');
    Exit;
  end;

  SecondsText := 'Analyze the whole WAV now?' + sLineBreak +
    'The analysis will run in the background.' + sLineBreak +
    'Press No to analyze the first 600 seconds only.';

  if MessageDlg(SecondsText, TMsgDlgType.mtConfirmation,
    [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo], 0) = mrYes then
    MaxFrames := 0
  else
  begin
    MaxFrames := Int64(600) * FSession.SampleRate;

    if MaxFrames > FSession.TotalFrames then
      MaxFrames := FSession.TotalFrames;
  end;

  StartAnalysis(MaxFrames);
end;

procedure TMainForm.FApplyButtonClick(Sender: TObject);
begin
  if FSession.Mode = dmPeakFile then
  begin
    ShowPeakFileRange(ReadInt64Edit(edStartSample, 0),
      ReadInt64Edit(edEndSample, ReadInt64Edit(edStartSample, 0)));
    Exit;
  end;

  ShowRawPosition(ReadInt64Edit(edStartSample, 0), ReadInt64Edit(edEndSample,
    ReadInt64Edit(edStartSample, 0)));
end;

procedure TMainForm.FModeBoxChange(Sender: TObject);
begin
  UpdatePlotMode;
end;

procedure TMainForm.FNextButtonClick(Sender: TObject);
begin
  if FSession.PeakCount = 0 then
    Exit;

  if FCurrentPeak < FSession.PeakCount - 1 then
    Inc(FCurrentPeak)
  else
    FCurrentPeak := FSession.PeakCount - 1;

  ShowPeak(FCurrentPeak);
end;

{ ================================================================== }
{  Воспроизведение                                                   }
{ ================================================================== }

procedure TMainForm.ApplyPlaybackSpeed;
begin
  case FPlaySpeedBox.ItemIndex of
    0: FPlaySpeed := 0.1;
    1: FPlaySpeed := 0.25;
    2: FPlaySpeed := 0.5;
    4: FPlaySpeed := 2.0;
    5: FPlaySpeed := 5.0;
    6: FPlaySpeed := 10.0;
  else
    FPlaySpeed := 1.0;
  end;
end;

procedure TMainForm.PlaySpeedBoxChange(Sender: TObject);
var
  ElapsedS: Double;
begin
  if FPlayActive then
  begin
    { Фиксируем текущую виртуальную позицию и перезапускаем часы,
      чтобы смена скорости не дала скачка вперёд или назад. }
    ElapsedS := FPlayClock.Elapsed.TotalSeconds;
    FPlayStartPos := FPlayStartPos +
      Trunc(ElapsedS * FSession.SampleRate * FPlaySpeed);
    FPlayClock := TStopwatch.StartNew;
  end;

  ApplyPlaybackSpeed;
end;

procedure TMainForm.FPlayButtonClick(Sender: TObject);
begin
  if FPlayActive then
    StopPlayback(False)
  else
    StartPlayback;
end;

procedure TMainForm.StartPlayback;
var
  Total: Integer;
  L, R, Mid: Int64;
  Pos: Int64;
  StartFrame: Int64;
begin
  if FPlayActive then
    Exit;

  if FSession.Mode = dmNone then
    Exit;

  Total := FSession.PeakCount;

  if Total <= 0 then
  begin
    UpdateStatus('Nothing to play: no peaks.');
    Exit;
  end;

  if FSession.SampleRate <= 0 then
    Exit;

  { Если стоим на последнем пике (например, после полного прохода) —
    начинаем с начала, иначе это дало бы мгновенный "пустой" плей. }
  if FCurrentPeak >= Total - 1 then
    FPlayIndex := 0
  else if FCurrentPeak >= 0 then
    FPlayIndex := FCurrentPeak
  else
  begin
    { Пик не выбран: берём первый пик от текущего начала отображения. }
    StartFrame := CurrentFrame;

    L := 0;
    R := Total - 1;
    while L < R do
    begin
      Mid := L + (R - L) div 2;
      Pos := FSession.GetPeakPosition(Integer(Mid));
      if Pos < StartFrame then
        L := Mid + 1
      else
        R := Mid;
    end;

    FPlayIndex := Integer(L);

    { Если текущая позиция находится после последнего пика (поиск
      вышел за конец) — начинаем с последнего пика. }
    if FPlayIndex >= Total then
      FPlayIndex := Total - 1;
  end;

  FPlayStartPos := FSession.GetPeakPosition(FPlayIndex);
  FPlayClock := TStopwatch.StartNew;
  FPlayActive := True;

  FPlayButton.Text := 'Stop';

  { Первый пик показываем немедленно, дальше их ведёт таймер. }
  ShowPeak(FPlayIndex);
  Inc(FPlayIndex);

  FPlayTimer.Enabled := True;

  UpdateStatus(Format('Playing: peak %d/%d, speed %gx',
    [FCurrentPeak + 1, Total, FPlaySpeed]));
end;

procedure TMainForm.StopPlayback(Finished: Boolean);
begin
  if not FPlayActive then
    Exit;

  FPlayTimer.Enabled := False;
  FPlayActive := False;
  FPlayButton.Text := 'Play';

  if Finished then
    UpdateStatus(Format('Playback finished at peak %d/%d.',
      [FCurrentPeak + 1, FSession.PeakCount]))
  else
    UpdateStatus(Format('Playback stopped at peak %d/%d.',
      [FCurrentPeak + 1, FSession.PeakCount]));
end;

procedure TMainForm.PlayTimerTick(Sender: TObject);
var
  Total: Integer;
  VirtualNow: Int64;
  ElapsedS: Double;
  ShowIdx: Integer;
  P: Double;
begin
  if not FPlayActive then
    Exit;

  Total := FSession.PeakCount;

  if Total <= 0 then
  begin
    StopPlayback(False);
    Exit;
  end;

  { Виртуальное "сейчас" в сэмплах: старт + реальное время * скорость.
    Скорость 1x соответствует реальному темпу записи. }
  ElapsedS := FPlayClock.Elapsed.TotalSeconds;
  VirtualNow := FPlayStartPos +
    Trunc(ElapsedS * FSession.SampleRate * FPlaySpeed);

  { За один тик может наступить время нескольких пиков — показываем
    последний из них, промежуточные пропускаем. }
  ShowIdx := -1;
  while (FPlayIndex < Total) and
        (FSession.GetPeakPosition(FPlayIndex) <= VirtualNow) do
  begin
    ShowIdx := FPlayIndex;
    Inc(FPlayIndex);
  end;

  if ShowIdx >= 0 then
    ShowPeak(ShowIdx);

  { Ползунок позиции двигаем молча — сам он перерисовывать ничего не должен. }
  if FSession.TotalFrames > 0 then
  begin
    P := VirtualNow / FSession.TotalFrames;
    if P < 0 then
      P := 0
    else if P > 1 then
      P := 1;

    FUpdating := True;
    try
      FPositionBar.Value := P * 1000;
    finally
      FUpdating := False;
    end;
  end;

  if FPlayIndex >= Total then
    StopPlayback(True);
end;

procedure TMainForm.FOpenPeakButtonClick(Sender: TObject);
var
  D: TOpenDialog;
  StartFrame, EndFrame: Int64;
begin
  StopPlayback(False);

  D := TOpenDialog.Create(Self);
  try
    D.Filter := 'EOD peak files (*.eodpk)|*.eodpk|All files (*.*)|*.*';
    D.Title := 'Open EOD peak file';
    if FLastDir <> '' then
      D.InitialDir := FLastDir;

    if not D.Execute then
      Exit;

    FLastDir := ExtractFilePath(D.FileName);

    FSession.OpenPeakFile(D.FileName);
    UpdateCaption;

    if FSession.TotalFrames > 0 then
    begin
      { EODPK draws only from the compact envelope (never a full raw
        buffer), so the whole file may be displayed at once. Allow the
        view to be zoomed all the way out to the entire file. }
      FPlot.SetMaxViewSamples(FSession.TotalFrames);
      FPlot.SetFullRange(0, FSession.TotalFrames - 1);
    end;

    BuildOverview;

    FCurrentPeak := -1;

    FillPeakList;

    if FSession.PeakCount > 0 then
    begin
      StartFrame := FSession.GetPeakPosition(0) - 200;;
      if StartFrame < 0 then
        StartFrame := 0;
      EndFrame := FSession.GetPeakPosition(0) + 200;
      if EndFrame >= FSession.TotalFrames then
        EndFrame := FSession.TotalFrames - 1;
      SetRangeEdits(StartFrame, EndFrame);
      ShowPeakFileRange(StartFrame, EndFrame);

    end
    else
    begin
      SetRangeEdits(0, 200);
    end;

    // UpdateStatus(Format(
    // 'EODPK: %d peaks, %d Hz',
    // [FSession.PeakCount, FSession.SampleRate]));
    UpdateStatus(Format('EODPK ver %d: %d peaks, %d Hz, %d frames',
      [FSession.Version, FSession.PeakCount, FSession.SampleRate,
      FSession.TotalFrames]));
  finally
    D.Free;
  end;
end;

procedure TMainForm.FOpenWavButtonClick(Sender: TObject);
var
  D: TOpenDialog;
  File1, File2: string;
begin
  if Assigned(FOpenThread) or Assigned(FAnalysis) then
    Exit;

  D := TOpenDialog.Create(Self);
  try
    D.Filter := 'WAV files (*.wav)|*.wav|All files (*.*)|*.*';
    D.Title := 'Open Tr12 WAV';
    if FLastDir <> '' then
      D.InitialDir := FLastDir;

    if not D.Execute then
      Exit;

    File1 := D.FileName;
    FLastDir := ExtractFilePath(File1);

    if TryGetPairedWavFileName(File1, File2) and FileExists(File2) then
    begin
      { Парный файл найден автоматически. }
    end
    else
    begin
      if TryGetPairedWavFileName(File1, File2) then
      begin
        if MessageDlg(
          'Парный WAV не найден:' + sLineBreak +
          File2 + sLineBreak + sLineBreak +
          'Выбрать второй WAV вручную?',
          TMsgDlgType.mtWarning,
          [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo], 0) <> mrYes then
          Exit;
      end
      else
      begin
        if MessageDlg(
          'Не удалось определить имя парного WAV.' + sLineBreak +
          'Выбрать второй WAV вручную?',
          TMsgDlgType.mtWarning,
          [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo], 0) <> mrYes then
          Exit;
      end;

      D.Title := 'Open paired WAV';

      if not D.Execute then
        Exit;

      File2 := D.FileName;
    end;
  finally
    D.Free;
  end;

  FOpenThread := TEodWavOpenThread.Create(File1, File2);
  FOpenThread.OnProgress := OpenProgress;
  FOpenThread.OnFinished := OpenFinished;
  FOpenThread.OnTerminate := OpenThreadTerminated;
  FOpenThread.Start;

  SetAnalysisUiState(True);
  FAnalyzeButton.Enabled := False;
  FOpenPeakButton.Enabled := False;
  FSaveButton.Enabled := False;
  UpdateStatus('Opening WAV in background...');
end;

procedure TMainForm.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  { Плеер живёт только в главном потоке — его достаточно просто остановить. }
  StopPlayback(False);

  if Assigned(FAnalysis) or Assigned(FOpenThread) then
  begin
    FClosing := True;
    if Assigned(FAnalysis) then
      FAnalysis.Cancel;
    if Assigned(FOpenThread) then
      FOpenThread.Cancel;
    CanClose := False;
    UpdateStatus('Stopping background operation...');
    Exit;
  end;

  CanClose := True;
end;

// procedure TMainForm.FPeakListClick(Sender: TObject);
/// /begin
/// /  if FPeakList.ItemIndex >= 0 then
/// /    ShowPeak(FPeakList.ItemIndex);
// var
// PeakIndex: Integer;
// begin
// if FPeakList.ItemIndex < 0 then
// Exit;
//
// PeakIndex :=
// FPeakListFirstIndex +
// FPeakList.ItemIndex;
//
// if (PeakIndex >= 0) and
// (PeakIndex < FSession.PeakCount) then
// ShowPeak(PeakIndex);
// end;
procedure TMainForm.FPeakListClick(Sender: TObject);
var
  PeakIndex: Integer;
  S: string;
begin
  if FPeakList.ItemIndex < 0 then
    Exit;

  S := FPeakList.Items[FPeakList.ItemIndex];

  { Обработка навигационных элементов }
  if S.StartsWith('<<') then
  begin
    { Листаем назад: предыдущее окно, крайний правый реальный элемент }
    PeakIndex := Max(0, FPeakListFirstIndex - 1);
    ShowPeak(PeakIndex);
    Exit;
  end;

  if S.StartsWith('>>') then
  begin
    { Листаем вперёд: следующее окно, крайний левый реальный элемент }
    PeakIndex := Min(FSession.PeakCount - 1, FPeakListFirstIndex +
      FPeakListRealCount);
    ShowPeak(PeakIndex);
    Exit;
  end;

  { Обычный пик }
  PeakIndex := FPeakListFirstIndex + FPeakList.ItemIndex;
  if FPeakListFirstIndex > 0 then
    Dec(PeakIndex); // компенсация элемента "<<"

  if (PeakIndex >= 0) and (PeakIndex < FSession.PeakCount) then
  begin
    FCurrentPeak := PeakIndex;
    ShowPeak(PeakIndex);
  end;
end;

procedure TMainForm.FPeakListMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Single);
var
  S: string;
begin
  if (Button <> TMouseButton.mbRight) or (FPeakList.Selected = nil) then
    Exit;

  S := FPeakList.Selected.Text;
  if S.StartsWith('<<') or S.StartsWith('>>') then
    Exit;

  { edEndSample.OnChange (edEndSampleChange) recomputes edRange automatically. }
  edEndSample.Text := S;
end;

procedure TMainForm.FPositionBarChange(Sender: TObject);
var
  P: Double;
  Frame: Int64;
  ViewW: Int64;
begin
  if FUpdating or (FSession.Mode = dmNone) then
    Exit;

  P := FPositionBar.Value / 1000.0;
  if P < 0 then
    P := 0
  else if P > 1 then
    P := 1;

  if FSession.TotalFrames > 0 then
    Frame := Round(P * (FSession.TotalFrames - 1))
  else
    Frame := 0;

  ViewW := FPlot.ViewSampleCount;
  if ViewW <= 0 then
    ViewW := FCurrentCount;
  if ViewW <= 0 then
    ViewW := 200;

  SetRangeEdits(Frame, Frame + ViewW - 1);

  if FSession.Mode = dmWav then
    ShowRawPosition(Frame, Frame + ViewW - 1)
  else if FSession.Mode = dmPeakFile then
    ShowPeakFileRange(Frame, Frame + ViewW - 1);
end;

procedure TMainForm.FPrevButtonClick(Sender: TObject);
begin
  if FSession.PeakCount = 0 then
    Exit;

  if FCurrentPeak > 0 then
    Dec(FCurrentPeak)
  else
    FCurrentPeak := 0;

  ShowPeak(FCurrentPeak);
end;

procedure TMainForm.FSaveButtonClick(Sender: TObject);
var
  D: TSaveDialog;
begin
  if Assigned(FAnalysis) then
  begin
    UpdateStatus('Analysis is still running.');
    Exit;
  end;

  if (FSession.Mode <> dmWav) and (FSession.Mode <> dmPeakFile) then
  begin
    UpdateStatus('Open a file first.');
    Exit;
  end;

  if FSession.PeakCount = 0 then
  begin
    UpdateStatus('No peaks to save.');
    Exit;
  end;

  D := TSaveDialog.Create(Self);
  try
    D.Filter := 'EOD peak files (*.eodpk)|*.eodpk';
    D.DefaultExt := 'eodpk';
    if FLastDir <> '' then
      D.InitialDir := FLastDir;

    if FSession.Mode = dmWav then
      D.FileName := GetSuggestedEodPeakFileName(FSession.File1)
    else if FSession.Mode = dmPeakFile then
      D.FileName := ChangeFileExt(ExtractFileName(FSession.PeakFile), '.eodpk')
    else
      D.FileName := 'peaks.eodpk';

    if not D.Execute then
      Exit;

    UpdateStatus('Saving peaks...');
    Application.ProcessMessages;

    FSession.SavePeakFile(D.FileName);

    FLastDir := ExtractFilePath(D.FileName);
    UpdateStatus('Saved: ' + D.FileName);
  finally
    D.Free;
  end;
end;

procedure TMainForm.FOpenFolderButtonClick(Sender: TObject);
var
  Target: string;
begin
  case FSession.Mode of
    dmWav: Target := FSession.File1;
    dmPeakFile: Target := FSession.PeakFile;
  else
    Exit;
  end;

  if Target = '' then
    Exit;

  {$IFDEF MSWINDOWS}
  { Ключ '/select,' открывает папку и подсвечивает файл в проводнике. }
  ShellExecute(0, 'open', 'explorer.exe',
    PChar('/select,"' + Target + '"'), nil, SW_SHOWNORMAL);
  {$ELSE}
  UpdateStatus('Opening the file folder is not supported on this platform.');
  {$ENDIF}
end;

procedure TMainForm.BuildOverview;
const
  OverviewPoints = 2000;
  ChunkSize = 65536;
var
  TotalFrames: Int64;
  I, J: Integer;
  N: Integer;
  StartFrame: Int64;
  EndFrame: Int64;
  Count64: Int64;
  Data: TAudioChunk;

  BinStart: Int64;
  BinEnd: Int64;

  VMin, VMax: Single;
  V: Single;

  P: TPeak;

  { Поканальные min/max текущего бина. }
  Ch: Integer;
  ChInit: Boolean;
  ChMin: array[0..3] of Single;
  ChMax: array[0..3] of Single;

  Envelope: TWaveEnvelope;
  B, B0, B1: Integer;

  function FrameValue(const AFrame: TAudioFrame): Single;
  var
    A1, A2, A3, A4: Single;
  begin
    A1 := Abs(AFrame.Ch1);
    A2 := Abs(AFrame.Ch2);
    A3 := Abs(AFrame.Ch3);
    A4 := Abs(AFrame.Ch4);

    Result := Max(Max(A1, A2), Max(A3, A4));
  end;

  procedure ResetChannelBin;
  var
    C: Integer;
  begin
    ChInit := False;

    for C := 0 to 3 do
    begin
      ChMin[C] := 0;
      ChMax[C] := 0;
    end;
  end;

  { Вызывается на каждый сэмпл всей записи, поэтому без циклов и вызовов
    на канал — только сравнения. }
  procedure AddChannelFrame(const AFrame: TAudioFrame);
  begin
    if ChInit then
    begin
      if AFrame.Ch1 < ChMin[0] then ChMin[0] := AFrame.Ch1;
      if AFrame.Ch1 > ChMax[0] then ChMax[0] := AFrame.Ch1;

      if AFrame.Ch2 < ChMin[1] then ChMin[1] := AFrame.Ch2;
      if AFrame.Ch2 > ChMax[1] then ChMax[1] := AFrame.Ch2;

      if AFrame.Ch3 < ChMin[2] then ChMin[2] := AFrame.Ch3;
      if AFrame.Ch3 > ChMax[2] then ChMax[2] := AFrame.Ch3;

      if AFrame.Ch4 < ChMin[3] then ChMin[3] := AFrame.Ch4;
      if AFrame.Ch4 > ChMax[3] then ChMax[3] := AFrame.Ch4;
    end
    else
    begin
      ChMin[0] := AFrame.Ch1;
      ChMax[0] := AFrame.Ch1;

      ChMin[1] := AFrame.Ch2;
      ChMax[1] := AFrame.Ch2;

      ChMin[2] := AFrame.Ch3;
      ChMax[2] := AFrame.Ch3;

      ChMin[3] := AFrame.Ch4;
      ChMax[3] := AFrame.Ch4;
    end;

    ChInit := True;
  end;

  function FrameToBin(AFrame: Int64): Integer;
  begin
    if TotalFrames <= 1 then
      Result := 0
    else
      Result := EnsureRange(
        Integer((AFrame * N) div TotalFrames), 0, N - 1);
  end;

  procedure UpdateChannelBin(ABin, AChannel: Integer;
    AChMin, AChMax: Single);
  begin
    { Пустой бакет кэша: min/max остались в начальных значениях. }
    if AChMin > AChMax then
      Exit;

    if AChMin < FOverviewChMin[AChannel][ABin] then
      FOverviewChMin[AChannel][ABin] := AChMin;

    if AChMax > FOverviewChMax[AChannel][ABin] then
      FOverviewChMax[AChannel][ABin] := AChMax;
  end;

begin
  if not Assigned(FOverview) then
    Exit;

  if FSession.Mode = dmNone then
  begin
    FOverview.Clear;
    Exit;
  end;

  TotalFrames := FSession.TotalFrames;

  if TotalFrames <= 0 then
  begin
    FOverview.Clear;
    Exit;
  end;

  N := OverviewPoints;

  if TotalFrames < N then
    N := Integer(TotalFrames);

  if N < 1 then
    Exit;

  SetLength(FOverviewMin, N);
  SetLength(FOverviewMax, N);

  for I := 0 to N - 1 do
  begin
    FOverviewMin[I] := 0;
    FOverviewMax[I] := 0;
  end;

  for Ch := 0 to 3 do
  begin
    SetLength(FOverviewChMin[Ch], N);
    SetLength(FOverviewChMax[Ch], N);

    for I := 0 to N - 1 do
    begin
      FOverviewChMin[Ch][I] := 0;
      FOverviewChMax[Ch][I] := 0;
    end;
  end;

  { --------------------------------------------------------------- }
  { WAV }
  { --------------------------------------------------------------- }

  if FSession.Mode = dmWav then
  begin
    for I := 0 to N - 1 do
    begin
      BinStart := (Int64(I) * TotalFrames) div N;

      BinEnd := (Int64(I + 1) * TotalFrames) div N - 1;

      if BinEnd < BinStart then
        BinEnd := BinStart;

      VMin := 0;
      VMax := 0;

      ResetChannelBin;

      StartFrame := BinStart;

      while StartFrame <= BinEnd do
      begin
        EndFrame := Min(BinEnd, StartFrame + ChunkSize - 1);

        Count64 := EndFrame - StartFrame + 1;

        if Count64 > MaxInt then
          Break;

        Data := FSession.ReadSegment(StartFrame, Integer(Count64), False);

        for J := 0 to Length(Data) - 1 do
        begin
          V := FrameValue(Data[J]);

          if J = 0 then
          begin
            VMin := V;
            VMax := V;
          end
          else
          begin
            if V < VMin then
              VMin := V;

            if V > VMax then
              VMax := V;
          end;

          AddChannelFrame(Data[J]);
        end;

        StartFrame := EndFrame + 1;
      end;

      FOverviewMin[I] := -VMax;
      FOverviewMax[I] := VMax;

      for Ch := 0 to 3 do
      begin
        FOverviewChMin[Ch][I] := ChMin[Ch];
        FOverviewChMax[Ch][I] := ChMax[Ch];
      end;
    end;
  end

  { --------------------------------------------------------------- }
  { EODPK }
  { --------------------------------------------------------------- }

  else if FSession.Mode = dmPeakFile then
  begin
    { Для EODPK используем peak records как источник сигнала. }

    for I := 0 to FSession.PeakCount - 1 do
    begin
      if not FSession.GetPeak(I, P) then
        Continue;

      if FSession.TotalFrames <= 1 then
        J := 0
      else
        J := EnsureRange(Integer((P.Position * N) div TotalFrames), 0, N - 1);

      V := Abs(P.Value);

      if V > FOverviewMax[J] then
        FOverviewMax[J] := V;

      if -V < FOverviewMin[J] then
        FOverviewMin[J] := -V;
    end;

    { Поканальные огибающие берём из кэша файла: он хранит min/max по
      каждому каналу. Если кэша нет, массивы останутся нулевыми, и режим
      "в цветах каналов" покажет обычную серую огибающую. }
    if FSession.ReadPeakEnvelope(0, TotalFrames - 1, N, Envelope) then
    begin
      for I := 0 to High(Envelope) do
      begin
        if Envelope[I].EndPosition < Envelope[I].StartPosition then
          Continue;

        B0 := FrameToBin(Envelope[I].StartPosition);
        B1 := FrameToBin(Envelope[I].EndPosition);

        for B := B0 to B1 do
        begin
          UpdateChannelBin(B, 0, Envelope[I].Ch1Min, Envelope[I].Ch1Max);
          UpdateChannelBin(B, 1, Envelope[I].Ch2Min, Envelope[I].Ch2Max);
          UpdateChannelBin(B, 2, Envelope[I].Ch3Min, Envelope[I].Ch3Max);
          UpdateChannelBin(B, 3, Envelope[I].Ch4Min, Envelope[I].Ch4Max);
        end;
      end;
    end;
  end;

  FOverview.SetData(FOverviewMin, FOverviewMax, 0, TotalFrames - 1);

  FOverview.SetChannelData(
    FOverviewChMin, FOverviewChMax, 0, TotalFrames - 1);

  FOverview.SetViewRange(0, Min(TotalFrames - 1, FPlot.ViewSampleCount));
end;

procedure TMainForm.UpdateOverviewView(ViewStart, ViewEnd: Int64);
begin
  if not Assigned(FOverview) then
    Exit;

  if FSession.Mode = dmNone then
    Exit;

  FOverview.SetViewRange(ViewStart, ViewEnd);
end;

procedure TMainForm.SetOverviewChannelColors(AValue: Boolean);
begin
  FOverviewChannelColors := AValue;

  if Assigned(FOverview) then
    FOverview.ChannelColors := AValue;
end;

procedure TMainForm.OverviewClick(Sender: TObject; Frame: Int64);
var
  ViewWidth: Int64;
  NewStart, NewEnd: Int64;
begin
  if FSession.Mode = dmNone then
    Exit;
  if FSession.TotalFrames <= 0 then
    Exit;

  ViewWidth := FPlot.ViewSampleCount;
  if ViewWidth <= 0 then
    ViewWidth := FCurrentCount;
  if ViewWidth <= 0 then
    ViewWidth := 201;

  NewStart := Frame - ViewWidth div 2;
  NewEnd := NewStart + ViewWidth;

  if NewStart < 0 then
  begin
    NewStart := 0;
    NewEnd := NewStart + ViewWidth;
  end;
  if NewEnd >= FSession.TotalFrames then
  begin
    NewEnd := FSession.TotalFrames - 1;
    NewStart := NewEnd - ViewWidth;
  end;
  if NewStart < 0 then
    NewStart := 0;

  SetRangeEdits(NewStart, NewEnd);

  if FSession.Mode = dmWav then
    ShowRawPosition(NewStart, NewEnd)
  else if FSession.Mode = dmPeakFile then
    ShowPeakFileRange(NewStart, NewEnd);

  { <<< FIX: восстановление рабочего диапазона отображения >>> }
  FPlot.GetViewRange(NewStart, NewEnd);
  UpdateOverviewView(NewStart, NewEnd);

  { Заполняем ListBox пиками вокруг выбранной на обзоре точки
    и подсвечиваем ближайший к ней пик. }
  FillPeakListAroundFrame(Frame);
end;


procedure TMainForm.OverviewRangeSelected(Sender: TObject; AStart, AEnd: Int64);
var
  ViewStart, ViewEnd: Int64;
begin
  if FSession.Mode = dmNone then
    Exit;
  if FSession.TotalFrames <= 0 then
    Exit;

  AStart := EnsureRange(AStart, Int64(0), FSession.TotalFrames - 1);
  AEnd := EnsureRange(AEnd, AStart, FSession.TotalFrames - 1);

  SetRangeEdits(AStart, AEnd);

  if FSession.Mode = dmWav then
    ShowRawPosition(AStart, AEnd)
  else if FSession.Mode = dmPeakFile then
    ShowPeakFileRange(AStart, AEnd);

  FPlot.GetViewRange(ViewStart, ViewEnd);
  UpdateOverviewView(ViewStart, ViewEnd);
end;

procedure TMainForm.PopulatePeakListRange(const Peaks: TPeakArray;
  FirstIndex: Int64; Total: Int64);
var
  I: Integer;
  LastIndex: Int64;
begin
  if Length(Peaks) = 0 then
  begin
    FPeakList.Clear;
    FPeakListFirstIndex := 0;
    FPeakListRealCount := 0;
    Exit;
  end;

  LastIndex := FirstIndex + Length(Peaks) - 1;

  FPeakListFirstIndex := FirstIndex;

  FPeakListRealCount := Length(Peaks);

  FPeakList.BeginUpdate;
  try
    FPeakList.Clear;

    { Ссылка "<<" в начало, если перед окном есть ещё элементы }
    if FirstIndex > 0 then
      FPeakList.Items.Add(Format('<<  (%d more)', [FirstIndex]));

    for I := 0 to High(Peaks) do
      FPeakList.Items.Add(Peaks[I].Position.ToString);

    { Ссылка ">>" в конец, если после окна есть ещё элементы }
    if LastIndex < Total - 1 then
      FPeakList.Items.Add(Format('>>  (%d more)', [Total - 1 - LastIndex]));
  finally
    FPeakList.EndUpdate;
  end;
end;

procedure TMainForm.FillPeakListAroundFrame(AFrame: Int64);
const
  HalfWindow = 100;
var
  Total: Int64;
  L, R, Mid: Int64;
  Pos: Int64;
  BestIndex: Int64;
  BestDistance: Int64;
  Distance: Int64;

  WindowFirst: Int64;
  WindowCount: Int64;

  Peaks: TPeakArray;

  ListIndex: Integer;
begin
  Total := FSession.PeakCount;

  if Total <= 0 then
  begin
    FPeakList.Clear;
    FPeakListFirstIndex := 0;
    FPeakListRealCount := 0;
    Exit;
  end;

  { ------------------------------------------------------------
    Ищем первый peak с Position >= AFrame.
    Работаем только через TEodGuiSession.
    ------------------------------------------------------------ }

  L := 0;
  R := Total - 1;

  while L < R do
  begin
    Mid := L + (R - L) div 2;

    Pos := FSession.GetPeakPosition(Integer(Mid));

    if Pos < 0 then
      Exit;

    if Pos < AFrame then
      L := Mid + 1
    else
      R := Mid;
  end;

  BestIndex := L;

  { Проверяем ближайший peak слева. }

  Pos := FSession.GetPeakPosition(Integer(L));

  if Pos < 0 then
    Exit;

  BestDistance := Abs(Pos - AFrame);

  if L > 0 then
  begin
    Pos := FSession.GetPeakPosition(Integer(L - 1));

    if Pos < 0 then
      Exit;

    Distance := Abs(Pos - AFrame);

    if Distance < BestDistance then
    begin
      BestDistance := Distance;
      BestIndex := L - 1;
    end;
  end;

  { ------------------------------------------------------------
    Если найденный peak уже находится в ListBox —
    просто выделяем его.
    ------------------------------------------------------------ }

  if (FPeakListRealCount > 0) and
     (BestIndex >= FPeakListFirstIndex) and
     (BestIndex < FPeakListFirstIndex + FPeakListRealCount) then
  begin
    ListIndex := Integer(BestIndex - FPeakListFirstIndex);

    if FPeakListFirstIndex > 0 then
      Inc(ListIndex);

    if (ListIndex >= 0) and
       (ListIndex < FPeakList.Count) then
      FPeakList.ItemIndex := ListIndex;

    Exit;
  end;

  { ------------------------------------------------------------
    Загружаем окно вокруг найденного peak.
    ------------------------------------------------------------ }

  WindowFirst := Max(Int64(0), BestIndex - HalfWindow);

  WindowCount := Min(
    Int64(HalfWindow * 2 + 1),
    Total - WindowFirst);

  if WindowCount <= 0 then
    Exit;

  if not FSession.ReadPeakInfoRange(
    WindowFirst,
    WindowCount,
    Peaks) then
    Exit;

  PopulatePeakListRange(
    Peaks,
    WindowFirst,
    Total);

  { ------------------------------------------------------------
    Выделяем найденный peak.
    ------------------------------------------------------------ }

  if (BestIndex >= WindowFirst) and
     (BestIndex < WindowFirst + Length(Peaks)) then
  begin
    ListIndex := Integer(BestIndex - WindowFirst);

    if WindowFirst > 0 then
      Inc(ListIndex);

    if (ListIndex >= 0) and
       (ListIndex < FPeakList.Count) then
      FPeakList.ItemIndex := ListIndex;
  end;
end;

procedure TMainForm.FSettingsButtonClick(Sender: TObject);
var
  Dlg: TEodSettingsForm;
  NewConfig: TEodDetectorConfig;
begin
  if Assigned(FAnalysis) then
  begin
    UpdateStatus('Cannot change settings while analysis is running.');
    Exit;
  end;

  Dlg := TEodSettingsForm.CreateWithConfig(Self, FConfig);
  try
    if Dlg.Execute(NewConfig) then
    begin
      FConfig := NewConfig;

      FDetector.Free;
      FDetector := TEodDetector.Create(FConfig);

      SaveDetectorConfig(GetDefaultConfigFileName, FConfig);
      UpdateStatus('Settings saved to ' + GetDefaultConfigFileName);
    end;
  finally
    Dlg.Free;
  end;
end;

end.
