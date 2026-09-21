unit Electrode.LayoutForm;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Math,
  System.IOUtils,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.StdCtrls, FMX.Objects, FMX.Edit,
  FMX.Layouts, FMX.Dialogs, FMX.ListBox, FMX.Graphics,
  FMX.Controls.Presentation,
  Electrode.Geometry, Electrode.Layout, Electrode.Matching,
  Electrode.Settings, Electrode.Localization, GUI.Plot.Base;

type
  { Режим, определяющий, что означает следующий клик по картинке. }
  TLayoutInputMode = (limNone, limCorners, limPair, limFish, limTruth);

  { Тип последнего ЗАВЕРШЁННОГО действия пользователя (для корректной
    работы "Отменить последнюю точку" - без этого трекера Undo не мог
    бы надёжно определить, что именно отменять, если, например, только
    что была добавлена отметка рыбы, а до этого - пара электродов). }
  TLastAction = (laNone, laCorner, laPair, laFish);

  { Форма для разметки калибровочного кадра: углы аквариума (для
    геометрической калибровки) и пары электродов (геометрия пар известна
    пользователю точно; сопоставление пары->канал и полярность +/- внутри
    пары - НЕТ, это решается позже отдельно по реальным амплитудам, см.
    комментарий в Eod.ElectrodeLayout.TElectrodePairInput).

    Согласно принятому в проекте подходу, у этой формы нет визуального
    .fmx-ресурса - все элементы создаются в коде (см. AGENTS.md /
    существующий пример Eod.SettingsForm). }
  TElectrodeLayoutForm = class(TForm)
  private
    FImageLayout: TLayout;
    FPaintBox: TPaintBox;
    FBitmap: TBitmap; // загруженный калибровочный кадр (может быть nil)
    FStatusLabel: TLabel;
    FInstructionLabel: TLabel;

    FBtnLoadImage: TButton;
    FBtnSetCorners: TButton;
    FBtnAddPair: TButton;
    FBtnAddFish: TButton;
    FBtnUndo: TButton;
    FBtnClearAll: TButton;
    FBtnExportJson: TButton;
    FBtnImportJson: TButton;
    FBtnClearMarkers: TButton;
    FBtnMarkTruth: TButton;

    { Соответствие пары → канал записи: у каждого электрода (пары) СВОЙ
      комбобокс, без промежуточного выделения в списке. Занятый канал не
      блокируется — выбор занятого канала просто снимает его с предыдущей
      пары. FPairLabels показывают номер пары в цвете её канала (те же
      цвета, что у каналов на графиках, EodChannelColors); у пары без
      канала — серый. FSyncingChannels защищает от повторного входа
      OnChange при программном обновлении комбобоксов. }
    FLabelPairChannel: TLabel;
    FPairChannelCombos: array [0 .. 3] of TComboBox;
    FPairLabels: array [0 .. 3] of TLabel;
    FSyncingChannels: Boolean;
    FBtnLocalize: TButton;
    FLocalizeInfo: TLabel;

    FEdTankWidth: TEdit;
    FEdTankHeight: TEdit;
    FLabelTankWidth: TLabel;
    FLabelTankHeight: TLabel;

    FLayout: TElectrodeLayoutInput;

    { Последние использованные пути: файл разметки (JSON) и картинка кадра.
      Переживают перезапуск программы (Electrode.Settings) и позволяют при
      открытии формы сразу подгружать последнюю картинку, не выбирая её
      каждый раз заново. }
    FLastLayoutPath: string;
    FLastImagePath: string;

    { События текущей записи (амплитуды по 4 каналам) — передаются из
      главной формы, когда открыта запись и есть пики; иначе пусто. }
    FAmplitudes: TElectrodeEventArray;

    { Результат локализации последнего прогона — хранится для отрисовки
      маркеров рыбы на кадре; FCalib — калибровка, на которой строился
      результат (относительные координаты -> пиксели кадра). }
    FLocalizedEvents: TLocalizedEventArray;
    FCalib: TAquariumCalibration;

    { Полярность каналов (+1/-1) для «живой» локализации. Управляется
      кнопками Ch1..Ch4; batch-подбор («Локализовать») перезаписывает их
      найденным решением. }
    FOrientation: TSigns4;
    FPolarityButtons: array [0 .. 3] of TButton;
    FLabelPolarity: TLabel;

    { «Живой» маркер: положение рыбы для текущего пика/курсора главной
      формы. FHasLiveEvent — последнее присланное событие; LocalizeLive
      перелокализует его при смене полярности/каналов без новых данных.
      FLiveTrail — траектория позиций за время наблюдения (путь рыбы). }
    FHasLiveEvent: Boolean;
    FLastLiveEvent: TElectrodeEventAmplitudes;
    FHasLivePosition: Boolean;
    FLivePosition: TPoint2D;
    FLiveFrame: Int64;
    FLiveTrail: array of TPoint2D;
    FLiveInfo: TLabel;

    { Метки «истинная позиция рыбы»: клики по кадру, привязанные к событию
      записи. Сохраняются в JSON (Electrode.Layout, TTruthMark) рядом с
      разметкой для честной сверки модели поля с реальными данными
      консольным инструментом SimLayout --truth. }
    FTruthMarks: TTruthMarkArray;

    FMode: TLayoutInputMode;
    FCornersPlaced: Integer;       // 0..4 - сколько углов уже отмечено в текущем проходе
    FHavePendingPairPoint: Boolean; // есть ли уже первая точка незавершённой пары
    FPendingPairPoint: TPoint2D;
    FHavePendingFishHead: Boolean; // есть ли уже точка "голова" незавершённой отметки рыбы
    FPendingFishHead: TPoint2D;
    FLastAction: TLastAction; // для корректной работы "Отменить последнюю точку"

    { Масштаб и смещение отображения картинки внутри PaintBox (картинка
      вписывается с сохранением пропорций - "letterbox"), нужны для
      пересчёта координат клика в пиксели исходного изображения. }
    FDisplayScale: Single;
    FDisplayOffsetX, FDisplayOffsetY: Single;

    procedure PaintBoxPaint(Sender: TObject; Canvas: TCanvas);
    procedure PaintBoxMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Single);

    procedure BtnLoadImageClick(Sender: TObject);
    function DoLoadImage(const AFileName: string): Boolean;
    procedure BtnSetCornersClick(Sender: TObject);
    procedure BtnAddPairClick(Sender: TObject);
    procedure BtnAddFishClick(Sender: TObject);
    procedure BtnMarkTruthClick(Sender: TObject);
    procedure SaveTruthMarksToFile;
    function EventIndexForFrame(AFrame: Int64): Integer;
    procedure BtnUndoClick(Sender: TObject);
    procedure BtnClearAllClick(Sender: TObject);
    procedure BtnExportJsonClick(Sender: TObject);
    procedure BtnImportJsonClick(Sender: TObject);

    procedure ChannelChange(Sender: TObject);
    procedure BtnLocalizeClick(Sender: TObject);
    procedure BtnClearMarkersClick(Sender: TObject);
    procedure RunLocalization;
    procedure UpdateLocalizeButtonState;
    procedure SyncChannelControls;
    procedure UpdatePairLabelColor(APairIndex: Integer);
    procedure ClearLocalizationResult;

    procedure UpdateDisplayTransform;
    function ScreenToImagePixel(SX, SY: Single; out ImgX, ImgY: Single): Boolean;
    procedure UpdateStatus;
    procedure HandleImageClick(ImgX, ImgY: Single);
    procedure ReadTankSizeFromEdits;

    { «Живой» маркер и ручная полярность. }
    procedure PolarityButtonClick(Sender: TObject);
    procedure RefreshPolarityButtons;
    procedure AppendTrail(const P: TPoint2D);
    procedure ClearLiveState;
    procedure LocalizeLive;

    { Диагностика согласованности конфигурации для одного события: какой
      канал самый активный и какой электрод физически ближе к позиции.
      Помогает заметить перепутанные каналы почти-симметричных пар. }
    function DiagnosticText(const AEvent: TElectrodeEventAmplitudes;
      const APosition: TPoint2D; const APairs: TPairGeometryArray): string;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    { Передаёт события записи (амплитуды по каналам) для локализации.
      Пустой массив = данных нет (разметка работает автономно). }
    procedure SetAmplitudes(const AAmplitudes: TElectrodeEventArray);

    { «Живое» событие из главной формы (текущий пик/курсор): локализует
      его текущей конфигурацией «пары<->каналы» + вручную выбранной
      полярностью и обновляет маркер рыбы на кадре (кнопка «Канал пары»
      и кнопки полярности Ch1..Ch4). Во время воспроизведения вызовы
      рисуют путь рыбы. }
    procedure UpdateLiveEvent(const AEvent: TElectrodeEventAmplitudes);

    property Layout: TElectrodeLayoutInput read FLayout;
  end;

implementation

uses
  FMX.DialogService;

{ ------------------------------------------------------------------ }
{ Вспомогательные функции                                           }
{ ------------------------------------------------------------------ }

{ Позиция считается «в аквариуме», если лежит внутри единичного квадрата
  (относительные координаты 0..1) с небольшим допуском - ЛМ может
  останавливаться у самой стенки. Единственный источник истины -
  Electrode.Matching.IsPositionInsideTank (там же штраф вне аквариума
  в оценке конфигураций). }
