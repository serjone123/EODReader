unit Electrode.Localization;

{$IFDEF FPC}
  {$MODE DELPHI}
  {$H+}
{$ENDIF}

interface

uses
{$IFDEF FPC}
  SysUtils, Math,
{$ELSE}
  System.SysUtils, System.Math,
{$ENDIF}
  Electrode.Geometry;

type
  { Один дифференциальный вход усилителя: пара электродов (+ и -) с
    известными реальными координатами в аквариуме (см, в той же системе
    координат, что и TAquariumCalibration.PixelToWorld). }
  TElectrodePair = record
    Plus, Minus: TPoint2D;
  end;

  { Ровно 4 канала - под текущую аппаратную конфигурацию (Ch1..Ch4). }
  TElectrodeLayout = array [0 .. 3] of TElectrodePair;

  { Результат локализации одного EOD-события. }
  TLocalizationResult = record
    Position: TPoint2D; // найденная позиция источника (см)
    Amplitude: Double; // амплитуда источника (условные единицы модели)
    ResidualRMS: Double; // RMS невязки по 4 каналам - индикатор качества фита:
                          // большая невязка обычно значит "модель поля/
                          // геометрия электродов не соответствуют данным"
    Converged: Boolean;
  end;

  { Локализует положение точечного источника (рыбы) в аквариуме по
    амплитудам на 4 дифференциальных каналах.

    МОДЕЛЬ ПОЛЯ: потенциал точечного источника в проводящей среде
    убывает с расстоянием как V(p) = A / dist(p, e)^ExponentN.
    Дифференциальный канал измеряет разность потенциалов на своих двух
    электродах (земля в разностной формуле сокращается и на результат
    не влияет):
      Ch_i = A * (1/dist(p,e_i+)^n - 1/dist(p,e_i-)^n)

    ExponentN=1 соответствует идеальному точечному источнику в
    безграничной однородной среде. Из-за отражений от стенок и дна
    реального аквариума эффективный показатель обычно лежит между 1 и 2 -
    его стоит подобрать эмпирически (например, по показаниям на известных
    позициях стимул-электрода, если он есть в записи), а не считать
    физической константой.

    ВАЖНО: это МОНОПОЛЬНАЯ модель ближнего поля, не учитывающая реальную
    геометрию тела рыбы, ориентацию диполя EOD-разряда и отражения от
    границ аквариума. На реальных данных стоит ожидать точность порядка
    "в каком углу/области аквариума", а не миллиметровую - это нормально
    для первой рабочей версии; вопрос данного этапа тестирования - вообще
    ли метод даёт разумный, устойчивый результат, а не точную цифру. }
  TSourceLocalizer = class
  private
    FElectrodes: TElectrodeLayout;
    FExponentN: Double;
  public
    constructor Create(const AElectrodes: TElectrodeLayout;
      AExponentN: Double = 1.5);

    { Локализует одно событие по его 4 амплитудам (в том же порядке,
      что и FElectrodes: Amplitudes[0] соответствует Electrodes[0] и
      т.д.). InitialGuess - начальное приближение для итерационного
      метода (например, центр аквариума, если ничего лучше нет).

      ВНИМАНИЕ: при полностью симметричной раскладке электродов
      геометрический центр аквариума может оказаться вырожденной точкой
      (Якобиан там нулевой по построению - см. LocalizeMultiStart) -
      используйте LocalizeMultiStart, если не уверены в качестве
      начального приближения. }
    function Localize(const Amplitudes: array of Double;
      const InitialGuess: TPoint2D): TLocalizationResult;

    { Более надёжная версия: пробует несколько стартовых точек на сетке
      TankWidth x TankHeight (например, 5x5) и возвращает результат с
      наименьшей невязкой. Устраняет проблему вырожденного старта в
      симметричных или частично симметричных раскладках электродов -
      единственная стартовая точка (даже "разумная", вроде центра
      аквариума) иногда может случайно совпасть с точкой, где Якобиан
      модели вырожден, и метод Левенберга-Марквардта не сможет сдвинуться
      с места (это не баг оптимизатора - в такой точке действительно нет
      локальной информации о направлении убывания невязки). }
    function LocalizeMultiStart(const Amplitudes: array of Double;
      TankWidth, TankHeight: Double; GridSize: Integer = 5): TLocalizationResult;

    property ExponentN: Double read FExponentN write FExponentN;
    property Electrodes: TElectrodeLayout read FElectrodes write FElectrodes;
  end;

implementation

function Dist(const A, B: TPoint2D): Double;
begin
  Result := Sqrt(Sqr(A.X - B.X) + Sqr(A.Y - B.Y));
end;

{ Вклад одного электрода в потенциал в точке P. MinDist защищает от
  деления на (около)ноль, если источник оказался вплотную к электроду -
  такое возможно только у самой стенки аквариума. }
function FieldContribution(const P, Electrode: TPoint2D;
  ExponentN: Double): Double;
const
  MinDist = 0.5; // см
var
  D: Double;
begin
  D := Dist(P, Electrode);
  if D < MinDist then
    D := MinDist;
  Result := 1.0 / Power(D, ExponentN);
