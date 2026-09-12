unit Gui.Plot;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Math,
  FMX.Types, FMX.Objects, FMX.Graphics, FMX.Forms,
  Core.Types, System.Classes, System.Generics.Collections, FMX.Menus;

type
  TPlotMode = (
    pmRaw,
    pmStd,
    pmFir15,
    pmRawAndFir15,
    pmRaw4Channels,
    pmHistogram
  );

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
  { Поканальные min/max огибающие; индекс 0..3 — канал 1..4. }
  TChannelEnvelopes = array[0..3] of TFloatArray;

  TOverviewPlot = class
  private
    FPaintBox: TPaintBox;

    FMinValues: TFloatArray;
    FMaxValues: TFloatArray;

    { Поканальные огибающие для режима "обзор в цветах каналов".
      Пустой массив = данных по каналу нет, канал не рисуется. }
    FChannelMin: TChannelEnvelopes;
    FChannelMax: TChannelEnvelopes;
    FShowChannelColors: Boolean;

    FFullStart: Int64;
    FFullEnd: Int64;

    FViewStart: Int64;
    FViewEnd: Int64;

    FOnClick: TOverviewClickEvent;
    FOnRangeSelected: TOverviewRangeSelectedEvent;

    { Drag-selection state }
    FDragging: Boolean;
    FDragIsSelection: Boolean;
    FDragStartX: Single;
    FDragStartFrame: Int64;
    FDragCurrentFrame: Int64;

    procedure PaintBoxPaint(Sender: TObject; Canvas: TCanvas);
    procedure PaintBoxMouseDown(Sender: TObject;
      Button: TMouseButton; Shift: TShiftState; X, Y: Single);
    procedure PaintBoxMouseMove(Sender: TObject;
      Shift: TShiftState; X, Y: Single);
    procedure PaintBoxMouseUp(Sender: TObject;
      Button: TMouseButton; Shift: TShiftState; X, Y: Single);

    function MapX(Frame: Int64; const R: TRectF): Single;
    function MapY(Value, MinY, MaxY: Double;
      const R: TRectF): Single;
    function XToFrame(X: Single; const R: TRectF): Int64;
    function GetPlotRect: TRectF;

    procedure SetShowChannelColors(AValue: Boolean);
    function GetHasChannelData: Boolean;
    procedure DrawChannelEnvelopes(Canvas: TCanvas; const R: TRectF);

  public
    constructor Create(APaintBox: TPaintBox);
    destructor Destroy; override;

    procedure Clear;

    procedure SetData(
      const AMinValues, AMaxValues: TFloatArray;
      AFullStart, AFullEnd: Int64);

    { Поканальные огибающие 4 каналов. Хранятся отдельно от общей
      огибающей из SetData, поэтому переключение ChannelColors не
      требует повторной подготовки данных. }
    procedure SetChannelData(
      const AMinValues, AMaxValues: TChannelEnvelopes;
      AFullStart, AFullEnd: Int64);

    procedure SetViewRange(AStart, AEnd: Int64);

    { Рисовать обзор поканально, в EodChannelColors. Если поканальных
      данных нет (HasChannelData = False), рисуется обычная огибающая. }
    property ChannelColors: Boolean
      read FShowChannelColors write SetShowChannelColors;

    property HasChannelData: Boolean read GetHasChannelData;

    property OnClick: TOverviewClickEvent read FOnClick write FOnClick;
    property OnRangeSelected: TOverviewRangeSelectedEvent
      read FOnRangeSelected write FOnRangeSelected;
  end;

  TSignalPlot = class
  private
    FPaintBox: TPaintBox;
    PopupMenuImg: TPopupMenu;
    FData: TAudioChunk;
    FStd: TFloatArray;
    FFir: TFloatArray;
    FMode: TPlotMode;
    FStartFrame: Int64;
    FSampleRate: Integer;
    FSelectedOffset: Integer;
    FPeakOffset: Integer;
    FShowPeakLine: Boolean;
    FPeakPositions: TArray<Int64>;
    FTitle: string;
    FHistogramStart: Int64;
    FHistogramEnd: Int64;

    { Navigation }
    FFullStart: Int64;
    FFullEnd: Int64;
    FViewStart: Int64;
    FViewEnd: Int64;
    FMaxView: Int64;
    FDragging: Boolean;
    FDragStartX: Single;
    FDragStartViewStart: Int64;
    FDragStartViewEnd: Int64;
    FLastMouseX: Single;
    FEnvelope: TWaveEnvelope;
    FEnvelopeActive: Boolean;

    FOnViewChanged : TViewChangedEvent;

    procedure DrawEnvelope4Channels(
      Canvas: TCanvas;
      const R: TRectF);
    procedure DrawEnvelopeSingle(
      Canvas: TCanvas;
      const R: TRectF);

    procedure PaintBoxPaint(Sender: TObject; Canvas: TCanvas);
    procedure PaintBoxMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Single);
    procedure PaintBoxMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Single);
    procedure PaintBoxMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Single);
    procedure PaintBoxMouseWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer; var Handled: Boolean);

    procedure DrawGrid(Canvas: TCanvas; const R: TRectF;
      MinY, MaxY: Double; const XStart, XEnd: Int64);
    procedure DrawHorizontalGrid(Canvas: TCanvas; const R: TRectF;
      MinY, MaxY: Double);
    procedure DrawVerticalGrid(Canvas: TCanvas; const R: TRectF);
    procedure DrawYAxisLabels(Canvas: TCanvas; const R: TRectF;
      MinY, MaxY: Double);
    procedure DrawXAxisLabels(Canvas: TCanvas; const R: TRectF;
      Count: Integer);
    procedure DrawXAxisLabelsAbsolute(Canvas: TCanvas; const R: TRectF;
      XStart, XEnd: Int64);
    function MapX(Index, Count: Integer; const R: TRectF): Single;
    function MapY(Value, MinY, MaxY: Double; const R: TRectF): Single;
    procedure RequestRepaint;
    function FormatAxisValue(V: Double): string;
    procedure DrawRaw(Canvas: TCanvas; const R: TRectF;
      MinY, MaxY: Double);
    procedure DrawRaw4Channels(Canvas: TCanvas; const R: TRectF);
    procedure DrawHistogram(Canvas: TCanvas; const R: TRectF);
    procedure DrawScalar(Canvas: TCanvas; const R: TRectF;
      const Values: TFloatArray; MinY, MaxY: Double);
    procedure DrawRawAndFir(Canvas: TCanvas; const R: TRectF;
      MinY, MaxY: Double);
    procedure UpdatePeakOffset(PeakFrame: Int64);
    procedure ClampView;
    procedure DoViewChanged;
    function ViewWidth: Int64;
    procedure CopyIMG(Sender: TObject);
  public
    constructor Create(APaintBox: TPaintBox);
    destructor Destroy; override;
    procedure ClearData;
    procedure SetChannels(const Data: TAudioChunk; StartFrame: Int64;
      SampleRate: Integer; PeakFrame: Int64 = -1;
      const ATitle: string = '');
    procedure SetStd(const Data: TFloatArray; StartFrame: Int64;
      SampleRate: Integer; PeakFrame: Int64 = -1;
      const ATitle: string = '');
    procedure SetFir(const Data: TFloatArray; StartFrame: Int64;
      SampleRate: Integer; PeakFrame: Int64 = -1;
      const ATitle: string = '');
    procedure SetMode(AMode: TPlotMode);
    function GetMode: TPlotMode;
    procedure SetPeakPositions(const Positions: array of Int64);
    procedure SetSelectedPosition(AFrame: Int64);
    procedure SetHistogramRange(StartFrame, EndFrame: Int64);
    procedure SetFullRange(AStart, AEnd: Int64);
    procedure SetMaxViewSamples(AValue: Int64);
    procedure SetViewRange(AStart, AEnd: Int64);
    procedure GetViewRange(out AStart, AEnd: Int64);
    function ViewSampleCount: Int64;
    procedure ZoomAt(AX: Single; AFactor: Double);
    procedure PanByPixels(ADeltaX: Single);
    property OnViewChanged: TViewChangedEvent read FOnViewChanged write FOnViewChanged;
    procedure SetEnvelope(const Envelope: TWaveEnvelope; StartFrame, EndFrame: Int64; SampleRate: Integer;
  const ATitle: string = '');
  end;

const
  MinViewSamples = 10;
  MaxViewSamples = 2000000;  { ~5 sec @ 96 kHz; prevents OOM on zoom-out }
  EnvelopeResolutionLimit = 10000;
implementation

uses
  FMX.Platform, System.Rtti;

constructor TSignalPlot.Create(APaintBox: TPaintBox);
begin
  inherited Create;
  if not Assigned(APaintBox) then
    raise EArgumentNilException.Create('TSignalPlot requires a TPaintBox');
  FPaintBox := APaintBox;
  FPaintBox.OnPaint := PaintBoxPaint;
  FPaintBox.OnMouseDown := PaintBoxMouseDown;
  FPaintBox.OnMouseMove := PaintBoxMouseMove;
  FPaintBox.OnMouseUp := PaintBoxMouseUp;
  FPaintBox.OnMouseWheel := PaintBoxMouseWheel;
  FPaintBox.HitTest := True;
  FMode := pmRaw;
  FSampleRate := 1;
  FSelectedOffset := -1;
  FPeakOffset := -1;
  FHistogramStart := 0;
  FHistogramEnd := -1;
  FFullStart := 0;
  FFullEnd := 0;
  FViewStart := 0;
  FViewEnd := 0;
  FMaxView := MaxViewSamples;
//  FLastMouseX := 0;
  FLastMouseX := FPaintBox.Width / 2 ;
  PopupMenuImg:= TPopupMenu.Create(APaintBox);
  PopupMenuImg.Parent:= APaintBox;
end;

destructor TSignalPlot.Destroy;
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

procedure TSignalPlot.RequestRepaint;
begin
  if Assigned(FPaintBox) then
    FPaintBox.Repaint;
end;

procedure TSignalPlot.ClearData;
begin
  SetLength(FData, 0);
  SetLength(FStd, 0);
  SetLength(FFir, 0);
  SetLength(FPeakPositions, 0);
  FSelectedOffset := -1;
  FPeakOffset := -1;
  FShowPeakLine := False;
  FTitle := '';
  FHistogramStart := 0;
  FHistogramEnd := -1;
  RequestRepaint;

  SetLength(FEnvelope, 0);
  FEnvelopeActive := False;
end;

function TSignalPlot.GetMode: TPlotMode;
begin
  Result := FMode;
end;

procedure TSignalPlot.SetMode(AMode: TPlotMode);
begin
  FMode := AMode;
  RequestRepaint;
end;

procedure TSignalPlot.UpdatePeakOffset(PeakFrame: Int64);
begin
  FShowPeakLine := PeakFrame >= 0;
  if FShowPeakLine then
    FPeakOffset := Integer(PeakFrame - FStartFrame)
  else
    FPeakOffset := -1;
end;

{ ------------------------------------------------------------------ }
{  Navigation                                                        }
{ ------------------------------------------------------------------ }

