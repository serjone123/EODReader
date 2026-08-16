unit Eod.Detector;

interface

uses
  Eod.Types;

type
  TDetectorProgressEvent = procedure(Sender: TObject; Processed, Total: Int64) of object;
  TDetectorCancelEvent = function(Sender: TObject): Boolean of object;

  TSegmentBoundaryMode = (sbStrict, sbPadWithZero);

  TEodDetector = class
  private
    FConfig: TEodDetectorConfig;
  public
    constructor Create(const AConfig: TEodDetectorConfig);
    function Analyze(const File1, File2: string): TEodEventArray;
    function AnalyzePeaks(const File1, File2: string; MaxFrames: Int64 = 0;
      AProgress: TDetectorProgressEvent = nil;
      ACancel: TDetectorCancelEvent = nil): TPeakArray;
    procedure ReadSegment(const File1, File2: string; StartFrame: Int64;
      ACount: Integer; Mode: TSegmentBoundaryMode; var Buffer: TAudioChunk);
    property Config: TEodDetectorConfig read FConfig;
    function ApplyFir15(const Values: TFloatArray): TFloatArray;
  end;

implementation

uses
  System.SysUtils, System.Math, Eod.AudioSource, Eod.Statistics, Eod.Fir15,
  Eod.Peaks, Eod.Classifier;

function AppendEvents(var A: TEodEventArray; const B: TEodEventArray): Integer;
var
  OldN, I: Integer;
begin
  OldN := Length(A);
  SetLength(A, OldN + Length(B));
  for I := 0 to High(B) do A[OldN + I] := B[I];
  Result := Length(A);
end;

function FilterCloseEvents(const Input: TEodEventArray; Distance: Int64): TEodEventArray;
var
  I, N: Integer;
  LastPos: Int64;
begin
  SetLength(Result, 0);
  LastPos := Low(Int64);
  for I := 0 to High(Input) do
    if (I = 0) or (Input[I].Position - LastPos > Distance) then
    begin
      N := Length(Result);
      SetLength(Result, N + 1);
      Result[N] := Input[I];
      LastPos := Input[I].Position;
    end;
end;

constructor TEodDetector.Create(const AConfig: TEodDetectorConfig);
begin
  inherited Create;
  FConfig := AConfig;
end;

function TEodDetector.AnalyzePeaks(const File1, File2: string; MaxFrames: Int64;
  AProgress: TDetectorProgressEvent; ACancel: TDetectorCancelEvent): TPeakArray;
var
  Source: TFourChannelAudioSource;
  Fir: TFir15;
  Audio, Std, Filtered: TFloatArray;
  Chunk: TAudioChunk;
  FirInput: TFloatArray;
  AllFiltered: TFloatArray;
  LocalPeaks: TPeakArray;
  Frame, N, I, Total: Int64;
  DesiredStart, DesiredEnd: Int64;
  ReadStart, ReadCount: Int64;
  DestOffset, CoreIndex: Integer;
begin
  SetLength(Result, 0);
  Source := TFourChannelAudioSource.Create(File1, File2);
  try
    Total := Source.TotalFrames;
    if (MaxFrames > 0) and (MaxFrames < Total) then
      Total := MaxFrames;

    { This validation stage keeps the filtered signal in RAM so prominence is
      calculated over the complete tested interval. A disk-backed cache will
      replace this in the large-file stage. }
    SetLength(AllFiltered, Total);

    Fir := TFir15.Create;
    try
      Frame := 0;
      while Frame < Total do
      begin
        N := FConfig.ChunkSize;
        if Frame + N > Total then
          N := Total - Frame;

        { Read 7 samples on each side of the core block so FIR15 has the
          same neighbourhood it would have in one continuous array. }
        DesiredStart := Frame - 7;
        DesiredEnd := Frame + N + 7;
        ReadStart := Max(0, DesiredStart);
        ReadCount := Min(Source.TotalFrames, DesiredEnd) - ReadStart;
        if ReadCount < 0 then
          ReadCount := 0;

        SetLength(FirInput, Integer(N) + 14);
        for I := 0 to High(FirInput) do
          FirInput[I] := 0;

        if ReadCount > 0 then
        begin
          Source.ReadFrames(ReadStart, Integer(ReadCount), Chunk);
          CalculateStdChunk(Chunk, Std);
          DestOffset := Integer(ReadStart - DesiredStart);
          for I := 0 to High(Std) do
            FirInput[DestOffset + I] := Std[I];
        end;

        Fir.Process(FirInput, Filtered);

        DestOffset := Integer(Frame - DesiredStart);
        for I := 0 to N - 1 do
        begin
          CoreIndex := I + DestOffset;
          AllFiltered[Frame + I] := Filtered[CoreIndex];
        end;

        Inc(Frame, N);

        if Assigned(AProgress) then
          AProgress(Self, Frame, Total);
        if Assigned(ACancel) and ACancel(Self) then
          Exit;
      end;

      if Assigned(ACancel) and ACancel(Self) then
        Exit;

      LocalPeaks := FindPeaksProminence(AllFiltered, FConfig.PeakProminence);
      if Assigned(AProgress) then
        AProgress(Self, Total, Total);
      Result := LocalPeaks;
    finally
      Fir.Free;
    end;
  finally
    Source.Free;
  end;
