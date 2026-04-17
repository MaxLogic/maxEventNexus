program MailboxTopicFamiliesSample;

{$APPTYPE CONSOLE}

uses
  Classes, SysUtils, TypInfo,
  maxLogic.EventNexus, maxLogic.EventNexus.Core, maxLogic.EventNexus.Mailbox;

type
  ITextMsg = interface
    ['{D6C4D1B4-2E4E-42A1-A8C9-249D03AB25D0}']
    function Text: string;
  end;

  TTextMsg = class(TInterfacedObject, ITextMsg)
  private
    fText: string;
  public
    constructor Create(const aText: string);
    function Text: string;
  end;

constructor TTextMsg.Create(const aText: string);
begin
  inherited Create;
  fText := aText;
end;

function TTextMsg.Text: string;
begin
  Result := fText;
end;

function DescribePostResult(aResult: TmaxPostResult): string;
begin
  Result := GetEnumName(TypeInfo(TmaxPostResult), Ord(aResult));
end;

var
  lBus: ImaxBus;
  lBusObj: TmaxBus;
  lHandled: TStringList;
  lMailbox: ImaxMailbox;
  lOwnerThreadId: TThreadID;
  lPostResult: TmaxPostResult;
begin
  lBus := maxBus;
  lBus.Clear;
  lBusObj := maxBusObj(lBus);
  lHandled := TStringList.Create;
  lMailbox := TmaxMailbox.Create;
  lOwnerThreadId := TThread.CurrentThread.ThreadID;
  try
    lBusObj.SubscribeIn<Integer>(lMailbox,
      procedure(const aValue: Integer)
      begin
        if TThread.CurrentThread.ThreadID <> lOwnerThreadId then
        begin
          raise Exception.Create('Typed mailbox handler ran on the wrong thread');
        end;
        lHandled.Add('typed:' + IntToStr(aValue));
        Writeln(Format('handled typed %d', [aValue]));
      end);
    lBusObj.SubscribeNamedIn('tick', lMailbox,
      procedure
      begin
        if TThread.CurrentThread.ThreadID <> lOwnerThreadId then
        begin
          raise Exception.Create('Exact named mailbox handler ran on the wrong thread');
        end;
        lHandled.Add('named:tick');
        Writeln('handled named tick');
      end);
    lBusObj.SubscribeNamedOfIn<string>('status', lMailbox,
      procedure(const aValue: string)
      begin
        if TThread.CurrentThread.ThreadID <> lOwnerThreadId then
        begin
          raise Exception.Create('Named-of mailbox handler ran on the wrong thread');
        end;
        lHandled.Add('named-of:' + aValue);
        Writeln('handled named-of ' + aValue);
      end);
    lBusObj.SubscribeGuidOfIn<ITextMsg>(lMailbox,
      procedure(const aValue: ITextMsg)
      begin
        if TThread.CurrentThread.ThreadID <> lOwnerThreadId then
        begin
          raise Exception.Create('Guid mailbox handler ran on the wrong thread');
        end;
        lHandled.Add('guid:' + aValue.Text);
        Writeln('handled guid ' + aValue.Text);
      end);

    Writeln(Format('receiver thread %d owns one mailbox for all topic families', [lOwnerThreadId]));
    Writeln('posting stays asynchronous; PumpAll executes the queued handlers on the receiver thread.');
    Writeln;

    lPostResult := lBusObj.PostResult<Integer>(7);
    Writeln(Format('typed post -> %s (pending=%d)', [DescribePostResult(lPostResult), lMailbox.PendingCount]));
    lPostResult := lBusObj.PostResultNamed('tick');
    Writeln(Format('named post -> %s (pending=%d)', [DescribePostResult(lPostResult), lMailbox.PendingCount]));
    lPostResult := lBusObj.PostResultNamedOf<string>('status', 'ready');
    Writeln(Format('named-of post -> %s (pending=%d)', [DescribePostResult(lPostResult), lMailbox.PendingCount]));
    lPostResult := lBusObj.PostResultGuidOf<ITextMsg>(TTextMsg.Create('hello'));
    Writeln(Format('guid post -> %s (pending=%d)', [DescribePostResult(lPostResult), lMailbox.PendingCount]));

    if lMailbox.PumpAll <> 4 then
    begin
      raise Exception.Create('Expected four handled mailbox items after PumpAll');
    end;
    if lHandled.Count <> 4 then
    begin
      raise Exception.CreateFmt('Expected 4 handled mailbox items but got %d', [lHandled.Count]);
    end;
    if lHandled[0] <> 'typed:7' then
    begin
      raise Exception.CreateFmt('Expected first handled item typed:7 but got %s', [lHandled[0]]);
    end;
    if lHandled[1] <> 'named:tick' then
    begin
      raise Exception.CreateFmt('Expected second handled item named:tick but got %s', [lHandled[1]]);
    end;
    if lHandled[2] <> 'named-of:ready' then
    begin
      raise Exception.CreateFmt('Expected third handled item named-of:ready but got %s', [lHandled[2]]);
    end;
    if lHandled[3] <> 'guid:hello' then
    begin
      raise Exception.CreateFmt('Expected fourth handled item guid:hello but got %s', [lHandled[3]]);
    end;

    Writeln;
    Writeln('summary: one mailbox can host typed, exact named, named-of, and GUID mailbox subscriptions together.');
  finally
    lHandled.Free;
    lBus.Clear;
  end;
end.
