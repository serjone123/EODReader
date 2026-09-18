unit Video.FfmpegExport;

{ Запуск ffmpeg/ffprobe как внешних процессов:
    - определение параметров видео эксперимента через ffprobe;
    - Этап A: кодирование потока RGB24-кадров (переданных через stdin) в
      видеофайл обзорной полосы (TFfmpegFrameWriter);
    - Этап B: наложение (overlay) видео полосы на видео эксперимента
      (RunOverlayComposite).

  Полоса рисуется с непрозрачным белым фоном (см. Video.OverlayRenderer),
  поэтому альфа-канал не нужен нигде в этом конвейере — overlay просто
  вставляет прямоугольник кадра полосы поверх кадра эксперимента.

  Реализация использует WinAPI (CreateProcess/CreatePipe) — сборка
  проекта сейчас Win32/Win64, см. AGENTS.md. }

interface

uses
  System.SysUtils, System.Classes;

type
  TSourceVideoInfo = record
    Width: Integer;
    Height: Integer;
    Fps: Double;
    DurationSec: Double;
    HasAudio: Boolean;
  end;

  { Пишет очередной кадр RGB24 в stdin запущенного процесса ffmpeg —
    вызывается из Threads.VideoExport на каждый кадр, отданный
    TVideoOverlayRenderer.RenderFrames. }
  TFfmpegFrameWriter = class
  private
    FStdInWrite: THandle;
    FProcessHandle: THandle;
    FThreadHandle: THandle;
  public
    constructor Create(const AFfmpegPath: string; AWidth, AHeight: Integer;
      AFps: Double; const AOutputFileName: string);
    destructor Destroy; override;

    { Пишет один кадр (ровно Width*Height*3 байт, RGB24). }
    procedure WriteFrame(const APixelsRGB24: TBytes);

    { Закрывает stdin (сигнал ffmpeg о конце потока) и дожидается
      завершения процесса. Возвращает код возврата ffmpeg (0 = успех). }
    function FinishAndWait(ATimeoutMs: Cardinal = INFINITE): Integer;
  end;

function ProbeSourceVideo(const AFfmpegPath, AVideoFileName: string;
  out AInfo: TSourceVideoInfo; out AErrorText: string): Boolean;

{ Синхронный запуск ffmpeg для этапа B (overlay). Блокирует вызывающий
  поток — вызывать только из фонового Threads.VideoExport, не из GUI. }
function RunOverlayComposite(
  const AFfmpegPath: string;
  const AExperimentVideoFileName: string;
  const AOverlayVideoFileName: string;
  const AOutputFileName: string;
  AOverlayX, AOverlayY: Integer;
  out AErrorText: string): Boolean;

implementation

uses
  Winapi.Windows, System.IOUtils, System.StrUtils;

{ ------------------------------------------------------------------ }
{ Вспомогательный запуск короткоживущего процесса с захватом stdout. }
{ ------------------------------------------------------------------ }

function RunProcessCaptureOutput(const ACommandLine: string;
  out AOutput: string): Integer;
var
  SecurityAttr: TSecurityAttributes;
  StdOutRead, StdOutWrite: THandle;
  StartInfo: TStartupInfo;
  ProcInfo: TProcessInformation;
  Buffer: array[0..4095] of AnsiChar;
  BytesRead: Cardinal;
  Cmd: string;
  ExitCode: Cardinal;
  Chunks: TStringBuilder;
begin
  AOutput := '';

  FillChar(SecurityAttr, SizeOf(SecurityAttr), 0);
  SecurityAttr.nLength := SizeOf(SecurityAttr);
  SecurityAttr.bInheritHandle := True;

  if not CreatePipe(StdOutRead, StdOutWrite, @SecurityAttr, 0) then
    raise Exception.Create('Не удалось создать канал для stdout процесса');

  { Дочерний процесс не должен унаследовать читающий конец. }
  SetHandleInformation(StdOutRead, HANDLE_FLAG_INHERIT, 0);

  FillChar(StartInfo, SizeOf(StartInfo), 0);
  StartInfo.cb := SizeOf(StartInfo);
  StartInfo.dwFlags := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
  StartInfo.wShowWindow := SW_HIDE;
  StartInfo.hStdOutput := StdOutWrite;
  StartInfo.hStdError := StdOutWrite;
  StartInfo.hStdInput := 0;

  Cmd := ACommandLine;
  UniqueString(Cmd);

  if not CreateProcess(nil, PChar(Cmd), nil, nil, True,
    CREATE_NO_WINDOW, nil, nil, StartInfo, ProcInfo) then
  begin
    CloseHandle(StdOutRead);
    CloseHandle(StdOutWrite);
    raise Exception.CreateFmt('Не удалось запустить процесс: %s', [ACommandLine]);
  end;

  CloseHandle(StdOutWrite);

  Chunks := TStringBuilder.Create;
  try
    while ReadFile(StdOutRead, Buffer, SizeOf(Buffer) - 1, BytesRead, nil)
      and (BytesRead > 0) do
    begin
      Buffer[BytesRead] := #0;
      Chunks.Append(string(AnsiString(Buffer)));
    end;
    AOutput := Chunks.ToString;
  finally
    Chunks.Free;
  end;

  CloseHandle(StdOutRead);

  WaitForSingleObject(ProcInfo.hProcess, INFINITE);
  GetExitCodeProcess(ProcInfo.hProcess, ExitCode);
  CloseHandle(ProcInfo.hProcess);
  CloseHandle(ProcInfo.hThread);

  Result := Integer(ExitCode);
