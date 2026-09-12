unit IO.PeakStore;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Math,
  Core.Types;

const
  EodPeakPageSize = 5000;

  EODPK_VERSION = 3;

  EODPK_CACHE_MAGIC = 'EODCACH3';

  { Maximum number of buckets in the finest cache level. }
  EodCacheMaxBuckets = 8192;

  { Every next cache level groups four buckets of the previous level. }
  EodCacheGroupFactor = 4;

  { Maximum number of cache levels. }
  EodCacheMaxLevels = 16;

type
  TPeakFileMagic = array [0 .. 7] of AnsiChar;

  { One cache level describes a contiguous range of peak records. }
  TEodPeakCacheLevelInfo = packed record
    Offset: Int64;
    Count: Int64;
    GroupSize: Int64;
  end;

  { Cache header is stored immediately before cache data. }
  TEodPeakCacheHeader = packed record
    Magic: TPeakFileMagic;
    Version: Cardinal;
    LevelCount: Cardinal;
    RecordSize: Cardinal;
    BaseGroupSize: Int64;

    Levels: array [0 .. EodCacheMaxLevels - 1] of TEodPeakCacheLevelInfo;
  end;

  { EODPK version 3 header.

    Layout:

    Header
    UTF-8 source name 1
    UTF-8 source name 2
    Fixed-size peak records
    Cache header
    Cache level 0
    Cache level 1
    ...

    HeaderSize points to the first peak record.
    CacheOffset points to the cache header.
  }
  TEodPeakFileHeader = packed record
    Magic: TPeakFileMagic;
    Version: Cardinal;
    HeaderSize: Int64;

    SampleRate: Cardinal;
    ChannelCount: Cardinal;

    WindowBefore: Integer;
    WindowAfter: Integer;
    SamplesPerPeak: Cardinal;

    PeakCount: Int64;
    TotalFrames: Int64;

    Source1Size: Int64;
    Source2Size: Int64;

    Source1SampleRate: Cardinal;
    Source2SampleRate: Cardinal;

    Source1Channels: Cardinal;
    Source2Channels: Cardinal;

    Source1NameBytes: Cardinal;
    Source2NameBytes: Cardinal;

    CacheOffset: Int64;
    CacheSize: Int64;
    CacheLevelCount: Cardinal;

    Reserved: Cardinal;
  end;

  { Fixed-size peak record header.

    IMPORTANT:
    Every peak record in EODPK v3 has exactly:

    SizeOf(TEodPeakRecordHeader) +
    SamplesPerPeak * SizeOf(TAudioFrame)

    bytes.

    This makes direct random access possible:

    RecordOffset = DataOffset + Index * RecordSize
  }
  TEodPeakRecordHeader = packed record
    Position: Int64;
    StartPosition: Int64;
    TimeSeconds: Double;
    PeakValue: Single;
    Prominence: Single;
    SampleCount: Cardinal;
  end;

  { One display bucket.

    16 bytes of position information +
    32 bytes of min/max for four channels =
    48 bytes.
  }
//  TWaveEnvelopePoint = packed record
//    StartPosition: Int64;
//    EndPosition: Int64;
//
//    Ch1Min: Single;
//    Ch1Max: Single;
//
//    Ch2Min: Single;
//    Ch2Max: Single;
//
//    Ch3Min: Single;
//    Ch3Max: Single;
//
//    Ch4Min: Single;
//    Ch4Max: Single;
//  end;

  // TWaveEnvelope = array of TWaveEnvelopePoint;

  TEodPeakStore = class
  private
    FStream: TFileStream;

    FHeader: TEodPeakFileHeader;

    { First peak record. }
    FDataOffset: Int64;

    FSource1Name: string;
    FSource2Name: string;

    FCacheHeader: TEodPeakCacheHeader;

    class function HeaderMagic: TPeakFileMagic; static;
    class function CacheMagic: TPeakFileMagic; static;

    class function FileSizeOf(const FileName: string): Int64; static;

    class function CheckedRecordSize(const Header: TEodPeakFileHeader)
      : Int64; static;

    class procedure BuildCacheForStream(Stream: TFileStream;
      var Header: TEodPeakFileHeader); static;

    class procedure WriteUtf8String(Stream: TStream; const S: string); static;

    class function ReadUtf8String(Stream: TStream; ByteCount: Cardinal)
      : string; static;

    function RecordSize: Int64;

    function RecordOffset(Index: Int64): Int64;

    function ReadCacheBucket(LevelIndex: Int64; BucketIndex: Int64;
      out Bucket: TWaveEnvelopePoint): Boolean;

    function SelectCacheLevel(FirstIndex: Int64; LastIndex: Int64;
      MaxPoints: Integer): Integer;

    function LoadCacheHeader: Boolean;

  public
    { Creates a completely new EODPK v3 file from WAV sources. }
    class procedure Save(const FileName, SourceFile1, SourceFile2: string;
      const Peaks: TPeakArray; WindowBefore, WindowAfter: Integer;
      PadWithZero: Boolean = False);

    { Rewrites an existing peak store into EODPK v3. }
    class procedure SaveFromStore(const DestFileName: string;
      Source: TEodPeakStore; const SourceFile1, SourceFile2: string;
      TotalFrames: Int64);

    constructor Open(const FileName: string);

    destructor Destroy; override;

    { Reads complete peak record including waveform. }
    function ReadRecord(Index: Int64; out Peak: TPeak; out StartPosition: Int64;
      var Samples: TAudioChunk): Boolean;

    { Reads only peak metadata.
      No waveform is allocated. }
    function ReadRecordInfo(Index: Int64; out Peak: TPeak;
      out StartPosition: Int64): Boolean;

    function PageCount: Int64;

    function GetPageBounds(PageIndex: Int64;
      out FirstIndex, Count: Int64): Boolean;

    function ReadRecordInfoPage(PageIndex: Int64;
      var Peaks: TPeakArray): Boolean;

    function ReadRecordInfoPageInternal(FirstIndex, Count: Int64;
      var Peaks: TPeakArray): Boolean;

    { Finds the range of peak records whose Position is inside
      StartFrame..EndFrame.

      No global peak-position array is created. }
    function FindPeakRange(StartFrame, EndFrame: Int64;
      out FirstIndex, LastIndex: Int64): Boolean;

    { Reads a display envelope from the appropriate cache level.

      MaxPoints limits the number of objects returned to the GUI. }
    function ReadEnvelope(FirstPeakIndex, LastPeakIndex: Int64;
      MaxPoints: Integer; var Envelope: TWaveEnvelope): Boolean;

    property Header: TEodPeakFileHeader read FHeader;

    property Source1Name: string read FSource1Name;

    property Source2Name: string read FSource2Name;
  end;

