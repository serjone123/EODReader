unit Eod.Fir15;

interface

uses
  Eod.Types;

type
  TFir15 = class
  private
    FCoeff: array[0..14] of Double;
  public
    constructor Create;
    procedure Process(const Input: TFloatArray; var Output: TFloatArray);
  end;

implementation

uses
  System.Math;

constructor TFir15.Create;
var
  I: Integer;
  Sum: Double;
begin
  Sum := 0;
  for I := 0 to 14 do
  begin
    FCoeff[I] := Sin((I + 1) * Pi / 16.0);
    Sum := Sum + FCoeff[I];
  end;
  for I := 0 to 14 do
    FCoeff[I] := FCoeff[I] / Sum;
end;

procedure TFir15.Process(const Input: TFloatArray; var Output: TFloatArray);
var
  I, J: Integer;
  S: Double;
begin
  SetLength(Output, Length(Input));
  if Length(Input) < 17 then Exit;

  // Exact index geometry of fir15.m:
  // MATLAB k15=9..L15-8, with Inp(k15+i-8), i=1..15.
  // Converted to zero-based indices: I=8..N-9, Input[I-7..I+7].
  for I := 8 to Length(Input) - 9 do
  begin
    S := 0;
    for J := 0 to 14 do
      S := S + Input[I + J - 7] * FCoeff[J];
    Output[I] := S;
  end;
end;

end.