end;

function ProbeSourceVideo(const AFfmpegPath, AVideoFileName: string;
  out AInfo: TSourceVideoInfo; out AErrorText: string): Boolean;
var
  ProbePath, Cmd, Output: string;
  ExitCode: Integer;
  FpsText: string;
  FpsNum, FpsDen: Integer;

  function ExtractField(const AKey: string): string;
  var
    P1, P2: Integer;
  begin
    Result := '';
    P1 := Output.IndexOf(AKey + '=');
    if P1 < 0 then
      Exit;
    P1 := P1 + Length(AKey) + 1;
    P2 := Output.IndexOf(#10, P1);
    if P2 < 0 then
      P2 := Length(Output);
    Result := Output.Substring(P1, P2 - P1).Trim;
  end;

begin
  Result := False;
  AErrorText := '';
  FillChar(AInfo, SizeOf(AInfo), 0);

  { ffprobe обычно лежит рядом с ffmpeg под тем же именем каталога. }
  ProbePath := TPath.Combine(TPath.GetDirectoryName(AFfmpegPath), 'ffprobe.exe');
  if not TFile.Exists(ProbePath) then
  begin
    AErrorText := 'ffprobe.exe не найден рядом с ffmpeg.exe (' + ProbePath + ')';
    Exit;
  end;

  Cmd := Format('"%s" -v error -select_streams v:0 ' +
    '-show_entries stream=width,height,r_frame_rate ' +
    '-show_entries format=duration ' +
    '-of default=noprint_wrappers=1 "%s"',
    [ProbePath, AVideoFileName]);

  ExitCode := RunProcessCaptureOutput(Cmd, Output);
  if ExitCode <> 0 then
  begin
    AErrorText := 'ffprobe завершился с ошибкой, код ' + ExitCode.ToString;
    Exit;
  end;

  AInfo.Width := StrToIntDef(ExtractField('width'), 0);
  AInfo.Height := StrToIntDef(ExtractField('height'), 0);
  AInfo.DurationSec := StrToFloatDef(ExtractField('duration'), 0,
    TFormatSettings.Invariant);

  FpsText := ExtractField('r_frame_rate'); // например "25/1" или "24992/1000"
  if FpsText.Contains('/') then
  begin
    FpsNum := StrToIntDef(FpsText.Substring(0, FpsText.IndexOf('/')), 0);
    FpsDen := StrToIntDef(FpsText.Substring(FpsText.IndexOf('/') + 1), 1);
    if FpsDen > 0 then
      AInfo.Fps := FpsNum / FpsDen
    else
      AInfo.Fps := 0;
  end
  else
    AInfo.Fps := StrToFloatDef(FpsText, 0, TFormatSettings.Invariant);

  { Наличие аудио — отдельным быстрым запросом, чтобы не усложнять парсинг
    основного вывода. }
  Cmd := Format('"%s" -v error -select_streams a:0 ' +
    '-show_entries stream=index -of csv=p=0 "%s"', [ProbePath, AVideoFileName]);
  RunProcessCaptureOutput(Cmd, Output);
  AInfo.HasAudio := Output.Trim <> '';

  Result := (AInfo.Width > 0) and (AInfo.Height > 0) and (AInfo.Fps > 0);
  if not Result and (AErrorText = '') then
    AErrorText := 'ffprobe не вернул корректные параметры видео';
end;

{ ------------------------------------------------------------------ }
{ TFfmpegFrameWriter — этап A: кадры через stdin -> видеофайл.       }
{ ------------------------------------------------------------------ }

constructor TFfmpegFrameWriter.Create(const AFfmpegPath: string;
  AWidth, AHeight: Integer; AFps: Double; const AOutputFileName: string);
var
  SecurityAttr: TSecurityAttributes;
  StdInRead, StdInWrite: THandle;
  StartInfo: TStartupInfo;
  ProcInfo: TProcessInformation;
  Cmd: string;
begin
  inherited Create;

  FillChar(SecurityAttr, SizeOf(SecurityAttr), 0);
  SecurityAttr.nLength := SizeOf(SecurityAttr);
  SecurityAttr.bInheritHandle := True;

  if not CreatePipe(StdInRead, StdInWrite, @SecurityAttr, 0) then
    raise Exception.Create('Не удалось создать канал для stdin ffmpeg');

  { Пишущий конец не должен наследоваться дочерним процессом. }
  SetHandleInformation(StdInWrite, HANDLE_FLAG_INHERIT, 0);

  FillChar(StartInfo, SizeOf(StartInfo), 0);
  StartInfo.cb := SizeOf(StartInfo);
  StartInfo.dwFlags := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
  StartInfo.wShowWindow := SW_HIDE;
  StartInfo.hStdInput := StdInRead;
  StartInfo.hStdOutput := 0;
  StartInfo.hStdError := 0;

  { -y перезаписывает выходной файл без вопроса (файл готовит сам воркер;
    повторный запуск с тем же именем — штатная ситуация при повторном
    Preview). rawvideo/rgb24 — формат кадров, отдаваемых
    TVideoOverlayRenderer.RenderFrames. }
  Cmd := Format(
    '"%s" -y -f rawvideo -pix_fmt rgb24 -s %dx%d -r %s -i pipe:0 ' +
    '-an -c:v libx264 -preset veryfast -pix_fmt yuv420p "%s"',
    [AFfmpegPath, AWidth, AHeight,
     FormatFloat('0.###', AFps, TFormatSettings.Invariant), AOutputFileName]);

  UniqueString(Cmd);

  if not CreateProcess(nil, PChar(Cmd), nil, nil, True,
    CREATE_NO_WINDOW, nil, nil, StartInfo, ProcInfo) then
  begin
    CloseHandle(StdInRead);
    CloseHandle(StdInWrite);
    raise Exception.CreateFmt('Не удалось запустить ffmpeg: %s', [Cmd]);
  end;

  { Читающий конец нужен был только дочернему процессу. }
  CloseHandle(StdInRead);

  FStdInWrite := StdInWrite;
  FProcessHandle := ProcInfo.hProcess;
  FThreadHandle := ProcInfo.hThread;
end;

destructor TFfmpegFrameWriter.Destroy;
begin
  if FStdInWrite <> 0 then
    CloseHandle(FStdInWrite);
  if FProcessHandle <> 0 then
    CloseHandle(FProcessHandle);
  if FThreadHandle <> 0 then
    CloseHandle(FThreadHandle);
  inherited;
end;

procedure TFfmpegFrameWriter.WriteFrame(const APixelsRGB24: TBytes);
var
  BytesWritten: Cardinal;
  TotalWritten: Cardinal;
begin
  TotalWritten := 0;
  { WriteFile может вернуть частичную запись на канал — дописываем
    остаток циклом. }
  while TotalWritten < Cardinal(Length(APixelsRGB24)) do
  begin
    if not WriteFile(FStdInWrite, APixelsRGB24[TotalWritten],
      Cardinal(Length(APixelsRGB24)) - TotalWritten, BytesWritten, nil) then
      raise Exception.Create('Ошибка записи кадра в stdin ffmpeg ' +
        '(процесс мог завершиться с ошибкой раньше времени)');
    Inc(TotalWritten, BytesWritten);
  end;
end;

function TFfmpegFrameWriter.FinishAndWait(ATimeoutMs: Cardinal): Integer;
var
  ExitCode: Cardinal;
  WaitResult: Cardinal;
begin
  CloseHandle(FStdInWrite);
  FStdInWrite := 0;

  WaitResult := WaitForSingleObject(FProcessHandle, ATimeoutMs);
  if WaitResult <> WAIT_OBJECT_0 then
  begin
    TerminateProcess(FProcessHandle, 1);
    raise Exception.Create('ffmpeg (этап A) не завершился за отведённое время');
  end;

  GetExitCodeProcess(FProcessHandle, ExitCode);
  Result := Integer(ExitCode);
end;

{ ------------------------------------------------------------------ }
{ Этап B — overlay.                                                   }
{ ------------------------------------------------------------------ }

function RunOverlayComposite(
  const AFfmpegPath: string;
  const AExperimentVideoFileName: string;
  const AOverlayVideoFileName: string;
  const AOutputFileName: string;
  AOverlayX, AOverlayY: Integer;
  out AErrorText: string): Boolean;
var
  Cmd, Output: string;
  ExitCode: Integer;
begin
  AErrorText := '';

  { Аудиодорожка берётся из видео эксперимента (0:a?, знак вопроса —
    "если есть"), видео — результат overlay поверх кадра эксперимента.
    Полоса непрозрачна (белый фон), альфа-канал не требуется. }
  Cmd := Format(
    '"%s" -y -i "%s" -i "%s" ' +
    '-filter_complex "[0:v][1:v]overlay=%d:%d:format=auto[outv]" ' +
    '-map "[outv]" -map 0:a? -c:v libx264 -preset medium -crf 18 ' +
    '-c:a copy "%s"',
    [AFfmpegPath, AExperimentVideoFileName, AOverlayVideoFileName,
     AOverlayX, AOverlayY, AOutputFileName]);

  ExitCode := RunProcessCaptureOutput(Cmd, Output);
  Result := ExitCode = 0;
  if not Result then
    AErrorText := Format('ffmpeg (этап B) завершился с кодом %d.%s%s',
      [ExitCode, sLineBreak, Output]);
end;

end.
