unit maxLogic.EventNexus.Threading.MaxAsync;

interface

uses
  Classes, SysUtils,
  maxAsync,
  maxLogic.EventNexus.Threading.Adapter;

type
  TMaxAsyncWorkItem = class
  private
    fProc: TmaxProc;
  public
    constructor Create(const aProc: TmaxProc);
    procedure Execute;
  end;

  TmaxAsyncScheduler = class(TInterfacedObject, IEventNexusScheduler)
  private
    fProcessor: TAsyncCollectionProcessor<TMaxAsyncWorkItem>;
    procedure EnqueueWork(const aProc: TmaxProc);
    procedure ScheduleAsync(const aProc: TmaxProc; aDelayUs: Integer);
  public
    constructor Create;
    destructor Destroy; override;
    procedure RunAsync(const aProc: TmaxProc);
    procedure RunOnMain(const aProc: TmaxProc);
    procedure RunDelayed(const aProc: TmaxProc; aDelayUs: Integer);
    function IsMainThread: Boolean;
  end;

function CreateMaxAsyncScheduler: IEventNexusScheduler;

implementation

constructor TMaxAsyncWorkItem.Create(const aProc: TmaxProc);
begin
  inherited Create;
  fProc := aProc;
end;

procedure TMaxAsyncWorkItem.Execute;
var
  lProc: TmaxProc;
begin
  lProc := fProc;
  fProc := nil;
  if ProcAssigned(lProc) then
    lProc();
end;

constructor TmaxAsyncScheduler.Create;
var
  lWorkerCount: Integer;
  lQueueCapacity: Integer;
begin
  inherited Create;
  fProcessor := TAsyncCollectionProcessor<TMaxAsyncWorkItem>.Create;
  fProcessor.Proc :=
    procedure(const aItem: TMaxAsyncWorkItem)
    begin
      if aItem = nil then
        Exit;
      try
        aItem.Execute;
      finally
        aItem.Free;
      end;
    end;

  lWorkerCount := TThread.ProcessorCount;
  if lWorkerCount < 2 then
    lWorkerCount := 2;
  lQueueCapacity := lWorkerCount * 256;
  if lQueueCapacity < 1024 then
    lQueueCapacity := 1024;

  fProcessor.SimultanousThreadCount := lWorkerCount;
  fProcessor.QueueMode := acpqmLockFreeMpmcRingQueue;
  fProcessor.QueueCapacity := lQueueCapacity;
  fProcessor.BackpressureMode := acpbmBlock;
end;

destructor TmaxAsyncScheduler.Destroy;
begin
  fProcessor.Free;
  inherited;
end;

procedure TmaxAsyncScheduler.EnqueueWork(const aProc: TmaxProc);
var
  lItem: TMaxAsyncWorkItem;
begin
  if not ProcAssigned(aProc) then
    Exit;
  lItem := TMaxAsyncWorkItem.Create(aProc);
  try
    fProcessor.Add(lItem);
  except
    lItem.Free;
    raise;
  end;
end;

procedure TmaxAsyncScheduler.ScheduleAsync(const aProc: TmaxProc; aDelayUs: Integer);
var
  lDelayMs: Integer;
  lHandle: iAsync; //PALOFF lifetime anchor for async handle until completion callback
  lProc: TmaxProc;
  lSelf: IEventNexusScheduler;
begin
  if not ProcAssigned(aProc) then
    Exit;
  lProc := aProc;
  if aDelayUs <= 0 then
  begin
    try
      EnqueueWork(lProc);
    except
      lProc();
    end;
    Exit;
  end;

  if aDelayUs > 0 then
    lDelayMs := aDelayUs div 1000
  else
    lDelayMs := 0;
  lSelf := Self as IEventNexusScheduler;
  try
    lHandle := SimpleAsyncCall(
      procedure
      begin
        if lDelayMs > 0 then
          TThread.Sleep(lDelayMs);
        lSelf.RunAsync(lProc);
      end,
      '',
      procedure
      begin
        lHandle := nil;
      end);
  except
    // If async backend submission fails, degrade to inline execution so callers keep progressing.
    if lDelayMs > 0 then
      TThread.Sleep(lDelayMs);
    lProc();
  end;
end;

procedure TmaxAsyncScheduler.RunAsync(const aProc: TmaxProc);
begin
  ScheduleAsync(aProc, 0);
end;

procedure TmaxAsyncScheduler.RunDelayed(const aProc: TmaxProc; aDelayUs: Integer);
begin
  ScheduleAsync(aProc, aDelayUs);
end;

procedure TmaxAsyncScheduler.RunOnMain(const aProc: TmaxProc);
begin
  if not ProcAssigned(aProc) then
    Exit;
  if IsMainThread() then
    aProc()
  else
    TThread.Queue(nil,
      procedure
      begin
        aProc();
      end);
end;

function TmaxAsyncScheduler.IsMainThread: Boolean;
begin
  Result := TThread.CurrentThread.ThreadID = MainThreadID;
end;

function CreateMaxAsyncScheduler: IEventNexusScheduler;
begin
  Result := TmaxAsyncScheduler.Create;
end;

end.
