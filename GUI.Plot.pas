unit GUI.Plot;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Math,
  FMX.Types, FMX.Objects, FMX.Graphics,
  Core.Types, System.Classes, System.Generics.Collections;

type
  TPlotMode = (
    pmRaw,
    pmStd,
    pmFir15,
    pmRawAndFir15,
    pmRaw4Channels,
    pmHistogram
  );

  TViewChangedEvent = procedure(Sender: TObject; ViewStart, ViewEnd: Int64) of object;

  TOverviewClickEvent = procedure(Sender: TObject; Frame: Int64) of object;

  TOverviewRangeSelectedEvent = procedure(Sender: TObject;
    AStart, AEnd: Int64) of object;

const
  { Цвета каналов 1..4 — те же, что использует основной график. }
  EodChannelColors: array[0..3] of TAlphaColor = (
    TAlphaColorRec.Red,
    TAlphaColorRec.Green,
    TAlphaColorRec.Blue,
    TAlphaColorRec.Orange);

type
  TOverviewPlot = class
  private
    FPaintBox: TPaintBox;

    FMinValues: TFloatArray;
    FMaxValues: TFloatArray;

    { Поканальные огибающие для режима "обзор в цветах каналов".
      Пустой массив = данных по каналу нет, канал не рисуется. }
    FChannelMin: TChannelEnvelopes;
    FChannelMax: TChannelEnvelopes;
    FShowChannelColors: Boolean;

    FFullStart: Int64;
    FFullEnd: Int64;

    FViewStart: Int64;
    FViewEnd: Int64;

    FOnClick: TOverviewClickEvent;
    FOnRangeSelected: TOverviewRangeSelectedEvent;

    { Drag-selection state }
    FDragging: Boolean;
    FDragIsSelection: Boolean;
    FDragStartX: Single;
    FDragStartFrame: Int64;
    FDragCurrentFrame: Int64;

    procedure PaintBoxPaint(Sender: TObject; Canvas: TCanvas);
    procedure PaintBoxMouseDown(Sender: TObject;
      Button: TMouseButton; Shift: TShiftState; X, Y: Single);
    procedure PaintBoxMouseMove(Sender: TObject;
      Shift: TShiftState; X, Y: Single);
    procedure PaintBoxMouseUp(Sender: TObject;
      Button: TMouseButton; Shift: TShiftState; X, Y: Single);

    function MapX(Frame: Int64; const R: TRectF): Single;
    function MapY(Value, MinY, MaxY: Double;
      const R: TRectF): Single;
    function XToFrame(X: Single; const R: TRectF): Int64;
    function GetPlotRect: TRectF;

    procedure SetShowChannelColors(AValue: Boolean);
    function GetHasChannelData: Boolean;
    procedure DrawChannelEnvelopes(Canvas: TCanvas; const R: TRectF);

  public
    constructor Create(APaintBox: TPaintBox);
    destructor Destroy; override;

    procedure Clear;

    procedure SetData(
      const AMinValues, AMaxValues: TFloatArray;
      AFullStart, AFullEnd: Int64);

    { Поканальные огибающие 4 каналов. Хранятся отдельно от общей
      огибающей из SetData, поэтому переключение ChannelColors не
      требует повторной подготовки данных. }
    procedure SetChannelData(
      const AMinValues, AMaxValues: TChannelEnvelopes;
      AFullStart, AFullEnd: Int64);

    procedure SetViewRange(AStart, AEnd: Int64);

    { Рисовать обзор поканально, в EodChannelColors. Если поканальных
      данных нет (HasChannelData = False), рисуется обычная огибающая. }
    property ChannelColors: Boolean
      read FShowChannelColors write SetShowChannelColors;

    property HasChannelData: Boolean read GetHasChannelData;

    property OnClick: TOverviewClickEvent read FOnClick write FOnClick;
    property OnRangeSelected: TOverviewRangeSelectedEvent
      read FOnRangeSelected write FOnRangeSelected;
  end;

  TSignalPlot = class
  private
    FPaintBox: TPaintBox;
    FData: TAudioChunk;
    FStd: TFloatArray;
    FFir: TFloatArray;
    FMode: TPlotMode;
    FStartFrame: Int64;
    FSampleRate: Integer;
    FSelectedOffset: Integer;
    FPeakOffset: Integer;
    FShowPeakLine: Boolean;
    FPeakPositions: TArray<Int64>;
    FTitle: string;
    FHistogramStart: Int64;
    FHistogramEnd: Int64;

    { Navigation }
    FFullStart: Int64;
    FFullEnd: Int64;
    FViewStart: Int64;
    FViewEnd: Int64;
    FMaxView: Int64;
    FDragging: Boolean;
    FDragStartX: Single;
    FDragStartViewStart: Int64;
    FDragStartViewEnd: Int64;
    FLastMouseX: Single;
    FEnvelope: TWaveEnvelope;
    FEnvelopeActive: Boolean;

    FOnViewChanged : TViewChangedEvent;

    procedure DrawEnvelope4Channels(
      Canvas: TCanvas;
      const R: TRectF);
    procedure DrawEnvelopeSingle(
      Canvas: TCanvas;
      const R: TRectF);

    procedure PaintBoxPaint(Sender: TObject; Canvas: TCanvas);
    procedure PaintBoxMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Single);
    procedure PaintBoxMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Single);
    procedure PaintBoxMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Single);
    procedure PaintBoxMouseWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer; var Handled: Boolean);

    procedure DrawGrid(Canvas: TCanvas; const R: TRectF;
      MinY, MaxY: Double; const XStart, XEnd: Int64);
    procedure DrawHorizontalGrid(Canvas: TCanvas; const R: TRectF;
      MinY, MaxY: Double);
    procedure DrawVerticalGrid(Canvas: TCanvas; const R: TRectF);
    procedure DrawYAxisLabels(Canvas: TCanvas; const R: TRectF;
      MinY, MaxY: Double);
    procedure DrawXAxisLabels(Canvas: TCanvas; const R: TRectF;
      Count: Integer);
    procedure DrawXAxisLabelsAbsolute(Canvas: TCanvas; const R: TRectF;
      XStart, XEnd: Int64);
    function MapX(Index, Count: Integer; const R: TRectF): Single;
    function MapY(Value, MinY, MaxY: Double; const R: TRectF): Single;
    procedure RequestRepaint;
    function FormatAxisValue(V: Double): string;
    procedure DrawRaw(Canvas: TCanvas; const R: TRectF;
      MinY, MaxY: Double);
    procedure DrawRaw4Channels(Canvas: TCanvas; const R: TRectF);
    procedure DrawHistogram(Canvas: TCanvas; const R: TRectF);
    procedure DrawScalar(Canvas: TCanvas; const R: TRectF;
      const Values: TFloatArray; MinY, MaxY: Double);
    procedure DrawRawAndFir(Canvas: TCanvas; const R: TRectF;
      MinY, MaxY: Double);
    procedure UpdatePeakOffset(PeakFrame: Int64);
    procedure ClampView;
    procedure DoViewChanged;
    function ViewWidth: Int64;
  public
    constructor Create(APaintBox: TPaintBox);
    destructor Destroy; override;
    procedure ClearData;
    procedure SetChannels(const Data: TAudioChunk; StartFrame: Int64;
      SampleRate: Integer; PeakFrame: Int64 = -1;
      const ATitle: string = '');
    procedure SetStd(const Data: TFloatArray; StartFrame: Int64;
      SampleRate: Integer; PeakFrame: Int64 = -1;
      const ATitle: string = '');
    procedure SetFir(const Data: TFloatArray; StartFrame: Int64;
      SampleRate: Integer; PeakFrame: Int64 = -1;
      const ATitle: string = '');
    procedure SetMode(AMode: TPlotMode);
    function GetMode: TPlotMode;
    procedure SetPeakPositions(const Positions: array of Int64);
    procedure SetSelectedPosition(AFrame: Int64);
    procedure SetHistogramRange(StartFrame, EndFrame: Int64);
    procedure SetFullRange(AStart, AEnd: Int64);
    procedure SetMaxViewSamples(AValue: Int64);
    procedure SetViewRange(AStart, AEnd: Int64);
    procedure GetViewRange(out AStart, AEnd: Int64);
    function ViewSampleCount: Int64;
    procedure ZoomAt(AX: Single; AFactor: Double);
    procedure PanByPixels(ADeltaX: Single);
    property OnViewChanged: TViewChangedEvent read FOnViewChanged write FOnViewChanged;
    procedure SetEnvelope(const Envelope: TWaveEnvelope; StartFrame, EndFrame: Int64; SampleRate: Integer;
  const ATitle: string = '');
  end;

const
  MinViewSamples = 10;
  MaxViewSamples = 2000000;
  EnvelopeResolutionLimit = 10000;
implementation
