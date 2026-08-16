unit Eod.WavReader;

interface

uses
  System.SysUtils, System.Classes;

type
  TWavEncoding = (wePCM, weIEEEFloat);

  TWavReader = class
  private
    FStream: TFileStream;
    FSampleRate: Integer;
    FChannels: Integer;
    FBitsPerSample: Integer;
    FBlockAlign: Integer;
    FDataOffset: Int64;
    FDataSize: Int64;
    FEncoding: TWavEncoding;
    FFrameCount: Int64;
    procedure ParseHeader;
    function ReadUInt16: Word;
    function ReadUInt32: Cardinal;
    function ReadFourCC: AnsiString;
    function DecodeSample(const P: PByte): Single;
  public
    constructor Create(const FileName: string);
    destructor Destroy; override;
    procedure SeekFrame(AFrame: Int64);
    function ReadFrames(AFrame: Int64; ACount: Integer; ADestination: PSingle): Integer;
    property SampleRate: Integer read FSampleRate;
    property Channels: Integer read FChannels;
    property BitsPerSample: Integer read FBitsPerSample;
    property BlockAlign: Integer read FBlockAlign;
    property TotalFrames: Int64 read FFrameCount;
    property Encoding: TWavEncoding read FEncoding;
  end;

implementation

function ReadLE16(P: PByte): Word; inline;
begin
  Result := P[0] or (P[1] shl 8);
end;

function ReadLE32(P: PByte): Cardinal; inline;
begin
  Result := Cardinal(P[0]) or (Cardinal(P[1]) shl 8) or
            (Cardinal(P[2]) shl 16) or (Cardinal(P[3]) shl 24);
end;

constructor TWavReader.Create(const FileName: string);
begin
  inherited Create;
  FStream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  ParseHeader;
end;

destructor TWavReader.Destroy;
begin
  FStream.Free;
  inherited;
end;

function TWavReader.ReadUInt16: Word;
var B: array[0..1] of Byte;
begin
  FStream.ReadBuffer(B, SizeOf(B));
  Result := ReadLE16(@B[0]);
end;

function TWavReader.ReadUInt32: Cardinal;
var B: array[0..3] of Byte;
begin
  FStream.ReadBuffer(B, SizeOf(B));
  Result := ReadLE32(@B[0]);
end;

function TWavReader.ReadFourCC: AnsiString;
var B: array[0..3] of AnsiChar;
begin
  FStream.ReadBuffer(B, SizeOf(B));
  SetString(Result, PAnsiChar(@B[0]), 4);
end;

procedure TWavReader.ParseHeader;
var
  RIFF, Wave, ChunkID: AnsiString;
  ChunkSize: Cardinal;
  AudioFormat: Word;
  HaveFmt, HaveData: Boolean;
  ChunkEnd: Int64;
  ExtSize: Word;
  ValidBits: Word;
  ChannelMask: Cardinal;
begin
  HaveFmt := False;
  HaveData := False;

  RIFF := ReadFourCC;
  if RIFF <> 'RIFF' then
    raise Exception.Create('Not a RIFF WAV file');

  ReadUInt32;
  Wave := ReadFourCC;
  if Wave <> 'WAVE' then
    raise Exception.Create('Not a WAVE file');

  while FStream.Position + 8 <= FStream.Size do
  begin
    ChunkID := ReadFourCC;
    ChunkSize := ReadUInt32;
    ChunkEnd := FStream.Position + ChunkSize;

    if ChunkID = 'fmt ' then
    begin
      AudioFormat := ReadUInt16;
      FChannels := ReadUInt16;
      FSampleRate := Integer(ReadUInt32);
      ReadUInt32; // byte rate
      FBlockAlign := ReadUInt16;
      FBitsPerSample := ReadUInt16;

      if AudioFormat = 1 then
        FEncoding := wePCM
      else if AudioFormat = 3 then
        FEncoding := weIEEEFloat
      else if AudioFormat = $FFFE then
      begin
        // WAVE_FORMAT_EXTENSIBLE. Read the sub-format tag.
        ExtSize := ReadUInt16;
        if ExtSize >= 22 then
        begin
          ValidBits := ReadUInt16;
          ChannelMask := ReadUInt32;
          // SubFormat GUID: first DWORD is the real format tag.
          AudioFormat := ReadUInt16;
          if AudioFormat = 1 then
            FEncoding := wePCM
          else if AudioFormat = 3 then
            FEncoding := weIEEEFloat
          else
            raise Exception.CreateFmt('Unsupported WAVE extensible format: %d', [AudioFormat]);
          if ValidBits = 0 then ;
          if ChannelMask = 0 then ;
        end
        else
          raise Exception.Create('Invalid WAVE_FORMAT_EXTENSIBLE chunk');
      end
      else
        raise Exception.CreateFmt('Unsupported WAV format code: %d', [AudioFormat]);

      HaveFmt := True;
    end
    else if ChunkID = 'data' then
    begin
      FDataOffset := FStream.Position;
      FDataSize := ChunkSize;
      HaveData := True;
    end;

    FStream.Position := ChunkEnd + (ChunkSize and 1);

    if HaveFmt and HaveData then
      Break;
  end;

  if not HaveFmt then
    raise Exception.Create('WAV fmt chunk not found');
  if not HaveData then
    raise Exception.Create('WAV data chunk not found');
  if FChannels <= 0 then
    raise Exception.Create('Invalid WAV channel count');
  if FBlockAlign <= 0 then
    raise Exception.Create('Invalid WAV block alignment');
  if (FEncoding = wePCM) and not (FBitsPerSample in [8,16,24,32]) then
    raise Exception.CreateFmt('Unsupported PCM bit depth: %d', [FBitsPerSample]);
  if (FEncoding = weIEEEFloat) and not (FBitsPerSample in [32,64]) then
    raise Exception.CreateFmt('Unsupported float bit depth: %d', [FBitsPerSample]);

  FFrameCount := FDataSize div FBlockAlign;
  FStream.Position := FDataOffset;
