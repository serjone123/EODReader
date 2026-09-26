unit Threads.OverviewBase;

{ Общий предок потоков построения обзорной огибающей:
  TEodOverviewThread (Threads.Overview — из WAV) и TEodPeakOverviewThread
  (Threads.PeakOverview — из кэша .eodpk).

  Берёт на себя всё, что у них совпадало: число точек обзора, поля
  результата (общая и поканальная огибающие, число кадров, прогресс),
  события OnProgress/OnFinished и их вызов в главном потоке. В наследниках
  остаются конструктор и RunTask — сами алгоритмы построения бинов у
  источников принципиально разные.

  Отмену, тексты ошибок и гарантированный вызов DoFinished (в главном
  потоке, из finally) обеспечивает TEodBackgroundThread. Наследник обязан
  освободить свой источник данных (файл WAV, хранилище .eodpk) ДО выхода
  из RunTask: DoFinished вызывается уже после этого, и форма может сразу
  переоткрыть тот же файл. }

interface

uses
  Core.Types, Threads.Base;

type
  TOverviewProgressEvent = procedure(Sender: TObject;
    Processed, Total: Int64) of object;

  TOverviewFinishedEvent = procedure(Sender: TObject;
    const OverviewMin, OverviewMax: TFloatArray;
    const ChannelMin, ChannelMax: TChannelEnvelopes;
    TotalFrames: Int64; Canceled: Boolean;
    const ErrorText: string) of object;

  TEodOverviewBaseThread = class(TEodBackgroundThread)
  protected
    { Число бинов обзора; значение меньше 1 приводится к 1. }
    FPoints: Integer;

    { Результат: общая огибающая и поканальные min/max (индекс 0..3 —
      канал 1..4), число кадров записи, сколько кадров обработано. }
    FOverviewMin: TFloatArray;
    FOverviewMax: TFloatArray;
    FChannelMin: TChannelEnvelopes;
    FChannelMax: TChannelEnvelopes;
    FTotalFrames: Int64;
    FProcessed: Int64;

    FOnProgress: TOverviewProgressEvent;
    FOnFinished: TOverviewFinishedEvent;

    { Обнуляет результат и счётчики; вызывается первой строкой RunTask. }
    procedure ResetResult;

    procedure DoProgress; override;
    procedure DoFinished; override;
  public
    constructor Create(APoints: Integer);

    property OnProgress: TOverviewProgressEvent
      read FOnProgress write FOnProgress;
    property OnFinished: TOverviewFinishedEvent
      read FOnFinished write FOnFinished;
  end;

implementation

constructor TEodOverviewBaseThread.Create(APoints: Integer);
begin
  inherited Create;
  FPoints := APoints;
  if FPoints < 1 then
    FPoints := 1;
end;

procedure TEodOverviewBaseThread.ResetResult;
var
  Ch: Integer;
begin
  FProcessed := 0;
  FTotalFrames := 0;
  SetLength(FOverviewMin, 0);
  SetLength(FOverviewMax, 0);
  for Ch := 0 to 3 do
  begin
    SetLength(FChannelMin[Ch], 0);
    SetLength(FChannelMax[Ch], 0);
  end;
end;

procedure TEodOverviewBaseThread.DoProgress;
begin
  if Assigned(FOnProgress) then
    FOnProgress(Self, FProcessed, FTotalFrames);
end;

procedure TEodOverviewBaseThread.DoFinished;
begin
  if Assigned(FOnFinished) then
    FOnFinished(Self, FOverviewMin, FOverviewMax,
      FChannelMin, FChannelMax, FTotalFrames, FCanceled, FErrorText);
end;

end.
