program MailboxWorkerSample;

{$APPTYPE CONSOLE}

uses
  Classes, SysUtils, SyncObjs,
  maxLogic.EventNexus, maxLogic.EventNexus.Core, maxLogic.EventNexus.Mailbox;

type
  TReceiverThread = class(TThread)
  private
    fBus: ImaxBus;
    fDone: TEvent;
    fReady: TEvent;
  public
    constructor Create(const aBus: ImaxBus; const aReady, aDone: TEvent);
  protected
    procedure Execute; override;
  end;

constructor TReceiverThread.Create(const aBus: ImaxBus; const aReady, aDone: TEvent);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  fBus := aBus;
  fDone := aDone;
  fReady := aReady;
end;

procedure TReceiverThread.Execute;
var
  lBusObj: TmaxBus;
  lMailbox: ImaxMailbox;
begin
  lBusObj := maxBusObj(fBus);
  lMailbox := TmaxMailbox.Create;
  lBusObj.SubscribeIn<Integer>(lMailbox,
    procedure(const aValue: Integer)
    begin
      Writeln(Format('receiver thread %d handled %d', [TThread.CurrentThread.ThreadID, aValue]));
      fDone.SetEvent;
      Terminate;
    end);
  fReady.SetEvent;
  while not Terminated do
    lMailbox.PumpOne(cMaxWaitInfinite);
end;

var
  lBus: ImaxBus;
  lDone: TEvent;
  lReady: TEvent;
  lReceiver: TReceiverThread;
  lSender: TThread;
begin
  lBus := maxBus;
  lBus.Clear;
  lDone := TEvent.Create(nil, True, False, '');
  lReady := TEvent.Create(nil, True, False, '');
  lReceiver := TReceiverThread.Create(lBus, lReady, lDone);
  lSender := nil;
  try
    lReceiver.Start;
    if lReady.WaitFor(5000) <> wrSignaled then
      raise Exception.Create('Receiver mailbox was not ready');

    Writeln(Format('main thread %d preparing sender', [TThread.CurrentThread.ThreadID]));
    lSender := TThread.CreateAnonymousThread(
      procedure
      begin
        Writeln(Format('sender thread %d posting 42', [TThread.CurrentThread.ThreadID]));
        maxBusObj(lBus).Post<Integer>(42);
      end);
    lSender.FreeOnTerminate := False;
    lSender.Start;
    lSender.WaitFor;

    if lDone.WaitFor(5000) <> wrSignaled then
      raise Exception.Create('Receiver mailbox did not handle the event in time');

    lReceiver.WaitFor;
  finally
    if lSender <> nil then
      lSender.Free;
    lReceiver.Free;
    lReady.Free;
    lDone.Free;
    lBus.Clear;
  end;
end.
