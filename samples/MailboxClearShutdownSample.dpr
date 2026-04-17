program MailboxClearShutdownSample;

{$APPTYPE CONSOLE}

uses
  Classes, SysUtils, SyncObjs,
  maxLogic.EventNexus, maxLogic.EventNexus.Core, maxLogic.EventNexus.Mailbox;

procedure DemonstrateClear(const aBus: ImaxBus);
var
  lBusObj: TmaxBus;
  lHits: Integer;
  lMailbox: ImaxMailbox;
  lPumped: Integer;
begin
  lBusObj := maxBusObj(aBus);
  lMailbox := TmaxMailbox.Create;
  lHits := 0;
  lBusObj.SubscribeIn<Integer>(lMailbox,
    procedure(const aValue: Integer)
    begin
      Inc(lHits);
      Writeln(Format('handled stale value %d', [aValue]));
    end);
  lBusObj.Post<Integer>(1);
  lBusObj.Post<Integer>(2);
  Writeln(Format('before Clear pending=%d', [lMailbox.PendingCount]));
  aBus.Clear;
  lPumped := lMailbox.PumpAll;
  Writeln(Format('after Clear pending=%d pumped=%d hits=%d', [lMailbox.PendingCount, lPumped, lHits]));
end;

procedure DemonstrateCloseBoundary;
var
  lClosed: TEvent;
  lCloser: TThread;
  lMailbox: ImaxMailbox;
  lPumped: Integer;
  lRelease: TEvent;
  lStarted: TEvent;
begin
  lClosed := TEvent.Create(nil, True, False, '');
  lCloser := nil;
  lMailbox := TmaxMailbox.Create;
  lRelease := TEvent.Create(nil, True, False, '');
  lStarted := TEvent.Create(nil, True, False, '');
  try
    lMailbox.TryPost(
      procedure
      begin
        Writeln('dequeued work started');
        lStarted.SetEvent;
        lRelease.WaitFor(5000);
        Writeln('dequeued work finished');
      end);
    lMailbox.TryPost(
      procedure
      begin
        Writeln('queued work should not run after Close(True)');
      end);

    lCloser := TThread.CreateAnonymousThread(
      procedure
      begin
        if lStarted.WaitFor(5000) <> wrSignaled then
          Exit;
        Writeln('closing mailbox with discard=True while the first item is already dequeued');
        lMailbox.Close(True);
        Sleep(100);
        lRelease.SetEvent;
        lClosed.SetEvent;
      end);
    lCloser.FreeOnTerminate := False;
    lCloser.Start;

    if not lMailbox.PumpOne(cMaxWaitInfinite) then
      raise Exception.Create('Expected the dequeued item to finish');
    if lClosed.WaitFor(5000) <> wrSignaled then
      raise Exception.Create('Mailbox close boundary demo timed out');

    lPumped := lMailbox.PumpAll;
    Writeln(Format('after Close pending=%d extra-pump=%d', [lMailbox.PendingCount, lPumped]));
  finally
    if lCloser <> nil then
    begin
      lCloser.WaitFor;
      lCloser.Free;
    end;
    lStarted.Free;
    lRelease.Free;
    lClosed.Free;
  end;
end;

procedure DemonstrateCloseRetain;
var
  lHandled: TStringList;
  lMailbox: ImaxMailbox;
  lPumped: Integer;
begin
  lHandled := TStringList.Create;
  lMailbox := TmaxMailbox.Create;
  try
    if not lMailbox.TryPost(
      procedure
      begin
        lHandled.Add('first');
        Writeln('retained first item');
      end) then
    begin
      raise Exception.Create('Expected first retained item to be queued');
    end;
    if not lMailbox.TryPost(
      procedure
      begin
        lHandled.Add('second');
        Writeln('retained second item');
      end) then
    begin
      raise Exception.Create('Expected second retained item to be queued');
    end;

    Writeln(Format('before Close(False) pending=%d', [lMailbox.PendingCount]));
    lMailbox.Close(False);
    if not lMailbox.IsClosed then
    begin
      raise Exception.Create('Expected mailbox to report closed after Close(False)');
    end;
    if lMailbox.TryPost(
      procedure
      begin
        Writeln('late item should not be admitted after Close(False)');
      end) then
    begin
      raise Exception.Create('Expected Close(False) to reject future enqueue');
    end;

    lPumped := lMailbox.PumpAll;
    Writeln(Format('after Close(False) pending=%d pumped=%d hits=%d', [lMailbox.PendingCount, lPumped, lHandled.Count]));
    if lPumped <> 2 then
    begin
      raise Exception.CreateFmt('Expected 2 retained items after Close(False) but got %d', [lPumped]);
    end;
    if lHandled.Count <> 2 then
    begin
      raise Exception.CreateFmt('Expected 2 handled retained items but got %d', [lHandled.Count]);
    end;
    if lHandled[0] <> 'first' then
    begin
      raise Exception.CreateFmt('Expected first retained item to stay first but got %s', [lHandled[0]]);
    end;
    if lHandled[1] <> 'second' then
    begin
      raise Exception.CreateFmt('Expected second retained item to stay second but got %s', [lHandled[1]]);
    end;
  finally
    lHandled.Free;
  end;
end;

var
  lBus: ImaxBus;
begin
  lBus := maxBus;
  lBus.Clear;
  try
    DemonstrateClear(lBus);
    DemonstrateCloseBoundary;
    DemonstrateCloseRetain;
  finally
    lBus.Clear;
  end;
end.
