unit uReadWavMain;

interface

uses
  System.SysUtils, System.Types, System.UITypes,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.StdCtrls, FMX.Objects, FMX.Edit,
  FMX.ListBox, FMX.Layouts, FMX.Dialogs, FMX.SpinBox
, System.Classes, FMX.Controls.Presentation
, Core.Types
, Core.Log
, Detection.Detector
, IO.PeakStore
, GUI.Model
, GUI.Plot.Signal
, GUI.Playback
, GUI.PeakList
, GUI.Analysis
, GUI.OverviewController
, GUI.ViewController
, Core.ConfigStore, GUI.SettingsForm
, GUI.FileNaming
, FMX.Menus
, Electrode.Matching
, Electrode.LayoutForm
, GUI.VideoExportForm
, fmx.Dialogservice
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
    procedure FinalizeOpenWav(const AFile1, AFile2: string);
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
    procedure FBuildOverviewButtonClick(Sender: TObject);
    procedure FPlayButtonClick(Sender: TObject);
    procedure lbPeakListClick(Sender: TObject);
    procedure PlaySpeedBoxChange(Sender: TObject);
  private
    FSession: TEodGuiSession;
    FDetector: TEodDetector;
    FConfig: TEodDetectorConfig;
    FPlot: TSignalPlot;
    FView: TEodViewController;
    FUpdating: Boolean;

    FBackground: TEodAnalysisController;

    FOverviewController: TEodOverviewController;
    FBuildOverviewButton: TButton;

    FPeakList: TEodPeakList;

    FPlayer: TEodPlayer;

    { Постоянная немодальная форма разметки электродов (Electrode.LayoutForm).
      Создаётся один раз, при закрытии прячется (caHide) и живёт до закрытия
      главной формы — разметка переживает открытие/закрытие окна. }
    FElectrodeForm: TElectrodeLayoutForm;

    FWheelAccumulator: Integer;

    FLastDir: string;

    procedure OverviewClick(Sender: TObject; Frame: Int64);
    procedure OverviewRangeSelected(Sender: TObject; AStart, AEnd: Int64);

    procedure UpdateStatus(const S: string);
    procedure UpdateCaption;
    function ShouldBuildOverview: Boolean;
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
    procedure PlotViewChanged(Sender: TObject; ViewStart, ViewEnd: Int64);
    procedure ViewRangeChanged(AStart, AEnd: Int64);

    { Собирает амплитуды EOD-событий по каналам из пиков текущей записи
      для локализации положения рыбы (кнопка "Разметка электродов"). }
    procedure BuildAmplitudeEvents(out AEvents: TElectrodeEventArray);

    { «Живое» событие под курсором (или под воспроизводимым пиком): шлёт его
      в форму разметки, где локализуется текущая позиция рыбы и рисуется
      путь. Вызывается из ViewRangeChanged (каждое изменение вида). }
    procedure PushCurrentEventToLayout;
    function FindNearestPeakIndex(APosition: Int64): Integer;
    procedure LayoutFormClose(Sender: TObject; var Action: TCloseAction);
  end;

var
  MainForm: TMainForm;

implementation

uses
  System.Math
  {$IFDEF MSWINDOWS}
  , Winapi.Windows, Winapi.ShellAPI
  {$ENDIF}
  , Electrode.Amplitudes;

{$R *.fmx}

