unit Video.OverlayRenderer;

{ Рендер отдельного видео "обзорной полосы" (envelope-график с движущимся
  плейхедом текущей позиции WAV-времени) без привязки к экранной форме.

  Полоса рисуется тем же движком, что и обычный TOverviewPlot на главной
  форме (GUI.Plot.Overview.pas), поэтому её вид совпадает с тем, что пользователь
  видит на экране (первая версия: белый фон, цвета каналов как в GUI —
  донастройка внешнего вида оставлена на будущее, см. TODO.md).

  Рендер идёт в offscreen TBitmap кадр за кадром; готовые кадры сразу
  отдаются наружу через callback — для потоковой передачи в ffmpeg без
  накопления всей последовательности в памяти. }

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes,
  FMX.Graphics, FMX.Objects,
  Core.Types, GUI.Plot.Overview;

type
  { Параметры одного прогона рендера. Данные огибающей задаются отдельно
    через SetEnvelopeData один раз на весь файл и переиспользуются между
    Preview- и Full-рендерами. }
  TVideoRenderParams = record
    OutputWidth: Integer;
    OutputHeight: Integer;
    Fps: Double;

    { Сколько кадров рендерить: для Preview — короткий отрезок,
      для Full — вся длительность видео эксперимента. }
    FrameCount: Int64;

    { Модель синхронизации (зафиксирована в TODO.md/README.md):
        VideoTime(кадр i) = i / Fps
        SampleTime        = VideoTime - OffsetSec
      OffsetSec подбирается пользователем вручную на глаз через Preview. }
    OffsetSec: Double;

    SampleRate: Integer;
    TotalFrames: Int64;

    { Рисовать поверх кадра текущее время WAV (ЧЧ:ММ:СС.ммм). }
    ShowTimeLabel: Boolean;
  end;

  { Кадр передаётся как сырые RGB24-байты, построчно сверху вниз, без
    выравнивания (padding): ровно Width*Height*3 байт. }
  TFrameReadyProc = reference to procedure(const APixelsRGB24: TBytes;
    AFrameIndex: Int64);

  TVideoProgressProc = reference to procedure(AFrame, ATotal: Int64);

  TVideoCancelFunc = reference to function: Boolean;

  TVideoOverlayRenderer = class
  private
    FOverview: TOverviewPlot;
    FDummyPaintBox: TPaintBox;
    FHaveData: Boolean;
    procedure DrawTimeLabel(Bmp: TBitmap; ASampleTimeSec: Double;
      AInRange: Boolean);
    procedure BitmapToRgb24(Bmp: TBitmap; out APixels: TBytes);
  public
    constructor Create;
    destructor Destroy; override;

    { Один раз на весь экспорт: те же массивы, что уже посчитаны для
      экранного TOverviewPlot (в uReadWavMain — FOverviewMin/Max,
      FOverviewChMin/Max), повторный проход по файлу не требуется. }
    procedure SetEnvelopeData(
      const AMinValues, AMaxValues: TFloatArray;
      const AChannelMin, AChannelMax: TChannelEnvelopes;
      AFullStart, AFullEnd: Int64;
      AChannelColors: Boolean);

    { Рендерит AParams.FrameCount кадров, вызывая AOnFrameReady для
      каждого готового кадра. Возвращает False, если рендер был прерван
      через AOnCancel (проверяется перед каждым кадром). }
    function RenderFrames(
      const AParams: TVideoRenderParams;
      AOnFrameReady: TFrameReadyProc;
      AOnProgress: TVideoProgressProc;
      AOnCancel: TVideoCancelFunc): Boolean;
  end;

implementation

uses
  System.Math, FMX.Types;

constructor TVideoOverlayRenderer.Create;
begin
  inherited Create;
  { TOverviewPlot требует реальный TPaintBox в конструкторе (назначает
    ему обработчики), но для offscreen-рендера этот PaintBox никогда не
    показывается и не получает реальных Paint/Mouse-событий — служит
    только контейнером для внутренних полей класса. }
  FDummyPaintBox := TPaintBox.Create(nil);
  FOverview := TOverviewPlot.Create(FDummyPaintBox);
  FHaveData := False;
end;

destructor TVideoOverlayRenderer.Destroy;
begin
  FOverview.Free;
  FDummyPaintBox.Free;
  inherited;
end;

procedure TVideoOverlayRenderer.SetEnvelopeData(
  const AMinValues, AMaxValues: TFloatArray;
  const AChannelMin, AChannelMax: TChannelEnvelopes;
  AFullStart, AFullEnd: Int64;
  AChannelColors: Boolean);
begin
  FOverview.SetData(AMinValues, AMaxValues, AFullStart, AFullEnd);
  FOverview.SetChannelData(AChannelMin, AChannelMax, AFullStart, AFullEnd);
  FOverview.ChannelColors := AChannelColors;
  FHaveData := True;
end;

procedure TVideoOverlayRenderer.DrawTimeLabel(Bmp: TBitmap;
  ASampleTimeSec: Double; AInRange: Boolean);
