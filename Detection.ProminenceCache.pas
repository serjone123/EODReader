unit Detection.ProminenceCache;

{ В прошлый раз access violation вырос из-за записи в невыделенный массив, и
  отладчик показал не тот кадр. С включённой проверкой границ тот же дефект
  даёт ERangeError с точным файлом и строкой вместо порчи кучи. Накладные
  расходы терпимы: стадии 2 и 3 уступают по времени стадии 1 (FIR15). }
{$RANGECHECKS ON}

interface

uses
  System.SysUtils, Core.Types, IO.SignalCache;

type
  { Анонимные методы, а не обычные указатели на процедуры: колбэк
    приходит извне (метод детектора) и не должен зависеть от цепочки
    кадров стека вызывающей вложенной процедуры. }
  TProminenceProgressEvent = reference to procedure(Processed, Total: Int64);
  TProminenceCancelEvent = reference to function: Boolean;

function BuildRightMinCache(const Filtered, RightMin: TFloatSignalCache;
  Total: Int64; BlockSize: Integer;
  AProgress: TProminenceProgressEvent; ACancel: TProminenceCancelEvent): Boolean;

function FindPeaksProminenceCached(const Filtered, RightMin: TFloatSignalCache;
  Total: Int64; MinProminence: Single;
  BlockSize: Integer; AProgress: TProminenceProgressEvent;
  ACancel: TProminenceCancelEvent): TPeakArray;

implementation

uses
  System.Classes, System.IOUtils, Core.Log;

const
  DefaultBlockSize = 65536;
  MinimumBlockSize = 1024;
  MaximumBlockSize = 1048576;
  StackMemoryEntries = 262144;
  { Предел файла монотонного стека: 32M записей по 8 байт = 256 МБ.
    На живом сигнале столько глубина не набирает; ограничение нужно,
    чтобы при патологически монотонном сигнале (например, мёртвый
    канал) не уйти в молчаливое заполнение диска. }
  MaxDiskStackEntries = 33554432;
  { Потолок массива пиков (1 ГБ ≈ 64 млн пиков). }
  MaxPeakArrayBytes = 1024 * 1024 * 1024;

type
  TProminenceStackEntry = packed record
    Value: Single;
    Minimum: Single;
  end;

  TProminenceStack = class
  private
    FEntries: array of TProminenceStackEntry;
    FEntryCount: Integer;   // валидных записей в текущей странице RAM
    FDirtyFrom: Integer;    // первый изменённый индекс страницы (Length = нет)
    FPageIndex: Int64;      // индекс страницы, которая сейчас в RAM
    FDiskCount: Int64;      // всего записей в стеке (диск + RAM)
    FUseDisk: Boolean;
    FStream: TFileStream;
    FFileName: string;
    procedure SpillToDisk;
    procedure FlushPage;
    procedure LoadPreviousPage;
  public
    constructor Create(const CacheDir: string);
    destructor Destroy; override;
    procedure Push(Value, Minimum: Single);
    function Pop(out Value, Minimum: Single): Boolean;
  end;

function NormalizeBlockSize(BlockSize: Integer): Integer;
begin
  { Те же границы, что и у FIR-чанка в TEodDetector: иначе мелкий
    ChunkSize из config.json дал бы блок в 1 отсчёт и миллион
    итераций с вызовом прогресса на каждую. }
  if (BlockSize < MinimumBlockSize) or (BlockSize > MaximumBlockSize) then
    BlockSize := DefaultBlockSize;
  Result := BlockSize;
end;

function MaxSingle(A, B: Single): Single;
begin
  if A > B then
    Result := A
  else
    Result := B;
end;

procedure AddPeak(var Peaks: TPeakArray; var Capacity, Count: Integer;
  Position: Int64; Value, Prominence: Single);
var
  NewCapacity: Integer;
begin
  if Count = Capacity then
  begin
    if Capacity = 0 then
      NewCapacity := 1024
    else if Capacity > (MaxInt div 2) then
      NewCapacity := MaxInt div 2
    else
      { ×1.5 вместо ×2: на больших массивах пиков пиковое потребление
        памяти заметно ниже, а лишних копий не больше чем на треть. }
      NewCapacity := Capacity + (Capacity div 2);
    if (Int64(NewCapacity) * SizeOf(TPeak)) > MaxPeakArrayBytes then
      raise ERangeError.Create(
        'Слишком много пиков: массив результата превысил 1 ГБ. ' +
        'Повысьте PeakProminence в настройках или разбейте запись на части.');
    SetLength(Peaks, NewCapacity);
    Capacity := NewCapacity;
  end;
  Peaks[Count].Position := Position;
  Peaks[Count].Value := Value;
  Peaks[Count].Prominence := Prominence;
  Inc(Count);
end;

