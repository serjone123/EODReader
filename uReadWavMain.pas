unit uReadWavMain;

interface

uses
  System.SysUtils, System.Types, System.UITypes,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.StdCtrls, FMX.Objects, FMX.Edit,
  FMX.ListBox, FMX.Layouts, FMX.Dialogs, FMX.SpinBox,
  Eod.Types, Eod.Detector, Eod.PeakStore, Eod.GuiModel, Eod.GuiPlot,
  System.Classes, FMX.Controls.Presentation,
  Eod.AnalysisThread, Eod.WavOpenThread;

type
  TMainForm = class(TForm)
    Layout1: TLayout;
    FOpenWavButton: TButton;
    FOpenPeakButton: TButton;
    FAnalyzeButton: TButton;
    FSaveButton: TButton;
    FPrevButton: TButton;
    FNextButton: TButton;
    FApplyButton: TButton;
    FSelectRangeButton: TButton;
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
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FSelectRangeButtonClick(Sender: TObject);
    procedure FAnalyzeButtonClick(Sender: TObject);
    procedure FApplyButtonClick(Sender: TObject);
    procedure FModeBoxChange(Sender: TObject);
    procedure FNextButtonClick(Sender: TObject);
    procedure FOpenPeakButtonClick(Sender: TObject);
    procedure FOpenWavButtonClick(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure FPeakListClick(Sender: TObject);
    procedure FPeakListMouseDown(Sender: TObject; Button: TMouseButton; Shift:
        TShiftState; X, Y: Single);
    procedure FPositionBarChange(Sender: TObject);
    procedure FPrevButtonClick(Sender: TObject);
    procedure FSaveButtonClick(Sender: TObject);
    procedure edStartSampleMouseWheel(Sender: TObject; Shift: TShiftState;
      WheelDelta: Integer; var Handled: Boolean);
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

    procedure OverviewClick(Sender: TObject; Frame: Int64);

    procedure BuildOverview;

    procedure UpdateOverviewView(ViewStart, ViewEnd: Int64);

    procedure FillPeakListAroundFrame(AFrame: Int64);
    procedure UpdateStatus(const S: string);
    procedure ShowPeak(Index: Integer);
    procedure ShowRawPosition(AStartFrame, AEndFrame: Int64);
    procedure ShowPeakFileRange(AStartFrame, AEndFrame: Int64);
    procedure ShowCurrentRange;
    function CurrentFrame: Int64;
    function ReadInt64Edit(AEdit: TEdit; const ADefault: Int64): Int64;
    function ReadRange: Integer;
    procedure FillPeakList;
    procedure StartAnalysis(MaxFrames: Int64);
    procedure AnalysisProgress(Sender: TObject; Processed, Total: Int64);
    procedure AnalysisFinished(Sender: TObject; const Peaks: TPeakArray;
      Canceled: Boolean; const ErrorText: string);
    procedure AnalysisThreadTerminated(Sender: TObject);
    procedure OpenProgress(Sender: TObject; Stage: Integer; const Text: string);
    procedure OpenFinished(Sender: TObject; Session: TEodGuiSession; Canceled: Boolean; const ErrorText: string);
    procedure OpenThreadTerminated(Sender: TObject);
    procedure SetAnalysisUiState(Analyzing: Boolean);
    procedure UpdatePlotMode;
    procedure PlotViewChanged(Sender: TObject; ViewStart, ViewEnd: Int64);
//    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; var Handled: Boolean): Boolean; override;
  public
  end;

var
  MainForm: TMainForm;

implementation

uses
  System.Math;

{$R *.fmx}
procedure TMainForm.FormCreate(Sender: TObject);
begin
  Caption := 'EOD Viewer';
  Position := TFormPosition.ScreenCenter;

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

//RAW (4 channels)
//STD
//FIR15
//RAW + FIR15
//RAW channels separate
//IPI histogram

  FModeBox.ItemIndex := 0;

  FPlot := TSignalPlot.Create(PaintBox);
  FPlot.OnViewChanged := PlotViewChanged;


  FOverview := TOverviewPlot.Create(OverviewPaintBox);
  FOverview.OnClick := OverviewClick;

  FPeakListFirstIndex := 0;
  FPeakListRealCount := 0;
  FWheelAccumulator := 0;
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


procedure TMainForm.AnalysisFinished(Sender: TObject;
  const Peaks: TPeakArray; Canceled: Boolean; const ErrorText: string);
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

procedure TMainForm.AnalysisProgress(Sender: TObject;
  Processed, Total: Int64);
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

  UpdateStatus(Format(
    'Analyzing: %d%%  (%d / %d frames)',
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
  edRange.Enabled := not Analyzing;
  FPositionBar.Enabled := not Analyzing;

  FAnalyzeButton.Enabled := True;

  if Analyzing then
    FAnalyzeButton.Text := 'Cancel analysis'
  else
    FAnalyzeButton.Text := 'Analyze WAV';
end;


procedure TMainForm.OpenProgress(Sender: TObject; Stage: Integer; const Text: string);
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
    FPlot.SetFullRange(0, FSession.TotalFrames - 1);

  BuildOverview;
  OldSession.Free;

  FSession.SetPeaks(nil);
  FCurrentPeak := -1;
  FCurrentStart := 0;
  FCurrentCount := 201;

  FillPeakList;
  SetAnalysisUiState(False);

  edStartSample.Text := '0';
  edRange.Text := '200';

  ShowRawPosition(0, 200);

  UpdateStatus(Format(
    'WAV: %.3f sec, %d Hz, %d frames',
    [FSession.TotalFrames / FSession.SampleRate,
     FSession.SampleRate,
     FSession.TotalFrames]));
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

  FUpdating := True;
  try
    edStartSample.Text := ViewStart.ToString;
    edRange.Text := ViewEnd.ToString;
  finally
    FUpdating := False;
  end;

  if FSession.Mode = dmWav then
    ShowRawPosition(ViewStart, ViewEnd)
  else if FSession.Mode = dmPeakFile then
    ShowPeakFileRange(ViewStart, ViewEnd);
end;

procedure TMainForm.FSelectRangeButtonClick(Sender: TObject);
var
  SelectedStart, SelectedEnd: Int64;
begin
  SelectedStart := ReadInt64Edit(edStartSample, 0);
  SelectedEnd := ReadInt64Edit(edRange, SelectedStart);

  if FSession.TotalFrames > 0 then
  begin
    SelectedStart := EnsureRange(SelectedStart, Int64(0), FSession.TotalFrames - 1);
    SelectedEnd := EnsureRange(SelectedEnd, SelectedStart, FSession.TotalFrames - 1);
  end;

end;


procedure TMainForm.UpdateStatus(const S: string);
begin
  FStatus.Text := S;
end;

procedure TMainForm.FillPeakList;
var
  I, MaxPeaks: Integer;
  P: TPeak;
  Peaks: TPeakArray;
begin
  FPeakList.BeginUpdate;
  try
    FPeakList.Clear;
    MaxPeaks := Min(FSession.PeakCount, 1000);

    if (FSession.Mode = dmPeakFile) and (MaxPeaks > 0) then
    begin
      if FSession.ReadPeakInfoPage(0, Peaks) then
      begin
        for I := 0 to Min(MaxPeaks, Length(Peaks)) - 1 do
          FPeakList.Items.Add(Peaks[I].Position.ToString);
      end;
    end
    else
    begin
      for I := 0 to MaxPeaks - 1 do
      begin
        if FSession.GetPeak(I, P) then
          FPeakList.Items.Add(P.Position.ToString);
      end;
    end;
  finally
    FPeakListFirstIndex := 0;
    FPeakListRealCount := FPeakList.Items.Count;  // <<< FIX
    FPeakList.EndUpdate;
  end;
end;
function TMainForm.ReadInt64Edit(AEdit: TEdit;
  const ADefault: Int64): Int64;
var
  V: Int64;
begin
  if TryStrToInt64(Trim(AEdit.Text), V) then
    Result := V
  else
    Result := ADefault;
end;

function TMainForm.ReadRange: Integer;
var
  V: Int64;
begin
  V := ReadInt64Edit(edRange, 200);

  if V < 1 then
    V := 1;

  if V > 1000000 then
    V := 1000000;

  Result := Integer(V);
end;

function TMainForm.CurrentFrame: Int64;
begin
  Result := ReadInt64Edit(edStartSample, 0);

  if FSession.TotalFrames > 0 then
    Result := EnsureRange(Result, 0, FSession.TotalFrames - 1)
  else
    Result := 0;
end;

//procedure TMainForm.edStartSampleMouseWheel(Sender: TObject; Shift: TShiftState;
//  WheelDelta: Integer; var Handled: Boolean);
//begin
//  case WheelDelta>0 of
//    true : FPrevButtonClick(self) ;
//    false: FNextButtonClick(self) ;
//  end;
//  Handled:=false;
//end;
procedure TMainForm.edStartSampleMouseWheel(Sender: TObject; Shift: TShiftState;
  WheelDelta: Integer; var Handled: Boolean);
const
  WHEEL_THRESHOLD = 120;  // один "щелчок" колеса = 120
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
//procedure TMainForm.ShowPeak(Index: Integer);
//var
//  Peak: TPeak;
//  StartFrame: Int64;
//  Data: TAudioChunk;
//  Std: TFloatArray;
//  Fir: TFloatArray;
//  Range: Integer;
//  PeakPositions: TArray<Int64>;
//begin
//  if (Index < 0) or (Index >= FSession.PeakCount) then
//    Exit;
//
////  FCurrentPeak := Index;
//if (Index >= FPeakListFirstIndex) and
//   (Index < FPeakListFirstIndex + FPeakList.Count) then
//begin
//  FPeakList.ItemIndex :=
//    Index - FPeakListFirstIndex;
//end;
//
//  if FSession.Mode = dmPeakFile then
//    Data := FSession.ReadPeak(Index, Peak, StartFrame)
//  else
//  begin
//    if not FSession.GetPeak(Index, Peak) then
//      Exit;
//    Range := 30;
//    StartFrame := Peak.Position - Range;
//    Data := FSession.ReadSegment(StartFrame, Range * 2 + 1, True);
//  end;
//
//  FCurrentStart := StartFrame;
//  FCurrentCount := Length(Data);
//
//  edStartSample.Text := Peak.Position.ToString;
////  FPeakList.ItemIndex := Index;
//
//  FCurrentPeak := Index;
//
//  FillPeakListAroundFrame(
//    Peak.Position);
//
//  Std := FSession.CalculateStd(Data);
//  Fir := FDetector.ApplyFir15(Std);
//
//  FPlot.SetChannels(
//    Data, StartFrame, FSession.SampleRate, Peak.Position,
//    Format('Peak #%d  sample %d',
//      [Index + 1, Peak.Position]));
//
//  FPlot.SetStd(
//    Std, StartFrame, FSession.SampleRate, Peak.Position,
//    'STD around peak');
//
//  FPlot.SetFir(
//    Fir, StartFrame, FSession.SampleRate, Peak.Position,
//    'FIR15 around peak');
//
//  PeakPositions := FSession.PeakPositions;
//  FPlot.SetPeakPositions(PeakPositions);
//  UpdatePlotMode;
//
//  FPlot.SetViewRange(StartFrame, StartFrame + Length(Data) - 1);
//
//  UpdateStatus(Format(
//    'Peak %d/%d: sample %d, time %.6f s, prominence %.6f',
//    [Index + 1, FSession.PeakCount, Peak.Position,
//     Peak.Position / FSession.SampleRate, Peak.Prominence]));
//end;
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

  edStartSample.Text := Peak.Position.ToString;

  FCurrentPeak := Index;

  Std := FSession.CalculateStd(Data);
  Fir := FDetector.ApplyFir15(Std);

  FPlot.SetChannels(
    Data, StartFrame, FSession.SampleRate, Peak.Position,
    Format('Peak #%d  sample %d', [Index + 1, Peak.Position]));

  FPlot.SetStd(
    Std, StartFrame, FSession.SampleRate, Peak.Position,
    'STD around peak');

  FPlot.SetFir(
    Fir, StartFrame, FSession.SampleRate, Peak.Position,
    'FIR15 around peak');

  PeakPositions := FSession.PeakPositions;
  FPlot.SetPeakPositions(PeakPositions);
  UpdatePlotMode;

  FPlot.SetViewRange(StartFrame, StartFrame + Length(Data) - 1);

  UpdateStatus(Format(
    'Peak %d/%d: sample %d, time %.6f s, prominence %.6f',
    [Index + 1, FSession.PeakCount, Peak.Position,
     Peak.Position / FSession.SampleRate, Peak.Prominence]));

  { Перезаполняем ListBox только если нужно, иначе просто подсвечиваем }
  FillPeakListAroundFrame(Peak.Position);
end;

procedure TMainForm.ShowPeakFileRange(AStartFrame, AEndFrame: Int64);
var
  StartFrame, EndFrame: Int64;
  Count64: Int64;
  Data: TAudioChunk;
  Std: TFloatArray;
  Fir: TFloatArray;
  Peak: TPeak;
  PeakStart: Int64;
  PeakEnd: Int64;
  CopyStart: Int64;
  CopyEnd: Int64;
  DestOffset: Int64;
  SourceOffset: Int64;
  CopyCount: Int64;
  I: Integer;
  Temp: TAudioChunk;
  PeakPositions: TArray<Int64>;
  FirstIdx, LastIdx: Integer;
begin
  if FSession.Mode <> dmPeakFile then
    Exit;

  if FSession.TotalFrames <= 0 then
    Exit;

  StartFrame := EnsureRange(AStartFrame, Int64(0), FSession.TotalFrames - 1);
  EndFrame := EnsureRange(AEndFrame, StartFrame, FSession.TotalFrames - 1);

  Count64 := EndFrame - StartFrame + 1;
  if Count64 > MaxInt then
    raise EArgumentOutOfRangeException.Create('Selected range is too large');

  SetLength(Data, Integer(Count64));
  if Length(Data) > 0 then
    FillChar(Data[0], Length(Data) * SizeOf(TAudioFrame), 0);

  if FSession.FindPeakRangeIndices(StartFrame, EndFrame, 30, FirstIdx, LastIdx) then
  begin
    for I := FirstIdx to LastIdx do
    begin
      Temp := FSession.ReadPeak(I, Peak, PeakStart);

      PeakEnd := PeakStart + Length(Temp) - 1;
      CopyStart := Max(StartFrame, PeakStart);
      CopyEnd := Min(EndFrame, PeakEnd);

      if CopyEnd < CopyStart then
        Continue;

      DestOffset := CopyStart - StartFrame;
      SourceOffset := CopyStart - PeakStart;
      CopyCount := CopyEnd - CopyStart + 1;

      Move(Temp[Integer(SourceOffset)], Data[Integer(DestOffset)],
        Integer(CopyCount) * SizeOf(TAudioFrame));
    end;
  end;

  FCurrentStart := StartFrame;
  FCurrentCount := Length(Data);

  Std := FSession.CalculateStd(Data);
  Fir := FDetector.ApplyFir15(Std);

  FPlot.SetChannels(
    Data, StartFrame, FSession.SampleRate, -1,
    Format('Samples %d .. %d', [StartFrame, EndFrame]));

  FPlot.SetStd(
    Std, StartFrame, FSession.SampleRate, -1,
    'STD');

  FPlot.SetFir(
    Fir, StartFrame, FSession.SampleRate, -1,
    'FIR15');

  PeakPositions := FSession.PeakPositions;
  FPlot.SetPeakPositions(PeakPositions);
  FPlot.SetSelectedPosition(StartFrame);
  FPlot.SetViewRange(StartFrame, EndFrame);
  FPlot.SetHistogramRange(StartFrame, EndFrame);

  edStartSample.Text := StartFrame.ToString;
  edRange.Text := EndFrame.ToString;

  UpdateStatus(Format(
    'EODPK samples %d .. %d  (%d samples, %.6f s .. %.6f s)',
    [StartFrame, EndFrame, Length(Data),
     StartFrame / FSession.SampleRate, EndFrame / FSession.SampleRate]));

  UpdatePlotMode;
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
begin
  if FSession.Mode <> dmWav then
    Exit;

  if FSession.TotalFrames <= 0 then
    Exit;

  StartFrame := EnsureRange(AStartFrame, Int64(0), FSession.TotalFrames - 1);
  EndFrame := EnsureRange(AEndFrame, StartFrame, FSession.TotalFrames - 1);

  Data := FSession.ReadSegment(
    StartFrame, EndFrame - StartFrame + 1, True);

  FCurrentStart := StartFrame;
  FCurrentCount := Length(Data);

  Std := FSession.CalculateStd(Data);
  Fir := FDetector.ApplyFir15(Std);

  FPlot.SetChannels(
    Data, StartFrame, FSession.SampleRate, -1,
    Format('Samples %d .. %d', [StartFrame, EndFrame]));

  FPlot.SetStd(
    Std, StartFrame, FSession.SampleRate, -1,
    'STD');

  FPlot.SetFir(
    Fir, StartFrame, FSession.SampleRate, -1,
    'FIR15');

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

  edStartSample.Text := StartFrame.ToString;
  edRange.Text := EndFrame.ToString;

  UpdateStatus(Format(
    'Samples %d .. %d  (%d samples, %.6f s .. %.6f s)',
    [StartFrame, EndFrame, Length(Data),
     StartFrame / FSession.SampleRate, EndFrame / FSession.SampleRate]));

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
  EndFrame := ReadInt64Edit(edRange, StartFrame);
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

  FAnalysis := TEodAnalysisThread.Create(
    FSession.File1,
    FSession.File2,
    FConfig,
    MaxFrames);

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
    ShowPeakFileRange(
      ReadInt64Edit(edStartSample, 0),
      ReadInt64Edit(edRange, ReadInt64Edit(edStartSample, 0)));
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

  SecondsText :=
    'Analyze the whole WAV now?' + sLineBreak +
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
    ShowPeakFileRange(
      ReadInt64Edit(edStartSample, 0),
      ReadInt64Edit(edRange, ReadInt64Edit(edStartSample, 0)));
    Exit;
  end;

  ShowRawPosition(
    ReadInt64Edit(edStartSample, 0),
    ReadInt64Edit(edRange, ReadInt64Edit(edStartSample, 0)));
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

    if not D.Execute then
      Exit;

    FSession.OpenPeakFile(D.FileName);

  if FSession.TotalFrames > 0 then
    FPlot.SetFullRange(0, FSession.TotalFrames - 1);

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
      edStartSample.Text := StartFrame.ToString;
      edRange.Text := EndFrame.ToString;
      ShowPeakFileRange(StartFrame, EndFrame);

    end
    else
    begin
      edStartSample.Text := '0';
      edRange.Text := '200';

    end;

//    UpdateStatus(Format(
//      'EODPK: %d peaks, %d Hz',
//      [FSession.PeakCount, FSession.SampleRate]));
      UpdateStatus(Format(
        'EODPK ver %d: %d peaks, %d Hz, %d frames',
        [FSession.Version, FSession.PeakCount,
         FSession.SampleRate, FSession.TotalFrames]));
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

    if not D.Execute then
      Exit;

    File1 := D.FileName;

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

procedure TMainForm.FormCloseQuery(Sender: TObject;
  var CanClose: Boolean);
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

//procedure TMainForm.FPeakListClick(Sender: TObject);
////begin
////  if FPeakList.ItemIndex >= 0 then
////    ShowPeak(FPeakList.ItemIndex);
//var
//  PeakIndex: Integer;
//begin
//  if FPeakList.ItemIndex < 0 then
//    Exit;
//
//  PeakIndex :=
//    FPeakListFirstIndex +
//    FPeakList.ItemIndex;
//
//  if (PeakIndex >= 0) and
//     (PeakIndex < FSession.PeakCount) then
//    ShowPeak(PeakIndex);
//end;
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
    PeakIndex := Min(FSession.PeakCount - 1,
      FPeakListFirstIndex + FPeakListRealCount);
    ShowPeak(PeakIndex);
    Exit;
  end;

  { Обычный пик }
  PeakIndex := FPeakListFirstIndex + FPeakList.ItemIndex;
  if FPeakListFirstIndex > 0 then
    Dec(PeakIndex);  // компенсация элемента "<<"

  if (PeakIndex >= 0) and (PeakIndex < FSession.PeakCount) then
  begin
    FCurrentPeak := PeakIndex;
    ShowPeak(PeakIndex);
  end;
end;
procedure TMainForm.FPeakListMouseDown(Sender: TObject; Button: TMouseButton;
    Shift: TShiftState; X, Y: Single);
begin
  if (Button=TMouseButton.mbRight) and (FPeakList.Selected<>nil) then
    edRange.Text:= FPeakList.Selected.Text;
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
  if P < 0 then P := 0 else if P > 1 then P := 1;

  if FSession.TotalFrames > 0 then
    Frame := Round(P * (FSession.TotalFrames - 1))
  else
    Frame := 0;

  ViewW := FPlot.ViewSampleCount;
  if ViewW <= 0 then
    ViewW := FCurrentCount;
  if ViewW <= 0 then
    ViewW := 200;

  FUpdating := True;
  try
    edStartSample.Text := Frame.ToString;
    edRange.Text := (Frame + ViewW).ToString;
  finally
    FUpdating := False;
  end;

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
    D.FileName := 'peaks.eodpk';

    if not D.Execute then
      Exit;

    UpdateStatus('Saving peaks...');
    Application.ProcessMessages;

    FSession.SavePeakFile(D.FileName);

    UpdateStatus('Saved: ' + D.FileName);
  finally
    D.Free;
  end;
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

  function FrameValue(
    const AFrame: TAudioFrame): Single;
  var
    A1, A2, A3, A4: Single;
  begin
    A1 := Abs(AFrame.Ch1);
    A2 := Abs(AFrame.Ch2);
    A3 := Abs(AFrame.Ch3);
    A4 := Abs(AFrame.Ch4);

    Result := Max(
      Max(A1, A2),
      Max(A3, A4));
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
  { WAV                                                              }
  { --------------------------------------------------------------- }

  if FSession.Mode = dmWav then
  begin
    for I := 0 to N - 1 do
    begin
      BinStart :=
        (Int64(I) * TotalFrames) div N;

      BinEnd :=
        (Int64(I + 1) * TotalFrames) div N - 1;

      if BinEnd < BinStart then
        BinEnd := BinStart;

      VMin := 0;
      VMax := 0;

      StartFrame := BinStart;

      while StartFrame <= BinEnd do
      begin
        EndFrame := Min(
          BinEnd,
          StartFrame + ChunkSize - 1);

        Count64 :=
          EndFrame - StartFrame + 1;

        if Count64 > MaxInt then
          Break;

        Data := FSession.ReadSegment(
          StartFrame,
          Integer(Count64),
          False);

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
  { EODPK                                                            }
  { --------------------------------------------------------------- }

  else if FSession.Mode = dmPeakFile then
  begin
    { Для EODPK используем peak records как источник сигнала. }

    for I := 0 to FSession.PeakCount - 1 do
    begin
      if not FSession.GetPeak(
        I,
        P)
      then
        Continue;

      if FSession.TotalFrames <= 1 then
        J := 0
      else
        J := EnsureRange(
          Integer(
            (P.Position * N) div TotalFrames),
          0,
          N - 1);

      V := Abs(P.Value);

      if V > FOverviewMax[J] then
        FOverviewMax[J] := V;

      if -V < FOverviewMin[J] then
        FOverviewMin[J] := -V;
    end;
  end;

  FOverview.SetData(
    FOverviewMin,
    FOverviewMax,
    0,
    TotalFrames - 1);

  FOverview.SetViewRange(
    0,
    Min(
      TotalFrames - 1,
      FPlot.ViewSampleCount));
end;

procedure TMainForm.UpdateOverviewView(
  ViewStart, ViewEnd: Int64);
begin
  if not Assigned(FOverview) then
    Exit;

  if FSession.Mode = dmNone then
    Exit;

  FOverview.SetViewRange(
    ViewStart,
    ViewEnd);
end;
//procedure TMainForm.OverviewClick(
//  Sender: TObject;
//  Frame: Int64);
//var
//  ViewWidth: Int64;
//  NewStart: Int64;
//  NewEnd: Int64;
//begin
//  if FSession.Mode = dmNone then
//    Exit;
//
//  if FSession.TotalFrames <= 0 then
//    Exit;
//
//  { Сохраняем текущий zoom }
//  ViewWidth := FPlot.ViewSampleCount;
//
//  if ViewWidth <= 0 then
//    ViewWidth := FCurrentCount;
//
//  if ViewWidth <= 0 then
//    ViewWidth := 201;
//
//  { Клик считается центром нового окна }
//  NewStart :=
//    Frame - ViewWidth div 2;
//
//  NewEnd :=
//    NewStart + ViewWidth;
//
//  { Ограничиваем окно границами файла }
//  if NewStart < 0 then
//  begin
//    NewStart := 0;
//    NewEnd := NewStart + ViewWidth;
//  end;
//
//  if NewEnd >= FSession.TotalFrames then
//  begin
//    NewEnd := FSession.TotalFrames - 1;
//    NewStart := NewEnd - ViewWidth;
//  end;
//
//  if NewStart < 0 then
//    NewStart := 0;
//
//  FUpdating := True;
//  try
//    edStartSample.Text := NewStart.ToString;
//    edRange.Text := NewEnd.ToString;
//  finally
//    FUpdating := False;
//  end;
//
//  if FSession.Mode = dmWav then
//    ShowRawPosition(
//      NewStart,
//      NewEnd)
//  else if FSession.Mode = dmPeakFile then
//    ShowPeakFileRange(
//      NewStart,
//      NewEnd);
//
//  FillPeakListAroundFrame(Frame);
//end;
procedure TMainForm.OverviewClick(Sender: TObject; Frame: Int64);
var
  ViewWidth: Int64;
  NewStart, NewEnd: Int64;
begin
  if FSession.Mode = dmNone then Exit;
  if FSession.TotalFrames <= 0 then Exit;

  ViewWidth := FPlot.ViewSampleCount;
  if ViewWidth <= 0 then ViewWidth := FCurrentCount;
  if ViewWidth <= 0 then ViewWidth := 201;

  NewStart := Frame - ViewWidth div 2;
  NewEnd   := NewStart + ViewWidth;

  if NewStart < 0 then begin NewStart := 0; NewEnd := NewStart + ViewWidth; end;
  if NewEnd >= FSession.TotalFrames then begin NewEnd := FSession.TotalFrames - 1; NewStart := NewEnd - ViewWidth; end;
  if NewStart < 0 then NewStart := 0;

  FUpdating := True;
  try
    edStartSample.Text := NewStart.ToString;
    edRange.Text := NewEnd.ToString;
  finally
    FUpdating := False;
  end;

  if FSession.Mode = dmWav then
    ShowRawPosition(NewStart, NewEnd)
  else if FSession.Mode = dmPeakFile then
    ShowPeakFileRange(NewStart, NewEnd);

  { <<< FIX: заставляем красный прямоугольник перерисоваться >>> }
  FPlot.GetViewRange(NewStart, NewEnd);
  UpdateOverviewView(NewStart, NewEnd);
end;
//procedure TMainForm.FillPeakListAroundFrame(
//  AFrame: Int64);
//var
//  Positions: TArray<Int64>;
//  L, R: Integer;
//  Mid: Integer;
//  I: Integer;
//  P: TPeak;
//begin
//  if FSession.PeakCount <= 0 then
//  begin
//    FPeakList.Clear;
//    FPeakListFirstIndex := 0;
//    Exit;
//  end;
//
//  Positions := FSession.PeakPositions;
//
//  if Length(Positions) = 0 then
//    Exit;
//
//  { --------------------------------------------------------------- }
//  { Binary search: первый peak >= AFrame                             }
//  { --------------------------------------------------------------- }
//
//  L := 0;
//  R := Length(Positions) - 1;
//
//  while L < R do
//  begin
//    Mid := L + (R - L) div 2;
//
//    if Positions[Mid] < AFrame then
//      L := Mid + 1
//    else
//      R := Mid;
//  end;
//
//  { Ближайший peak }
//  if L > 0 then
//  begin
//    if Abs(Positions[L - 1] - AFrame) <
//       Abs(Positions[L] - AFrame) then
//      L := L - 1;
//  end;
//
//  Mid := L;
//
//  { ±100 peaks }
//  L := Max(
//    0,
//    Mid - 100);
//
//  R := Min(
//    Length(Positions) - 1,
//    Mid + 100);
//
//  FPeakListFirstIndex := L;
//
//  FPeakList.BeginUpdate;
//  try
//    FPeakList.Clear;
//
//    for I := L to R do
//      FPeakList.Items.Add(
//        Positions[I].ToString);
//
//    { Выбираем peak, по которому кликнули }
//    FPeakList.ItemIndex := Mid - L;
//
//  finally
//    FPeakList.EndUpdate;
//  end;
//end;
procedure TMainForm.FillPeakListAroundFrame(AFrame: Int64);
const
  HalfWindow = 100;
var
  Positions: TArray<Int64>;
  Total, Mid, L, R, I: Integer;
  ListIndex: Integer;
begin
  if FSession.PeakCount <= 0 then
  begin
    FPeakList.Clear;
    FPeakListFirstIndex := 0;
    FPeakListRealCount := 0;
    Exit;
  end;

  Positions := FSession.PeakPositions;
  Total := Length(Positions);

  { Binary search: ближайший peak к AFrame }
  L := 0;
  R := Total - 1;
  while L < R do
  begin
    Mid := L + (R - L) div 2;
    if Positions[Mid] < AFrame then
      L := Mid + 1
    else
      R := Mid;
  end;
  if (L > 0) and (Abs(Positions[L - 1] - AFrame) < Abs(Positions[L] - AFrame)) then
    Dec(L);
  Mid := L;

  { Если текущий пик уже внутри загруженного окна — только подсвечиваем }
  if (Mid >= FPeakListFirstIndex) and
     (Mid < FPeakListFirstIndex + FPeakListRealCount) and
     (FPeakListRealCount > 0) then
  begin
    FPeakList.ItemIndex := Mid - FPeakListFirstIndex;
    Exit;
  end;

  { Иначе перезаполняем окно ±100 с текущим посередине }
  L := Max(0, Mid - HalfWindow);
  R := Min(Total - 1, Mid + HalfWindow);

  FPeakListFirstIndex := L;
  FPeakListRealCount := R - L + 1;

  FPeakList.BeginUpdate;
  try
    FPeakList.Clear;

    { Навигационный элемент "<<" в начало, если есть что листать }
    if L > 0 then
      FPeakList.Items.Add(Format('<<  (%d more)', [L]));

    for I := L to R do
      FPeakList.Items.Add(Positions[I].ToString);

    { Навигационный элемент ">>" в конец, если есть что листать }
    if R < Total - 1 then
      FPeakList.Items.Add(Format('>>  (%d more)', [Total - 1 - R]));

    { Подсвечиваем текущий пик }
    if (Mid >= L) and (Mid <= R) then
    begin
      ListIndex := Mid - L;
      if L > 0 then Inc(ListIndex);  // сдвиг из-за "<<"
      FPeakList.ItemIndex := ListIndex;
    end;
  finally
    FPeakList.EndUpdate;
  end;
end;
end.
