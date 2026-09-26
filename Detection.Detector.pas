unit Detection.Detector;

{ Колбэки прогресса/отмены — обычные методы этого класса (см. FProgress),
  а не вложенные процедуры AnalyzePeaks. Вложенная процедура читает
  локальные переменные внешнего метода по цепочке кадров стека; когда её
  вызывают через указатель на процедуру из другого модуля, расстояние до
  кадра внешнего метода больше одного, и в оптимизированной сборке
  (инлайн ReportProgress в обёртку) смещение вычислялось неверно —
  вызов AProgress падал в access violation, причём отладчик показывал
  неверный кадр и неверные аргументы. }
{$INLINE OFF}

interface

uses
  Core.Types;

type
  TDetectorProgressEvent = procedure(Sender: TObject; Processed, Total: Int64) of object;
  TDetectorCancelEvent = function(Sender: TObject): Boolean of object;

  TSegmentBoundaryMode = (sbStrict, sbPadWithZero);

  TEodDetector = class
  private
    FConfig: TEodDetectorConfig;
    FProgress: TDetectorProgressEvent;
    FCancel: TDetectorCancelEvent;
    FProgressTotal: Int64;
    FLastProgress: Int64;
    procedure ReportStage(AStage, AStageSize: Integer;
      AProcessed, AStageTotal: Int64);
    procedure ReportFinal;
    procedure RightMinProgress(AProcessed, AStageTotal: Int64);
    procedure PeaksProgress(AProcessed, AStageTotal: Int64);
    function Canceled: Boolean;
  public
    constructor Create(const AConfig: TEodDetectorConfig);
    function Analyze(const File1, File2: string): TEodEventArray;
    function AnalyzePeaks(const File1, File2: string; MaxFrames: Int64 = 0;
      AProgress: TDetectorProgressEvent = nil;
      ACancel: TDetectorCancelEvent = nil): TPeakArray;
    procedure ReadSegment(const File1, File2: string; StartFrame: Int64;
      ACount: Integer; Mode: TSegmentBoundaryMode; var Buffer: TAudioChunk);
    property Config: TEodDetectorConfig read FConfig;
    function ApplyFir15(const Values: TFloatArray): TFloatArray;
  end;

implementation

uses
  System.SysUtils, System.Math, System.IOUtils, System.Generics.Defaults,
  System.Generics.Collections,
  Core.Log,
  IO.AudioSource, IO.SignalCache, Signal.Statistics, Signal.Fir15,
  Detection.ProminenceCache, Detection.Classifier;

const
  { TFir15.Process only produces valid output for indices
    [8 .. Length(Input)-9] (see Eod.Fir15, exact geometry of fir15.m).
    To get a full N-sample core output for a chunk of length N we must
    feed it N + 2*Fir15HalfWidth samples, with the core block starting
    at offset Fir15HalfWidth.

    NOTE: this used to be 7 on each side, which only yields N-2 valid
    core samples instead of N — the first and last sample of every
    chunk were silently left at 0 in AllFiltered. That is now fixed. }
  Fir15HalfWidth = 8;

function AppendEvents(var A: TEodEventArray; const B: TEodEventArray): Integer;
var
  OldN, I: Integer;
begin
  OldN := Length(A);
  SetLength(A, OldN + Length(B));
  for I := 0 to High(B) do A[OldN + I] := B[I];
  Result := Length(A);
end;

{ Подавление близких событий. Из каждой группы событий, чьи позиции лежат в
  пределах Distance друг от друга (от первого события группы), остаётся одно —
  с максимальной корреляцией. Вход может быть не отсортирован по позиции,
  поэтому перед группировкой события сортируются: Position — по возрастанию,
  при равенстве позиций Correlation — по убыванию; так выбор победителя в
  группе детерминирован даже после неустойчивой сортировки.

  Это замена старой реализации, которая в порядке появления списка молча
  оставляла ПЕРВОЕ событие, а матлаб-эталон (см. read_wav_4ch_last.m,
  блок дедупликации) оставлял последний элемент пары и терял полностью
  первый элемент списка и оба элемента близкой пары. Здесь из близкой группы
  всегда остаётся ровно один кандидат — лучший по качеству классификации. }
