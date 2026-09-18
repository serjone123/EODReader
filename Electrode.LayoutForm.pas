unit Electrode.LayoutForm;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Math,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.StdCtrls, FMX.Objects, FMX.Edit,
  FMX.Layouts, FMX.Dialogs, FMX.ListBox, FMX.Graphics,
  FMX.Controls.Presentation,
  Electrode.Geometry, Electrode.Layout;

type
  { Режим, определяющий, что означает следующий клик по картинке. }
  TLayoutInputMode = (limNone, limCorners, limPair, limFish);

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

    FEdTankWidth: TEdit;
    FEdTankHeight: TEdit;
    FLabelTankWidth: TLabel;
    FLabelTankHeight: TLabel;

    FPairsListBox: TListBox;

    FLayout: TElectrodeLayoutInput;

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
    procedure BtnSetCornersClick(Sender: TObject);
    procedure BtnAddPairClick(Sender: TObject);
    procedure BtnAddFishClick(Sender: TObject);
    procedure BtnUndoClick(Sender: TObject);
    procedure BtnClearAllClick(Sender: TObject);
    procedure BtnExportJsonClick(Sender: TObject);
    procedure BtnImportJsonClick(Sender: TObject);

    procedure UpdateDisplayTransform;
    function ScreenToImagePixel(SX, SY: Single; out ImgX, ImgY: Single): Boolean;
    procedure UpdateStatus;
    procedure RefreshPairsList;
    procedure HandleImageClick(ImgX, ImgY: Single);
    procedure ReadTankSizeFromEdits;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    property Layout: TElectrodeLayoutInput read FLayout;
  end;

procedure ShowElectrodeLayoutForm;

implementation

{ ------------------------------------------------------------------ }
{ Создание формы и элементов управления (без .fmx - см. заголовок     }
{ модуля и комментарий в памяти проекта про Eod.SettingsForm).        }
{ ------------------------------------------------------------------ }

constructor TElectrodeLayoutForm.Create(AOwner: TComponent);
const
  Margin = 8;
  RowHeight = 28;
  ButtonWidth = 160;
  PanelWidth = 200;
var
  ButtonsPanel: TLayout;
  Y: Single;

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
  Height := 720;
  Position := TFormPosition.ScreenCenter;

  FLayout := CreateEmptyLayout;
  FMode := limNone;
  FCornersPlaced := 0;
  FHavePendingPairPoint := False;
  FHavePendingFishHead := False;
  FLastAction := laNone;
  FBitmap := nil;
  FDisplayScale := 1;
  FDisplayOffsetX := 0;
  FDisplayOffsetY := 0;

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
  Y := Y + 18;

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
  Y := Y + 18;

  FEdTankHeight := TEdit.Create(Self);
  FEdTankHeight.Parent := ButtonsPanel;
  FEdTankHeight.Position.X := 0;
  FEdTankHeight.Position.Y := Y;
  FEdTankHeight.Width := ButtonWidth;
  FEdTankHeight.Height := RowHeight - 4;
  FEdTankHeight.Text := '';
  Y := Y + RowHeight + 8;

  FBtnSetCorners := AddButton('Указать углы аквариума', BtnSetCornersClick);
  FBtnAddPair := AddButton('Добавить пару электродов', BtnAddPairClick);
  FBtnAddFish := AddButton('Отметить рыбу (голова+хвост)', BtnAddFishClick);
  FBtnUndo := AddButton('Отменить последнюю точку', BtnUndoClick);
  FBtnClearAll := AddButton('Очистить всё', BtnClearAllClick);

  Y := Y + 8;
  FBtnExportJson := AddButton('Экспорт в JSON...', BtnExportJsonClick);
  FBtnImportJson := AddButton('Импорт из JSON...', BtnImportJsonClick);

  Y := Y + 8;
  FPairsListBox := TListBox.Create(Self);
  FPairsListBox.Parent := ButtonsPanel;
  FPairsListBox.Position.X := 0;
  FPairsListBox.Position.Y := Y;
  FPairsListBox.Width := ButtonWidth;
  FPairsListBox.Height := 200;

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
end;

destructor TElectrodeLayoutForm.Destroy;
begin
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
const
  PairColors: array [0 .. 3] of TAlphaColor = (
    TAlphaColorRec.Red, TAlphaColorRec.Lime, TAlphaColorRec.Blue,
    TAlphaColorRec.Orange);
