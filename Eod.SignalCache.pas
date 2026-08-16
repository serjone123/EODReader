unit Eod.SignalCache;

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, Eod.Types;

type
  TFloatSignalCache = class
  private
    FStream: TFileStream;
    FFileName: string;
    FDeleteOnDestroy: Boolean;
    FCount: Int64;
  public
    constructor Create(const FileName: string = '');
    destructor Destroy; override;
    procedure Append(const Data: TFloatArray);
    procedure Read(StartIndex: Int64; Count: Integer; var Data: TFloatArray);
    property Count: Int64 read FCount;
    property FileName: string read FFileName;
  end;

implementation

constructor TFloatSignalCache.Create(const FileName: string);
begin
  inherited Create;
  FDeleteOnDestroy := FileName = '';
  if FDeleteOnDestroy then
    FFileName := TPath.GetTempFileName
  else
    FFileName := FileName;
  FStream := TFileStream.Create(FFileName, fmCreate or fmOpenReadWrite or fmShareDenyNone);
  FCount := 0;
end;

destructor TFloatSignalCache.Destroy;
begin
  FStream.Free;
  if FDeleteOnDestroy and FileExists(FFileName) then
    DeleteFile(FFileName);
  inherited;
end;

procedure TFloatSignalCache.Append(const Data: TFloatArray);
begin
  if Length(Data) = 0 then Exit;
  FStream.Position := FStream.Size;
  FStream.WriteBuffer(Data[0], Length(Data) * SizeOf(Single));
  Inc(FCount, Length(Data));
end;

procedure TFloatSignalCache.Read(StartIndex: Int64; Count: Integer; var Data: TFloatArray);
var
  Bytes: Int64;
begin
  if Count < 0 then Count := 0;
  if StartIndex < 0 then StartIndex := 0;
  if StartIndex >= FCount then
  begin
    SetLength(Data, 0);
    Exit;
  end;
  if StartIndex + Count > FCount then
    Count := FCount - StartIndex;
  SetLength(Data, Count);
  if Count = 0 then Exit;
  Bytes := Int64(Count) * SizeOf(Single);
  FStream.Position := StartIndex * SizeOf(Single);
  FStream.ReadBuffer(Data[0], Bytes);
end;

end.
