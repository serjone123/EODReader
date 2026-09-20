unit Electrode.Settings;

{ Хранит последние использованные пути формы разметки
  (Electrode.LayoutForm): файл разметки (JSON) и картинку кадра. Пути
  переживают перезапуск программы, чтобы картинка подгружалась при
  открытии формы автоматически и не приходилось каждый раз выбирать её
  заново отдельно от JSON. Хранятся в маленьком JSON-файле рядом с
  конфигом приложения (по образцу Core.ConfigStore). }

interface

{ Читает сохранённые пути. Если файла нет или он битый — возвращает
  пустые строки (вызывающий молча их игнорирует). }
procedure LoadLayoutPaths(out ALayoutFile, AImageFile: string);

{ Записывает пути. Пишутся значения как есть (кнопка «Очистить всё»
  может сознательно их обнулить). }
procedure SaveLayoutPaths(const ALayoutFile, AImageFile: string);

implementation

uses
  System.SysUtils, System.IOUtils, System.JSON;

function PathsFileName: string;
begin
  Result := TPath.Combine(TPath.GetAppPath, 'electrode_paths.json');
end;

procedure LoadLayoutPaths(out ALayoutFile, AImageFile: string);
var
  Fn, Text: string;
  JV: TJSONValue;
  JO: TJSONObject;
begin
  ALayoutFile := '';
  AImageFile := '';

  Fn := PathsFileName;
  if not TFile.Exists(Fn) then
    Exit;

  Text := TFile.ReadAllText(Fn, TEncoding.UTF8);
  if Text.Trim = '' then
    Exit;

  JV := TJSONObject.ParseJSONValue(Text);
  if JV = nil then
    Exit;
  try
    if not (JV is TJSONObject) then
      Exit;
    JO := TJSONObject(JV);

    JO.TryGetValue<string>('LayoutFile', ALayoutFile);
    JO.TryGetValue<string>('ImageFile', AImageFile);
  finally
    JV.Free;
  end;
end;

procedure SaveLayoutPaths(const ALayoutFile, AImageFile: string);
var
  JO: TJSONObject;
begin
  JO := TJSONObject.Create;
  try
    JO.AddPair('LayoutFile', ALayoutFile);
    JO.AddPair('ImageFile', AImageFile);
    TFile.WriteAllText(PathsFileName, JO.Format(2), TEncoding.UTF8);
  finally
    JO.Free;
  end;
end;

end.