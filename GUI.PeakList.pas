unit GUI.PeakList;

interface

uses
  System.SysUtils, System.Math,
  FMX.ListBox,
  Core.Types,
  GUI.Model;

type
  { Пагинация списка пиков TListBox в UI главной формы (логика вынесена из
    TMainForm).

      FillFirstPage   — первые MaxListPeaks пиков (сразу после открытия файла);
      FillAroundFrame — окно ±HalfWindow вокруг ближайшего к AFrame пика
                        с подсветкой выбранного (бинарный поиск);
      HandleClick     — переход по пунктам списка, включая ссылки "<<"/">>";
      HandleRightClick— правый клик по реальному пику: кладёт его позицию
                        в поле "конец диапазона" через колбэк SetEndEditText.

    Класс не владеет TListBox (это компонент формы) и не знает остальной
    логики формы: показ пика идёт через колбэк ShowPeak. }
  TEodPeakListShowPeak = reference to procedure(Index: Integer);
  TEodPeakListSetEndText = reference to procedure(const S: string);

  TEodPeakList = class
  private
    FListBox: TListBox;
    FSession: TEodGuiSession;

    FShowPeak: TEodPeakListShowPeak;
    FSetEndEditText: TEodPeakListSetEndText;

    FFirstIndex: Integer;   // индекс первого реального пика в окне
    FRealCount: Integer;    // сколько реальных пиков показано

    procedure PopulatePeakListRange(const Peaks: TPeakArray;
      FirstIndex: Int64; Total: Int64);
  public
    constructor Create(AListBox: TListBox; ASession: TEodGuiSession;
      AShowPeak: TEodPeakListShowPeak;
      ASetEndEditText: TEodPeakListSetEndText);

    procedure Clear;
    procedure FillFirstPage;
    procedure FillAroundFrame(AFrame: Int64);
    procedure HandleClick;
    procedure HandleRightClick;

    property Session: TEodGuiSession read FSession write FSession;
  end;

implementation

constructor TEodPeakList.Create(AListBox: TListBox; ASession: TEodGuiSession;
  AShowPeak: TEodPeakListShowPeak;
  ASetEndEditText: TEodPeakListSetEndText);
begin
  inherited Create;
  FListBox := AListBox;
  FSession := ASession;
  FShowPeak := AShowPeak;
  FSetEndEditText := ASetEndEditText;
  FFirstIndex := 0;
  FRealCount := 0;
end;

procedure TEodPeakList.Clear;
begin
  FFirstIndex := 0;
  FRealCount := 0;
  FListBox.Clear;
end;

procedure TEodPeakList.FillFirstPage;
const
  MaxListPeaks = 1000;
var
  Total: Int64;
  Count: Int64;
  Peaks: TPeakArray;
begin
  Total := FSession.PeakCount;

  if Total <= 0 then
  begin
    Clear;
    Exit;
  end;

  Count := Min(Total, Int64(MaxListPeaks));

  if not FSession.ReadPeakInfoRange(0, Count, Peaks) then
    Exit;

  PopulatePeakListRange(Peaks, 0, Total);
end;

procedure TEodPeakList.PopulatePeakListRange(const Peaks: TPeakArray;
  FirstIndex: Int64; Total: Int64);
var
  I: Integer;
  LastIndex: Int64;
begin
  if Length(Peaks) = 0 then
  begin
    Clear;
    Exit;
  end;

  LastIndex := FirstIndex + Length(Peaks) - 1;

  FFirstIndex := Integer(FirstIndex);
  FRealCount := Length(Peaks);

  FListBox.BeginUpdate;
  try
    FListBox.Clear;

    { Ссылка "<<" в начало, если перед окном есть ещё элементы }
    if FirstIndex > 0 then
      FListBox.Items.Add(Format('<<  (%d more)', [FirstIndex]));

    for I := 0 to High(Peaks) do
      FListBox.Items.Add(Peaks[I].Position.ToString);

    { Ссылка ">>" в конец, если после окна есть ещё элементы }
    if LastIndex < Total - 1 then
      FListBox.Items.Add(Format('>>  (%d more)', [Total - 1 - LastIndex]));
  finally
    FListBox.EndUpdate;
  end;
end;

procedure TEodPeakList.FillAroundFrame(AFrame: Int64);
const
  HalfWindow = 100;