implementation

uses
  IO.AudioSource;

class function TEodPeakStore.HeaderMagic: TPeakFileMagic;
begin
  Result[0] := 'E';
  Result[1] := 'O';
  Result[2] := 'D';
  Result[3] := 'P';
  Result[4] := 'K';
  Result[5] := '0';
  Result[6] := '0';
  Result[7] := '3';
end;

class function TEodPeakStore.CacheMagic: TPeakFileMagic;
begin
  Result[0] := AnsiChar(EODPK_CACHE_MAGIC[1]);
  Result[1] := AnsiChar(EODPK_CACHE_MAGIC[2]);
  Result[2] := AnsiChar(EODPK_CACHE_MAGIC[3]);
  Result[3] := AnsiChar(EODPK_CACHE_MAGIC[4]);
  Result[4] := AnsiChar(EODPK_CACHE_MAGIC[5]);
  Result[5] := AnsiChar(EODPK_CACHE_MAGIC[6]);
  Result[6] := AnsiChar(EODPK_CACHE_MAGIC[7]);
  Result[7] := AnsiChar(EODPK_CACHE_MAGIC[8]);
end;

class function TEodPeakStore.FileSizeOf(const FileName: string): Int64;
var
  S: TFileStream;
begin
  S := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
  try
    Result := S.Size;
  finally
    S.Free;
  end;
end;

class function TEodPeakStore.CheckedRecordSize(const Header
  : TEodPeakFileHeader): Int64;
var
  WaveBytes: Int64;
begin
  if Header.SamplesPerPeak > Cardinal(MaxInt div SizeOf(TAudioFrame)) then
  begin
    raise ERangeError.Create('EODPK SamplesPerPeak is too large');
  end;

  WaveBytes := Int64(Header.SamplesPerPeak) * SizeOf(TAudioFrame);

  Result := SizeOf(TEodPeakRecordHeader) + WaveBytes;

  if Result < SizeOf(TEodPeakRecordHeader) then
    raise ERangeError.Create('EODPK record size overflow');
end;

class procedure TEodPeakStore.WriteUtf8String(Stream: TStream; const S: string);
var
  B: TBytes;
begin
  B := TEncoding.UTF8.GetBytes(S);

  if Length(B) > 0 then
    Stream.WriteBuffer(B[0], Length(B));
end;

class function TEodPeakStore.ReadUtf8String(Stream: TStream;
  ByteCount: Cardinal): string;
var
  B: TBytes;
begin
  SetLength(B, ByteCount);

  if ByteCount > 0 then
    Stream.ReadBuffer(B[0], ByteCount);

  Result := TEncoding.UTF8.GetString(B);
end;

class procedure TEodPeakStore.BuildCacheForStream(Stream: TFileStream;
  var Header: TEodPeakFileHeader);
type
  TLevelArray = array of TWaveEnvelopePoint;