procedure TMainForm.FormCreate(Sender: TObject);
begin
  Position := TFormPosition.ScreenCenter;
  UpdateCaption;

  if not LoadDetectorConfig(GetDefaultConfigFileName, FConfig) then
    FConfig := DefaultEodDetectorConfig;
  FSession := TEodGuiSession.Create;
  FDetector := TEodDetector.Create(FConfig);

  { Владелец фоновых воркеров (GUI.Analysis.pas). Реакция на прогресс и
    результаты остаётся здесь, в форме; контроллер лишь дергает события. }
  FBackground := TEodAnalysisController.Create;
  FBackground.OnAnalysisProgress := AnalysisProgress;
  FBackground.OnAnalysisFinished := AnalysisFinished;
  FBackground.OnOpenProgress := OpenProgress;
  FBackground.OnOpenFinished := OpenFinished;
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

  { Обзорный график и его воркеры полностью живут в GUI.OverviewController.
    Клики и выделения на обзоре пересылаются обратно в навигацию формы;
    статус идёт в строку состояния. Почти все колбэки — прямые методы
    TMainForm. }
  FOverviewController := TEodOverviewController.Create(
    FSession,
    OverviewPaintBox,
    function: Int64
    begin
      Result := FPlot.ViewSampleCount;
    end,
    UpdateStatus,
    OverviewClick,
    OverviewRangeSelected,
    BackgroundCloseRequest);

  FBuildOverviewButton := TButton.Create(Self);
  FBuildOverviewButton.Parent := layLeft;
  FBuildOverviewButton.Align := TAlignLayout.Top;
  FBuildOverviewButton.Margins.Left := 4;
  FBuildOverviewButton.Margins.Top := 4;
  FBuildOverviewButton.Margins.Bottom := 4;
  FBuildOverviewButton.Position.X := 4;
  FBuildOverviewButton.Position.Y := 276;
  FBuildOverviewButton.Width := 61;
  FBuildOverviewButton.Height := 26;
  FBuildOverviewButton.Text := 'Обзор';
  FBuildOverviewButton.OnClick := FBuildOverviewButtonClick;
  FBuildOverviewButton.Enabled := False;

  { edRange — производный индикатор только для чтения: End - Start.
    Обработчики назначены кодом, а не через .fmx, чтобы не зависеть от
    того, привязал ли их дизайнер формы. }
  edRange.ReadOnly := True;
  edStartSample.OnChange := edStartSampleChange;
  edEndSample.OnChange := edEndSampleChange;

  FPeakList := TEodPeakList.Create(lbPeakList, FSession,
    procedure(Index: Integer)
    begin
      FView.ShowPeak(Index);
    end,
    procedure(const S: string)
    begin
      edEndSample.Text := S;
    end);
  FWheelAccumulator := 0;

  { Показ пиков и диапазонов на основном графике (GUI.ViewController.pas).
    Плеер создаётся ниже, поэтому «идёт ли воспроизведение» проверяется
    в момент вызова, а не при создании. }
  FView := TEodViewController.Create(FPlot, FSession, FDetector,
    FOverviewController, FPeakList,
    function: Boolean
    begin
      Result := Assigned(FPlayer) and FPlayer.Active;
    end,
    ViewRangeChanged,
    UpdateStatus);
  FView.PlotMode := TPlotMode(FModeBox.ItemIndex);

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
      FView.ShowPeak(Index);
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
      Result := FView.CurrentPeak;
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
        if (FView.CurrentPeak >= 0) and
           (FView.CurrentPeak < FSession.PeakCount) then
          FPeakList.FillAroundFrame(
            FSession.GetPeakPosition(FView.CurrentPeak));
      end;
    end);

  FPlayer.SetSpeedIndex(FPlaySpeedBox.ItemIndex);

  FStatus.Text := '';

  FOverviewController.ChannelColors := True;
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  { Обычно к этому моменту воркеры уже завершены: FormCloseQuery не даёт
    дойти до FormDestroy, пока работает хотя бы один. }
  FBackground.CancelAll;
  FBackground.Free;
  FBackground := nil;

  FOverviewController.CancelAll;
  FOverviewController.Free;
  FOverviewController := nil;

  FView.Free;
  FView := nil;

  FPlayer.Free;
  FPlayer := nil;

  FPeakList.Free;
  FPeakList := nil;

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

  if FBackground.AnyRunning or FOverviewController.AnyRunning then
  begin
    FBackground.CancelAll;
    FOverviewController.CancelAll;
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
    FView.CurrentPeak := -1;
    lbPeakList.Clear;
    UpdateStatus('Analysis cancelled.');
  end
  else if ErrorText <> '' then
  begin
    FSession.SetPeaks(nil);
    FView.CurrentPeak := -1;
    lbPeakList.Clear;
    UpdateStatus('Analysis error: ' + ErrorText);
    { Текст ошибки длинный (стадия, блок, диапазон кадров) и в строке
      состояния обрезается — показываем его в диалоге, его можно скопировать.

      ВАЖНО: шестой параметр (пустой анонимный обработчик) нельзя убирать.
      Без него вызов не разрешается, и вместе с ним перестают разрешаться
      оба других вызова TDialogService.MessageDialog в этом же модуле —
      компилятор падает с E2250 на всех трёх. }
    TDialogService.MessageDialog(
      'Ошибка анализа:' + sLineBreak + ErrorText + sLineBreak + sLineBreak +
        'Подробности в журнале: ' + LogFilePath,
      TMsgDlgType.mtError,
      [TMsgDlgBtn.mbOk],
      TMsgDlgBtn.mbOk,
      0,
      procedure(const AResult: TModalResult)
      begin
      end);
  end
  else
  begin
    FSession.SetPeaks(Peaks);
    FPeakList.FillAroundFrame(FSession.GetPeakPosition(0));

    if Length(Peaks) > 0 then
      FView.ShowPeak(0);

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
  FBuildOverviewButton.Enabled := not Analyzing and
    (FSession.Mode = dmWav) and (FSession.TotalFrames > 0);

  FAnalyzeButton.Enabled := True;

  if Analyzing then
    FAnalyzeButton.Text := 'Cancel analysis'
  else
    FAnalyzeButton.Text := 'Analyze WAV';
