program MailboxOverflowSample;

{$APPTYPE CONSOLE}

uses
  Classes, SysUtils, TypInfo,
  System.Generics.Collections,
  maxLogic.EventNexus, maxLogic.EventNexus.Core, maxLogic.EventNexus.Mailbox;

var
  lBus: ImaxBus;
  lBusObj: TmaxBus;
  lHandled: TList<Integer>;
  lMailbox: ImaxMailbox;
  lPolicy: TmaxMailboxPolicy;
  lPostResult: TmaxPostResult;
begin
  lBus := maxBus;
  lBus.Clear;
  lBusObj := maxBusObj(lBus);
  lHandled := TList<Integer>.Create;
  lPolicy.MaxDepth := 1;
  lPolicy.Overflow := MailboxDropNewest;
  lPolicy.DeadlineUs := 0;
  lMailbox := TmaxMailbox.Create(lPolicy);
  try
    lBusObj.SubscribeIn<Integer>(lMailbox,
      procedure(const aValue: Integer)
      begin
        lHandled.Add(aValue);
        Writeln(Format('handled %d', [aValue]));
      end);

    Writeln(Format('receiver thread %d owns a bounded mailbox (maxDepth=%d, overflow=%s)',
      [TThread.CurrentThread.ThreadID, lPolicy.MaxDepth, 'MailboxDropNewest']));
    Writeln('posting without pumping shows mailbox-side overflow, not coalescing.');
    Writeln;

    lPostResult := lBusObj.PostResult<Integer>(1);
    Writeln(Format('post 1 -> %s (pending=%d)', [GetEnumName(TypeInfo(TmaxPostResult), Ord(lPostResult)), lMailbox.PendingCount]));
    lPostResult := lBusObj.PostResult<Integer>(2);
    Writeln(Format('post 2 -> %s (pending=%d)', [GetEnumName(TypeInfo(TmaxPostResult), Ord(lPostResult)), lMailbox.PendingCount]));
    lPostResult := lBusObj.PostResult<Integer>(3);
    Writeln(Format('post 3 -> %s (pending=%d)', [GetEnumName(TypeInfo(TmaxPostResult), Ord(lPostResult)), lMailbox.PendingCount]));

    if lMailbox.PendingCount <> 1 then
      raise Exception.CreateFmt('Expected 1 pending item before pump but got %d', [lMailbox.PendingCount]);
    if lMailbox.PumpAll <> 1 then
      raise Exception.Create('Expected exactly one handled item after pump');
    if lHandled.Count <> 1 then
      raise Exception.CreateFmt('Expected 1 handled value but got %d', [lHandled.Count]);
    if lHandled[0] <> 1 then
      raise Exception.CreateFmt('Expected only the first value to survive overflow but got %d', [lHandled[0]]);

    Writeln;
    Writeln('summary: bounded mailbox overflow dropped later arrivals until the receiver pumped the mailbox.');
  finally
    lHandled.Free;
    lBus.Clear;
  end;
end.
