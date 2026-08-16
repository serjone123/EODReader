unit Eod.GuiModel;

interface

uses
  System.SysUtils, System.Classes, System.Math,
  Eod.Types, Eod.Detector, Eod.PeakStore, Eod.AudioSource, Eod.Statistics;

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
    FPeaks: TPeakArray;            // used only for dmWav
    FPeakPositions: TArray<Int64>; // lazy-loaded cache for dmPeakFile
    FPeakPositionsLoaded: Boolean;
    FSampleRate: Integer;
    FTotalFrames: Int64;
    procedure CloseObjects;
    procedure LoadPeakPositions;
    function GetPeakPositions: TArray<Int64>;
    function GetVersion: integer;
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
    function FindPeakRangeIndices(StartFrame, EndFrame: Int64; WindowMargin: Integer; out FirstIdx, LastIdx: Integer): Boolean;
    function CalculateStd(const Data: TAudioChunk): TFloatArray;
    function PeakCount: Integer;
    procedure SavePeakFile(const FileName: string);
    property Mode: TDataMode read FMode;
    property File1: string read FFile1;
    property File2: string read FFile2;
    property PeakFile: string read FPeakFile;
    property SampleRate: Integer read FSampleRate;
    property TotalFrames: Int64 read FTotalFrames;
    property PeakPositions: TArray<Int64> read GetPeakPositions;
    property Version: integer read GetVersion;
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
  SetLength(FPeakPositions, 0);
  FPeakPositionsLoaded := False;
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
var
  P: TPeak;
  StartFrame: Int64;
begin
  Close;
  FStore := TEodPeakStore.Open(FileName);
  FPeakFile := FileName;
  FSampleRate := FStore.Header.SampleRate;
  FTotalFrames := FStore.Header.TotalFrames;

  if (FStore.Header.Version = EODPK_VERSION_1) and
     (FStore.Header.PeakCount > 0) then
  begin
    if FStore.ReadRecordInfo(FStore.Header.PeakCount - 1, P, StartFrame) then
      FTotalFrames := P.Position + 1;
  end;

  FMode := dmPeakFile;
end;

procedure TEodGuiSession.LoadPeakPositions;
var
  PageIndex, I: Integer;
  Peaks: TPeakArray;
  FirstIdx, Count: Int64;
begin
  if FPeakPositionsLoaded then
    Exit;
  if FMode <> dmPeakFile then
    Exit;
  if FStore = nil then
    Exit;

  SetLength(FPeakPositions, FStore.Header.PeakCount);

  for PageIndex := 0 to FStore.PageCount - 1 do
  begin
    if not FStore.GetPageBounds(PageIndex, FirstIdx, Count) then
      Continue;
    if not FStore.ReadRecordInfoPageInternal(FirstIdx, Count, Peaks) then
      Continue;
    for I := 0 to High(Peaks) do
      FPeakPositions[FirstIdx + I] := Peaks[I].Position;
  end;

  FPeakPositionsLoaded := True;
end;

function TEodGuiSession.GetPeakPositions: TArray<Int64>;
var
  I: Integer;
begin
  if FMode = dmWav then
  begin
    SetLength(Result, Length(FPeaks));
    for I := 0 to High(FPeaks) do
      Result[I] := FPeaks[I].Position;
    Exit;
  end;

  if FMode = dmPeakFile then
  begin
    LoadPeakPositions;
    Result := Copy(FPeakPositions);
    Exit;
  end;

  SetLength(Result, 0);
end;

function TEodGuiSession.GetVersion: integer;
begin
    result:= FStore.Header.Version
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
      SourceStart := StartFrame;
      SourceEnd := StartFrame + Count;
      if SourceStart < 0 then SourceStart := 0;
      if SourceEnd > FSource.TotalFrames then SourceEnd := FSource.TotalFrames;
      if SourceEnd <= SourceStart then Exit;
      CopyCount := SourceEnd - SourceStart;
      DestOffset := SourceStart - StartFrame;
      FSource.ReadFrames(SourceStart, Integer(CopyCount), Temp);
      for I := 0 to Integer(CopyCount) - 1 do
        Result[DestOffset + I] := Temp[I];
    end
    else
      FSource.ReadFrames(StartFrame, Count, Result);
    Exit;
  end;

  if FMode = dmPeakFile then
    raise Exception.Create('Arbitrary segment reading is not available from an EOD peak file');

  raise Exception.Create('No data source is open');
end;

function TEodGuiSession.ReadPeak(Index: Integer; out Peak: TPeak; out StartFrame: Int64): TAudioChunk;
begin
  if FMode <> dmPeakFile then
    raise Exception.Create('ReadPeak requires an EOD peak file');
  if not FStore.ReadRecord(Index, Peak, StartFrame, Result) then
    raise Exception.CreateFmt('Invalid peak index: %d', [Index]);
