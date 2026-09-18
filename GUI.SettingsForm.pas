unit GUI.SettingsForm;

{ A small modal dialog that lets the user edit the previously-hardcoded
  TEodDetectorConfig fields. Built entirely in code (no .fmx resource),
  so it drops into the project with just this unit added to the .dpr. }

interface

uses
  System.SysUtils, System.UITypes, System.Types, System.Classes,
  FMX.Types, FMX.Forms, FMX.StdCtrls, FMX.Edit, FMX.Layouts, FMX.Controls,
  Core.Types;

type
  TEodSettingsForm = class(TForm)
  private
    FConfig: TEodDetectorConfig;
    FResultConfig: TEodDetectorConfig;
    FAccepted: Boolean;

    FEdProminence: TEdit;
    FEdThreshold: TEdit;
    FEdWindowBefore: TEdit;
    FEdWindowAfter: TEdit;
    FEdChunkSize: TEdit;
    FEdDuplicateDistance: TEdit;
    FErrorLabel: TLabel;

    procedure BuildUI;
    function AddRow(var Y: Single; const Caption, InitialValue: string): TEdit;
    procedure OkClick(Sender: TObject);
    procedure CancelClick(Sender: TObject);
    function TryReadConfig(out AConfig: TEodDetectorConfig;
      out ErrorMsg: string): Boolean;
  public
    constructor CreateWithConfig(AOwner: TComponent;
      const AConfig: TEodDetectorConfig); reintroduce;

    { Shows the dialog modally. Returns True and fills AConfig if the
      user pressed OK with valid values; returns False (AConfig
      untouched) if the user cancelled. }
    function Execute(out AConfig: TEodDetectorConfig): Boolean;
  end;

implementation

uses
  System.Math;

constructor TEodSettingsForm.CreateWithConfig(AOwner: TComponent;
  const AConfig: TEodDetectorConfig);
begin
  inherited CreateNew(AOwner);
  FConfig := AConfig;
  FAccepted := False;

  Caption := 'Detector settings';
  Width := 380;
  Height := 330;
  Position := TFormPosition.OwnerFormCenter;
  BorderStyle := TFmxFormBorderStyle.Single;

  BuildUI;
end;

function TEodSettingsForm.AddRow(var Y: Single; const Caption,
  InitialValue: string): TEdit;
var
  Lbl: TLabel;
begin
  Lbl := TLabel.Create(Self);
  Lbl.Parent := Self;
  Lbl.Position.X := 12;
  Lbl.Position.Y := Y;
  Lbl.Width := 190;
  Lbl.Height := 22;
  Lbl.Text := Caption;

  Result := TEdit.Create(Self);
  Result.Parent := Self;
  Result.Position.X := 210;
  Result.Position.Y := Y;
  Result.Width := 150;
  Result.Height := 24;
  Result.Text := InitialValue;

  Y := Y + 30;
end;

procedure TEodSettingsForm.BuildUI;
var
  Y: Single;
  BtnOk, BtnCancel: TButton;
  FmtSettings: TFormatSettings;
begin
  FmtSettings := TFormatSettings.Invariant;
  Y := 16;

  FEdProminence := AddRow(Y, 'Peak prominence',
    FloatToStr(FConfig.PeakProminence, FmtSettings));
  FEdThreshold := AddRow(Y, 'Correlation threshold',
    FloatToStr(FConfig.CorrelationThreshold, FmtSettings));
  FEdWindowBefore := AddRow(Y, 'Window before (samples)',
    IntToStr(FConfig.WindowBefore));
  FEdWindowAfter := AddRow(Y, 'Window after (samples)',
    IntToStr(FConfig.WindowAfter));
  FEdChunkSize := AddRow(Y, 'Analysis chunk size',
    IntToStr(FConfig.ChunkSize));
  FEdDuplicateDistance := AddRow(Y, 'Duplicate distance (samples)',
    IntToStr(FConfig.DuplicateDistance));

  FErrorLabel := TLabel.Create(Self);
  FErrorLabel.Parent := Self;
  FErrorLabel.Position.X := 12;
  FErrorLabel.Position.Y := Y + 4;
  FErrorLabel.Width := 350;
  FErrorLabel.Height := 40;
  FErrorLabel.TextSettings.FontColor := TAlphaColorRec.Firebrick;
  FErrorLabel.Text := '';

  BtnOk := TButton.Create(Self);
  BtnOk.Parent := Self;
  BtnOk.Position.X := 190;
  BtnOk.Position.Y := Y + 50;
  BtnOk.Width := 80;
  BtnOk.Height := 26;
  BtnOk.Text := 'OK';
  BtnOk.OnClick := OkClick;

  BtnCancel := TButton.Create(Self);
  BtnCancel.Parent := Self;
  BtnCancel.Position.X := 280;
  BtnCancel.Position.Y := Y + 50;
  BtnCancel.Width := 80;
  BtnCancel.Height := 26;
  BtnCancel.Text := 'Cancel';
  BtnCancel.OnClick := CancelClick;
