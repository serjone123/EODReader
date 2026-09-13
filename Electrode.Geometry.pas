unit Electrode.Geometry;

{$IFDEF FPC}
  {$MODE DELPHI}
  {$H+}
{$ENDIF}

interface

uses
{$IFDEF FPC}
  SysUtils, Math;
{$ELSE}
  System.SysUtils, System.Math;
{$ENDIF}

type
  { Точка в двумерном пространстве. Используется и для пиксельных координат
    кадра, и для реальных координат аквариума (в сантиметрах) — смысл
    определяется контекстом использования, тип один и тот же. }
  TPoint2D = record
    X, Y: Double;
    constructor Create(AX, AY: Double);
  end;

  TPoint2DArray = array of TPoint2D;

  { Группа точек, которые в реальности лежат на одной прямой линии
    (например, несколько точек вдоль стенки аквариума на кадре).
    Используется только для калибровки дисторсии объектива — сама прямая
    не обязана быть горизонтальной/вертикальной. }
  TCollinearGroup = TPoint2DArray;
  TCollinearGroups = array of TCollinearGroup;

  TMatrix3x3 = array [0 .. 2, 0 .. 2] of Double;

  { Модель радиальной дисторсии объектива (без тангенциальной составляющей —
    для широкоугольных экшн-камер радиальная обычно доминирует).

    Прямая формула (снятие дисторсии, "исходный кадр -> идеальный пинхол"):
      r_ideal = r_distorted * (1 + K1*r_distorted^2 + K2*r_distorted^4)

    Координаты нормализуются на NormRadius (примерно половина диагонали
    кадра), чтобы K1/K2 не зависели от конкретного разрешения видео. }
  TDistortionModel = record
    Cx, Cy: Double; // центр дисторсии, пиксели исходного кадра
    K1, K2: Double; // коэффициенты радиальной дисторсии
    NormRadius: Double; // масштаб нормализации, пиксели

    { Пиксель исходного (искажённого) кадра -> положение на "идеальном"
      неискажённом кадре. }
    function Undistort(const P: TPoint2D): TPoint2D;

    { Обратное преобразование: неискажённая точка -> пиксель исходного
      кадра. Точного аналитического решения нет, ищется итерациями
      Ньютона по модулю радиуса (сходится за несколько шагов). }
    function Distort(const P: TPoint2D): TPoint2D;
  end;

  { Проективное преобразование (гомография) 3x3. В этом модуле применяется
    к уже неискажённым (после TDistortionModel.Undistort) пиксельным
    координатам и переводит их в реальные координаты аквариума (см),
    либо выполняет обратное преобразование. }
  THomography = record
    H: TMatrix3x3;
    function Apply(const P: TPoint2D): TPoint2D;
    function ApplyInverse(const P: TPoint2D): TPoint2D;
    class function Identity: THomography; static;
  end;

  { Модель гомографии, используемая при калибровке.

    ВАЖНО (см. подробный комментарий у RefineHomographyLM в разделе
    implementation и результаты тестов в TestGeometrySynthetic.pas):
    полная проективная гомография (8 параметров) при типичной точности
    ручного клика мышью (1-5 px) даёт ошибку локализации порядка
    10-20 см на аквариуме метрового масштаба — не из-за бага, а потому
    что параметры h31/h32 (отвечающие именно за перспективу/"наклон")
    сами по себе очень малы и предельно чувствительны к шуму входных
    точек. Это фундаментальное свойство проективной геометрии, а не
    особенность этой конкретной реализации.

    Аффинная модель (6 параметров, без перспективы) физически означает
    "камера смотрит строго сверху, без наклона" — при этом допущении
    ошибка на тех же данных падает примерно в 5-6 раз (единицы см
    вместо десятков). Для большинства реальных установок с камерой,
    закреплённой сверху под небольшим углом, аффинная модель на
    практике ТОЧНЕЕ формально более полной проективной — именно потому
    что она не пытается оценивать плохо обусловленные параметры,
    точности которых клик мышью всё равно дать не может.

    hmAffine (по умолчанию) — рекомендуется в подавляющем большинстве
    случаев. hmProjective имеет смысл, только если есть достаточно
    (десятки) хорошо распределённых по всей площади, а не только по
    контуру, калибровочных точек с точностью существенно лучше 1 px
    (например, получены программным детектором, а не ручным кликом). }
  THomographyModel = (hmAffine, hmProjective);

  { Полная калибровка кадра: пиксель исходного (искажённого) видео/фото
    <-> реальные координаты в аквариуме (см).

    Порядок использования:
      1. CalibrateDistortion  — по группам точек, которые физически лежат
         на одной прямой (например, вдоль стенок аквариума), подбирает
         коэффициенты дисторсии.
      2. CalibrateHomography  — по набору пар "реальные координаты (см) —
         пиксель на исходном кадре" строит гомографию.
      3. PixelToWorld / WorldToPixel — рабочие функции преобразования. }
  TAquariumCalibration = class
  private
    FDistortion: TDistortionModel;
    FHomography: THomography;
    FCalibrated: Boolean;
  public
    constructor Create;

    procedure CalibrateDistortion(const Groups: TCollinearGroups;
      ImageWidth, ImageHeight: Integer);

    procedure CalibrateHomography(const WorldPts,
      DistortedPixelPts: array of TPoint2D;
      Model: THomographyModel = hmAffine);

    function PixelToWorld(const APixel: TPoint2D): TPoint2D;
    function WorldToPixel(const AWorld: TPoint2D): TPoint2D;

    { RMS-ошибка (в см) гомографии на переданном наборе точек. Удобно
      показать пользователю сразу после калибровки как оценку качества. }
    function HomographyResidualRMS(const WorldPts,
      DistortedPixelPts: array of TPoint2D): Double;

    property Distortion: TDistortionModel read FDistortion write FDistortion;
    property Homography: THomography read FHomography write FHomography;
    property Calibrated: Boolean read FCalibrated;
  end;