end;

procedure TEodDetector.ReadSegment(const File1, File2: string; StartFrame: Int64;
  ACount: Integer; Mode: TSegmentBoundaryMode; var Buffer: TAudioChunk);
var
  Source: TFourChannelAudioSource;
  SourceStart, SourceEnd, CopyCount, DestOffset: Int64;
  Temp: TAudioChunk;
  I: Integer;
begin
  SetLength(Buffer, 0);
  if ACount <= 0 then Exit;

  Source := TFourChannelAudioSource.Create(File1, File2);
  try
    if Mode = sbStrict then
    begin
      if (StartFrame < 0) or (StartFrame + ACount > Source.TotalFrames) then
        raise EArgumentOutOfRangeException.CreateFmt(
          'Segment [%d..%d] is outside source [0..%d]',
          [StartFrame, StartFrame + ACount - 1, Source.TotalFrames - 1]);

      Source.ReadFrames(StartFrame, ACount, Buffer);
      Exit;
    end;

    SetLength(Buffer, ACount);
    for I := 0 to ACount - 1 do
      Buffer[I].Ch1 := 0;

    SourceStart := StartFrame;
    SourceEnd := StartFrame + ACount;

    if SourceStart < 0 then
      SourceStart := 0;
    if SourceEnd > Source.TotalFrames then
      SourceEnd := Source.TotalFrames;

    if SourceEnd <= SourceStart then
      Exit;

    CopyCount := SourceEnd - SourceStart;
    DestOffset := SourceStart - StartFrame;
    Source.ReadFrames(SourceStart, CopyCount, Temp);

    for I := 0 to Integer(CopyCount) - 1 do
      Buffer[DestOffset + I] := Temp[I];
  finally
    Source.Free;
  end;
end;

function TEodDetector.Analyze(const File1, File2: string): TEodEventArray;
var
  Source: TFourChannelAudioSource;
  Classifier: TEodClassifier;
  CandidateWindow: TAudioChunk;
  PeakResults: TEodEventArray;
  Peaks: TPeakArray;
  Peak: TPeak;
  StartFrame, WindowLength: Int64;
begin
  SetLength(Result, 0);
  Source := TFourChannelAudioSource.Create(File1, File2);
  try
    Classifier := TEodClassifier.Create;
    try
      Peaks := AnalyzePeaks(File1, File2);
      WindowLength := FConfig.WindowBefore + FConfig.WindowAfter + 1;

      for Peak in Peaks do
      begin
        StartFrame := Peak.Position - FConfig.WindowBefore;
        if (StartFrame < 0) or
           (StartFrame + WindowLength > Source.TotalFrames) then
          Continue;

        Source.ReadFrames(StartFrame, WindowLength, CandidateWindow);
        PeakResults := Classifier.Classify(
          CandidateWindow,
          StartFrame,
          FConfig.CorrelationThreshold
        );
        AppendEvents(Result, PeakResults);
      end;

      Result := FilterCloseEvents(Result, FConfig.DuplicateDistance);
    finally
      Classifier.Free;
    end;
  finally
    Source.Free;
  end;
end;

function TEodDetector.ApplyFir15(const Values: TFloatArray): TFloatArray;
var
  Fir: TFir15;
begin
  Fir := TFir15.Create;
  try
    Fir.Process(Values, Result);
  finally
    Fir.Free;
  end;
end;

end.