constructor TProminenceStack.Create(const CacheDir: string);
begin
  inherited Create;
  SetLength(FEntries, StackMemoryEntries);
  FEntryCount := 0;
  FDirtyFrom := StackMemoryEntries;
  FPageIndex := 0;
  FDiskCount := 0;
  FUseDisk := False;
  { Файл стека — рядом с кэшами сигнала, а не в %TEMP%: на системном
    диске для длинной записи места может не хватить. }
  if CacheDir = '' then
    FFileName := TPath.GetTempFileName
  else
    FFileName := TPath.Combine(CacheDir, TPath.GetRandomFileName);
end;
destructor TProminenceStack.Destroy;
begin
  FStream.Free;
  if FFileName <> '' then
    DeleteFile(FFileName);
  FEntries := nil;
  inherited;
end;

{ Стек не помещается в RAM: сливаем накопленную страницу в файл одним
  блоком. Дальше работаем постранично (FlushPage/LoadPreviousPage) —
  позиционирование диска происходит только на границах страниц, а не
  на каждом Push/Pop. }
procedure TProminenceStack.SpillToDisk;
begin
  FStream := TFileStream.Create(FFileName,
    fmCreate or fmOpenReadWrite or fmShareDenyNone);
  FStream.Position := 0;
  if FEntryCount > 0 then
    FStream.WriteBuffer(FEntries[0],
      Int64(FEntryCount) * SizeOf(TProminenceStackEntry));
  { Страница 0 легла на диск, RAM теперь держит пустую страницу 1. }
  FPageIndex := 1;
  FEntryCount := 0;
  FDirtyFrom := Length(FEntries);
  FDiskCount := Length(FEntries);
  FUseDisk := True;
  LogWrite('монотонный стек выгружен на диск: ' + FFileName);
end;

{ Пишем на диск только изменённую часть текущей страницы. }
procedure TProminenceStack.FlushPage;
begin
  if not FUseDisk then
    Exit;
  if (FEntryCount > 0) and (FDirtyFrom < FEntryCount) then
  begin
    FStream.Position := (FPageIndex * Length(FEntries) + FDirtyFrom) *
      SizeOf(TProminenceStackEntry);
    FStream.WriteBuffer(FEntries[FDirtyFrom],
      Int64(FEntryCount - FDirtyFrom) * SizeOf(TProminenceStackEntry));
  end;
  FDirtyFrom := Length(FEntries);
end;

{ RAM-страница опустела при Pop — подгружаем предыдущую страницу. }
procedure TProminenceStack.LoadPreviousPage;
var
  Count: Int64;
begin
  Dec(FPageIndex);
  Count := FDiskCount - FPageIndex * Length(FEntries);
  if (Count <= 0) or (Count > Length(FEntries)) then
    raise ERangeError.Create('Prominence stack page underflow');
  FEntryCount := Integer(Count);
  FDirtyFrom := Length(FEntries);
  FStream.Position := FPageIndex * Int64(Length(FEntries)) *
    SizeOf(TProminenceStackEntry);
  FStream.ReadBuffer(FEntries[0],
    Int64(FEntryCount) * SizeOf(TProminenceStackEntry));
end;

procedure TProminenceStack.Push(Value, Minimum: Single);
var
  Entry: TProminenceStackEntry;
  PageSize: Integer;
begin
  Entry.Value := Value;
  Entry.Minimum := Minimum;
  PageSize := Length(FEntries);

  if not FUseDisk then
  begin
    if FEntryCount < PageSize then
    begin
      FEntries[FEntryCount] := Entry;
      Inc(FEntryCount);
      Exit;
    end;
    SpillToDisk;
  end
  else if FEntryCount >= PageSize then
  begin
    { Страница заполнена: сбрасываем её и переходим к следующей. }
    FlushPage;
    Inc(FPageIndex);
    FEntryCount := 0;
  end;

  if FDirtyFrom > FEntryCount then
    FDirtyFrom := FEntryCount;
  FEntries[FEntryCount] := Entry;
  Inc(FEntryCount);
  Inc(FDiskCount);
  if FDiskCount > MaxDiskStackEntries then
    raise ERangeError.Create(
      'Стек проминенций на диске превысил 256 МБ — сигнал похож на ' +
      'монотонный (например, мёртвый канал). Проверьте сигнал.');
end;

function TProminenceStack.Pop(out Value, Minimum: Single): Boolean;
var
  Entry: TProminenceStackEntry;
begin
  Result := False;
  if not FUseDisk then
  begin
    if FEntryCount = 0 then
      Exit;
    Dec(FEntryCount);
    Entry := FEntries[FEntryCount];
  end
  else
  begin
    if FEntryCount = 0 then
    begin
      if FDiskCount = 0 then
        Exit;
      LoadPreviousPage;
    end;
    Dec(FEntryCount);
    Dec(FDiskCount);
    Entry := FEntries[FEntryCount];
  end;
  Value := Entry.Value;
  Minimum := Entry.Minimum;
  Result := True;
