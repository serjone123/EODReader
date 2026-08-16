program ReadEOD;

uses
  System.StartUpCopy,
  FMX.Forms,
  uReadWavMain in 'uReadWavMain.pas' {MainForm},
  Eod.Types in 'Eod.Types.pas',
  Eod.WavReader in 'Eod.WavReader.pas',
  Eod.Fir15 in 'Eod.Fir15.pas',
  Eod.Correlation in 'Eod.Correlation.pas',
  Eod.Peaks in 'Eod.Peaks.pas',
  Eod.Statistics in 'Eod.Statistics.pas',
  Eod.Templates in 'Eod.Templates.pas',
  Eod.AudioSource in 'Eod.AudioSource.pas',
  Eod.Classifier in 'Eod.Classifier.pas',
  Eod.Detector in 'Eod.Detector.pas',
  Eod.GuiModel in 'Eod.GuiModel.pas',
  Eod.GuiPlot in 'Eod.GuiPlot.pas',
  Eod.PeakStore in 'Eod.PeakStore.pas',
  Eod.SignalCache in 'Eod.SignalCache.pas',
  Eod.AnalysisThread in 'Eod.AnalysisThread.pas',
  Eod.WavOpenThread in 'Eod.WavOpenThread.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