function InsideTank(const P: TPoint2D): Boolean;
begin
  Result := IsPositionInsideTank(P);
end;

{ Человекочитаемое описание полярности, например "Ch1:+, Ch2:−, Ch3:+, Ch4:−". }
function SignsToString(const S: TSigns4): string;
var
  C: Integer;
begin
  Result := '';
  for C := 0 to 3 do
  begin
    if C > 0 then
      Result := Result + ', ';
    if S[C] < 0 then
      Result := Result + Format('Ch%d:−', [C + 1])
    else
      Result := Result + Format('Ch%d:+', [C + 1]);
  end;
end;

{ Индекс пары электродов, ближайшей к точке APosition (расстояние до любого
  из двух контактов A/B). Пары — уже в мировых координатах (0..1). }
function NearestPairIndex(const APosition: TPoint2D;
  const APairs: TPairGeometryArray): Integer;
var
  P: Integer;
  D, DA, DB, Best: Double;
begin
  Result := -1;
  Best := MaxDouble;
  for P := 0 to High(APairs) do
  begin
    DA := Sqr(APairs[P].A.X - APosition.X) + Sqr(APairs[P].A.Y - APosition.Y);
    DB := Sqr(APairs[P].B.X - APosition.X) + Sqr(APairs[P].B.Y - APosition.Y);
    D := DA;
    if DB < D then
      D := DB;
    if D < Best then
    begin
      Best := D;
      Result := P;
    end;
  end;
end;

{ Диагностика согласованности конфигурации события: сопоставляем самый
  активный канал и физически ближайший к позиции электрод. Когда они
  совпадают — конфигурация согласована; когда нет, каналы почти
  симметричных пар, скорее всего, перепутаны, и это видно сразу. }
function TElectrodeLayoutForm.DiagnosticText(const AEvent: TElectrodeEventAmplitudes;
  const APosition: TPoint2D; const APairs: TPairGeometryArray): string;
var
  ActiveC, PairOfActive, NearestP, P: Integer;
begin
  ActiveC := MostActiveChannel(AEvent);
  PairOfActive := -1;
  for P := 0 to High(APairs) do
    if APairs[P].UserChannel = ActiveC then
    begin
      PairOfActive := P;
      Break;
    end;

  NearestP := NearestPairIndex(APosition, APairs);

  if (PairOfActive >= 0) and (NearestP >= 0) and (PairOfActive = NearestP) then
    Result := Format('Сильный канал Ch%d = ближайший электрод (пара %d): согласовано.',
      [ActiveC + 1, NearestP + 1])
  else if PairOfActive >= 0 then
    Result := Format('Сильный канал Ch%d (пара %d), но ближайший электрод — пара %d. ' +
      'Если почти всегда, каналы пар перепутаны — поменяйте их в комбобоксах.',
      [ActiveC + 1, PairOfActive + 1, NearestP + 1])
  else
    Result := Format('Сильный канал Ch%d, электрод для него не назначен.',
      [ActiveC + 1]);
end;

{ ------------------------------------------------------------------ }
{ Создание формы и элементов управления (без .fmx - см. заголовок     }
{ модуля и комментарий в памяти проекта про Eod.SettingsForm).        }
{ ------------------------------------------------------------------ }

constructor TElectrodeLayoutForm.Create(AOwner: TComponent);
const
  Margin = 8;
  RowHeight = 24;
  ButtonWidth = 160;
  PanelWidth = 200;
var
  ButtonsPanel: TLayout;
  Y: Single;
  C: Integer;

  function AddButton(const ACaption: string; AOnClick: TNotifyEvent): TButton;
  begin
    Result := TButton.Create(Self);
    Result.Parent := ButtonsPanel;
    Result.Position.X := 0;
    Result.Position.Y := Y;
    Result.Width := ButtonWidth;
    Result.Height := RowHeight - 4;
    Result.Text := ACaption;
    Result.OnClick := AOnClick;
    Y := Y + RowHeight;
  end;

