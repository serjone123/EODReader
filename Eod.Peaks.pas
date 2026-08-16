unit Eod.Peaks;

interface

uses
  System.SysUtils, Eod.Types;

function FindPeaksProminence(const X: TFloatArray; MinProminence: Single): TPeakArray;

implementation

uses
  System.Math;

function IsLocalMaximum(const X: TFloatArray; I: Integer): Boolean;
begin
  Result := (I > 0) and (I < High(X)) and
            (X[I] > X[I-1]) and (X[I] >= X[I+1]);
end;

function PeakProminence(const X: TFloatArray; Peak: Integer): Single;
var
  I: Integer;
  LeftMin, RightMin, PeakValue: Single;
begin
  PeakValue := X[Peak];
  LeftMin := PeakValue;
  I := Peak - 1;
  while I >= 0 do
  begin
    if X[I] > PeakValue then Break;
    if X[I] < LeftMin then LeftMin := X[I];
    Dec(I);
  end;

  RightMin := PeakValue;
  I := Peak + 1;
  while I <= High(X) do
  begin
    if X[I] > PeakValue then Break;
    if X[I] < RightMin then RightMin := X[I];
    Inc(I);
  end;

  Result := PeakValue - Max(LeftMin, RightMin);
end;

function FindPeaksProminence(const X: TFloatArray; MinProminence: Single): TPeakArray;
var
  I, Count: Integer;
  P: Single;
begin
  SetLength(Result, 0);
  if Length(X) < 3 then Exit;

  Count := 0;
  for I := 1 to High(X) - 1 do
    if IsLocalMaximum(X, I) then
    begin
      P := PeakProminence(X, I);
      if P >= MinProminence then
      begin
        SetLength(Result, Count + 1);
        Result[Count].Position := I;
        Result[Count].Value := X[I];
        Result[Count].Prominence := P;
        Inc(Count);
      end;
    end;
end;

end.