end;

function TEodGuiSession.ReadPeakInfoPage(PageIndex: Integer; var Peaks: TPeakArray): Boolean;
var
  FirstIdx, Count: Int64;
begin
  Result := False;
  if FMode <> dmPeakFile then
    Exit;
  if FStore = nil then
    Exit;
  if not FStore.GetPageBounds(PageIndex, FirstIdx, Count) then
    Exit;
  Result := FStore.ReadRecordInfoPageInternal(FirstIdx, Count, Peaks);
end;

function TEodGuiSession.GetPeak(Index: Integer; out Peak: TPeak): Boolean;
var
  StartFrame: Int64;
begin
  Result := False;
  if (Index < 0) or (Index >= PeakCount) then
    Exit;

  if FMode = dmWav then
  begin
    Peak := FPeaks[Index];
    Result := True;
    Exit;
  end;

  if FMode = dmPeakFile then
  begin
    if FStore = nil then Exit;
    Result := FStore.ReadRecordInfo(Index, Peak, StartFrame);
  end;
end;

function TEodGuiSession.GetPeakPosition(Index: Integer): Int64;
var
  P: TPeak;
  StartFrame: Int64;
begin
  Result := -1;
  if (Index < 0) or (Index >= PeakCount) then
    Exit;

  if FMode = dmWav then
  begin
    Result := FPeaks[Index].Position;
    Exit;
  end;

  if FMode = dmPeakFile then
  begin
    if FStore = nil then Exit;
    if FPeakPositionsLoaded and (Index < Length(FPeakPositions)) then
    begin
      Result := FPeakPositions[Index];
      Exit;
    end;
    if FStore.ReadRecordInfo(Index, P, StartFrame) then
      Result := P.Position;
  end;
end;

function TEodGuiSession.FindPeakRangeIndices(StartFrame, EndFrame: Int64; WindowMargin: Integer; out FirstIdx, LastIdx: Integer): Boolean;
var
  Positions: TArray<Int64>;
  L, R, M: Integer;
  SearchStart, SearchEnd: Int64;
begin
  Result := False;
  FirstIdx := -1;
  LastIdx := -1;

  if PeakCount = 0 then
    Exit;

  Positions := PeakPositions;
  if Length(Positions) = 0 then
    Exit;

  SearchStart := StartFrame - WindowMargin;
  SearchEnd := EndFrame + WindowMargin;

  L := 0;
  R := High(Positions);
  while L <= R do
  begin
    M := (L + R) div 2;
    if Positions[M] >= SearchStart then
    begin
      FirstIdx := M;
      R := M - 1;
    end
    else
      L := M + 1;
  end;
  if FirstIdx < 0 then
    FirstIdx := Length(Positions);

  L := 0;
  R := High(Positions);
  while L <= R do
  begin
    M := (L + R) div 2;
    if Positions[M] <= SearchEnd then
    begin
      LastIdx := M;
      L := M + 1;
    end
    else
      R := M - 1;
  end;

  Result := (FirstIdx <= LastIdx) and (LastIdx >= 0) and (FirstIdx < Length(Positions));
end;

function TEodGuiSession.CalculateStd(const Data: TAudioChunk): TFloatArray;
begin
  CalculateStdChunk(Data, Result);
end;

function TEodGuiSession.PeakCount: Integer;
begin
  if FMode = dmWav then
    Result := Length(FPeaks)
  else if (FMode = dmPeakFile) and (FStore <> nil) then
    Result := Integer(FStore.Header.PeakCount)
  else
    Result := 0;
end;

procedure TEodGuiSession.SavePeakFile(const FileName: string);
var
  LastPeak: TPeak;
  StartFrame: Int64;
  TotalFrames: Int64;
begin
  if FMode = dmWav then
  begin
    TEodPeakStore.Save(FileName, FFile1, FFile2, FPeaks, 30, 30, True);
    Exit;
  end;

  if FMode = dmPeakFile then
  begin
    TotalFrames := FTotalFrames;
    if (FStore.Header.Version = EODPK_VERSION_1) and
       (FStore.Header.PeakCount > 0) then
    begin
      if FStore.ReadRecordInfo(FStore.Header.PeakCount - 1, LastPeak, StartFrame) then
        TotalFrames := Max(TotalFrames, LastPeak.Position + 1);
    end;

    TEodPeakStore.SaveFromStore(FileName, FStore, '', '', TotalFrames);
    Exit;
  end;

  raise Exception.Create('No data source is open');
end;

end.