var
  S: string;
  R: TRectF;
begin
  if ASampleTimeSec < 0 then
    S := '--:--:--.---'
  else
    S := Format('%.2d:%.2d:%.2d.%.3d', [
      Trunc(ASampleTimeSec) div 3600,
      (Trunc(ASampleTimeSec) div 60) mod 60,
      Trunc(ASampleTimeSec) mod 60,
      Round(Frac(ASampleTimeSec) * 1000)]);

  if not AInRange then
    S := S + '  (вне записи)';

  if Bmp.Canvas.BeginScene then
  try
    R := RectF(6, 4, Bmp.Width - 6, 24);
    Bmp.Canvas.Fill.Color := TAlphaColorRec.Black;
    Bmp.Canvas.Font.Size := 14;
    Bmp.Canvas.FillText(R, S, False, 1, [], TTextAlign.Leading,
      TTextAlign.Leading);
  finally
    Bmp.Canvas.EndScene;
  end;
end;

procedure TVideoOverlayRenderer.BitmapToRgb24(Bmp: TBitmap; out APixels: TBytes);
var
  Data: TBitmapData;
  X, Y: Integer;
  Src: PAlphaColorRec;
  DstOffset: Integer;
begin
  { ВНИМАНИЕ: порядок каналов внутри TAlphaColorRec зависит от платформы/
    формата пикселей FMX-битмапа. На Win32 ожидается BGRA с полями
    .R/.G/.B/.A, соответствующими фактическому смыслу цвета (FMX сам
    разруливает физическую раскладку байт под капотом TBitmapData). Если
    после сборки цвета на итоговом видео окажутся перепутаны (R и B
    местами) — поменять местами Src.R/Src.B здесь. Это единственное
    место, которое имеет смысл проверить в первую очередь при отладке. }
  SetLength(APixels, Bmp.Width * Bmp.Height * 3);
  if not Bmp.Map(TMapAccess.Read, Data) then
    raise Exception.Create('Не удалось получить доступ к пикселям кадра');
  try
    for Y := 0 to Bmp.Height - 1 do
    begin
      Src := PAlphaColorRec(PByte(Data.Data) + Y * Data.Pitch);
      DstOffset := Y * Bmp.Width * 3;
      for X := 0 to Bmp.Width - 1 do
      begin
        APixels[DstOffset + X * 3 + 0] := Src.R;
        APixels[DstOffset + X * 3 + 1] := Src.G;
        APixels[DstOffset + X * 3 + 2] := Src.B;
        Inc(Src);
      end;
    end;
  finally
    Bmp.Unmap(Data);
  end;
end;

function TVideoOverlayRenderer.RenderFrames(
  const AParams: TVideoRenderParams;
  AOnFrameReady: TFrameReadyProc;
  AOnProgress: TVideoProgressProc;
  AOnCancel: TVideoCancelFunc): Boolean;
var
  I: Int64;
  VideoTimeSec, SampleTimeSec: Double;
  SamplePos, ClampedPos: Int64;
  InRange: Boolean;
  Bmp: TBitmap;
  Pixels: TBytes;
begin
  Result := True;

  if not FHaveData then
    raise Exception.Create('SetEnvelopeData не вызван перед рендером');

  if AParams.SampleRate <= 0 then
    raise Exception.Create('Некорректный SampleRate для рендера видео');

  for I := 0 to AParams.FrameCount - 1 do
  begin
    if Assigned(AOnCancel) and AOnCancel() then
    begin
      Result := False;
      Exit;
    end;

    VideoTimeSec := I / AParams.Fps;
    SampleTimeSec := VideoTimeSec - AParams.OffsetSec;
    SamplePos := Round(SampleTimeSec * AParams.SampleRate);

    InRange := (SamplePos >= 0) and (SamplePos < AParams.TotalFrames);

    { Плейхед — вырожденный (нулевой ширины) диапазон просмотра:
      TOverviewPlot.RenderPlot рисует прямоугольник текущего View по
      FViewStart/FViewEnd; при равных значениях он превращается в
      вертикальную линию — это и есть движущийся маркер положения. }
    ClampedPos := EnsureRange(SamplePos, Int64(0), AParams.TotalFrames - 1);
    FOverview.SetViewRange(ClampedPos, ClampedPos);

    Bmp := FOverview.RenderToBitmap(AParams.OutputWidth, AParams.OutputHeight);
    try
      if AParams.ShowTimeLabel then
        DrawTimeLabel(Bmp, SampleTimeSec, InRange);

      BitmapToRgb24(Bmp, Pixels);
    finally
      Bmp.Free;
    end;

    if Assigned(AOnFrameReady) then
      AOnFrameReady(Pixels, I);

    if Assigned(AOnProgress) and ((I mod 25) = 0) then
      AOnProgress(I, AParams.FrameCount);
  end;

  if Assigned(AOnProgress) then
    AOnProgress(AParams.FrameCount, AParams.FrameCount);
end;

end.