end;

procedure TWavReader.SeekFrame(AFrame: Int64);
var
  Pos: Int64;
begin
  if AFrame < 0 then AFrame := 0;
  if AFrame > FFrameCount then AFrame := FFrameCount;
  Pos := FDataOffset + AFrame * FBlockAlign;
  FStream.Position := Pos;
end;

function TWavReader.DecodeSample(const P: PByte): Single;
var
  I32: Integer;
  D: Double;
  F: Single;
  S16: SmallInt;
  Sign24: Integer;
begin
  if FEncoding = weIEEEFloat then
  begin
    if FBitsPerSample = 32 then
    begin
      Move(P^, F, SizeOf(F));
      Exit(F);
    end;
    Move(P^, D, SizeOf(D));
    Exit(D);
  end;

  case FBitsPerSample of
    8: Result := (Integer(P[0]) - 128) / 128.0;
    16:
      begin
        Move(P^, S16, SizeOf(S16));
        Result := S16 / 32768.0;
      end;
    24:
      begin
        I32 := Integer(P[0]) or (Integer(P[1]) shl 8) or (Integer(P[2]) shl 16);
        if (I32 and $800000) <> 0 then
          Sign24 := I32 or Integer($FF000000)
        else
          Sign24 := I32;
        Result := Sign24 / 8388608.0;
      end;
    32:
      begin
        I32 := Integer(Cardinal(P[0]) or (Cardinal(P[1]) shl 8) or
          (Cardinal(P[2]) shl 16) or (Cardinal(P[3]) shl 24));
        Result := I32 / 2147483648.0;
      end;
  else
    Result := 0;
  end;
end;

function TWavReader.ReadFrames(AFrame: Int64; ACount: Integer; ADestination: PSingle): Integer;
var
  BytesToRead: Integer;
  ByteBuf: TBytes;
  FramesRead, Ch: Integer;
  FramePtr: PByte;
  Dst: PSingle;
begin
  Result := 0;
  if ACount <= 0 then Exit;
  if AFrame < 0 then AFrame := 0;
  if AFrame >= FFrameCount then Exit;

  FramesRead := ACount;
  if AFrame + FramesRead > FFrameCount then
    FramesRead := FFrameCount - AFrame;

  SeekFrame(AFrame);
  BytesToRead := FramesRead * FBlockAlign;
  SetLength(ByteBuf, BytesToRead);
  FStream.ReadBuffer(ByteBuf[0], BytesToRead);

  Dst := ADestination;
  FramePtr := @ByteBuf[0];

  for var Frame := 0 to FramesRead - 1 do
  begin
    for Ch := 0 to FChannels - 1 do
    begin
      Dst^ := DecodeSample(FramePtr + Ch * (FBitsPerSample div 8));
      Inc(Dst);
    end;
    Inc(FramePtr, FBlockAlign);
  end;

  Result := FramesRead;
end;

end.