procedure TSignalPlot.SetFullRange(AStart, AEnd: Int64);
begin
  if AEnd < AStart then
  begin
    FFullStart := AStart;
    FFullEnd := AStart;
  end
  else
  begin
    FFullStart := AStart;
    FFullEnd := AEnd;
  end;
  FViewStart := FFullStart;
  if (FFullEnd - FFullStart) > FMaxView then
    FViewEnd := FFullStart + FMaxView
  else
    FViewEnd := FFullEnd;
  RequestRepaint;
end;

procedure TSignalPlot.SetMaxViewSamples(AValue: Int64);
begin
  { The maximum view width is mode-dependent. In WAV mode a wide view
    allocates a matching raw buffer, so it must stay bounded. In EODPK
    mode the plot only reads the compact envelope, so the whole file
    can be shown. The caller decides which limit applies. }
  if AValue < MinViewSamples then
    AValue := MinViewSamples;
  FMaxView := AValue;
end;

procedure TSignalPlot.SetViewRange(AStart, AEnd: Int64);
begin
  if AEnd < AStart then
  begin
    FViewStart := AStart;
    FViewEnd := AStart;
  end
  else
  begin
    FViewStart := AStart;
    FViewEnd := AEnd;
  end;
  SetHistogramRange(FViewStart, FViewEnd);
  RequestRepaint;
end;

procedure TSignalPlot.GetViewRange(out AStart, AEnd: Int64);
begin
  AStart := FViewStart;
  AEnd := FViewEnd;
end;

function TSignalPlot.ViewSampleCount: Int64;
begin
  Result := FViewEnd - FViewStart;
  if Result < 0 then
    Result := 0;
end;

function TSignalPlot.ViewWidth: Int64;
begin
  Result := ViewSampleCount;
end;

//procedure TSignalPlot.ClampView;
//var
//  W, Center: Int64;
//begin
//  W := FViewEnd - FViewStart;
//
//  { Limit minimum width }
//  if W < MinViewSamples then
//  begin
//    Center := (FViewStart + FViewEnd) div 2;
//    W := MinViewSamples;
//    FViewStart := Center - W div 2;
//    FViewEnd := FViewStart + W;
//  end;
//
//  { Limit maximum width — prevents OOM when zooming out }
//  if W > MaxViewSamples then
//  begin
//    Center := (FViewStart + FViewEnd) div 2;
//    W := MaxViewSamples;
//    FViewStart := Center - W div 2;
//    FViewEnd := FViewStart + W;
//  end;
//
//  { Clamp to file bounds }
//  if FViewStart < FFullStart then
//  begin
//    FViewStart := FFullStart;
//    FViewEnd := FViewStart + W;
//  end;
//
//  if FViewEnd > FFullEnd then
//  begin
//    FViewEnd := FFullEnd;
//    FViewStart := FViewEnd - W;
//    if FViewStart < FFullStart then
//      FViewStart := FFullStart;
//  end;
//
//  { Final safety clamp }
//  if FViewStart < FFullStart then
//    FViewStart := FFullStart;
//  if FViewEnd > FFullEnd then
//    FViewEnd := FFullEnd;
//  if FViewEnd - FViewStart < MinViewSamples then
//    FViewEnd := FViewStart + MinViewSamples;
//  if FViewEnd > FFullEnd then
//    FViewEnd := FFullEnd;
//end;
procedure TSignalPlot.ClampView;
var
  FullWidth: Int64;
  W: Int64;
begin
  FullWidth := FFullEnd - FFullStart;

  if FullWidth <= 0 then
  begin
    FViewStart := FFullStart;
    FViewEnd := FFullEnd;
    Exit;
  end;

  { --------------------------------------------------------------- }
  { First determine the desired width.                              }
  { --------------------------------------------------------------- }

  W := FViewEnd - FViewStart;

  if W < MinViewSamples then
    W := MinViewSamples;

  if W > FMaxView then
    W := FMaxView;

  { The complete file is smaller than our minimum zoom level. }
  if W >= FullWidth then
  begin
    FViewStart := FFullStart;
    FViewEnd := FFullEnd;
    Exit;
  end;

  { --------------------------------------------------------------- }
  { Keep the current center, but move the whole window into bounds. }
  { --------------------------------------------------------------- }

  FViewStart :=
    ((FViewStart + FViewEnd) div 2) - W div 2;

  FViewEnd := FViewStart + W;

  { Left boundary. }
  if FViewStart < FFullStart then
  begin
    FViewStart := FFullStart;
    FViewEnd := FViewStart + W;
  end;

  { Right boundary. }
  if FViewEnd > FFullEnd then
  begin
    FViewEnd := FFullEnd;
    FViewStart := FViewEnd - W;
  end;

  { Final protection. }
  if FViewStart < FFullStart then
    FViewStart := FFullStart;

  if FViewEnd > FFullEnd then
    FViewEnd := FFullEnd;

  { This should never be necessary, but prevents an invalid range. }
  if FViewEnd < FViewStart then
  begin
    FViewStart := FFullStart;
    FViewEnd := FFullEnd;
  end;
end;
procedure TSignalPlot.DoViewChanged;
begin
  if Assigned(FOnViewChanged) then
    FOnViewChanged(Self, FViewStart, FViewEnd);
end;

//procedure TSignalPlot.ZoomAt(AX: Single; AFactor: Double);
//var
//  R: TRectF;
//  PlotWidth: Single;
//  SampleUnderCursor: Double;
//  NewWidth: Double;
//  NewStart: Double;
//begin
//  if (FFullEnd <= FFullStart) or (AFactor <= 0) then
//    Exit;
//
//  R := RectF(0, 0, FPaintBox.Width, FPaintBox.Height);
//  PlotWidth := R.Width;
//  if PlotWidth <= 0 then
//    Exit;
//
//  if (AX < 0) or (AX > PlotWidth) then
//    AX := PlotWidth / 2;
//
//  if (FViewEnd > FViewStart) then
//    SampleUnderCursor := FViewStart + (AX / PlotWidth) * (FViewEnd - FViewStart)
//  else
//    SampleUnderCursor := FViewStart;
//
//  NewWidth := (FViewEnd - FViewStart) * AFactor;
//  if NewWidth < MinViewSamples then
//    NewWidth := MinViewSamples;
//  if NewWidth > MaxViewSamples then
//    NewWidth := MaxViewSamples;
//
//  NewStart := SampleUnderCursor - (AX / PlotWidth) * NewWidth;
//
//  FViewStart := Round(NewStart);
//  FViewEnd := FViewStart + Round(NewWidth);
//
//  ClampView;
//  RequestRepaint;
//  DoViewChanged;
//end;
procedure TSignalPlot.ZoomAt(
  AX: Single;
  AFactor: Double);
var
  R: TRectF;
  PlotWidth: Single;
  ViewWidthD: Double;
  FullWidthD: Double;
  CursorRatio: Double;
  SampleUnderCursor: Double;
  NewWidth: Double;
  NewStart: Double;
  NewEnd: Double;
begin
  if (FFullEnd <= FFullStart) then
    Exit;

  if AFactor <= 0 then
    Exit;

  R := RectF(
    0,
    0,
    FPaintBox.Width,
    FPaintBox.Height);

  PlotWidth := R.Width;

  if PlotWidth <= 0 then
    Exit;

  if AX < 0 then
    AX := 0
  else if AX > PlotWidth then
    AX := PlotWidth;

  ViewWidthD :=
    FViewEnd - FViewStart;

  FullWidthD :=
    FFullEnd - FFullStart;

  if ViewWidthD <= 0 then
  begin
    FViewStart := FFullStart;
    FViewEnd := FFullEnd;
    ViewWidthD := FullWidthD;
  end;

  { Position under mouse, from 0 to 1. }
  CursorRatio :=
    AX / PlotWidth;

  SampleUnderCursor :=
    FViewStart +
    CursorRatio * ViewWidthD;

  { --------------------------------------------------------------- }
  { Calculate new width.                                            }
  { --------------------------------------------------------------- }

  NewWidth := ViewWidthD * AFactor;

  if NewWidth < MinViewSamples then
    NewWidth := MinViewSamples;

  if NewWidth > FMaxView then
    NewWidth := FMaxView;

  if NewWidth >= FullWidthD then
  begin
    FViewStart := FFullStart;
    FViewEnd := FFullEnd;

    RequestRepaint;
    DoViewChanged;
    Exit;
  end;

  { --------------------------------------------------------------- }
  { Keep the sample under the mouse at the same screen position.    }
  { --------------------------------------------------------------- }

  NewStart :=
    SampleUnderCursor -
    CursorRatio * NewWidth;

  NewEnd :=
    NewStart + NewWidth;

  FViewStart := Round(NewStart);
  FViewEnd := Round(NewEnd);

  ClampView;

  RequestRepaint;
  DoViewChanged;
end;
procedure TSignalPlot.PanByPixels(ADeltaX: Single);
var
  R: TRectF;
  PlotWidth: Single;
  SamplesPerPixel: Double;
  DeltaSamples: Int64;
begin
  if (FFullEnd <= FFullStart) or not FDragging then
    Exit;

  R := RectF(0, 0, FPaintBox.Width, FPaintBox.Height);
  PlotWidth := R.Width;
  if PlotWidth <= 0 then
    Exit;

  SamplesPerPixel := (FDragStartViewEnd - FDragStartViewStart) / PlotWidth;
  DeltaSamples := Round(ADeltaX * SamplesPerPixel);

  FViewStart := FDragStartViewStart - DeltaSamples;
  FViewEnd := FDragStartViewEnd - DeltaSamples;

  ClampView;
  RequestRepaint;
  DoViewChanged;
end;

{ ------------------------------------------------------------------ }
{  Menu                                                    }
{ ------------------------------------------------------------------ }
procedure TSignalPlot.CopyIMG(Sender: TObject);
var
  ClipboardService: IFMXClipboardService;
  Bitmap: TBitmap;
begin

  try


    // Проверяем, что изображение действительно загрузилось
//    if FPaintBox.paiCanvas.Bitmap.IsEmpty then
//      Exit;

    // Получаем сервис буфера обмена
//    if TPlatformServices.Current.SupportsPlatformService(IFMXClipboardService, ClipboardService) then
//      // Передаём изображение в буфер. Сервис сам создаёт копию данных,
//      // поэтому после вызова Bitmap можно безопасно освободить
//      ClipboardService.SetClipboard(TValue.From<TBitmap>(FPaintBox.Canvas.Bitmap));
  finally
//    Bitmap.Free;
  end;


end;
{ ------------------------------------------------------------------ }
{  Mouse handlers                                                    }
{ ------------------------------------------------------------------ }

function AddMenuItem(PM: TPopupMenu; AText: string; AAction: TNotifyEvent):TMenuItem;
begin
  result := TMenuItem.Create(PM)  ;
  result.Parent:= PM;
  result.Text:=AText ;
  result.OnClick:=AAction ;
end;