function DeduplicateEvents(const Input: TEodEventArray; Distance: Int64): TEodEventArray;
var
  Events: TArray<TEodEvent>;
  Comparer: IComparer<TEodEvent>;
  J, K, GStart, N: Integer;
  Best: TEodEvent;
begin
  SetLength(Result, 0);
  N := Length(Input);
  if N = 0 then Exit;

  SetLength(Events, N);
  for J := 0 to N - 1 do
    Events[J] := Input[J];

  Comparer := TComparer<TEodEvent>.Construct(
    function(const A, B: TEodEvent): Integer
    begin
      if A.Position < B.Position then Exit(-1);
      if A.Position > B.Position then Exit(1);
      if A.Correlation > B.Correlation then Exit(-1);
      if A.Correlation < B.Correlation then Exit(1);
      Result := 0;
    end);
  TArray.Sort<TEodEvent>(Events, Comparer);

  GStart := 0;
  for J := 1 to N - 1 do
  begin
    if Events[J].Position - Events[GStart].Position > Distance then
    begin
      Best := Events[GStart];
      for K := GStart + 1 to J - 1 do
        if Events[K].Correlation > Best.Correlation then
          Best := Events[K];
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := Best;
      GStart := J;
    end;
  end;

  Best := Events[GStart];
  for K := GStart + 1 to N - 1 do
    if Events[K].Correlation > Best.Correlation then
      Best := Events[K];
  SetLength(Result, Length(Result) + 1);
  Result[High(Result)] := Best;
end;

constructor TEodDetector.Create(const AConfig: TEodDetectorConfig);
begin
  inherited Create;
  FConfig := AConfig;
  FLastProgress := -1;
end;

procedure TEodDetector.ReportStage(AStage, AStageSize: Integer;
  AProcessed, AStageTotal: Int64);
var
  Value: Int64;
begin
  if not Assigned(FProgress) or (AStageTotal <= 0) then
    Exit;
  Value := AStage + Round(AProcessed * (AStageSize / AStageTotal));
  { Прогресс — это блокирующий Synchronize в главный поток. Шлём его
    только когда изменился целый процент: иначе на записи в сотни
    миллионов кадров получаем десятки тысяч холостых переключений. }
  if Value = FLastProgress then
    Exit;
  FLastProgress := Value;
  { Наружу отдаём именно кадры, а не шкалу 0..100: иначе статус в UI
    делит «проценты» на Total кадров и показывает 0%. }
  LogWriteFmt('прогресс %d%% (%d из %d кадров)',
    [Value, (Value * FProgressTotal) div 100, FProgressTotal]);
  try
    FProgress(Self, (Value * FProgressTotal) div 100, FProgressTotal);
  except
    on E: EAbort do
      raise;
    on E: Exception do
    begin
      { Обратная связь — украшение: поломка статусной строки не должна
        срывать многочасовой анализ. Пишем в журнал (там будет точный
        адрес обращения) и отключаем прогресс до конца запуска. }
      LogWriteFmt('обратная связь прогресса ОТКЛЮЧЕНА на стадии %d%% (%d из %d): %s: %s',
        [Value, (Value * FProgressTotal) div 100, FProgressTotal,
         E.ClassName, E.Message]);
      FProgress := nil;
    end;
  end;
end;

procedure TEodDetector.ReportFinal;
begin
  if not Assigned(FProgress) or (FProgressTotal <= 0) or Canceled then
    Exit;
  try
    FProgress(Self, FProgressTotal, FProgressTotal);
  except
    on E: EAbort do
      raise;
    on E: Exception do
      LogWriteFmt('финальный прогресс не доставлен: %s: %s',
        [E.ClassName, E.Message]);
  end;
end;