var
  Levels: array of TLevelArray;

  CacheHeader: TEodPeakCacheHeader;

  Magic: TPeakFileMagic;

  BaseGroupSize: Int64;

  GroupSize: Int64;

  BucketCount: Int64;

  LevelCount: Integer;

  Level: Integer;

  B: Int64;

  I: Int64;

  S: Int64;

  E: Int64;

  Rec: TEodPeakRecordHeader;

  Bucket: TWaveEnvelopePoint;

  Src: TWaveEnvelopePoint;

  CacheOffset: Int64;

  CacheEnd: Int64;

  Offset: Int64;

  WaveCount: Cardinal;

  Samples: TAudioChunk;

  procedure InitBucket(out X: TWaveEnvelopePoint);
  begin
    X.StartPosition := High(Int64);
    X.EndPosition := Low(Int64);

    X.Ch1Min := MaxSingle;
    X.Ch1Max := -MaxSingle;

    X.Ch2Min := MaxSingle;
    X.Ch2Max := -MaxSingle;

    X.Ch3Min := MaxSingle;
    X.Ch3Max := -MaxSingle;

    X.Ch4Min := MaxSingle;
    X.Ch4Max := -MaxSingle;
  end;

  procedure AddFrame(var X: TWaveEnvelopePoint; const F: TAudioFrame);
  begin
    X.Ch1Min := Min(X.Ch1Min, F.Ch1);
    X.Ch1Max := Max(X.Ch1Max, F.Ch1);

    X.Ch2Min := Min(X.Ch2Min, F.Ch2);
    X.Ch2Max := Max(X.Ch2Max, F.Ch2);

    X.Ch3Min := Min(X.Ch3Min, F.Ch3);
    X.Ch3Max := Max(X.Ch3Max, F.Ch3);

    X.Ch4Min := Min(X.Ch4Min, F.Ch4);
    X.Ch4Max := Max(X.Ch4Max, F.Ch4);
  end;

  procedure AddBucket(var X: TWaveEnvelopePoint; const Y: TWaveEnvelopePoint);
  begin
    if Y.EndPosition < Y.StartPosition then
      Exit;

    X.StartPosition := Min(X.StartPosition, Y.StartPosition);

    X.EndPosition := Max(X.EndPosition, Y.EndPosition);

    X.Ch1Min := Min(X.Ch1Min, Y.Ch1Min);
    X.Ch1Max := Max(X.Ch1Max, Y.Ch1Max);

    X.Ch2Min := Min(X.Ch2Min, Y.Ch2Min);
    X.Ch2Max := Max(X.Ch2Max, Y.Ch2Max);

    X.Ch3Min := Min(X.Ch3Min, Y.Ch3Min);
    X.Ch3Max := Max(X.Ch3Max, Y.Ch3Max);

    X.Ch4Min := Min(X.Ch4Min, Y.Ch4Min);
    X.Ch4Max := Max(X.Ch4Max, Y.Ch4Max);
  end;

begin
  { Validate the record layout even when there are no peaks. }
  CheckedRecordSize(Header);

  { ------------------------------------------------------------
    Empty EODPK.
    ------------------------------------------------------------ }

  if Header.PeakCount <= 0 then
  begin
    FillChar(CacheHeader, SizeOf(CacheHeader), 0);

    Magic := CacheMagic;

    Move(Magic, CacheHeader.Magic, SizeOf(Magic));

    CacheHeader.Version := EODPK_VERSION;

    CacheHeader.LevelCount := 0;

    CacheHeader.RecordSize := SizeOf(TWaveEnvelopePoint);

    CacheOffset := Stream.Size;

    Stream.Position := CacheOffset;

    Stream.WriteBuffer(CacheHeader, SizeOf(CacheHeader));

    Header.CacheOffset := CacheOffset;

    Header.CacheSize := SizeOf(CacheHeader);

    Header.CacheLevelCount := 0;

    Exit;
  end;

  { ------------------------------------------------------------
    Determine finest cache level.
    ------------------------------------------------------------ }

  BaseGroupSize := (Header.PeakCount + EodCacheMaxBuckets - 1)
    div EodCacheMaxBuckets;

  if BaseGroupSize < 1 then
    BaseGroupSize := 1;

  LevelCount := 1;
  GroupSize := BaseGroupSize;

  while (LevelCount < EodCacheMaxLevels) and (GroupSize < Header.PeakCount) do
  begin
    if GroupSize > High(Int64) div EodCacheGroupFactor then
      Break;

    GroupSize := GroupSize * EodCacheGroupFactor;

    Inc(LevelCount);
  end;

  SetLength(Levels, LevelCount);

  { ------------------------------------------------------------
    Allocate all cache levels.

    This is intentionally tiny compared with the source file.
    ------------------------------------------------------------ }

  GroupSize := BaseGroupSize;

  for Level := 0 to LevelCount - 1 do
  begin
    BucketCount := (Header.PeakCount + GroupSize - 1) div GroupSize;

    if BucketCount > EodCacheMaxBuckets then
    begin
      BucketCount := EodCacheMaxBuckets;
    end;

    SetLength(Levels[Level], Integer(BucketCount));

    for B := 0 to High(Levels[Level]) do
      InitBucket(Levels[Level][B]);

    if GroupSize > High(Int64) div EodCacheGroupFactor then
      Break;

    GroupSize := GroupSize * EodCacheGroupFactor;
  end;

  { ------------------------------------------------------------
    Build level 0.

    We read the fixed-size records sequentially.
    No global waveform array is created.
    ------------------------------------------------------------ }

  Stream.Position := Header.HeaderSize;

  for I := 0 to Header.PeakCount - 1 do
  begin
    Stream.ReadBuffer(Rec, SizeOf(Rec));

    WaveCount := Rec.SampleCount;

    if WaveCount > Header.SamplesPerPeak then
    begin
      raise EStreamError.Create('Invalid EODPK record sample count');
    end;

    SetLength(Samples, WaveCount);

    if WaveCount > 0 then
    begin
      Stream.ReadBuffer(Samples[0], Integer(WaveCount) * SizeOf(TAudioFrame));
    end;

    B := I div BaseGroupSize;

    if B > High(Levels[0]) then
      Continue;

    Bucket := Levels[0][Integer(B)];

    Bucket.StartPosition := Min(Bucket.StartPosition, Rec.StartPosition);

    if WaveCount > 0 then
    begin
      Bucket.EndPosition := Max(Bucket.EndPosition,
        Rec.StartPosition + WaveCount - 1);
    end;

    for S := 0 to Int64(WaveCount) - 1 do
    begin
      AddFrame(Bucket, Samples[Integer(S)]);
    end;

    Levels[0][Integer(B)] := Bucket;
  end;

  { ------------------------------------------------------------
    Build coarse levels from previous levels.
    ------------------------------------------------------------ }

  for Level := 1 to LevelCount - 1 do
  begin
    for B := 0 to High(Levels[Level]) do
    begin
      InitBucket(Bucket);

      S := Int64(B) * EodCacheGroupFactor;

      E := Min(S + EodCacheGroupFactor - 1, Int64(High(Levels[Level - 1])));

      while S <= E do
      begin
        Src := Levels[Level - 1][Integer(S)];

        AddBucket(Bucket, Src);

        Inc(S);
      end;

      Levels[Level][B] := Bucket;
    end;
  end;

  { ------------------------------------------------------------
    Write cache.
    ------------------------------------------------------------ }

  FillChar(CacheHeader, SizeOf(CacheHeader), 0);

  Magic := CacheMagic;

  Move(Magic, CacheHeader.Magic, SizeOf(Magic));

  CacheHeader.Version := EODPK_VERSION;

  CacheHeader.LevelCount := LevelCount;

  CacheHeader.RecordSize := SizeOf(TWaveEnvelopePoint);

  CacheHeader.BaseGroupSize := BaseGroupSize;

  CacheOffset := Stream.Size;

  Stream.Position := CacheOffset;

  { Placeholder header. It will be rewritten after offsets
    are known. }
  Stream.WriteBuffer(CacheHeader, SizeOf(CacheHeader));

  Offset := CacheOffset + SizeOf(CacheHeader);

  GroupSize := BaseGroupSize;

  for Level := 0 to LevelCount - 1 do
  begin
    CacheHeader.Levels[Level].Offset := Offset;

    CacheHeader.Levels[Level].Count := Length(Levels[Level]);

    CacheHeader.Levels[Level].GroupSize := GroupSize;

    if Length(Levels[Level]) > 0 then
    begin
      Stream.WriteBuffer(Levels[Level][0], Length(Levels[Level]) *
        SizeOf(TWaveEnvelopePoint));
    end;

    Offset := Stream.Position;

    if GroupSize <= High(Int64) div EodCacheGroupFactor then
    begin
      GroupSize := GroupSize * EodCacheGroupFactor;
    end;
  end;

  CacheEnd := Stream.Position;

  { Rewrite cache header with actual offsets. }

  Stream.Position := CacheOffset;

  Stream.WriteBuffer(CacheHeader, SizeOf(CacheHeader));

  Stream.Position := CacheEnd;

  Header.CacheOffset := CacheOffset;

  Header.CacheSize := CacheEnd - CacheOffset;

  Header.CacheLevelCount := LevelCount;
