unit Eod.Correlation;

interface

uses
  Eod.Types;

function PearsonCorrelation(const A, B: TFloatArray): Double;
function TemplateCorrelation(const Template, Test: TFloatArray): TCorrelationResult;
function FindBestTemplateOn4Channels(const Template: TFloatArray; const Test: TAudioChunk): TCorrelationResult;

implementation

uses
  System.SysUtils;
function PearsonCorrelation(const A, B: TFloatArray): Double;
var
  I, N: Integer;
  MA, MB, Num, DA, DB, XA, XB: Double;
begin
  N := Length(A);
  if N <> Length(B) then
    raise EArgumentException.Create('Correlation: different lengths');
  if N = 0 then Exit(0);

  MA := 0; MB := 0;
  for I := 0 to N - 1 do begin MA := MA + A[I]; MB := MB + B[I]; end;
  MA := MA / N; MB := MB / N;

  Num := 0; DA := 0; DB := 0;
  for I := 0 to N - 1 do
  begin
    XA := A[I] - MA;
    XB := B[I] - MB;
    Num := Num + XA * XB;
    DA := DA + XA * XA;
    DB := DB + XB * XB;
  end;
  if (DA = 0) or (DB = 0) then Exit(0);
  Result := Num / Sqrt(DA * DB);
end;

function TemplateCorrelation(const Template, Test: TFloatArray): TCorrelationResult;
var
  N, L, Pos, J: Integer;
  MeanT, SumE, SumE2, DenT, DenC, Dot, Corr: Double;
  SumT, SumT2: Double;
  X: Double;
begin
  Result.Correlation := 0;
  Result.Position := 0;
  N := Length(Test);
  L := Length(Template);
  if (N = 0) or (L = 0) or (L >= N) then Exit;

  SumT := 0; SumT2 := 0;
  for J := 0 to N - 1 do begin SumT := SumT + Test[J]; SumT2 := SumT2 + Test[J] * Test[J]; end;
  MeanT := SumT / N;
  DenT := SumT2 - N * MeanT * MeanT;
  if DenT <= 0 then Exit;

  SumE := 0; SumE2 := 0;
  for J := 0 to L - 1 do begin SumE := SumE + Template[J]; SumE2 := SumE2 + Template[J] * Template[J]; end;
  DenC := SumE2 - (SumE * SumE) / N;
  if DenC <= 0 then Exit;

  // corr_et.m scans kk=1..(N-L), i.e. zero-based Pos=0..N-L-1.
  // For C = [zeros, Template, zeros], the centered dot product simplifies to
  // sum over the template window of (Test-MeanT)*Template.
  Dot := 0;
  for J := 0 to L - 1 do
    Dot := Dot + (Test[J] - MeanT) * Template[J];

  Corr := Abs(Dot / Sqrt(DenT * DenC));
  Result.Correlation := Corr;
  Result.Position := 0;

  for Pos := 1 to N - L - 1 do
  begin
    // Sliding dot product with the template.
    // For clarity and correctness this version recalculates the short dot.
    // L=100 in the supplied templates; a prefix/FFT version can be added later.
    Dot := 0;
    for J := 0 to L - 1 do
      Dot := Dot + (Test[Pos + J] - MeanT) * Template[J];

    Corr := Abs(Dot / Sqrt(DenT * DenC));
    if Corr > Result.Correlation then
    begin
      Result.Correlation := Corr;
      Result.Position := Pos;
    end;
  end;
end;

function FindBestTemplateOn4Channels(const Template: TFloatArray; const Test: TAudioChunk): TCorrelationResult;
var
  Ch, I: Integer;
  X: TFloatArray;
  R: TCorrelationResult;
begin
  Result.Correlation := 0;
  Result.Position := 0;
  Result.Channel := 0;
  SetLength(X, Length(Test));

  for Ch := 0 to 3 do
  begin
    for I := 0 to High(Test) do
      case Ch of
        0: X[I] := Test[I].Ch1;
        1: X[I] := Test[I].Ch2;
        2: X[I] := Test[I].Ch3;
        3: X[I] := Test[I].Ch4;
      end;

    R := TemplateCorrelation(Template, X);
    if R.Correlation > Result.Correlation then
    begin
      Result := R;
      Result.Channel := Ch;
    end;
  end;
end;

end.