procedure TEodDetector.RightMinProgress(AProcessed, AStageTotal: Int64);
begin
  ReportStage(40, 30, AProcessed, AStageTotal);
end;

procedure TEodDetector.PeaksProgress(AProcessed, AStageTotal: Int64);
begin
  ReportStage(70, 30, AProcessed, AStageTotal);
end;

function TEodDetector.Canceled: Boolean;
begin
  Result := Assigned(FCancel) and FCancel(Self);
end;

function TEodDetector.AnalyzePeaks(const File1, File2: string; MaxFrames: Int64;
  AProgress: TDetectorProgressEvent; ACancel: TDetectorCancelEvent): TPeakArray;
var
  Source: TFourChannelAudioSource;
  FilteredCache, RightMinCache: TFloatSignalCache;
  Fir: TFir15;
  Std, Filtered, CoreFiltered, FirInput: TFloatArray;
  Chunk: TAudioChunk;
  Frame, Total, DesiredStart, DesiredEnd: Int64;
  ReadStart, ReadCount: Int64;
  N, I, DestOffset, CoreIndex, BlockSize: Integer;
  StageStart: TDateTime;
  function FormatBytes(ABytes: Int64): string;
  begin
    if ABytes >= 1024 * 1024 * 1024 then
      Result := Format('%.1f ГБ', [ABytes / (1024.0 * 1024 * 1024)])
    else if ABytes >= 1024 * 1024 then
      Result := Format('%.0f МБ', [ABytes / (1024.0 * 1024)])
    else
      Result := Format('%d Б', [ABytes]);
  end;
  function OpenCaches(const ADir: string; out AError: string): Boolean;
  begin
    Result := False;
    AError := '';
    try
      FilteredCache := TFloatSignalCache.Create(ADir);
      RightMinCache := TFloatSignalCache.Create(ADir);
      Result := True;
    except
      on E: Exception do
      begin
        AError := E.Message;
        FilteredCache.Free;
        FilteredCache := nil;
        RightMinCache.Free;
        RightMinCache := nil;
      end;
    end;
  end;
  { Кэши кладём рядом с самим WAV: на системном диске для длинной
    записи места может не хватить, и его конец в 32-битном процессе
    выглядит как access violation, а не как понятная ошибка. Если
    каталог записи не доступен для записи (например, read-only шара) —
    откатываемся на %TEMP%. }
  procedure PrepareCaches;
  var
    Dir, Err1, Err2: string;
  begin
    Dir := ExtractFilePath(ExpandFileName(File1));
    if (Dir <> '') and OpenCaches(Dir, Err1) then
      Exit;
    if OpenCaches('', Err2) then
      Exit;
    if Err1 <> '' then
      raise Exception.Create(Err1)
    else if Err2 <> '' then
      raise Exception.Create(Err2)
    else
      raise Exception.Create('Не удалось создать временный кэш сигнала');
  end;
  procedure CheckCacheSpace;
  var
    Need, FreeSpace: Int64;
  begin
    Need := SignalCacheRequiredBytes(Total);
    FreeSpace := SignalCacheFreeSpace(FilteredCache.Dir);
    if (FreeSpace >= 0) and (FreeSpace < Need) then
      raise Exception.CreateFmt(
        'Недостаточно места для временных кэшей: нужно %s, доступно %s (%s). ' +
        'Освободите место на диске или перенесите запись на диск большего объёма.',
        [FormatBytes(Need), FormatBytes(FreeSpace), FilteredCache.Dir]);
  end;