begin
  inherited CreateNew(AOwner);

  Caption := 'Разметка электродов и аквариума';
  Width := 1100;

  { Высота под всё содержимое панели справа: кнопки, список пар, канал,
    полярность Ch1..Ch4, кнопку «Отметить истинную позицию» и две
    информационные строки («Локализовать» и «живой маркер») — иначе
    нижние элементы уезжают за край окна и обратной связи не видно.
    Компактная версия: ряды по 24 px, список пар — всего на 4 записи. }
  Height := 760;
  Position := TFormPosition.ScreenCenter;

  FLayout := CreateEmptyLayout;
  FMode := limNone;
  FCornersPlaced := 0;
  FHavePendingPairPoint := False;
  FHavePendingFishHead := False;
  FLastAction := laNone;
  FBitmap := nil;
  FCalib := nil;
  SetLength(FLocalizedEvents, 0);
  FSyncingChannels := False;
  for C := 0 to 3 do
    FOrientation[C] := 1;
  FHasLiveEvent := False;
  FHasLivePosition := False;
  SetLength(FLiveTrail, 0);
  FDisplayScale := 1;
  FDisplayOffsetX := 0;
  FDisplayOffsetY := 0;
  SetLength(FTruthMarks, 0);

  { --- Правая панель с кнопками и полями --- }
  ButtonsPanel := TLayout.Create(Self);
  ButtonsPanel.Parent := Self;
  ButtonsPanel.Align := TAlignLayout.Right;
  ButtonsPanel.Width := PanelWidth;
  ButtonsPanel.Margins.Left := Margin;
  ButtonsPanel.Margins.Top := Margin;
  ButtonsPanel.Margins.Right := Margin;
  ButtonsPanel.Margins.Bottom := Margin;

  Y := 0;

  FBtnLoadImage := AddButton('Загрузить кадр...', BtnLoadImageClick);

  FLabelTankWidth := TLabel.Create(Self);
  FLabelTankWidth.Parent := ButtonsPanel;
  FLabelTankWidth.Position.X := 0;
  FLabelTankWidth.Position.Y := Y;
  FLabelTankWidth.Width := ButtonWidth;
  FLabelTankWidth.Text := 'Ширина аквариума, см (необязательно):';
  Y := Y + 15;

  FEdTankWidth := TEdit.Create(Self);
  FEdTankWidth.Parent := ButtonsPanel;
  FEdTankWidth.Position.X := 0;
  FEdTankWidth.Position.Y := Y;
  FEdTankWidth.Width := ButtonWidth;
  FEdTankWidth.Height := RowHeight - 4;
  FEdTankWidth.Text := '';
  Y := Y + RowHeight;

  FLabelTankHeight := TLabel.Create(Self);
  FLabelTankHeight.Parent := ButtonsPanel;
  FLabelTankHeight.Position.X := 0;
  FLabelTankHeight.Position.Y := Y;
  FLabelTankHeight.Width := ButtonWidth;
  FLabelTankHeight.Text := 'Высота аквариума, см (необязательно):';
  Y := Y + 15;

  FEdTankHeight := TEdit.Create(Self);
  FEdTankHeight.Parent := ButtonsPanel;
  FEdTankHeight.Position.X := 0;
  FEdTankHeight.Position.Y := Y;
  FEdTankHeight.Width := ButtonWidth;
  FEdTankHeight.Height := RowHeight - 4;
  FEdTankHeight.Text := '';
  Y := Y + RowHeight + 6;

  FBtnSetCorners := AddButton('Указать углы аквариума', BtnSetCornersClick);
  FBtnAddPair := AddButton('Добавить пару электродов', BtnAddPairClick);
  FBtnAddFish := AddButton('Отметить рыбу (голова+хвост)', BtnAddFishClick);
  FBtnMarkTruth := AddButton('Отметить истинную позицию', BtnMarkTruthClick);
  FBtnUndo := AddButton('Отменить последнюю точку', BtnUndoClick);
  FBtnClearAll := AddButton('Очистить всё', BtnClearAllClick);

  Y := Y + 6;
  FBtnExportJson := AddButton('Экспорт в JSON...', BtnExportJsonClick);
  FBtnImportJson := AddButton('Импорт из JSON...', BtnImportJsonClick);

  Y := Y + 6;

  { Соответствие «пара → канал записи»: каждому электроду (паре) свой
    комбобокс — никакого списка с промежуточным выделением. Название пары
    слева окрашено в цвет её канала (тот же, что у каналов на графиках,
    EodChannelColors); без канала — серый. }
  FLabelPairChannel := TLabel.Create(Self);
  FLabelPairChannel.Parent := ButtonsPanel;
  FLabelPairChannel.Position.X := 0;
  FLabelPairChannel.Position.Y := Y;
  FLabelPairChannel.Width := ButtonWidth;
  FLabelPairChannel.Height := 15;
  FLabelPairChannel.Text := 'Соответствие пары → канал:';
  Y := Y + 15;

  for C := 0 to 3 do
  begin
    FPairLabels[C] := TLabel.Create(Self);
    FPairLabels[C].Parent := ButtonsPanel;
    FPairLabels[C].Position.X := 0;
    FPairLabels[C].Position.Y := Y + 2;
    FPairLabels[C].Width := 58;
    FPairLabels[C].Height := RowHeight - 4;
    FPairLabels[C].Text := Format('Пара %d', [C + 1]);
    FPairLabels[C].TextSettings.FontColor := TAlphaColorRec.Gray;
    FPairLabels[C].TextSettings.VertAlign := TTextAlign.Center;

    FPairChannelCombos[C] := TComboBox.Create(Self);
    FPairChannelCombos[C].Parent := ButtonsPanel;
    FPairChannelCombos[C].Position.X := FPairLabels[C].Width + 2;
    FPairChannelCombos[C].Position.Y := Y;
    FPairChannelCombos[C].Width := ButtonWidth - FPairLabels[C].Width - 2;
    FPairChannelCombos[C].Height := RowHeight - 4;
    FPairChannelCombos[C].Items.Add('—');
    FPairChannelCombos[C].Items.Add('Ch1');
    FPairChannelCombos[C].Items.Add('Ch2');
    FPairChannelCombos[C].Items.Add('Ch3');
    FPairChannelCombos[C].Items.Add('Ch4');
    FPairChannelCombos[C].ItemIndex := 0;
    FPairChannelCombos[C].Tag := C;
    FPairChannelCombos[C].OnChange := ChannelChange;
    Y := Y + RowHeight;
  end;
  Y := Y + 6;

  { Локализация рыбы по амплитудам пиков текущей записи. }
  FBtnLocalize := AddButton('Локализовать (по пикам)', BtnLocalizeClick);

  FLocalizeInfo := TLabel.Create(Self);
  FLocalizeInfo.Parent := ButtonsPanel;
  FLocalizeInfo.Position.X := 0;
  FLocalizeInfo.Position.Y := Y;
  FLocalizeInfo.Width := ButtonWidth;
  FLocalizeInfo.Height := 40;
  FLocalizeInfo.Text := '';
  FLocalizeInfo.TextSettings.WordWrap := True;
  FLocalizeInfo.TextSettings.FontColor := TAlphaColorRec.Darkblue;
  Y := Y + 40;

  { Очистка результатов локализации с картинки (зелёные маркеры, путь),
    чтобы кадр не замусоривался при повторных прогонах. Разметку
    (углы/пары) не трогает. }
  FBtnClearMarkers := AddButton('Очистить маркеры', BtnClearMarkersClick);

  { Ручная полярность каналов (+/-). Автоподбор («Локализовать по пикам»)
    находит полярность сам; этими кнопками её перебирают вручную — маркер
    рыбы на кадре должен вставать на реальную рыбу при правильной
    полярности. Знак канала = знак окна, в котором амплитуда максимальна
    по модулю (см. Electrode.Amplitudes). }
  FLabelPolarity := TLabel.Create(Self);
  FLabelPolarity.Parent := ButtonsPanel;
  FLabelPolarity.Position.X := 0;
  FLabelPolarity.Position.Y := Y;
  FLabelPolarity.Width := ButtonWidth;
  FLabelPolarity.Height := 15;
  FLabelPolarity.Text := 'Полярность (клик — перевернуть):';
  Y := Y + 15;

  for C := 0 to 3 do
  begin
    FPolarityButtons[C] := TButton.Create(Self);
    FPolarityButtons[C].Parent := ButtonsPanel;
    FPolarityButtons[C].Position.X := 0;
    FPolarityButtons[C].Position.Y := Y;
    FPolarityButtons[C].Width := ButtonWidth;
    FPolarityButtons[C].Height := RowHeight - 4;
    FPolarityButtons[C].Text := Format('Ch%d: +', [C + 1]);
    FPolarityButtons[C].Tag := C;
    FPolarityButtons[C].OnClick := PolarityButtonClick;
    Y := Y + RowHeight;
  end;
  Y := Y + 4;

  { Служебная строка «живого» маркера: последняя позиция рыбы и её
    невязка (качество фита текущей конфигурацией). }
  FLiveInfo := TLabel.Create(Self);
  FLiveInfo.Parent := ButtonsPanel;
  FLiveInfo.Position.X := 0;
  FLiveInfo.Position.Y := Y;
  FLiveInfo.Width := ButtonWidth;
  FLiveInfo.Height := 52;
  FLiveInfo.Text := '';
  FLiveInfo.TextSettings.WordWrap := True;
  Y := Y + 60;

  { --- Центральная область: картинка + статус --- }
  FImageLayout := TLayout.Create(Self);
  FImageLayout.Parent := Self;
  FImageLayout.Align := TAlignLayout.Client;

  FStatusLabel := TLabel.Create(Self);
  FStatusLabel.Parent := FImageLayout;
  FStatusLabel.Align := TAlignLayout.Top;
  FStatusLabel.Height := 24;
  FStatusLabel.Text := 'Кадр не загружен.';

  FInstructionLabel := TLabel.Create(Self);
  FInstructionLabel.Parent := FImageLayout;
  FInstructionLabel.Align := TAlignLayout.Top;
  FInstructionLabel.Height := 24;
  FInstructionLabel.TextSettings.FontColor := TAlphaColorRec.Darkblue;
  FInstructionLabel.Text := '';

  FPaintBox := TPaintBox.Create(Self);
  FPaintBox.Parent := FImageLayout;
  FPaintBox.Align := TAlignLayout.Client;
  FPaintBox.OnPaint := PaintBoxPaint;
  FPaintBox.OnMouseDown := PaintBoxMouseDown;
  FPaintBox.HitTest := True;

  UpdateStatus;
  UpdateLocalizeButtonState;

  { Последнюю картинку подгружаем автоматически, чтобы при каждом
    открытии формы не выбирать её заново (путь хранится в
    Electrode.Settings и переживает перезапуск программы). }
  LoadLayoutPaths(FLastLayoutPath, FLastImagePath);
  if (FLastImagePath <> '') and TFile.Exists(FLastImagePath) then
    DoLoadImage(FLastImagePath);
end;

destructor TElectrodeLayoutForm.Destroy;
begin
  FCalib.Free;
  FBitmap.Free;
  inherited;
end;

{ ------------------------------------------------------------------ }
{ Отображение картинки и разметки                                     }
{ ------------------------------------------------------------------ }

procedure TElectrodeLayoutForm.UpdateDisplayTransform;
var
  ScaleX, ScaleY: Single;
begin
  if (not Assigned(FBitmap)) or (FBitmap.Width = 0) or (FBitmap.Height = 0) then
  begin
    FDisplayScale := 1;
    FDisplayOffsetX := 0;
    FDisplayOffsetY := 0;
    Exit;
  end;

  { Вписываем картинку в PaintBox с сохранением пропорций ("letterbox"),
    аналогично тому, как это обычно делается для превью изображений. }
  ScaleX := FPaintBox.Width / FBitmap.Width;
  ScaleY := FPaintBox.Height / FBitmap.Height;
  FDisplayScale := Min(ScaleX, ScaleY);

  FDisplayOffsetX := (FPaintBox.Width - FBitmap.Width * FDisplayScale) / 2;
  FDisplayOffsetY := (FPaintBox.Height - FBitmap.Height * FDisplayScale) / 2;
end;

function TElectrodeLayoutForm.ScreenToImagePixel(SX, SY: Single;
  out ImgX, ImgY: Single): Boolean;
begin
  Result := False;
  if (not Assigned(FBitmap)) or (FDisplayScale <= 0) then
    Exit;

  ImgX := (SX - FDisplayOffsetX) / FDisplayScale;
  ImgY := (SY - FDisplayOffsetY) / FDisplayScale;

  Result := (ImgX >= 0) and (ImgY >= 0) and
    (ImgX <= FBitmap.Width) and (ImgY <= FBitmap.Height);
end;

procedure TElectrodeLayoutForm.PaintBoxPaint(Sender: TObject; Canvas: TCanvas);
var
  DestRect: TRectF;
  I: Integer;
  P1, P2: TPointF;
  C, ValidChannels: Integer;
  MaxV: Double;
  V: array [0 .. 3] of Double;
  PairA, PairB, Mid: TPoint2D;
  PElect: TElectrodePair;
  Sc: TPointF;

  function ToScreen(const P: TPoint2D): TPointF;
  begin
    Result.X := FDisplayOffsetX + P.X * FDisplayScale;
    Result.Y := FDisplayOffsetY + P.Y * FDisplayScale;
  end;

  procedure DrawMarker(const P: TPointF; Color: TAlphaColor; const Caption: string);
  const
    R = 6;
  begin
    Canvas.Stroke.Kind := TBrushKind.Solid;
    Canvas.Stroke.Color := Color;
    Canvas.Stroke.Thickness := 2;
    Canvas.DrawEllipse(RectF(P.X - R, P.Y - R, P.X + R, P.Y + R), 1);
    Canvas.DrawLine(PointF(P.X - R * 1.5, P.Y), PointF(P.X + R * 1.5, P.Y), 1);
    Canvas.DrawLine(PointF(P.X, P.Y - R * 1.5), PointF(P.X, P.Y + R * 1.5), 1);

    if Caption <> '' then
    begin
      Canvas.Fill.Color := Color;
      Canvas.Font.Size := 13;
      Canvas.FillText(RectF(P.X + R + 2, P.Y - 9, P.X + 120, P.Y + 9),
        Caption, False, 1, [], TTextAlign.Leading, TTextAlign.Center);
    end;
  end;

  { Цвет электрода = цвет назначенного ему канала (EodChannelColors с
    графика), без канала — серый. }
  function PairColor(APairIndex: Integer): TAlphaColor;
  begin
    if (APairIndex >= 0) and (APairIndex < Length(FLayout.Pairs)) and
       (FLayout.Pairs[APairIndex].ChannelIndex >= 0) and
       (FLayout.Pairs[APairIndex].ChannelIndex <= 3) then
      Result := EodChannelColors[FLayout.Pairs[APairIndex].ChannelIndex]
    else
      Result := TAlphaColorRec.Gray;
  end;