end;

function BuildRightMinCache(const Filtered, RightMin: TFloatSignalCache;
  Total: Int64; BlockSize: Integer;
  AProgress: TProminenceProgressEvent; ACancel: TProminenceCancelEvent): Boolean;
var
  Stack: TProminenceStack;
  X, OutBlock: TFloatArray;
  EndIndex, StartIndex, Count64, Processed: Int64;
  Count, J, Block: Integer;
  Value, CurrentMinimum, TopValue, TopMinimum: Single;
begin
  Result := False;
  SetLength(X, 0);
  SetLength(OutBlock, 0);
  if (Filtered = nil) or (RightMin = nil) or (Total < 0) then
    raise EArgumentOutOfRangeException.Create('Invalid right-min cache arguments');
  if Total > Filtered.Count then
    raise EArgumentOutOfRangeException.Create('Filtered cache is shorter than Total');
  BlockSize := NormalizeBlockSize(BlockSize);
  RightMin.Initialize(Filtered.SampleRate, Total);
  if Total = 0 then
    Exit(True);

  Stack := TProminenceStack.Create(Filtered.Dir);
  try
    Processed := 0;
    Block := 0;
    EndIndex := Total - 1;
    while EndIndex >= 0 do
    begin
      if Assigned(ACancel) and ACancel() then
        Exit;
      Inc(Block);
      { Каждая операция блока под своей меткой: по тексту ошибки видно,
        что именно сломалось (чтение кэша / стек / запись / прогресс).
        Обработчик не срабатывает, пока исключения нет. }
      try
        Count64 := EndIndex + 1;
        if Count64 > BlockSize then
          Count64 := BlockSize;
        StartIndex := EndIndex - Count64 + 1;
        Count := Integer(Count64);
        try
          Filtered.Read(StartIndex, Count, X);
          if Length(X) <> Count then
            raise EReadError.Create('Invalid filtered cache block');
        except
          on E: EAbort do
            raise;
          on E: Exception do
            raise EStageError.CreateFmt('чтение отфильтрованного кэша, блок %d, [%d..%d]: %s: %s',
              [Block, StartIndex, StartIndex + Count64 - 1, E.ClassName, E.Message]);
        end;
        SetLength(OutBlock, Count);
        try
          for J := Count - 1 downto 0 do
          begin
            Value := X[J];
            CurrentMinimum := Value;
            while Stack.Pop(TopValue, TopMinimum) do
            begin
              if TopValue <= Value then
              begin
                if TopMinimum < CurrentMinimum then
                  CurrentMinimum := TopMinimum;
              end
              else
              begin
                Stack.Push(TopValue, TopMinimum);
                Break;
              end;
            end;
            OutBlock[Count - 1 - J] := CurrentMinimum;
            Stack.Push(Value, CurrentMinimum);
          end;
        except
          on E: EAbort do
            raise;
          on E: Exception do
            raise EStageError.CreateFmt('монотонный стек, блок %d (Processed=%d из %d): %s: %s',
              [Block, Processed, Total, E.ClassName, E.Message]);
        end;
        try
          RightMin.Append(OutBlock);
        except
          on E: EAbort do
            raise;
          on E: Exception do
            raise EStageError.CreateFmt('запись кэша правых минимумов, блок %d (Processed=%d из %d): %s: %s',
              [Block, Processed, Total, E.ClassName, E.Message]);
        end;
        Inc(Processed, Count64);
        if Assigned(AProgress) then
          try
            AProgress(Processed, Total);
          except
            on E: EAbort do
              raise;
            on E: Exception do
              raise EStageError.CreateFmt('обратная связь прогресса, блок %d (Processed=%d из %d): %s: %s',
                [Block, Processed, Total, E.ClassName, E.Message]);
          end;
        EndIndex := StartIndex - 1;
      except
        on E: EAbort do
          raise;
        on E: EStageError do
          raise;
        on E: Exception do
          raise EStageError.CreateFmt('блок %d (Processed=%d из %d): %s: %s',
            [Block, Processed, Total, E.ClassName, E.Message]);
      end;
    end;
    Result := RightMin.Count = Total;
  finally
    Stack.Free;
    SetLength(X, 0);
    SetLength(OutBlock, 0);
  end;
end;

function FindPeaksProminenceCached(const Filtered, RightMin: TFloatSignalCache;
  Total: Int64; MinProminence: Single;
  BlockSize: Integer; AProgress: TProminenceProgressEvent;
  ACancel: TProminenceCancelEvent): TPeakArray;
