unit Eod.Classifier;

interface

uses
  Eod.Types, Eod.Correlation;

type
  TEodClassifier = class
  private
    FGnat, FMorm, FStim: TFloatArray;
    function MakeWindow(const Source: TAudioChunk; StartIndex, Count: Integer): TAudioChunk;
    procedure AddResult(var A: TEodEventArray; const E: TEodEvent);
  public
    constructor Create;
    function Classify(const Test: TAudioChunk; AbsoluteStart: Int64; Threshold: Single): TEodEventArray;
  end;

implementation

uses
  Eod.Templates;

constructor TEodClassifier.Create;
begin
  inherited Create;
  FGnat := GnatTemplate;
  FMorm := MormTemplate;
  FStim := StimTemplate;
end;

function TEodClassifier.MakeWindow(const Source: TAudioChunk; StartIndex, Count: Integer): TAudioChunk;
var I: Integer;
begin
  SetLength(Result, Count);
  for I := 0 to Count - 1 do Result[I] := Source[StartIndex + I];
end;

procedure TEodClassifier.AddResult(var A: TEodEventArray; const E: TEodEvent);
var N: Integer;
begin
  N := Length(A);
  SetLength(A, N + 1);
  A[N] := E;
end;

function TEodClassifier.Classify(const Test: TAudioChunk; AbsoluteStart: Int64; Threshold: Single): TEodEventArray;
var
  R: TCorrelationResult;
  E: TEodEvent;
begin
  SetLength(Result, 0);

  R := FindBestTemplateOn4Channels(FGnat, Test);
  if R.Correlation > Threshold then
  begin
    E.Position := AbsoluteStart + R.Position;
    E.FishType := ftGnat;
    E.Correlation := R.Correlation;
    E.Channel := R.Channel;
    AddResult(Result, E);
  end;

  R := FindBestTemplateOn4Channels(FMorm, Test);
  if R.Correlation > Threshold then
  begin
    E.Position := AbsoluteStart + R.Position;
    E.FishType := ftMorm;
    E.Correlation := R.Correlation;
    E.Channel := R.Channel;
    AddResult(Result, E);
  end;

  R := FindBestTemplateOn4Channels(FStim, Test);
  if R.Correlation > Threshold then
  begin
    E.Position := AbsoluteStart + R.Position;
    E.FishType := ftStim;
    E.Correlation := R.Correlation;
    E.Channel := R.Channel;
    AddResult(Result, E);
  end;
end;

end.