begin
  Canvas.Fill.Kind := TBrushKind.Solid;
  Canvas.Fill.Color := TAlphaColorRec.Gainsboro;
  Canvas.FillRect(RectF(0, 0, FPaintBox.Width, FPaintBox.Height), 0, 0, [], 1);

  if not Assigned(FBitmap) then
  begin
    Canvas.Fill.Color := TAlphaColorRec.Gray;
    Canvas.Font.Size := 14;
    Canvas.FillText(RectF(0, 0, FPaintBox.Width, FPaintBox.Height),
      'Загрузите кадр (кнопка "Загрузить кадр...")', False, 1, [],
      TTextAlign.Center, TTextAlign.Center);
    Exit;
  end;

  UpdateDisplayTransform;

  DestRect := RectF(FDisplayOffsetX, FDisplayOffsetY,
    FDisplayOffsetX + FBitmap.Width * FDisplayScale,
    FDisplayOffsetY + FBitmap.Height * FDisplayScale);
  Canvas.DrawBitmap(FBitmap, RectF(0, 0, FBitmap.Width, FBitmap.Height),
    DestRect, 1, True);

  { Углы аквариума, уже отмеченные - соединяем линией по порядку клика,
    чтобы пользователь визуально видел получившийся четырёхугольник. }
  if FCornersPlaced > 0 then
  begin
    for I := 0 to FCornersPlaced - 1 do
      DrawMarker(ToScreen(FLayout.TankCorners[I]), TAlphaColorRec.Yellow,
        Format('Угол %d', [I + 1]));

    if FCornersPlaced >= 2 then
    begin
      Canvas.Stroke.Color := TAlphaColorRec.Yellow;
      Canvas.Stroke.Thickness := 1.5;
      for I := 0 to FCornersPlaced - 2 do
      begin
        P1 := ToScreen(FLayout.TankCorners[I]);
        P2 := ToScreen(FLayout.TankCorners[I + 1]);
        Canvas.DrawLine(P1, P2, 1);
      end;
      if FCornersPlaced = 4 then
      begin
        P1 := ToScreen(FLayout.TankCorners[3]);
        P2 := ToScreen(FLayout.TankCorners[0]);
        Canvas.DrawLine(P1, P2, 1);
      end;
    end;
  end;

  { Уже сохранённые пары электродов. Пары рисуются в цвете своего канала
    (те же цвета, что у каналов на графиках) — красный канал = красный
    электрод; пара без канала — серая. }
  for I := 0 to High(FLayout.Pairs) do
  begin
    P1 := ToScreen(FLayout.Pairs[I].PointA);
    P2 := ToScreen(FLayout.Pairs[I].PointB);

    Canvas.Stroke.Color := PairColor(I);
    Canvas.Stroke.Thickness := 1.5;
    Canvas.DrawLine(P1, P2, 1);

    DrawMarker(P1, PairColor(I), Format('Пара %d', [I + 1]));
    DrawMarker(P2, PairColor(I), '');
  end;

  { Первая точка ещё не завершённой пары (курсор ждёт вторую точку). }
  if FHavePendingPairPoint then
    DrawMarker(ToScreen(FPendingPairPoint), TAlphaColorRec.Magenta,
      Format('Пара %d (1/2)', [Length(FLayout.Pairs) + 1]));

  { Уже сохранённые отметки рыбы: линия голова->хвост, с подписями
    "Г" (голова) и "Х" (хвост), чтобы не путать с электродами. }
  for I := 0 to High(FLayout.FishMarks) do
  begin
    P1 := ToScreen(FLayout.FishMarks[I].HeadPoint);
    P2 := ToScreen(FLayout.FishMarks[I].TailPoint);

    Canvas.Stroke.Color := TAlphaColorRec.Cyan;
    Canvas.Stroke.Thickness := 2;
    Canvas.DrawLine(P1, P2, 1);

    DrawMarker(P1, TAlphaColorRec.Cyan, Format('Рыба %d: Г', [I + 1]));
    DrawMarker(P2, TAlphaColorRec.Cyan, 'Х');
  end;

  { Незавершённая отметка рыбы (уже кликнута голова, ждём хвост). }
  if FHavePendingFishHead then
    DrawMarker(ToScreen(FPendingFishHead), TAlphaColorRec.Cyan,
      Format('Рыба %d: Г (ждём хвост)', [Length(FLayout.FishMarks) + 1]));

  { Метки «истинная позиция рыбы»: белые кружки с малиновым маркером и
    подписью «И N» — их ставит кнопка «Отметить истинную позицию». }
  if Assigned(FCalib) and (Length(FTruthMarks) > 0) then
    for I := 0 to High(FTruthMarks) do
    begin
      P1 := ToScreen(FCalib.WorldToPixel(FTruthMarks[I].PositionRel));
      Canvas.Fill.Kind := TBrushKind.Solid;
      Canvas.Fill.Color := TAlphaColorRec.White;
      Canvas.FillEllipse(RectF(P1.X - 5, P1.Y - 5, P1.X + 5, P1.Y + 5), 1);
      DrawMarker(P1, TAlphaColorRec.Magenta, Format('И %d', [I + 1]));
    end;

  { Результат локализации: зелёный маркер на место каждого события,
    участвовавшего в прогоне (кнопка "Локализовать (по пикам)"). Маркеры
    событий, позиция которых вылезла за пределы аквариума (плохой фит),
    не рисуются вовсе - иначе кадр замусоривается точками вне картинки;
    такие события видны только в счётчике "позиций внутри аквариума"
    информационной строки. }
  if Assigned(FCalib) and (Length(FLocalizedEvents) > 0) then
    for I := 0 to High(FLocalizedEvents) do
      if FLocalizedEvents[I].Converged and
         IsPositionInsideTank(FLocalizedEvents[I].Position) then
        DrawMarker(ToScreen(FCalib.WorldToPixel(FLocalizedEvents[I].Position)),
          TAlphaColorRec.Lime, '');

  { «Живой» маркер: траектория рыбы (позиции из последних присланных
    главной формой событий) и текущая позиция. Траектория оранжевая,
    текущее положение — красный маркер с номером кадра. }
  if Assigned(FCalib) and (Length(FLiveTrail) > 0) then
  begin
    Canvas.Stroke.Color := TAlphaColorRec.Orange;
    Canvas.Stroke.Thickness := 2;
    P1 := ToScreen(FCalib.WorldToPixel(FLiveTrail[0]));
    for I := 1 to High(FLiveTrail) do
    begin
      P2 := ToScreen(FCalib.WorldToPixel(FLiveTrail[I]));
      Canvas.DrawLine(P1, P2, 1);
      P1 := P2;
    end;
  end;

  { «Линии распространения тока»: от текущей позиции рыбы к середине
    каждой пары электродов. Толщина линии пропорциональна предсказанной
    моделью поля амплитуде канала (|V| = 1/r+^1.5 - 1/r-^1.5), цвет —
    цвету канала пары. Толстая линия показывает, какой электрод «видит»
    рыбу сильнее всего, и несовпадение «активный канал ↔ электрод»
    становится видно прямо на кадре. Рисуется только когда всем 4 парам
    назначены каналы. }
  if Assigned(FCalib) and FHasLivePosition and
     HasKnownTankSize(FLayout) and
     (Length(FLayout.Pairs) = EodChannelCount) then
  begin
    ValidChannels := 0;
    for C := 0 to 3 do
    begin
      V[C] := 0;
      if (FLayout.Pairs[C].ChannelIndex >= 0) and
         (FLayout.Pairs[C].ChannelIndex <= 3) then
        Inc(ValidChannels);
    end;
    if ValidChannels = EodChannelCount then
    begin
      MaxV := 0;
      for C := 0 to 3 do
      begin
        { Поле считается в САНТИМЕТРАХ (MinDist = 0.5 см в модели),
          поэтому пару и точку рыбы перед расчётом переводим в см. }
        PairA := RelativeToCm(
          FCalib.PixelToWorld(FLayout.Pairs[C].PointA), FLayout);
        PairB := RelativeToCm(
          FCalib.PixelToWorld(FLayout.Pairs[C].PointB), FLayout);
        PElect.Plus := PairA;
        PElect.Minus := PairB;
        V[FLayout.Pairs[C].ChannelIndex] :=
          Abs(PredictChannelValue(RelativeToCm(FLivePosition, FLayout),
            1, PElect, 1.5));
        if V[FLayout.Pairs[C].ChannelIndex] > MaxV then
          MaxV := V[FLayout.Pairs[C].ChannelIndex];
      end;

      if MaxV > 0 then
        for C := 0 to 3 do
          if (FLayout.Pairs[C].ChannelIndex >= 0) and
             (FLayout.Pairs[C].ChannelIndex <= 3) then
          begin
            { Та же пара в см для середины «линии тока». }
            PairA := RelativeToCm(
              FCalib.PixelToWorld(FLayout.Pairs[C].PointA), FLayout);
            PairB := RelativeToCm(
              FCalib.PixelToWorld(FLayout.Pairs[C].PointB), FLayout);
            Mid.X := (PairA.X + PairB.X) / 2;
            Mid.Y := (PairA.Y + PairB.Y) / 2;
            Sc := ToScreen(FCalib.WorldToPixel(CmToRelative(Mid, FLayout)));
            Canvas.Stroke.Kind := TBrushKind.Solid;
            Canvas.Stroke.Color :=
              EodChannelColors[FLayout.Pairs[C].ChannelIndex];
            Canvas.Stroke.Thickness :=
              1 + 3 * (V[FLayout.Pairs[C].ChannelIndex] / MaxV);
            Canvas.DrawLine(ToScreen(FCalib.WorldToPixel(FLivePosition)),
              Sc, 1);
          end;
    end;
  end;

  if Assigned(FCalib) and FHasLivePosition then
    DrawMarker(ToScreen(FCalib.WorldToPixel(FLivePosition)),
      TAlphaColorRec.Red, Format('Рыба (кадр %d)', [FLiveFrame]));
