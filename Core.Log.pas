unit Core.Log;

interface

uses
  System.SysUtils;

{ Простой журнал запусков, прогресса и ошибок: %TEMP%\ReadEOD.log (UTF-8).
  Нужен потому, что текст ошибки длинный (стадия, блок, диапазон кадров),
  в строке состояния обрезается, а копировать его из модального окна
  неудобно. По журналу же видно, сколько времени заняла каждая стадия. }

function LogFilePath: string;

procedure LogWrite(const AText: string);
procedure LogWriteFmt(const AFormat: string; const Args: array of const);
procedure LogException(const AContext: string; E: Exception);

implementation

uses
  System.Classes, System.IOUtils, System.SyncObjs;

const
  { Больше мегабайта журнал не растёт: при каждой записи, если файл
    перерос, он пересоздаётся заново. }
  MaxLogBytes = 1024 * 1024;
  Utf8Bom: array[0..2] of Byte = ($EF, $BB, $BF);

var
  LogCS: TCriticalSection;

function LogFilePath: string;
begin
  Result := TPath.Combine(TPath.GetTempPath, 'ReadEOD.log');
end;

procedure LogWrite(const AText: string);
var
  Bytes: TBytes;
  Stream: TFileStream;
begin
  Bytes := TEncoding.UTF8.GetBytes(
    FormatDateTime('hh:nn:ss.zzz', Now) + '  ' + AText + sLineBreak);
  { Запись в журнал не должна никогда ломать приложение, поэтому любая
    ошибка внутри молча игнорируется. }
  LogCS.Enter;
  try
    try
      if FileExists(LogFilePath) then
      begin
        Stream := TFileStream.Create(LogFilePath,
          fmOpenReadWrite or fmShareDenyWrite);
        if Stream.Size > MaxLogBytes then
        begin
          { Журнал не растёт бесконечно: пересоздаём, BOM пишем заново. }
          Stream.Free;
          Stream := TFileStream.Create(LogFilePath, fmCreate);
          Stream.WriteBuffer(Utf8Bom[0], SizeOf(Utf8Bom));
        end;
      end
      else
      begin
        Stream := TFileStream.Create(LogFilePath, fmCreate);
        { BOM — чтобы кириллица читалась в блокноте без догадок о кодировке. }
        Stream.WriteBuffer(Utf8Bom[0], SizeOf(Utf8Bom));
      end;
      try
        Stream.Position := Stream.Size;
        if Length(Bytes) > 0 then
          Stream.WriteBuffer(Bytes[0], Length(Bytes));
      finally
        Stream.Free;
      end;
    except
    end;
  finally
    LogCS.Leave;
  end;
end;

procedure LogWriteFmt(const AFormat: string; const Args: array of const);
begin
  LogWrite(Format(AFormat, Args));
end;

procedure LogException(const AContext: string; E: Exception);
begin
  LogWrite(AContext + ': ' + E.ClassName + ': ' + E.Message);
end;

initialization
  LogCS := TCriticalSection.Create;

finalization
  LogCS.Free;

end.