end;

function PredictChannel(const P: TPoint2D; A: Double;
  const Pair: TElectrodePair; ExponentN: Double): Double;
begin
  Result := A * (FieldContribution(P, Pair.Plus, ExponentN) -
    FieldContribution(P, Pair.Minus, ExponentN));
end;

{ Решение системы 3x3 методом Крамера - для такой маленькой и локальной
  задачи (внутри одной итерации ЛМ) это проще и ничем не хуже общего
  Гаусса из Eod.Geometry (который к тому же не экспортирован оттуда). }
function Det3(A11, A12, A13, A21, A22, A23, A31, A32, A33: Double): Double;
begin
  Result := A11 * (A22 * A33 - A23 * A32) - A12 * (A21 * A33 - A23 * A31) +
    A13 * (A21 * A32 - A22 * A31);
end;

type
  TVec3 = array [0 .. 2] of Double;
  TMat3 = array [0 .. 2, 0 .. 2] of Double;

function Solve3x3(const M: TMat3; const B: TVec3; out X: TVec3): Boolean;
var
  DetM: Double;
begin
  DetM := Det3(M[0, 0], M[0, 1], M[0, 2], M[1, 0], M[1, 1], M[1, 2],
    M[2, 0], M[2, 1], M[2, 2]);
  if Abs(DetM) < 1E-14 then
  begin
    Result := False;
    Exit;
  end;

  X[0] := Det3(B[0], M[0, 1], M[0, 2], B[1], M[1, 1], M[1, 2], B[2],
    M[2, 1], M[2, 2]) / DetM;
  X[1] := Det3(M[0, 0], B[0], M[0, 2], M[1, 0], B[1], M[1, 2], M[2, 0],
    B[2], M[2, 2]) / DetM;
  X[2] := Det3(M[0, 0], M[0, 1], B[0], M[1, 0], M[1, 1], B[1], M[2, 0],
    M[2, 1], B[2]) / DetM;
  Result := True;
end;

constructor TSourceLocalizer.Create(const AElectrodes: TElectrodeLayout;
  AExponentN: Double);
begin
  inherited Create;
  FElectrodes := AElectrodes;
  FExponentN := AExponentN;
end;

function TSourceLocalizer.Localize(const Amplitudes: array of Double;
  const InitialGuess: TPoint2D): TLocalizationResult;
const
  MaxIterations = 100;
  DiffEpsilon = 1E-4;
  InitialLambda = 1E-2;
var
  P, Trial, PPlus, PMinus: array [0 .. 2] of Double; // x, y, A
  R, RPlus, RMinus, RTrial: array [0 .. 3] of Double;
  Jac: array [0 .. 3, 0 .. 2] of Double;
  JtJ: TMat3;
  JtR, Delta: TVec3;
  Cost, TrialCost, Lambda: Double;
  Iter, Ch, ParamIdx, ParamIdx2, K: Integer;

  procedure ComputeResiduals(const Params: array of Double;
    var Res: array of Double);
  var
    Pt: TPoint2D;
    A: Double;
    C: Integer;
  begin
    Pt.X := Params[0];
    Pt.Y := Params[1];
    A := Params[2];
    for C := 0 to 3 do
      Res[C] := PredictChannel(Pt, A, FElectrodes[C], FExponentN) -
        Amplitudes[C];
  end;

  function SumSq(const V: array of Double): Double;
  var
    I: Integer;
  begin
    Result := 0;
    for I := 0 to High(V) do
      Result := Result + Sqr(V[I]);
  end;