end;

{ ------------------------------------------------------------------ }
{ Обработка кликов                                                    }
{ ------------------------------------------------------------------ }

procedure TElectrodeLayoutForm.PaintBoxMouseDown(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Single);
var
  ImgX, ImgY: Single;
begin
  if Button <> TMouseButton.mbLeft then
    Exit;
  if FMode = limNone then
    Exit;
  if not ScreenToImagePixel(X, Y, ImgX, ImgY) then
    Exit; // клик мимо картинки - игнорируем

  HandleImageClick(ImgX, ImgY);
end;

procedure TElectrodeLayoutForm.HandleImageClick(ImgX, ImgY: Single);
var
  NewPair: TElectrodePairInput;
  NewFish: TFishReferenceMark;
  N, C: Integer;
begin
  case FMode of
    limCorners:
      begin
        if FCornersPlaced >= 4 then
          Exit; // на всякий случай - кнопка сама сбрасывает счётчик перед стартом

        FLayout.TankCorners[FCornersPlaced] := TPoint2D.Create(ImgX, ImgY);
        Inc(FCornersPlaced);
        FLastAction := laCorner;

        if FCornersPlaced = 4 then
        begin
          FLayout.TankCornersSet := 4;
          FMode := limNone;
        end;
      end;

    limPair:
      begin
        if not FHavePendingPairPoint then
        begin
          FPendingPairPoint := TPoint2D.Create(ImgX, ImgY);
          FHavePendingPairPoint := True;
        end
        else
        begin
          NewPair.PointA := FPendingPairPoint;
          NewPair.PointB := TPoint2D.Create(ImgX, ImgY);
          NewPair.Label_ := '';
          NewPair.ChannelIndex := -1;

          N := Length(FLayout.Pairs);
          SetLength(FLayout.Pairs, N + 1);
          FLayout.Pairs[N] := NewPair;

          FHavePendingPairPoint := False;
          FMode := limNone;
          FLastAction := laPair;
          SyncChannelControls;
          UpdateLocalizeButtonState;
          ClearLiveState;
        end;
      end;

    limFish:
      begin
        if not FHavePendingFishHead then
        begin
          FPendingFishHead := TPoint2D.Create(ImgX, ImgY);
          FHavePendingFishHead := True;
        end
        else
        begin
          NewFish.HeadPoint := FPendingFishHead;
          NewFish.TailPoint := TPoint2D.Create(ImgX, ImgY);
          NewFish.Label_ := '';

          N := Length(FLayout.FishMarks);
          SetLength(FLayout.FishMarks, N + 1);
          FLayout.FishMarks[N] := NewFish;

          FHavePendingFishHead := False;
          FMode := limNone;
          FLastAction := laFish;
        end;
      end;

    limTruth:
      begin
        { Однокликовый режим: клик по кадру ставит метку истинной позиции
          рыбы, привязанную к последнему «живому» событию из главной формы
          (если оно есть), и сразу сохраняет файл рядом с разметкой. }
        try
          if not Assigned(FCalib) then
            FCalib := BuildCalibrationFromLayout(FLayout);
        except
          FCalib := nil;
        end;
        if Assigned(FCalib) then
        begin
          N := Length(FTruthMarks);
          SetLength(FTruthMarks, N + 1);
          FTruthMarks[N].Frame := -1;
          FTruthMarks[N].CEvent := -1;
          FTruthMarks[N].Note := '';
          FTruthMarks[N].HasAmp := False;
          if FHasLiveEvent then
          begin
            FTruthMarks[N].Frame := FLastLiveEvent.Frame;
            FTruthMarks[N].CEvent := EventIndexForFrame(FLastLiveEvent.Frame);
            for C := 0 to 3 do
              FTruthMarks[N].Amplitudes[C] := FLastLiveEvent.Amplitudes[C];
            FTruthMarks[N].HasAmp := True;
          end;
          FTruthMarks[N].PositionRel := FCalib.PixelToWorld(
            TPoint2D.Create(ImgX, ImgY));
          SaveTruthMarksToFile;
        end
        else
          FInstructionLabel.Text :=
            'Истинная позиция: укажите сначала 4 угла аквариума.';
        FMode := limNone;
      end;
  else
    ; // limNone - ничего не делаем
  end;

  UpdateStatus;
  FPaintBox.Repaint;
end;

procedure TElectrodeLayoutForm.BtnMarkTruthClick(Sender: TObject);
begin
  { Клик по кадру поставит метку истинной позиции рыбы (привязанную к
    текущему «живому» событию) и сразу сохранит её в JSON рядом с
    разметкой (Electrode.Layout.SaveTruthMarksToJSON). }
  if FLastLayoutPath = '' then
  begin
    FInstructionLabel.Text :=
      'Сначала сохраните разметку в JSON ("Экспорт в JSON") — метки пишутся рядом с ней.';
    Exit;
  end;
  FMode := limTruth;
  UpdateStatus;
end;

function TElectrodeLayoutForm.EventIndexForFrame(AFrame: Int64): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to High(FAmplitudes) do
    if FAmplitudes[I].Frame = AFrame then
    begin
      Result := I;
      Exit;
    end;
end;

procedure TElectrodeLayoutForm.SaveTruthMarksToFile;
var
  Dir, Base, OutName: string;
begin
  if FLastLayoutPath = '' then
  begin
    FInstructionLabel.Text :=
      'Разметка не сохранена в JSON — откройте панель разметки заново и экспортируйте её (или импортируйте).';
    Exit;
  end;
  Dir := ExtractFilePath(FLastLayoutPath);
  Base := ChangeFileExt(ExtractFileName(FLastLayoutPath), '');
  OutName := Dir + Base + '_marks.json';
  ReadTankSizeFromEdits;
  SaveTruthMarksToJSON(FTruthMarks,
    ExtractFileName(FLastLayoutPath),
    FLayout.TankWidthCm, FLayout.TankHeightCm, OutName);
  if FHasLiveEvent then
    FInstructionLabel.Text := Format(
      'Истинных позиций: %d шт., сохранено: %s (с амплитудами события)',
      [Length(FTruthMarks), OutName])
  else
    FInstructionLabel.Text := Format(
      'Истинных позиций: %d шт., сохранено: %s (БЕЗ амплитуд — перед кликом поставьте курсор/плейхед на событие)',
      [Length(FTruthMarks), OutName]);
end;

{ ------------------------------------------------------------------ }
{ Кнопки                                                              }
{ ------------------------------------------------------------------ }

procedure TElectrodeLayoutForm.BtnLoadImageClick(Sender: TObject);
var
  D: TOpenDialog;
begin
  D := TOpenDialog.Create(Self);
  try
    D.Filter := 'Изображения (*.png;*.jpg;*.jpeg;*.bmp)|*.png;*.jpg;*.jpeg;*.bmp|Все файлы (*.*)|*.*';
    D.Title := 'Загрузить калибровочный кадр';
    if not D.Execute then
      Exit;

    if not DoLoadImage(D.FileName) then
      Exit;

    { Запоминаем путь, чтобы в следующий раз картинка подгрузилась сама. }
    FLastImagePath := D.FileName;
    SaveLayoutPaths(FLastLayoutPath, FLastImagePath);
  finally
    D.Free;
  end;
end;

{ Загрузка картинки кадра с полным сбросом маркеров. Возвращает False,
  если файл не прочитан (тогда состояние формы не меняется). }
function TElectrodeLayoutForm.DoLoadImage(const AFileName: string): Boolean;
begin
  Result := False;
  if not TFile.Exists(AFileName) then
    Exit;

  FreeAndNil(FBitmap);
  FBitmap := TBitmap.Create;
  try
    FBitmap.LoadFromFile(AFileName);
  except
    FreeAndNil(FBitmap);
    Exit;
  end;

  FLayout.SourceImageFile := ExtractFileName(AFileName);
  FLayout.ImageWidth := Round(FBitmap.Width);
  FLayout.ImageHeight := Round(FBitmap.Height);

  ClearLocalizationResult;
  ClearLiveState;
  UpdateDisplayTransform;
  UpdateStatus;
  FPaintBox.Repaint;
  Result := True;
end;

