unit Electrode.Layout;

{$IFDEF FPC}
  {$MODE DELPHI}
  {$H+}
{$ENDIF}

interface

uses
{$IFDEF FPC}
  SysUtils, Classes, StrUtils,
{$ELSE}
  System.SysUtils, System.Classes, System.StrUtils,
{$ENDIF}
  Electrode.Geometry;

const
  { Число дифференциальных каналов усилителя - под текущую аппаратную
    конфигурацию (Ch1..Ch4). Если оборудование изменится, это единственное
    место, которое нужно будет поменять в этом модуле. }
  EodChannelCount = 4;

  ElectrodeLayoutFormatVersion = 1;

type
  { Одна физически подключённая пара контактов (дифференциальный вход),
    указанная пользователем на изображении.

    ВАЖНО: на этапе ввода пользователь может достоверно указать только
    ГЕОМЕТРИЮ пары (два контакта физически соединены одним разъёмом/
    проводом), но НЕ может достоверно сказать:
      - какому номеру канала (Ch1..Ch4) эта пара соответствует;
      - какой из двух контактов пары является "+", а какой "-".
    Оба этих факта поэтому НЕ хранятся здесь как уверенные данные - они
    определяются позже автоматическим подбором (см. Eod.ChannelMatching,
    когда появится) по реальным амплитудам сигнала. PointA/PointB -
    намеренно симметричные, неупорядоченные обозначения, а не "Plus"/
    "Minus", чтобы не создавать ложного впечатления определённости. }
  TElectrodePairInput = record
    PointA, PointB: TPoint2D; // пиксельные координаты на исходном кадре
    Label_: string; // произвольная пользовательская пометка (необязательно)
  end;

  TElectrodePairInputArray = array of TElectrodePairInput;

  { Разметка одной рыбы на кадре: точки "голова" и "хвост", указанные
    пользователем на глаз. Служит для двух целей:
      1) Грубая проверка результата автоматической локализации ("рыба
         была примерно здесь, что выдал алгоритм?") - не точная истина,
         а ориентир;
      2) Оценка размера тела рыбы в относительных единицах (и в см,
         если задан масштаб) - расстояние голова-хвост.
    Как и с электродами, здесь возможна лёгкая путаница "где на самом
    деле голова, а где хвост" при быстрой разметке видео - это не
    критично для целей текущего этапа (грубая проверка/оценка размера),
    но стоит помнить при анализе результатов. }
  TFishReferenceMark = record
    HeadPoint, TailPoint: TPoint2D; // пиксельные координаты на кадре
    Label_: string; // например, "кадр 1234, у левой стенки"
  end;

  TFishReferenceMarkArray = array of TFishReferenceMark;

  { Полный набор данных, вводимых пользователем на одном калибровочном
    кадре: 4 угла аквариума (для геометрической калибровки, см.
    Eod.Geometry.TAquariumCalibration) + до EodChannelCount пар
    электродов + произвольное число отметок рыбы. Один такой набор
    соответствует одному кадру/скриншоту - если ракурс камеры между
    записями не менялся, один набор можно переиспользовать для разных
    сессий записи. }
  TElectrodeLayoutInput = record
    { Информационные поля - не участвуют в вычислениях, но полезны при
      экспорте/повторном открытии, чтобы не перепутать, к какому видео
      относится калибровка. }
    SourceImageFile: string;
    ImageWidth, ImageHeight: Integer;

    { Углы аквариума на изображении, в порядке обхода по часовой стрелке
      начиная с левого верхнего (визуально) угла - порядок важен только
      для удобства чтения экспортированного файла человеком, для расчётов
      использует TAquariumCalibration.CalibrateHomography, которому
      порядок точек не важен. }
    TankCorners: array [0 .. 3] of TPoint2D;
    TankCornersSet: Integer; // сколько из 4 углов пользователь уже указал (0-4)

    { Реальные размеры аквариума в см - НЕОБЯЗАТЕЛЬНЫ. Калибровка и
      локализация полностью работают в ОТНОСИТЕЛЬНЫХ единицах (доля
      ширины/высоты аквариума, 0..1) без этих значений - см.
      BuildCalibrationFromLayout и RelativeToCm. Значение <= 0
      означает "размер не задан/неизвестен". Если размеры станут
      известны позже, их можно вписать и пересчитать результаты в см
      без повторной разметки картинки. }
    TankWidthCm, TankHeightCm: Double;

    { Пары электродов в порядке, в котором пользователь их указал на
      экране (это НЕ номер канала - см. комментарий у TElectrodePairInput). }
    Pairs: TElectrodePairInputArray;

    { Отметки положения рыбы (голова+хвост) - см. TFishReferenceMark. }
    FishMarks: TFishReferenceMarkArray;
  end;

