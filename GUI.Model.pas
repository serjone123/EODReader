unit GUI.Model;

interface

uses
  System.SysUtils, System.Classes, System.Math,
  Core.Types, Detection.Detector, IO.PeakStore, IO.AudioSource, Signal.Statistics;

type
  TDataMode = (dmNone, dmWav, dmPeakFile);

  TEodGuiSession = class
  private
    FMode: TDataMode;
    FFile1: string;
    FFile2: string;
    FPeakFile: string;
    FSource: TFourChannelAudioSource;
    FStore: TEodPeakStore;
    FPeaks: TPeakArray;
    FSampleRate: Integer;
    FTotalFrames: Int64;
    procedure CloseObjects;
    function GetVersion: Integer;
    function GetPeakPositions: TArray<Int64>;
  public
    destructor Destroy; override;
    procedure Close;
    procedure OpenWavPair(const File1, File2: string);
    procedure OpenPeakFile(const FileName: string);
    procedure SetPeaks(const APeaks: TPeakArray);
    function ReadSegment(StartFrame: Int64; Count: Integer; Pad: Boolean = True): TAudioChunk;
    function ReadPeak(Index: Integer; out Peak: TPeak; out StartFrame: Int64): TAudioChunk;
    function ReadPeakInfoPage(PageIndex: Integer; var Peaks: TPeakArray): Boolean;
    function GetPeak(Index: Integer; out Peak: TPeak): Boolean;
    function GetPeakPosition(Index: Integer): Int64;
    function CalculateStd(const Data: TAudioChunk): TFloatArray;
    function PeakCount: Integer;
    procedure SavePeakFile(const FileName: string);
    property Mode: TDataMode read FMode;
    property File1: string read FFile1;
    property File2: string read FFile2;
    property PeakFile: string read FPeakFile;
    property SampleRate: Integer read FSampleRate;
    property TotalFrames: Int64 read FTotalFrames;
    property Version: Integer read GetVersion;
    function FindPeakRangeIndices(StartFrame, EndFrame: Int64; WindowMargin: Int64; out FirstIdx, LastIdx: Int64): Boolean;
    function ReadPeakEnvelope(StartFrame, EndFrame: Int64; MaxPoints: Integer; var Envelope: TWaveEnvelope): Boolean;
    function ReadPeakInfoRange(FirstIndex: Int64; Count: Int64; var Peaks: TPeakArray): Boolean;
    property PeakPositions: TArray<Int64> read GetPeakPositions;
  end;

implementation

procedure TEodGuiSession.CloseObjects;
begin
  FStore.Free;
  FStore := nil;
  FSource.Free;
  FSource := nil;
end;

destructor TEodGuiSession.Destroy;
begin
  CloseObjects;
  inherited;
end;

function TEodGuiSession.FindPeakRangeIndices(StartFrame, EndFrame, WindowMargin: Int64; out FirstIdx, LastIdx: Int64): Boolean;
var
  L, R, M: Int64;
  P: TPeak;
  StartPos: Int64;
  SearchStart, SearchEnd: Int64;
begin
  Result := False;
  FirstIdx := -1;
  LastIdx := -1;
  if FStore = nil then Exit;
  if FStore.Header.PeakCount <= 0 then Exit;
  SearchStart := Max(0, StartFrame - WindowMargin);
  SearchEnd := EndFrame + WindowMargin;

  L := 0;
  R := FStore.Header.PeakCount - 1;
  while L <= R do
  begin
    M := L + (R - L) div 2;
    if not FStore.ReadRecordInfo(M, P, StartPos) then Exit;
    if P.Position >= SearchStart then begin FirstIdx := M; R := M - 1 end
    else L := M + 1;
  end;
  if FirstIdx < 0 then FirstIdx := FStore.Header.PeakCount;

  L := 0;
  R := FStore.Header.PeakCount - 1;
  while L <= R do
  begin
    M := L + (R - L) div 2;
    if not FStore.ReadRecordInfo(M, P, StartPos) then Exit;
    if P.Position <= SearchEnd then begin LastIdx := M; L := M + 1 end
    else R := M - 1;
  end;
  Result := (FirstIdx >= 0) and (FirstIdx <= LastIdx);