implementation

{ ------------------------------------------------------------------ }
{ Вспомогательная линейная алгебра (без внешних библиотек)           }
{ ------------------------------------------------------------------ }

type
  TDoubleVector = array of Double;
  TDoubleMatrix = array of TDoubleVector;

{ Решает систему линейных уравнений A*X = B методом Гаусса с выбором
  ведущего элемента по столбцу. A и B изменяются в процессе (рабочие
  копии должен передавать вызывающий код, если исходные данные нужны
  после вызова). }
function SolveLinearSystem(A: TDoubleMatrix; B: TDoubleVector;
  out X: TDoubleVector): Boolean;
var
  N, I, J, K, PivotRow: Integer;
  MaxVal, Factor, Temp: Double;
  RowTmp: TDoubleVector;
begin
  N := Length(B);
  SetLength(X, N);

  for K := 0 to N - 2 do
  begin
    PivotRow := K;
    MaxVal := Abs(A[K, K]);
    for I := K + 1 to N - 1 do
      if Abs(A[I, K]) > MaxVal then
      begin
        MaxVal := Abs(A[I, K]);
        PivotRow := I;
      end;

    if MaxVal < 1E-12 then
    begin
      Result := False;
      Exit;
    end;

    if PivotRow <> K then
    begin
      RowTmp := A[K];
      A[K] := A[PivotRow];
      A[PivotRow] := RowTmp;
      Temp := B[K];
      B[K] := B[PivotRow];
      B[PivotRow] := Temp;
    end;

    for I := K + 1 to N - 1 do
    begin
      Factor := A[I, K] / A[K, K];
      for J := K to N - 1 do
        A[I, J] := A[I, J] - Factor * A[K, J];
      B[I] := B[I] - Factor * B[K];
    end;
  end;

  if Abs(A[N - 1, N - 1]) < 1E-12 then
  begin
    Result := False;
    Exit;
  end;

  for K := N - 1 downto 0 do
  begin
    Temp := B[K];
    for J := K + 1 to N - 1 do
      Temp := Temp - A[K, J] * X[J];
    X[K] := Temp / A[K, K];
  end;

  Result := True;
end;

{ Добавляет в нормальные уравнения (A^T*A, A^T*b) вклад одной строки
  исходной системы: A += Row^T*Row, B += Row^T*Rhs.
  Row должен содержать ровно Length(B) элементов. }
procedure AddNormalEquationRow(var A: TDoubleMatrix; var Bv: TDoubleVector;
  const Row: array of Double; Rhs: Double);
var
  I, J, N: Integer;
begin
  N := Length(Bv);
  for I := 0 to N - 1 do
  begin
    Bv[I] := Bv[I] + Row[I] * Rhs;
    for J := 0 to N - 1 do
      A[I, J] := A[I, J] + Row[I] * Row[J];
  end;
end;

function Mat3Mul(const A, B: TMatrix3x3): TMatrix3x3;
var
  I, J, K: Integer;
begin
  for I := 0 to 2 do
    for J := 0 to 2 do
    begin
      Result[I, J] := 0;
      for K := 0 to 2 do
        Result[I, J] := Result[I, J] + A[I, K] * B[K, J];
    end;
end;

{ Строит изотропное нормализующее преобразование Хартли для набора точек:
  после переноса центроида в начало координат и масштабирования среднее
  расстояние точки до начала координат становится равным Sqrt(2).

  Это устраняет катастрофическую плохую обусловленность прямого DLT:
  без нормализации в одной системе уравнений соседствуют слагаемые
  порядка "1" (свободный член гомографии) и порядка "координата в
  пикселях * координата в сантиметрах" (может быть 10^4-10^6), и после
  построения нормальных уравнений (A^T*A) разброс масштабов возводится
  в квадрат — result становится крайне чувствителен к шуму входных точек
  (что и наблюдается на практике: клик мышью с ошибкой в 1-2 пикселя без
  нормализации давал ошибку локализации в десятки-сотни сантиметров). }
function BuildNormalization(const Pts: array of TPoint2D): TMatrix3x3;
var
  N, I: Integer;
  Mx, My, AvgDist, Scale: Double;
