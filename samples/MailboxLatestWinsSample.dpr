program MailboxLatestWinsSample;

{$APPTYPE CONSOLE}

uses
  Classes, SysUtils,
  maxLogic.EventNexus, maxLogic.EventNexus.Core, maxLogic.EventNexus.Mailbox;

type
  TProgressUpdate = record
    Job: string;
    Percent: Integer;
  end;

function DescribeUpdate(const aUpdate: TProgressUpdate): string;
begin
  Result := Format('%s=%d%%', [aUpdate.Job, aUpdate.Percent]);
end;

procedure PostUpdate(const aBusObj: TmaxBus; const aMailbox: ImaxMailbox; const aJob: string; const aPercent: Integer);
var
  lUpdate: TProgressUpdate;
begin
  lUpdate.Job := aJob;
  lUpdate.Percent := aPercent;
  aBusObj.Post<TProgressUpdate>(lUpdate);
  Writeln(Format('post %s (pending=%d)', [DescribeUpdate(lUpdate), aMailbox.PendingCount]));
end;

var
  lBus: ImaxBus;
  lBusObj: TmaxBus;
  lHandled: TStringList;
  lLine: string;
  lMailbox: ImaxMailbox;
  lPumped: Integer;
begin
  lBus := maxBus;
  lBus.Clear;
  lBusObj := maxBusObj(lBus);
  lHandled := TStringList.Create;
  lMailbox := TmaxMailbox.Create;
  try
    lBusObj.SubscribeIn<TProgressUpdate>(lMailbox,
      procedure(const aValue: TProgressUpdate)
      begin
        lHandled.Add(DescribeUpdate(aValue));
        Writeln('handled ' + DescribeUpdate(aValue));
      end,
      function(const aValue: TProgressUpdate): string
      begin
        Result := aValue.Job;
      end);

    Writeln(Format('receiver thread %d owns the mailbox', [TThread.CurrentThread.ThreadID]));
    Writeln('topic-level coalescing is disabled; this sample shows receiver-side mailbox coalescing only.');
    Writeln;
    Writeln('== same key collapses ==');
    PostUpdate(lBusObj, lMailbox, 'alpha', 10);
    PostUpdate(lBusObj, lMailbox, 'alpha', 50);
    PostUpdate(lBusObj, lMailbox, 'alpha', 80);
    lPumped := lMailbox.PumpAll;
    Writeln(Format('summary: pending=%d pumped=%d handled=%d', [lMailbox.PendingCount, lPumped, lHandled.Count]));
    if lPumped <> 1 then
    begin
      raise Exception.CreateFmt('Expected 1 pumped item for the first phase but got %d', [lPumped]);
    end;
    if lHandled.Count <> 1 then
    begin
      raise Exception.CreateFmt('Expected 1 handled item for the first phase but got %d', [lHandled.Count]);
    end;
    if lHandled[0] <> 'alpha=80%' then
    begin
      raise Exception.CreateFmt('Expected handled item alpha=80%% in the first phase but got %s', [lHandled[0]]);
    end;

    Writeln;
    Writeln('== unrelated keys keep order ==');
    lHandled.Clear;
    PostUpdate(lBusObj, lMailbox, 'alpha', 10);
    PostUpdate(lBusObj, lMailbox, 'beta', 20);
    PostUpdate(lBusObj, lMailbox, 'alpha', 80);
    lPumped := lMailbox.PumpAll;
    Writeln(Format('summary: pending=%d pumped=%d handled=%d', [lMailbox.PendingCount, lPumped, lHandled.Count]));
    if lPumped <> 2 then
    begin
      raise Exception.CreateFmt('Expected 2 pumped items for the second phase but got %d', [lPumped]);
    end;
    if lHandled.Count <> 2 then
    begin
      raise Exception.CreateFmt('Expected 2 handled items for the second phase but got %d', [lHandled.Count]);
    end;
    if lHandled[0] <> 'alpha=80%' then
    begin
      raise Exception.CreateFmt('Expected first handled item alpha=80%% in the second phase but got %s', [lHandled[0]]);
    end;
    if lHandled[1] <> 'beta=20%' then
    begin
      raise Exception.CreateFmt('Expected second handled item beta=20%% in the second phase but got %s', [lHandled[1]]);
    end;

    Writeln('final handled order:');
    for lLine in lHandled do
    begin
      Writeln('  ' + lLine);
    end;
    Writeln('latest pending wins per key, and unrelated keys keep their original queue slots.');
  finally
    lHandled.Free;
    lBus.Clear;
  end;
end.
