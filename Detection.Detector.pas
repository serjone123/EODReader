unit Detection.Detector;

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
  System.SysUtils, System.Math, System.Generics.Defaults, System.Generics.Collections,
  IO.AudioSource, Signal.Statistics, Signal.Fir15,
  Signal.Peaks, Detection.Classifier;

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
end;

function TEodDetector.AnalyzePeaks(const File1, File2: string; MaxFrames: Int64;
  AProgress: TDetectorProgressEvent; ACancel: TDetectorCancelEvent): TPeakArray;
var
  Source: TFourChannelAudioSource;
  Fir: TFir15;
  Std, Filtered: TFloatArray;
  Chunk: TAudioChunk;
  FirInput: TFloatArray;
  AllFiltered: TFloatArray;
  LocalPeaks: TPeakArray;
  Frame, N, I: Integer;
  Total, DesiredStart, DesiredEnd: Int64;
  ReadStart, ReadCount: Int64;
  DestOffset, CoreIndex: Integer;
begin
  SetLength(Result, 0);
  Source := TFourChannelAudioSource.Create(File1, File2);
  try
    Total := Source.TotalFrames;
    if (MaxFrames > 0) and (MaxFrames < Total) then
      Total := MaxFrames;

    { Анализ пока целиком держит отфильтрованный сигнал в RAM (prominence
      считается по всему интервалу; дисковый кэш — этап P1). Динамический
      массив в Win32 адресуется через Integer, поэтому Total длиннее MaxInt
      не поддерживается: вместо молчаливого переполнения Int64 -> Integer
      (порча длины, отрицательный размер) пробрасываем понятную ошибку.
      После этой проверки все сужения Int64 -> Integer ниже безопасны. }
    if Total > MaxInt then
      raise ERangeError.CreateFmt(
        'Запись длиной %d кадров слишком велика для анализа в памяти ' +
        '(лимит %d). Потоковая/чанковая обработка планируется (P1).',
        [Total, MaxInt]);
    SetLength(AllFiltered, Integer(Total));

    Fir := TFir15.Create;
    try
      Frame := 0;
      while Frame < Total do
      begin
        N := FConfig.ChunkSize;
        if Frame + N > Total then
          N := Integer(Total - Frame);

        { Read Fir15HalfWidth samples on each side of the core block so
          FIR15 has the same neighbourhood it would have in one continuous
          array, and so its valid output range exactly covers the N core
          samples (see Fir15HalfWidth comment above). }
        DesiredStart := Frame - Fir15HalfWidth;
        DesiredEnd := Frame + N + Fir15HalfWidth;
        ReadStart := Max(0, DesiredStart);
        ReadCount := Min(Source.TotalFrames, DesiredEnd) - ReadStart;
        if ReadCount < 0 then
          ReadCount := 0;

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

        DestOffset := Integer(Frame - DesiredStart); { = Fir15HalfWidth }
        for I := 0 to N - 1 do
        begin
          CoreIndex := I + DestOffset;
          AllFiltered[Frame + I] := Filtered[CoreIndex];
        end;

        Inc(Frame, N);

        if Assigned(AProgress) then
          AProgress(Self, Frame, Total);
        if Assigned(ACancel) and ACancel(Self) then
          Exit;
      end;

      if Assigned(ACancel) and ACancel(Self) then
        Exit;

      LocalPeaks := FindPeaksProminence(AllFiltered, FConfig.PeakProminence);
      if Assigned(AProgress) then
        AProgress(Self, Total, Total);
      Result := LocalPeaks;
    finally
      Fir.Free;
    end;
  finally
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
