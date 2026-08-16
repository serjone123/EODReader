unit Eod.Types;

interface

uses
  System.SysUtils;

type
  TFloatArray = array of Single;

  TAudioFrame = packed record
    Ch1: Single;
    Ch2: Single;
    Ch3: Single;
    Ch4: Single;
  end;

  TAudioChunk = array of TAudioFrame;

  TFishType = (ftUnknown, ftGnat, ftMorm, ftStim);

  TPeak = record
    Position: Int64;
    Value: Single;
    Prominence: Single;
  end;

  TCorrelationResult = record
    Correlation: Single;
    Position: Integer; // zero-based inside the Test window
    Channel: Integer;  // zero-based
  end;

  TEodEvent = record
    Position: Int64;   // zero-based sample/frame in the original recording
    FishType: TFishType;
    Correlation: Single;
    Channel: Integer;  // zero-based
  end;

  TPeakArray = array of TPeak;
  TEodEventArray = array of TEodEvent;

  TEodDetectorConfig = record
    PeakProminence: Single;
    CorrelationThreshold: Single;
    WindowBefore: Integer;
    WindowAfter: Integer;
    ExtractionBefore: Integer;
    ExtractionAfter: Integer;
    ChunkSize: Integer;
    DuplicateDistance: Int64;
  end;

function DefaultEodDetectorConfig: TEodDetectorConfig;
function FishTypeToString(AType: TFishType): string;

implementation

function DefaultEodDetectorConfig: TEodDetectorConfig;
begin
  Result.PeakProminence := 0.002;
  Result.CorrelationThreshold := 0.9;
  Result.WindowBefore := 200;
  Result.WindowAfter := 200;
  Result.ExtractionBefore := 30;
  Result.ExtractionAfter := 30;
  Result.ChunkSize := 65536;
  Result.DuplicateDistance := 5;
end;

function FishTypeToString(AType: TFishType): string;
begin
  case AType of
    ftGnat: Result := 'Gnat';
    ftMorm: Result := 'Morm';
    ftStim: Result := 'Stim';
  else
    Result := 'Unknown';
  end;
end;

end.