begin
  SetLength(Result, 0);
  Source := nil;
  FilteredCache := nil;
  RightMinCache := nil;
  try
    Source := TFourChannelAudioSource.Create(File1, File2);
    Total := Source.TotalFrames;
    if (MaxFrames > 0) and (MaxFrames < Total) then
      Total := MaxFrames;

    { Один размер блока на все три стадии: иначе мелкий ChunkSize из
      config.json даст блок в 1 отсчёт в prominence-проходах. }
    BlockSize := FConfig.ChunkSize;
    if (BlockSize < 1024) or (BlockSize > MaxEodChunkSize) then
      BlockSize := 65536;
    FProgress := AProgress;
    FCancel := ACancel;
    FProgressTotal := Total;
    FLastProgress := -1;
    StageStart := Now;

    PrepareCaches;
    CheckCacheSpace;
    LogWriteFmt('анализ начат: %s + %s, %d кадров, блок %d, кэши в %s',
      [ExtractFileName(File1), ExtractFileName(File2), Total, BlockSize,
       FilteredCache.Dir]);
    FilteredCache.Initialize(Source.SampleRate, Total);

    Fir := TFir15.Create;
    try
      Frame := 0;
      while Frame < Total do
      begin
        N := BlockSize;
        if Int64(N) > Total - Frame then
          N := Integer(Total - Frame);

        DesiredStart := Frame - Fir15HalfWidth;
        DesiredEnd := Frame + Int64(N) + Fir15HalfWidth;
        ReadStart := Max(0, DesiredStart);
        ReadCount := Min(Source.TotalFrames, DesiredEnd) - ReadStart;
        if ReadCount < 0 then
          ReadCount := 0;

        try
          SetLength(FirInput, N + 2 * Fir15HalfWidth);
          for I := 0 to High(FirInput) do
            FirInput[I] := 0;

          if ReadCount > 0 then
          begin
            Source.ReadFrames(ReadStart, Integer(ReadCount), Chunk);
            CalculateStdChunk(Chunk, Std);
            DestOffset := Integer(ReadStart - DesiredStart);
            for I := 0 to High(Std) do
              FirInput[DestOffset + I] := Std[I];
          end;

          Fir.Process(FirInput, Filtered);
          SetLength(CoreFiltered, N);
          DestOffset := Integer(Frame - DesiredStart);
          for I := 0 to N - 1 do
          begin
            CoreIndex := I + DestOffset;
            CoreFiltered[I] := Filtered[CoreIndex];
          end;
          FilteredCache.Append(CoreFiltered);
        except
          on E: EAbort do
            raise;
          on E: Exception do
            raise EStageError.CreateFmt(
              'стадия 1 «STD + FIR15», кадр %d из %d: %s: %s',
              [Frame, Total, E.ClassName, E.Message]);
        end;
        Inc(Frame, N);
        ReportStage(0, 40, Frame, Total);
        if Canceled then
          Exit;
      end;
      LogWriteFmt('стадия 1 «STD + FIR15» завершена за %.3f с',
        [(Now - StageStart) * 86400]);
      StageStart := Now;

      if Canceled then
        Exit;
      try
        if not BuildRightMinCache(FilteredCache, RightMinCache, Total,
          BlockSize, Self.RightMinProgress, Self.Canceled) then
          Exit;
      except
        on E: EAbort do
          raise;
        on E: Exception do
          raise EStageError.CreateFmt('стадия 2 «правый минимум prominence»: %s: %s',
            [E.ClassName, E.Message]);
      end;
      LogWriteFmt('стадия 2 «правый минимум prominence» завершена за %.3f с',
        [(Now - StageStart) * 86400]);
      StageStart := Now;
      try
        Result := FindPeaksProminenceCached(FilteredCache, RightMinCache,
          Total, FConfig.PeakProminence, BlockSize,
          Self.PeaksProgress, Self.Canceled);
      except
        on E: EAbort do
          raise;
        on E: Exception do
          raise EStageError.CreateFmt('стадия 3 «поиск пиков по prominence»: %s: %s',
            [E.ClassName, E.Message]);
      end;
      LogWriteFmt('стадия 3 «поиск пиков» завершена за %.3f с, пиков %d',
        [(Now - StageStart) * 86400, Length(Result)]);
      ReportFinal;
    finally
      Fir.Free;
    end;
  finally
    FProgress := nil;
    FCancel := nil;
    RightMinCache.Free;
    FilteredCache.Free;
    Source.Free;
  end;