procedure TSignalPlot.PaintBoxMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Single);
begin
  if Button = TMouseButton.mbLeft then
    begin
      FDragging := True;
      FDragStartX := X;
      FDragStartViewStart := FViewStart;
      FDragStartViewEnd := FViewEnd;
      FLastMouseX := X
    end
  else  if Button = TMouseButton.mbRight then
    begin
      for var I := 0 to PopupMenuImg.ItemsCount-1  do
        begin
          PopupMenuImg.Items[0].Free ;
        end;

      AddMenuItem(PopupMenuImg, 'Copy ', CopyIMG);
      PopupMenuImg.Popup(Screen.MousePos.x, Screen.MousePos.y)
    end;

end;

procedure TSignalPlot.PaintBoxMouseMove(Sender: TObject; Shift: TShiftState;
  X, Y: Single);
begin
  FLastMouseX := X;

  { If the left button was released outside the paintbox, stop dragging }
  if not (ssLeft in Shift) then
  begin
    FDragging := False;
    Exit;
  end;

  if not FDragging then
    Exit;

  PanByPixels(X - FDragStartX);
end;

procedure TSignalPlot.PaintBoxMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Single);
begin
  FDragging := False;
end;

procedure TSignalPlot.PaintBoxMouseWheel(Sender: TObject; Shift: TShiftState;
  WheelDelta: Integer; var Handled: Boolean);
var
  Factor: Double;
begin
  Handled := True;

  if WheelDelta > 0 then
    Factor := 0.8   // zoom in
  else
    Factor := 1.25; // zoom out

  ZoomAt(FLastMouseX, Factor);
end;

{ ------------------------------------------------------------------ }
{  Existing drawing code (unchanged logic)                           }
{ ------------------------------------------------------------------ }

function TSignalPlot.MapX(Index, Count: Integer;
  const R: TRectF): Single;
begin
  if Count <= 1 then
    Exit(R.Left);
  Result := R.Left + (Index / (Count - 1)) * R.Width;
end;

function TSignalPlot.MapY(Value, MinY, MaxY: Double;
  const R: TRectF): Single;
begin
  if SameValue(MaxY, MinY) then
    Exit(R.CenterPoint.Y);
  Result := R.Bottom -
    ((Value - MinY) / (MaxY - MinY)) * R.Height;
end;

function TSignalPlot.FormatAxisValue(V: Double): string;
begin
  if Abs(V) < 0.0000005 then
    V := 0;
  if Abs(V) >= 100 then
    Result := FormatFloat('0.##', V)
  else if Abs(V) >= 1 then
    Result := FormatFloat('0.###', V)
  else if Abs(V) >= 0.01 then
    Result := FormatFloat('0.#####', V)
  else
    Result := FormatFloat('0.000000', V);
end;

procedure TSignalPlot.DrawYAxisLabels(Canvas: TCanvas;
  const R: TRectF; MinY, MaxY: Double);
var
  I: Integer;
  Y, V: Double;
  S: string;
begin
  Canvas.Fill.Color := TAlphaColorRec.Gray;
  Canvas.Font.Size := 11;
  for I := 0 to 5 do
  begin
    V := MaxY - I * (MaxY - MinY) / 5;
    Y := MapY(V, MinY, MaxY, R);
    S := FormatAxisValue(V);
    Canvas.FillText(
      RectF(2, Y - 9, R.Left - 4, Y + 9),
      S,
      False,
      1,
      [],
      TTextAlign.Trailing,
      TTextAlign.Center);
  end;
end;

procedure TSignalPlot.DrawXAxisLabels(Canvas: TCanvas;
  const R: TRectF; Count: Integer);
var
  I, SampleIndex: Integer;
  X: Single;
  Sample: Int64;
  S: string;
begin
  if Count <= 0 then
    Exit;
  Canvas.Fill.Color := TAlphaColorRec.Gray;
  Canvas.Font.Size := 10;
  for I := 0 to 5 do
  begin
    if Count = 1 then
      SampleIndex := 0
    else
      SampleIndex := Round(I * (Count - 1) / 5);
    X := MapX(SampleIndex, Count, R);
    Sample := FStartFrame + SampleIndex;
    S := Sample.ToString;
    Canvas.FillText(
      RectF(X - 45, R.Bottom + 3, X + 45, R.Bottom + 19),
      S,
      False,
      1,
      [],
      TTextAlign.Center,
      TTextAlign.Center);
  end;
end;

procedure TSignalPlot.DrawXAxisLabelsAbsolute(Canvas: TCanvas;
  const R: TRectF; XStart, XEnd: Int64);
var
  I: Integer;
  X: Single;
  Sample: Int64;
  S: string;
begin
  if XEnd < XStart then
    Exit;
  Canvas.Fill.Color := TAlphaColorRec.Gray;
  Canvas.Font.Size := 10;
  for I := 0 to 5 do
  begin
    Sample := XStart +
      Round(I * (XEnd - XStart) / 5);
    if XEnd = XStart then
      X := R.Left
    else
      X := R.Left +
        ((Sample - XStart) / (XEnd - XStart)) * R.Width;
    S := Sample.ToString;
    Canvas.FillText(
      RectF(X - 48, R.Bottom + 3, X + 48, R.Bottom + 19),
      S,
      False,
      1,
      [],
      TTextAlign.Center,
      TTextAlign.Center);
  end;
end;

procedure TSignalPlot.DrawHorizontalGrid(Canvas: TCanvas;
  const R: TRectF; MinY, MaxY: Double);
var
  I: Integer;
  Y, V: Single;
begin
  Canvas.Stroke.Kind := TBrushKind.Solid;
  Canvas.Stroke.Color := TAlphaColorRec.Lightgray;
  Canvas.Stroke.Thickness := 1;
  for I := 0 to 5 do
  begin
    Y := R.Top + I * R.Height / 5;
    Canvas.DrawLine(
      PointF(R.Left, Y),
      PointF(R.Right, Y),
      1);
  end;
  if (MinY <= 0) and (MaxY >= 0) then
  begin
    V := MapY(0, MinY, MaxY, R);
    Canvas.Stroke.Color := TAlphaColorRec.Gray;
    Canvas.Stroke.Thickness := 1.5;
    Canvas.DrawLine(
      PointF(R.Left, V),
      PointF(R.Right, V),
      1);
  end;
end;

procedure TSignalPlot.DrawVerticalGrid(Canvas: TCanvas;
  const R: TRectF);
var
  I: Integer;
  X: Single;
begin
  Canvas.Stroke.Kind := TBrushKind.Solid;
  Canvas.Stroke.Color := TAlphaColorRec.Lightgray;
  Canvas.Stroke.Thickness := 1;
  for I := 0 to 5 do
  begin
    X := R.Left + I * R.Width / 5;
    Canvas.DrawLine(
      PointF(X, R.Top),
      PointF(X, R.Bottom),
      1);
  end;
end;

procedure TSignalPlot.DrawGrid(Canvas: TCanvas;
  const R: TRectF; MinY, MaxY: Double;
  const XStart, XEnd: Int64);
begin
  DrawHorizontalGrid(Canvas, R, MinY, MaxY);
  DrawVerticalGrid(Canvas, R);
  DrawYAxisLabels(Canvas, R, MinY, MaxY);
  DrawXAxisLabelsAbsolute(Canvas, R, XStart, XEnd);
end;

procedure TSignalPlot.DrawRaw(Canvas: TCanvas;
  const R: TRectF; MinY, MaxY: Double);
var
  N, Ch, I, B, B0, B1: Integer;
  PixelCount, Columns: Integer;
  MinV, MaxV, V: Double;
  X, Y1, Y2: Single;
  A: array[0..3] of TAlphaColor;
begin
  N := Length(FData);
  if N = 0 then
    Exit;
  A[0] := TAlphaColorRec.Red;
  A[1] := TAlphaColorRec.Green;
  A[2] := TAlphaColorRec.Blue;
  A[3] := TAlphaColorRec.Orange;

  PixelCount := Max(1, Ceil(R.Width * 2));

  if N <= PixelCount then
  begin
    for Ch := 0 to 3 do
    begin
      Canvas.Stroke.Color := A[Ch];
      Canvas.Stroke.Thickness := 1;
      for I := 1 to N - 1 do
      begin
        case Ch of
          0:
            begin
              Y1 := MapY(FData[I - 1].Ch1, MinY, MaxY, R);
              Y2 := MapY(FData[I].Ch1, MinY, MaxY, R);
            end;
          1:
            begin
              Y1 := MapY(FData[I - 1].Ch2, MinY, MaxY, R);
              Y2 := MapY(FData[I].Ch2, MinY, MaxY, R);
            end;
          2:
            begin
              Y1 := MapY(FData[I - 1].Ch3, MinY, MaxY, R);
              Y2 := MapY(FData[I].Ch3, MinY, MaxY, R);
            end;
        else
          begin
            Y1 := MapY(FData[I - 1].Ch4, MinY, MaxY, R);
            Y2 := MapY(FData[I].Ch4, MinY, MaxY, R);
          end;
        end;
        Canvas.DrawLine(
          PointF(MapX(I - 1, N, R), Y1),
          PointF(MapX(I, N, R), Y2),
          1);
      end;
    end;
    Exit;
  end;

  Columns := Max(1, Ceil(R.Width));
  { Large ranges: min/max envelope per screen column. }
  for Ch := 0 to 3 do
  begin
    Canvas.Stroke.Color := A[Ch];
    Canvas.Stroke.Thickness := 1;
    for B := 0 to Columns - 1 do
    begin
      B0 := Floor(B * N / Columns);
      B1 := Floor((B + 1) * N / Columns) - 1;
      if B0 < 0 then
        B0 := 0;
      if B1 >= N then
        B1 := N - 1;
      if B1 < B0 then
        Continue;

      MinV := MaxDouble;
      MaxV := -MaxDouble;
      for I := B0 to B1 do
      begin
        case Ch of
          0: V := FData[I].Ch1;
          1: V := FData[I].Ch2;
          2: V := FData[I].Ch3;
        else V := FData[I].Ch4;
        end;
        MinV := Min(MinV, V);
        MaxV := Max(MaxV, V);
      end;
      X := R.Left + (B + 0.5) * R.Width / Columns;
      Y1 := MapY(MinV, MinY, MaxY, R);
      Y2 := MapY(MaxV, MinY, MaxY, R);
      Canvas.DrawLine(
        PointF(X, Y1),
        PointF(X, Y2),
        1);
    end;
  end;
end;

procedure TSignalPlot.DrawScalar(Canvas: TCanvas;
  const R: TRectF; const Values: TFloatArray;
  MinY, MaxY: Double);
var
  N, I, B, B0, B1: Integer;
  PixelCount, Columns: Integer;
  MinV, MaxV: Double;
  X, Y1, Y2: Single;
