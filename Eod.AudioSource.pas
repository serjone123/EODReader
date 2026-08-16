unit Eod.AudioSource;

interface

uses
  System.SysUtils, Eod.Types, Eod.WavReader;

type
  TFourChannelAudioSource = class
  private
    FWav1: TWavReader;
    FWav2: TWavReader;
    FFrames: Int64;
    FSampleRate: Integer;
  public
    constructor Create(const File1, File2: string);
    destructor Destroy; override;
    procedure ReadFrames(AFrame: Int64; ACount: Integer; var Buffer: TAudioChunk);
    property SampleRate: Integer read FSampleRate;
    property TotalFrames: Int64 read FFrames;
  end;

implementation

constructor TFourChannelAudioSource.Create(const File1, File2: string);
begin
  inherited Create;
  FWav1 := TWavReader.Create(File1);
  try
    FWav2 := TWavReader.Create(File2);
  except
    FWav1.Free;
    raise;
  end;

  if FWav1.Channels <> 2 then
    raise Exception.Create('First WAV must be stereo');
  if FWav2.Channels <> 2 then
    raise Exception.Create('Second WAV must be stereo');
  if FWav1.SampleRate <> FWav2.SampleRate then
    raise Exception.Create('WAV files have different sample rates');
  if FWav1.TotalFrames <> FWav2.TotalFrames then
    raise Exception.Create('WAV files have different number of frames');

  FSampleRate := FWav1.SampleRate;
  FFrames := FWav1.TotalFrames;
end;

destructor TFourChannelAudioSource.Destroy;
begin
  FWav2.Free;
  FWav1.Free;
  inherited;
end;

procedure TFourChannelAudioSource.ReadFrames(AFrame: Int64; ACount: Integer; var Buffer: TAudioChunk);
var
  Raw1, Raw2: TFloatArray;
  N, I: Integer;
begin
  if ACount <= 0 then begin SetLength(Buffer, 0); Exit; end;
  SetLength(Raw1, ACount * 2);
  SetLength(Raw2, ACount * 2);
  N := FWav1.ReadFrames(AFrame, ACount, @Raw1[0]);
  if FWav2.ReadFrames(AFrame, ACount, @Raw2[0]) <> N then
    raise Exception.Create('Second WAV returned a different frame count');

  SetLength(Buffer, N);
  for I := 0 to N - 1 do
  begin
    Buffer[I].Ch1 := Raw1[I*2];
    Buffer[I].Ch2 := Raw1[I*2+1];
    Buffer[I].Ch3 := Raw2[I*2];
    Buffer[I].Ch4 := Raw2[I*2+1];
  end;
end;

end.
