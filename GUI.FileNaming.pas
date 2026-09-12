unit GUI.FileNaming;

interface

uses
  System.SysUtils;

function TryGetPairedWavFileName(const AFileName: string;
  out APairedFileName: string): Boolean;
function GetEodBaseName(const AFileName: string): string;
function GetSuggestedEodPeakFileName(const AFileName: string): string;

implementation

function TryGetPairedWavFileName(const AFileName: string;
  out APairedFileName: string): Boolean;
var
  DirName: string;
  BaseName: string;
  ExtName: string;
  SuffixPos: Integer;
begin
  APairedFileName := '';
  Result := False;

  if AFileName = '' then
    Exit;

  DirName := ExtractFilePath(AFileName);
  BaseName := ChangeFileExt(ExtractFileName(AFileName), '');
  ExtName := ExtractFileExt(AFileName);

  if not SameText(ExtName, '.wav') then
    Exit;

  SuffixPos := Pos('_Tr12', BaseName);
  if (SuffixPos > 0) and
     (SuffixPos + Length('_Tr12') - 1 = Length(BaseName)) then
  begin
    Delete(BaseName, SuffixPos, Length('_Tr12'));
    APairedFileName := DirName + BaseName + '_Tr34' + ExtName;
    Result := True;
    Exit;
  end;

  SuffixPos := Pos('_Tr34', BaseName);
  if (SuffixPos > 0) and
     (SuffixPos + Length('_Tr34') - 1 = Length(BaseName)) then
  begin
    Delete(BaseName, SuffixPos, Length('_Tr34'));
    APairedFileName := DirName + BaseName + '_Tr12' + ExtName;
    Result := True;
  end;
end;

function GetEodBaseName(const AFileName: string): string;
var
  BaseName: string;
  SuffixPos: Integer;
begin
  BaseName := ChangeFileExt(ExtractFileName(AFileName), '');

  SuffixPos := Pos('_Tr12', BaseName);
  if (SuffixPos > 0) and
     (SuffixPos + Length('_Tr12') - 1 = Length(BaseName)) then
    Delete(BaseName, SuffixPos, Length('_Tr12'))
  else
  begin
    SuffixPos := Pos('_Tr34', BaseName);
    if (SuffixPos > 0) and
       (SuffixPos + Length('_Tr34') - 1 = Length(BaseName)) then
      Delete(BaseName, SuffixPos, Length('_Tr34'));
  end;

  Result := BaseName;
end;

function GetSuggestedEodPeakFileName(const AFileName: string): string;
begin
  Result := GetEodBaseName(AFileName) + '.eodpk';
end;

end.