begin
  N := Length(Values);
  if N = 0 then
    Exit;

  Canvas.Stroke.Color := TAlphaColorRec.Navy;
  Canvas.Stroke.Thickness := 1.5;

  PixelCount := Max(1, Ceil(R.Width * 2));

  if N <= PixelCount then
  begin
    for I := 1 to N - 1 do
    begin
      Canvas.DrawLine(
        PointF(
          MapX(I - 1, N, R),
          MapY(Values[I - 1], MinY, MaxY, R)),
        PointF(
          MapX(I, N, R),
          MapY(Values[I], MinY, MaxY, R)),
        1);
    end;
    Exit;
  end;

  Columns := Max(1, Ceil(R.Width));
  for B := 0 to Columns - 1 do
  begin
    B0 := Floor(B * N / Columns);
    B1 := Floor((B + 1) * N / Columns) - 1;
    if B0 < 0 then
      B0 := 0;
    if B1 >= N then
      B1 := N - 1;
    if B1 < B0 then
      Continue;

    MinV := MaxDouble;
    MaxV := -MaxDouble;
    for I := B0 to B1 do
    begin
      MinV := Min(MinV, Values[I]);
      MaxV := Max(MaxV, Values[I]);
    end;
    X := R.Left + (B + 0.5) * R.Width / Columns;
    Y1 := MapY(MinV, MinY, MaxY, R);
    Y2 := MapY(MaxV, MinY, MaxY, R);
    Canvas.DrawLine(
      PointF(X, Y1),
      PointF(X, Y2),
      1);
  end;
end;

procedure TSignalPlot.DrawRawAndFir(Canvas: TCanvas;
  const R: TRectF; MinY, MaxY: Double);
begin
  DrawRaw(Canvas, R, MinY, MaxY);
  if Length(FFir) > 0 then
  begin
    Canvas.Stroke.Color := TAlphaColorRec.Black;
    Canvas.Stroke.Thickness := 2;
    DrawScalar(Canvas, R, FFir, MinY, MaxY);
  end;
end;

procedure TSignalPlot.DrawRaw4Channels(Canvas: TCanvas; const R: TRectF);
const
  Gap = 48;
  BottomAxisSpace = 24;
var
  Ch, I, N, B, B0, B1, Columns: Integer;
  H: Single;
  CR: TRectF;
  MinY, MaxY, V, MinV, MaxV, MaxAbs: Double;
  X, Y1, Y2: Single;
  A: array[0..3] of TAlphaColor;
  Title: string;
  LastGraphBottom: Single;
  PixelCount: Integer;
begin
  N := Length(FData);
  if N = 0 then Exit;

  A[0] := TAlphaColorRec.Red;
  A[1] := TAlphaColorRec.Green;
  A[2] := TAlphaColorRec.Blue;
  A[3] := TAlphaColorRec.Orange;

  MaxAbs := 0;
  for I := 0 to N - 1 do
  begin
    V := Abs(FData[I].Ch1); if V > MaxAbs then MaxAbs := V;
    V := Abs(FData[I].Ch2); if V > MaxAbs then MaxAbs := V;
    V := Abs(FData[I].Ch3); if V > MaxAbs then MaxAbs := V;
    V := Abs(FData[I].Ch4); if V > MaxAbs then MaxAbs := V;
  end;
  if MaxAbs = 0 then MaxAbs := 1;

  MinY := -MaxAbs * 1.05;
  MaxY :=  MaxAbs * 1.05;

  H := (R.Height - 3 * Gap - BottomAxisSpace) / 4;
  if H <= 20 then Exit;
  Columns := Max(1, Ceil(R.Width));
  PixelCount := Max(1, Ceil(R.Width * 2));

  for Ch := 0 to 3 do
  begin
    CR := RectF(
      R.Left,
      R.Top + Ch * (H + Gap),
      R.Right,
      R.Top + Ch * (H + Gap) + H);

    DrawHorizontalGrid(Canvas, CR, MinY, MaxY);
    DrawYAxisLabels(Canvas, CR, MinY, MaxY);

    Canvas.Stroke.Color := A[Ch];
    Canvas.Stroke.Thickness := 1;

    if N <= PixelCount then
    begin
      for I := 1 to N - 1 do
      begin
        case Ch of
          0: begin Y1 := MapY(FData[I-1].Ch1, MinY, MaxY, CR);
                   Y2 := MapY(FData[I].Ch1, MinY, MaxY, CR); end;
          1: begin Y1 := MapY(FData[I-1].Ch2, MinY, MaxY, CR);
                   Y2 := MapY(FData[I].Ch2, MinY, MaxY, CR); end;
          2: begin Y1 := MapY(FData[I-1].Ch3, MinY, MaxY, CR);
                   Y2 := MapY(FData[I].Ch3, MinY, MaxY, CR); end;
        else begin Y1 := MapY(FData[I-1].Ch4, MinY, MaxY, CR);
                   Y2 := MapY(FData[I].Ch4, MinY, MaxY, CR); end;
        end;
        Canvas.DrawLine(
          PointF(MapX(I-1, N, CR), Y1),
          PointF(MapX(I, N, CR), Y2),
          1);
      end;
    end
    else
    begin
      for B := 0 to Columns - 1 do
      begin
        B0 := Floor(B * N / Columns);
        B1 := Floor((B + 1) * N / Columns) - 1;
        if B0 < 0 then B0 := 0;
        if B1 >= N then B1 := N - 1;
        if B1 < B0 then Continue;

        MinV := MaxDouble;
        MaxV := -MaxDouble;
        for I := B0 to B1 do
        begin
          case Ch of
            0: V := FData[I].Ch1;
            1: V := FData[I].Ch2;
            2: V := FData[I].Ch3;
          else V := FData[I].Ch4;
          end;
          MinV := Min(MinV, V);
          MaxV := Max(MaxV, V);
        end;

        X := CR.Left + (B + 0.5) * CR.Width / Columns;
        Y1 := MapY(MinV, MinY, MaxY, CR);
        Y2 := MapY(MaxV, MinY, MaxY, CR);
        Canvas.DrawLine(PointF(X, Y1), PointF(X, Y2), 1);
      end;
    end;

    Canvas.Fill.Color := A[Ch];
    Canvas.Font.Size := 11;
    Title := Format('Channel %d', [Ch + 1]);
    Canvas.FillText(
      RectF(CR.Left + 3, CR.Top + 2, CR.Left + 95, CR.Top + 18),
      Title, False, 1, [],
      TTextAlign.Leading, TTextAlign.Center);
  end;

  LastGraphBottom := R.Top + 3 * (H + Gap) + H;
  Canvas.Stroke.Kind := TBrushKind.Solid;
  Canvas.Stroke.Color := TAlphaColorRec.Lightgray;
  Canvas.Stroke.Thickness := 1;
  for I := 0 to 5 do
  begin
    X := R.Left + I * R.Width / 5;
    Canvas.DrawLine(PointF(X, R.Top), PointF(X, LastGraphBottom), 1);
  end;
  DrawXAxisLabelsAbsolute(
    Canvas,
    RectF(R.Left, LastGraphBottom, R.Right, LastGraphBottom + BottomAxisSpace),
    FStartFrame,
    FStartFrame + N - 1);
end;

procedure TSignalPlot.DrawHistogram(Canvas: TCanvas;
  const R: TRectF);
const
  MaxBins = 200;
var
  I, Count, Bin, NumBins: Integer;
  P1, P2: Int64;
  DeltaSamples: Int64;
  Ms, MaxMs, BinWidth, X, Y, H, MaxCount: Double;
  Bins: array of Integer;
  S: string;
  AxisMax: Integer;
begin
  Count := Length(FPeakPositions);
  if Count < 2 then
    Exit;
  if FHistogramEnd < FHistogramStart then
    Exit;

  MaxMs := 0;
  for I := 0 to Count - 2 do
  begin
    P1 := FPeakPositions[I];
    P2 := FPeakPositions[I + 1];
    if (P1 < FHistogramStart) or (P1 > FHistogramEnd) then
      Continue;
    DeltaSamples := P2 - P1;
    if DeltaSamples <= 0 then
      Continue;
    Ms := DeltaSamples * 1000.0 / FSampleRate;
    if Ms > MaxMs then
      MaxMs := Ms;
  end;
  if MaxMs <= 0 then
    Exit;

  AxisMax := Ceil(MaxMs);
  if AxisMax < 10 then
    AxisMax := 10;
  NumBins := Min(MaxBins, AxisMax);
  if NumBins < 1 then
    NumBins := 1;
  SetLength(Bins, NumBins);

  MaxCount := 0;
  BinWidth := AxisMax / NumBins;
  for I := 0 to Count - 2 do
  begin
    P1 := FPeakPositions[I];
    P2 := FPeakPositions[I + 1];
    if (P1 < FHistogramStart) or (P1 > FHistogramEnd) then
      Continue;
    DeltaSamples := P2 - P1;
    if DeltaSamples <= 0 then
      Continue;
    Ms := DeltaSamples * 1000.0 / FSampleRate;
    Bin := Floor(Ms / BinWidth);
    if Bin = NumBins then
      Bin := NumBins - 1;
    if (Bin >= 0) and (Bin < NumBins) then
    begin
      Inc(Bins[Bin]);
      if Bins[Bin] > MaxCount then
        MaxCount := Bins[Bin];
    end;
  end;

  if MaxCount <= 0 then
    Exit;

  Canvas.Stroke.Kind := TBrushKind.Solid;
  Canvas.Stroke.Color := TAlphaColorRec.Lightgray;
  Canvas.Stroke.Thickness := 1;
  for I := 0 to 5 do
  begin
    Y := R.Top + I * R.Height / 5;
    Canvas.DrawLine(
      PointF(R.Left, Y),
      PointF(R.Right, Y),
      1);
  end;
  for I := 0 to 10 do
  begin
    X := R.Left + I * R.Width / 10;
    Canvas.DrawLine(
      PointF(X, R.Top),
      PointF(X, R.Bottom),
      1);
  end;

  BinWidth := R.Width / NumBins;
  Canvas.Fill.Color := TAlphaColorRec.Navy;
  Canvas.Fill.Kind := TBrushKind.Solid;
  for I := 0 to NumBins - 1 do
  begin
    if Bins[I] = 0 then
      Continue;
    X := R.Left + I * BinWidth;
    H := Bins[I] / MaxCount * R.Height;
    Y := R.Bottom - H;
//    Canvas.FillRect(RectF(X + 1, Y, X + BinWidth - 1, R.Bottom), 0, 0, [], 1);
    if BinWidth < 2 then
      Canvas.FillRect(RectF(X, Y, X + BinWidth, R.Bottom), 0, 0, [], 1)
    else
      Canvas.FillRect(RectF(X + 1, Y, X + BinWidth - 1, R.Bottom), 0, 0, [], 1);
  end;

  Canvas.Fill.Color := TAlphaColorRec.Gray;
  Canvas.Font.Size := 10;
  for I := 0 to 10 do
  begin
    Ms := I * AxisMax / 10.0;
    X := R.Left + I * R.Width / 10;
    S := FormatFloat('0.0', Ms) + ' ms';
    Canvas.FillText(
      RectF(X - 35, R.Bottom + 3, X + 35, R.Bottom + 19),
      S, False, 1, [],
      TTextAlign.Center, TTextAlign.Center);
  end;
  for I := 0 to 5 do
  begin
    S := IntToStr(Round(I * MaxCount / 5));
    Y := R.Bottom - I * R.Height / 5;
    Canvas.FillText(
      RectF(2, Y - 9, R.Left - 4, Y + 9),
      S, False, 1, [],
      TTextAlign.Trailing, TTextAlign.Center);
  end;
end;

procedure TSignalPlot.PaintBoxPaint(Sender: TObject; Canvas: TCanvas);
const
  MarginL = 78;
  MarginR = 12;
  MarginT = 28;
  MarginB = 34;