var
  DestRect: TRectF;
  I: Integer;
  P1, P2: TPointF;

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

  { Уже сохранённые пары электродов. }
  for I := 0 to High(FLayout.Pairs) do
  begin
    P1 := ToScreen(FLayout.Pairs[I].PointA);
    P2 := ToScreen(FLayout.Pairs[I].PointB);

    Canvas.Stroke.Color := PairColors[I mod Length(PairColors)];
    Canvas.Stroke.Thickness := 1.5;
    Canvas.DrawLine(P1, P2, 1);

    DrawMarker(P1, PairColors[I mod Length(PairColors)],
      Format('Пара %d', [I + 1]));
    DrawMarker(P2, PairColors[I mod Length(PairColors)], '');
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
  N: Integer;
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

          N := Length(FLayout.Pairs);
          SetLength(FLayout.Pairs, N + 1);
          FLayout.Pairs[N] := NewPair;

          FHavePendingPairPoint := False;
          FMode := limNone;
          FLastAction := laPair;
          RefreshPairsList;
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
  else
    ; // limNone - ничего не делаем
  end;

  UpdateStatus;
  FPaintBox.Repaint;
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

    FreeAndNil(FBitmap);
    FBitmap := TBitmap.Create;
    FBitmap.LoadFromFile(D.FileName);

    FLayout.SourceImageFile := ExtractFileName(D.FileName);
    FLayout.ImageWidth := Round(FBitmap.Width);
    FLayout.ImageHeight := Round(FBitmap.Height);

    UpdateDisplayTransform;
    UpdateStatus;
    FPaintBox.Repaint;
  finally
    D.Free;
  end;
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
        end;
      laPair:
        if Length(FLayout.Pairs) > 0 then
        begin
          SetLength(FLayout.Pairs, Length(FLayout.Pairs) - 1);
          RefreshPairsList;
          FLastAction := laNone;
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
  if MessageDlg('Удалить всю текущую разметку (углы, все пары электродов и отметки рыбы)?',
    TMsgDlgType.mtConfirmation, [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo], 0) <> mrYes then
    Exit;

  ReadTankSizeFromEdits;
  FLayout.TankCornersSet := 0;
  FCornersPlaced := 0;
  SetLength(FLayout.Pairs, 0);
  SetLength(FLayout.FishMarks, 0);
  FMode := limNone;
  FHavePendingPairPoint := False;
  FHavePendingFishHead := False;
  FLastAction := laNone;

  RefreshPairsList;
  UpdateStatus;
  FPaintBox.Repaint;
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

    { Картинку из JSON мы не загружаем автоматически (в файле хранится
      только имя, не сами байты) - если координаты относятся не к тому
      кадру, что сейчас на экране, они всё равно будут в пиксельных
      координатах правильного (исходного для этой разметки) кадра, и
      отображение на ДРУГОЙ картинке будет искажено. Предупреждаем. }
    if Assigned(FBitmap) and (FLayout.SourceImageFile <> '') and
       (ExtractFileName(FLayout.SourceImageFile) <> '') then
      ShowMessage('Загружена разметка для кадра "' + FLayout.SourceImageFile +
        '". Если сейчас открыт другой кадр, загрузите правильный ' +
        'через "Загрузить кадр...", иначе точки будут показаны неверно.');

    RefreshPairsList;
    UpdateStatus;
    FPaintBox.Repaint;
  finally
    D.Free;
  end;
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

procedure TElectrodeLayoutForm.RefreshPairsList;
var
  I: Integer;
  S: string;
begin
  FPairsListBox.Items.Clear;
  for I := 0 to High(FLayout.Pairs) do
  begin
    S := Format('Пара %d', [I + 1]);
    if FLayout.Pairs[I].Label_ <> '' then
      S := S + ': ' + FLayout.Pairs[I].Label_;
    FPairsListBox.Items.Add(S);
  end;
end;

procedure TElectrodeLayoutForm.UpdateStatus;
begin
  FStatusLabel.Text := Format(
    'Углы аквариума: %d/4.  Пар электродов указано: %d/%d.  Отметок рыбы: %d.',
    [FCornersPlaced, Length(FLayout.Pairs), EodChannelCount, Length(FLayout.FishMarks)]);

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
  else
    FInstructionLabel.Text :=
      'Выберите действие: "Указать углы аквариума", "Добавить пару электродов" или "Отметить рыбу".';
  end;
end;

{ ------------------------------------------------------------------ }

procedure ShowElectrodeLayoutForm;
var
  F: TElectrodeLayoutForm;
begin
  F := TElectrodeLayoutForm.Create(nil);
  try
    F.ShowModal;
  finally
    F.Free;
  end;
end;

end.
