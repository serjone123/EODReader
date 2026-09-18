unit GUI.VideoExportForm;

{ Немодальное окно экспорта видео с наложенной обзорной полосой.
  Код-only форма (без .fmx), по аналогии с GUI.SettingsForm.pas —
  события назначаются в конструкторе, а не через RTTI published,
  см. AGENTS.md, раздел "Обработчики событий: назначать кодом, а не
  через форму".

  Не блокирует основной поток: рендер и композитинг идут в фоновом
  TEodVideoExportThread, форма только показывает прогресс и позволяет
  отменить операцию (кнопка "Отмена"). }

interface

uses
  System.SysUtils, System.UITypes, System.Types, System.Classes,
  FMX.Types, FMX.Forms, FMX.StdCtrls, FMX.Edit, FMX.Layouts, FMX.Controls,
  FMX.Dialogs,
  Core.Types, Threads.VideoExport, Video.FfmpegExport, Video.FfmpegLocate;

type
  { Источник данных огибающей и параметров сессии — форма не знает про
    TEodGuiSession напрямую (см. GUI.Model.pas), чтобы не тянуть в
    GUI.VideoExportForm лишние зависимости; вызывающий код (uReadWavMain)
    заполняет эту запись перед показом формы теми же массивами, что уже
    построены для экранного обзорного графика. }
  TVideoExportSessionData = record
    SampleRate: Integer;
    TotalFrames: Int64;
    EnvelopeMin: TFloatArray;
    EnvelopeMax: TFloatArray;
    ChannelMin: TChannelEnvelopes;
    ChannelMax: TChannelEnvelopes;
    ChannelColors: Boolean;
  end;

  TEodVideoExportForm = class(TForm)
  private
    FSessionData: TVideoExportSessionData;
    FExportThread: TEodVideoExportThread;
    FFfmpegPath: string;

    FEdVideoFile: TEdit;
    FBtnBrowseVideo: TButton;
    FEdOffsetSec: TEdit;
    FEdPreviewDurationSec: TEdit;
    FBtnPreview: TButton;
    FBtnFull: TButton;
    FBtnCancel: TButton;
    FStatusLabel: TLabel;
    FFfmpegLabel: TLabel;

    procedure BuildUI;
    procedure BrowseVideoClick(Sender: TObject);
    procedure PreviewClick(Sender: TObject);
    procedure FullClick(Sender: TObject);
    procedure CancelClick(Sender: TObject);

    function EnsureFfmpegAvailable: Boolean;
    procedure StartExport(FullRun: Boolean);
    procedure SetBusy(ABusy: Boolean);

    procedure ExportProgress(Sender: TObject; Stage: TVideoExportStage;
      Done, Total: Int64);
    procedure ExportFinished(Sender: TObject; Canceled: Boolean;
      const ErrorText, OutputFileName: string);
    procedure ExportThreadTerminated(Sender: TObject);
  public
    constructor CreateWithSession(AOwner: TComponent;
      const ASessionData: TVideoExportSessionData); reintroduce;
  end;

procedure ShowVideoExportForm(AOwner: TComponent;
  const ASessionData: TVideoExportSessionData);

implementation

uses
  System.IOUtils, System.Math;

const
  { Preview всегда рендерится с начала видео эксперимента (VideoTime = 0):
    именно это пользователь и увидит первым делом, сверяя совпадение
    начала полосы с видимым в кадре опорным событием (например, щелчком
    стимулятора). }
  DefaultPreviewDurationSec = 15;

procedure ShowVideoExportForm(AOwner: TComponent;
  const ASessionData: TVideoExportSessionData);
var
  Frm: TEodVideoExportForm;
begin
  Frm := TEodVideoExportForm.CreateWithSession(AOwner, ASessionData);
  Frm.Show;
end;

constructor TEodVideoExportForm.CreateWithSession(AOwner: TComponent;
  const ASessionData: TVideoExportSessionData);