function CreateEmptyLayout: TElectrodeLayoutInput;

{ Сохраняет layout в компактный JSON-файл, который пользователь может
  переслать вместе с несколькими наборами реальных амплитуд для подбора
  сопоставления электрод->канал (см. комментарий у TElectrodePairInput). }
procedure SaveElectrodeLayoutToJSON(const Layout: TElectrodeLayoutInput;
  const FileName: string);

function LoadElectrodeLayoutFromJSON(const FileName: string): TElectrodeLayoutInput;

{ Строит TAquariumCalibration из TankCorners. Результат PixelToWorld -
  ОТНОСИТЕЛЬНЫЕ координаты (0..1 по каждой оси), сантиметры не нужны на
  этом шаге - см. подробное обоснование у реализации этой функции.
  Требует, чтобы все 4 угла уже были указаны (TankCornersSet = 4).
  Модель гомографии - hmAffine (см. подробное обоснование в
  Eod.Geometry.THomographyModel): для прямоугольного аквариума и разумно
  расположенной камеры этого достаточно, и это надёжнее полной
  проективной модели при ручном клике по картинке. }
function BuildCalibrationFromLayout(const Layout: TElectrodeLayoutInput): TAquariumCalibration;

{ True, если пользователь указал оба реальных размера аквариума (см) -
  то есть можно переводить относительные координаты в сантиметры. }
function HasKnownTankSize(const Layout: TElectrodeLayoutInput): Boolean;

{ Относительные координаты (0..1, как их возвращает калибровка из
  BuildCalibrationFromLayout) -> сантиметры. X и Y масштабируются
  независимо друг от друга. Вызывать имеет смысл, только если
  HasKnownTankSize(Layout) = True. }
function RelativeToCm(const P: TPoint2D;
  const Layout: TElectrodeLayoutInput): TPoint2D;

{ Обратное преобразование: сантиметры -> относительные координаты. }
function CmToRelative(const P: TPoint2D;
  const Layout: TElectrodeLayoutInput): TPoint2D;

implementation

function CreateEmptyLayout: TElectrodeLayoutInput;
begin
  FillChar(Result, SizeOf(Result), 0);
  { 0 означает "размер не задан" - см. комментарий у TankWidthCm/
    TankHeightCm в разделе interface. Разметка полностью работает и без
    этих значений (в относительных единицах). }
  Result.TankWidthCm := 0;
  Result.TankHeightCm := 0;
  SetLength(Result.Pairs, 0);
  SetLength(Result.FishMarks, 0);
end;

var
  { Настройки форматирования чисел, не зависящие от локали пользователя
    (точка как разделитель дробной части) - JSON обязан использовать
    точку независимо от региональных настроек ОС. Собственная переменная
    вместо TFormatSettings.Invariant (доступного только в относительно
    новых версиях Delphi и отсутствующего в Free Pascal) ради переносимости. }
  JsonFS: TFormatSettings;

procedure InitJsonFormatSettings;
begin
  FillChar(JsonFS, SizeOf(JsonFS), 0);
  JsonFS.DecimalSeparator := '.';
  JsonFS.ThousandSeparator := ',';
  JsonFS.DateSeparator := '-';
  JsonFS.TimeSeparator := ':';