begin
  P[0] := InitialGuess.X;
  P[1] := InitialGuess.Y;

  { Начальная оценка амплитуды - грубо, по максимальной по модулю
    амплитуде среди каналов (с запасом x2, чтобы не начинать заведомо
    заниженной оценкой). }
  P[2] := 0;
  for Ch := 0 to 3 do
    if Abs(Amplitudes[Ch]) > Abs(P[2]) then
      P[2] := Amplitudes[Ch] * 2;
  if P[2] = 0 then
    P[2] := 1;

  ComputeResiduals(P, R);
  Cost := SumSq(R);
  Lambda := InitialLambda;
  Result.Converged := False;

  {$IFDEF EODLOC_DEBUG}
  Writeln(Format('  [DBG] Старт: P=(%.3f,%.3f,%.3f) Cost=%.8f R=[%.5f %.5f %.5f %.5f]',
    [P[0], P[1], P[2], Cost, R[0], R[1], R[2], R[3]]));
  {$ENDIF}

  for Iter := 1 to MaxIterations do
  begin
    for ParamIdx := 0 to 2 do
    begin
      PPlus := P;
      PPlus[ParamIdx] := PPlus[ParamIdx] + DiffEpsilon;
      PMinus := P;
      PMinus[ParamIdx] := PMinus[ParamIdx] - DiffEpsilon;
      ComputeResiduals(PPlus, RPlus);
      ComputeResiduals(PMinus, RMinus);
      {$IFDEF EODLOC_DEBUG}
      if Iter = 1 then
        Writeln(Format('    [DBG-J] p=%d PPlus=(%.6f,%.6f,%.6f) PMinus=(%.6f,%.6f,%.6f) RPlus=[%.6f %.6f %.6f %.6f] RMinus=[%.6f %.6f %.6f %.6f]',
          [ParamIdx, PPlus[0],PPlus[1],PPlus[2], PMinus[0],PMinus[1],PMinus[2],
           RPlus[0],RPlus[1],RPlus[2],RPlus[3], RMinus[0],RMinus[1],RMinus[2],RMinus[3]]));
      {$ENDIF}
      for Ch := 0 to 3 do
        Jac[Ch, ParamIdx] := (RPlus[Ch] - RMinus[Ch]) / (2 * DiffEpsilon);
    end;

    for ParamIdx := 0 to 2 do
    begin
      JtR[ParamIdx] := 0;
      for K := 0 to 3 do
        JtR[ParamIdx] := JtR[ParamIdx] + Jac[K, ParamIdx] * R[K];
      JtR[ParamIdx] := -JtR[ParamIdx];

      for ParamIdx2 := 0 to 2 do
      begin
        JtJ[ParamIdx, ParamIdx2] := 0;
        for K := 0 to 3 do
          JtJ[ParamIdx, ParamIdx2] := JtJ[ParamIdx, ParamIdx2] +
            Jac[K, ParamIdx] * Jac[K, ParamIdx2];
      end;
    end;

    for ParamIdx := 0 to 2 do
      JtJ[ParamIdx, ParamIdx] := JtJ[ParamIdx, ParamIdx] * (1 + Lambda);

    if not Solve3x3(JtJ, JtR, Delta) then
    begin
      {$IFDEF EODLOC_DEBUG}
      Writeln(Format('  [DBG] Iter %d: Solve3x3 FAILED. JtJ=[%.6f %.6f %.6f / %.6f %.6f %.6f / %.6f %.6f %.6f] JtR=[%.6f %.6f %.6f]',
        [Iter, JtJ[0,0],JtJ[0,1],JtJ[0,2], JtJ[1,0],JtJ[1,1],JtJ[1,2], JtJ[2,0],JtJ[2,1],JtJ[2,2], JtR[0],JtR[1],JtR[2]]));
      {$ENDIF}
      Break;
    end;

    for ParamIdx := 0 to 2 do
      Trial[ParamIdx] := P[ParamIdx] + Delta[ParamIdx];

    ComputeResiduals(Trial, RTrial);
    TrialCost := SumSq(RTrial);

    if TrialCost < Cost then
    begin
      P := Trial;
      {$IFDEF EODLOC_DEBUG}
      Writeln(Format('  [DBG] Iter %d ACCEPT: P=(%.3f,%.3f,%.3f) Cost=%.8f->%.8f Lambda=%.6f',
        [Iter, P[0], P[1], P[2], Cost, TrialCost, Lambda]));
      {$ENDIF}
      if (Cost - TrialCost) < 1E-12 * (Cost + 1E-12) then
      begin
        Cost := TrialCost;
        Result.Converged := True;
        Break;
      end;
      Cost := TrialCost;
      Lambda := Lambda * 0.5;
    end
    else
    begin
      Lambda := Lambda * 2;
      {$IFDEF EODLOC_DEBUG}
      Writeln(Format('  [DBG] Iter %d REJECT: TrialCost=%.8f > Cost=%.8f, Lambda->%.6f',
        [Iter, TrialCost, Cost, Lambda]));
      {$ENDIF}
      if Lambda > 1E8 then
        Break;
    end;
  end;

  Result.Position.X := P[0];
  Result.Position.Y := P[1];
  Result.Amplitude := P[2];
  Result.ResidualRMS := Sqrt(Cost / 4);
end;

function TSourceLocalizer.LocalizeMultiStart(const Amplitudes: array of Double;
  TankWidth, TankHeight: Double; GridSize: Integer): TLocalizationResult;
var
  GX, GY: Integer;
  Guess: TPoint2D;
  Candidate: TLocalizationResult;
  BestResidual: Double;
  HaveResult: Boolean;
begin
  HaveResult := False;
  BestResidual := MaxDouble;

  if GridSize < 1 then
    GridSize := 1;

  for GY := 0 to GridSize - 1 do
    for GX := 0 to GridSize - 1 do
    begin
      { Сетка стартовых точек, слегка смещённая от точных долей ширины/
        высоты (0.5/GridSize и т.п.), чтобы почти наверняка не попасть
        ровно на ось симметрии электродов, даже если раскладка
        симметрична (см. комментарий у Localize). }
      Guess.X := TankWidth * (GX + 0.5) / GridSize;
      Guess.Y := TankHeight * (GY + 0.5) / GridSize;

      Candidate := Localize(Amplitudes, Guess);

      if (not HaveResult) or (Candidate.ResidualRMS < BestResidual) then
      begin
        Result := Candidate;
        BestResidual := Candidate.ResidualRMS;
        HaveResult := True;
      end;
    end;
end;

end.
