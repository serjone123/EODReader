unit Eod.PeakStore;

interface

uses
  System.SysUtils, System.Classes, Eod.Types;

const
  EodPeakPageSize = 5000;

  EODPK_VERSION_1 = 1;
  EODPK_VERSION_2 = 2;

type
  TPeakFileMagic = array[0..7] of AnsiChar;

  { Version 2 header.  The variable UTF-8 source names are stored immediately
    after this fixed header. HeaderSize points to the first peak record. }
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
  end;

  { Version 1 header retained only for backward-compatible reading. }
  TEodPeakFileHeaderV1 = packed record
    Magic: TPeakFileMagic;
    Version: Cardinal;
    SampleRate: Cardinal;
    WindowBefore: Integer;
    WindowAfter: Integer;
    ChannelCount: Cardinal;
    PeakCount: Int64;
  end;

  TEodPeakRecordHeader = packed record
    Position: Int64;
    StartPosition: Int64;
    TimeSeconds: Double;
    PeakValue: Single;
    Prominence: Single;
    SampleCount: Cardinal;
  end;

  TEodPeakStore = class
  private
    FStream: TFileStream;
    FHeader: TEodPeakFileHeader;
    FDataOffset: Int64;
    FSource1Name: string;
    FSource2Name: string;
    class function HeaderMagic: TPeakFileMagic; static;
    class procedure WriteUtf8String(Stream: TStream; const S: string); static;
    class function ReadUtf8String(Stream: TStream; ByteCount: Cardinal): string; static;
    class function FileSizeOf(const FileName: string): Int64; static;
    function RecordSize: Int64;
    function RecordOffset(Index: Int64): Int64;
  public
    class procedure Save(const FileName, SourceFile1, SourceFile2: string;
      const Peaks: TPeakArray; WindowBefore, WindowAfter: Integer;
      PadWithZero: Boolean = False);
    class procedure SaveFromStore(const DestFileName: string; Source: TEodPeakStore;
      const SourceFile1, SourceFile2: string; TotalFrames: Int64);

    constructor Open(const FileName: string);
    destructor Destroy; override;

    function ReadRecord(Index: Int64; out Peak: TPeak;
      out StartPosition: Int64; var Samples: TAudioChunk): Boolean;
    function ReadRecordInfo(Index: Int64; out Peak: TPeak;
      out StartPosition: Int64): Boolean;

    function PageCount: Int64;
    function GetPageBounds(PageIndex: Int64; out FirstIndex, Count: Int64): Boolean;
    function ReadRecordInfoPage(PageIndex: Int64; var Peaks: TPeakArray): Boolean;
    function ReadRecordInfoPageInternal(FirstIndex, Count: Int64;
  var Peaks: TPeakArray): Boolean;

    property Header: TEodPeakFileHeader read FHeader;
    property Source1Name: string read FSource1Name;
    property Source2Name: string read FSource2Name;
  end;

implementation

uses
  System.Math, Eod.AudioSource;

class function TEodPeakStore.HeaderMagic: TPeakFileMagic;
begin
  Result[0] := 'E';
  Result[1] := 'O';
  Result[2] := 'D';
  Result[3] := 'P';
  Result[4] := 'K';
  Result[5] := '0';
  Result[6] := '0';
  Result[7] := '1';
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

class procedure TEodPeakStore.WriteUtf8String(Stream: TStream; const S: string);
var
  B: TBytes;
begin
  B := TEncoding.UTF8.GetBytes(S);
  if Length(B) > 0 then
    Stream.WriteBuffer(B[0], Length(B));
end;

class function TEodPeakStore.ReadUtf8String(Stream: TStream; ByteCount: Cardinal): string;
var
  B: TBytes;
begin
  SetLength(B, ByteCount);
  if ByteCount > 0 then
    Stream.ReadBuffer(B[0], ByteCount);
  Result := TEncoding.UTF8.GetString(B);
end;

