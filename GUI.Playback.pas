unit GUI.Playback;

interface

uses
  System.SysUtils, System.Diagnostics, System.Classes,
  FMX.Types,
  Core.Types,
  GUI.Model;

type
  { Плеер "проигрывает" запись как последовательность пиков: таймер ведёт
    виртуальное время (сэмплы), а в момент, когда наступает время очередного
    пика, этот пик отображается через колбэк ShowPeak.

    Класс не владеет ни одним контролом TMainForm: текст кнопки Play/Stop,
    ползунок позиции и статусная строка обновляются колбэками, которые
    привязывает форма. TTimer живёт внутри класса (создаётся кодом, без
    зависимости от .fmx). }
  TEodPlayerShowPeak = reference to procedure(Index: Integer);
  TEodPlayerStatus = reference to procedure(const S: string);
  TEodPlayerGetFrame = reference to function: Int64;
  TEodPlayerGetIndex = reference to function: Integer;
  TEodPlayerSetPosition = reference to procedure(P: Double);
  TEodPlayerStateChanged = reference to procedure(Active: Boolean);

  TEodPlayer = class
  private
    FSession: TEodGuiSession;
    FPlayTimer: TTimer;

    FShowPeak: TEodPlayerShowPeak;
    FStatus: TEodPlayerStatus;
    FGetCurrentFrame: TEodPlayerGetFrame;
    FGetCurrentIndex: TEodPlayerGetIndex;
    FSetPosition: TEodPlayerSetPosition;
    FStateChanged: TEodPlayerStateChanged;

    FActive: Boolean;        // идёт воспроизведение
    FIndex: Integer;         // индекс следующего пика к показу
    FStartPos: Int64;        // виртуальное "сейчас" в сэмплах на старте
    FClock: TStopwatch;      // реальное время с момента старта
    FSpeed: Double;          // множитель скорости (сэмплы/сек умножаются)

    procedure SetSpeed(AValue: Double);
    procedure PlayTimerTick(Sender: TObject);
    function VirtualNow: Int64;
  public
    constructor Create(ASession: TEodGuiSession;
      AShowPeak: TEodPlayerShowPeak; AStatus: TEodPlayerStatus;
      AGetCurrentFrame: TEodPlayerGetFrame;
      AGetCurrentIndex: TEodPlayerGetIndex;
      ASetPosition: TEodPlayerSetPosition;
      AStateChanged: TEodPlayerStateChanged);
    destructor Destroy; override;

    procedure Start;
    procedure Stop(Finished: Boolean);
    { Установка скорости из предустановленного набора по индексу
      комбобокса PlaySpeed: 0..6 -> (0.1, 0.25, 0.5, 1, 2, 5, 10)x.
      Неизвестный индекс даёт 1x. Вид индексов живёт здесь, а не на форме. }
    procedure SetSpeedIndex(AIndex: Integer);

    property Session: TEodGuiSession read FSession write FSession;
    property Active: Boolean read FActive;
    property Speed: Double read FSpeed write SetSpeed;
  end;

implementation

constructor TEodPlayer.Create(ASession: TEodGuiSession;
  AShowPeak: TEodPlayerShowPeak; AStatus: TEodPlayerStatus;
  AGetCurrentFrame: TEodPlayerGetFrame;
  AGetCurrentIndex: TEodPlayerGetIndex;
  ASetPosition: TEodPlayerSetPosition;
  AStateChanged: TEodPlayerStateChanged);
begin
  inherited Create;
  FSession := ASession;
  FShowPeak := AShowPeak;
  FStatus := AStatus;
  FGetCurrentFrame := AGetCurrentFrame;
  FGetCurrentIndex := AGetCurrentIndex;
  FSetPosition := ASetPosition;
  FStateChanged := AStateChanged;

  FActive := False;
  FIndex := 0;
  FStartPos := 0;
  FSpeed := 1.0;

  FPlayTimer := TTimer.Create(nil);
  FPlayTimer.Interval := 30;
  FPlayTimer.OnTimer := PlayTimerTick;
  FPlayTimer.Enabled := False;
end;

destructor TEodPlayer.Destroy;
begin
  FPlayTimer.Enabled := False;
  FPlayTimer.Free;
  inherited;
end;

procedure TEodPlayer.SetSpeed(AValue: Double);
var
  ElapsedS: Double;
begin
  if AValue = FSpeed then
    Exit;

  if FActive then
  begin
    { Фиксируем текущую виртуальную позицию и перезапускаем часы,
      чтобы смена скорости не дала скачка вперёд или назад. }
    ElapsedS := FClock.Elapsed.TotalSeconds;
    FStartPos := FStartPos +
      Trunc(ElapsedS * FSession.SampleRate * FSpeed);
    FClock := TStopwatch.StartNew;
  end;

  FSpeed := AValue;