var
  Stack: TProminenceStack;
  X, RightReverse: TFloatArray;
  StartIndex, Count64, Processed, CurrentIndex: Int64;
  Count, J, Block: Integer;
  Value, CurrentMinimum, TopValue, TopMinimum: Single;
  PreviousValue, PreviousPreviousValue: Single;
  PreviousLeftMinimum, PreviousRightMinimum, Prominence: Single;
  HavePrevious: Boolean;
  PeakCount, Capacity: Integer;
begin
  SetLength(Result, 0);
  SetLength(X, 0);
  SetLength(RightReverse, 0);
  if (Filtered = nil) or (RightMin = nil) or (Total < 0) then
    raise EArgumentOutOfRangeException.Create('Invalid prominence cache arguments');
  if (Filtered.Count < Total) or (RightMin.Count < Total) then
    raise EArgumentOutOfRangeException.Create('Prominence cache is shorter than Total');
  if Total < 3 then
    Exit;
  BlockSize := NormalizeBlockSize(BlockSize);

  Stack := TProminenceStack.Create(Filtered.Dir);
  try
    StartIndex := 0;
    Processed := 0;
    Block := 0;
    HavePrevious := False;
    PreviousValue := 0;
    PreviousPreviousValue := 0;
    PreviousLeftMinimum := 0;
    PreviousRightMinimum := 0;
    PeakCount := 0;
    Capacity := 0;
    while StartIndex < Total do
    begin
      if Assigned(ACancel) and ACancel() then
      begin
        SetLength(Result, 0);
        Exit;
      end;
      Inc(Block);
      try
        Count64 := Total - StartIndex;
        if Count64 > BlockSize then
          Count64 := BlockSize;
        Count := Integer(Count64);
        try
          Filtered.Read(StartIndex, Count, X);
          RightMin.Read(Total - StartIndex - Count64, Count, RightReverse);
          if (Length(X) <> Count) or (Length(RightReverse) <> Count) then
            raise EReadError.Create('Invalid prominence cache block');
        except
          on E: EAbort do
            raise;
          on E: Exception do
            raise EStageError.CreateFmt('чтение кэшей, блок %d (Processed=%d из %d): %s: %s',
              [Block, Processed, Total, E.ClassName, E.Message]);
        end;
        { RightMin лежит в обратном порядке, поэтому правый минимум для
          индекса J лежит в RightReverse[Count - 1 - J]. Отдельный
          развёрнутый массив не нужен (и его не было — запись в него была
          выходом за границу, т.е. access violation). }
        try
          for J := 0 to Count - 1 do
          begin
            Value := X[J];
            CurrentIndex := StartIndex + J;
            if HavePrevious and (CurrentIndex >= 2) and
              (PreviousValue > PreviousPreviousValue) and
              (PreviousValue >= Value) then
            begin
              Prominence := PreviousValue - MaxSingle(PreviousLeftMinimum,
                PreviousRightMinimum);
              if Prominence >= MinProminence then
                AddPeak(Result, Capacity, PeakCount, CurrentIndex - 1,
                  PreviousValue, Prominence);
            end;

            CurrentMinimum := Value;
            while Stack.Pop(TopValue, TopMinimum) do
            begin
              if TopValue <= Value then
              begin
                if TopMinimum < CurrentMinimum then
                  CurrentMinimum := TopMinimum;
              end
              else
              begin
                Stack.Push(TopValue, TopMinimum);
                Break;
              end;
            end;
            Stack.Push(Value, CurrentMinimum);
            PreviousPreviousValue := PreviousValue;
            PreviousValue := Value;
            PreviousLeftMinimum := CurrentMinimum;
            PreviousRightMinimum := RightReverse[Count - 1 - J];
            HavePrevious := True;
          end;
        except
          on E: EAbort do
            raise;
          on E: Exception do
            raise EStageError.CreateFmt('поиск пиков, блок %d (Processed=%d из %d, найдено %d): %s: %s',
              [Block, Processed, Total, PeakCount, E.ClassName, E.Message]);
        end;
        Inc(Processed, Count64);
        if Assigned(AProgress) then
          try
            AProgress(Processed, Total);
          except
            on E: EAbort do
              raise;
            on E: Exception do
              raise EStageError.CreateFmt('обратная связь прогресса, блок %d (Processed=%d из %d): %s: %s',
                [Block, Processed, Total, E.ClassName, E.Message]);
          end;
        Inc(StartIndex, Count64);
      except
        on E: EAbort do
          raise;
        on E: EStageError do
          raise;
        on E: Exception do
          raise EStageError.CreateFmt('блок %d (Processed=%d из %d): %s: %s',
            [Block, Processed, Total, E.ClassName, E.Message]);
      end;
    end;
    if PeakCount = 0 then
      SetLength(Result, 0)
    else
      SetLength(Result, PeakCount);
  finally
    Stack.Free;
    SetLength(X, 0);
    SetLength(RightReverse, 0);
  end;
end;

end.
