unit Eod.GuiPlot;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Math,
  FMX.Types, FMX.Objects, FMX.Graphics,
  Eod.Types;

type
  TPlotMode = (pmChannels, pmStd);

  { TSignalPlot is a drawing helper for an FMX TPaintBox.
    The TPaintBox itself belongs to the form. TSignalPlot only keeps the
    data and installs an OnPaint handler. All drawing is performed inside
    that handler on the PaintBox canvas. }
  TSignalPlot = class
  private
    FPaintBox: TPaintBox;
    FOldOnPaint: TPaintEvent;
    FData: TAudioChunk;
    FStd: TFloatArray;
    FMode: TPlotMode;
    FStartFrame: Int64;
    FSampleRate: Integer;
    FSelectedOffset: Integer;
    FShowPeakLine: Boolean;
    FPeakOffset: Integer;
    FPeakPositions: TArray<Int64>;
    FTitle: string;

    procedure PaintBoxPaint(Sender: TObject; Canvas: TCanvas);
    procedure DrawGrid(Canvas: TCanvas; const R: TRectF; MinY, MaxY: Double);
    function MapX(Index, Count: Integer; const R: TRectF): Single;
    function MapY(Value, MinY, MaxY: Double; const R: TRectF): Single;
    procedure RequestRepaint;
  public
    constructor Create(APaintBox: TPaintBox);
    destructor Destroy; override;

    procedure ClearData;
    procedure SetChannels(const Data: TAudioChunk; StartFrame: Int64;
      SampleRate: Integer; PeakFrame: Int64 = -1; const ATitle: string = '');
    procedure SetStd(const Data: TFloatArray; StartFrame: Int64;
      SampleRate: Integer; PeakFrame: Int64 = -1; const ATitle: string = '');
    procedure SetPeakPositions(const Positions: array of Int64);
    procedure SetSelectedPosition(AFrame: Int64);
  end;

implementation

constructor TSignalPlot.Create(APaintBox: TPaintBox);
begin
  inherited Create;

  if not Assigned(APaintBox) then
    raise EArgumentNilException.Create('TSignalPlot requires a TPaintBox');

  FPaintBox := APaintBox;
  FOldOnPaint := FPaintBox.OnPaint;
  FPaintBox.OnPaint := PaintBoxPaint;

  FMode := pmChannels;
  FSampleRate := 1;
  FSelectedOffset := -1;
  FPeakOffset := -1;
end;

destructor TSignalPlot.Destroy;
begin
  if Assigned(FPaintBox) and (FPaintBox.OnPaint = PaintBoxPaint) then
    FPaintBox.OnPaint := FOldOnPaint;

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
  SetLength(FPeakPositions, 0);
  FSelectedOffset := -1;
  FPeakOffset := -1;
  FShowPeakLine := False;
  RequestRepaint;
end;

function TSignalPlot.MapX(Index, Count: Integer; const R: TRectF): Single;
begin
  if Count <= 1 then
    Exit(R.Left);

  Result := R.Left + (Index / (Count - 1)) * R.Width;
end;

function TSignalPlot.MapY(Value, MinY, MaxY: Double; const R: TRectF): Single;
begin
  if SameValue(MaxY, MinY) then
    Exit(R.CenterPoint.Y);

  Result := R.Bottom - ((Value - MinY) / (MaxY - MinY)) * R.Height;
end;

procedure TSignalPlot.DrawGrid(Canvas: TCanvas; const R: TRectF; MinY, MaxY: Double);
var
  I: Integer;
  Y: Single;
  S: string;