end;

class procedure TEodPeakStore.Save(const FileName, SourceFile1,
  SourceFile2: string; const Peaks: TPeakArray;
  WindowBefore, WindowAfter: Integer; PadWithZero: Boolean);
var
  Source: TFourChannelAudioSource;

  Stream: TFileStream;

  Header: TEodPeakFileHeader;

  Rec: TEodPeakRecordHeader;

  Buffer: TAudioChunk;

  Temp: TAudioChunk;

  I: Integer;

  Saved: Int64;

  SampleCount: Integer;

  StartPosition: Int64;

  Valid: Boolean;

  Name1: TBytes;

  Name2: TBytes;

  SourceStart: Int64;

  SourceEnd: Int64;

  DestOffset: Int64;

  CopyCount: Int64;

begin
  if WindowBefore < 0 then
    raise EArgumentOutOfRangeException.Create('WindowBefore must be >= 0');

  if WindowAfter < 0 then
    raise EArgumentOutOfRangeException.Create('WindowAfter must be >= 0');

  if Int64(WindowBefore) + Int64(WindowAfter) + 1 > Cardinal(MaxInt) then
  begin
    raise ERangeError.Create('Peak window is too large');
  end;

  Source := TFourChannelAudioSource.Create(SourceFile1, SourceFile2);

  try
    Name1 := TEncoding.UTF8.GetBytes(ExtractFileName(SourceFile1));

    Name2 := TEncoding.UTF8.GetBytes(ExtractFileName(SourceFile2));

    FillChar(Header, SizeOf(Header), 0);

    Header.Magic := HeaderMagic;

    Header.Version := EODPK_VERSION;

    Header.HeaderSize := SizeOf(Header) + Length(Name1) + Length(Name2);

    Header.SampleRate := Source.SampleRate;

    Header.ChannelCount := 4;

    Header.WindowBefore := WindowBefore;

    Header.WindowAfter := WindowAfter;

    Header.SamplesPerPeak :=
      Cardinal(Int64(WindowBefore) + Int64(WindowAfter) + 1);

    Header.PeakCount := 0;

    Header.TotalFrames := Source.TotalFrames;

    Header.Source1Size := FileSizeOf(SourceFile1);

    Header.Source2Size := FileSizeOf(SourceFile2);

    Header.Source1SampleRate := Source.SampleRate;

    Header.Source2SampleRate := Source.SampleRate;

    Header.Source1Channels := 2;

    Header.Source2Channels := 2;

    Header.Source1NameBytes := Length(Name1);

    Header.Source2NameBytes := Length(Name2);

    Stream := TFileStream.Create(FileName, fmCreate);

    try
      { Header + source names. }

      Stream.WriteBuffer(Header, SizeOf(Header));

      if Length(Name1) > 0 then
        Stream.WriteBuffer(Name1[0], Length(Name1));

      if Length(Name2) > 0 then
        Stream.WriteBuffer(Name2[0], Length(Name2));

      Saved := 0;

      SampleCount := Integer(Header.SamplesPerPeak);

      { ----------------------------------------------------------
        Write fixed-size peak records.
        ---------------------------------------------------------- }

      for I := 0 to High(Peaks) do
      begin
        StartPosition := Peaks[I].Position - WindowBefore;

        Valid := (StartPosition >= 0) and (StartPosition <= Source.TotalFrames)
          and (Int64(SampleCount) <= Source.TotalFrames - StartPosition);

        if (not Valid) and (not PadWithZero) then
        begin
          Continue;
        end;

        SetLength(Buffer, SampleCount);

        if SampleCount > 0 then
        begin
          FillChar(Buffer[0], SampleCount * SizeOf(TAudioFrame), 0);
        end;

        if Valid then
        begin
          Source.ReadFrames(StartPosition, SampleCount, Buffer);
        end
        else
        begin
          SourceStart := Max(Int64(0), StartPosition);

          SourceEnd := Min(Source.TotalFrames, StartPosition + SampleCount);

          if SourceEnd > SourceStart then
          begin
            CopyCount := SourceEnd - SourceStart;

            DestOffset := SourceStart - StartPosition;

            Source.ReadFrames(SourceStart, Integer(CopyCount), Temp);

            Move(Temp[0], Buffer[Integer(DestOffset)],
              Integer(CopyCount) * SizeOf(TAudioFrame));
          end;
        end;

        FillChar(Rec, SizeOf(Rec), 0);

        Rec.Position := Peaks[I].Position;

        Rec.StartPosition := StartPosition;

        Rec.TimeSeconds := Peaks[I].Position / Source.SampleRate;

        Rec.PeakValue := Peaks[I].Value;

        Rec.Prominence := Peaks[I].Prominence;

        { IMPORTANT:
          always fixed-size in v3. }
        Rec.SampleCount := Header.SamplesPerPeak;

        Stream.WriteBuffer(Rec, SizeOf(Rec));

        if SampleCount > 0 then
        begin
          Stream.WriteBuffer(Buffer[0], SampleCount * SizeOf(TAudioFrame));
        end;

        Inc(Saved);
      end;

      Header.PeakCount := Saved;

      { Build the cache directly from the written EODPK records.
        No second WAV pass is needed. }

      BuildCacheForStream(Stream, Header);

      { Rewrite final header with PeakCount and cache offsets. }

      Stream.Position := 0;

      Stream.WriteBuffer(Header, SizeOf(Header));

    finally
      Stream.Free;
    end;

  finally
    Source.Free;
  end;
