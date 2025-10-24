program SchedulerCompare;

{$APPTYPE CONSOLE}

uses
  SysUtils, Classes, SyncObjs,
  maxLogic.EventNexus.Threading.Adapter,
  maxLogic.EventNexus.Threading.RawThread,
  {$IFDEF max_DELPHI}
  maxLogic.EventNexus.Threading.MaxAsync,
  maxLogic.EventNexus.Threading.TTask,
  {$ENDIF}
  maxLogic.EventNexus;

type
  TSchedulerFactory = function: IEventNexusScheduler;

  TSchedulerEntry = record
    Name: string;
    Factory: TSchedulerFactory;
  end;

function CreateRawThreadScheduler: IEventNexusScheduler;
begin
  Result := TmaxRawThreadScheduler.Create;
end;

{$IFNDEF max_DELPHI}
function CreateTTaskScheduler: IEventNexusScheduler;
begin
  raise Exception.Create('TTask scheduler not available on this compiler.');
end;
{$ENDIF}

function WaitForSignal(const aEvent: TEvent; aTimeoutMs: Cardinal): Boolean;
var
  start: UInt64;
begin
  start := GetTickCount64;
  repeat
    if aEvent.WaitFor(0) = wrSignaled then
      Exit(True);
  {$IFDEF max_DELPHI}
    TThread.CheckSynchronize(0);
  {$ELSE}
    CheckSynchronize;
  {$ENDIF}
    Sleep(1);
  until GetTickCount64 - start >= aTimeoutMs;
  Result := aEvent.WaitFor(0) = wrSignaled;
end;

procedure BenchmarkScheduler(const aEntry: TSchedulerEntry; aEvents, aConsumers: Integer);
var
  scheduler: IEventNexusScheduler;
  bus: ImaxBus;
  remaining: Integer;
  remainingLock: TCriticalSection;
  done: TEvent;
  startTick, stopTick: UInt64;
  i: Integer;
begin
  WriteLn('--- ', aEntry.Name, ' ---');
  scheduler := aEntry.Factory;
  bus := ImaxBus(TmaxBus.Create(scheduler));
  done := TEvent.Create(nil, True, False, '');
  remainingLock := TCriticalSection.Create;
  try
    remaining := aEvents * aConsumers;
    for i := 1 to aConsumers do
      bus.Subscribe<Integer>(
        procedure(const aValue: Integer)
        begin
          remainingLock.Enter;
          try
            Dec(remaining);
            if remaining = 0 then
              done.SetEvent;
          finally
            remainingLock.Leave;
          end;
        end,
        Async);

    startTick := GetTickCount64;
    for i := 1 to aEvents do
      bus.Post<Integer>(i);

    if not WaitForSignal(done, 60000) then
      raise Exception.CreateFmt('%s failed to drain queue', [aEntry.Name]);
    stopTick := GetTickCount64;

    WriteLn('Events: ', aEvents);
    WriteLn('Async consumers: ', aConsumers);
    WriteLn('Elapsed ms: ', stopTick - startTick);
    if stopTick > startTick then
      WriteLn('Throughput evt/s: ', Int64(aEvents) * aConsumers * 1000 div (stopTick - startTick));
  finally
    done.Free;
    remainingLock.Free;
    bus := nil;
    scheduler := nil;
  end;
end;

procedure Run;
const
  EVENTS_PER_RUN = 20000;
  ASYNC_CONSUMERS = 4;
var
  entries: array of TSchedulerEntry;
  idx: Integer;
begin
  SetLength(entries, 1
{$IFDEF max_DELPHI}
    + 2
{$ENDIF}
  );
  idx := 0;
  entries[idx].Name := 'raw-thread';
  entries[idx].Factory := CreateRawThreadScheduler;
  Inc(idx);
{$IFDEF max_DELPHI}
  entries[idx].Name := 'maxAsync';
  entries[idx].Factory := CreateMaxAsyncScheduler;
  Inc(idx);
  entries[idx].Name := 'TTask';
  entries[idx].Factory := CreateTTaskScheduler;
  Inc(idx);
{$ENDIF}

  for idx := Low(entries) to High(entries) do
  begin
    BenchmarkScheduler(entries[idx], EVENTS_PER_RUN, ASYNC_CONSUMERS);
    WriteLn;
  end;
end;

begin
  try
    Run;
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