begin
  inherited CreateNew(AOwner);
  FSessionData := ASessionData;
  FExportThread := nil;

  Caption := 'Экспорт видео с обзорной полосой';
  Width := 540;
  Height := 320;
  Position := TFormPosition.ScreenCenter;

  BuildUI;

  if TryLocateFfmpeg(FFfmpegPath) then
    FFfmpegLabel.Text := 'ffmpeg: ' + FFfmpegPath
  else
    FFfmpegLabel.Text := 'ffmpeg не найден — будет предложено выбрать при запуске';
end;

procedure TEodVideoExportForm.BuildUI;
var
  Y: Single;
  Lbl: TLabel;
begin
  Y := 12;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := Self;
  Lbl.Position.X := 12; Lbl.Position.Y := Y;
  Lbl.Width := 120; Lbl.Height := 22;
  Lbl.Text := 'Видео эксперимента:';

  FEdVideoFile := TEdit.Create(Self);
  FEdVideoFile.Parent := Self;
  FEdVideoFile.Position.X := 140; FEdVideoFile.Position.Y := Y;
  FEdVideoFile.Width := 300; FEdVideoFile.Height := 24;

  FBtnBrowseVideo := TButton.Create(Self);
  FBtnBrowseVideo.Parent := Self;
  FBtnBrowseVideo.Position.X := 448; FBtnBrowseVideo.Position.Y := Y;
  FBtnBrowseVideo.Width := 80; FBtnBrowseVideo.Height := 24;
  FBtnBrowseVideo.Text := 'Обзор...';
  FBtnBrowseVideo.OnClick := BrowseVideoClick;
  Y := Y + 34;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := Self;
  Lbl.Position.X := 12; Lbl.Position.Y := Y;
  Lbl.Width := 280; Lbl.Height := 22;
  Lbl.Text := 'Смещение Offset, сек (VideoTime = SampleTime + Offset):';

  FEdOffsetSec := TEdit.Create(Self);
  FEdOffsetSec.Parent := Self;
  FEdOffsetSec.Position.X := 300; FEdOffsetSec.Position.Y := Y;
  FEdOffsetSec.Width := 100; FEdOffsetSec.Height := 24;
  FEdOffsetSec.Text := '0';
  Y := Y + 34;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := Self;
  Lbl.Position.X := 12; Lbl.Position.Y := Y;
  Lbl.Width := 220; Lbl.Height := 22;
  Lbl.Text := 'Длительность превью, сек:';

  FEdPreviewDurationSec := TEdit.Create(Self);
  FEdPreviewDurationSec.Parent := Self;
  FEdPreviewDurationSec.Position.X := 300; FEdPreviewDurationSec.Position.Y := Y;
  FEdPreviewDurationSec.Width := 100; FEdPreviewDurationSec.Height := 24;
  FEdPreviewDurationSec.Text := IntToStr(DefaultPreviewDurationSec);
  Y := Y + 40;

  FBtnPreview := TButton.Create(Self);
  FBtnPreview.Parent := Self;
  FBtnPreview.Position.X := 12; FBtnPreview.Position.Y := Y;
  FBtnPreview.Width := 150; FBtnPreview.Height := 28;
  FBtnPreview.Text := 'Превью (короткий кусок)';
  FBtnPreview.OnClick := PreviewClick;

  FBtnFull := TButton.Create(Self);
  FBtnFull.Parent := Self;
  FBtnFull.Position.X := 170; FBtnFull.Position.Y := Y;
  FBtnFull.Width := 140; FBtnFull.Height := 28;
  FBtnFull.Text := 'Полный рендер';
  FBtnFull.OnClick := FullClick;

  FBtnCancel := TButton.Create(Self);
  FBtnCancel.Parent := Self;
  FBtnCancel.Position.X := 318; FBtnCancel.Position.Y := Y;
  FBtnCancel.Width := 100; FBtnCancel.Height := 28;
  FBtnCancel.Text := 'Отмена';
  FBtnCancel.Enabled := False;
  FBtnCancel.OnClick := CancelClick;
  Y := Y + 40;

  FFfmpegLabel := TLabel.Create(Self);
  FFfmpegLabel.Parent := Self;
  FFfmpegLabel.Position.X := 12; FFfmpegLabel.Position.Y := Y;
  FFfmpegLabel.Width := 510; FFfmpegLabel.Height := 20;
  Y := Y + 26;

  FStatusLabel := TLabel.Create(Self);
  FStatusLabel.Parent := Self;
  FStatusLabel.Position.X := 12; FStatusLabel.Position.Y := Y;
  FStatusLabel.Width := 510; FStatusLabel.Height := 60;
  FStatusLabel.Text := '';