end;

class procedure TEodPeakStore.SaveFromStore(const DestFileName: string;
  Source: TEodPeakStore; const SourceFile1, SourceFile2: string;
  TotalFrames: Int64);
var
  Dest: TFileStream;

  Header: TEodPeakFileHeader;

  Rec: TEodPeakRecordHeader;

  Samples: TAudioChunk;

  Peak: TPeak;

  StartPos: Int64;

  I: Int64;

  Name1: TBytes;

  Name2: TBytes;

begin
  if Source = nil then
    raise EArgumentNilException.Create('Source store is nil');

  if SourceFile1 <> '' then
    Name1 := TEncoding.UTF8.GetBytes(ExtractFileName(SourceFile1))
  else
    Name1 := TEncoding.UTF8.GetBytes(Source.Source1Name);

  if SourceFile2 <> '' then
    Name2 := TEncoding.UTF8.GetBytes(ExtractFileName(SourceFile2))
  else
    Name2 := TEncoding.UTF8.GetBytes(Source.Source2Name);

  FillChar(Header, SizeOf(Header), 0);

  Header.Magic := HeaderMagic;

  Header.Version := EODPK_VERSION;

  Header.SampleRate := Source.Header.SampleRate;

  Header.ChannelCount := Source.Header.ChannelCount;

  Header.WindowBefore := Source.Header.WindowBefore;

  Header.WindowAfter := Source.Header.WindowAfter;

  Header.SamplesPerPeak := Source.Header.SamplesPerPeak;

  Header.PeakCount := Source.Header.PeakCount;

  if TotalFrames > 0 then
    Header.TotalFrames := TotalFrames
  else
    Header.TotalFrames := Source.Header.TotalFrames;

  Header.Source1Size := Source.Header.Source1Size;

  Header.Source2Size := Source.Header.Source2Size;

  Header.Source1SampleRate := Source.Header.Source1SampleRate;

  Header.Source2SampleRate := Source.Header.Source2SampleRate;

  Header.Source1Channels := Source.Header.Source1Channels;

  Header.Source2Channels := Source.Header.Source2Channels;

  Header.Source1NameBytes := Length(Name1);

  Header.Source2NameBytes := Length(Name2);

  Header.HeaderSize := SizeOf(Header) + Length(Name1) + Length(Name2);

  Dest := TFileStream.Create(DestFileName, fmCreate);

  try
    Dest.WriteBuffer(Header, SizeOf(Header));

    if Length(Name1) > 0 then
      Dest.WriteBuffer(Name1[0], Length(Name1));

    if Length(Name2) > 0 then
      Dest.WriteBuffer(Name2[0], Length(Name2));

    { Source must already be v3.
      ReadRecord returns the fixed-size waveform. }

    for I := 0 to Source.Header.PeakCount - 1 do
    begin
      if not Source.ReadRecord(I, Peak, StartPos, Samples) then
      begin
        raise EStreamError.CreateFmt('Cannot read peak %d', [I]);
      end;

      FillChar(Rec, SizeOf(Rec), 0);

      Rec.Position := Peak.Position;

      Rec.StartPosition := StartPos;

      Rec.TimeSeconds := Peak.Position / Header.SampleRate;

      Rec.PeakValue := Peak.Value;

      Rec.Prominence := Peak.Prominence;

      Rec.SampleCount := Header.SamplesPerPeak;

      Dest.WriteBuffer(Rec, SizeOf(Rec));

      if Length(Samples) > 0 then
      begin
        Dest.WriteBuffer(Samples[0], Length(Samples) * SizeOf(TAudioFrame));
      end;
    end;

    BuildCacheForStream(Dest, Header);

    Dest.Position := 0;

    Dest.WriteBuffer(Header, SizeOf(Header));

  finally
    Dest.Free;
  end;
