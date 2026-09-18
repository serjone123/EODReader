unit Video.FfmpegLocate;

{ Поиск исполняемого файла ffmpeg и хранение выбранного пользователем пути
  в отдельном JSON-файле настроек (не смешивается с TEodDetectorConfig,
  см. Core.ConfigStore.pas — это разные по смыслу настройки).

  Порядок поиска:
    1. ffmpeg.exe рядом с exe приложения;
    2. путь, ранее сохранённый пользователем, если файл по нему всё ещё
       существует;
    3. если ничего не найдено — вызывающий GUI-код должен показать диалог
       выбора файла и вызвать SaveFfmpegPath. Эта функция сама диалогов
       не показывает, чтобы не тянуть в юнит зависимость от FMX.Dialogs. }

interface

uses
  System.SysUtils;

function GetVideoSettingsFileName: string;

{ Возвращает True и заполняет APath, если ffmpeg найден автоматически
  (рядом с exe или по ранее сохранённому и всё ещё существующему пути).
  Диалогов не показывает. }
function TryLocateFfmpeg(out APath: string): Boolean;

procedure SaveFfmpegPath(const APath: string);

implementation

uses
  System.IOUtils, System.JSON;

function GetVideoSettingsFileName: string;
begin
  Result := TPath.Combine(TPath.GetDirectoryName(ParamStr(0)),
    'video_export_settings.json');
end;

function TryLoadSavedFfmpegPath(out APath: string): Boolean;
var
  Text: string;
  JV: TJSONValue;
  JO: TJSONObject;
begin
  Result := False;
  APath := '';

  if not TFile.Exists(GetVideoSettingsFileName) then
    Exit;

  Text := TFile.ReadAllText(GetVideoSettingsFileName, TEncoding.UTF8);
  if Text.Trim = '' then
    Exit;

  JV := TJSONObject.ParseJSONValue(Text);
  if JV = nil then
    Exit;
  try
    if not (JV is TJSONObject) then
      Exit;
    JO := TJSONObject(JV);
    Result := JO.TryGetValue<string>('FfmpegPath', APath) and (APath <> '');
  finally
    JV.Free;
  end;
end;

procedure SaveFfmpegPath(const APath: string);
var
  JO: TJSONObject;
begin
  JO := TJSONObject.Create;
  try
    JO.AddPair('FfmpegPath', APath);
    TFile.WriteAllText(GetVideoSettingsFileName, JO.Format(2), TEncoding.UTF8);
  finally
    JO.Free;
  end;
end;

function TryLocateFfmpeg(out APath: string): Boolean;
var
  NearExe: string;
  Saved: string;
begin
  Result := False;
  APath := '';

  { 1. Рядом с исполняемым файлом приложения. }
  NearExe := TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), 'ffmpeg.exe');
  if TFile.Exists(NearExe) then
  begin
    APath := NearExe;
    Result := True;
    Exit;
  end;

  { 2. Путь, сохранённый ранее пользователем — но только если файл по
       нему всё ещё существует (условие из задачи: если ffmpeg по
       сохранённому пути пропал, ищем заново / спрашиваем пользователя). }
  if TryLoadSavedFfmpegPath(Saved) and TFile.Exists(Saved) then
  begin
    APath := Saved;
    Result := True;
  end;
end;

end.