end;

procedure TEodPlayer.SetSpeedIndex(AIndex: Integer);
const
  PresetSpeeds: array[0..6] of Double =
    (0.1, 0.25, 0.5, 1.0, 2.0, 5.0, 10.0);
begin
  if (AIndex >= 0) and (AIndex < Length(PresetSpeeds)) then
    Speed := PresetSpeeds[AIndex]
  else
    Speed := 1.0;
end;

function TEodPlayer.VirtualNow: Int64;
var
  ElapsedS: Double;
begin
  ElapsedS := FClock.Elapsed.TotalSeconds;
  Result := FStartPos +
    Trunc(ElapsedS * FSession.SampleRate * FSpeed);
end;

procedure TEodPlayer.Start;
var
  Total: Integer;
  L, R, Mid: Int64;
  Pos: Int64;
  StartFrame: Int64;
begin
  if FActive then
    Exit;

  if FSession.Mode = dmNone then
    Exit;

  if FSession.SampleRate <= 0 then
    Exit;

  Total := FSession.PeakCount;
  if Total <= 0 then
  begin
    if Assigned(FStatus) then
      FStatus('Nothing to play: no peaks.');
    Exit;
  end;

  { Если стоим на последнем пике (например, после полного прохода) —
    начинаем с начала, иначе это дало бы мгновенный "пустой" плей. }
  if FGetCurrentIndex() >= Total - 1 then
    FIndex := 0
  else if FGetCurrentIndex() >= 0 then
    FIndex := FGetCurrentIndex()
  else
  begin
    { Пик не выбран: берём первый пик от текущего начала отображения. }
    StartFrame := FGetCurrentFrame();

    L := 0;
    R := Total - 1;
    while L < R do
    begin
      Mid := L + (R - L) div 2;
      Pos := FSession.GetPeakPosition(Integer(Mid));
      if Pos < StartFrame then
        L := Mid + 1
      else
        R := Mid;
    end;

    FIndex := Integer(L);

    { Если текущая позиция находится после последнего пика (поиск
      вышел за конец) — начинаем с последнего пика. }
    if FIndex >= Total then
      FIndex := Total - 1;
  end;

  FStartPos := FSession.GetPeakPosition(FIndex);
  FClock := TStopwatch.StartNew;
  FActive := True;

  if Assigned(FStateChanged) then
    FStateChanged(True);

  { Первый пик показываем немедленно, дальше их ведёт таймер. }
  if Assigned(FShowPeak) then
    FShowPeak(FIndex);
  Inc(FIndex);

  FPlayTimer.Enabled := True;

  if Assigned(FStatus) then
    FStatus(Format('Playing: peak %d/%d, speed %gx',
      [FIndex, Total, FSpeed]));
end;

procedure TEodPlayer.Stop(Finished: Boolean);
begin
  if not FActive then
    Exit;

  FPlayTimer.Enabled := False;
  FActive := False;

  if Assigned(FStateChanged) then
    FStateChanged(False);

  if Assigned(FStatus) then
  begin
    if Finished then
      FStatus(Format('Playback finished at peak %d/%d.',
        [FGetCurrentIndex() + 1, FSession.PeakCount]))
    else
      FStatus(Format('Playback stopped at peak %d/%d.',
        [FGetCurrentIndex() + 1, FSession.PeakCount]));
  end;
end;

procedure TEodPlayer.PlayTimerTick(Sender: TObject);
var
  Total: Integer;
  VNow: Int64;
  ShowIdx: Integer;
  P: Double;
begin
  if not FActive then
    Exit;

  Total := FSession.PeakCount;
  if Total <= 0 then
  begin
    Stop(False);
    Exit;
  end;

  { Виртуальное "сейчас" в сэмплах: старт + реальное время * скорость.
    Скорость 1x соответствует реальному темпу записи. }
  VNow := VirtualNow;

  { За один тик может наступить время нескольких пиков — показываем
    последний из них, промежуточные пропускаем. }
  ShowIdx := -1;
  while (FIndex < Total) and
        (FSession.GetPeakPosition(FIndex) <= VNow) do
  begin
    ShowIdx := FIndex;
    Inc(FIndex);
  end;

  if ShowIdx >= 0 then
    if Assigned(FShowPeak) then
      FShowPeak(ShowIdx);

  { Ползунок позиции двигаем молча — сам он перерисовывать ничего не должен. }
  if (FSession.TotalFrames > 0) and Assigned(FSetPosition) then
  begin
    P := VNow / FSession.TotalFrames;
    if P < 0 then
      P := 0
    else if P > 1 then
      P := 1;
    FSetPosition(P);
  end;

  if FIndex >= Total then
    Stop(True);
end;

end.