class procedure TEodPeakStore.Save(const FileName, SourceFile1, SourceFile2: string;
  const Peaks: TPeakArray; WindowBefore, WindowAfter: Integer; PadWithZero: Boolean);
var
  Source: TFourChannelAudioSource;
  Stream: TFileStream;
  Header: TEodPeakFileHeader;
  Rec: TEodPeakRecordHeader;
  Buffer: TAudioChunk;
  I, Saved: Integer;
  StartPosition: Int64;
  SampleCount: Integer;
  Valid: Boolean;
  Magic: TPeakFileMagic;
  Name1, Name2: TBytes;
  Source1Rate, Source2Rate: Cardinal;
  Source1Channels, Source2Channels: Cardinal;
  SourceStart, SourceEnd, DestOffset, CopyCount: Int64;
  Temp: TAudioChunk;
begin
  if WindowBefore < 0 then
    raise EArgumentOutOfRangeException.Create('WindowBefore must be >= 0');
  if WindowAfter < 0 then
    raise EArgumentOutOfRangeException.Create('WindowAfter must be >= 0');

  Source := TFourChannelAudioSource.Create(SourceFile1, SourceFile2);
  try
    { The combined source is always four channels. Read the WAV metadata
      through the existing source abstraction. Both files are expected to
      have the same sample rate and two channels. }
    Source1Rate := Source.SampleRate;
    Source2Rate := Source.SampleRate;
    Source1Channels := 2;
    Source2Channels := 2;

    Name1 := TEncoding.UTF8.GetBytes(ExtractFileName(SourceFile1));
    Name2 := TEncoding.UTF8.GetBytes(ExtractFileName(SourceFile2));

    FillChar(Header, SizeOf(Header), 0);
    Magic := HeaderMagic;
    Move(Magic, Header.Magic, SizeOf(Magic));
    Header.Version := EODPK_VERSION_2;
    Header.HeaderSize := SizeOf(Header) + Length(Name1) + Length(Name2);
    Header.SampleRate := Source.SampleRate;
    Header.ChannelCount := 4;
    Header.WindowBefore := WindowBefore;
    Header.WindowAfter := WindowAfter;
    Header.SamplesPerPeak := WindowBefore + WindowAfter + 1;
    Header.PeakCount := 0;
    Header.TotalFrames := Source.TotalFrames;
    Header.Source1Size := FileSizeOf(SourceFile1);
    Header.Source2Size := FileSizeOf(SourceFile2);
    Header.Source1SampleRate := Source1Rate;
    Header.Source2SampleRate := Source2Rate;
    Header.Source1Channels := Source1Channels;
    Header.Source2Channels := Source2Channels;
    Header.Source1NameBytes := Length(Name1);
    Header.Source2NameBytes := Length(Name2);

    Stream := TFileStream.Create(FileName, fmCreate);
    try
      Stream.WriteBuffer(Header, SizeOf(Header));
      if Length(Name1) > 0 then
        Stream.WriteBuffer(Name1[0], Length(Name1));
      if Length(Name2) > 0 then
        Stream.WriteBuffer(Name2[0], Length(Name2));

      Saved := 0;
      SampleCount := Header.SamplesPerPeak;

      for I := 0 to High(Peaks) do
      begin
        StartPosition := Peaks[I].Position - WindowBefore;
        Valid := (StartPosition >= 0) and
                 (StartPosition + SampleCount <= Source.TotalFrames);

        if (not Valid) and (not PadWithZero) then
          Continue;

        SetLength(Buffer, SampleCount);
        FillChar(Buffer[0], SampleCount * SizeOf(TAudioFrame), 0);

        if Valid then
          Source.ReadFrames(StartPosition, SampleCount, Buffer)
        else
        begin
          SourceStart := StartPosition;
          if SourceStart < 0 then
            SourceStart := 0;
          SourceEnd := StartPosition + SampleCount;
          if SourceEnd > Source.TotalFrames then
            SourceEnd := Source.TotalFrames;

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
        Rec.SampleCount := Length(Buffer);

        Stream.WriteBuffer(Rec, SizeOf(Rec));
        Stream.WriteBuffer(Buffer[0], Length(Buffer) * SizeOf(TAudioFrame));
        Inc(Saved);
      end;

      Header.PeakCount := Saved;
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
  DestStream: TFileStream;
  Header: TEodPeakFileHeader;
  Rec: TEodPeakRecordHeader;
  Samples: TAudioChunk;
  Peak: TPeak;
  StartPos: Int64;
  I: Integer;
  Name1, Name2: TBytes;
  Saved: Integer;
