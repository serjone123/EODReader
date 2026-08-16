unit Eod.Statistics;

interface

uses
  Eod.Types;

function Std4(const A, B, C, D: Single): Single;
procedure CalculateStdChunk(const Input: TAudioChunk; var Output: TFloatArray);

implementation

function Std4(const A, B, C, D: Single): Single;
var
  Mean, S: Double;
begin
  Mean := (A + B + C + D) * 0.25;
  S := Sqr(A - Mean) + Sqr(B - Mean) + Sqr(C - Mean) + Sqr(D - Mean);
  Result := Sqrt(S / 3.0);
end;

procedure CalculateStdChunk(const Input: TAudioChunk; var Output: TFloatArray);
var
  I: Integer;
begin
  SetLength(Output, Length(Input));
  for I := 0 to High(Input) do
    Output[I] := Std4(Input[I].Ch1, Input[I].Ch2, Input[I].Ch3, Input[I].Ch4);
end;

end.
