unit Gui.Plot.Base;

interface

uses
  System.SysUtils, System.Types, System.UITypes,
  FMX.Objects, FMX.Graphics, FMX.Forms,
  System.Classes, FMX.Menus;

type
  TViewChangedEvent = procedure(Sender: TObject; ViewStart, ViewEnd: Int64) of object;

  TOverviewClickEvent = procedure(Sender: TObject; Frame: Int64) of object;

  TOverviewRangeSelectedEvent = procedure(Sender: TObject;
    AStart, AEnd: Int64) of object;
const
  { Цвета каналов 1..4 — те же, что использует основной график. }
  EodChannelColors: array[0..3] of TAlphaColor = (
    TAlphaColorRec.Red,
    TAlphaColorRec.Green,
    TAlphaColorRec.Blue,
    TAlphaColorRec.Orange);
type
  { Общий предок TOverviewPlot и TSignalPlot.

    Оба класса владеют TPaintBox, рисуют себя через переопределяемый
    RenderPlot(Canvas, ARect) и должны уметь:
      1) рендерить себя в оффскрин-битмап произвольного размера —
         RenderToBitmap. Сейчас это нужно TOverviewPlot для покадрового
         рендера видео-полосы (Video.OverlayRenderer.pas); после переноса
         сюда тем же методом сможет пользоваться и TSignalPlot — для
         будущего покадрового экспорта анимации основного графика по
         тому же принципу, без повторной реализации;
      2) показывать по правому клику одинаковое контекстное меню
         (Copy / Save to file...). Раньше это было только у TSignalPlot;
         TOverviewPlot такого меню не имел вовсе. }
  TPlotBase = class abstract
  protected
    FPaintBox: TPaintBox;
    FPopupMenu: TPopupMenu;

    { Рисует текущее состояние в ARect произвольного холста Canvas.
      Используется и на экране (PaintBoxPaint), и при рендере в
      оффскрин-битмап (RenderToBitmap) — реализация НЕ должна
      подставлять размеры/координаты FPaintBox вместо переданного ARect. }
    procedure RenderPlot(Canvas: TCanvas; const ARect: TRectF); virtual; abstract;

    procedure PaintBoxPaint(Sender: TObject; Canvas: TCanvas);

    { Наполняет FPopupMenu перед показом. Базовая реализация добавляет
      Copy/Save to file; потомок может дополнить список, переопределив
      метод и вызвав inherited. }
    procedure BuildContextMenu; virtual;

    procedure CopyToClipboard(Sender: TObject);
    procedure SaveViewToFile(Sender: TObject);

    { Общий обработчик правого клика для PaintBoxMouseDown потомков. }
    procedure HandleRightClick;
  public
    constructor Create(APaintBox: TPaintBox);
    destructor Destroy; override;

    { Рендерит текущее состояние (данные + текущий вид) в новый
      оффскрин TBitmap заданного размера, без привязки к размеру
      реального TPaintBox на экране. Владение результатом переходит
      к вызывающему коду — он обязан освободить TBitmap. }
    function RenderToBitmap(AWidth, AHeight: Integer): TBitmap;

    { То же самое, но в размер текущего PaintBox — тот же кадр, что
      виден на экране. Используется для Copy/Save в контекстном меню. }
    function GetPlotAsBitmap: TBitmap;
  end;
implementation

uses
  FMX.Platform, FMX.Dialogs;

function AddMenuItem(PM: TPopupMenu; AText: string; AAction: TNotifyEvent): TMenuItem;
begin
  Result := TMenuItem.Create(PM);
  Result.Parent := PM;
  Result.Text := AText;
  Result.OnClick := AAction;
end;

{ TPlotBase }

constructor TPlotBase.Create(APaintBox: TPaintBox);
begin
  inherited Create;
  if not Assigned(APaintBox) then
    raise EArgumentNilException.CreateFmt('%s requires a TPaintBox', [ClassName]);

  FPaintBox := APaintBox;
  FPaintBox.OnPaint := PaintBoxPaint;
  FPaintBox.HitTest := True;

end;

destructor TPlotBase.Destroy;
begin
  if Assigned(FPaintBox) then
  begin
    FPaintBox.OnPaint := nil;
    FPaintBox.OnMouseDown := nil;
    FPaintBox.OnMouseMove := nil;
    FPaintBox.OnMouseUp := nil;
    FPaintBox.OnMouseWheel := nil;
  end;

  FPaintBox := nil;
  inherited;
end;

procedure TPlotBase.PaintBoxPaint(Sender: TObject; Canvas: TCanvas);
begin
  RenderPlot(Canvas, FPaintBox.LocalRect);
end;

function TPlotBase.RenderToBitmap(AWidth, AHeight: Integer): TBitmap;
begin
  Result := TBitmap.Create(AWidth, AHeight);
  try
    if Result.Canvas.BeginScene then
    try
      RenderPlot(Result.Canvas, RectF(0, 0, AWidth, AHeight));
    finally
      Result.Canvas.EndScene;
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TPlotBase.GetPlotAsBitmap: TBitmap;
begin
  Result := RenderToBitmap(Round(FPaintBox.Width), Round(FPaintBox.Height));
end;

procedure TPlotBase.BuildContextMenu;
var
  I: Integer;
begin
  { Меню создаём лениво, при первом правом клике: рендер видео создаёт
    график в фоновом потоке, а создавать FMX-контролы вне главного
    потока небезопасно. }
  if FPopupMenu = nil then
  begin
    FPopupMenu := TPopupMenu.Create(FPaintBox);
    FPopupMenu.Parent := FPaintBox;
  end;
  for I := FPopupMenu.ItemsCount - 1 downto 0 do
    FPopupMenu.Items[I].Free;

  AddMenuItem(FPopupMenu, 'Copy', CopyToClipboard);
  AddMenuItem(FPopupMenu, 'Save to file...', SaveViewToFile);
end;

procedure TPlotBase.CopyToClipboard(Sender: TObject);
var
  Svc: IFMXClipboardService;
  Bmp: TBitmap;
begin
  if TPlatformServices.Current.SupportsPlatformService(IFMXClipboardService, Svc) then
  begin
    Bmp := GetPlotAsBitmap;
    try
      Svc.SetClipboard(Bmp);
    finally
      Bmp.Free;
    end;
  end;
end;

procedure TPlotBase.SaveViewToFile(Sender: TObject);
var
  D: TSaveDialog;
  Bmp: TBitmap;
begin
  D := TSaveDialog.Create(nil);
  try
    D.Filter := 'PNG image (*.png)|*.png|Bitmap (*.bmp)|*.bmp';
    D.DefaultExt := 'png';
    D.FileName := 'plot.png';
    if not D.Execute then
      Exit;

    Bmp := GetPlotAsBitmap;
    try
      Bmp.SaveToFile(D.FileName);
    finally
      Bmp.Free;
    end;
  finally
    D.Free;
  end;
end;

procedure TPlotBase.HandleRightClick;
begin
  BuildContextMenu;
  FPopupMenu.Popup(Screen.MousePos.X, Screen.MousePos.Y);
end;
end.