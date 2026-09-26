unit IO.SignalCache;

interface

uses
  System.Classes, System.SysUtils, System.IOUtils, Core.Types;

type
  { Временный файл-кеш отфильтрованного сигнала (4 байта на кадр).
    Создаётся в каталоге CacheDir (пустая строка = %TEMP%) и удаляется
    при Destroy. }
  TFloatSignalCache = class
  private
    FStream: TFileStream;
    FFileName: string;
    FDir: string;
    FCount: Int64;
    FTotalFrames: Int64;
    FSampleRate: Integer;
    FDataOffset: Int64;
    procedure WriteHeader;
  public
    constructor Create(const CacheDir: string = '');
    destructor Destroy; override;
    procedure Initialize(ASampleRate: Integer; ATotalFrames: Int64);
    procedure Append(const Data: TFloatArray);
    procedure Read(StartIndex: Int64; Count: Integer; var Data: TFloatArray);
    property Count: Int64 read FCount;
    property TotalFrames: Int64 read FTotalFrames;
    property SampleRate: Integer read FSampleRate;
    property FileName: string read FFileName;
    property Dir: string read FDir;
  end;

{ Сколько места на диске нужно под кэши анализа: два кэша по 4 байта
  на кадр (отфильтрованный сигнал и правый минимум) плюс запас. }
function SignalCacheRequiredBytes(Frames: Int64): Int64;

{ Свободное место на диске, где лежит каталог ADir; -1, если узнать
  не удалось. Работает и для сетевых путей (UNC). }
function SignalCacheFreeSpace(const ADir: string): Int64;

implementation

uses
  Winapi.Windows;

const
  SignalCacheHeaderSize = 36;
  { Запас сверх 8 байт на кадр: заголовки, выравнивание, и то, что
    файл не сжимается при росте. }
  SignalCacheReserveBytes = 64 * 1024 * 1024;

type
  TFloatSignalCacheHeader = packed record
    Magic: array[0..3] of AnsiChar;
    Version: Cardinal;
    HeaderSize: Cardinal;
    Count: Int64;
    TotalFrames: Int64;
    SampleRate: Cardinal;
    Reserved: Cardinal;
  end;

function SignalCacheRequiredBytes(Frames: Int64): Int64;
begin
  if Frames <= 0 then
    Exit(0);
  { 2 кэша по 4 байта + 50% запаса + фиксированный резерв. }
  Result := (Frames * 8) + (Frames div 2) + SignalCacheReserveBytes;
end;

function SignalCacheFreeSpace(const ADir: string): Int64;
var
  FreeBytes, TotalBytes, TotalFreeBytes: Int64;
  Path: string;
begin
  Result := -1;
  Path := ADir;
  if Path = '' then
    Path := TPath.GetTempPath;
  if not GetDiskFreeSpaceExW(PChar(Path), FreeBytes, TotalBytes,
    @TotalFreeBytes) then
    Exit;
  if FreeBytes < 0 then
    Exit;
  Result := FreeBytes;
end;

constructor TFloatSignalCache.Create(const CacheDir: string);
begin
  inherited Create;
  FDir := CacheDir;
  if FDir = '' then
    FDir := TPath.GetTempPath;
  FFileName := TPath.Combine(FDir, TPath.GetRandomFileName);
  FStream := TFileStream.Create(FFileName, fmCreate or fmOpenReadWrite or fmShareDenyNone);
  FCount := 0;
  FTotalFrames := 0;
  FSampleRate := 0;
  FDataOffset := SizeOf(TFloatSignalCacheHeader);
  WriteHeader;
end;

destructor TFloatSignalCache.Destroy;
begin
  if FStream <> nil then
  begin
    { Итоговый Count в заголовке — файл остаётся самодостаточным. }
    WriteHeader;
    FStream.Free;
    FStream := nil;
  end;
  if FileExists(FFileName) then
    { Явно SysUtils: из-за Winapi.Windows одноимённый DeleteFile — это
      Win32-API, который не удаляет файл, а только помечает его. }
    System.SysUtils.DeleteFile(FFileName);
  inherited;
end;

procedure TFloatSignalCache.WriteHeader;
var
  Header: TFloatSignalCacheHeader;
begin
  FillChar(Header, SizeOf(Header), 0);
  Header.Magic[0] := 'S';
  Header.Magic[1] := 'C';
  Header.Magic[2] := '0';
  Header.Magic[3] := '1';
  Header.Version := 1;
  Header.HeaderSize := SignalCacheHeaderSize;
  Header.Count := FCount;
  Header.TotalFrames := FTotalFrames;
  Header.SampleRate := FSampleRate;
  FStream.Position := 0;
  FStream.WriteBuffer(Header, SizeOf(Header));
end;

procedure TFloatSignalCache.Initialize(ASampleRate: Integer; ATotalFrames: Int64);
begin
  FCount := 0;
  FSampleRate := ASampleRate;
  FTotalFrames := ATotalFrames;
  FStream.Position := FDataOffset;
  WriteHeader;
end;

procedure TFloatSignalCache.Append(const Data: TFloatArray);
var
  Bytes: Int64;
begin
  if Length(Data) = 0 then
    Exit;
  if (FCount > (High(Int64) div SizeOf(Single)) - Length(Data)) then
    raise ERangeError.Create('Signal cache size exceeds Int64');
  Bytes := Int64(Length(Data)) * SizeOf(Single);
  FStream.Position := FDataOffset + FCount * SizeOf(Single);
  FStream.WriteBuffer(Data[0], Bytes);
  Inc(FCount, Length(Data));
  { Заголовок перезаписываем только при Initialize и в Create: он нужен
    для самопроверки файла, но перезапись на каждом чанке — лишние
    два системных вызова на блок. }
end;

procedure TFloatSignalCache.Read(StartIndex: Int64; Count: Integer;
  var Data: TFloatArray);
var
  Remaining: Int64;
begin
  SetLength(Data, 0);
  if Count < 0 then
    Count := 0;
  if StartIndex < 0 then
    StartIndex := 0;
  if (FCount = 0) or (StartIndex >= FCount) then
    Exit;
  Remaining := FCount - StartIndex;
  if Int64(Count) > Remaining then
    Count := Integer(Remaining);
  SetLength(Data, Count);
  if Count = 0 then
    Exit;
  FStream.Position := FDataOffset + StartIndex * SizeOf(Single);
  FStream.ReadBuffer(Data[0], Int64(Count) * SizeOf(Single));
end;

end.