procedure TElectrodeLayoutForm.BtnSetCornersClick(Sender: TObject);
begin
  if not Assigned(FBitmap) then
  begin
    ShowMessage('Сначала загрузите калибровочный кадр.');
    Exit;
  end;

  ReadTankSizeFromEdits;

  FMode := limCorners;
  FCornersPlaced := 0;
  FLayout.TankCornersSet := 0;
  FHavePendingPairPoint := False;
  FLastAction := laNone;
  ClearLiveState;
  UpdateStatus;
  FPaintBox.Repaint;
end;

procedure TElectrodeLayoutForm.BtnAddPairClick(Sender: TObject);
begin
  if not Assigned(FBitmap) then
  begin
    ShowMessage('Сначала загрузите калибровочный кадр.');
    Exit;
  end;

  if Length(FLayout.Pairs) >= EodChannelCount then
  begin
    ShowMessage(Format('Уже указано максимальное число пар (%d). ' +
      'Удалите лишнюю через "Очистить всё", если нужно переразметить.',
      [EodChannelCount]));
    Exit;
  end;

  FMode := limPair;
  FHavePendingPairPoint := False;
  UpdateStatus;
end;

procedure TElectrodeLayoutForm.BtnAddFishClick(Sender: TObject);
begin
  if not Assigned(FBitmap) then
  begin
    ShowMessage('Сначала загрузите калибровочный кадр.');
    Exit;
  end;

  FMode := limFish;
  FHavePendingFishHead := False;
  UpdateStatus;
end;

procedure TElectrodeLayoutForm.BtnUndoClick(Sender: TObject);
begin
  { Незавершённая (ещё не сохранённая) точка - отменяем её в первую
    очередь, это всегда самое недавнее действие. }
  if FHavePendingPairPoint then
  begin
    FHavePendingPairPoint := False;
  end
  else if FHavePendingFishHead then
  begin
    FHavePendingFishHead := False;
  end
  else
  begin
    { Иначе отменяем последнее ЗАВЕРШЁННОЕ действие - используем
      FLastAction, а не догадки по текущему режиму (FMode), так как
      режим уже мог быть сброшен в limNone после завершения действия. }
    case FLastAction of
      laCorner:
        if FCornersPlaced > 0 then
        begin
          Dec(FCornersPlaced);
          FLayout.TankCornersSet := FCornersPlaced;
          FLastAction := laNone;
          ClearLocalizationResult;
          ClearLiveState;
        end;
      laPair:
        if Length(FLayout.Pairs) > 0 then
        begin
          SetLength(FLayout.Pairs, Length(FLayout.Pairs) - 1);
          SyncChannelControls;
          UpdateLocalizeButtonState;
          FLastAction := laNone;
          ClearLiveState;
        end;
      laFish:
        if Length(FLayout.FishMarks) > 0 then
        begin
          SetLength(FLayout.FishMarks, Length(FLayout.FishMarks) - 1);
          FLastAction := laNone;
        end;
    else
      ; // laNone или неизвестное состояние - отменять нечего
    end;
  end;

  UpdateStatus;
  FPaintBox.Repaint;
end;

procedure TElectrodeLayoutForm.BtnClearAllClick(Sender: TObject);
begin
  TDialogService.MessageDialog(
    'Удалить всю текущую разметку (углы, все пары электродов и отметки рыбы)?',
    TMsgDlgType.mtConfirmation,
    [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo],
    TMsgDlgBtn.mbNo, // Кнопка по умолчанию (фокус на "Нет" для безопасности)
    0,
    procedure(const AResult: TModalResult)
    begin
      // Если пользователь не нажал "Да" — просто ничего не делаем и выходим из колбэка
      if AResult <> mrYes then
        Exit;

      // Весь код очистки выполняется только при подтверждении
      ReadTankSizeFromEdits;
      FLayout.TankCornersSet := 0;
      FCornersPlaced := 0;
      SetLength(FLayout.Pairs, 0);
      SetLength(FLayout.FishMarks, 0);
      FMode := limNone;
      FHavePendingPairPoint := False;
      FHavePendingFishHead := False;
      FLastAction := laNone;

      ClearLocalizationResult;
      ClearLiveState;
      SyncChannelControls;
      UpdateStatus;
      FPaintBox.Repaint;
    end
  );
end;

procedure TElectrodeLayoutForm.BtnExportJsonClick(Sender: TObject);
var
  D: TSaveDialog;
begin
  ReadTankSizeFromEdits;

  D := TSaveDialog.Create(Self);
  try
    D.Filter := 'JSON-файлы (*.json)|*.json';
    D.DefaultExt := 'json';
    D.FileName := 'electrode_layout.json';
    if not D.Execute then
      Exit;

    SaveElectrodeLayoutToJSON(FLayout, D.FileName);
    ShowMessage('Сохранено: ' + D.FileName);
    FLastLayoutPath := D.FileName;
    SaveLayoutPaths(FLastLayoutPath, FLastImagePath);
  finally
    D.Free;
  end;
end;

procedure TElectrodeLayoutForm.BtnImportJsonClick(Sender: TObject);
var
  D: TOpenDialog;
begin
  D := TOpenDialog.Create(Self);
  try
    D.Filter := 'JSON-файлы (*.json)|*.json';
    D.Title := 'Импорт разметки электродов';
    if not D.Execute then
      Exit;

    FLayout := LoadElectrodeLayoutFromJSON(D.FileName);
    FCornersPlaced := FLayout.TankCornersSet;
    FMode := limNone;
    FHavePendingPairPoint := False;
    FHavePendingFishHead := False;
    FLastAction := laNone;

    FLastLayoutPath := D.FileName;

    { Картинку пытаемся подгрузить автоматически из запомненного пути
      (см. комментарий у FLastImagePath). Если это та же картинка, что
      в разметке, — всё сойдётся без лишних вопросов. }
    if (FLastImagePath <> '') and TFile.Exists(FLastImagePath) then
      DoLoadImage(FLastImagePath);

    ClearLocalizationResult;
    ClearLiveState;
    SaveLayoutPaths(FLastLayoutPath, FLastImagePath);

    { Поля размера аквариума показываем пустыми, если размер не задан
      (0 - см. комментарий у TankWidthCm/TankHeightCm), а не как "0",
      чтобы не создавать впечатление, что ноль - это реальное значение. }
    if FLayout.TankWidthCm > 0 then
      FEdTankWidth.Text := FormatFloat('0.##', FLayout.TankWidthCm)
    else
      FEdTankWidth.Text := '';
    if FLayout.TankHeightCm > 0 then
      FEdTankHeight.Text := FormatFloat('0.##', FLayout.TankHeightCm)
    else
      FEdTankHeight.Text := '';

    { Если авто-загрузка не смогла (путь потерян/файл удалён) или
      картинка на экране не совпадает с той, что в разметке, - кадр
      загружаем вручную через "Загрузить кадр...". Совпало (имя файла
      сошлось) - молчим, всё и так корректно. }
    if Assigned(FBitmap) and (FLayout.SourceImageFile <> '') and
       (AnsiLowerCase(ExtractFileName(FLayout.SourceImageFile)) <>
        AnsiLowerCase(ExtractFileName(FLastImagePath))) then
      ShowMessage('Загружена разметка для кадра "' + FLayout.SourceImageFile +
        '". Если сейчас открыт другой кадр, загрузите правильный ' +
        'через "Загрузить кадр...", иначе точки будут показаны неверно.');

    SyncChannelControls;
    UpdateStatus;
    FPaintBox.Repaint;
  finally
    D.Free;
  end;
end;

{ ------------------------------------------------------------------ }
{ Назначение каналов и локализация рыбы                              }
{ ------------------------------------------------------------------ }

procedure TElectrodeLayoutForm.ChannelChange(Sender: TObject);
var
  I, J, Ch: Integer;
begin
  if FSyncingChannels then
    Exit;

  I := TComboBox(Sender).Tag;
  if (I < 0) or (I >= Length(FLayout.Pairs)) then
    Exit;
  Ch := TComboBox(Sender).ItemIndex - 1; // -1 = «—», канал не назначен
  if (Ch < -1) or (Ch > 3) then
    Exit;

  { Выбранный канал мог быть занят другой парой — просто забираем его
    себе: с прежней пары он снимается (никаких «выбрать занятый нельзя»). }
  if Ch >= 0 then
    for J := 0 to High(FLayout.Pairs) do
      if (J <> I) and (FLayout.Pairs[J].ChannelIndex = Ch) then
        FLayout.Pairs[J].ChannelIndex := -1;

  FLayout.Pairs[I].ChannelIndex := Ch;

  FSyncingChannels := True;
  try
    SyncChannelControls;
  finally
    FSyncingChannels := False;
  end;

  UpdateLocalizeButtonState;
  { Смена привязки каналов меняет интерпретацию позиций — путь рыбы
    перерисуем с чистого листа последней (или будущей) конфигурацией. }
  SetLength(FLiveTrail, 0);
  LocalizeLive;
  FPaintBox.Repaint;
end;

{ Синхронизирует комбобоксы и цвета подписей с текущей разметкой.
  Вызывается при добавлении/удалении пар, импорте, «Очистить всё» и
  применении найденной конфигурации. FSyncingChannels защищает от
  повторного входа OnChange. }
procedure TElectrodeLayoutForm.SyncChannelControls;
var
  I, Ch: Integer;