end;

function TEodSettingsForm.TryReadConfig(out AConfig: TEodDetectorConfig;
  out ErrorMsg: string): Boolean;
var
  FmtSettings: TFormatSettings;
  DProminence, DThreshold: Double;
  IWindowBefore, IWindowAfter, IChunkSize: Integer;
  IDuplicateDistance: Int64;
begin
  Result := False;
  ErrorMsg := '';
  FmtSettings := TFormatSettings.Invariant;
  AConfig := FConfig;

  if not TryStrToFloat(FEdProminence.Text.Replace(',', '.'), DProminence, FmtSettings)
    or (DProminence < 0) then
  begin
    ErrorMsg := 'Peak prominence must be a non-negative number.';
    Exit;
  end;

  if not TryStrToFloat(FEdThreshold.Text.Replace(',', '.'), DThreshold, FmtSettings)
    or (DThreshold < 0) or (DThreshold > 1) then
  begin
    ErrorMsg := 'Correlation threshold must be between 0 and 1.';
    Exit;
  end;

  if not TryStrToInt(FEdWindowBefore.Text, IWindowBefore) or (IWindowBefore < 0) then
  begin
    ErrorMsg := 'Window before must be a non-negative integer.';
    Exit;
  end;

  if not TryStrToInt(FEdWindowAfter.Text, IWindowAfter) or (IWindowAfter < 0) then
  begin
    ErrorMsg := 'Window after must be a non-negative integer.';
    Exit;
  end;

  if not TryStrToInt(FEdChunkSize.Text, IChunkSize) or (IChunkSize < 1024) then
  begin
    ErrorMsg := 'Chunk size must be an integer >= 1024.';
    Exit;
  end;

  if not TryStrToInt64(FEdDuplicateDistance.Text, IDuplicateDistance)
    or (IDuplicateDistance < 0) then
  begin
    ErrorMsg := 'Duplicate distance must be a non-negative integer.';
    Exit;
  end;

  AConfig.PeakProminence := DProminence;
  AConfig.CorrelationThreshold := DThreshold;
  AConfig.WindowBefore := IWindowBefore;
  AConfig.WindowAfter := IWindowAfter;
  AConfig.ChunkSize := IChunkSize;
  AConfig.DuplicateDistance := IDuplicateDistance;
  { ExtractionBefore/After are not exposed here yet; keep the
    previous/default values. }

  Result := True;
end;

procedure TEodSettingsForm.OkClick(Sender: TObject);
var
  NewConfig: TEodDetectorConfig;
  ErrorMsg: string;
begin
  if not TryReadConfig(NewConfig, ErrorMsg) then
  begin
    FErrorLabel.Text := ErrorMsg;
    Exit;
  end;

  FResultConfig := NewConfig;
  FAccepted := True;
  ModalResult := mrOk;
  Close;
end;

procedure TEodSettingsForm.CancelClick(Sender: TObject);
begin
  FAccepted := False;
  ModalResult := mrCancel;
  Close;
end;

function TEodSettingsForm.Execute(out AConfig: TEodDetectorConfig): Boolean;
begin
  { This app targets desktop platforms (Win32/Win64/Linux64), where the
    classic blocking ShowModal is supported. }
  ShowModal;

  Result := FAccepted;
  if Result then
    AConfig := FResultConfig;
end;

end.
