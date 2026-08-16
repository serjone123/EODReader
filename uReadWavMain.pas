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
    procedure FSelectRangeButtonClick(Sender: TObject);
    procedure FAnalyzeButtonClick(Sender: TObject);
    procedure FApplyButtonClick(Sender: TObject);
    procedure FModeBoxChange(Sender: TObject);
    procedure FNextButtonClick(Sender: TObject);
    procedure FOpenPeakButtonClick(Sender: TObject);
    procedure FOpenWavButtonClick(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure FormDestroy(Sender: TObject);
    procedure FormCreate(Sender: TObject);
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
  public
  end;

var
  MainForm: TMainForm;

implementation

uses
  System.Math;

{$R *.fmx}

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
    FillPeakList;

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

  FPlot.SetFullRange(0, FSession.TotalFrames - 1);

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

  FPlot.Free;
  FPlot := nil;

  FDetector.Free;
  FSession.Free;
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

procedure TMainForm.edStartSampleMouseWheel(Sender: TObject; Shift: TShiftState;
  WheelDelta: Integer; var Handled: Boolean);
begin
  case WheelDelta>0 of
    true : FPrevButtonClick(self) ;
    false: FNextButtonClick(self) ;
  end;
  Handled:=false;
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

  FCurrentPeak := Index;

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
  FPeakList.ItemIndex := Index;

  Std := FSession.CalculateStd(Data);
  Fir := FDetector.ApplyFir15(Std);

  FPlot.SetChannels(
    Data, StartFrame, FSession.SampleRate, Peak.Position,
    Format('Peak #%d  sample %d',
      [Index + 1, Peak.Position]));

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
          FPlot.SetFullRange(0, FSession.TotalFrames - 1);
    end
    else
    begin
      edStartSample.Text := '0';
      edRange.Text := '200';
          FPlot.SetFullRange(0, FSession.TotalFrames - 1);
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

procedure TMainForm.FPeakListClick(Sender: TObject);
begin
  if FPeakList.ItemIndex >= 0 then
    ShowPeak(FPeakList.ItemIndex);
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
end.
