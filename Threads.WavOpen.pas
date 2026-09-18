unit Threads.WavOpen;

interface

uses
  System.Classes, System.SysUtils,
  Threads.Base, GUI.Model;

type
  TEodWavProgressProc = procedure(AStage: Integer;
    const AStageText: string) of object;
  TEodWavOpenFinishedProc = procedure(ASession: TEodGuiSession;
    ACanceled: Boolean; const AErrorText: string) of object;

  TEodWavOpenThread = class(TEodBackgroundThread)
  private
    FFile1: string;
    FFile2: string;
    FSession: TEodGuiSession;
    FStage: Integer;
    FStageText: string;
    FOnProgress: TEodWavProgressProc;
    FOnFinished: TEodWavOpenFinishedProc;
  protected
    procedure RunTask; override;
    procedure DoProgress; override;
    procedure DoFinished; override;
  public
    constructor Create(const AFile1, AFile2: string;
      AOnProgress: TEodWavProgressProc;
      AOnFinished: TEodWavOpenFinishedProc);

    property Session: TEodGuiSession read FSession;
  end;

implementation

constructor TEodWavOpenThread.Create(const AFile1, AFile2: string;
  AOnProgress: TEodWavProgressProc;
  AOnFinished: TEodWavOpenFinishedProc);
begin
  inherited Create;
  FFile1 := AFile1;
  FFile2 := AFile2;
  FOnProgress := AOnProgress;
  FOnFinished := AOnFinished;
end;

procedure TEodWavOpenThread.RunTask;
begin
  FSession := nil;

  CheckCancel;

  FStage := 5;
  FStageText := 'Preparing audio source';
  TThread.Synchronize(Self, DoProgress);

  CheckCancel;

  FSession := TEodGuiSession.Create;

  FStage := 20;
  FStageText := 'Opening WAV files';
  TThread.Synchronize(Self, DoProgress);

  FSession.OpenWavPair(FFile1, FFile2);

  CheckCancel;

  FStage := 70;
  FStageText := 'Checking audio parameters';
  TThread.Synchronize(Self, DoProgress);

  { Метаданные должны быть доступны до передачи сессии в главный поток.
    Большой аудиобуфер здесь не создаётся. }
  if (FSession.SampleRate <= 0) or (FSession.TotalFrames <= 0) then
    raise Exception.Create('Invalid WAV source');

  FStage := 100;
  FStageText := 'WAV ready';
  TThread.Synchronize(Self, DoProgress);
end;

procedure TEodWavOpenThread.DoProgress;
begin
  if Assigned(FOnProgress) then
    FOnProgress(FStage, FStageText);
end;

procedure TEodWavOpenThread.DoFinished;
begin
  if Assigned(FOnFinished) then
    FOnFinished(FSession, FCanceled, FErrorText);
end;

end.
