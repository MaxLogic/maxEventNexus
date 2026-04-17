program MailboxWorkerIntegrationSample;

{$APPTYPE CONSOLE}

uses
  Classes, SysUtils, SyncObjs, TypInfo,
  maxLogic.EventNexus, maxLogic.EventNexus.Core, maxLogic.EventNexus.Mailbox;

type
  TJobRequest = record
    JobId: Integer;
    Payload: string;
  end;

  TJobProgress = record
    JobId: Integer;
    Stage: string;
  end;

  TJobResult = record
    JobId: Integer;
    Output: string;
  end;

  TWorkerThread = class(TThread)
  private
    fBus: ImaxBus;
    fReady: TEvent;
    fStopped: TEvent;
  public
    constructor Create(const aBus: ImaxBus; const aReady, aStopped: TEvent);
  protected
    procedure Execute; override;
  end;

constructor TWorkerThread.Create(const aBus: ImaxBus; const aReady, aStopped: TEvent);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  fBus := aBus;
  fReady := aReady;
  fStopped := aStopped;
end;

procedure TWorkerThread.Execute;
var
  lBusObj: TmaxBus;
  lMailbox: ImaxMailbox;
  lOwnerThreadId: TThreadID;
begin
  lBusObj := maxBusObj(fBus);
  lMailbox := TmaxMailbox.Create;
  lOwnerThreadId := TThread.CurrentThread.ThreadID;
  try
    lBusObj.SubscribeNamedOfIn<TJobRequest>('worker.job', lMailbox,
      procedure(const aValue: TJobRequest)
      var
        lProgress: TJobProgress;
        lResult: TJobResult;
      begin
        if TThread.CurrentThread.ThreadID <> lOwnerThreadId then
        begin
          raise Exception.Create('Worker job handler ran on the wrong thread');
        end;

        Writeln(Format('worker thread %d processing job %d (%s)',
          [lOwnerThreadId, aValue.JobId, aValue.Payload]));

        lProgress.JobId := aValue.JobId;
        lProgress.Stage := 'started ' + aValue.Payload;
        lBusObj.Post<TJobProgress>(lProgress);

        lResult.JobId := aValue.JobId;
        lResult.Output := UpperCase(aValue.Payload);
        lBusObj.Post<TJobResult>(lResult);
      end);

    lBusObj.SubscribeNamedIn('worker.stop', lMailbox,
      procedure
      begin
        if TThread.CurrentThread.ThreadID <> lOwnerThreadId then
        begin
          raise Exception.Create('Worker stop handler ran on the wrong thread');
        end;

        Writeln(Format('worker thread %d received stop', [lOwnerThreadId]));
        Terminate;
      end);

    fReady.SetEvent;
    while not Terminated do
    begin
      lMailbox.PumpOne(cMaxWaitInfinite);
    end;
  finally
    fStopped.SetEvent;
  end;
end;

function DescribePostResult(aResult: TmaxPostResult): string;
begin
  Result := GetEnumName(TypeInfo(TmaxPostResult), Ord(aResult));
end;

var
  lBus: ImaxBus;
  lBusObj: TmaxBus;
  lHandled: TStringList;
  lMainMailbox: ImaxMailbox;
  lMainThreadId: TThreadID;
  lReady: TEvent;
  lStopped: TEvent;
  lWorker: TWorkerThread;
  lJob: TJobRequest;
  lPostResult: TmaxPostResult;
begin
  lBus := maxBus;
  lBus.Clear;
  lBusObj := maxBusObj(lBus);
  lHandled := TStringList.Create;
  lMainMailbox := TmaxMailbox.Create;
  lMainThreadId := TThread.CurrentThread.ThreadID;
  lReady := TEvent.Create(nil, True, False, '');
  lStopped := TEvent.Create(nil, True, False, '');
  lWorker := TWorkerThread.Create(lBus, lReady, lStopped);
  try
    lBusObj.SubscribeIn<TJobProgress>(lMainMailbox,
      procedure(const aValue: TJobProgress)
      begin
        if TThread.CurrentThread.ThreadID <> lMainThreadId then
        begin
          raise Exception.Create('Progress handler ran on the wrong thread');
        end;

        lHandled.Add(Format('progress:%d:%s', [aValue.JobId, aValue.Stage]));
        Writeln(Format('main thread %d handled progress %d -> %s',
          [lMainThreadId, aValue.JobId, aValue.Stage]));
      end);

    lBusObj.SubscribeIn<TJobResult>(lMainMailbox,
      procedure(const aValue: TJobResult)
      begin
        if TThread.CurrentThread.ThreadID <> lMainThreadId then
        begin
          raise Exception.Create('Result handler ran on the wrong thread');
        end;

        lHandled.Add(Format('result:%d:%s', [aValue.JobId, aValue.Output]));
        Writeln(Format('main thread %d handled result %d -> %s',
          [lMainThreadId, aValue.JobId, aValue.Output]));
      end);

    lWorker.Start;
    if lReady.WaitFor(5000) <> wrSignaled then
    begin
      raise Exception.Create('Worker mailbox was not ready');
    end;

    Writeln(Format('main thread %d posting work into the worker mailbox', [lMainThreadId]));

    lJob.JobId := 1;
    lJob.Payload := 'alpha';
    lPostResult := lBusObj.PostResultNamedOf<TJobRequest>('worker.job', lJob);
    Writeln(Format('job 1 post -> %s', [DescribePostResult(lPostResult)]));

    lJob.JobId := 2;
    lJob.Payload := 'beta';
    lPostResult := lBusObj.PostResultNamedOf<TJobRequest>('worker.job', lJob);
    Writeln(Format('job 2 post -> %s', [DescribePostResult(lPostResult)]));

    while lHandled.Count < 4 do
    begin
      if not lMainMailbox.PumpOne(5000) then
      begin
        raise Exception.Create('Timed out while waiting for worker progress/results');
      end;
    end;

    if lHandled[0] <> 'progress:1:started alpha' then
    begin
      raise Exception.CreateFmt('Unexpected first callback: %s', [lHandled[0]]);
    end;
    if lHandled[1] <> 'result:1:ALPHA' then
    begin
      raise Exception.CreateFmt('Unexpected second callback: %s', [lHandled[1]]);
    end;
    if lHandled[2] <> 'progress:2:started beta' then
    begin
      raise Exception.CreateFmt('Unexpected third callback: %s', [lHandled[2]]);
    end;
    if lHandled[3] <> 'result:2:BETA' then
    begin
      raise Exception.CreateFmt('Unexpected fourth callback: %s', [lHandled[3]]);
    end;

    lPostResult := lBusObj.PostResultNamed('worker.stop');
    Writeln(Format('stop post -> %s', [DescribePostResult(lPostResult)]));

    if lStopped.WaitFor(5000) <> wrSignaled then
    begin
      raise Exception.Create('Worker did not stop after the stop command');
    end;
    lWorker.WaitFor;

    Writeln;
    Writeln('summary: worker mailbox accepted named job commands, published typed progress/results, and shut down through an exact named control message.');
  finally
    lWorker.Free;
    lStopped.Free;
    lReady.Free;
    lHandled.Free;
    lBus.Clear;
  end;
end.