var
  Total: Int64;
  L, R, Mid: Int64;
  Pos: Int64;
  BestIndex: Int64;
  BestDistance: Int64;
  Distance: Int64;

  WindowFirst: Int64;
  WindowCount: Int64;

  Peaks: TPeakArray;

  ListIndex: Integer;
begin
  Total := FSession.PeakCount;

  if Total <= 0 then
  begin
    Clear;
    Exit;
  end;

  { Ищем первый peak с Position >= AFrame.
    Работаем только через TEodGuiSession. }
  L := 0;
  R := Total - 1;

  while L < R do
  begin
    Mid := L + (R - L) div 2;
    Pos := FSession.GetPeakPosition(Integer(Mid));

    if Pos < 0 then
      Exit;

    if Pos < AFrame then
      L := Mid + 1
    else
      R := Mid;
  end;

  BestIndex := L;

  { Проверяем ближайший peak слева. }
  Pos := FSession.GetPeakPosition(Integer(L));

  if Pos < 0 then
    Exit;

  BestDistance := Abs(Pos - AFrame);

  if L > 0 then
  begin
    Pos := FSession.GetPeakPosition(Integer(L - 1));

    if Pos < 0 then
      Exit;

    Distance := Abs(Pos - AFrame);

    if Distance < BestDistance then
      BestIndex := L - 1;
  end;

  { Если найденный peak уже находится в ListBox — просто выделяем его. }
  if (FRealCount > 0) and
     (BestIndex >= FFirstIndex) and
     (BestIndex < FFirstIndex + Int64(FRealCount)) then
  begin
    ListIndex := Integer(BestIndex - FFirstIndex);

    if FFirstIndex > 0 then
      Inc(ListIndex);

    if (ListIndex >= 0) and
       (ListIndex < FListBox.Count) then
      FListBox.ItemIndex := ListIndex;

    Exit;
  end;

  { Загружаем окно вокруг найденного peak. }
  WindowFirst := Max(Int64(0), BestIndex - HalfWindow);

  WindowCount := Min(
    Int64(HalfWindow * 2 + 1),
    Total - WindowFirst);

  if WindowCount <= 0 then
    Exit;

  if not FSession.ReadPeakInfoRange(WindowFirst, WindowCount, Peaks) then
    Exit;

  PopulatePeakListRange(Peaks, WindowFirst, Total);

  { Выделяем найденный peak. }
  if (BestIndex >= WindowFirst) and
     (BestIndex < WindowFirst + Length(Peaks)) then
  begin
    ListIndex := Integer(BestIndex - WindowFirst);

    if WindowFirst > 0 then
      Inc(ListIndex);

    if (ListIndex >= 0) and
       (ListIndex < FListBox.Count) then
      FListBox.ItemIndex := ListIndex;
  end;
end;

procedure TEodPeakList.HandleClick;
var
  PeakIndex: Integer;
  S: string;
begin
  if FListBox.ItemIndex < 0 then
    Exit;
  S := FListBox.Items[FListBox.ItemIndex];

  { Обработка навигационных элементов }
  if S.StartsWith('<<') then
  begin
    { Листаем назад: предыдущее окно, крайний правый реальный элемент }
    PeakIndex := Max(0, FFirstIndex - 1);
    if Assigned(FShowPeak) then
      FShowPeak(PeakIndex);
    Exit;
  end;

  if S.StartsWith('>>') then
  begin
    { Листаем вперёд: следующее окно, крайний левый реальный элемент }
    PeakIndex := Min(FSession.PeakCount - 1, FFirstIndex + FRealCount);
    if Assigned(FShowPeak) then
      FShowPeak(PeakIndex);
    Exit;
  end;

  { Обычный пик }
  PeakIndex := FFirstIndex + FListBox.ItemIndex;
  if FFirstIndex > 0 then
    Dec(PeakIndex); // компенсация элемента "<<"
  if (PeakIndex >= 0) and (PeakIndex < FSession.PeakCount) then
    if Assigned(FShowPeak) then
      FShowPeak(PeakIndex);
end;

procedure TEodPeakList.HandleRightClick;
var
  S: string;
begin
  if FListBox.Selected = nil then
    Exit;

  S := FListBox.Selected.Text;
  if S.StartsWith('<<') or S.StartsWith('>>') then
    Exit;

  { OnChange контрола сам пересчитает диапазон. }
  if Assigned(FSetEndEditText) then
    FSetEndEditText(S);
end;

end.