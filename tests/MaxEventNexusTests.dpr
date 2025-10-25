program MaxEventNexusTests;

{$I ../fpc_delphimode.inc}

{$IFDEF FPC}
{$DEFINE max_FPC}
{$ELSE}
{$DEFINE max_DELPHI}
{$ENDIF}

uses
  mormot.core.Test in 'src\mormot.core.test.pas',
  SysUtils,
  Classes,
  {$IFDEF max_DELPHI}
  System.Generics.Collections,
  {$ELSE}
  Generics.Collections,
  {$ENDIF}
  SyncObjs,

  maxLogic.EventNexus.Threading.Adapter in '..\maxLogic.EventNexus.Threading.Adapter.pas',
  maxLogic.EventNexus.Threading.RawThread in '..\maxLogic.EventNexus.Threading.RawThread.pas',
  {$IFDEF max_DELPHI}
  maxLogic.EventNexus.Threading.MaxAsync in '..\maxLogic.EventNexus.Threading.MaxAsync.pas',
  maxLogic.EventNexus.Threading.TTask in '..\maxLogic.EventNexus.Threading.TTask.pas',
  {$ENDIF }
  maxLogic.EventNexus in '..\maxLogic.EventNexus.pas',
  MaxEventNexus.Main.Tests in 'src\MaxEventNexus.Main.Tests.pas';

var
  lTests: TSynTests;
begin
  lTests := TSynTests.Create('MaxEventNexus');
  try
    lTests.AddCase(TTestAggregateException);
    lTests.AddCase(TTestAsyncDelivery);
    lTests.AddCase(TTestCoalesce);
    lTests.AddCase(TTestFuzz);
    lTests.AddCase(TTestGuidTopics);
    lTests.AddCase(TTestMetrics);
    lTests.AddCase(TTestNamedTopics);
    lTests.AddCase(TTestQueuePolicy);
    lTests.AddCase(TTestSchedulers);
    lTests.AddCase(TTestSticky);
    lTests.AddCase(TTestSubscribeOrdering);
    lTests.AddCase(TTestUnsubscribeAll);

    lTests.Run;
  finally
    lTests.Free;
  end;
end.