begin
  N := Length(Pts);
  Mx := 0;
  My := 0;
  for I := 0 to N - 1 do
  begin
    Mx := Mx + Pts[I].X;
    My := My + Pts[I].Y;
  end;
  Mx := Mx / N;
  My := My / N;

  AvgDist := 0;
  for I := 0 to N - 1 do
    AvgDist := AvgDist + Sqrt(Sqr(Pts[I].X - Mx) + Sqr(Pts[I].Y - My));
  AvgDist := AvgDist / N;

  if AvgDist < 1E-12 then
    Scale := 1
  else
    Scale := Sqrt(2) / AvgDist;

  Result[0, 0] := Scale; Result[0, 1] := 0;     Result[0, 2] := -Scale * Mx;
  Result[1, 0] := 0;     Result[1, 1] := Scale; Result[1, 2] := -Scale * My;
  Result[2, 0] := 0;     Result[2, 1] := 0;     Result[2, 2] := 1;
end;

function ApplyMat3(const M: TMatrix3x3; const P: TPoint2D): TPoint2D;
begin
  Result.X := M[0, 0] * P.X + M[0, 1] * P.Y + M[0, 2];
  Result.Y := M[1, 0] * P.X + M[1, 1] * P.Y + M[1, 2];
  { W всегда равен 1 для преобразований переноса+масштаба, поэтому
    деление на W не требуется. }
end;

function Invert3x3(const M: TMatrix3x3): TMatrix3x3;
var
  Det: Double;
begin
  Det := M[0, 0] * (M[1, 1] * M[2, 2] - M[1, 2] * M[2, 1]) -
         M[0, 1] * (M[1, 0] * M[2, 2] - M[1, 2] * M[2, 0]) +
         M[0, 2] * (M[1, 0] * M[2, 1] - M[1, 1] * M[2, 0]);

  if Abs(Det) < 1E-15 then
    raise Exception.Create('Гомография вырождена, обратной матрицы не существует');

  Result[0, 0] := (M[1, 1] * M[2, 2] - M[1, 2] * M[2, 1]) / Det;
  Result[0, 1] := -(M[0, 1] * M[2, 2] - M[0, 2] * M[2, 1]) / Det;
  Result[0, 2] := (M[0, 1] * M[1, 2] - M[0, 2] * M[1, 1]) / Det;
  Result[1, 0] := -(M[1, 0] * M[2, 2] - M[1, 2] * M[2, 0]) / Det;
  Result[1, 1] := (M[0, 0] * M[2, 2] - M[0, 2] * M[2, 0]) / Det;
  Result[1, 2] := -(M[0, 0] * M[1, 2] - M[0, 2] * M[1, 0]) / Det;
  Result[2, 0] := (M[1, 0] * M[2, 1] - M[1, 1] * M[2, 0]) / Det;
  Result[2, 1] := -(M[0, 0] * M[2, 1] - M[0, 1] * M[2, 0]) / Det;
  Result[2, 2] := (M[0, 0] * M[1, 1] - M[0, 1] * M[1, 0]) / Det;
end;