begin
  if Source = nil then
    raise EArgumentNilException.Create('Source store is nil');

  Name1 := TEncoding.UTF8.GetBytes(ExtractFileName(SourceFile1));
  Name2 := TEncoding.UTF8.GetBytes(ExtractFileName(SourceFile2));

  FillChar(Header, SizeOf(Header), 0);
  Header.Magic := HeaderMagic;
  Header.Version := EODPK_VERSION_2;
  Header.SampleRate := Source.Header.SampleRate;
  Header.ChannelCount := Source.Header.ChannelCount;
  Header.WindowBefore := Source.Header.WindowBefore;
  Header.WindowAfter := Source.Header.WindowAfter;
  Header.SamplesPerPeak := Source.Header.SamplesPerPeak;

  if Source.Header.Version = EODPK_VERSION_2 then
  begin
    Header.Source1Size := Source.Header.Source1Size;
    Header.Source2Size := Source.Header.Source2Size;
    Header.Source1SampleRate := Source.Header.Source1SampleRate;
    Header.Source2SampleRate := Source.Header.Source2SampleRate;
    Header.Source1Channels := Source.Header.Source1Channels;
    Header.Source2Channels := Source.Header.Source2Channels;
    if SourceFile1 = '' then
      Name1 := TEncoding.UTF8.GetBytes(Source.Source1Name);
    if SourceFile2 = '' then
      Name2 := TEncoding.UTF8.GetBytes(Source.Source2Name);
  end;

  Header.Source1NameBytes := Length(Name1);
  Header.Source2NameBytes := Length(Name2);
  Header.HeaderSize := SizeOf(Header) + Length(Name1) + Length(Name2);

  if TotalFrames > 0 then
    Header.TotalFrames := TotalFrames
  else if Source.Header.Version = EODPK_VERSION_2 then
    Header.TotalFrames := Source.Header.TotalFrames
  else
    Header.TotalFrames := 0;

  DestStream := TFileStream.Create(DestFileName, fmCreate);
  try
    DestStream.WriteBuffer(Header, SizeOf(Header));
    if Length(Name1) > 0 then
      DestStream.WriteBuffer(Name1[0], Length(Name1));
    if Length(Name2) > 0 then
      DestStream.WriteBuffer(Name2[0], Length(Name2));

    Saved := 0;
    for I := 0 to Source.Header.PeakCount - 1 do
    begin
      if not Source.ReadRecord(I, Peak, StartPos, Samples) then
        raise Exception.CreateFmt('Cannot read peak %d from source', [I]);

      FillChar(Rec, SizeOf(Rec), 0);
      Rec.Position := Peak.Position;
      Rec.StartPosition := StartPos;
      Rec.TimeSeconds := Peak.Position / Header.SampleRate;
      Rec.PeakValue := Peak.Value;
      Rec.Prominence := Peak.Prominence;
      Rec.SampleCount := Length(Samples);

      DestStream.WriteBuffer(Rec, SizeOf(Rec));
      if Length(Samples) > 0 then
        DestStream.WriteBuffer(Samples[0], Length(Samples) * SizeOf(TAudioFrame));
      Inc(Saved);
    end;

    Header.PeakCount := Saved;
    DestStream.Position := 0;
    DestStream.WriteBuffer(Header, SizeOf(Header));
  finally
    DestStream.Free;
  end;
end;

constructor TEodPeakStore.Open(const FileName: string);
var
  Magic, Expected: TPeakFileMagic;
  V1: TEodPeakFileHeaderV1;
  NameBytes: Cardinal;