begin
  for I := 0 to 3 do
  begin
    if I < Length(FLayout.Pairs) then
    begin
      Ch := FLayout.Pairs[I].ChannelIndex;
      if (Ch < -1) or (Ch > 3) then
        Ch := -1;
      FPairChannelCombos[I].ItemIndex := Ch + 1;
      FPairChannelCombos[I].Enabled := True;
    end
    else
    begin
      FPairChannelCombos[I].ItemIndex := 0;
      FPairChannelCombos[I].Enabled := False;
    end;
    UpdatePairLabelColor(I);
  end;
end;

{ Цвет подписи «Пара N» = цвет назначенного канала (тот же, что в таблице
  и на кадре); без канала — серый. }
procedure TElectrodeLayoutForm.UpdatePairLabelColor(APairIndex: Integer);
var
  Ch: Integer;
begin
  Ch := -1;
  if (APairIndex >= 0) and (APairIndex < Length(FLayout.Pairs)) then
    Ch := FLayout.Pairs[APairIndex].ChannelIndex;
  if (Ch >= 0) and (Ch <= 3) then
    FPairLabels[APairIndex].TextSettings.FontColor := EodChannelColors[Ch]
  else
    FPairLabels[APairIndex].TextSettings.FontColor := TAlphaColorRec.Gray;
end;

procedure TElectrodeLayoutForm.UpdateLocalizeButtonState;
begin
  { Кнопка активна без ручного назначения каналов: перебор (ScanChannelAssignment)
    сам добирает каналы свободных пар (нужно для импортированных JSON v1,
    где channelIndex = -1). Ручное назначение используется, если задано. }
  FBtnLocalize.Enabled := (Length(FLayout.Pairs) = EodChannelCount) and
    (FLayout.TankCornersSet = 4) and (Length(FAmplitudes) > 0);
end;

procedure TElectrodeLayoutForm.ClearLocalizationResult;
begin
  SetLength(FLocalizedEvents, 0);
  FLocalizeInfo.Text := '';
end;

procedure TElectrodeLayoutForm.BtnLocalizeClick(Sender: TObject);
begin
  RunLocalization;
end;

{ Очистка картинки от результатов локализации: зелёные маркеры рыбы и
  путь «живого» маркера убираются, разметка (углы/пары) остаётся. }
procedure TElectrodeLayoutForm.BtnClearMarkersClick(Sender: TObject);
begin
  ClearLocalizationResult;
  ClearLiveState;
  UpdateStatus;
  FPaintBox.Repaint;
end;

procedure TElectrodeLayoutForm.RunLocalization;
var
  Pairs, PairsRel: TPairGeometryArray;
  I: Integer;
  Res: TChannelMatchScanResult;
  TankW, TankH: Double;
  ConvCount: Integer;
  InsideTankCount: Integer;
  CheckedEvents: Integer;
  MismatchEvents: Integer;
begin
  { Каждая причина отказа даёт видимую строку — молчаливых Exit не должно
    быть, иначе нет обратной связи. }
  if Length(FLayout.Pairs) <> EodChannelCount then
  begin
    FLocalizeInfo.Text := 'Нужно указать ровно 4 пары электродов.';
    Exit;
  end;
  if Length(FAmplitudes) = 0 then
  begin
    FLocalizeInfo.Text := 'Нет событий записи: откройте и проанализируйте WAV или откройте .eodpk с пиками.';
    Exit;
  end;

  FreeAndNil(FCalib);
  FCalib := BuildCalibrationFromLayout(FLayout);
  if not Assigned(FCalib) then
  begin
    FLocalizeInfo.Text := 'Калибровка не удалась: укажите 4 угла аквариума.';
    Exit;
  end;

  { Локализация работает в САНТИМЕТРАХ: модель поля и MinDist = 0.5 см
    в Electrode.Localization заданы в см, поэтому пары переводятся из
    относительных 0..1 в см, прогон идёт по реальным размерам аквариума,
    а результаты возвращаются обратно в относительные для отрисовки.
    Без размеров локализация невозможна (иначе пришлось бы подставлять
    MinDist в относительных единицах, что ломает поле у стенок). }
  ReadTankSizeFromEdits;
  if not HasKnownTankSize(FLayout) then
  begin
    FLocalizeInfo.Text := 'Укажите размеры аквариума (ширина и высота, см) — локализация считает поле в сантиметрах.';
    Exit;
  end;
  TankW := FLayout.TankWidthCm;
  TankH := FLayout.TankHeightCm;

  { Пары: PairsRel — относительные 0..1 (для диагностики и отрисовки),
    Pairs — те же пары в сантиметрах (для локализации). }
  SetLength(Pairs, EodChannelCount);
  SetLength(PairsRel, EodChannelCount);
  for I := 0 to EodChannelCount - 1 do
  begin
    PairsRel[I].A := FCalib.PixelToWorld(FLayout.Pairs[I].PointA);
    PairsRel[I].B := FCalib.PixelToWorld(FLayout.Pairs[I].PointB);
    PairsRel[I].UserChannel := FLayout.Pairs[I].ChannelIndex;
    Pairs[I].A := RelativeToCm(PairsRel[I].A, FLayout);
    Pairs[I].B := RelativeToCm(PairsRel[I].B, FLayout);
    Pairs[I].UserChannel := FLayout.Pairs[I].ChannelIndex;
  end;

  { Параметры поиска: сетка финального мультистарта 5x5, показатель
    поля 1.5, оценка комбинаций по первым 20 событиям на сетке 3x3. }
  Res := ScanChannelAssignment(FAmplitudes, Pairs, TankW, TankH,
    5, 1.5, 20, 3);

  if not Res.OK then
  begin
    FLocalizeInfo.Text := 'Локализация не удалась: каналы пар дублируются или данные пустые. Проверьте «Канал пары» для каждой пары.';
    Exit;
  end;

  FLocalizedEvents := Res.Events;

  { Результаты локализации получены в см — возвращаем их в относительные
    координаты для отрисовки и диагностики (позиции маркеров на кадре
    тоже строятся через FCalib.WorldToPixel). }
  for I := 0 to High(FLocalizedEvents) do
    if FLocalizedEvents[I].Converged then
      FLocalizedEvents[I].Position :=
        CmToRelative(FLocalizedEvents[I].Position, FLayout);

  ConvCount := 0;
  InsideTankCount := 0;
  for I := 0 to High(FLocalizedEvents) do
  begin
    if FLocalizedEvents[I].Converged then
      Inc(ConvCount);
    if FLocalizedEvents[I].Converged and
       InsideTank(FLocalizedEvents[I].Position) then
      Inc(InsideTankCount);
  end;

  FLocalizeInfo.Text := Format(
    'Найдена конфигурация: %d событий локализовано, из них %d с позицией внутри аквариума.'#10 +
    'Средняя невязка: %.3f. Проверено комбинаций: %d.',
    [ConvCount, InsideTankCount, Res.MeanResidual, Res.SearchCombinations]);

  if (ConvCount > 0) and (InsideTankCount = 0) then
    FLocalizeInfo.Text := FLocalizeInfo.Text + #10 +
      'Нет позиций внутри аквариума: проверьте, что кадр и разметка соответствуют друг другу (JSON от другого кадра?) и что пары указаны верно.';

  { Контроль согласованности: в какой доле событий самый активный канал
    НЕ соответствует электроду, ближайшему к позиции. Систематическое
    несовпадение — признак перепутанных каналов почти-симметричных пар
    (самый частый случай: зелёный ↔ оранжевый). }
  CheckedEvents := 0;
  MismatchEvents := 0;
  for I := 0 to High(FLocalizedEvents) do
    if FLocalizedEvents[I].Converged and
       InsideTank(FLocalizedEvents[I].Position) then
    begin
      Inc(CheckedEvents);
      if NearestPairIndex(FLocalizedEvents[I].Position, PairsRel) <>
         Res.Assignment[MostActiveChannel(FAmplitudes[I])] then
        Inc(MismatchEvents);
    end;

  if (CheckedEvents > 0) and (MismatchEvents > 0) then
    FLocalizeInfo.Text := FLocalizeInfo.Text + #10 + Format(
      'В %d из %d событий самый активный канал не совпадает с ближайшим электродом. ' +
      'Если это систематически, каналы двух почти-симметричных пар перепутаны — ' +
      'поменяйте их в комбобоксах.', [MismatchEvents, CheckedEvents]);

  { Применяем найденную конфигурацию как рабочую: каналы пар и полярность.
    После этого «живой» маркер (курсор/воспроизведение главной формы)
    использует это же решение, а пользователь может уточнять его кнопками
    полярности Ch1..Ch4. }
  for I := 0 to 3 do
    if (Res.Assignment[I] >= 0) and (Res.Assignment[I] < Length(FLayout.Pairs)) then
      FLayout.Pairs[Res.Assignment[I]].ChannelIndex := I;
  FOrientation := Res.Orientation;
  RefreshPolarityButtons;
  FSyncingChannels := True;
  try
    SyncChannelControls;
  finally
    FSyncingChannels := False;
  end;

  SetLength(FLiveTrail, 0);
  LocalizeLive;

  UpdateStatus;
  FPaintBox.Repaint;
end;

procedure TElectrodeLayoutForm.SetAmplitudes(
  const AAmplitudes: TElectrodeEventArray);