{ Наименее-квадратичный фит прямой линии через набор точек (метод главных
  компонент для 2D: направление прямой = собственный вектор ковариационной
  матрицы с наибольшим собственным числом). Возвращает сумму квадратов
  перпендикулярных расстояний точек до этой прямой — то есть "насколько
  точки не лежат на одной прямой". }
function CollinearResidualSq(const Pts: TPoint2DArray): Double;
var
  N, I: Integer;
  Mx, My, Sxx, Syy, Sxy, Theta, Nx, Ny, D: Double;
begin
  N := Length(Pts);
  Result := 0;
  if N < 2 then
    Exit;

  Mx := 0;
  My := 0;
  for I := 0 to N - 1 do
  begin
    Mx := Mx + Pts[I].X;
    My := My + Pts[I].Y;
  end;
  Mx := Mx / N;
  My := My / N;

  Sxx := 0;
  Syy := 0;
  Sxy := 0;
  for I := 0 to N - 1 do
  begin
    Sxx := Sxx + Sqr(Pts[I].X - Mx);
    Syy := Syy + Sqr(Pts[I].Y - My);
    Sxy := Sxy + (Pts[I].X - Mx) * (Pts[I].Y - My);
  end;

  { Угол собственного вектора симметричной матрицы 2x2 в замкнутом виде. }
  Theta := 0.5 * ArcTan2(2 * Sxy, Sxx - Syy);

  { Нормаль к найденной прямой (перпендикуляр к направлению). }
  Nx := -Sin(Theta);
  Ny := Cos(Theta);

  D := 0;
  for I := 0 to N - 1 do
    D := D + Sqr(Nx * (Pts[I].X - Mx) + Ny * (Pts[I].Y - My));

  Result := D;
end;

{ ------------------------------------------------------------------ }
{ Нелинейное уточнение гомографии (Левенберг-Марквардт)               }
{ ------------------------------------------------------------------ }

{ Линейный DLT даёт лишь грубую начальную оценку гомографии: он решает
  линеаризованный суррогат задачи, а не минимизирует напрямую реальную
  ошибку репроекции. На практике (и это подтвердилось на синтетических
  тестах этого модуля) при калибровочных точках, лежащих только по
  контуру объекта, линейный DLT крайне чувствителен к шуму клика —
  ошибка не убывает и даже не стабилизируется с ростом числа точек,
  потому что дело не в шуме/усреднении, а в том, что линейная
  постановка задачи плохо приближает настоящую (проективную) невязку.

  Стандартное решение (как в любой серьёзной калибровке камеры) —
  после линейного DLT запустить итеративное уточнение, напрямую
  минимizируя сумму квадратов реальных ошибок репроекции. Это и делает
  RefineHomographyLM. }

type
  T8Params = array [0 .. 7] of Double; // h11,h12,h13,h21,h22,h23,h31,h32 (h33=1)

function Params8ToMatrix(const P: T8Params): TMatrix3x3;
begin
  Result[0, 0] := P[0]; Result[0, 1] := P[1]; Result[0, 2] := P[2];
  Result[1, 0] := P[3]; Result[1, 1] := P[4]; Result[1, 2] := P[5];
  Result[2, 0] := P[6]; Result[2, 1] := P[7]; Result[2, 2] := 1;
end;

function ApplyHomogMatrix(const M: TMatrix3x3; const P: TPoint2D): TPoint2D;
var
  W: Double;
begin
  W := M[2, 0] * P.X + M[2, 1] * P.Y + M[2, 2];
  if Abs(W) < 1E-12 then
    W := 1E-12;
  Result.X := (M[0, 0] * P.X + M[0, 1] * P.Y + M[0, 2]) / W;
  Result.Y := (M[1, 0] * P.X + M[1, 1] * P.Y + M[1, 2]) / W;
end;

{ Вектор невязок "предсказание минус факт" по X,Y для каждой точки
  подряд (длина 2*N). Именно эту величину, а не линейный суррогат DLT,
  и нужно на самом деле минимизировать. }
procedure ComputeReprojResiduals(const P: T8Params;
  const NormPix, NormWorld: TPoint2DArray; var R: TDoubleVector);
var
  M: TMatrix3x3;
  I: Integer;
  Pred: TPoint2D;
begin
  M := Params8ToMatrix(P);
  SetLength(R, 2 * Length(NormPix));
  for I := 0 to High(NormPix) do
  begin
    Pred := ApplyHomogMatrix(M, NormPix[I]);
    R[2 * I] := Pred.X - NormWorld[I].X;
    R[2 * I + 1] := Pred.Y - NormWorld[I].Y;
  end;
end;

function SumOfSquares(const V: TDoubleVector): Double;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(V) do
    Result := Result + Sqr(V[I]);
end;

procedure RefineHomographyLM(var P: T8Params;
  const NormPix, NormWorld: TPoint2DArray);
const
  MaxIterations = 100;
  DiffEpsilon = 1E-6; // шаг численного дифференцирования
  InitialLambda = 1E-3;
var
  Iter, I, K, ParamIdx, ParamIdx2, N2: Integer;
  R, RTrial, RPlus, RMinus: TDoubleVector;
  Jac: TDoubleMatrix;
  JtJ: TDoubleMatrix;
  JtR, Delta: TDoubleVector;
  PPlus, PMinus, Trial: T8Params;
  Cost, TrialCost, Lambda: Double;
begin
  ComputeReprojResiduals(P, NormPix, NormWorld, R);
  Cost := SumOfSquares(R);
  Lambda := InitialLambda;
  N2 := Length(R);

  for Iter := 1 to MaxIterations do
  begin
    { Численный якобиан (центральные разности) по каждому из 8 параметров. }
    SetLength(Jac, N2, 8);
    for ParamIdx := 0 to 7 do
    begin
      PPlus := P;
      PPlus[ParamIdx] := PPlus[ParamIdx] + DiffEpsilon;
      PMinus := P;
      PMinus[ParamIdx] := PMinus[ParamIdx] - DiffEpsilon;
      ComputeReprojResiduals(PPlus, NormPix, NormWorld, RPlus);
      ComputeReprojResiduals(PMinus, NormPix, NormWorld, RMinus);
      for I := 0 to N2 - 1 do
        Jac[I, ParamIdx] := (RPlus[I] - RMinus[I]) / (2 * DiffEpsilon);
    end;

    { Нормальные уравнения Левенберга-Марквардта:
      (J^T*J + lambda*diag(J^T*J)) * delta = -J^T*R }
    SetLength(JtJ, 8, 8);
    SetLength(JtR, 8);
    for ParamIdx := 0 to 7 do
    begin
      JtR[ParamIdx] := 0;
      for K := 0 to N2 - 1 do
        JtR[ParamIdx] := JtR[ParamIdx] + Jac[K, ParamIdx] * R[K];
      JtR[ParamIdx] := -JtR[ParamIdx];

      for ParamIdx2 := 0 to 7 do
      begin
        JtJ[ParamIdx, ParamIdx2] := 0;
        for K := 0 to N2 - 1 do
          JtJ[ParamIdx, ParamIdx2] := JtJ[ParamIdx, ParamIdx2] +
            Jac[K, ParamIdx] * Jac[K, ParamIdx2];
      end;
    end;

    { Демпфирование Марквардта - усиливаем диагональ, чтобы шаг был
      более осторожным (ближе к градиентному спуску), пока далеко от
      минимума, и более "ньютоновским", когда уже близко. }
    for ParamIdx := 0 to 7 do
      JtJ[ParamIdx, ParamIdx] := JtJ[ParamIdx, ParamIdx] * (1 + Lambda);

    if not SolveLinearSystem(JtJ, JtR, Delta) then
      Break; // система выродилась - дальше уточнять нечем

    for ParamIdx := 0 to 7 do
      Trial[ParamIdx] := P[ParamIdx] + Delta[ParamIdx];

    ComputeReprojResiduals(Trial, NormPix, NormWorld, RTrial);
    TrialCost := SumOfSquares(RTrial);

    if TrialCost < Cost then
    begin
      { Шаг принят: обновляем точку, ослабляем демпфирование. }
      if (Cost - TrialCost) < 1E-14 * (Cost + 1E-14) then
      begin
        P := Trial;
        Cost := TrialCost;
        Break; // практически сошлось
      end;
      P := Trial;
      Cost := TrialCost;
      Lambda := Lambda * 0.5;
    end
    else
    begin
      { Шаг отклонён: усиливаем демпфирование и пробуем снова. }
      Lambda := Lambda * 2;
      if Lambda > 1E10 then
        Break; // не получается улучшить - останавливаемся на достигнутом
    end;
  end;
end;

{ ------------------------------------------------------------------ }
{ Аффинный (6-параметров) фит: X = a*u+b*v+c, Y = d*u+e*v+f.          }
{ Точное решение методом наименьших квадратов, без итераций - по      }
{ построению не подвержено проблеме плохой обусловленности, которая   }
{ портит полную проективную гомографию (см. THomographyModel в        }
{ разделе interface).                                                 }
{ ------------------------------------------------------------------ }
function SolveAffine6(const NormPix, NormWorld: TPoint2DArray): TMatrix3x3;
var
  N, I: Integer;
  Sxx, Sxy, Sx, Syy, Sy, S1: Double;
  Sux, Svx, ScX, Suy, Svy, ScY: Double;
  M: TDoubleMatrix;
  BvX, BvY, CoefX, CoefY: TDoubleVector;
  U, V, WX, WY: Double;
begin
  N := Length(NormPix);
  Sxx := 0; Sxy := 0; Sx := 0; Syy := 0; Sy := 0; S1 := 0;
  Sux := 0; Svx := 0; ScX := 0;
  Suy := 0; Svy := 0; ScY := 0;

  for I := 0 to N - 1 do
  begin
    U := NormPix[I].X; V := NormPix[I].Y;
    WX := NormWorld[I].X; WY := NormWorld[I].Y;

    Sxx := Sxx + U * U; Sxy := Sxy + U * V; Sx := Sx + U;
    Syy := Syy + V * V; Sy := Sy + V; S1 := S1 + 1;

    Sux := Sux + U * WX; Svx := Svx + V * WX; ScX := ScX + WX;
    Suy := Suy + U * WY; Svy := Svy + V * WY; ScY := ScY + WY;
  end;

  { Одна и та же матрица нормальных уравнений (3x3) для X и для Y -
    независимая линейная регрессия по каждой координате. }
  SetLength(M, 3, 3);
  M[0, 0] := Sxx; M[0, 1] := Sxy; M[0, 2] := Sx;
  M[1, 0] := Sxy; M[1, 1] := Syy; M[1, 2] := Sy;
  M[2, 0] := Sx;  M[2, 1] := Sy;  M[2, 2] := S1;

  SetLength(BvX, 3);
  BvX[0] := Sux; BvX[1] := Svx; BvX[2] := ScX;
  SetLength(BvY, 3);
  BvY[0] := Suy; BvY[1] := Svy; BvY[2] := ScY;

  if not SolveLinearSystem(Copy(M), Copy(BvX), CoefX) then
    raise Exception.Create('Не удалось решить аффинную систему (точки вырождены?)');
  if not SolveLinearSystem(Copy(M), Copy(BvY), CoefY) then
    raise Exception.Create('Не удалось решить аффинную систему (точки вырождены?)');

  Result[0, 0] := CoefX[0]; Result[0, 1] := CoefX[1]; Result[0, 2] := CoefX[2];
  Result[1, 0] := CoefY[0]; Result[1, 1] := CoefY[1]; Result[1, 2] := CoefY[2];
  Result[2, 0] := 0;        Result[2, 1] := 0;        Result[2, 2] := 1;
end;

{ ------------------------------------------------------------------ }
{ TPoint2D                                                            }
{ ------------------------------------------------------------------ }

constructor TPoint2D.Create(AX, AY: Double);
begin
  X := AX;
  Y := AY;
end;

{ ------------------------------------------------------------------ }
{ TDistortionModel                                                    }
{ ------------------------------------------------------------------ }

function TDistortionModel.Undistort(const P: TPoint2D): TPoint2D;
var
  Dx, Dy, R2, R4, Factor: Double;
begin
  Dx := (P.X - Cx) / NormRadius;
  Dy := (P.Y - Cy) / NormRadius;
  R2 := Dx * Dx + Dy * Dy;
  R4 := R2 * R2;
  Factor := 1 + K1 * R2 + K2 * R4;
  Result.X := Cx + Dx * Factor * NormRadius;
  Result.Y := Cy + Dy * Factor * NormRadius;
end;

function TDistortionModel.Distort(const P: TPoint2D): TPoint2D;
var
  Ux, Uy, Ru, Rd, F, DF, Ratio: Double;
  I: Integer;
begin
  Ux := (P.X - Cx) / NormRadius;
  Uy := (P.Y - Cy) / NormRadius;
  Ru := Sqrt(Ux * Ux + Uy * Uy);

  if Ru < 1E-12 then
  begin
    Result := P;
    Exit;
  end;

  { Решаем Rd*(1 + K1*Rd^2 + K2*Rd^4) = Ru относительно Rd методом
    Ньютона. Начальное приближение — сам Ru (дисторсия обычно не
    экстремальная, сходимость быстрая). }
  Rd := Ru;
  for I := 1 to 20 do
  begin
    F := Rd * (1 + K1 * Sqr(Rd) + K2 * Sqr(Sqr(Rd))) - Ru;
    DF := 1 + 3 * K1 * Sqr(Rd) + 5 * K2 * Sqr(Sqr(Rd));
    if Abs(DF) < 1E-12 then
      Break;
    Rd := Rd - F / DF;
    if Rd < 0 then
      Rd := 0;
  end;

  Ratio := Rd / Ru;
  Result.X := Cx + Ux * Ratio * NormRadius;
  Result.Y := Cy + Uy * Ratio * NormRadius;
end;

{ ------------------------------------------------------------------ }
{ THomography                                                         }
{ ------------------------------------------------------------------ }

class function THomography.Identity: THomography;
var
  I, J: Integer;
begin
  for I := 0 to 2 do
    for J := 0 to 2 do
      if I = J then
        Result.H[I, J] := 1
      else
        Result.H[I, J] := 0;
end;

function THomography.Apply(const P: TPoint2D): TPoint2D;
var
  W: Double;
begin
  W := H[2, 0] * P.X + H[2, 1] * P.Y + H[2, 2];
  if Abs(W) < 1E-12 then
    W := 1E-12;
  Result.X := (H[0, 0] * P.X + H[0, 1] * P.Y + H[0, 2]) / W;
  Result.Y := (H[1, 0] * P.X + H[1, 1] * P.Y + H[1, 2]) / W;
end;

function THomography.ApplyInverse(const P: TPoint2D): TPoint2D;
var
  Inv: TMatrix3x3;
  W: Double;
begin
  Inv := Invert3x3(H);
  W := Inv[2, 0] * P.X + Inv[2, 1] * P.Y + Inv[2, 2];
  if Abs(W) < 1E-12 then
    W := 1E-12;
  Result.X := (Inv[0, 0] * P.X + Inv[0, 1] * P.Y + Inv[0, 2]) / W;
  Result.Y := (Inv[1, 0] * P.X + Inv[1, 1] * P.Y + Inv[1, 2]) / W;
end;

{ ------------------------------------------------------------------ }
{ TAquariumCalibration                                                }
{ ------------------------------------------------------------------ }

constructor TAquariumCalibration.Create;
begin
  inherited Create;
  FDistortion.Cx := 0;
  FDistortion.Cy := 0;
  FDistortion.K1 := 0;
  FDistortion.K2 := 0;
  FDistortion.NormRadius := 1;
  FHomography := THomography.Identity;
  FCalibrated := False;
end;

procedure TAquariumCalibration.CalibrateDistortion(const Groups: TCollinearGroups;
  ImageWidth, ImageHeight: Integer);
const
  GridSteps = 12;
  Rounds = 6;
  { Глобальные физические границы коэффициентов - поиск НИКОГДА не должен
    выходить за них, даже после многократного пересужения окна вокруг
    текущего минимума (баг, из-за которого окно могло "уползти" далеко
    за пределы разумного, был обнаружен и исправлен по результатам
    тестов в TestGeometrySynthetic.pas). }
  GlobalK1Lo = -1.0; GlobalK1Hi = 1.0;
  GlobalK2Lo = -1.0; GlobalK2Hi = 1.0;
  { Если найденная "оптимальная" дисторсия улучшает невязку менее чем на
    эту долю по сравнению с гипотезой "дисторсии нет" (K1=K2=0),
    считаем, что реального сигнала кривизны недостаточно для надёжной
    оценки (типичная ситуация, когда калибровочные точки лежат близко
    к центру кадра или шум клика сопоставим с самой кривизной) - и
    используем K1=K2=0, а не подгонку под шум. }
  MinCostImprovementRatio = 0.3;
var
  Cand: TDistortionModel;

  function Cost(K1, K2: Double): Double;
  var
    G, I: Integer;
    Undist: TPoint2DArray;
  begin
    Cand.K1 := K1;
    Cand.K2 := K2;
    Result := 0;
    for G := 0 to High(Groups) do
    begin
      SetLength(Undist, Length(Groups[G]));
      for I := 0 to High(Groups[G]) do
        Undist[I] := Cand.Undistort(Groups[G][I]);
      Result := Result + CollinearResidualSq(Undist);
    end;
  end;

var
  BestK1, BestK2, BestCost, ZeroCost: Double;
  K1Lo, K1Hi, K2Lo, K2Hi: Double;
  Step1, Step2: Double;
  K1, K2, C: Double;
  RoundIdx: Integer;
begin
  if Length(Groups) = 0 then
    raise Exception.Create('Для калибровки дисторсии нужна хотя бы одна группа точек');

  Cand.Cx := ImageWidth / 2;
  Cand.Cy := ImageHeight / 2;
  Cand.NormRadius := Sqrt(Sqr(ImageWidth / 2) + Sqr(ImageHeight / 2));

  { Грубый диапазон поиска: для типичных широкоугольных экшн-камер
    нормированные коэффициенты барреловой дисторсии укладываются в
    этот интервал. Метод — сеточный поиск с последовательным сужением
    окна вокруг текущего минимума (без внешних библиотек оптимизации). }
  K1Lo := GlobalK1Lo;
  K1Hi := GlobalK1Hi;
  K2Lo := GlobalK2Lo;
  K2Hi := GlobalK2Hi;

  ZeroCost := Cost(0, 0);
  BestK1 := 0;
  BestK2 := 0;
  BestCost := ZeroCost;

  for RoundIdx := 1 to Rounds do
  begin
    Step1 := (K1Hi - K1Lo) / GridSteps;
    Step2 := (K2Hi - K2Lo) / GridSteps;

    K1 := K1Lo;
    while K1 <= K1Hi do
    begin
      K2 := K2Lo;
      while K2 <= K2Hi do
      begin
        C := Cost(K1, K2);
        if C < BestCost then
        begin
          BestCost := C;
          BestK1 := K1;
          BestK2 := K2;
        end;
        K2 := K2 + Step2;
      end;
      K1 := K1 + Step1;
    end;

    { Сужаем окно вокруг найденного минимума, но НЕ выходя за глобальные
      физические границы - иначе при неудачном шуме окно может "уползти"
      к нефизичным значениям (это и происходило до исправления). }
    K1Lo := Max(GlobalK1Lo, BestK1 - Step1 * 1.5);
    K1Hi := Min(GlobalK1Hi, BestK1 + Step1 * 1.5);
    K2Lo := Max(GlobalK2Lo, BestK2 - Step2 * 1.5);
    K2Hi := Min(GlobalK2Hi, BestK2 + Step2 * 1.5);
  end;

  { Защита от переобучения на шум (см. подробности в комментариях к
    константам выше и в TestGeometrySynthetic.pas): переобучение под шум
    проявляется двумя независимыми признаками, и достаточно любого одного
    из них, чтобы не доверять найденной дисторсии и откатиться на "без
    дисторсии":
      1) найденное значение упёрлось в границу диапазона поиска - для
         реальных объективов настолько экстремальная дисторсия (в этой
         нормировке) маловероятна, и практика показывает, что это почти
         всегда означает не "экстремальный объектив", а переобучение
         гибкой модели под шум немногочисленных точек;
      2) относительное улучшение невязки недостаточно значимо (см.
         MinCostImprovementRatio) - сигнатура "сигнал кривизны слабее
         шума клика". }
  {$IFDEF EODGEO_DEBUG_DISTORTION}
  Writeln(Format('[DEBUG] ZeroCost=%.6f BestCost=%.6f Ratio=%.6f BestK1=%.5f BestK2=%.5f',
    [ZeroCost, BestCost, BestCost / ZeroCost, BestK1, BestK2]));
  {$ENDIF}
  if (Abs(BestK1) >= 0.9 * GlobalK1Hi) or (Abs(BestK2) >= 0.9 * GlobalK2Hi) or
     (BestCost > (1 - MinCostImprovementRatio) * ZeroCost) then
  begin
    BestK1 := 0;
    BestK2 := 0;
  end;

  Cand.K1 := BestK1;
  Cand.K2 := BestK2;
  FDistortion := Cand;