end;

constructor TEodPeakStore.Open(const FileName: string);
var
  Magic: TPeakFileMagic;

  Expected: TPeakFileMagic;

  CacheExpected: TPeakFileMagic;

  NameBytes: Int64;

  FileRecEnd: Int64;

begin
  inherited Create;

  FStream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);

  try
    if FStream.Size < SizeOf(TEodPeakFileHeader) then
    begin
      raise EStreamError.Create('Invalid EODPK file: too small');
    end;

    Expected := HeaderMagic;

    FStream.Position := 0;

    FStream.ReadBuffer(Magic, SizeOf(Magic));

    if not CompareMem(@Magic, @Expected, SizeOf(Magic)) then
    begin
      raise EStreamError.Create('Invalid EODPK signature');
    end;

    FStream.Position := 0;

    FStream.ReadBuffer(FHeader, SizeOf(FHeader));

    if FHeader.Version <> EODPK_VERSION then
    begin
      raise EStreamError.CreateFmt('Unsupported EODPK version: %d',
        [FHeader.Version]);
    end;

    if FHeader.HeaderSize < SizeOf(FHeader) then
    begin
      raise EStreamError.Create('Invalid EODPK HeaderSize');
    end;

    if FHeader.HeaderSize > FStream.Size then
    begin
      raise EStreamError.Create('EODPK header exceeds file');
    end;

    if FHeader.ChannelCount <> 4 then
    begin
      raise EStreamError.Create('EODPK must contain four channels');
    end;

    if FHeader.WindowBefore < 0 then
      raise EStreamError.Create('Invalid EODPK WindowBefore');

    if FHeader.WindowAfter < 0 then
      raise EStreamError.Create('Invalid EODPK WindowAfter');

    if Int64(FHeader.WindowBefore) + Int64(FHeader.WindowAfter) + 1 <> FHeader.SamplesPerPeak
    then
    begin
      raise EStreamError.Create('Invalid EODPK window');
    end;

    if FHeader.PeakCount < 0 then
    begin
      raise EStreamError.Create('Invalid EODPK PeakCount');
    end;

    if FHeader.TotalFrames < 0 then
    begin
      raise EStreamError.Create('Invalid EODPK TotalFrames');
    end;

    if FHeader.CacheOffset < 0 then
    begin
      raise EStreamError.Create('Invalid EODPK CacheOffset');
    end;

    if FHeader.CacheOffset > FStream.Size then
    begin
      raise EStreamError.Create('EODPK CacheOffset exceeds file');
    end;

    { Read source names. }

    FStream.Position := SizeOf(FHeader);

    FSource1Name := ReadUtf8String(FStream, FHeader.Source1NameBytes);

    FSource2Name := ReadUtf8String(FStream, FHeader.Source2NameBytes);

    NameBytes := Int64(FHeader.Source1NameBytes) +
      Int64(FHeader.Source2NameBytes);

    if FHeader.HeaderSize <> SizeOf(FHeader) + NameBytes then
    begin
      raise EStreamError.Create('Invalid EODPK HeaderSize/name lengths');
    end;

    FDataOffset := FHeader.HeaderSize;

    { Because records are fixed-size, this calculation is safe and
      allows direct random access. }

    if FHeader.PeakCount > (High(Int64) - FDataOffset) div RecordSize then
    begin
      raise ERangeError.Create('EODPK peak record offset overflow');
    end;

    FileRecEnd := FDataOffset + FHeader.PeakCount * RecordSize;

    if FileRecEnd > FStream.Size then
    begin
      raise EStreamError.Create('EODPK peak records exceed file');
    end;

    { Cache begins immediately after peak records. }

    if FHeader.CacheOffset <> FileRecEnd then
    begin
      raise EStreamError.Create('Invalid EODPK CacheOffset');
    end;

    if not LoadCacheHeader then
    begin
      raise EStreamError.Create('Invalid EODPK cache');
    end;

    CacheExpected := CacheMagic;

    if not CompareMem(@FCacheHeader.Magic, @CacheExpected, SizeOf(CacheExpected))
    then
    begin
      raise EStreamError.Create('Invalid EODPK cache signature');
    end;

  except
    FStream.Free;
    FStream := nil;
    raise;
  end;
end;

destructor TEodPeakStore.Destroy;
begin
  FStream.Free;
  inherited;
end;

function TEodPeakStore.RecordSize: Int64;
begin
  Result := CheckedRecordSize(FHeader);
end;

function TEodPeakStore.RecordOffset(Index: Int64): Int64;
var
  RS: Int64;