var
  FullR, R: TRectF;
  I, N, Ch: Integer;
  MinY, MaxY, V: Double;
  S: string;
  PeakX, X: Single;
  PlotTitle: string;
  MaxAbs: Double;
begin
  FullR := RectF(0, 0, FPaintBox.Width, FPaintBox.Height);
  Canvas.Fill.Kind := TBrushKind.Solid;
  Canvas.Fill.Color := TAlphaColorRec.White;
  Canvas.FillRect(FullR, 0, 0, [], 1);

  R := RectF(
    MarginL,
    MarginT,
    FPaintBox.Width - MarginR,
    FPaintBox.Height - MarginB);

  case FMode of
    pmRaw: PlotTitle := 'RAW - 4 channels';
    pmStd: PlotTitle := 'STD';
    pmFir15: PlotTitle := 'FIR15';
    pmRawAndFir15: PlotTitle := 'RAW + FIR15';
    pmRaw4Channels: PlotTitle := 'RAW - 4 channels (separate)';
    pmHistogram: PlotTitle := 'IPI histogram';
  end;

  if FTitle <> '' then
    PlotTitle := FTitle + '  [' + PlotTitle + ']';

  Canvas.Fill.Color := TAlphaColorRec.Black;
  Canvas.Font.Size := 13;
  Canvas.FillText(
    RectF(4, 2, FPaintBox.Width - 4, 22),
    PlotTitle, False, 1, [],
    TTextAlign.Leading, TTextAlign.Center);

  case FMode of
    pmRaw, pmRawAndFir15: N := Length(FData);
    pmStd: N := Length(FStd);
    pmFir15: N := Length(FFir);
    pmRaw4Channels: N := Length(FData);
    pmHistogram: N := 1;
  end;

  if FMode = pmHistogram then
  begin
    DrawHistogram(Canvas, R);
    if FHistogramEnd >= FHistogramStart then
      S := Format('IPI range: %d .. %d samples  (%.3f .. %.3f s)',
        [FHistogramStart, FHistogramEnd,
         FHistogramStart / FSampleRate, FHistogramEnd / FSampleRate])
    else
      S := 'IPI histogram: no range selected';
    Canvas.Fill.Color := TAlphaColorRec.Gray;
    Canvas.Font.Size := 11;
    Canvas.FillText(
      RectF(MarginL, FPaintBox.Height - 22, FPaintBox.Width - 5, FPaintBox.Height),
      S, False, 1, [],
      TTextAlign.Leading, TTextAlign.Center);
    Exit;
  end;
{ EODPK envelope is a RAW representation. The layout (single overlaid
  graph vs. four separate graphs) must depend on the current mode ONLY,
  never on the zoom level. }
if FEnvelopeActive and
   ((FMode = pmRaw) or (FMode = pmRaw4Channels)) then
begin
  if FMode = pmRaw4Channels then
    DrawEnvelope4Channels(Canvas, R)
  else
    DrawEnvelopeSingle(Canvas, R);

  { selected position / peak marker if needed }

  Exit;
end;


{ Normal non-envelope data. }
case FMode of
  pmRaw, pmRawAndFir15: N := Length(FData);
  pmStd: N := Length(FStd);
  pmFir15: N := Length(FFir);
  pmRaw4Channels: N := Length(FData);
end;
  if N = 0 then
    Exit;

  if FMode = pmRaw4Channels then
  begin
//    DrawRaw4Channels(Canvas, R);
    if FEnvelopeActive then
      DrawEnvelope4Channels(Canvas, R)
    else
      DrawRaw4Channels(Canvas, R);
    if (FSelectedOffset >= 0) and (FSelectedOffset < N) then
    begin
      X := MapX(FSelectedOffset, N, R);
      Canvas.Stroke.Color := TAlphaColorRec.Dimgray;
      Canvas.Stroke.Thickness := 1;
      Canvas.DrawLine(PointF(X, R.Top), PointF(X, R.Bottom), 1);
    end;
    if FShowPeakLine and (FPeakOffset >= 0) and (FPeakOffset < N) then
    begin
      PeakX := MapX(FPeakOffset, N, R);
      Canvas.Stroke.Color := TAlphaColorRec.Black;
      Canvas.Stroke.Thickness := 1;
      Canvas.DrawLine(PointF(PeakX, R.Top), PointF(PeakX, R.Bottom), 1);
    end;
    S := Format('Start sample: %d    End sample: %d    Duration: %.3f ms',
      [FStartFrame, FStartFrame + N - 1, N * 1000.0 / FSampleRate]);
    Canvas.Fill.Color := TAlphaColorRec.Gray;
    Canvas.Font.Size := 11;
    Canvas.FillText(
      RectF(MarginL, FPaintBox.Height - 22, FPaintBox.Width - 5, FPaintBox.Height),
      S, False, 1, [],
      TTextAlign.Leading, TTextAlign.Center);
    Exit;
  end;

  { Determine one common Y scale for ordinary single-plot modes. }
  MinY := MaxDouble;
  MaxY := -MaxDouble;
  if (FMode = pmRaw) then
  begin
    MaxAbs := 0;
    for I := 0 to N - 1 do
    begin
      V := Abs(FData[I].Ch1); if V > MaxAbs then MaxAbs := V;
      V := Abs(FData[I].Ch2); if V > MaxAbs then MaxAbs := V;
      V := Abs(FData[I].Ch3); if V > MaxAbs then MaxAbs := V;
      V := Abs(FData[I].Ch4); if V > MaxAbs then MaxAbs := V;
    end;
    if MaxAbs = 0 then MaxAbs := 1;
    MinY := -MaxAbs * 1.05;
    MaxY :=  MaxAbs * 1.05;
  end
  else if FMode = pmRawAndFir15 then
  begin
    MaxAbs := 0;
    for I := 0 to Length(FData) - 1 do
    begin
      V := Abs(FData[I].Ch1); if V > MaxAbs then MaxAbs := V;
      V := Abs(FData[I].Ch2); if V > MaxAbs then MaxAbs := V;
      V := Abs(FData[I].Ch3); if V > MaxAbs then MaxAbs := V;
      V := Abs(FData[I].Ch4); if V > MaxAbs then MaxAbs := V;
    end;
    for I := 0 to Length(FFir) - 1 do
    begin
      V := Abs(FFir[I]); if V > MaxAbs then MaxAbs := V;
    end;
    if MaxAbs = 0 then MaxAbs := 1;
    MinY := -MaxAbs * 1.05;
    MaxY :=  MaxAbs * 1.05;
  end
  else if FMode = pmStd then
  begin
    MaxY := 0;
    for I := 0 to N - 1 do
    begin
      V := FStd[I];
      if V > MaxY then MaxY := V;
    end;
    MinY := 0;
  end
  else if FMode = pmFir15 then
  begin
    MaxY := 0;
    for I := 0 to N - 1 do
    begin
      V := FFir[I];
      if V > MaxY then MaxY := V;
    end;
    MinY := 0;
  end;

  if (FMode <> pmRaw) and
     (FMode <> pmRawAndFir15) and
     (FMode <> pmRaw4Channels) and
     (FMode <> pmHistogram) then
  begin
    if (FMode = pmStd) or (FMode = pmFir15) then
    begin
      MinY := 0;
      if MaxY <= 0 then MaxY := 1;
      MaxY := MaxY * 1.05;
    end
    else
    begin
      if SameValue(MinY, MaxY) then
      begin
        MinY := MinY - 1;
        MaxY := MaxY + 1;
      end
      else
      begin
        V := (MaxY - MinY) * 0.05;
        MinY := MinY - V;
        MaxY := MaxY + V;
      end;
    end;
  end;

  DrawGrid(Canvas, R, MinY, MaxY, FStartFrame, FStartFrame + N - 1);

  case FMode of
    pmRaw: DrawRaw(Canvas, R, MinY, MaxY);
    pmStd: DrawScalar(Canvas, R, FStd, MinY, MaxY);
    pmFir15:
      begin
        Canvas.Stroke.Color := TAlphaColorRec.Darkgreen;
        DrawScalar(Canvas, R, FFir, MinY, MaxY);
      end;
    pmRawAndFir15: DrawRawAndFir(Canvas, R, MinY, MaxY);
  end;

  { Selected sample. }
  if (FSelectedOffset >= 0) and (FSelectedOffset < N) then
  begin
    X := MapX(FSelectedOffset, N, R);
    Canvas.Stroke.Color := TAlphaColorRec.Dimgray;
    Canvas.Stroke.Thickness := 1;
    Canvas.DrawLine(PointF(X, R.Top), PointF(X, R.Bottom), 1);
  end;

  { Peak marker. }
  if FShowPeakLine and (FPeakOffset >= 0) and (FPeakOffset < N) then
  begin
    PeakX := MapX(FPeakOffset, N, R);
    Canvas.Stroke.Color := TAlphaColorRec.Black;
    Canvas.Stroke.Thickness := 1;
    Canvas.DrawLine(PointF(PeakX, R.Top), PointF(PeakX, R.Bottom), 1);
  end;

  S := Format('Start sample: %d    End sample: %d    Duration: %.3f ms',
    [FStartFrame, FStartFrame + N - 1, N * 1000.0 / FSampleRate]);
  Canvas.Fill.Color := TAlphaColorRec.Gray;
  Canvas.Font.Size := 11;
  Canvas.FillText(
    RectF(MarginL, FPaintBox.Height - 22, FPaintBox.Width - 5, FPaintBox.Height),
    S, False, 1, [],
    TTextAlign.Leading, TTextAlign.Center);
end;

procedure TSignalPlot.SetChannels(
  const Data: TAudioChunk;
  StartFrame: Int64;
  SampleRate: Integer;
  PeakFrame: Int64;
  const ATitle: string);
begin
  FData := Copy(Data);
  FStartFrame := StartFrame;
  FSampleRate := SampleRate;
  FTitle := ATitle;
  UpdatePeakOffset(PeakFrame);
  FSelectedOffset := -1;
  { Raw channel data replaces any previously shown envelope. Leaving the
    envelope active would make PaintBox keep drawing the stale envelope
    (and hide the raw signal) after the user zooms back in. }
  SetLength(FEnvelope, 0);
  FEnvelopeActive := False;
  RequestRepaint;
end;

procedure TSignalPlot.SetStd(
  const Data: TFloatArray;
  StartFrame: Int64;
  SampleRate: Integer;
  PeakFrame: Int64;
  const ATitle: string);
begin
  FStd := Copy(Data);
  FStartFrame := StartFrame;
  FSampleRate := SampleRate;
  FTitle := ATitle;
  UpdatePeakOffset(PeakFrame);
  FSelectedOffset := -1;
  RequestRepaint;
end;

procedure TSignalPlot.SetFir(
  const Data: TFloatArray;
  StartFrame: Int64;
  SampleRate: Integer;
  PeakFrame: Int64;
  const ATitle: string);
begin
  FFir := Copy(Data);
  FStartFrame := StartFrame;
  FSampleRate := SampleRate;
  FTitle := ATitle;
  UpdatePeakOffset(PeakFrame);
  FSelectedOffset := -1;
  RequestRepaint;