end;

procedure TAquariumCalibration.CalibrateHomography(const WorldPts,
  DistortedPixelPts: array of TPoint2D; Model: THomographyModel);
var
  N, I: Integer;
  UndistPts, NormPixArr, NormWorldArr: TPoint2DArray;
  Tp, Tw, TwInv, HNorm: TMatrix3x3;
  A: TDoubleMatrix;
  Bv, Xv: TDoubleVector;
  U, V, WX, WY: Double;
  Params: T8Params;
begin
  N := Length(WorldPts);
  if N <> Length(DistortedPixelPts) then
    raise Exception.Create('Количество мировых и пиксельных точек должно совпадать');
  if N < 4 then
    raise Exception.Create('Для калибровки гомографии нужно минимум 4 точки');

  { Сначала снимаем дисторсию — гомография работает только с "идеальными"
    (неискажёнными) координатами. }
  SetLength(UndistPts, N);
  for I := 0 to N - 1 do
    UndistPts[I] := FDistortion.Undistort(DistortedPixelPts[I]);

  { Нормализация Хартли: без неё DLT катастрофически чувствителен к шуму
    входных точек (см. комментарий у BuildNormalization). }
  Tp := BuildNormalization(UndistPts);
  Tw := BuildNormalization(WorldPts);

  SetLength(NormPixArr, N);
  SetLength(NormWorldArr, N);
  for I := 0 to N - 1 do
  begin
    NormPixArr[I] := ApplyMat3(Tp, UndistPts[I]);
    NormWorldArr[I] := ApplyMat3(Tw, WorldPts[I]);
  end;

  if Model = hmAffine then
  begin
    { Аффинная модель: точное решение МНК за один шаг, без итераций и
      без плохо обусловленных проективных параметров (см. THomographyModel
      в interface — почему это рекомендуемый по умолчанию режим). }
    HNorm := SolveAffine6(NormPixArr, NormWorldArr);
  end
  else
  begin
    { --- Шаг 1: линейный DLT - даёт быстрое, но лишь грубое начальное
      приближение (сам по себе неустойчив к шуму точек, лежащих только
      по контуру объекта - см. комментарий у RefineHomographyLM). --- }
    SetLength(A, 8, 8);
    SetLength(Bv, 8);

    for I := 0 to N - 1 do
    begin
      U := NormPixArr[I].X;
      V := NormPixArr[I].Y;
      WX := NormWorldArr[I].X;
      WY := NormWorldArr[I].Y;

      { h33' зафиксирован равным 1 (в нормализованном пространстве это
        безопасное допущение при разумной геометрии калибровочных точек):
          u*h11 + v*h12 + h13 - u*X*h31 - v*X*h32 = X
          u*h21 + v*h22 + h23 - u*Y*h31 - v*Y*h32 = Y }
      AddNormalEquationRow(A, Bv, [U, V, 1, 0, 0, 0, -U * WX, -V * WX], WX);
      AddNormalEquationRow(A, Bv, [0, 0, 0, U, V, 1, -U * WY, -V * WY], WY);
    end;

    if not SolveLinearSystem(A, Bv, Xv) then
      raise Exception.Create('Не удалось решить систему для гомографии (точки вырождены?)');

    Params[0] := Xv[0]; Params[1] := Xv[1]; Params[2] := Xv[2];
    Params[3] := Xv[3]; Params[4] := Xv[4]; Params[5] := Xv[5];
    Params[6] := Xv[6]; Params[7] := Xv[7];

    { --- Шаг 2: нелинейное уточнение (Левенберг-Марквардт), напрямую
      минимизирующее реальную ошибку репроекции. Смягчает, но
      принципиально не отменяет чувствительность проективных
      параметров к шуму - см. THomographyModel в interface. --- }
    RefineHomographyLM(Params, NormPixArr, NormWorldArr);

    HNorm := Params8ToMatrix(Params);
  end;

  { Возвращаемся из нормализованных координат к исходным:
    World = Tw^-1 * HNorm * Tp * Pixel_undist }
  TwInv := Invert3x3(Tw);
  FHomography.H := Mat3Mul(TwInv, Mat3Mul(HNorm, Tp));

  FCalibrated := True;