begin
  inherited Create;
  FStream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    if FStream.Size < SizeOf(TEodPeakFileHeaderV1) then
      raise Exception.Create('Invalid EOD peak file: too small');

    Expected := HeaderMagic;
    FStream.ReadBuffer(Magic, SizeOf(Magic));
    if not CompareMem(@Magic, @Expected, SizeOf(Magic)) then
      raise Exception.Create('Invalid EOD peak file signature');

    FStream.Position := 0;
    FStream.ReadBuffer(V1, SizeOf(V1));

    if V1.Version = EODPK_VERSION_1 then
    begin
      FillChar(FHeader, SizeOf(FHeader), 0);
      Move(V1.Magic, FHeader.Magic, SizeOf(V1.Magic));
      FHeader.Version := EODPK_VERSION_1;
      FHeader.HeaderSize := SizeOf(V1);
      FHeader.SampleRate := V1.SampleRate;
      FHeader.ChannelCount := V1.ChannelCount;
      FHeader.WindowBefore := V1.WindowBefore;
      FHeader.WindowAfter := V1.WindowAfter;
      FHeader.SamplesPerPeak := V1.WindowBefore + V1.WindowAfter + 1;
      FHeader.PeakCount := V1.PeakCount;
      FHeader.TotalFrames := 0;
      FDataOffset := SizeOf(V1);
      FSource1Name := '';
      FSource2Name := '';
      Exit;
    end;

    if V1.Version <> EODPK_VERSION_2 then
      raise Exception.CreateFmt('Unsupported EOD peak file version: %d', [V1.Version]);

    FStream.Position := 0;
    FStream.ReadBuffer(FHeader, SizeOf(FHeader));

    if FHeader.HeaderSize < SizeOf(FHeader) then
      raise Exception.Create('Invalid EOD peak file header size');
    if FHeader.HeaderSize > FStream.Size then
      raise Exception.Create('Invalid EOD peak file: header exceeds file size');
    if FHeader.ChannelCount <> 4 then
      raise Exception.Create('Unsupported channel count in EOD peak file');
    if FHeader.SamplesPerPeak <> Cardinal(FHeader.WindowBefore + FHeader.WindowAfter + 1) then
      raise Exception.Create('Invalid EOD peak file: sample count does not match window');

    FStream.Position := SizeOf(FHeader);
    FSource1Name := ReadUtf8String(FStream, FHeader.Source1NameBytes);
    FSource2Name := ReadUtf8String(FStream, FHeader.Source2NameBytes);
    NameBytes := FHeader.Source1NameBytes + FHeader.Source2NameBytes;
    if FHeader.HeaderSize <> SizeOf(FHeader) + NameBytes then
      raise Exception.Create('Invalid EOD peak file: header size mismatch');

    FDataOffset := FHeader.HeaderSize;
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
  Result := SizeOf(TEodPeakRecordHeader) +
    Int64(FHeader.SamplesPerPeak) * SizeOf(TAudioFrame);
end;

function TEodPeakStore.RecordOffset(Index: Int64): Int64;
begin
  Result := FDataOffset + Index * RecordSize;
end;

function TEodPeakStore.ReadRecordInfo(Index: Int64; out Peak: TPeak;
  out StartPosition: Int64): Boolean;
var
  Rec: TEodPeakRecordHeader;
begin
  Result := False;
  if (Index < 0) or (Index >= FHeader.PeakCount) then
    Exit;

  FStream.Position := RecordOffset(Index);
  FStream.ReadBuffer(Rec, SizeOf(Rec));

  Peak.Position := Rec.Position;
  Peak.Value := Rec.PeakValue;
  Peak.Prominence := Rec.Prominence;
  StartPosition := Rec.StartPosition;
  Result := True;
end;

function TEodPeakStore.PageCount: Int64;
begin
  if FHeader.PeakCount <= 0 then
    Result := 0
  else
    Result := (FHeader.PeakCount + EodPeakPageSize - 1) div EodPeakPageSize;