begin
  FAmplitudes := AAmplitudes;
  ClearLocalizationResult;
  UpdateLocalizeButtonState;
end;

{ ------------------------------------------------------------------ }
{ «Живой» маркер (курсор / воспроизведение главной формы)             }
{ ------------------------------------------------------------------ }

procedure TElectrodeLayoutForm.RefreshPolarityButtons;
var
  C: Integer;
begin
  for C := 0 to 3 do
    if Assigned(FPolarityButtons[C]) then
      if FOrientation[C] < 0 then
        FPolarityButtons[C].Text := Format('Ch%d: −', [C + 1])
      else
        FPolarityButtons[C].Text := Format('Ch%d: +', [C + 1]);
end;

procedure TElectrodeLayoutForm.PolarityButtonClick(Sender: TObject);
var
  C: Integer;
begin
  C := (Sender as TButton).Tag;
  FOrientation[C] := -FOrientation[C];
  RefreshPolarityButtons;
  { Новая полярность меняет интерпретацию всех позиций — начинаем путь
    заново и перелокализуем последнее событие. }
  SetLength(FLiveTrail, 0);
  LocalizeLive;
end;

procedure TElectrodeLayoutForm.AppendTrail(const P: TPoint2D);
const
  MaxTrail = 4000;
  DropFirst = 500;
begin
  if Length(FLiveTrail) >= MaxTrail then
    FLiveTrail := System.Copy(FLiveTrail, DropFirst,
      Length(FLiveTrail) - DropFirst);
  SetLength(FLiveTrail, Length(FLiveTrail) + 1);
  FLiveTrail[High(FLiveTrail)] := P;
end;

procedure TElectrodeLayoutForm.ClearLiveState;
begin
  FHasLiveEvent := False;
  FHasLivePosition := False;
  SetLength(FLiveTrail, 0);
  if Assigned(FLiveInfo) then
    FLiveInfo.Text := '';
end;

procedure TElectrodeLayoutForm.LocalizeLive;
var
  Pairs, PairsRel: TPairGeometryArray;
  I, O, C: Integer;
  Res, Cand: TLocalizedEvent;
  Signs: TSigns4;
  BestSigns: TSigns4;
  BestPos, ResPosRel: TPoint2D;
  BestFrame: Int64;
  BestRMS: Double;
  TankW, TankH: Double;
  FoundInside: Boolean;
begin
  if not FHasLiveEvent then
    Exit;
  if not Assigned(FLiveInfo) then
    Exit;

  if not Assigned(FCalib) then
    try
      FCalib := BuildCalibrationFromLayout(FLayout);
    except
      FCalib := nil;
    end;
  if not Assigned(FCalib) then
  begin
    FLiveInfo.Text := 'Живой маркер: укажите сначала 4 угла аквариума.';
    FHasLivePosition := False;
    FPaintBox.Repaint;
    Exit;
  end;

  if Length(FLayout.Pairs) <> EodChannelCount then
  begin
    FLiveInfo.Text := 'Живой маркер: укажите все 4 пары электродов ' +
      '(или загрузите их из JSON).';
    FHasLivePosition := False;
    FPaintBox.Repaint;
    Exit;
  end;

  { Локализация работает в сантиметрах (см. RunLocalization) — без
    размеров аквариума живой маркер не строится. }
  ReadTankSizeFromEdits;
  if not HasKnownTankSize(FLayout) then
  begin
    FLiveInfo.Text := 'Живой маркер: укажите размеры аквариума (ширина и высота, см).';
    FHasLivePosition := False;
    FPaintBox.Repaint;
    Exit;
  end;
  TankW := FLayout.TankWidthCm;
  TankH := FLayout.TankHeightCm;

  SetLength(Pairs, EodChannelCount);
  SetLength(PairsRel, EodChannelCount);
  for I := 0 to EodChannelCount - 1 do
  begin
    PairsRel[I].A := FCalib.PixelToWorld(FLayout.Pairs[I].PointA);
    PairsRel[I].B := FCalib.PixelToWorld(FLayout.Pairs[I].PointB);
    PairsRel[I].UserChannel := FLayout.Pairs[I].ChannelIndex;
    Pairs[I].A := RelativeToCm(PairsRel[I].A, FLayout);
    Pairs[I].B := RelativeToCm(PairsRel[I].B, FLayout);
    Pairs[I].UserChannel := FLayout.Pairs[I].ChannelIndex;
  end;

  Res := LocalizeSingleEvent(FLastLiveEvent, Pairs, FOrientation,
    TankW, TankH, 1.5, 5);
  ResPosRel := CmToRelative(Res.Position, FLayout);

  if Res.Converged and InsideTank(ResPosRel) then
  begin
    FHasLivePosition := True;
    FLivePosition := ResPosRel;
    FLiveFrame := Res.Frame;
    AppendTrail(ResPosRel);
    FLiveInfo.Text := Format(
      'Живой маркер: событие #%d, RMS %.3f', [FLiveFrame, Res.ResidualRMS]);
    FLiveInfo.Text := FLiveInfo.Text + #10 +
      DiagnosticText(FLastLiveEvent, ResPosRel, PairsRel);
  end
  else
  begin
    { Текущая конфигурация не дала позицию внутри аквариума. Пробуем все
      16 комбинаций полярности и ищем первую, дающую позицию внутри с
      наименьшей невязкой — это и есть "попытка поменять конфигурацию".
      Полностью менять каналы пар на живом маркере не делаем: для этого
      есть «Локализовать (по пикам)». }
    FoundInside := False;
    Cand := Res;
    BestSigns := FOrientation;
    BestRMS := MaxDouble;
    BestFrame := 0;
    for O := 0 to 15 do
    begin
      for C := 0 to 3 do
        if (O and (1 shl C)) <> 0 then
          Signs[C] := -1
        else
          Signs[C] := 1;

      Cand := LocalizeSingleEvent(FLastLiveEvent, Pairs, Signs,
        TankW, TankH, 1.5, 5);
      if Cand.Converged and
         InsideTank(CmToRelative(Cand.Position, FLayout)) then
        if (not FoundInside) or (Cand.ResidualRMS < BestRMS) then
        begin
          FoundInside := True;
          BestRMS := Cand.ResidualRMS;
          BestSigns := Signs;
          BestPos := CmToRelative(Cand.Position, FLayout);
          BestFrame := Cand.Frame;
        end;
    end;

    if FoundInside then
    begin
      FHasLivePosition := True;
      FLivePosition := BestPos;
      FLiveFrame := BestFrame;
      FLiveInfo.Text := 'Позиция в аквариуме только при полярности ' +
        SignsToString(BestSigns) +
        '. Нажмите эти кнопки полярности, чтобы закрепить (путь перерисуется).';
    end
    else
    begin
      FHasLivePosition := False;
      FLiveInfo.Text := 'Позиция не найдена внутри аквариума. Проверьте: ' +
        'кадр разметки соответствует кадру записи (JSON от другого кадра?), ' +
        'правильно ли указаны пары электродов, и назначьте каналы пар.';
    end;
  end;

  UpdateStatus;
  FPaintBox.Repaint;
end;

procedure TElectrodeLayoutForm.UpdateLiveEvent(
  const AEvent: TElectrodeEventAmplitudes);
begin
  FHasLiveEvent := True;
  FLastLiveEvent := AEvent;
  LocalizeLive;
end;

{ ------------------------------------------------------------------ }
{ Вспомогательное                                                     }
{ ------------------------------------------------------------------ }

procedure TElectrodeLayoutForm.ReadTankSizeFromEdits;
var
  W, H: Double;
begin
  if TryStrToFloat(FEdTankWidth.Text, W) and (W > 0) then
    FLayout.TankWidthCm := W;
  if TryStrToFloat(FEdTankHeight.Text, H) and (H > 0) then
    FLayout.TankHeightCm := H;
end;

procedure TElectrodeLayoutForm.UpdateStatus;
begin
  FStatusLabel.Text := Format(
    'Углы аквариума: %d/4.  Пар электродов указано: %d/%d.  Отметок рыбы: %d.  Истинных позиций: %d.',
    [FCornersPlaced, Length(FLayout.Pairs), EodChannelCount,
     Length(FLayout.FishMarks), Length(FTruthMarks)]);

  case FMode of
    limCorners:
      FInstructionLabel.Text := Format(
        'Кликните угол %d из 4 (по порядку обхода периметра).',
        [FCornersPlaced + 1]);
    limPair:
      if FHavePendingPairPoint then
        FInstructionLabel.Text := 'Кликните второй контакт этой же пары.'
      else
        FInstructionLabel.Text := Format(
          'Кликните первый контакт пары %d (два контакта одного дифференциального входа).',
          [Length(FLayout.Pairs) + 1]);
    limFish:
      if FHavePendingFishHead then
        FInstructionLabel.Text := 'Кликните хвост той же рыбы.'
      else
        FInstructionLabel.Text := 'Кликните голову рыбы.';
    limTruth:
      FInstructionLabel.Text :=
        'Кликните по кадру в том месте, где находится рыба. Метка сохранится с амплитудами текущего события (если курсор/плейхед стоит на пике).';
  else
    FInstructionLabel.Text :=
      'Выберите действие: "Указать углы аквариума", "Добавить пару электродов" или "Отметить рыбу".';
  end;
end;

{ ------------------------------------------------------------------ }

end.
