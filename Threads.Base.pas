unit Threads.Base;

interface

uses
  System.Classes, System.SyncObjs, System.SysUtils, Core.Log;

type
  { Базовый класс для фоновых воркеров GUI.
    Берёт на себя общий boilerplate: событие отмены, тексты ошибок
    и гарантированный вызов DoFinished в finally при любом сценарии
    (нормальное завершение, Exit, отмена, исключение).

    Потомок переопределяет:
      RunTask     — вся предметная работа; может бросать исключения
                    или вызывать CheckCancel;
      DoFinished  — уведомление владельца о завершении (вызывается
                    через TThread.Synchronize в главном потоке);
      DoProgress  — по желанию, уведомление о прогрессе. }
  TEodBackgroundThread = class(TThread)
  private
    FCancelEvent: TEvent;
    function GetCancelRequested: Boolean;
  protected
    FCanceled: Boolean;
    FErrorText: string;

    procedure RunTask; virtual; abstract;
    procedure DoFinished; virtual; abstract;
    procedure DoProgress; virtual;

    { Кидает EAbort, если запрошена отмена. Вызывается из RunTask. }
    procedure CheckCancel;

    property CancelRequested: Boolean read GetCancelRequested;

    procedure Execute; override;

  public
    constructor Create;
    destructor Destroy; override;

    { Устанавливает событие отмены. Безопасно вызывать из любого потока. }
    procedure Cancel;
  end;

implementation

constructor TEodBackgroundThread.Create;
begin
  inherited Create(True);
  FreeOnTerminate := True;
  FCancelEvent := TEvent.Create(nil, True, False, '');
end;

destructor TEodBackgroundThread.Destroy;
begin
  FCancelEvent.Free;
  inherited;
end;

procedure TEodBackgroundThread.Cancel;
begin
  if Assigned(FCancelEvent) then
    FCancelEvent.SetEvent;
end;

function TEodBackgroundThread.GetCancelRequested: Boolean;
begin
  Result := Assigned(FCancelEvent) and (FCancelEvent.WaitFor(0) = wrSignaled);
end;

procedure TEodBackgroundThread.CheckCancel;
begin
  if CancelRequested then
    Abort
end;

procedure TEodBackgroundThread.DoProgress;
begin
  { по умолчанию ничего не делаем }
end;

procedure TEodBackgroundThread.Execute;
begin
  FCanceled := False;
  FErrorText := '';
  LogWrite(ClassName + ': старт');
  try
    try
      RunTask;
    except
      on EAbort do
        FCanceled := True;
      on E: Exception do
      begin
        { С классом исключения: по одному тексту не отличить
          EOutOfMemory / EAccessViolation / EReadError. }
        FErrorText := E.ClassName + ': ' + E.Message;
        FCanceled := CancelRequested;
        LogWrite(ClassName + ': ошибка — ' + FErrorText);
      end;
    end;
  finally
    if CancelRequested then
      FCanceled := True;
    LogWriteFmt('%s: завершение, отменено=%s, ошибка="%s"',
      [ClassName, BoolToStr(FCanceled, True), FErrorText]);
    try
      TThread.Synchronize(Self, DoFinished);
    except
      on E: Exception do
      begin
        { Исключение из обработчика владельца иначе осело бы в
          FatalException потока и пропало — передаём его в главный поток. }
        var Msg := E.Message;
        TThread.Queue(nil,
          procedure
          begin
            raise Exception.Create(Msg);
          end);
      end;
    end;
  end;
end;

end.