end;

function TMainForm.ShouldBuildOverview: Boolean;
begin
  Result := False;
  if (FConfig.OverviewMaxSeconds > 0) and
    (FSession.SampleRate > 0) and (FSession.TotalFrames > 0) then
    Result := FSession.TotalFrames / FSession.SampleRate <=
      FConfig.OverviewMaxSeconds;
end;

procedure TMainForm.FBuildOverviewButtonClick(Sender: TObject);
begin
  if (FSession.Mode <> dmWav) or (FSession.TotalFrames <= 0) then
    Exit;
  if FOverviewController.AnyRunning then
    Exit;
  FOverviewController.StartOverview;
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
  Events: TElectrodeEventArray;
  AutoOverview: Boolean;
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
  FView.Session := FSession;
  FPeakList.Session := FSession;
  FOverviewController.Session := FSession;
  FPlayer.Session := FSession;
  if FSession.TotalFrames > 0 then
  begin
    { В режиме WAV под вид выделяется сырой буфер, поэтому максимальная
      ширина вида ограничена — иначе при отдалении будут огромные
      аллокации. }
    FPlot.SetMaxViewSamples(MaxViewSamples);
    FPlot.SetFullRange(0, FSession.TotalFrames - 1);
  end;

  AutoOverview := ShouldBuildOverview;
  if AutoOverview then
    FOverviewController.StartOverview
  else
    FOverviewController.ClearOverview;
  FBuildOverviewButton.Enabled := FSession.TotalFrames > 0;
  OldSession.Free;

  FSession.SetPeaks(nil);
  FView.Reset;

  FPeakList.FillFirstPage;
  SetAnalysisUiState(False);

  SetRangeEdits(0, 200);

  FView.ShowRange(0, 200);

  { Сессия сменилась — форма разметки должна знать новые амплитуды,
    иначе batch-локализация будет работать со старыми данными. }
  if Assigned(FElectrodeForm) then
  begin
    BuildAmplitudeEvents(Events);
    FElectrodeForm.SetAmplitudes(Events);
  end;

  UpdateStatus(Format('WAV: %.3f sec, %d Hz, %d frames',
    [FSession.TotalFrames / FSession.SampleRate, FSession.SampleRate,
    FSession.TotalFrames]));
  if not AutoOverview then
    UpdateStatus('Автоматический обзор пропущен для большой записи. Нажмите «Обзор» для построения.');

  UpdateCaption;