end;

procedure TEodVideoExportForm.BrowseVideoClick(Sender: TObject);
var
  D: TOpenDialog;
begin
  D := TOpenDialog.Create(Self);
  try
    D.Filter := 'Видео (*.mp4;*.mov;*.avi;*.mkv)|*.mp4;*.mov;*.avi;*.mkv|Все файлы|*.*';
    if D.Execute then
      FEdVideoFile.Text := D.FileName;
  finally
    D.Free;
  end;
end;

function TEodVideoExportForm.EnsureFfmpegAvailable: Boolean;
var
  D: TOpenDialog;
begin
  Result := TryLocateFfmpeg(FFfmpegPath);
  if Result then
    Exit;

  D := TOpenDialog.Create(Self);
  try
    D.Filter := 'ffmpeg.exe|ffmpeg.exe|Все файлы|*.*';
    D.Title := 'Укажите путь к ffmpeg.exe';
    Result := D.Execute;
    if Result then
    begin
      FFfmpegPath := D.FileName;
      SaveFfmpegPath(FFfmpegPath);
      FFfmpegLabel.Text := 'ffmpeg: ' + FFfmpegPath;
    end;
  finally
    D.Free;
  end;
end;

procedure TEodVideoExportForm.SetBusy(ABusy: Boolean);
begin
  FBtnPreview.Enabled := not ABusy;
  FBtnFull.Enabled := not ABusy;
  FBtnBrowseVideo.Enabled := not ABusy;
  FEdVideoFile.Enabled := not ABusy;
  FEdOffsetSec.Enabled := not ABusy;
  FEdPreviewDurationSec.Enabled := not ABusy;
  FBtnCancel.Enabled := ABusy;
end;

procedure TEodVideoExportForm.PreviewClick(Sender: TObject);
begin
  StartExport(False);
end;

procedure TEodVideoExportForm.FullClick(Sender: TObject);
begin
  StartExport(True);
end;

procedure TEodVideoExportForm.CancelClick(Sender: TObject);
begin
  if Assigned(FExportThread) then
  begin
    FExportThread.Cancel;
    FStatusLabel.Text := 'Отмена запрошена...';
    FBtnCancel.Enabled := False;
  end;
end;

procedure TEodVideoExportForm.StartExport(FullRun: Boolean);
var
  Info: TSourceVideoInfo;
  ProbeError: string;
  Offset, PreviewDuration: Double;
  Req: TVideoExportRequest;
  OutputDir, BaseName: string;
