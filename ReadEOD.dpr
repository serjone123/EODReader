program ReadEOD;

uses
  System.StartUpCopy,
  FMX.Forms,
  uReadWavMain in 'uReadWavMain.pas' {MainForm},
  Core.Types in 'Core.Types.pas',
  IO.WavReader in 'IO.WavReader.pas',
  Signal.Fir15 in 'Signal.Fir15.pas',
  Detection.Correlation in 'Detection.Correlation.pas',
  Signal.Peaks in 'Signal.Peaks.pas',
  Signal.Statistics in 'Signal.Statistics.pas',
  Detection.Templates in 'Detection.Templates.pas',
  IO.AudioSource in 'IO.AudioSource.pas',
  Detection.Classifier in 'Detection.Classifier.pas',
  Detection.Detector in 'Detection.Detector.pas',
  GUI.Model in 'GUI.Model.pas',
  GUI.Plot in 'GUI.Plot.pas',
  IO.PeakStore in 'IO.PeakStore.pas',
  IO.SignalCache in 'IO.SignalCache.pas',
  Threads.Analysis in 'Threads.Analysis.pas',
  Threads.WavOpen in 'Threads.WavOpen.pas',
  Core.ConfigStore in 'Core.ConfigStore.pas',
  GUI.SettingsForm in 'GUI.SettingsForm.pas',
  Threads.Overview in 'Threads.Overview.pas',
  Threads.PeakOverview in 'Threads.PeakOverview.pas',
  Electrode.LayoutForm in 'Electrode.LayoutForm.pas',
  Electrode.Layout in 'Electrode.Layout.pas',
  Source.Localization in 'Source.Localization.pas',
  Electrode.Geometry in 'Electrode.Geometry.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