end;

procedure TMainForm.PlotViewChanged(Sender: TObject; ViewStart, ViewEnd: Int64);
begin
  if FSession.Mode = dmNone then
    Exit;

  FOverviewController.SetViewRange(ViewStart, ViewEnd);

  SetRangeEdits(ViewStart, ViewEnd);

  FView.ShowRange(ViewStart, ViewEnd);
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

procedure TMainForm.StartAnalysis(MaxFrames: Int64);
begin
  if FBackground.AnalysisRunning then
    Exit;

  lbPeakList.Clear;
  FSession.SetPeaks(nil);
  FView.CurrentPeak := -1;

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

  // Текст сообщения переведен на русский язык
  SecondsText := 'Анализировать весь WAV-файл целиком?' + sLineBreak +
    'Анализ будет выполняться в фоновом режиме.' + sLineBreak +
    'Нажмите «Нет», чтобы проанализировать только первые 600 секунд.';

  // Вызываем асинхронный диалог с тремя кнопками
  TDialogService.MessageDialog(
    SecondsText,
    TMsgDlgType.mtConfirmation,
    [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo, TMsgDlgBtn.mbCancel], // Добавлена кнопка отмены
    TMsgDlgBtn.mbYes, // Кнопка по умолчанию
    0,
    procedure(const AResult: TModalResult)
    begin
      // Проверяем выбор пользователя
      case AResult of
        mrYes:
          begin
            MaxFrames := 0;
          end;

        mrNo:
          begin
            MaxFrames := Int64(600) * FSession.SampleRate;

            if MaxFrames > FSession.TotalFrames then
              MaxFrames := FSession.TotalFrames;
          end;

        else
          // Если нажата кнопка «Отмена» (mrCancel) или кнопка «Назад» на Android
          Exit;
      end;

      // Запуск анализа происходит только для mrYes и mrNo
      StartAnalysis(MaxFrames);
    end
  );
end;


procedure TMainForm.FApplyButtonClick(Sender: TObject);
var
  S: Int64;
begin
  S := ReadInt64Edit(edStartSample, 0);
  FView.ShowRange(S, ReadInt64Edit(edEndSample, S));
end;

procedure TMainForm.FModeBoxChange(Sender: TObject);
begin
  if Assigned(FView) and (FModeBox.ItemIndex >= 0) then
    FView.PlotMode := TPlotMode(FModeBox.ItemIndex);
end;

procedure TMainForm.FNextButtonClick(Sender: TObject);
begin
  FView.NextPeak;
end;

{ ================================================================== }
{  Воспроизведение (код в GUI.Playback.pas — TEodPlayer)             }
{ ================================================================== }

procedure TMainForm.PlaySpeedBoxChange(Sender: TObject);
begin
  FPlayer.SetSpeedIndex(FPlaySpeedBox.ItemIndex);
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
  FBuildOverviewButton.Enabled := False;

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

    FOverviewController.StartPeakOverview(D.FileName,
      cbBucketModeBox.ItemIndex = 0);

    FView.CurrentPeak := -1;

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
      FView.ShowRange(StartFrame, EndFrame);
      FOverviewController.SetViewRange(StartFrame, EndFrame);
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

// Вспомогательный метод (или приватный метод формы), чтобы не дублировать код запуска
procedure TMainForm.FinalizeOpenWav(const AFile1, AFile2: string);
begin
  FBackground.StartOpenWav(AFile1, AFile2);

  SetAnalysisUiState(True);
  FAnalyzeButton.Enabled := False;
  FOpenPeakButton.Enabled := False;
  FSaveButton.Enabled := False;
  UpdateStatus('Opening WAV in background...');
end;

