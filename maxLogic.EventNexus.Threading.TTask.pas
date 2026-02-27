unit maxLogic.EventNexus.Threading.TTask;

interface

uses
  System.Classes, System.SysUtils, System.Threading,
  maxLogic.EventNexus.Threading.Adapter;

type
  TmaxTTaskScheduler = class(TInterfacedObject, IEventNexusScheduler)
  private
    fPool: TThreadPool;
  public
    constructor Create;
    destructor Destroy; override;
    procedure RunAsync(const aProc: TmaxProc);
    procedure RunOnMain(const aProc: TmaxProc);
    procedure RunDelayed(const aProc: TmaxProc; aDelayUs: Integer);
    function IsMainThread: Boolean;
  end;

function CreateTTaskScheduler: IEventNexusScheduler;

implementation

constructor TmaxTTaskScheduler.Create;
var
  lCpuCount: Integer;
  lMaxWorkers: Integer;
  lMinWorkers: Integer;
begin
  inherited Create;
  fPool := TThreadPool.Create;
  lCpuCount := TThread.ProcessorCount;
  if lCpuCount < 1 then
    lCpuCount := 1;
  lMaxWorkers := lCpuCount * 2;
  if lMaxWorkers < 2 then
    lMaxWorkers := 2;
  lMinWorkers := lCpuCount;
  if lMinWorkers < 2 then
    lMinWorkers := 2;
  fPool.SetMaxWorkerThreads(lMaxWorkers);
  fPool.SetMinWorkerThreads(lMinWorkers);
end;

destructor TmaxTTaskScheduler.Destroy;
begin
  fPool.Free;
  inherited Destroy;
end;

procedure TmaxTTaskScheduler.RunAsync(const aProc: TmaxProc);
begin
  if not ProcAssigned(aProc) then
    Exit;
  try
    TTask.Run(
      procedure
      begin
        aProc();
      end, fPool);
  except
    // Thread-pool submission can fail under OS pressure; degrade to inline execution.
    aProc();
  end;
end;

procedure TmaxTTaskScheduler.RunOnMain(const aProc: TmaxProc);
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

procedure TmaxTTaskScheduler.RunDelayed(const aProc: TmaxProc; aDelayUs: Integer);
begin
  if not ProcAssigned(aProc) then
    Exit;
  try
    TTask.Run(
      procedure
      var
        lDelayMs: Integer;
      begin
        if aDelayUs > 0 then
        begin
          lDelayMs := aDelayUs div 1000;
          if lDelayMs > 0 then
            TThread.Sleep(lDelayMs);
        end;
        aProc();
      end, fPool);
  except
    if aDelayUs > 0 then
      TThread.Sleep(aDelayUs div 1000);
    aProc();
  end;
end;

function TmaxTTaskScheduler.IsMainThread: Boolean;
begin
  Result := TThread.CurrentThread.ThreadID = MainThreadID;
end;

function CreateTTaskScheduler: IEventNexusScheduler;
begin
  Result := TmaxTTaskScheduler.Create;
end;

end.
