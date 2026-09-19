unit Gui.Plot.Overview;

interface

uses
  System.Types, System.UITypes, System.Math,
  FMX.Types, FMX.Objects, FMX.Graphics,
  System.Classes, Core.Types, Gui.Plot.Base;

type
  TOverviewPlot = class(TPlotBase)
  private
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
  protected
    procedure RenderPlot(Canvas: TCanvas; const AOuterRect: TRectF); override;
  public
    constructor Create(APaintBox: TPaintBox);

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

implementation

{ ------------------------------------------------------------------ }
{ TOverviewPlot                                                      }
{ ------------------------------------------------------------------ }

constructor TOverviewPlot.Create(APaintBox: TPaintBox);
begin
  inherited Create(APaintBox);

  FPaintBox.OnMouseDown := PaintBoxMouseDown;
  FPaintBox.OnMouseMove := PaintBoxMouseMove;
  FPaintBox.OnMouseUp := PaintBoxMouseUp;

  FFullStart := 0;
  FFullEnd := 0;
  FViewStart := 0;
  FViewEnd := 0;

  FDragging := False;
  FDragIsSelection := False;
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
procedure TOverviewPlot.RenderPlot(
  Canvas: TCanvas;
  const AOuterRect: TRectF);
var
  R: TRectF;
  I, N: Integer;
  X: Single;
  YMin, YMax: Double;
  Y1, Y2: Single;
  ViewLeft, ViewRight: Single;
begin
Canvas.Fill.Kind := TBrushKind.Solid;
Canvas.Fill.Color := TAlphaColorRec.White;
Canvas.FillRect(AOuterRect, 0, 0, [], 1);

  if (Length(FMinValues) = 0) or
     (Length(FMaxValues) = 0) or
     (FFullEnd <= FFullStart) then
    Exit;

  R := RectF(
    AOuterRect.Left + 2,
    AOuterRect.Top + 2,
    AOuterRect.Right - 2,
    AOuterRect.Bottom - 2);

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

  { Current visible range (в видео-рендере — вырожденный в линию плейхед,
    если FViewStart = FViewEnd, см. Video.OverlayRenderer.pas). }
  ViewLeft := MapX(FViewStart, R);
  ViewRight := MapX(FViewEnd, R);

  if ViewRight < ViewLeft then
    begin
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
  if Button = TMouseButton.mbRight then
  begin
    HandleRightClick;
    Exit;
  end;

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