procedure TMainForm.FOpenWavButtonClick(Sender: TObject);
var
  D: TOpenDialog;
  // Переносим переменные, которые должны "выжить" внутри колбэка
  // Delphi автоматически захватит их в анонимный метод
  CapturedFile1: string;
  CapturedFile2: string;
  MsgText: string;
begin
  if FBackground.OpenRunning or FBackground.AnalysisRunning then
    Exit;

  D := TOpenDialog.Create(Self);
  try
    D.Filter := 'WAV files (*.wav)|*.wav|All files (*.*)|*.*';
    D.Title := 'Открыть первый WAV';
    if FLastDir <> '' then
      D.InitialDir := FLastDir;

    if not D.Execute then
      Exit;

    CapturedFile1 := D.FileName;
    FLastDir := ExtractFilePath(CapturedFile1);

    // Сценарий 1: Парный файл найден автоматически
    if TryGetPairedWavFileName(CapturedFile1, CapturedFile2) and FileExists(CapturedFile2) then
    begin
      FinalizeOpenWav(CapturedFile1, CapturedFile2);
      Exit;
    end;

    // Формируем текст сообщения в зависимости от ситуации
    if TryGetPairedWavFileName(CapturedFile1, CapturedFile2) then
    begin
      MsgText := 'Парный WAV не найден:' + sLineBreak +
        CapturedFile2 + sLineBreak + sLineBreak +
        'Выбрать второй WAV вручную?';
    end
    else
    begin
      MsgText := 'Не удалось определить имя парного WAV.' + sLineBreak +
        'Выбрать второй WAV вручную?';
    end;

  finally
    // Уничтожаем диалог первого файла, так как управление передается в асинхронный поток
    D.Free;
  end;

  // Сценарий 2: Парный файл НЕ найден, вызываем асинхронный диалог
  TDialogService.MessageDialog(
    MsgText,
    TMsgDlgType.mtWarning,
    [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo],
    TMsgDlgBtn.mbYes,
    0,
    procedure(const AResult: TModalResult)
    var
      SecondaryDialog: TOpenDialog;
    begin
      // Если пользователь отказался выбирать вручную — просто выходим
      if AResult <> mrYes then
        Exit;

      // Пользователь согласился выбрать файл вручную
      SecondaryDialog := TOpenDialog.Create(Self);
      try
        SecondaryDialog.Filter := 'WAV files (*.wav)|*.wav|All files (*.*)|*.*';
        SecondaryDialog.Title := 'Открыть парный WAV';
        if FLastDir <> '' then
          SecondaryDialog.InitialDir := FLastDir;

        // Если во втором диалоге нажали "Отмена" — выходим
        if not SecondaryDialog.Execute then
          Exit;

        CapturedFile2 := SecondaryDialog.FileName;
      finally
        SecondaryDialog.Free;
      end;

      // Запускаем фоновый воркер
      FinalizeOpenWav(CapturedFile1, CapturedFile2);
    end
  );
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
    ViewW := FView.CurrentCount;
  if ViewW <= 0 then
    ViewW := 200;

  SetRangeEdits(Frame, Frame + ViewW - 1);

  FView.ShowRange(Frame, Frame + ViewW - 1);
end;

procedure TMainForm.FPrevButtonClick(Sender: TObject);
begin
  FView.PrevPeak;
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

procedure TMainForm.OverviewClick(Sender: TObject; Frame: Int64);
var
  ViewWidth: Int64;
  NewStart, NewEnd: Int64;
