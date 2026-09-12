unit Signal.Peaks;

interface

uses
  System.SysUtils, Core.Types;

function FindPeaksProminence(const X: TFloatArray; MinProminence: Single): TPeakArray;

implementation

uses
  System.Math;

function IsLocalMaximum(const X: TFloatArray; I: Integer): Boolean;
begin
  Result := (I > 0) and (I < High(X)) and
            (X[I] > X[I-1]) and (X[I] >= X[I+1]);
end;

{ ------------------------------------------------------------------
  O(N) replacement for the previous O(N^2) prominence scan.

  Semantics are unchanged from the original brute-force version:
  for a candidate index I, LeftMin/RightMin is the minimum value
  found while walking away from I until (and NOT including) the
  first strictly-greater neighbour on that side, floored at X[I]
  itself. Prominence = X[I] - Max(LeftMin, RightMin).

  This is computed with two monotonic-stack passes (left-to-right,
  then right-to-left). Each element is pushed and popped at most
  once per pass, so total cost is O(N) instead of O(N^2). This is
  the standard "min-in-range-to-next-greater-element" technique
  (the same idea used for "sum of subarray minimums").
  ------------------------------------------------------------------ }

procedure ComputeSideMin(const X: TFloatArray; Reverse: Boolean;
  var Out_: TFloatArray);
var
  N, I, Idx, SP: Integer;
  StackVal, StackMin: TFloatArray;
  CurMin: Single;
begin
  N := Length(X);
  SetLength(Out_, N);
  SetLength(StackVal, N);
  SetLength(StackMin, N);
  SP := 0;

  for I := 0 to N - 1 do
  begin
    if Reverse then
      Idx := N - 1 - I
    else
      Idx := I;

    CurMin := X[Idx];

    { Absorb every stacked element that is NOT strictly greater than
      X[Idx] (equal values do not block, matching the original
      "if X[I] > PeakValue then Break" — a break only on strict >). }
    while (SP > 0) and (StackVal[SP - 1] <= X[Idx]) do
    begin
      if StackMin[SP - 1] < CurMin then
        CurMin := StackMin[SP - 1];
      Dec(SP);
    end;

    Out_[Idx] := CurMin;

    StackVal[SP] := X[Idx];
    StackMin[SP] := CurMin;
    Inc(SP);
  end;
end;

function FindPeaksProminence(const X: TFloatArray; MinProminence: Single): TPeakArray;
var
  N, I, Count: Integer;
  LeftMin, RightMin: TFloatArray;
  P: Single;
begin
  SetLength(Result, 0);
  N := Length(X);
  if N < 3 then Exit;

  ComputeSideMin(X, False, LeftMin);
  ComputeSideMin(X, True, RightMin);

  Count := 0;
  for I := 1 to N - 2 do
  begin
    if IsLocalMaximum(X, I) then
    begin
      P := X[I] - Max(LeftMin[I], RightMin[I]);
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
end;

end.