end;

procedure TSignalPlot.SetPeakPositions(
  const Positions: array of Int64);
var
  I: Integer;
begin
  SetLength(FPeakPositions, Length(Positions));
  for I := 0 to High(Positions) do
    FPeakPositions[I] := Positions[I];
  if (Length(FPeakPositions) > 0) and
     (FHistogramEnd < FHistogramStart) then
  begin
    FHistogramStart := FPeakPositions[0];
    FHistogramEnd := FPeakPositions[High(FPeakPositions)];
  end;
  RequestRepaint;
end;

procedure TSignalPlot.SetHistogramRange(
  StartFrame, EndFrame: Int64);
begin
  if EndFrame < StartFrame then
  begin
    FHistogramStart := EndFrame;
    FHistogramEnd := StartFrame;
  end
  else
  begin
    FHistogramStart := StartFrame;
    FHistogramEnd := EndFrame;
  end;
  RequestRepaint;
end;

procedure TSignalPlot.SetSelectedPosition(AFrame: Int64);
begin
  if (Length(FData) > 0) or
     (Length(FStd) > 0) or
     (Length(FFir) > 0) then
  begin
    FSelectedOffset := Integer(AFrame - FStartFrame);
  end
  else
    FSelectedOffset := -1;
  RequestRepaint;
end;

procedure TSignalPlot.SetEnvelope(
  const Envelope: TWaveEnvelope;
  StartFrame, EndFrame: Int64;
  SampleRate: Integer;
  const ATitle: string);
begin
  SetLength(FData, 0);
  SetLength(FStd, 0);
  SetLength(FFir, 0);

  FEnvelope := Copy(Envelope);
  FEnvelopeActive := Length(FEnvelope) > 0;

  FStartFrame := StartFrame;
  FSampleRate := SampleRate;
  FTitle := ATitle;

  FSelectedOffset := -1;
  FPeakOffset := -1;
  FShowPeakLine := False;

  { IMPORTANT: do NOT touch the full range here.
    The full range is the whole file and is configured once when the
    file is opened. Overwriting it with the current view would make the
    plot believe it is already fully zoomed out and silently block any
    further zoom-out. Only the current view range is updated. }
  SetViewRange(StartFrame, EndFrame);
end;

procedure TSignalPlot.DrawEnvelope4Channels(
  Canvas: TCanvas;
  const R: TRectF);
const
  Gap = 6;
var
  Ch: Integer;
  H: Single;
  CR: TRectF;

  MinY, MaxY: Double;
  VMin, VMax: Double;

  A: array[0..3] of TAlphaColor;

  ViewWidth: Int64;
  PlotWidth: Integer;

  I, B: Integer;
  B0, B1: Integer;
  VisibleCount: Integer;

  P: TWaveEnvelopePoint;

  CenterFrame: Int64;

  X: Single;
  Y1, Y2: Single;

  ColumnMin: Double;
  ColumnMax: Double;

  EnvStart, EnvEnd: Int64;
  FirstVisible, LastVisible: Integer;

  function PointMin(const P: TWaveEnvelopePoint): Double;
  begin
    case Ch of
      0: Result := P.Ch1Min;
      1: Result := P.Ch2Min;
      2: Result := P.Ch3Min;
    else
      Result := P.Ch4Min;
    end;
  end;

  function PointMax(const P: TWaveEnvelopePoint): Double;
  begin
    case Ch of
      0: Result := P.Ch1Max;
      1: Result := P.Ch2Max;
      2: Result := P.Ch3Max;
    else
      Result := P.Ch4Max;
    end;
  end;