end;

procedure TEodDetector.ReadSegment(const File1, File2: string; StartFrame: Int64;
  ACount: Integer; Mode: TSegmentBoundaryMode; var Buffer: TAudioChunk);
var
  Source: TFourChannelAudioSource;
  SourceStart, SourceEnd, CopyCount, DestOffset: Int64;
  Temp: TAudioChunk;
  I: Integer;
begin
  SetLength(Buffer, 0);
  if ACount <= 0 then Exit;

  Source := TFourChannelAudioSource.Create(File1, File2);
  try
    if Mode = sbStrict then
    begin
      if (StartFrame < 0) or (StartFrame + ACount > Source.TotalFrames) then
        raise EArgumentOutOfRangeException.CreateFmt(
          'Segment [%d..%d] is outside source [0..%d]',
          [StartFrame, StartFrame + ACount - 1, Source.TotalFrames - 1]);

      Source.ReadFrames(StartFrame, ACount, Buffer);
      Exit;
    end;

    SetLength(Buffer, ACount);
    for I := 0 to ACount - 1 do
      Buffer[I].Ch1 := 0;

    SourceStart := StartFrame;
    SourceEnd := StartFrame + ACount;

    if SourceStart < 0 then
      SourceStart := 0;
    if SourceEnd > Source.TotalFrames then
      SourceEnd := Source.TotalFrames;

    if SourceEnd <= SourceStart then
      Exit;

    CopyCount := SourceEnd - SourceStart;
    DestOffset := SourceStart - StartFrame;
    Source.ReadFrames(SourceStart, CopyCount, Temp);

    for I := 0 to Integer(CopyCount) - 1 do
      Buffer[DestOffset + I] := Temp[I];
  finally
    Source.Free;
  end;
end;

function TEodDetector.Analyze(const File1, File2: string): TEodEventArray;
var
  Source: TFourChannelAudioSource;
  Classifier: TEodClassifier;
  CandidateWindow: TAudioChunk;
  PeakResults: TEodEventArray;
  Peaks: TPeakArray;
  Peak: TPeak;
  StartFrame, WindowLength: Int64;
begin
  SetLength(Result, 0);
  Source := TFourChannelAudioSource.Create(File1, File2);
  try
    Classifier := TEodClassifier.Create;
    try
      Peaks := AnalyzePeaks(File1, File2);
      WindowLength := FConfig.WindowBefore + FConfig.WindowAfter + 1;

      { Правило классификации. Classify проверяет три шаблона независимо
        (как corr_et.m в матлаб-эталоне) и может вернуть до трёх кандидатов
        на один STD-пик — по одному на каждый тип рыбы, если корреляция
        превысила порог. «Один кандидат на физическое событие» получается
        ниже в DeduplicateEvents: из группы близких по позиции кандидатов
        остаётся лучший по корреляции. Явный выбор «лучшего шаблона» в
        классификаторе не делается намеренно — только когда в близкой окрестности
        действительно несколько разрядов, они сохраняются все. }
      for Peak in Peaks do
      begin
        StartFrame := Peak.Position - FConfig.WindowBefore;
        if (StartFrame < 0) or
           (StartFrame + WindowLength > Source.TotalFrames) then
          Continue;

        Source.ReadFrames(StartFrame, WindowLength, CandidateWindow);
        PeakResults := Classifier.Classify(
          CandidateWindow,
          StartFrame,
          FConfig.CorrelationThreshold
        );
        AppendEvents(Result, PeakResults);
      end;

      Result := DeduplicateEvents(Result, FConfig.DuplicateDistance);
    finally
      Classifier.Free;
    end;
  finally
    Source.Free;
  end;
end;

function TEodDetector.ApplyFir15(const Values: TFloatArray): TFloatArray;
var
  Fir: TFir15;
begin
  Fir := TFir15.Create;
  try
    Fir.Process(Values, Result);
  finally
    Fir.Free;
  end;
end;

end.