begin
  if Assigned(FExportThread) then
    Exit;

  if not TFile.Exists(FEdVideoFile.Text) then
  begin
    FStatusLabel.Text := 'Укажите существующий файл видео эксперимента.';
    Exit;
  end;

  if not EnsureFfmpegAvailable then
  begin
    FStatusLabel.Text := 'ffmpeg не выбран — экспорт невозможен.';
    Exit;
  end;

  if not TryStrToFloat(FEdOffsetSec.Text.Replace(',', '.'), Offset,
    TFormatSettings.Invariant) then
  begin
    FStatusLabel.Text := 'Некорректное значение Offset.';
    Exit;
  end;

  if not TryStrToFloat(FEdPreviewDurationSec.Text.Replace(',', '.'),
    PreviewDuration, TFormatSettings.Invariant) or (PreviewDuration <= 0) then
    PreviewDuration := DefaultPreviewDurationSec;

  FStatusLabel.Text := 'Определение параметров видео (ffprobe)...';
  Application.ProcessMessages;

  if not ProbeSourceVideo(FFfmpegPath, FEdVideoFile.Text, Info, ProbeError) then
  begin
    FStatusLabel.Text := 'Ошибка ffprobe: ' + ProbeError;
    Exit;
  end;

  OutputDir := ExtractFilePath(FEdVideoFile.Text);
  BaseName := ChangeFileExt(ExtractFileName(FEdVideoFile.Text), '');

  Req.FfmpegPath := FFfmpegPath;
  Req.ExperimentVideoFileName := FEdVideoFile.Text;
  Req.OutputWidth := Info.Width;
  Req.Fps := Info.Fps;
  Req.SampleRate := FSessionData.SampleRate;
  Req.TotalFrames := FSessionData.TotalFrames;
  Req.OffsetSec := Offset;

  { Полоса — по нижнему краю кадра, во всю ширину, оставшаяся часть
    высоты кадра ниже 85% (первая версия; настройка позиции/размера —
    на будущее, см. TODO.md). }
  Req.OverlayX := 0;
  Req.OverlayY := Round(Info.Height * 0.85);
  Req.OutputHeight := Info.Height - Req.OverlayY;

  Req.EnvelopeMin := FSessionData.EnvelopeMin;
  Req.EnvelopeMax := FSessionData.EnvelopeMax;
  Req.ChannelMin := FSessionData.ChannelMin;
  Req.ChannelMax := FSessionData.ChannelMax;
  Req.ChannelColors := FSessionData.ChannelColors;

  if FullRun then
  begin
    Req.FrameCount := Round(Info.DurationSec * Info.Fps);
    Req.BarVideoFileName := TPath.Combine(OutputDir, BaseName + '_overview_bar_full.mp4');
    Req.OutputFileName := TPath.Combine(OutputDir, BaseName + '_with_overview.mp4');
  end
  else
  begin
    Req.FrameCount := Round(Min(PreviewDuration, Info.DurationSec) * Info.Fps);
    Req.BarVideoFileName := TPath.Combine(OutputDir, BaseName + '_overview_bar_preview.mp4');
    Req.OutputFileName := TPath.Combine(OutputDir, BaseName + '_preview.mp4');
  end;

  { Кэширование готовой полосы между повторными запусками с одинаковым
    Offset — отдельная задача (см. TODO.md); пока каждый запуск рендерит
    полосу заново. }
  Req.ReuseExistingBarVideo := False;

  SetBusy(True);
  FStatusLabel.Text := 'Запуск рендера...';

  FExportThread := TEodVideoExportThread.Create(Req);
  FExportThread.OnProgress := ExportProgress;
  FExportThread.OnFinished := ExportFinished;
  FExportThread.OnTerminate := ExportThreadTerminated;
  FExportThread.Start;
end;

procedure TEodVideoExportForm.ExportProgress(Sender: TObject;
  Stage: TVideoExportStage; Done, Total: Int64);
var
  StageText: string;
  Percent: Integer;
begin
  case Stage of
    vesRenderingBar: StageText := 'Рендер полосы';
    vesCompositing: StageText := 'Наложение на видео (ffmpeg)';
  end;

  if Total > 0 then
    Percent := Round(Done * 100.0 / Total)
  else
    Percent := 0;

  FStatusLabel.Text := Format('%s: %d%% (%d / %d)',
    [StageText, Percent, Done, Total]);
end;

procedure TEodVideoExportForm.ExportFinished(Sender: TObject;
  Canceled: Boolean; const ErrorText, OutputFileName: string);
begin
  SetBusy(False);

  if Canceled then
    FStatusLabel.Text := 'Отменено пользователем.'
  else if ErrorText <> '' then
    FStatusLabel.Text := 'Ошибка: ' + ErrorText
  else
    FStatusLabel.Text := 'Готово: ' + OutputFileName;
end;

procedure TEodVideoExportForm.ExportThreadTerminated(Sender: TObject);
begin
  if FExportThread = Sender then
    FExportThread := nil;
end;

end.
