unit uReadWavMain;

interface

uses
  System.SysUtils, System.Types, System.UITypes,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.StdCtrls, FMX.Objects, FMX.Edit,
  FMX.ListBox, FMX.Layouts, FMX.Dialogs, FMX.SpinBox
, System.Classes, FMX.Controls.Presentation
, Core.Types
, Detection.Detector
, IO.PeakStore
, GUI.Model
, GUI.Plot
, GUI.Playback
, GUI.PeakList
, GUI.Analysis
, Core.ConfigStore, GUI.SettingsForm
, GUI.FileNaming
, FMX.Menus
, Electrode.LayoutForm
, GUI.VideoExportForm
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
    lbPeakList: TListBox;
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
    MainMenu1: TMainMenu;
    btGeometry: TButton;
    btVideoExport: TButton;
    layLeft: TLayout;
    cbBucketModeBox: TComboBox;
    cbOverviewLookBox: TComboBox;
    procedure btGeometryClick(Sender: TObject);
    procedure btVideoExportClick(Sender: TObject);
    procedure cbBucketModeBoxChange(Sender: TObject);
    procedure cbOverviewLookBoxChange(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FAnalyzeButtonClick(Sender: TObject);
    procedure FApplyButtonClick(Sender: TObject);
    procedure FModeBoxChange(Sender: TObject);
    procedure FNextButtonClick(Sender: TObject);
    procedure FOpenPeakButtonClick(Sender: TObject);
    procedure FOpenWavButtonClick(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure lbPeakListMouseDown(Sender: TObject; Button: TMouseButton;
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
    procedure lbPeakListClick(Sender: TObject);
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
    FBackground: TEodAnalysisController;

    FOverview: TOverviewPlot;

    FOverviewMin: TFloatArray;
    FOverviewMax: TFloatArray;

    { Поканальные огибающие обзорного графика (индекс 0..3 — канал 1..4)
      для режима OverviewChannelColors. }
    FOverviewChMin: TChannelEnvelopes;
    FOverviewChMax: TChannelEnvelopes;
    FOverviewChannelColors: Boolean;

    FPeakList: TEodPeakList;

    FPlayer: TEodPlayer;

    FWheelAccumulator: Integer;

    FLastDir: string;

    procedure ApplyPlaybackSpeed;

    procedure OverviewClick(Sender: TObject; Frame: Int64);
    procedure OverviewRangeSelected(Sender: TObject; AStart, AEnd: Int64);

    procedure StartOverview;
    procedure OverviewProgress(Sender: TObject; Processed, Total: Int64);
    procedure OverviewFinished(Sender: TObject;
      const OverviewMin, OverviewMax: TFloatArray;
      const ChannelMin, ChannelMax: TChannelEnvelopes;
      TotalFrames: Int64; Canceled: Boolean;
      const ErrorText: string);

    procedure PeakOverviewProgress(Sender: TObject; Processed, Total: Int64);
    procedure PeakOverviewFinished(Sender: TObject;
      const OverviewMin, OverviewMax: TFloatArray;
      const ChannelMin, ChannelMax: TChannelEnvelopes;
      TotalFrames: Int64; Canceled: Boolean;
      const ErrorText: string);
    procedure StartPeakOverview(const AFileName: string);

    procedure UpdateOverviewView(ViewStart, ViewEnd: Int64);

    procedure SetOverviewChannelColors(AValue: Boolean);

    procedure UpdateStatus(const S: string);
    procedure UpdateCaption;
    procedure ShowPeak(Index: Integer);
    procedure ShowRawPosition(AStartFrame, AEndFrame: Int64);
    procedure ShowPeakFileRange(AStartFrame, AEndFrame: Int64);
    function CurrentFrame: Int64;
    function ReadInt64Edit(AEdit: TEdit; const ADefault: Int64): Int64;
    procedure SetRangeEdits(AStart, AEnd: Int64);
    procedure UpdateRangeDisplay;
    procedure StartAnalysis(MaxFrames: Int64);
    procedure AnalysisProgress(Sender: TObject; Processed, Total: Int64);
    procedure AnalysisFinished(Sender: TObject; const Peaks: TPeakArray;
      Canceled: Boolean; const ErrorText: string);
    procedure OpenProgress(Stage: Integer; const Text: string);
    procedure OpenFinished(Session: TEodGuiSession;
      Canceled: Boolean; const ErrorText: string);
    procedure SetAnalysisUiState(Analyzing: Boolean);
    procedure BackgroundCloseRequest(Sender: TObject);
    procedure UpdatePlotMode;
    procedure PlotViewChanged(Sender: TObject; ViewStart, ViewEnd: Int64);
    { Обзорный график в цветах каналов 1..4 (как у основного графика).
      Поканальные огибающие строит BuildOverview, поэтому переключение
      не перечитывает файл. }
    property OverviewChannelColors: Boolean
      read FOverviewChannelColors write SetOverviewChannelColors;
    procedure ApplyOverviewLook;
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

  { Владелец фоновых воркеров (GUI.Analysis.pas). Реакция на прогресс и
    результаты остаётся здесь, в форме; контроллер лишь дергает события. }
  FBackground := TEodAnalysisController.Create;
  FBackground.OnAnalysisProgress := AnalysisProgress;
  FBackground.OnAnalysisFinished := AnalysisFinished;
  FBackground.OnOpenProgress := OpenProgress;
  FBackground.OnOpenFinished := OpenFinished;
  FBackground.OnOverviewProgress := OverviewProgress;
  FBackground.OnOverviewFinished := OverviewFinished;
  FBackground.OnPeakOverviewProgress := PeakOverviewProgress;
  FBackground.OnPeakOverviewFinished := PeakOverviewFinished;
  FBackground.OnCloseRequest := BackgroundCloseRequest;

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

  { edRange — производный индикатор только для чтения: End - Start.
    Обработчики назначены кодом, а не через .fmx, чтобы не зависеть от
    того, привязал ли их дизайнер формы. }
  edRange.ReadOnly := True;
  edStartSample.OnChange := edStartSampleChange;
  edEndSample.OnChange := edEndSampleChange;

  FPeakList := TEodPeakList.Create(lbPeakList, FSession,
    procedure(Index: Integer)
    begin
      ShowPeak(Index);
    end,
    procedure(const S: string)
    begin
      edEndSample.Text := S;
    end);
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

  { Плеер (GUI.Playback.pas) работает кодами: сам ведёт таймер и не знает
    ни о форме, ни о ListBox; весь обмен — через колбэки ниже. }
  FPlayer := TEodPlayer.Create(FSession,
    procedure(Index: Integer)
    begin
      ShowPeak(Index);
    end,
    procedure(const S: string)
    begin
      UpdateStatus(S);
    end,
    function: Int64
    begin
      Result := CurrentFrame;
    end,
    function: Integer
    begin
      Result := FCurrentPeak;
    end,
    procedure(P: Double)
    begin
      FUpdating := True;
      try
        FPositionBar.Value := P * 1000;
      finally
        FUpdating := False;
      end;
    end,
    procedure(Active: Boolean)
    begin
      if Active then
        FPlayButton.Text := 'Stop'
      else
      begin
        FPlayButton.Text := 'Play';
        { Во время плея список не обновлялся — синхронизируем его один раз
          с последним показанным пиком. }
        if (FCurrentPeak >= 0) and (FCurrentPeak < FSession.PeakCount) then
          FPeakList.FillAroundFrame(FSession.GetPeakPosition(FCurrentPeak));
      end;
    end);

  ApplyPlaybackSpeed;

  FStatus.Text := '';

  OverviewChannelColors :=true;
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  { Обычно к этому моменту воркеры уже завершены: FormCloseQuery не даёт
    дойти до FormDestroy, пока работает хотя бы один. }
  FBackground.CancelAll;
  FBackground.Free;
  FBackground := nil;

  FPlayer.Free;
  FPlayer := nil;

  FPeakList.Free;
  FPeakList := nil;

  FOverview.Free;
  FOverview := nil;

  FPlot.Free;
  FPlot := nil;

  FDetector.Free;
  FSession.Free;
end;

procedure TMainForm.BackgroundCloseRequest(Sender: TObject);
begin
  Close;
end;

procedure TMainForm.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  { Плеер живёт только в главном потоке — его достаточно просто остановить. }
  FPlayer.Stop(False);

  if FBackground.AnyRunning then
  begin
    FBackground.CancelAll;
    CanClose := False;
    UpdateStatus('Stopping background operation...');
    Exit;
  end;

  CanClose := True;
end;

procedure TMainForm.AnalysisFinished(Sender: TObject; const Peaks: TPeakArray;
  Canceled: Boolean; const ErrorText: string);
begin
  if FBackground.Closing then
    Exit;

  if Canceled then
  begin
    FSession.SetPeaks(nil);
    FCurrentPeak := -1;
    lbPeakList.Clear;
    UpdateStatus('Analysis cancelled.');
  end
  else if ErrorText <> '' then
  begin
    FSession.SetPeaks(nil);
    FCurrentPeak := -1;
    lbPeakList.Clear;
    UpdateStatus('Analysis error: ' + ErrorText);
  end
  else
  begin
    FSession.SetPeaks(Peaks);
    FPeakList.FillAroundFrame(FSession.GetPeakPosition(0));

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
  if FBackground.Closing then
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

procedure TMainForm.SetAnalysisUiState(Analyzing: Boolean);
begin
  if Analyzing then
    { Анализ/открытие WAV ломает текущую сессию — плей останавливаем. }
    FPlayer.Stop(False);

  FOpenWavButton.Enabled := not Analyzing;
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

procedure TMainForm.OpenProgress(Stage: Integer;
  const Text: string);
begin
  if FBackground.Closing then
    Exit;
  UpdateStatus(Format('Opening WAV: %d%% - %s', [Stage, Text]));
end;

procedure TMainForm.OpenFinished(Session: TEodGuiSession;
  Canceled: Boolean; const ErrorText: string);
var
  OldSession: TEodGuiSession;
begin
  if FBackground.Closing then
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
  FPlayer.Session := FSession;
  FPeakList.Session := FSession;
  if FSession.TotalFrames > 0 then
  begin
    { В режиме WAV под вид выделяется сырой буфер, поэтому максимальная
      ширина вида ограничена — иначе при отдалении будут огромные
      аллокации. }
    FPlot.SetMaxViewSamples(MaxViewSamples);
    FPlot.SetFullRange(0, FSession.TotalFrames - 1);
  end;

  StartOverview;
  OldSession.Free;

  FSession.SetPeaks(nil);
  FCurrentPeak := -1;
  FCurrentStart := 0;
  FCurrentCount := 201;

  FPeakList.FillFirstPage;
  SetAnalysisUiState(False);

  SetRangeEdits(0, 200);

  ShowRawPosition(0, 200);

  UpdateStatus(Format('WAV: %.3f sec, %d Hz, %d frames',
    [FSession.TotalFrames / FSession.SampleRate, FSession.SampleRate,
    FSession.TotalFrames]));

  UpdateCaption;
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
  InfoText: string;
begin
  NameText := '';
  InfoText := '';

  if Assigned(FSession) then
    case FSession.Mode of
      dmWav:
        begin
          if FSession.File1 <> '' then
            NameText := ExtractFileName(FSession.File1) + ' + ' +
              ExtractFileName(FSession.File2);

          if (FSession.SampleRate > 0) and (FSession.TotalFrames > 0) then
            InfoText := Format('%.3f s | %d Hz | %d frames',
              [FSession.TotalFrames / FSession.SampleRate,
               FSession.SampleRate,
               FSession.TotalFrames]);
        end;

      dmPeakFile:
        begin
          if FSession.PeakFile <> '' then
            NameText := ExtractFileName(FSession.PeakFile);

          if (FSession.SampleRate > 0) and (FSession.TotalFrames > 0) then
            InfoText := Format('%d Hz | %d frames | %d peaks',
              [FSession.SampleRate,
               FSession.TotalFrames,
               FSession.PeakCount]);
        end;
    end;

  if NameText = '' then
    Caption := 'EOD Viewer'
  else if InfoText = '' then
    Caption := 'EOD Viewer - ' + NameText
  else
    Caption := 'EOD Viewer - ' + NameText + ' | ' + InfoText;

  FOpenFolderButton.Enabled := NameText <> '';
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
begin
  if (Index < 0) or (Index >= FSession.PeakCount) then
    Exit;

  { Убран ручной ItemIndex — теперь делает TEodPeakList.FillAroundFrame }

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

  UpdatePlotMode;

  FPlot.SetViewRange(StartFrame, StartFrame + Length(Data) - 1);

  { Синхронизируем красный прямоугольник выделения на обзорном графике
    с новым диапазоном отображения. SetViewRange не вызывает OnViewChanged,
    поэтому обновляем обзор вручную. }
  UpdateOverviewView(StartFrame, StartFrame + Length(Data) - 1);

  UpdateStatus(Format('Peak %d/%d: sample %d, time %.6f s, prominence %.6f',
    [Index + 1, FSession.PeakCount, Peak.Position,
    Peak.Position / FSession.SampleRate, Peak.Prominence]));

  { Перезаполняем ListBox только если нужно, иначе просто подсвечиваем.
    Во время воспроизведения список не трогаем: обновление на каждый пик
    тормозит плей; при остановке список синхронизируется один раз
    (колбэк состояния плеера в FormCreate). }
  if not FPlayer.Active then
    FPeakList.FillAroundFrame(Peak.Position);
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
  { Малый диапазон: сохраняем точный вид сигнала. }
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
  { Большой диапазон: TAudioChunk под диапазон НЕ создаём никогда. }
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

  { STD/FIR здесь бессмысленны без восстановления сырого сигнала. }
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
  if FBackground.AnalysisRunning then
    Exit;

  lbPeakList.Clear;
  FSession.SetPeaks(nil);
  FCurrentPeak := -1;

  SetAnalysisUiState(True);
  UpdateStatus('Starting analysis...');

  FBackground.StartAnalysis(FSession.File1, FSession.File2, FConfig, MaxFrames);
end;


procedure TMainForm.FAnalyzeButtonClick(Sender: TObject);
var
  SecondsText: string;
  MaxFrames: Int64;
begin
  { Та же кнопка служит командой немедленной отмены, пока работает воркер.
    WaitFor здесь не вызываем — интерфейс остаётся отзывчивым. }
  if FBackground.AnalysisRunning then
  begin
    FBackground.CancelAnalysis;
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
{  Воспроизведение (код в GUI.Playback.pas — TEodPlayer)             }
{ ================================================================== }

procedure TMainForm.ApplyPlaybackSpeed;
begin
  case FPlaySpeedBox.ItemIndex of
    0: FPlayer.Speed := 0.1;
    1: FPlayer.Speed := 0.25;
    2: FPlayer.Speed := 0.5;
    4: FPlayer.Speed := 2.0;
    5: FPlayer.Speed := 5.0;
    6: FPlayer.Speed := 10.0;
  else
    FPlayer.Speed := 1.0;
  end;
end;

procedure TMainForm.PlaySpeedBoxChange(Sender: TObject);
begin
  ApplyPlaybackSpeed;
end;

procedure TMainForm.FPlayButtonClick(Sender: TObject);
begin
  if FPlayer.Active then
    FPlayer.Stop(False)
  else
    FPlayer.Start;
end;

procedure TMainForm.FOpenPeakButtonClick(Sender: TObject);
var
  D: TOpenDialog;
  StartFrame, EndFrame: Int64;
begin
  FPlayer.Stop(False);

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
      { EODPK рисуется только по компактной огибающей (полный сырой буфер
        не создаётся), поэтому файл можно показать целиком. Разрешаем
        отдалять вид до всего файла. }
      FPlot.SetMaxViewSamples(FSession.TotalFrames);
      FPlot.SetFullRange(0, FSession.TotalFrames - 1);
    end;

    StartPeakOverview(D.FileName);

    FCurrentPeak := -1;

    FPeakList.FillFirstPage;

    if FSession.PeakCount > 0 then
    begin
      StartFrame := FSession.GetPeakPosition(0) - 200;
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
  if FBackground.OpenRunning or FBackground.AnalysisRunning then
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

  FBackground.StartOpenWav(File1, File2);

  SetAnalysisUiState(True);
  FAnalyzeButton.Enabled := False;
  FOpenPeakButton.Enabled := False;
  FSaveButton.Enabled := False;
  UpdateStatus('Opening WAV in background...');
end;

procedure TMainForm.lbPeakListMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Single);
begin
  if Button = TMouseButton.mbRight then
    FPeakList.HandleRightClick;
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
  if FBackground.AnalysisRunning then
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
  FPeakList.FillAroundFrame(Frame);
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

procedure TMainForm.FSettingsButtonClick(Sender: TObject);
var
  Dlg: TEodSettingsForm;
  NewConfig: TEodDetectorConfig;
begin
  if FBackground.AnalysisRunning then
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

procedure TMainForm.StartOverview;
begin
  if FBackground.Closing or (FSession.Mode <> dmWav) then
    Exit;

  FOverview.Clear;

  UpdateStatus('Building overview in background...');

  FBackground.StartOverview(FSession.File1, FSession.File2);
end;

procedure TMainForm.OverviewProgress(Sender: TObject;
  Processed, Total: Int64);
var
  Percent: Integer;
begin
  if FBackground.Closing then
    Exit;

  if Total > 0 then
    Percent := Round(Processed * 100.0 / Total)
  else
    Percent := 0;

  if Percent < 0 then
    Percent := 0
  else if Percent > 100 then
    Percent := 100;

  UpdateStatus(Format('Building overview: %d%%', [Percent]));
end;

procedure TMainForm.OverviewFinished(Sender: TObject;
  const OverviewMin, OverviewMax: TFloatArray;
  const ChannelMin, ChannelMax: TChannelEnvelopes;
  TotalFrames: Int64; Canceled: Boolean;
  const ErrorText: string);
begin
  if FBackground.Closing then
    Exit;

  if Canceled then
  begin
    UpdateStatus('Overview building cancelled.');
    Exit;
  end;

  if ErrorText <> '' then
  begin
    UpdateStatus('Overview error: ' + ErrorText);
    Exit;
  end;

  FOverviewMin := Copy(OverviewMin);
  FOverviewMax := Copy(OverviewMax);
  FOverviewChMin := ChannelMin;
  FOverviewChMax := ChannelMax;

  FOverview.SetData(
    FOverviewMin,
    FOverviewMax,
    0,
    TotalFrames - 1);

  FOverview.SetChannelData(
    FOverviewChMin,
    FOverviewChMax,
    0,
    TotalFrames - 1);

  FOverview.SetViewRange(
    0,
    Min(TotalFrames - 1, FPlot.ViewSampleCount));

  ApplyOverviewLook;

  UpdateStatus(Format(
    'WAV: %.3f sec, %d Hz, %d frames',
    [FSession.TotalFrames / FSession.SampleRate,
     FSession.SampleRate,
     FSession.TotalFrames]));
end;

procedure TMainForm.StartPeakOverview(const AFileName: string);
var
  Ch: Integer;
begin
  if FBackground.Closing then
    Exit;

  if FBackground.OverviewRunning then
  begin
    FBackground.CancelOverview;
    Exit;
  end;

  if AFileName = '' then
    Exit;

  FOverviewMin := nil;
  FOverviewMax := nil;

  for Ch := 0 to 3 do
  begin
    FOverviewChMin[Ch] := nil;
    FOverviewChMax[Ch] := nil;
  end;

  UpdateStatus('Building EODPK overview...');

  FBackground.StartPeakOverview(AFileName, cbBucketModeBox.ItemIndex = 0);
end;

procedure TMainForm.PeakOverviewFinished(Sender: TObject;
  const OverviewMin, OverviewMax: TFloatArray;
  const ChannelMin, ChannelMax: TChannelEnvelopes;
  TotalFrames: Int64; Canceled: Boolean;
  const ErrorText: string);
var
  I: Integer;
begin
  if FBackground.Closing then
    Exit;

  if Canceled then
  begin
    UpdateStatus('EODPK overview cancelled.');
    Exit;
  end;

  if ErrorText <> '' then
  begin
    UpdateStatus('EODPK overview error: ' + ErrorText);
    Exit;
  end;

  FOverviewMin := OverviewMin;
  FOverviewMax := OverviewMax;

  for I := 0 to 3 do
  begin
    FOverviewChMin[I] := ChannelMin[I];
    FOverviewChMax[I] := ChannelMax[I];
  end;

  if (TotalFrames > 0) and (Length(FOverviewMin) > 0) then
    begin
      FOverview.SetData(
        FOverviewMin,
        FOverviewMax,
        0,
        TotalFrames - 1);

      FOverview.SetChannelData(
        FOverviewChMin,
        FOverviewChMax,
        0,
        TotalFrames - 1);

      FOverview.SetViewRange(
        0,
        Min(TotalFrames - 1, FPlot.ViewSampleCount));
    end;


//  FOverview.ChannelColors := FOverviewChannelColors;
  ApplyOverviewLook;
  if (TotalFrames > 0) and (Length(FOverviewMin) > 0) then
    UpdateOverviewView(0, TotalFrames - 1);

  UpdateStatus(Format('EODPK overview ready: %d frames',
    [TotalFrames]));
end;


procedure TMainForm.PeakOverviewProgress(Sender: TObject; Processed,
  Total: Int64);
var
  Percent: Integer;
begin
  if FBackground.Closing then
    Exit;

  if Total > 0 then
    Percent := Round(Processed * 100.0 / Total)
  else
    Percent := 0;

  if Percent < 0 then
    Percent := 0
  else if Percent > 100 then
    Percent := 100;

  UpdateStatus(Format('Building overview: %d%%', [Percent]));
end;

procedure TMainForm.btGeometryClick(Sender: TObject);
begin
  ShowElectrodeLayoutForm
end;

procedure TMainForm.btVideoExportClick(Sender: TObject);
var
  SessionData: TVideoExportSessionData;
begin
  if FSession.Mode = dmNone then
  begin
    UpdateStatus('Сначала откройте WAV или .eodpk.');
    Exit;
  end;

  if Length(FOverviewMin) = 0 then
  begin
    UpdateStatus('Обзорный график ещё не построен — дождитесь его загрузки.');
    Exit;
  end;

  { Экспорт видео использует уже посчитанную для экранного обзорного
    графика огибающую (FOverviewMin/Max/ChMin/ChMax) — тот же массив,
    что рисует FOverview на главной форме, повторный проход по файлу
    не требуется. }
  SessionData.SampleRate := FSession.SampleRate;
  SessionData.TotalFrames := FSession.TotalFrames;
  SessionData.EnvelopeMin := FOverviewMin;
  SessionData.EnvelopeMax := FOverviewMax;
  SessionData.ChannelMin := FOverviewChMin;
  SessionData.ChannelMax := FOverviewChMax;
  SessionData.ChannelColors := FOverviewChannelColors;

  ShowVideoExportForm(Self, SessionData);

end;

procedure TMainForm.cbBucketModeBoxChange(Sender: TObject);
begin
  { Режим бакетов применяется при построении обзора EODPK, поэтому
    строим заново (для EODPK это быстрое чтение кэша). }
  if FSession.Mode = dmPeakFile then
    StartPeakOverview(FSession.PeakFile);
end;

procedure TMainForm.cbOverviewLookBoxChange(Sender: TObject);
begin
  ApplyOverviewLook;
end;

procedure TMainForm.ApplyOverviewLook;
begin
  if not Assigned(FOverview) then
    Exit;

  { Обзор ещё не построен — запоминаем только режим цвета. }
  if (Length(FOverviewChMin[0]) = 0) or (FSession.TotalFrames <= 0) then
  begin
    OverviewChannelColors := cbOverviewLookBox.ItemIndex = 0;
    Exit;
  end;

  if cbOverviewLookBox.ItemIndex = 0 then
    OverviewChannelColors := True
  else
  begin
    { Общая огибающая выводится из поканальной — пересчёт обзора не нужен. }
    BuildGeneralEnvelope(FOverviewChMin, FOverviewChMax,
      cbOverviewLookBox.ItemIndex = 1, FOverviewMin, FOverviewMax);
    FOverview.SetData(FOverviewMin, FOverviewMax, 0,
      FSession.TotalFrames - 1);
    OverviewChannelColors := False;
  end;
end;

procedure TMainForm.lbPeakListClick(Sender: TObject);
begin
  FPeakList.HandleClick;
end;

end.
