unit Eod.WavOpenThread;

interface

uses
  System.Classes, System.SysUtils, System.SyncObjs,
  Eod.GuiModel;

type
  TWavOpenProgressEvent = procedure(Sender: TObject; Stage: Integer;
    const Text: string) of object;
  TWavOpenFinishedEvent = procedure(Sender: TObject;
    Session: TEodGuiSession; Canceled: Boolean;
    const ErrorText: string) of object;

  TEodWavOpenThread = class(TThread)
  private
    FFile1: string;
    FFile2: string;
    FCancelEvent: TEvent;
    FSession: TEodGuiSession;
    FCanceled: Boolean;
    FErrorText: string;
    FStage: Integer;
    FStageText: string;
    FOnProgress: TWavOpenProgressEvent;
    FOnFinished: TWavOpenFinishedEvent;
    procedure DoProgress;
    procedure DoFinished;
    function CancelRequested: Boolean;
  protected
    procedure Execute; override;
  public
    constructor Create(const AFile1, AFile2: string);
    destructor Destroy; override;
    procedure Cancel;
    property OnProgress: TWavOpenProgressEvent read FOnProgress write FOnProgress;
    property OnFinished: TWavOpenFinishedEvent read FOnFinished write FOnFinished;
  end;

implementation

constructor TEodWavOpenThread.Create(const AFile1, AFile2: string);
begin
  inherited Create(True);
  FreeOnTerminate := True;
  FFile1 := AFile1;
  FFile2 := AFile2;
  FCancelEvent := TEvent.Create(nil, True, False, '');
end;

destructor TEodWavOpenThread.Destroy;
begin
  FSession.Free;
  FCancelEvent.Free;
  inherited;
end;

procedure TEodWavOpenThread.Cancel;
begin
  FCancelEvent.SetEvent;
end;

function TEodWavOpenThread.CancelRequested: Boolean;
begin
  Result := FCancelEvent.WaitFor(0) = wrSignaled;
end;

procedure TEodWavOpenThread.DoProgress;
begin
  if Assigned(FOnProgress) then
    FOnProgress(Self, FStage, FStageText);
end;

procedure TEodWavOpenThread.DoFinished;
var
  Session: TEodGuiSession;
begin
  Session := FSession;
  FSession := nil;
  if Assigned(FOnFinished) then
    FOnFinished(Self, Session, FCanceled, FErrorText)
  else
    Session.Free;
end;

procedure TEodWavOpenThread.Execute;
begin
  FCanceled := False;
  FErrorText := '';
  FSession := nil;

  try
    if CancelRequested then
    begin
      FCanceled := True;
      Exit;
    end;

    FStage := 5;
    FStageText := 'Preparing audio source';
    TThread.Synchronize(Self, DoProgress);

    if CancelRequested then
    begin
      FCanceled := True;
      Exit;
    end;

    FSession := TEodGuiSession.Create;

    FStage := 20;
    FStageText := 'Opening WAV files';
    TThread.Synchronize(Self, DoProgress);

    FSession.OpenWavPair(FFile1, FFile2);

    if CancelRequested then
    begin
      FCanceled := True;
      Exit;
    end;

    FStage := 70;
    FStageText := 'Checking audio parameters';
    TThread.Synchronize(Self, DoProgress);

    { Force the source metadata to be available before handing the session
      over to the main thread. No large audio buffer is created here. }
    if (FSession.SampleRate <= 0) or (FSession.TotalFrames <= 0) then
      raise Exception.Create('Invalid WAV source');

    FStage := 100;
    FStageText := 'WAV ready';
    TThread.Synchronize(Self, DoProgress);
  except
    on E: Exception do
    begin
      FErrorText := E.Message;
      FCanceled := CancelRequested;
    end;
  end;

  if CancelRequested then
    FCanceled := True;

  TThread.Synchronize(Self, DoFinished);
end;

end.
