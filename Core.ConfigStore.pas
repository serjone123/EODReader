unit Core.ConfigStore;

{ Persists TEodDetectorConfig (Core.Types) to/from a small JSON file, so
  detector settings survive an application restart. }

interface

uses
  Core.Types;

function GetDefaultConfigFileName: string;

{ Returns True and fills Config if FileName exists and parses correctly.
  Returns False (and Config = DefaultEodDetectorConfig) otherwise, so the
  caller can always safely use the result. }
function LoadDetectorConfig(const FileName: string;
  out Config: TEodDetectorConfig): Boolean;

procedure SaveDetectorConfig(const FileName: string;
  const Config: TEodDetectorConfig);

implementation

uses
  System.SysUtils, System.IOUtils, System.JSON;

function GetDefaultConfigFileName: string;
var
  Dir: string;
begin
//  Dir := TPath.Combine(TPath.GetAppPath, 'EODReader');
//  if not TDirectory.Exists(Dir) then
//    TDirectory.CreateDirectory(Dir);
//  Result := TPath.Combine(Dir, 'eodreader_config.json');
  Result := TPath.Combine(TPath.GetAppPath, 'config.json');
end;

function LoadDetectorConfig(const FileName: string;
  out Config: TEodDetectorConfig): Boolean;
var
  Text: string;
  JV: TJSONValue;
  JO: TJSONObject;
  DValue: Double;
  IValue: Integer;
  I64Value: Int64;
begin
  Result := False;
  Config := DefaultEodDetectorConfig;

  if not TFile.Exists(FileName) then
    Exit;

  Text := TFile.ReadAllText(FileName, TEncoding.UTF8);
  if Text.Trim = '' then
    Exit;

  JV := TJSONObject.ParseJSONValue(Text);
  if JV = nil then
    Exit;
  try
    if not (JV is TJSONObject) then
      Exit;
    JO := TJSONObject(JV);

    if JO.TryGetValue<Double>('PeakProminence', DValue) then
      Config.PeakProminence := DValue;

    if JO.TryGetValue<Double>('CorrelationThreshold', DValue) then
      Config.CorrelationThreshold := DValue;

    if JO.TryGetValue<Integer>('WindowBefore', IValue) then
      Config.WindowBefore := IValue;

    if JO.TryGetValue<Integer>('WindowAfter', IValue) then
      Config.WindowAfter := IValue;

    if JO.TryGetValue<Integer>('ExtractionBefore', IValue) then
      Config.ExtractionBefore := IValue;

    if JO.TryGetValue<Integer>('ExtractionAfter', IValue) then
      Config.ExtractionAfter := IValue;

    if JO.TryGetValue<Integer>('ChunkSize', IValue) then
      Config.ChunkSize := IValue;

    if JO.TryGetValue<Int64>('DuplicateDistance', I64Value) then
      Config.DuplicateDistance := I64Value;

    { Basic sanity checks. If the file is corrupted/hand-edited into
      something nonsensical, fall back silently to safe defaults for
      the offending fields rather than let the detector misbehave. }
    if Config.ChunkSize <= 0 then
      Config.ChunkSize := DefaultEodDetectorConfig.ChunkSize;
    if Config.WindowBefore < 0 then
      Config.WindowBefore := DefaultEodDetectorConfig.WindowBefore;
    if Config.WindowAfter < 0 then
      Config.WindowAfter := DefaultEodDetectorConfig.WindowAfter;
    if Config.PeakProminence < 0 then
      Config.PeakProminence := DefaultEodDetectorConfig.PeakProminence;

    Result := True;
  finally
    JV.Free;
  end;
end;

procedure SaveDetectorConfig(const FileName: string;
  const Config: TEodDetectorConfig);
var
  JO: TJSONObject;
begin
  JO := TJSONObject.Create;
  try
    JO.AddPair('PeakProminence', TJSONNumber.Create(Config.PeakProminence));
    JO.AddPair('CorrelationThreshold', TJSONNumber.Create(Config.CorrelationThreshold));
    JO.AddPair('WindowBefore', TJSONNumber.Create(Config.WindowBefore));
    JO.AddPair('WindowAfter', TJSONNumber.Create(Config.WindowAfter));
    JO.AddPair('ExtractionBefore', TJSONNumber.Create(Config.ExtractionBefore));
    JO.AddPair('ExtractionAfter', TJSONNumber.Create(Config.ExtractionAfter));
    JO.AddPair('ChunkSize', TJSONNumber.Create(Config.ChunkSize));
    JO.AddPair('DuplicateDistance', TJSONNumber.Create(Config.DuplicateDistance));

    TFile.WriteAllText(FileName, JO.Format(2), TEncoding.UTF8);
  finally
    JO.Free;
  end;
end;

end.
