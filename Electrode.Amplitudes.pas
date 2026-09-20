unit Electrode.Amplitudes;

{$IFDEF FPC}
  {$MODE DELPHI}
  {$H+}
{$ENDIF}

{ Извлечение амплитуд одного EOD-события по каждому из 4 каналов из окна
  сырого сигнала вокруг события. Амплитуды подаются на вход локализации
  (Electrode.Matching / Electrode.Localization). }

interface

uses
{$IFDEF FPC}
  Math,
{$ELSE}
  System.Math,
{$ENDIF}
  Core.Types, Electrode.Matching;

{ Амплитуда канала = значение сигнала (со знаком) в кадре окна, где
  |сигнал| этого канала максимален по модулю. Каналы берутся независимо:
  на физическое событие все каналы отвечают почти одновременно, а лёгкие
  временные сдвиги прихода волны к разным электродам для амплитудной
  модели несущественны. Если окно пустое — возвращает все нули. }
function ExtractEventAmplitudes(const Data: TAudioChunk): TChannelAmplitudes;

implementation

function ExtractEventAmplitudes(const Data: TAudioChunk): TChannelAmplitudes;
var
  I: Integer;
  V: Double;
begin
  Result[0] := 0;
  Result[1] := 0;
  Result[2] := 0;
  Result[3] := 0;

  for I := 0 to High(Data) do
  begin
    V := Data[I].Ch1;
    if Abs(V) > Abs(Result[0]) then
      Result[0] := V;
    V := Data[I].Ch2;
    if Abs(V) > Abs(Result[1]) then
      Result[1] := V;
    V := Data[I].Ch3;
    if Abs(V) > Abs(Result[2]) then
      Result[2] := V;
    V := Data[I].Ch4;
    if Abs(V) > Abs(Result[3]) then
      Result[3] := V;
  end;
end;

end.