end;

procedure TEodGuiSession.Close;
begin
  CloseObjects;
  FMode := dmNone;
  FFile1 := '';
  FFile2 := '';
  FPeakFile := '';
  FSampleRate := 0;
  FTotalFrames := 0;
  SetLength(FPeaks, 0);
end;

procedure TEodGuiSession.OpenWavPair(const File1, File2: string);
begin
  Close;
  FSource := TFourChannelAudioSource.Create(File1, File2);
  FFile1 := File1;
  FFile2 := File2;
  FSampleRate := FSource.SampleRate;
  FTotalFrames := FSource.TotalFrames;
  FMode := dmWav;
end;

procedure TEodGuiSession.OpenPeakFile(const FileName: string);
begin
  Close;
  FStore := TEodPeakStore.Open(FileName);
  FPeakFile := FileName;
  FSampleRate := FStore.Header.SampleRate;
  FTotalFrames := FStore.Header.TotalFrames;
  FMode := dmPeakFile;
end;

function TEodGuiSession.GetPeakPositions: TArray<Int64>;
var
  I: Int64;
  P: TPeak;
  StartFrame: Int64;
  Count: Int64;
begin
  SetLength(Result, 0);
  if FMode = dmWav then
  begin
    SetLength(Result, Length(FPeaks));
    for I := 0 to High(FPeaks) do
      Result[I] := FPeaks[I].Position;
    Exit;
  end;

  if (FMode <> dmPeakFile) or (FStore = nil) then Exit;
  Count := FStore.Header.PeakCount;
  if Count > MaxInt then
    raise ERangeError.Create('Too many peaks for a Delphi dynamic array');
  SetLength(Result, Integer(Count));
  for I := 0 to Count - 1 do
  begin
    if not FStore.ReadRecordInfo(I, P, StartFrame) then
    begin
      SetLength(Result, 0);
      Exit;
    end;
    Result[Integer(I)] := P.Position;
  end;
end;

function TEodGuiSession.GetVersion: Integer;
begin
  if FStore <> nil then Result := FStore.Header.Version else Result := 0;
end;

procedure TEodGuiSession.SetPeaks(const APeaks: TPeakArray);
begin
  FPeaks := Copy(APeaks);
end;

function TEodGuiSession.ReadSegment(StartFrame: Int64; Count: Integer; Pad: Boolean): TAudioChunk;
var
  SourceStart, SourceEnd, CopyCount, DestOffset: Int64;
  Temp: TAudioChunk;
  I: Integer;
begin
  SetLength(Result, 0);
  if Count <= 0 then Exit;
  if FMode = dmWav then
  begin
    if Pad then
    begin
      SetLength(Result, Count);
      SourceStart := Max(0, StartFrame);
      SourceEnd := Min(FSource.TotalFrames, StartFrame + Count);
      if SourceEnd <= SourceStart then Exit;
      CopyCount := SourceEnd - SourceStart;
      DestOffset := SourceStart - StartFrame;
      FSource.ReadFrames(SourceStart, Integer(CopyCount), Temp);
      for I := 0 to Integer(CopyCount) - 1 do Result[DestOffset + I] := Temp[I];
    end
    else FSource.ReadFrames(StartFrame, Count, Result);
    Exit;
  end;
  if FMode = dmPeakFile then raise Exception.Create('Arbitrary segment reading is not available from an EOD peak file');
  raise Exception.Create('No data source is open');
end;

function TEodGuiSession.ReadPeak(Index: Integer; out Peak: TPeak; out StartFrame: Int64): TAudioChunk;
begin
  if FMode <> dmPeakFile then raise Exception.Create('ReadPeak requires an EOD peak file');
  if not FStore.ReadRecord(Index, Peak, StartFrame, Result) then raise Exception.CreateFmt('Invalid peak index: %d', [Index]);
