program MaxEventNexusTests;

{$I ../fpc_delphimode.inc}

{$IFDEF FPC}
  {$DEFINE max_FPC}
{$ELSE}
  {$DEFINE max_DELPHI}
{$ENDIF}

uses
  mormot.core.test in 'src\mormot.core.test.pas',
  SysUtils,
  Classes,
  {$IFDEF max_DELPHI}
  System.Generics.Collections,
  {$ELSE}
  Generics.Collections,
  {$ENDIF}
  SyncObjs,

  maxLogic.EventNexus.Threading.Adapter in '..\src\maxLogic.EventNexus.Threading.Adapter.pas',
  maxLogic.EventNexus.Threading.RawThread in '..\src\maxLogic.EventNexus.Threading.RawThread.pas',
  {$IFDEF max_DELPHI}
  maxLogic.EventNexus.Threading.MaxAsync in '..\src\maxLogic.EventNexus.Threading.MaxAsync.pas',
  maxLogic.EventNexus.Threading.TTask in '..\src\maxLogic.EventNexus.Threading.TTask.pas',
  {$ENDIF }
  maxLogic.EventNexus in '..\maxLogic.EventNexus.pas',
  MaxEventNexus.Main.Tests in 'src\MaxEventNexus.Main.Tests.pas';



var
  Tests: TSynTests;
begin
  Tests := TSynTests.Create('MaxEventNexus');
  try
    Tests.AddCase(TTestAggregateException);
    Tests.AddCase(TTestAsyncDelivery);
    Tests.AddCase(TTestCoalesce);
    Tests.AddCase(TTestFuzz);
    Tests.AddCase(TTestGuidTopics);
    Tests.AddCase(TTestMetrics);
    Tests.AddCase(TTestNamedTopics);
    Tests.AddCase(TTestQueuePolicy);
    Tests.AddCase(TTestSchedulers);
    Tests.AddCase(TTestSticky);
    Tests.AddCase(TTestSubscribeOrdering);
    Tests.AddCase(TTestUnsubscribeAll);
    Tests.Run;
  finally
    Tests.Free;
  end;
end.