begin
  Canvas.Stroke.Kind := TBrushKind.Solid;
  Canvas.Stroke.Color := TAlphaColorRec.Lightgray;
  Canvas.Stroke.Thickness := 1;

  for I := 0 to 4 do
  begin
    Y := R.Top + I * R.Height / 4;
    Canvas.DrawLine(PointF(R.Left, Y), PointF(R.Right, Y), 1);
  end;

  Y := MapY(0, MinY, MaxY, R);
  if (Y >= R.Top) and (Y <= R.Bottom) then
  begin
    Canvas.Stroke.Color := TAlphaColorRec.Gray;
    Canvas.DrawLine(PointF(R.Left, Y), PointF(R.Right, Y), 1);
  end;

  Canvas.Fill.Color := TAlphaColorRec.Gray;
  Canvas.Font.Size := 11;

  S := FormatFloat('0.###E+0', MinY);
  Canvas.FillText(
    RectF(R.Left + 2, R.Top, R.Left + 90, R.Top + 18),
    S, False, 1, Canvas.Fill, TTextAlign.Leading, TTextAlign.Center);

  S := FormatFloat('0.###E+0', MaxY);
  Canvas.FillText(
    RectF(R.Left + 2, R.Bottom - 18, R.Left + 90, R.Bottom),
    S, False, 1, Canvas.Fill, TTextAlign.Leading, TTextAlign.Center);
end;

procedure TSignalPlot.PaintBoxPaint(Sender: TObject; Canvas: TCanvas);
const
  MarginL = 55;
  MarginR = 10;
  MarginT = 24;
  MarginB = 24;
var
  R: TRectF;
  I, N: Integer;
  MinY, MaxY, V: Double;
  P1, P2: TPointF;
  Ch: Integer;
  Prev: array[0..3] of TPointF;
  HavePrev: array[0..3] of Boolean;
  A: array[0..3] of TAlphaColor;
  S: string;
  PeakX: Single;
  Values: array[0..3] of Single;
  FullR: TRectF;
begin
  { Do not call Canvas.Clear here. A TPaintBox uses the form's FMX canvas.
    We paint its own complete rectangle instead. }
  FullR := RectF(0, 0, FPaintBox.Width, FPaintBox.Height);
  Canvas.Fill.Kind := TBrushKind.Solid;
  Canvas.Fill.Color := TAlphaColorRec.White;
  Canvas.FillRect(FullR, 0, 0, [], 1);

  R := RectF(MarginL, MarginT,
    FPaintBox.Width - MarginR, FPaintBox.Height - MarginB);

  Canvas.Fill.Color := TAlphaColorRec.Black;
  Canvas.Font.Size := 13;
  Canvas.FillText(
    RectF(4, 2, FPaintBox.Width - 4, 22),
    FTitle, False, 1, Canvas.Fill, TTextAlign.Leading, TTextAlign.Center);

  if FMode = pmStd then
    N := Length(FStd)
  else
    N := Length(FData);

  if N = 0 then
    Exit;

  MinY := MaxDouble;
  MaxY := -MaxDouble;

  if FMode = pmStd then
  begin
    for I := 0 to N - 1 do
    begin
      V := FStd[I];
      MinY := Min(MinY, V);
      MaxY := Max(MaxY, V);
    end;
  end
  else
  begin
    for I := 0 to N - 1 do
    begin
      Values[0] := FData[I].Ch1;
      Values[1] := FData[I].Ch2;
      Values[2] := FData[I].Ch3;
      Values[3] := FData[I].Ch4;

      for Ch := 0 to 3 do
      begin
        V := Values[Ch];
        MinY := Min(MinY, V);
        MaxY := Max(MaxY, V);
      end;
    end;
  end;

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

  DrawGrid(Canvas, R, MinY, MaxY);

  if FMode = pmStd then
  begin
    Canvas.Stroke.Color := TAlphaColorRec.Navy;
    Canvas.Stroke.Thickness := 1.5;

    for I := 1 to N - 1 do
    begin
      P1 := PointF(MapX(I - 1, N, R), MapY(FStd[I - 1], MinY, MaxY, R));
      P2 := PointF(MapX(I, N, R), MapY(FStd[I], MinY, MaxY, R));
      Canvas.DrawLine(P1, P2, 1);
    end;
  end
  else
  begin
    A[0] := TAlphaColorRec.Red;
    A[1] := TAlphaColorRec.Green;
    A[2] := TAlphaColorRec.Blue;
    A[3] := TAlphaColorRec.Orange;

    FillChar(HavePrev, SizeOf(HavePrev), 0);

    for I := 0 to N - 1 do
    begin
      Values[0] := FData[I].Ch1;
      Values[1] := FData[I].Ch2;
      Values[2] := FData[I].Ch3;
      Values[3] := FData[I].Ch4;

      for Ch := 0 to 3 do
      begin
        P2 := PointF(MapX(I, N, R), MapY(Values[Ch], MinY, MaxY, R));
        Canvas.Stroke.Color := A[Ch];
        Canvas.Stroke.Thickness := 1;

        if HavePrev[Ch] then
          Canvas.DrawLine(Prev[Ch], P2, 1);

        Prev[Ch] := P2;
        HavePrev[Ch] := True;
      end;
    end;
  end;

  if Length(FPeakPositions) > 0 then
  begin
    Canvas.Stroke.Color := TAlphaColorRec.Gray;
    Canvas.Stroke.Thickness := 1;

    for I := 0 to High(FPeakPositions) do
    begin
      if (FPeakPositions[I] >= FStartFrame) and
         (FPeakPositions[I] < FStartFrame + N) then
      begin
        PeakX := MapX(
          Integer(FPeakPositions[I] - FStartFrame), N, R);
        Canvas.DrawLine(
          PointF(PeakX, R.Top), PointF(PeakX, R.Bottom), 1);
      end;
    end;
  end;

  if FShowPeakLine and (FPeakOffset >= 0) and (FPeakOffset < N) then
  begin
    PeakX := MapX(FPeakOffset, N, R);
    Canvas.Stroke.Color := TAlphaColorRec.Black;
    Canvas.Stroke.Thickness := 2;
    Canvas.DrawLine(PointF(PeakX, R.Top), PointF(PeakX, R.Bottom), 1);
  end;

  if FSelectedOffset >= 0 then
  begin
    PeakX := MapX(FSelectedOffset, N, R);
    Canvas.Stroke.Color := TAlphaColorRec.Dimgray;
    Canvas.Stroke.Thickness := 1;
    Canvas.DrawLine(PointF(PeakX, R.Top), PointF(PeakX, R.Bottom), 1);
  end;

  S := Format(
    'Start sample: %d    Duration: %.3f ms',
    [FStartFrame, N * 1000.0 / FSampleRate]);

  Canvas.Fill.Color := TAlphaColorRec.Gray;
  Canvas.Font.Size := 11;
  Canvas.FillText(
    RectF(55, FPaintBox.Height - 21, FPaintBox.Width - 5, FPaintBox.Height),
    S, False, 1, Canvas.Fill, TTextAlign.Leading, TTextAlign.Center);
