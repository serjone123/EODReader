unit Threads.VideoExport;

{ Фоновый экспорт видео с наложенной обзорной полосой:
    Этап A — рендер полосы (Video.OverlayRenderer) и кодирование её в
             отдельный видеофайл (Video.FfmpegExport.TFfmpegFrameWriter);
    Этап B — наложение (overlay) полосы на видео эксперимента
             (Video.FfmpegExport.RunOverlayComposite).

  Организован по образцу Threads.Overview.pas: TThread с TEvent для
  отмены, TThread.Synchronize для прогресса/финала, FreeOnTerminate. }

interface

uses
  System.Classes, System.SysUtils, System.SyncObjs,
  Core.Types, Video.OverlayRenderer, Video.FfmpegExport;

type
  TVideoExportStage = (vesRenderingBar, vesCompositing);

  TVideoExportProgressEvent = procedure(Sender: TObject;
    Stage: TVideoExportStage; Done, Total: Int64) of object;
  TVideoExportFinishedEvent = procedure(Sender: TObject;
    Canceled: Boolean; const ErrorText, OutputFileName: string) of object;

  TVideoExportRequest = record
    FfmpegPath: string;
    ExperimentVideoFileName: string;
    OutputFileName: string;

    { Путь для промежуточного видео полосы. Кэширование между повторными
      Preview/Full с одинаковыми параметрами — см. TODO.md, пункт про
      сохранение видео графика; в этой версии ReuseExistingBarVideo
      зарезервировано, но GUI пока всегда передаёт False. }
    BarVideoFileName: string;
    ReuseExistingBarVideo: Boolean;

    OutputWidth: Integer;
    OutputHeight: Integer;
    Fps: Double;
    FrameCount: Int64;
    OffsetSec: Double;
    SampleRate: Integer;
    TotalFrames: Int64;

    OverlayX: Integer;
    OverlayY: Integer;

    { Данные огибающей — копия того, что уже посчитано для экранного
      TOverviewPlot (uReadWavMain.FOverviewMin/Max/ChMin/ChMax). }
    EnvelopeMin: TFloatArray;
    EnvelopeMax: TFloatArray;
    ChannelMin: TChannelEnvelopes;
    ChannelMax: TChannelEnvelopes;
    ChannelColors: Boolean;
  end;

  TEodVideoExportThread = class(TThread)
  private
    FRequest: TVideoExportRequest;
    FCancelEvent: TEvent;
    FCanceled: Boolean;
    FErrorText: string;
    FStage: TVideoExportStage;
    FDone, FTotal: Int64;
    FOnProgress: TVideoExportProgressEvent;
    FOnFinished: TVideoExportFinishedEvent;
    procedure DoProgress;
    function CancelRequested: Boolean;
  protected
    procedure Execute; override;
  public
    constructor Create(const ARequest: TVideoExportRequest);
    destructor Destroy; override;
    procedure Cancel;
    property OnProgress: TVideoExportProgressEvent read FOnProgress write FOnProgress;
    property OnFinished: TVideoExportFinishedEvent read FOnFinished write FOnFinished;
  end;

implementation

uses
  System.IOUtils;

constructor TEodVideoExportThread.Create(const ARequest: TVideoExportRequest);
begin
  inherited Create(True);
  FreeOnTerminate := True;
  FRequest := ARequest;
  FCancelEvent := TEvent.Create(nil, True, False, '');
end;

destructor TEodVideoExportThread.Destroy;
begin
  FCancelEvent.Free;
  inherited;
end;

procedure TEodVideoExportThread.Cancel;
begin
  FCancelEvent.SetEvent;
end;

function TEodVideoExportThread.CancelRequested: Boolean;
begin
  Result := FCancelEvent.WaitFor(0) = wrSignaled;
end;

procedure TEodVideoExportThread.DoProgress;
begin
  if Assigned(FOnProgress) then
    FOnProgress(Self, FStage, FDone, FTotal);