end;

function TAquariumCalibration.PixelToWorld(const APixel: TPoint2D): TPoint2D;
var
  Undist: TPoint2D;
begin
  if not FCalibrated then
    raise Exception.Create('Калибровка ещё не выполнена (см. CalibrateHomography)');
  Undist := FDistortion.Undistort(APixel);
  Result := FHomography.Apply(Undist);
end;

function TAquariumCalibration.WorldToPixel(const AWorld: TPoint2D): TPoint2D;
var
  Undist: TPoint2D;
begin
  if not FCalibrated then
    raise Exception.Create('Калибровка ещё не выполнена (см. CalibrateHomography)');
  Undist := FHomography.ApplyInverse(AWorld);
  Result := FDistortion.Distort(Undist);
end;

function TAquariumCalibration.HomographyResidualRMS(const WorldPts,
  DistortedPixelPts: array of TPoint2D): Double;
var
  I, N: Integer;
  Predicted: TPoint2D;
  SumSq: Double;
begin
  N := Length(WorldPts);
  SumSq := 0;
  for I := 0 to N - 1 do
  begin
    Predicted := PixelToWorld(DistortedPixelPts[I]);
    SumSq := SumSq + Sqr(Predicted.X - WorldPts[I].X) +
      Sqr(Predicted.Y - WorldPts[I].Y);
  end;

  if N = 0 then
    Result := 0
  else
    Result := Sqrt(SumSq / N);
end;

end.