begin
  if Length(FEnvelope) = 0 then
    Exit;

  if (FViewEnd <= FViewStart) then
    Exit;

  if R.Width <= 0 then
    Exit;

  ViewWidth := FViewEnd - FViewStart;
  if ViewWidth <= 0 then
    Exit;

  A[0] := TAlphaColorRec.Red;
  A[1] := TAlphaColorRec.Green;
  A[2] := TAlphaColorRec.Blue;
  A[3] := TAlphaColorRec.Orange;

  H := (R.Height - 3 * Gap) / 4.0;
  if H <= 1 then
    Exit;

  PlotWidth := Max(1, Ceil(R.Width));

  { --------------------------------------------------------------- }
  { Find visible envelope indices.                                  }
  { This is important: don't process the entire envelope when only  }
  { a small part of it is currently visible.                        }
  { --------------------------------------------------------------- }

  FirstVisible := -1;
  LastVisible := -1;

  for I := 0 to High(FEnvelope) do
  begin
    EnvStart := FEnvelope[I].StartPosition;
    EnvEnd   := FEnvelope[I].EndPosition;

    if EnvEnd < FViewStart then
      Continue;

    if EnvStart > FViewEnd then
      Break;

    if FirstVisible < 0 then
      FirstVisible := I;

    LastVisible := I;
  end;

  if FirstVisible < 0 then
    Exit;

  { --------------------------------------------------------------- }
  { Four independent channel plots.                                 }
  { --------------------------------------------------------------- }

  for Ch := 0 to 3 do
  begin
    CR := RectF(
      R.Left,
      R.Top + Ch * (H + Gap),
      R.Right,
      R.Top + Ch * (H + Gap) + H);

    { ------------------------------------------------------------- }
    { Y scale.                                                       }
    { IMPORTANT: calculate it from the visible data, not from the   }
    { entire envelope.                                               }
    { ------------------------------------------------------------- }

    MinY := MaxDouble;
    MaxY := -MaxDouble;

    for I := FirstVisible to LastVisible do
    begin
      P := FEnvelope[I];

      VMin := PointMin(P);
      VMax := PointMax(P);

      if VMin < MinY then
        MinY := VMin;

      if VMax > MaxY then
        MaxY := VMax;
    end;

    if (MinY = MaxDouble) or
       (MaxY = -MaxDouble) then
      Continue;

    if Abs(MaxY - MinY) < 1E-12 then
    begin
      MinY := MinY - 1;
      MaxY := MaxY + 1;
    end
    else
    begin
      VMin := (MaxY - MinY) * 0.05;
      MinY := MinY - VMin;
      MaxY := MaxY + VMin;
    end;

    DrawHorizontalGrid(Canvas, CR, MinY, MaxY);

    Canvas.Stroke.Kind := TBrushKind.Solid;
    Canvas.Stroke.Color := A[Ch];
    Canvas.Stroke.Thickness := 1;

    { ------------------------------------------------------------- }
    { NORMAL MODE                                                     }
    { Small view: draw every envelope point.                        }
    { ------------------------------------------------------------- }

    { Choose the drawing strategy by how many envelope points fall in
      the view versus the number of screen columns. This is independent
      of the absolute zoom level and prevents a single wide bucket from
      being stretched across many columns (which looked like squares). }
    if (LastVisible - FirstVisible + 1) <= PlotWidth then
    begin
      for I := FirstVisible to LastVisible do
      begin
        P := FEnvelope[I];

        CenterFrame :=
          P.StartPosition +
          (P.EndPosition - P.StartPosition) div 2;

        if CenterFrame < FViewStart then
          Continue;

        if CenterFrame > FViewEnd then
          Continue;

        X :=
          CR.Left +
          ((CenterFrame - FViewStart) / ViewWidth) *
          CR.Width;

        VMin := PointMin(P);
        VMax := PointMax(P);

        Y1 := MapY(VMin, MinY, MaxY, CR);
        Y2 := MapY(VMax, MinY, MaxY, CR);

        Canvas.DrawLine(
          PointF(X, Y1),
          PointF(X, Y2),
          1);
      end;
    end

    { ------------------------------------------------------------- }
    { REDUCED RESOLUTION MODE                                        }
    { Large view: one min/max envelope per screen column.            }
    { ------------------------------------------------------------- }

//    else
//    begin
//      for B := 0 to PlotWidth - 1 do
//      begin
//        { Frame range represented by this screen column. }
//        EnvStart :=
//          FViewStart +
//          Floor((B / PlotWidth) * ViewWidth);
//
//        EnvEnd :=
//          FViewStart +
//          Floor(((B + 1) / PlotWidth) * ViewWidth) - 1;
//
//        if EnvEnd < EnvStart then
//          EnvEnd := EnvStart;
//
//        { Find envelope points belonging to this screen column. }
//        ColumnMin := MaxDouble;
//        ColumnMax := -MaxDouble;
//
//        for I := FirstVisible to LastVisible do
//        begin
//          P := FEnvelope[I];
//
//          CenterFrame :=
//            P.StartPosition +
//            (P.EndPosition - P.StartPosition) div 2;
//
//          if CenterFrame < EnvStart then
//            Continue;
//
//          if CenterFrame > EnvEnd then
//            Break;
//
//          VMin := PointMin(P);
//          VMax := PointMax(P);
//
//          if VMin < ColumnMin then
//            ColumnMin := VMin;
//
//          if VMax > ColumnMax then
//            ColumnMax := VMax;
//        end;
//
//        if ColumnMin = MaxDouble then
//          Continue;
//
//        X :=
//          CR.Left +
//          (B + 0.5) * CR.Width / PlotWidth;
//
//        Y1 := MapY(ColumnMin, MinY, MaxY, CR);
//        Y2 := MapY(ColumnMax, MinY, MaxY, CR);
//
//        Canvas.DrawLine(
//          PointF(X, Y1),
//          PointF(X, Y2),
//          1);
//      end;
//    end;
    { More envelope points than screen columns: aggregate by point
      INDEX, not by frame range. Bucketing by index guarantees that a
      single (possibly wide) envelope bucket contributes to exactly one
      screen column, so the plot can no longer degrade into solid
      rectangular blocks. }
    else
    begin
      VisibleCount := LastVisible - FirstVisible + 1;

      for B := 0 to PlotWidth - 1 do
      begin
        B0 := FirstVisible + (Int64(B) * VisibleCount) div PlotWidth;
        B1 := FirstVisible + (Int64(B + 1) * VisibleCount) div PlotWidth - 1;

        if B0 < FirstVisible then
          B0 := FirstVisible;
        if B1 > LastVisible then
          B1 := LastVisible;
        if B1 < B0 then
          Continue;

        ColumnMin := MaxDouble;
        ColumnMax := -MaxDouble;

        for I := B0 to B1 do
        begin
          P := FEnvelope[I];

          VMin := PointMin(P);
          VMax := PointMax(P);

          if VMin < ColumnMin then
            ColumnMin := VMin;

          if VMax > ColumnMax then
            ColumnMax := VMax;
        end;

        if ColumnMin = MaxDouble then
          Continue;

        X := CR.Left + (B + 0.5) * CR.Width / PlotWidth;

        Y1 := MapY(ColumnMin, MinY, MaxY, CR);
        Y2 := MapY(ColumnMax, MinY, MaxY, CR);

        Canvas.DrawLine(
          PointF(X, Y1),
          PointF(X, Y2),
          1);
      end;
    end;
    { Channel label }
    Canvas.Fill.Color := A[Ch];
    Canvas.Font.Size := 11;

    Canvas.FillText(
      RectF(
        CR.Left + 3,
        CR.Top + 2,
        CR.Left + 95,
        CR.Top + 18),
      Format('Channel %d', [Ch + 1]),
      False,
      1,
      [],
      TTextAlign.Leading,
      TTextAlign.Center);
  end;
end;

procedure TSignalPlot.DrawEnvelopeSingle(
  Canvas: TCanvas;
  const R: TRectF);
var
  Ch: Integer;

  MinY, MaxY: Double;
  VMin, VMax: Double;

  A: array[0..3] of TAlphaColor;

  ViewWidth: Int64;
  PlotWidth: Integer;

  I, B: Integer;
  B0, B1: Integer;
  VisibleCount: Integer;

  P: TWaveEnvelopePoint;

  CenterFrame: Int64;

  X: Single;
  Y1, Y2: Single;

  ColumnMin: Double;
  ColumnMax: Double;

  EnvStart, EnvEnd: Int64;
  FirstVisible, LastVisible: Integer;

  function PointMin(const P: TWaveEnvelopePoint): Double;
  begin
    case Ch of
      0: Result := P.Ch1Min;
      1: Result := P.Ch2Min;
      2: Result := P.Ch3Min;
    else
      Result := P.Ch4Min;
    end;
  end;

  function PointMax(const P: TWaveEnvelopePoint): Double;
  begin
    case Ch of
      0: Result := P.Ch1Max;
      1: Result := P.Ch2Max;
      2: Result := P.Ch3Max;
    else
      Result := P.Ch4Max;
    end;
  end;

begin
  if Length(FEnvelope) = 0 then
    Exit;

  if (FViewEnd <= FViewStart) then
    Exit;

  if R.Width <= 0 then
    Exit;

  ViewWidth := FViewEnd - FViewStart;
  if ViewWidth <= 0 then
    Exit;

  A[0] := TAlphaColorRec.Red;
  A[1] := TAlphaColorRec.Green;
  A[2] := TAlphaColorRec.Blue;
  A[3] := TAlphaColorRec.Orange;

  PlotWidth := Max(1, Ceil(R.Width));

  { --------------------------------------------------------------- }
  { Find visible envelope indices.                                  }
  { --------------------------------------------------------------- }

  FirstVisible := -1;
  LastVisible := -1;

  for I := 0 to High(FEnvelope) do
  begin
    EnvStart := FEnvelope[I].StartPosition;
    EnvEnd   := FEnvelope[I].EndPosition;

    if EnvEnd < FViewStart then
      Continue;

    if EnvStart > FViewEnd then
      Break;

    if FirstVisible < 0 then
      FirstVisible := I;

    LastVisible := I;
  end;

  if FirstVisible < 0 then
    Exit;

  { --------------------------------------------------------------- }
  { One common Y scale across all four channels, from visible data. }
  { --------------------------------------------------------------- }

  MinY := MaxDouble;
  MaxY := -MaxDouble;

  for I := FirstVisible to LastVisible do
  begin
    P := FEnvelope[I];

    for Ch := 0 to 3 do
    begin
      VMin := PointMin(P);
      VMax := PointMax(P);

      if VMin < MinY then
        MinY := VMin;

      if VMax > MaxY then
        MaxY := VMax;
    end;
  end;

  if (MinY = MaxDouble) or
     (MaxY = -MaxDouble) then
    Exit;

  if Abs(MaxY - MinY) < 1E-12 then
  begin
    MinY := MinY - 1;
    MaxY := MaxY + 1;
  end
  else
  begin
    VMin := (MaxY - MinY) * 0.05;
    MinY := MinY - VMin;
    MaxY := MaxY + VMin;
  end;

  DrawGrid(Canvas, R, MinY, MaxY, FViewStart, FViewEnd);

  { --------------------------------------------------------------- }
  { Draw all four channels overlaid on the same graph.              }
  { --------------------------------------------------------------- }

  for Ch := 0 to 3 do
  begin
    Canvas.Stroke.Kind := TBrushKind.Solid;
    Canvas.Stroke.Color := A[Ch];
    Canvas.Stroke.Thickness := 1;

    if (LastVisible - FirstVisible + 1) <= PlotWidth then
    begin
      for I := FirstVisible to LastVisible do
      begin
        P := FEnvelope[I];

        CenterFrame :=
          P.StartPosition +
          (P.EndPosition - P.StartPosition) div 2;

        if CenterFrame < FViewStart then
          Continue;

        if CenterFrame > FViewEnd then
          Continue;

        X :=
          R.Left +
          ((CenterFrame - FViewStart) / ViewWidth) *
          R.Width;

        VMin := PointMin(P);
        VMax := PointMax(P);

        Y1 := MapY(VMin, MinY, MaxY, R);
        Y2 := MapY(VMax, MinY, MaxY, R);

        Canvas.DrawLine(
          PointF(X, Y1),
          PointF(X, Y2),
          1);
      end;
    end
    else
    begin
      VisibleCount := LastVisible - FirstVisible + 1;

      for B := 0 to PlotWidth - 1 do
      begin
        B0 := FirstVisible + (Int64(B) * VisibleCount) div PlotWidth;
        B1 := FirstVisible + (Int64(B + 1) * VisibleCount) div PlotWidth - 1;

        if B0 < FirstVisible then
          B0 := FirstVisible;
        if B1 > LastVisible then
          B1 := LastVisible;
        if B1 < B0 then
          Continue;

        ColumnMin := MaxDouble;
        ColumnMax := -MaxDouble;

        for I := B0 to B1 do
        begin
          P := FEnvelope[I];

          VMin := PointMin(P);
          VMax := PointMax(P);

          if VMin < ColumnMin then
            ColumnMin := VMin;

          if VMax > ColumnMax then
            ColumnMax := VMax;
        end;

        if ColumnMin = MaxDouble then
          Continue;

        X := R.Left + (B + 0.5) * R.Width / PlotWidth;

        Y1 := MapY(ColumnMin, MinY, MaxY, R);
        Y2 := MapY(ColumnMax, MinY, MaxY, R);

        Canvas.DrawLine(
          PointF(X, Y1),
          PointF(X, Y2),
          1);
      end;
    end;
  end;
end;
{ ------------------------------------------------------------------ }
{ TOverviewPlot                                                      }
{ ------------------------------------------------------------------ }


constructor TOverviewPlot.Create(APaintBox: TPaintBox);
begin
  inherited Create;

  if not Assigned(APaintBox) then
    raise EArgumentNilException.Create(
      'TOverviewPlot requires a TPaintBox');

  FPaintBox := APaintBox;

  FPaintBox.OnPaint := PaintBoxPaint;
  FPaintBox.OnMouseDown := PaintBoxMouseDown;
  FPaintBox.OnMouseMove := PaintBoxMouseMove;
  FPaintBox.OnMouseUp := PaintBoxMouseUp;
  FPaintBox.HitTest := True;

  FFullStart := 0;
  FFullEnd := 0;
  FViewStart := 0;
  FViewEnd := 0;

  FDragging := False;
  FDragIsSelection := False;
end;

destructor TOverviewPlot.Destroy;
begin
  if Assigned(FPaintBox) then
  begin
    FPaintBox.OnPaint := nil;
    FPaintBox.OnMouseDown := nil;
    FPaintBox.OnMouseMove := nil;
    FPaintBox.OnMouseUp := nil;
  end;

  FPaintBox := nil;
  inherited;
end;

procedure TOverviewPlot.Clear;
var
  Ch: Integer;
begin
  SetLength(FMinValues, 0);
  SetLength(FMaxValues, 0);

  for Ch := 0 to 3 do
  begin
    SetLength(FChannelMin[Ch], 0);
    SetLength(FChannelMax[Ch], 0);
  end;

  FFullStart := 0;
  FFullEnd := 0;
  FViewStart := 0;
  FViewEnd := 0;

  if Assigned(FPaintBox) then
    FPaintBox.Repaint;
end;

procedure TOverviewPlot.SetData(
  const AMinValues, AMaxValues: TFloatArray;
  AFullStart, AFullEnd: Int64);
begin
  FMinValues := Copy(AMinValues);
  FMaxValues := Copy(AMaxValues);

  FFullStart := AFullStart;
  FFullEnd := AFullEnd;

  if FFullEnd < FFullStart then
  begin
    FFullStart := 0;
    FFullEnd := 0;
  end;

  if Assigned(FPaintBox) then
    FPaintBox.Repaint;
end;

procedure TOverviewPlot.SetChannelData(
  const AMinValues, AMaxValues: TChannelEnvelopes;
  AFullStart, AFullEnd: Int64);
var
  Ch: Integer;
begin
  for Ch := 0 to 3 do
  begin
    FChannelMin[Ch] := Copy(AMinValues[Ch]);
    FChannelMax[Ch] := Copy(AMaxValues[Ch]);
  end;

  FFullStart := AFullStart;
  FFullEnd := AFullEnd;

  if FFullEnd < FFullStart then
  begin
    FFullStart := 0;
    FFullEnd := 0;
  end;

  if Assigned(FPaintBox) then
    FPaintBox.Repaint;
end;

procedure TOverviewPlot.SetShowChannelColors(AValue: Boolean);
begin
  if FShowChannelColors = AValue then
    Exit;

  FShowChannelColors := AValue;

  if Assigned(FPaintBox) then
    FPaintBox.Repaint;
end;

function TOverviewPlot.GetHasChannelData: Boolean;
var
  Ch: Integer;
begin
  for Ch := 0 to 3 do
    if (Length(FChannelMin[Ch]) > 0) and
       (Length(FChannelMax[Ch]) > 0) then
      Exit(True);

  Result := False;
end;

procedure TOverviewPlot.SetViewRange(
  AStart, AEnd: Int64);
begin
  FViewStart := AStart;
  FViewEnd := AEnd;

  if FViewStart < FFullStart then
    FViewStart := FFullStart;

  if FViewEnd > FFullEnd then
    FViewEnd := FFullEnd;

  if Assigned(FPaintBox) then
    FPaintBox.Repaint;
end;

function TOverviewPlot.GetPlotRect: TRectF;
begin
  Result := RectF(
    2,
    2,
    FPaintBox.Width - 2,
    FPaintBox.Height - 2);
end;

function TOverviewPlot.MapX(
  Frame: Int64;
  const R: TRectF): Single;
begin
  if FFullEnd <= FFullStart then
    Exit(R.Left);

  Result :=
    R.Left +
    ((Frame - FFullStart) /
     (FFullEnd - FFullStart)) *
    R.Width;
end;

function TOverviewPlot.XToFrame(X: Single; const R: TRectF): Int64;
var
  P: Double;
begin
  if R.Width <= 0 then
    Exit(FFullStart);

  if X < R.Left then
    X := R.Left;
  if X > R.Right then
    X := R.Right;

  P := (X - R.Left) / R.Width;
  if P < 0 then
    P := 0
  else if P > 1 then
    P := 1;

  Result := FFullStart + Round(P * (FFullEnd - FFullStart));

  if Result < FFullStart then
    Result := FFullStart;
  if Result > FFullEnd then
    Result := FFullEnd;
end;

function TOverviewPlot.MapY(
  Value, MinY, MaxY: Double;
  const R: TRectF): Single;
begin
  if SameValue(MaxY, MinY) then
    Exit(R.CenterPoint.Y);

  Result :=
    R.Bottom -
    ((Value - MinY) /
     (MaxY - MinY)) *
    R.Height;
end;

procedure TOverviewPlot.PaintBoxPaint(
  Sender: TObject;
  Canvas: TCanvas);
var
  R: TRectF;
  I, N: Integer;
  X: Single;
  YMin, YMax: Double;
  Y1, Y2: Single;
  ViewLeft, ViewRight: Single;
begin
//  Canvas.Clear(TAlphaColorRec.White);
Canvas.Fill.Kind := TBrushKind.Solid;
Canvas.Fill.Color := TAlphaColorRec.White;
Canvas.FillRect(RectF(0, 0, FPaintBox.Width, FPaintBox.Height), 0, 0, [], 1);

  if (Length(FMinValues) = 0) or
     (Length(FMaxValues) = 0) or
     (FFullEnd <= FFullStart) then
    Exit;

  R := RectF(
    2,
    2,
    FPaintBox.Width - 2,
    FPaintBox.Height - 2);

  if (R.Width <= 0) or (R.Height <= 0) then
    Exit;

  N := Min(
    Length(FMinValues),
    Length(FMaxValues));

  if N <= 0 then
    Exit;

  { Find global Y range }
  YMin := FMinValues[0];
  YMax := FMaxValues[0];

  for I := 1 to N - 1 do
  begin
    if FMinValues[I] < YMin then
      YMin := FMinValues[I];

    if FMaxValues[I] > YMax then
      YMax := FMaxValues[I];
  end;

  if SameValue(YMin, YMax) then
  begin
    YMin := YMin - 1;
    YMax := YMax + 1;
  end;

  { Zero line }
  if (YMin <= 0) and (YMax >= 0) then
  begin
    Canvas.Stroke.Kind := TBrushKind.Solid;
    Canvas.Stroke.Color := TAlphaColorRec.Lightgray;
    Canvas.Stroke.Thickness := 1;

    Y1 := MapY(0, YMin, YMax, R);

    Canvas.DrawLine(
      PointF(R.Left, Y1),
      PointF(R.Right, Y1),
      1);
  end;

  { Signal envelope }
  if FShowChannelColors and GetHasChannelData then
    DrawChannelEnvelopes(Canvas, R)
  else
  begin
    Canvas.Stroke.Kind := TBrushKind.Solid;
    Canvas.Stroke.Color := TAlphaColorRec.Gray;
    Canvas.Stroke.Thickness := 1;

    if N = 1 then
    begin
      X := R.CenterPoint.X;

      Canvas.DrawLine(
        PointF(X, MapY(FMinValues[0], YMin, YMax, R)),
        PointF(X, MapY(FMaxValues[0], YMin, YMax, R)),
        1);
    end
    else
    begin
      for I := 0 to N - 1 do
      begin
        X :=
          R.Left +
          I / (N - 1) * R.Width;

        Y1 := MapY(
          FMinValues[I],
          YMin,
          YMax,
          R);

        Y2 := MapY(
          FMaxValues[I],
          YMin,
          YMax,
          R);

        Canvas.DrawLine(
          PointF(X, Y1),
          PointF(X, Y2),
          1);
      end;
    end;
  end;

  { Current visible range }
  ViewLeft := MapX(FViewStart, R);
  ViewRight := MapX(FViewEnd, R);

  if ViewRight < ViewLeft then
    begin
     // Swap(ViewLeft, ViewRight);
      var temp := ViewLeft  ;
      ViewLeft := ViewRight;
      ViewRight:= temp
    end;


  Canvas.Stroke.Kind := TBrushKind.Solid;
  Canvas.Stroke.Color := TAlphaColorRec.Red;
  Canvas.Stroke.Thickness := 2;

  Canvas.DrawRect(
    RectF(
      ViewLeft,
      R.Top,
      ViewRight,
      R.Bottom),
    0,
    0,
    AllCorners,
    1);

  { Range currently being dragged by the mouse (drawn on top). }
  if FDragging and FDragIsSelection then
  begin
    var SelLeft := MapX(FDragStartFrame, R);
    var SelRight := MapX(FDragCurrentFrame, R);

    if SelRight < SelLeft then
    begin
      var Temp := SelLeft;
      SelLeft := SelRight;
      SelRight := Temp;
    end;

    Canvas.Fill.Kind := TBrushKind.Solid;
    Canvas.Fill.Color := TAlphaColor($4000A0FF);
    Canvas.FillRect(
      RectF(SelLeft, R.Top, SelRight, R.Bottom),
      0, 0, [], 1);

    Canvas.Stroke.Kind := TBrushKind.Solid;
    Canvas.Stroke.Color := TAlphaColor($FF1E90FF);
    Canvas.Stroke.Thickness := 2;
    Canvas.DrawRect(
      RectF(SelLeft, R.Top, SelRight, R.Bottom),
      0, 0, AllCorners, 1);
  end;
end;

procedure TOverviewPlot.DrawChannelEnvelopes(
  Canvas: TCanvas;
  const R: TRectF);
const
  { Полупрозрачность: огибающие каналов перекрываются, и сквозь верхнюю
    линию должны быть видны остальные. }
  ChannelAlpha = $C0;
var
  Ch, I, N, Columns, Col: Integer;
  I0, I1, Mid: Integer;
  Scale, V: Double;
  X, Y1, Y2: Single;
  ColMin, ColMax: Single;
begin
  Columns := Max(1, Ceil(R.Width));

  for Ch := 0 to 3 do
  begin
    N := Min(Length(FChannelMin[Ch]), Length(FChannelMax[Ch]));

    if N <= 0 then
      Continue;

    { Масштаб свой для каждого канала: при общем масштабе слабый канал
      выглядел бы на обзоре прямой линией. Диапазон симметричен нулю,
      поэтому ноль у всех каналов на одной вертикали. }
    Scale := 0;

    for I := 0 to N - 1 do
    begin
      V := Abs(FChannelMin[Ch][I]);
      if V > Scale then
        Scale := V;

      V := Abs(FChannelMax[Ch][I]);
      if V > Scale then
        Scale := V;
    end;

    if Scale <= 0 then
      Continue;

    Canvas.Stroke.Kind := TBrushKind.Solid;
    Canvas.Stroke.Color :=
      (EodChannelColors[Ch] and $00FFFFFF) or
      (TAlphaColor(ChannelAlpha) shl 24);
    Canvas.Stroke.Thickness := 1;

    if N = 1 then
    begin
      X := R.CenterPoint.X;

      Canvas.DrawLine(
        PointF(X, MapY(FChannelMin[Ch][0], -Scale, Scale, R)),
        PointF(X, MapY(FChannelMax[Ch][0], -Scale, Scale, R)),
        1);

      Continue;
    end;

    if N <= Columns then
    begin
      for I := 0 to N - 1 do
      begin
        X := R.Left + I / (N - 1) * R.Width;

        Canvas.DrawLine(
          PointF(X, MapY(FChannelMin[Ch][I], -Scale, Scale, R)),
          PointF(X, MapY(FChannelMax[Ch][I], -Scale, Scale, R)),
          1);
      end;
    end
    else
    begin
      { Бинарных точек больше, чем пикселей по ширине: на колонку
        объединяем несколько бинов, иначе линии рисуются друг поверх
        друга и картинка становится ярче/шумнее без пользы. }
      for Col := 0 to Columns - 1 do
      begin
        I0 := (Int64(Col) * (N - 1)) div Columns;
        I1 := (Int64(Col + 1) * (N - 1)) div Columns;

        if I1 < I0 then
          I1 := I0;

        if I1 > N - 1 then
          I1 := N - 1;

        ColMin := FChannelMin[Ch][I0];
        ColMax := FChannelMax[Ch][I0];

        for I := I0 + 1 to I1 do
        begin
          if FChannelMin[Ch][I] < ColMin then
            ColMin := FChannelMin[Ch][I];

          if FChannelMax[Ch][I] > ColMax then
            ColMax := FChannelMax[Ch][I];
        end;

        Mid := (I0 + I1) div 2;

        X := R.Left + Mid / (N - 1) * R.Width;

        Y1 := MapY(ColMin, -Scale, Scale, R);
        Y2 := MapY(ColMax, -Scale, Scale, R);

        Canvas.DrawLine(PointF(X, Y1), PointF(X, Y2), 1);
      end;
    end;
  end;
end;

procedure TOverviewPlot.PaintBoxMouseDown(
  Sender: TObject;
  Button: TMouseButton;
  Shift: TShiftState;
  X, Y: Single);
var
  R: TRectF;
  Frame: Int64;
begin
  if Button <> TMouseButton.mbLeft then
    Exit;

  if (FFullEnd <= FFullStart) then
    Exit;

  R := GetPlotRect;

  if R.Width <= 0 then
    Exit;

  Frame := XToFrame(X, R);

  { Start tracking a potential drag-selection. Whether it turns into a
    plain click or a range selection is decided in MouseUp, based on
    whether the cursor actually moved. }
  FDragging := True;
  FDragIsSelection := False;
  FDragStartX := X;
  FDragStartFrame := Frame;
  FDragCurrentFrame := Frame;
end;

procedure TOverviewPlot.PaintBoxMouseMove(
  Sender: TObject;
  Shift: TShiftState;
  X, Y: Single);
const
  DragThresholdPx = 3;
var
  R: TRectF;
begin
  if not (ssLeft in Shift) then
  begin
    FDragging := False;
    Exit;
  end;

  if not FDragging then
    Exit;

  if (FFullEnd <= FFullStart) then
    Exit;

  R := GetPlotRect;
  if R.Width <= 0 then
    Exit;

  if not FDragIsSelection then
  begin
    if Abs(X - FDragStartX) < DragThresholdPx then
      Exit;
    FDragIsSelection := True;
  end;

  FDragCurrentFrame := XToFrame(X, R);

  if Assigned(FPaintBox) then
    FPaintBox.Repaint;
end;

procedure TOverviewPlot.PaintBoxMouseUp(
  Sender: TObject;
  Button: TMouseButton;
  Shift: TShiftState;
  X, Y: Single);
var
  R: TRectF;
  SelStart, SelEnd: Int64;
begin
  if Button <> TMouseButton.mbLeft then
    Exit;

  if not FDragging then
    Exit;

  FDragging := False;

  if (FFullEnd <= FFullStart) then
    Exit;

  R := GetPlotRect;
  if R.Width <= 0 then
    Exit;

  if not FDragIsSelection then
  begin
    { Plain click, no drag: navigate. }
    if Assigned(FOnClick) then
      FOnClick(Self, FDragStartFrame);
    Exit;
  end;

  { Drag finished: report the selected range. }
  FDragIsSelection := False;

  SelStart := FDragStartFrame;
  SelEnd := XToFrame(X, R);

  if SelEnd < SelStart then
  begin
    var Temp := SelStart;
    SelStart := SelEnd;
    SelEnd := Temp;
  end;

  if Assigned(FOnRangeSelected) then
    FOnRangeSelected(Self, SelStart, SelEnd);
end;

end.