begin
  if (Index < 0) or (Index >= FHeader.PeakCount) then
  begin
    raise EArgumentOutOfRangeException.Create('Peak index out of range');
  end;

  RS := RecordSize;

  if Index > (High(Int64) - FDataOffset) div RS then
  begin
    raise ERangeError.Create('EODPK record offset overflow');
  end;

  Result := FDataOffset + Index * RS;
end;

function TEodPeakStore.LoadCacheHeader: Boolean;
begin
  Result := False;

  FillChar(FCacheHeader, SizeOf(FCacheHeader), 0);

  if FHeader.CacheSize < SizeOf(FCacheHeader) then
    Exit;

  if FHeader.CacheOffset > FStream.Size - FHeader.CacheSize then
    Exit;

  FStream.Position := FHeader.CacheOffset;

  FStream.ReadBuffer(FCacheHeader, SizeOf(FCacheHeader));

  Result := (FCacheHeader.Version = EODPK_VERSION) and
    (FCacheHeader.RecordSize = SizeOf(TWaveEnvelopePoint)) and
    (FCacheHeader.LevelCount <= EodCacheMaxLevels) and
    (FCacheHeader.LevelCount = FHeader.CacheLevelCount);
end;

function TEodPeakStore.ReadRecord(Index: Int64; out Peak: TPeak;
  out StartPosition: Int64; var Samples: TAudioChunk): Boolean;
var
  Rec: TEodPeakRecordHeader;

  N: Integer;

begin
  Result := False;

  FillChar(Peak, SizeOf(Peak), 0);

  StartPosition := 0;

  SetLength(Samples, 0);

  if (Index < 0) or (Index >= FHeader.PeakCount) then
    Exit;

  FStream.Position := RecordOffset(Index);

  FStream.ReadBuffer(Rec, SizeOf(Rec));

  if Rec.SampleCount > FHeader.SamplesPerPeak then
  begin
    raise EStreamError.Create('Invalid EODPK record sample count');
  end;

  Peak.Position := Rec.Position;

  Peak.Value := Rec.PeakValue;

  Peak.Prominence := Rec.Prominence;

  StartPosition := Rec.StartPosition;

  N := Integer(Rec.SampleCount);

  SetLength(Samples, N);

  if N > 0 then
  begin
    FStream.ReadBuffer(Samples[0], N * SizeOf(TAudioFrame));
  end;

  { v3 records are fixed-size. If a malformed file contains a
    smaller SampleCount, skip the unused tail so subsequent reads
    remain aligned. }

  if Rec.SampleCount < FHeader.SamplesPerPeak then
  begin
    FStream.Position := RecordOffset(Index) + RecordSize;
  end;

  Result := True;
end;

function TEodPeakStore.ReadRecordInfo(Index: Int64; out Peak: TPeak;
  out StartPosition: Int64): Boolean;
var
  Rec: TEodPeakRecordHeader;
begin
  Result := False;

  FillChar(Peak, SizeOf(Peak), 0);

  StartPosition := 0;

  if (Index < 0) or (Index >= FHeader.PeakCount) then
    Exit;

  FStream.Position := RecordOffset(Index);

  FStream.ReadBuffer(Rec, SizeOf(Rec));

  if Rec.SampleCount > FHeader.SamplesPerPeak then
  begin
    raise EStreamError.Create('Invalid EODPK record sample count');
  end;

  Peak.Position := Rec.Position;

  Peak.Value := Rec.PeakValue;

  Peak.Prominence := Rec.Prominence;

  StartPosition := Rec.StartPosition;

  Result := True;
end;

function TEodPeakStore.PageCount: Int64;
begin
  if FHeader.PeakCount <= 0 then
    Exit(0);

  Result := (FHeader.PeakCount + EodPeakPageSize - 1) div EodPeakPageSize;
end;

function TEodPeakStore.GetPageBounds(PageIndex: Int64;
  out FirstIndex, Count: Int64): Boolean;
begin
  Result := False;

  FirstIndex := 0;

  Count := 0;

  if (PageIndex < 0) or (PageIndex >= PageCount) then
    Exit;

  FirstIndex := PageIndex * EodPeakPageSize;

  Count := Min(Int64(EodPeakPageSize), FHeader.PeakCount - FirstIndex);

  Result := Count > 0;
end;

function TEodPeakStore.ReadRecordInfoPage(PageIndex: Int64;
  var Peaks: TPeakArray): Boolean;
var
  FirstIndex: Int64;

  Count: Int64;
begin
  Result := GetPageBounds(PageIndex, FirstIndex, Count) and
    ReadRecordInfoPageInternal(FirstIndex, Count, Peaks);
end;

function TEodPeakStore.ReadRecordInfoPageInternal(FirstIndex, Count: Int64;
  var Peaks: TPeakArray): Boolean;
var
  I: Int64;

  P: TPeak;

  StartPos: Int64;
begin
  Result := False;

  SetLength(Peaks, 0);

  if FirstIndex < 0 then
    Exit;

  if Count < 0 then
    Exit;

  if FirstIndex > FHeader.PeakCount then
    Exit;

  if Count > FHeader.PeakCount - FirstIndex then
    Exit;

  if Count > MaxInt then
  begin
    raise ERangeError.Create('Too many peaks requested');
  end;

  SetLength(Peaks, Integer(Count));

  for I := 0 to Count - 1 do
  begin
    if not ReadRecordInfo(FirstIndex + I, P, StartPos) then
    begin
      SetLength(Peaks, Integer(I));

      Exit;
    end;

    Peaks[Integer(I)] := P;
  end;

  Result := True;