end;

function TEodGuiSession.ReadPeakInfoPage(PageIndex: Integer; var Peaks: TPeakArray): Boolean;
var FirstIdx, Count: Int64;
begin
  Result := False;
  if (FMode <> dmPeakFile) or (FStore = nil) then Exit;
  if not FStore.GetPageBounds(PageIndex, FirstIdx, Count) then Exit;
  Result := FStore.ReadRecordInfoPageInternal(FirstIdx, Count, Peaks);
end;

function TEodGuiSession.ReadPeakInfoRange(FirstIndex, Count: Int64; var Peaks: TPeakArray): Boolean;
var I: Int64; P: TPeak; StartFrame: Int64;
begin
  Result := False;
  SetLength(Peaks, 0);
  if (FStore = nil) or (FMode <> dmPeakFile) or (FirstIndex < 0) or (Count <= 0) then Exit;
  if FirstIndex >= FStore.Header.PeakCount then Exit;
  if Count > FStore.Header.PeakCount - FirstIndex then Count := FStore.Header.PeakCount - FirstIndex;
  if Count > MaxInt then Exit;
  SetLength(Peaks, Integer(Count));
  for I := 0 to Count - 1 do
  begin
    if not FStore.ReadRecordInfo(FirstIndex + I, P, StartFrame) then begin SetLength(Peaks, 0); Exit end;
    Peaks[Integer(I)] := P;
  end;
  Result := True;
end;

function TEodGuiSession.GetPeak(Index: Integer; out Peak: TPeak): Boolean;
var StartFrame: Int64;
begin
  Result := False;
  if (Index < 0) or (Index >= PeakCount) then Exit;
  if FMode = dmWav then begin Peak := FPeaks[Index]; Result := True; Exit end;
  if FMode = dmPeakFile then Result := FStore.ReadRecordInfo(Index, Peak, StartFrame);
end;

function TEodGuiSession.GetPeakPosition(Index: Integer): Int64;
var P: TPeak; StartFrame: Int64;
begin
  Result := -1;
  if (Index < 0) or (Index >= PeakCount) then Exit;
  if FMode = dmWav then Result := FPeaks[Index].Position
  else if (FMode = dmPeakFile) and FStore.ReadRecordInfo(Index, P, StartFrame) then Result := P.Position;
end;

function TEodGuiSession.CalculateStd(const Data: TAudioChunk): TFloatArray;
begin
  CalculateStdChunk(Data, Result);
end;

function TEodGuiSession.PeakCount: Integer;
begin
  if FMode = dmWav then Result := Length(FPeaks)
  else if (FMode = dmPeakFile) and (FStore <> nil) then
  begin
    if FStore.Header.PeakCount > MaxInt then raise ERangeError.Create('Peak count exceeds Integer API limit');
    Result := Integer(FStore.Header.PeakCount);
  end
  else Result := 0;
end;

procedure TEodGuiSession.SavePeakFile(const FileName: string);
begin
  if FMode = dmWav then TEodPeakStore.Save(FileName, FFile1, FFile2, FPeaks, 30, 30, True)
  else if FMode = dmPeakFile then TEodPeakStore.SaveFromStore(FileName, FStore, '', '', FTotalFrames)
  else raise Exception.Create('No data source is open');
end;

function TEodGuiSession.ReadPeakEnvelope(StartFrame, EndFrame: Int64; MaxPoints: Integer; var Envelope: TWaveEnvelope): Boolean;
var FirstIdx, LastIdx: Int64;
begin
  Result := False;
  SetLength(Envelope, 0);
  if FMode <> dmPeakFile then Exit;
  if not FindPeakRangeIndices(StartFrame, EndFrame, 0, FirstIdx, LastIdx) then Exit;
  Result := FStore.ReadEnvelope(FirstIdx, LastIdx, MaxPoints, Envelope);
end;

end.
