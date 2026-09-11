unit uReadWavMain;

interface

uses
  System.SysUtils, System.Types, System.UITypes,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.StdCtrls, FMX.Objects, FMX.Edit,
  FMX.ListBox, FMX.Layouts, FMX.Dialogs, FMX.SpinBox
, System.Classes, FMX.Controls.Presentation
, Eod.AnalysisThread
, Eod.Types
, Eod.Detector
, Eod.PeakStore
, Eod.GuiModel
, Eod.GuiPlot
, Eod.WavOpenThread
, Eod.ConfigStore, Eod.SettingsForm
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

    FPeakListFirstIndex: Integer;

    FPeakListRealCount: Integer;

    FWheelAccumulator: Integer;

    FLastDir: string;

    procedure OverviewClick(Sender: TObject; Frame: Int64);
    procedure OverviewRangeSelected(Sender: TObject; AStart, AEnd: Int64);

    procedure BuildOverview;

    procedure UpdateOverviewView(ViewStart, ViewEnd: Int64);

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

  FStatus.Text := '';
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

procedure TMainForm.FOpenPeakButtonClick(Sender: TObject);
var
  D: TOpenDialog;
  StartFrame, EndFrame: Int64;
begin
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

    D.Title := 'Open Tr34 WAV';
    if not D.Execute then
      Exit;

    File2 := D.FileName;
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
      D.FileName := ChangeFileExt(ExtractFileName(FSession.File1), '.eodpk')
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
        end;

        StartFrame := EndFrame + 1;
      end;

      FOverviewMin[I] := -VMax;
      FOverviewMax[I] := VMax;
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
  end;

  FOverview.SetData(FOverviewMin, FOverviewMax, 0, TotalFrames - 1);

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