end;

function TEodPeakStore.FindPeakRange(StartFrame, EndFrame: Int64;
  out FirstIndex, LastIndex: Int64): Boolean;
var
  L: Int64;

  R: Int64;

  M: Int64;

  P: TPeak;

  Dummy: Int64;

begin
  Result := False;

  FirstIndex := -1;

  LastIndex := -1;

  if FHeader.PeakCount = 0 then
    Exit;

  if EndFrame < StartFrame then
    Exit;

  { ------------------------------------------------------------
    First peak >= StartFrame.
    ------------------------------------------------------------ }

  L := 0;

  R := FHeader.PeakCount - 1;

  while L <= R do
  begin
    M := L + (R - L) div 2;

    if not ReadRecordInfo(M, P, Dummy) then
      Exit;

    if P.Position >= StartFrame then
    begin
      FirstIndex := M;

      R := M - 1;
    end
    else
    begin
      L := M + 1;
    end;
  end;

  { ------------------------------------------------------------
    Last peak <= EndFrame.
    ------------------------------------------------------------ }

  L := 0;

  R := FHeader.PeakCount - 1;

  while L <= R do
  begin
    M := L + (R - L) div 2;

    if not ReadRecordInfo(M, P, Dummy) then
      Exit;

    if P.Position <= EndFrame then
    begin
      LastIndex := M;

      L := M + 1;
    end
    else
    begin
      R := M - 1;
    end;
  end;

  Result := (FirstIndex >= 0) and (LastIndex >= FirstIndex);
end;

function TEodPeakStore.SelectCacheLevel(FirstIndex, LastIndex: Int64;
  MaxPoints: Integer): Integer;
var
  Level: Integer;

  Count: Int64;

  GroupSize: Int64;

  Buckets: Int64;
begin
  Result := -1;

  if MaxPoints < 1 then
    MaxPoints := 1;

  Count := LastIndex - FirstIndex + 1;

  for Level := 0 to Integer(FCacheHeader.LevelCount) - 1 do
  begin
    GroupSize := FCacheHeader.Levels[Level].GroupSize;

    if GroupSize <= 0 then
      Continue;

    Buckets := (Count + GroupSize - 1) div GroupSize;

    if Buckets <= MaxPoints then
    begin
      Result := Level;

      Exit;
    end;
  end;

  if FCacheHeader.LevelCount > 0 then
  begin
    Result := Integer(FCacheHeader.LevelCount) - 1;
  end;
end;

function TEodPeakStore.ReadCacheBucket(LevelIndex, BucketIndex: Int64;
  out Bucket: TWaveEnvelopePoint): Boolean;
var
  Info: TEodPeakCacheLevelInfo;

  Pos: Int64;

  CacheEnd: Int64;
begin
  Result := False;

  FillChar(Bucket, SizeOf(Bucket), 0);

  if (LevelIndex < 0) or (LevelIndex >= FCacheHeader.LevelCount) then
    Exit;

  Info := FCacheHeader.Levels[LevelIndex];

  if (BucketIndex < 0) or (BucketIndex >= Info.Count) then
    Exit;

  if Info.Offset < 0 then
    Exit;

  if BucketIndex > (High(Int64) - Info.Offset) div SizeOf(TWaveEnvelopePoint)
  then
    Exit;

  Pos := Info.Offset + BucketIndex * SizeOf(TWaveEnvelopePoint);

  CacheEnd := FHeader.CacheOffset + FHeader.CacheSize;

  if Pos > CacheEnd - SizeOf(TWaveEnvelopePoint) then
    Exit;

  FStream.Position := Pos;

  FStream.ReadBuffer(Bucket, SizeOf(Bucket));

  Result := True;
end;

function TEodPeakStore.ReadEnvelope(FirstPeakIndex, LastPeakIndex: Int64;
  MaxPoints: Integer; var Envelope: TWaveEnvelope): Boolean;
var
  Level: Integer;
  GroupSize: Int64;
  FirstBucket: Int64;
  LastBucket: Int64;
  Count: Int64;
  I: Int64;
  Bucket: TWaveEnvelopePoint;
begin
  Result := False;
  SetLength(Envelope, 0);
  if FCacheHeader.LevelCount = 0 then
    Exit;

  if FirstPeakIndex < 0 then
    FirstPeakIndex := 0;

  if LastPeakIndex >= FHeader.PeakCount then
  begin
    LastPeakIndex := FHeader.PeakCount - 1;
  end;

  if LastPeakIndex < FirstPeakIndex then
    Exit;

  Level := SelectCacheLevel(FirstPeakIndex, LastPeakIndex, MaxPoints);

  if Level < 0 then
    Exit;

  GroupSize := FCacheHeader.Levels[Level].GroupSize;

  if GroupSize <= 0 then
    Exit;

  FirstBucket := FirstPeakIndex div GroupSize;
  LastBucket := LastPeakIndex div GroupSize;
  Count := LastBucket - FirstBucket + 1;

  if Count > MaxInt then
  begin
    raise ERangeError.Create('Envelope is too large');
  end;

  SetLength(Envelope, Integer(Count));

for I := 0 to Count - 1 do
begin
  if not ReadCacheBucket(
    Level,
    FirstBucket + I,
    Bucket) then
  begin
    SetLength(
      Envelope,
      Integer(I));

    Exit;
  end;

  Envelope[Integer(I)] :=
    Bucket;
end;

  Result := Length(Envelope) > 0;
end;

end.