begin
  if FSession.Mode = dmNone then
    Exit;
  if FSession.TotalFrames <= 0 then
    Exit;

  { Привязка к ближайшему пику: клик по пустому месту обзора всё равно
    приводит к пику. Иначе вид уезжает в промежуток, ListBox пиков остаётся
    без выделения, а сохранение метки/события даёт нулевые амплитуды. }
  if FConfig.OverviewSnapToPeak and (FSession.PeakCount > 0) then
    Frame := FSession.GetPeakPosition(FindNearestPeakIndex(Frame));

  ViewWidth := FPlot.ViewSampleCount;
  if ViewWidth <= 0 then
    ViewWidth := FView.CurrentCount;
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

  FView.ShowRange(NewStart, NewEnd);

  { <<< FIX: восстановление рабочего диапазона отображения >>> }
  FPlot.GetViewRange(NewStart, NewEnd);
  FOverviewController.SetViewRange(NewStart, NewEnd);

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

  FView.ShowRange(AStart, AEnd);

  FPlot.GetViewRange(ViewStart, ViewEnd);
  FOverviewController.SetViewRange(ViewStart, ViewEnd);
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

      FView.Detector := FDetector;

      SaveDetectorConfig(GetDefaultConfigFileName, FConfig);
      UpdateStatus('Settings saved to ' + GetDefaultConfigFileName);
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TMainForm.btGeometryClick(Sender: TObject);
var
  Events: TElectrodeEventArray;
begin
  { Постоянная немодальная форма разметки: создаётся один раз (OnClose
    только прячет её — данные разметки переживают закрытие окна). }
  if not Assigned(FElectrodeForm) then
  begin
    FElectrodeForm := TElectrodeLayoutForm.Create(Self);
    FElectrodeForm.OnClose := LayoutFormClose;
  end;

  { События пиков текущей записи (для batch-локализации кнопкой
    «Локализовать»); без записи форма работает автономно. }
  BuildAmplitudeEvents(Events);
  FElectrodeForm.SetAmplitudes(Events);

  FElectrodeForm.Show;
  FElectrodeForm.BringToFront;

  { «Живой» маркер сразу под текущим курсором. }
  PushCurrentEventToLayout;
end;

procedure TMainForm.LayoutFormClose(Sender: TObject; var Action: TCloseAction);
begin
  { Форму не уничтожаем — прячем, чтобы разметка (углы, пары, каналы,
    полярность) пережила закрытие окна. Освободит владелец (TMainForm). }
  Action := TCloseAction.caHide;
end;

function TMainForm.FindNearestPeakIndex(APosition: Int64): Integer;
var
  Lo, Hi, Mid: Integer;
  PosMid, PosLo, PosHi: Int64;
begin
  Result := 0;
  if FSession.PeakCount = 0 then
    Exit;

  { Позиции пиков отсортированы по кадру — бинарный поиск нижней границы. }
  Lo := 0;
  Hi := FSession.PeakCount - 1;
  while Lo < Hi do
  begin
    Mid := (Lo + Hi) div 2;
    PosMid := FSession.GetPeakPosition(Mid);
    if PosMid < APosition then
      Lo := Mid + 1
    else
      Hi := Mid;
  end;

  { Между двух соседних пиков берём ближайший по кадру. }
  Result := Lo;
  if Result > 0 then
  begin
    PosLo := Abs(FSession.GetPeakPosition(Result - 1) - APosition);
    PosHi := Abs(FSession.GetPeakPosition(Result) - APosition);
    if PosLo < PosHi then
      Dec(Result);
  end;
end;

procedure TMainForm.PushCurrentEventToLayout;
var
  Event: TElectrodeEventAmplitudes;
  Index: Integer;
  Chunk: TAudioChunk;
  Peak, ReadPeakRec: TPeak;
  StartFrame: Int64;
begin
  if not Assigned(FElectrodeForm) then
    Exit;
  if (FSession = nil) or (FSession.Mode = dmNone) or
     (FSession.PeakCount = 0) then
    Exit;

  Index := FindNearestPeakIndex(CurrentFrame);

  if FSession.Mode = dmWav then
  begin
    if not FSession.GetPeak(Index, Peak) then
      Exit;
    Event.Frame := Peak.Position;
    Chunk := FSession.ReadSegment(Peak.Position - 30, 61, True);
  end
  else
  begin
    { dmPeakFile: окно события читается только через ReadPeak. }
    Chunk := FSession.ReadPeak(Index, ReadPeakRec, StartFrame);
    Event.Frame := StartFrame;
  end;

  Event.Amplitudes := ExtractEventAmplitudes(Chunk);
  FElectrodeForm.UpdateLiveEvent(Event);