end;

procedure TEodVideoExportThread.Execute;
var
  Renderer: TVideoOverlayRenderer;
  Writer: TFfmpegFrameWriter;
  Params: TVideoRenderParams;
  OkStageB: Boolean;
  NeedRenderBar: Boolean;
begin
  FCanceled := False;
  FErrorText := '';

  try
    try
      { --------------------------------------------------------- }
      { Этап A — рендер полосы.                                    }
      { --------------------------------------------------------- }

      NeedRenderBar := (not FRequest.ReuseExistingBarVideo)
        or (not TFile.Exists(FRequest.BarVideoFileName));

      if NeedRenderBar then
      begin
        FStage := vesRenderingBar;
        FDone := 0;
        FTotal := FRequest.FrameCount;
        TThread.Synchronize(Self, DoProgress);

        Renderer := TVideoOverlayRenderer.Create;
        try
          Renderer.SetEnvelopeData(
            FRequest.EnvelopeMin, FRequest.EnvelopeMax,
            FRequest.ChannelMin, FRequest.ChannelMax,
            0, FRequest.TotalFrames - 1,
            FRequest.ChannelColors);

          Writer := TFfmpegFrameWriter.Create(
            FRequest.FfmpegPath,
            FRequest.OutputWidth, FRequest.OutputHeight, FRequest.Fps,
            FRequest.BarVideoFileName);
          try
            Params.OutputWidth := FRequest.OutputWidth;
            Params.OutputHeight := FRequest.OutputHeight;
            Params.Fps := FRequest.Fps;
            Params.FrameCount := FRequest.FrameCount;
            Params.OffsetSec := FRequest.OffsetSec;
            Params.SampleRate := FRequest.SampleRate;
            Params.TotalFrames := FRequest.TotalFrames;
            Params.ShowTimeLabel := True;

            Renderer.RenderFrames(
              Params,
              procedure(const APixelsRGB24: TBytes; AFrameIndex: Int64)
              begin
                Writer.WriteFrame(APixelsRGB24);
              end,
              procedure(AFrame, ATotal: Int64)
              begin
                FDone := AFrame;
                FTotal := ATotal;
                TThread.Synchronize(Self, DoProgress);
              end,
              function: Boolean
              begin
                Result := CancelRequested;
              end);

            if CancelRequested then
            begin
              FCanceled := True;
              Exit;
            end;

            if Writer.FinishAndWait <> 0 then
            begin
              FErrorText := 'ffmpeg (рендер полосы) завершился с ошибкой';
              Exit;
            end;
          finally
            Writer.Free;
          end;
        finally
          Renderer.Free;
        end;
      end;

      if CancelRequested then
      begin
        FCanceled := True;
        Exit;
      end;

      { --------------------------------------------------------- }
      { Этап B — наложение на видео эксперимента.                 }
      { --------------------------------------------------------- }

      FStage := vesCompositing;
      FDone := 0;
      FTotal := 1;
      TThread.Synchronize(Self, DoProgress);

      OkStageB := RunOverlayComposite(
        FRequest.FfmpegPath,
        FRequest.ExperimentVideoFileName,
        FRequest.BarVideoFileName,
        FRequest.OutputFileName,
        FRequest.OverlayX, FRequest.OverlayY,
        FErrorText);

      if not OkStageB then
      begin
        FCanceled := CancelRequested;
        Exit;
      end;

      FDone := 1;
      TThread.Synchronize(Self, DoProgress);
    except
      on E: Exception do
      begin
        FErrorText := E.Message;
        FCanceled := CancelRequested;
      end;
    end;
  finally
    if CancelRequested then
      FCanceled := True;

    TThread.Synchronize(Self,
      procedure
      begin
        if Assigned(FOnFinished) then
          FOnFinished(Self, FCanceled, FErrorText, FRequest.OutputFileName);
      end);
  end;
end;

end.