end;

{ ------------------------------------------------------------------ }
{ Минимальный самодостаточный JSON-writer/reader под фиксированную     }
{ схему этого модуля. Полноценная библиотека (System.JSON в Delphi)   }
{ здесь намеренно не используется: схема простая и плоская, а ручная  }
{ реализация без зависимостей одинаково легко компилируется и в       }
{ Delphi, и при тестовой сборке через Free Pascal.                    }
{ ------------------------------------------------------------------ }

function JsonEscape(const S: string): string;
var
  I: Integer;
  C: Char;
begin
  Result := '';
  for I := 1 to Length(S) do
  begin
    C := S[I];
    case C of
      '"': Result := Result + '\"';
      '\': Result := Result + '\\';
      #13: ; // пропускаем - переносы строк в подписях не нужны
      #10: Result := Result + '\n';
    else
      Result := Result + C;
    end;
  end;
end;

{ Простейший разбор JSON-строки в кавычках, начиная с позиции, где
  Pos указывает на открывающую кавычку. Возвращает разобранную строку и
  сдвигает Pos на позицию сразу после закрывающей кавычки. }
function ParseJsonString(const S: string; var Pos: Integer): string;
begin
  Result := '';
  Inc(Pos); // пропускаем открывающую "
  while (Pos <= Length(S)) and (S[Pos] <> '"') do
  begin
    if (S[Pos] = '\') and (Pos < Length(S)) then
    begin
      Inc(Pos);
      case S[Pos] of
        'n': Result := Result + #10;
        '"': Result := Result + '"';
        '\': Result := Result + '\';
      else
        Result := Result + S[Pos];
      end;
    end
    else
      Result := Result + S[Pos];
    Inc(Pos);
  end;
  Inc(Pos); // пропускаем закрывающую "
end;

{ Пропускает пробельные символы и запятые/скобки-разделители, до начала
  следующего значимого токена (используется при простом ручном разборе). }
procedure SkipWhitespace(const S: string; var Pos: Integer);
begin
  while (Pos <= Length(S)) and (S[Pos] in [' ', #9, #10, #13]) do
    Inc(Pos);
end;

function ParseJsonNumber(const S: string; var Pos: Integer): Double;
var
  StartPos: Integer;
begin
  StartPos := Pos;
  while (Pos <= Length(S)) and (S[Pos] in ['0'..'9', '-', '+', '.', 'e', 'E']) do
    Inc(Pos);
  Result := StrToFloatDef(Copy(S, StartPos, Pos - StartPos), 0,
    JsonFS);
end;

{ Находит позицию значения по ключу внутри плоского JSON-объекта.
  Возвращает позицию первого символа значения (сразу после ':'), или 0,
  если ключ не найден. Рассчитано на СВОЙ ЖЕ формат вывода этого модуля
  (не претендует на разбор произвольного JSON от третьих источников). }
function FindKeyValuePos(const S: string; const Key: string;
  StartFrom: Integer = 1): Integer;
var
  NeedlePos: Integer;
  Needle: string;
begin
  Needle := '"' + Key + '"';
  NeedlePos := PosEx(Needle, S, StartFrom);
  Result := 0;
  if NeedlePos = 0 then
    Exit;
  Result := NeedlePos + Length(Needle);
  while (Result <= Length(S)) and (S[Result] in [' ', #9, #10, #13, ':']) do
    Inc(Result);
end;

procedure SaveElectrodeLayoutToJSON(const Layout: TElectrodeLayoutInput;
  const FileName: string);
var
  SL: TStringList;
  I: Integer;

  function PointToJson(const P: TPoint2D): string;
  begin
    Result := Format('{"x": %.3f, "y": %.3f}', [P.X, P.Y],
      JsonFS);
  end;

begin
  SL := TStringList.Create;
  try
    SL.Add('{');
    SL.Add(Format('  "formatVersion": %d,', [ElectrodeLayoutFormatVersion]));
    SL.Add(Format('  "sourceImageFile": "%s",', [JsonEscape(Layout.SourceImageFile)]));
    SL.Add(Format('  "imageWidth": %d,', [Layout.ImageWidth]));
    SL.Add(Format('  "imageHeight": %d,', [Layout.ImageHeight]));
    SL.Add(Format('  "tankWidthCm": %.3f,', [Layout.TankWidthCm],
      JsonFS));
    SL.Add(Format('  "tankHeightCm": %.3f,', [Layout.TankHeightCm],
      JsonFS));
    SL.Add(Format('  "tankCornersSet": %d,', [Layout.TankCornersSet]));

    SL.Add('  "tankCorners": [');
    for I := 0 to 3 do
      SL.Add('    ' + PointToJson(Layout.TankCorners[I]) +
        IfThen(I < 3, ',', ''));
    SL.Add('  ],');

    SL.Add('  "electrodePairs": [');
    for I := 0 to High(Layout.Pairs) do
    begin
      SL.Add('    {');
      SL.Add('      "label": "' + JsonEscape(Layout.Pairs[I].Label_) + '",');
      SL.Add('      "pointA": ' + PointToJson(Layout.Pairs[I].PointA) + ',');
      SL.Add('      "pointB": ' + PointToJson(Layout.Pairs[I].PointB));
      SL.Add('    }' + IfThen(I < High(Layout.Pairs), ',', ''));
    end;
    SL.Add('  ],');

    SL.Add('  "fishMarks": [');
    for I := 0 to High(Layout.FishMarks) do
    begin
      SL.Add('    {');
      SL.Add('      "label": "' + JsonEscape(Layout.FishMarks[I].Label_) + '",');
      SL.Add('      "headPoint": ' + PointToJson(Layout.FishMarks[I].HeadPoint) + ',');
      SL.Add('      "tailPoint": ' + PointToJson(Layout.FishMarks[I].TailPoint));
      SL.Add('    }' + IfThen(I < High(Layout.FishMarks), ',', ''));
    end;
    SL.Add('  ]');

    SL.Add('}');
    SL.SaveToFile(FileName, TEncoding.UTF8);
  finally
    SL.Free;
  end;
end;

function LoadElectrodeLayoutFromJSON(const FileName: string): TElectrodeLayoutInput;
var
  S: string;
  Pos, ArrStart, ArrEnd, I, J: Integer;
  ArrText: string;
  Objects: TArray<string>;

  function ReadPointAt(const Source: string; var P: Integer): TPoint2D;
  var
    XP, YP: Integer;
  begin
    XP := FindKeyValuePos(Source, 'x', P);
    P := XP;
    Result.X := ParseJsonNumber(Source, P);
    YP := FindKeyValuePos(Source, 'y', P);
    P := YP;
    Result.Y := ParseJsonNumber(Source, P);
  end;

  { Разбивает текст JSON-массива на подстроки верхнего уровня (объекты
    JSON, каждый в своих фигурных скобках), корректно учитывая вложенные
    фигурные скобки (нужно, так как внутри каждого объекта пары/отметки
    есть вложенные pointA/pointB или headPoint/tailPoint). Используется
    и для electrodePairs, и для fishMarks - формат полей внутри разный,
    но структура массива одинаковая. }
  function ExtractTopLevelObjects(const Text: string): TArray<string>;
  var
    P, ObjStart, ObjEnd, Depth: Integer;
  begin
    SetLength(Result, 0);
    P := 1;
    while True do
    begin
      ObjStart := PosEx('{', Text, P);
      if ObjStart = 0 then
        Break;

      Depth := 0;
      ObjEnd := ObjStart;
      while ObjEnd <= Length(Text) do
      begin
        if Text[ObjEnd] = '{' then
          Inc(Depth)
        else if Text[ObjEnd] = '}' then
        begin
          Dec(Depth);
          if Depth = 0 then
            Break;
        end;
        Inc(ObjEnd);
      end;
      if Depth <> 0 then
        Break; // разметка повреждена - прекращаем разбор

      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := Copy(Text, ObjStart, ObjEnd - ObjStart + 1);
      P := ObjEnd + 1;
    end;
  end;

begin
  Result := CreateEmptyLayout;
  with TStringList.Create do
  try
    LoadFromFile(FileName, TEncoding.UTF8);
    S := Text;
  finally
    Free;
  end;

  Pos := FindKeyValuePos(S, 'sourceImageFile');
  if Pos > 0 then Result.SourceImageFile := ParseJsonString(S, Pos);

  Pos := FindKeyValuePos(S, 'imageWidth');
  if Pos > 0 then Result.ImageWidth := Round(ParseJsonNumber(S, Pos));

  Pos := FindKeyValuePos(S, 'imageHeight');
  if Pos > 0 then Result.ImageHeight := Round(ParseJsonNumber(S, Pos));

  Pos := FindKeyValuePos(S, 'tankWidthCm');
  if Pos > 0 then Result.TankWidthCm := ParseJsonNumber(S, Pos);

  Pos := FindKeyValuePos(S, 'tankHeightCm');
  if Pos > 0 then Result.TankHeightCm := ParseJsonNumber(S, Pos);

  Pos := FindKeyValuePos(S, 'tankCornersSet');
  if Pos > 0 then Result.TankCornersSet := Round(ParseJsonNumber(S, Pos));

  { Углы аквариума: находим массив "tankCorners" и последовательно читаем
    4 объекта (x,y) внутри него. }
  ArrStart := FindKeyValuePos(S, 'tankCorners');
  if ArrStart > 0 then
  begin
    Pos := ArrStart;
    for I := 0 to 3 do
    begin
      Pos := PosEx('{', S, Pos);
      if Pos = 0 then Break;
      Result.TankCorners[I] := ReadPointAt(S, Pos);
    end;
  end;

  { Пары электродов: находим массив "electrodePairs", далее разбираем
    объекты верхнего уровня внутри него (см. ExtractTopLevelObjects).
    Пар может быть от 0 до EodChannelCount. }
  SetLength(Result.Pairs, 0);
  ArrStart := FindKeyValuePos(S, 'electrodePairs');
  if ArrStart > 0 then
  begin
    ArrEnd := PosEx(']', S, ArrStart);
    if ArrEnd = 0 then ArrEnd := Length(S);
    ArrText := Copy(S, ArrStart, ArrEnd - ArrStart);

    Objects := ExtractTopLevelObjects(ArrText);
    SetLength(Result.Pairs, Length(Objects));
    for J := 0 to High(Objects) do
    begin
      with Result.Pairs[J] do
      begin
        I := FindKeyValuePos(Objects[J], 'label');
        if I > 0 then Label_ := ParseJsonString(Objects[J], I)
        else Label_ := '';

        I := FindKeyValuePos(Objects[J], 'pointA');
        if I > 0 then
        begin
          I := PosEx('{', Objects[J], I);
          PointA := ReadPointAt(Objects[J], I);
        end;

        I := FindKeyValuePos(Objects[J], 'pointB');
        if I > 0 then
        begin
          I := PosEx('{', Objects[J], I);
          PointB := ReadPointAt(Objects[J], I);
        end;
      end;
    end;
  end;

  { Отметки рыбы: находим массив "fishMarks", разбираем аналогично парам
    электродов, только с полями headPoint/tailPoint. }
  SetLength(Result.FishMarks, 0);
  ArrStart := FindKeyValuePos(S, 'fishMarks');
  if ArrStart > 0 then
  begin
    ArrEnd := PosEx(']', S, ArrStart);
    if ArrEnd = 0 then ArrEnd := Length(S);
    ArrText := Copy(S, ArrStart, ArrEnd - ArrStart);

    Objects := ExtractTopLevelObjects(ArrText);
    SetLength(Result.FishMarks, Length(Objects));
    for J := 0 to High(Objects) do
    begin
      with Result.FishMarks[J] do
      begin
        I := FindKeyValuePos(Objects[J], 'label');
        if I > 0 then Label_ := ParseJsonString(Objects[J], I)
        else Label_ := '';

        I := FindKeyValuePos(Objects[J], 'headPoint');
        if I > 0 then
        begin
          I := PosEx('{', Objects[J], I);
          HeadPoint := ReadPointAt(Objects[J], I);
        end;

        I := FindKeyValuePos(Objects[J], 'tailPoint');
        if I > 0 then
        begin
          I := PosEx('{', Objects[J], I);
          TailPoint := ReadPointAt(Objects[J], I);
        end;
      end;
    end;
  end;
end;

function BuildCalibrationFromLayout(const Layout: TElectrodeLayoutInput): TAquariumCalibration;
var
  WorldPts, PixelPts: array of TPoint2D;
begin
  if Layout.TankCornersSet < 4 then
    raise Exception.Create('Не все 4 угла аквариума указаны - калибровка невозможна');

  { Единичный квадрат вместо сантиметров - см. подробное обоснование в
    комментарии к этой функции в разделе interface: X и Y аффинного
    преобразования масштабируются независимо друг от друга, поэтому
    калибровка по единичному квадрату с последующим умножением
    результата на реальные TankWidthCm/TankHeightCm математически
    эквивалентна прямой калибровке в сантиметрах, но не требует знать
    размеры аквариума заранее. Порядок вершин соответствует порядку,
    в котором пользователь кликал углы на экране (см. подсказки в
    форме ввода Eod.ElectrodeLayoutForm). }
  SetLength(WorldPts, 4);
  SetLength(PixelPts, 4);
  WorldPts[0] := TPoint2D.Create(0, 0);
  WorldPts[1] := TPoint2D.Create(1, 0);
  WorldPts[2] := TPoint2D.Create(1, 1);
  WorldPts[3] := TPoint2D.Create(0, 1);

  PixelPts[0] := Layout.TankCorners[0];
  PixelPts[1] := Layout.TankCorners[1];
  PixelPts[2] := Layout.TankCorners[2];
  PixelPts[3] := Layout.TankCorners[3];

  Result := TAquariumCalibration.Create;
  try
    { Дисторсию по умолчанию не калибруем - для 4 угловых точек
      надёжной оценки K1/K2 всё равно не получить (см. подробный разбор
      в TestGeometrySynthetic.pas), а нулевая дисторсия как минимум не
      портит результат. Если позже появятся точки вдоль стенок,
      вызывающий код может дополнительно вызвать CalibrateDistortion
      сам, до вызова этой функции. }
    Result.CalibrateHomography(WorldPts, PixelPts, hmAffine);
  except
    Result.Free;
    raise;
  end;
end;

function HasKnownTankSize(const Layout: TElectrodeLayoutInput): Boolean;
begin
  Result := (Layout.TankWidthCm > 0) and (Layout.TankHeightCm > 0);
end;

function RelativeToCm(const P: TPoint2D;
  const Layout: TElectrodeLayoutInput): TPoint2D;
begin
  Result.X := P.X * Layout.TankWidthCm;
  Result.Y := P.Y * Layout.TankHeightCm;
end;

function CmToRelative(const P: TPoint2D;
  const Layout: TElectrodeLayoutInput): TPoint2D;
begin
  if Layout.TankWidthCm > 0 then
    Result.X := P.X / Layout.TankWidthCm
  else
    Result.X := 0;
  if Layout.TankHeightCm > 0 then
    Result.Y := P.Y / Layout.TankHeightCm
  else
    Result.Y := 0;
end;

initialization
  InitJsonFormatSettings;

end.