end;

procedure TSignalPlot.SetChannels(const Data: TAudioChunk; StartFrame: Int64;
  SampleRate: Integer; PeakFrame: Int64; const ATitle: string);
begin
  FMode := pmChannels;
  FData := Copy(Data);
  SetLength(FStd, 0);
  FStartFrame := StartFrame;
  FSampleRate := SampleRate;
  FTitle := ATitle;

  FShowPeakLine := PeakFrame >= 0;
  if FShowPeakLine then
    FPeakOffset := Integer(PeakFrame - StartFrame)
  else
    FPeakOffset := -1;

  FSelectedOffset := -1;
  RequestRepaint;
end;

procedure TSignalPlot.SetStd(const Data: TFloatArray; StartFrame: Int64;
  SampleRate: Integer; PeakFrame: Int64; const ATitle: string);
begin
  FMode := pmStd;
  SetLength(FData, 0);
  FStd := Copy(Data);
  FStartFrame := StartFrame;
  FSampleRate := SampleRate;
  FTitle := ATitle;

  FShowPeakLine := PeakFrame >= 0;
  if FShowPeakLine then
    FPeakOffset := Integer(PeakFrame - StartFrame)
  else
    FPeakOffset := -1;

  FSelectedOffset := -1;
  RequestRepaint;
end;

procedure TSignalPlot.SetPeakPositions(const Positions: array of Int64);
var
  I: Integer;
begin
  SetLength(FPeakPositions, Length(Positions));
  for I := 0 to High(Positions) do
    FPeakPositions[I] := Positions[I];

  RequestRepaint;
end;

procedure TSignalPlot.SetSelectedPosition(AFrame: Int64);
begin
  if Length(FData) > 0 then
    FSelectedOffset := Integer(AFrame - FStartFrame)
  else if Length(FStd) > 0 then
    FSelectedOffset := Integer(AFrame - FStartFrame)
  else
    FSelectedOffset := -1;

  RequestRepaint;
end;

end.
