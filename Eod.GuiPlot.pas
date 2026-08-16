unit Eod.GuiPlot;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Math,
  FMX.Types, FMX.Objects, FMX.Graphics,
  Eod.Types, System.Classes;

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

  TSignalPlot = class
  private
    FPaintBox: TPaintBox;
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
    FDragging: Boolean;
    FDragStartX: Single;
    FDragStartViewStart: Int64;
    FDragStartViewEnd: Int64;
    FLastMouseX: Single;
    FOnViewChanged: TViewChangedEvent;

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
    procedure SetViewRange(AStart, AEnd: Int64);
    procedure GetViewRange(out AStart, AEnd: Int64);
    function ViewSampleCount: Int64;
    procedure ZoomAt(AX: Single; AFactor: Double);
    procedure PanByPixels(ADeltaX: Single);
    property OnViewChanged: TViewChangedEvent read FOnViewChanged write FOnViewChanged;
  end;

implementation

const
  MinViewSamples = 10;

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
  FLastMouseX := 0;
end;

destructor TSignalPlot.Destroy;
begin
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
  FViewEnd := FFullEnd;
  RequestRepaint;
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

procedure TSignalPlot.ClampView;
var
  W: Int64;
begin
  W := ViewSampleCount;
  if W < MinViewSamples then
  begin
    W := MinViewSamples;
    FViewEnd := FViewStart + W;
  end;

  if FViewStart < FFullStart then
  begin
    FViewStart := FFullStart;
    FViewEnd := FViewStart + W;
  end;

  if FViewEnd > FFullEnd then
  begin
    FViewEnd := FFullEnd;
    FViewStart := FViewEnd - W;
    if FViewStart < FFullStart then
      FViewStart := FFullStart;
  end;

  if FViewStart < FFullStart then
    FViewStart := FFullStart;
  if FViewEnd > FFullEnd then
    FViewEnd := FFullEnd;
end;

procedure TSignalPlot.DoViewChanged;
begin
  if Assigned(FOnViewChanged) then
    FOnViewChanged(Self, FViewStart, FViewEnd);
end;

procedure TSignalPlot.ZoomAt(AX: Single; AFactor: Double);
var
  R: TRectF;
  PlotWidth: Single;
  SampleUnderCursor: Double;
  NewWidth: Double;
  NewStart: Double;
begin
  if (FFullEnd <= FFullStart) or (AFactor <= 0) then
    Exit;

  R := RectF(0, 0, FPaintBox.Width, FPaintBox.Height);
  PlotWidth := R.Width;
  if PlotWidth <= 0 then
    Exit;

  if (FViewEnd > FViewStart) then
    SampleUnderCursor := FViewStart + (AX / PlotWidth) * (FViewEnd - FViewStart)
  else
    SampleUnderCursor := FViewStart;

  NewWidth := (FViewEnd - FViewStart) * AFactor;
  if NewWidth < MinViewSamples then
    NewWidth := MinViewSamples;

  NewStart := SampleUnderCursor - (AX / PlotWidth) * NewWidth;

  FViewStart := Round(NewStart);
  FViewEnd := FViewStart + Round(NewWidth);

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
{  Mouse handlers                                                    }
{ ------------------------------------------------------------------ }

procedure TSignalPlot.PaintBoxMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Single);
begin
  if Button <> TMouseButton.mbLeft then
    Exit;

  FDragging := True;
  FDragStartX := X;
  FDragStartViewStart := FViewStart;
  FDragStartViewEnd := FViewEnd;
  FLastMouseX := X;
end;

procedure TSignalPlot.PaintBoxMouseMove(Sender: TObject; Shift: TShiftState;
  X, Y: Single);
begin
  FLastMouseX := X;
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
      [TFillTextFlag.RightToLeft],
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
      [TFillTextFlag.RightToLeft],
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
      [TFillTextFlag.RightToLeft],
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
      Title, False, 1, [TFillTextFlag.RightToLeft],
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
  for I := 0 to NumBins - 1 do
  begin
    if Bins[I] = 0 then
      Continue;
    X := R.Left + I * BinWidth;
    H := Bins[I] / MaxCount * R.Height;
    Y := R.Bottom - H;
    Canvas.FillRect(
      RectF(X + 1, Y, X + BinWidth - 1, R.Bottom),
      0, 0, [], 1);
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
      S, False, 1, [TFillTextFlag.RightToLeft],
      TTextAlign.Center, TTextAlign.Center);
  end;
  for I := 0 to 5 do
  begin
    S := IntToStr(Round(I * MaxCount / 5));
    Y := R.Bottom - I * R.Height / 5;
    Canvas.FillText(
      RectF(2, Y - 9, R.Left - 4, Y + 9),
      S, False, 1, [TFillTextFlag.RightToLeft],
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
    PlotTitle, False, 1, [TFillTextFlag.RightToLeft],
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
      S, False, 1, [TFillTextFlag.RightToLeft],
      TTextAlign.Leading, TTextAlign.Center);
    Exit;
  end;

  if N = 0 then
    Exit;

  if FMode = pmRaw4Channels then
  begin
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
      S, False, 1, [TFillTextFlag.RightToLeft],
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
    S, False, 1, [TFillTextFlag.RightToLeft],
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

end.