end;

procedure TMainForm.BuildAmplitudeEvents(out AEvents: TElectrodeEventArray);
var
  Sess: TEodGuiSession;
  Total, I, Step, N, Idx: Integer;
  Chunk: TAudioChunk;
  Peak: TPeak;
  StartFrame: Int64;
begin
  SetLength(AEvents, 0);
  Sess := FSession;
  if (Sess = nil) or (Sess.Mode = dmNone) then
    Exit;

  Total := Sess.PeakCount;
  if Total <= 0 then
    Exit;

  { Для локализации достаточно репрезентативного подмножества пиков,
    равномерно распределённых по всей записи: берём не более 150, с
    шагом по индексу. Окно вокруг события (61 кадр) читается: из WAV -
    произвольным чтением по позиции пика, из .eodpk - через ReadPeak. }
  N := Min(Total, 150);
  if N > 1 then
    Step := (Total - 1) div (N - 1)
  else
    Step := 1;

  SetLength(AEvents, N);
  for I := 0 to N - 1 do
  begin
    Idx := I * Step;
    if Sess.Mode = dmWav then
    begin
      if not Sess.GetPeak(Idx, Peak) then
        Continue;
      StartFrame := Peak.Position;
      Chunk := Sess.ReadSegment(Max(0, Peak.Position - 30), 61, True);
    end
    else
      Chunk := Sess.ReadPeak(Idx, Peak, StartFrame);
    AEvents[I].Frame := StartFrame;
    AEvents[I].Amplitudes := ExtractEventAmplitudes(Chunk);
  end;
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

  if not FOverviewController.HasEnvelope then
  begin
    UpdateStatus('Обзорный график ещё не построен — дождитесь его загрузки.');
    Exit;
  end;

  { Экспорт видео использует уже посчитанную для экранного обзорного
    графика огибающую (контроллер обзора) — тот же массив, что рисует
    обзор на главной форме, повторный проход по файлу не требуется. }
  SessionData.SampleRate := FSession.SampleRate;
  SessionData.TotalFrames := FSession.TotalFrames;
  SessionData.EnvelopeMin := FOverviewController.EnvelopeMin;
  SessionData.EnvelopeMax := FOverviewController.EnvelopeMax;
  SessionData.ChannelMin := FOverviewController.ChannelMin;
  SessionData.ChannelMax := FOverviewController.ChannelMax;
  SessionData.ChannelColors := FOverviewController.ChannelColors;

  ShowVideoExportForm(Self, SessionData);

end;

procedure TMainForm.cbBucketModeBoxChange(Sender: TObject);
begin
  FOverviewController.SetOverviewLook(cbBucketModeBox.ItemIndex);
end;

procedure TMainForm.cbOverviewLookBoxChange(Sender: TObject);
begin
{ Режим бакетов применяется при построении обзора EODPK, поэтому
    строим заново (для EODPK это быстрое чтение кэша). }
  if FSession.Mode = dmPeakFile then
    FOverviewController.StartPeakOverview(FSession.PeakFile,
     cbOverviewLookBox.ItemIndex = 0);
end;

procedure TMainForm.lbPeakListClick(Sender: TObject);
begin
  FPeakList.HandleClick;
end;

procedure TMainForm.ViewRangeChanged(AStart, AEnd: Int64);
begin
  SetRangeEdits(AStart, AEnd);
  { Курсор/воспроизведение сдвинулись — обновляем «живой» маркер рыбы
    в форме разметки (если она создана). Во время воспроизведения это
    рисует путь рыбы на кадре. }
  PushCurrentEventToLayout;
end;

end.