end;

function TEodPeakStore.GetPageBounds(PageIndex: Int64; out FirstIndex, Count: Int64): Boolean;
var
  Remaining: Int64;
begin
  Result := False;
  FirstIndex := 0;
  Count := 0;
  if (PageIndex < 0) or (PageIndex >= PageCount) then
    Exit;

  FirstIndex := PageIndex * EodPeakPageSize;
  Remaining := FHeader.PeakCount - FirstIndex;
  if Remaining > EodPeakPageSize then
    Count := EodPeakPageSize
  else
    Count := Remaining;
  Result := Count > 0;
end;

function TEodPeakStore.ReadRecordInfoPageInternal(FirstIndex, Count: Int64;
  var Peaks: TPeakArray): Boolean;
var
  Buffer: TBytes;
  Rec: TEodPeakRecordHeader;
  I: Int64;
  Offset: Int64;
  BytesToRead: Int64;
  RecSize: Int64;
begin
  Result := False;
  SetLength(Peaks, 0);

  if (FirstIndex < 0) or (Count <= 0) then
    Exit;

  if FirstIndex >= FHeader.PeakCount then
    Exit;

  if FirstIndex + Count > FHeader.PeakCount then
    Count := FHeader.PeakCount - FirstIndex;

  RecSize := RecordSize;
  BytesToRead := Count * RecSize;

  { Защита от выхода за пределы файла. }
  if RecordOffset(FirstIndex) + BytesToRead > FStream.Size then
    raise Exception.Create('Invalid EOD peak file: record data exceeds file size');

  SetLength(Peaks, Integer(Count));
  SetLength(Buffer, Integer(BytesToRead));

  FStream.Position := RecordOffset(FirstIndex);

  if BytesToRead > 0 then
    FStream.ReadBuffer(Buffer[0], Integer(BytesToRead));

  for I := 0 to Count - 1 do
  begin
    Offset := I * RecSize;

    Move(
      Buffer[Integer(Offset)],
      Rec,
      SizeOf(TEodPeakRecordHeader)
    );

    Peaks[Integer(I)].Position := Rec.Position;
    Peaks[Integer(I)].Value := Rec.PeakValue;
    Peaks[Integer(I)].Prominence := Rec.Prominence;
  end;

  Result := True;
end;


function TEodPeakStore.ReadRecordInfoPage(PageIndex: Int64;
  var Peaks: TPeakArray): Boolean;
var
  FirstIndex, Count: Int64;
begin
  Result := GetPageBounds(PageIndex, FirstIndex, Count);

  SetLength(Peaks, 0);

  if not Result then
    Exit;

  Result := ReadRecordInfoPageInternal(
    FirstIndex,
    Count,
    Peaks
  );
end;

function TEodPeakStore.ReadRecord(Index: Int64; out Peak: TPeak;
  out StartPosition: Int64; var Samples: TAudioChunk): Boolean;
var
  Rec: TEodPeakRecordHeader;
  SampleBytes: Int64;
begin
  Result := False;
  SetLength(Samples, 0);
  if (Index < 0) or (Index >= FHeader.PeakCount) then
    Exit;

  FStream.Position := RecordOffset(Index);
  FStream.ReadBuffer(Rec, SizeOf(Rec));

  if Rec.SampleCount <> FHeader.SamplesPerPeak then
    raise Exception.CreateFmt(
      'Invalid EOD peak record %d: expected %d samples, got %d',
      [Index, FHeader.SamplesPerPeak, Rec.SampleCount]);

  SetLength(Samples, Rec.SampleCount);
  SampleBytes := Int64(Rec.SampleCount) * SizeOf(TAudioFrame);
  if SampleBytes > 0 then
    FStream.ReadBuffer(Samples[0], SampleBytes);

  Peak.Position := Rec.Position;
  Peak.Value := Rec.PeakValue;
  Peak.Prominence := Rec.Prominence;
  StartPosition := Rec.StartPosition;
  Result := True;
end;

end.
