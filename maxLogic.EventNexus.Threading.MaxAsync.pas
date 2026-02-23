unit maxLogic.EventNexus.Threading.MaxAsync;

interface

uses
  Classes, SysUtils,
  maxAsync,
  maxLogic.EventNexus.Threading.Adapter;

type
  TmaxAsyncScheduler = class(TInterfacedObject, IEventNexusScheduler)
  private
    procedure ScheduleAsync(const aProc: TmaxProc; aDelayUs: Integer);
  public
    procedure RunAsync(const aProc: TmaxProc);
    procedure RunOnMain(const aProc: TmaxProc);
    procedure RunDelayed(const aProc: TmaxProc; aDelayUs: Integer);
    function IsMainThread: Boolean;
  end;

function CreateMaxAsyncScheduler: IEventNexusScheduler;

implementation

type
  TMaxAsyncTask = class
  private
    FProc: TmaxProc;
    FDelayUs: Integer;
    FHandle: iAsync;
  public
    constructor Create(const aProc: TmaxProc; aDelayUs: Integer);
    procedure Execute;
    procedure AfterDone;
    procedure AttachHandle(const aHandle: iAsync);
  end;

  TMainQueueAdapter = class
  private
    FProc: TmaxProc;
  public
    constructor Create(const aProc: TmaxProc);
    procedure Invoke;
  end;

constructor TMaxAsyncTask.Create(const aProc: TmaxProc; aDelayUs: Integer);
begin
  inherited Create;
  FProc := aProc;
  FDelayUs := aDelayUs;
end;

procedure TMaxAsyncTask.AttachHandle(const aHandle: iAsync);
begin
  FHandle := aHandle;
end;

procedure TMaxAsyncTask.Execute;
var
  lDelayMs: Integer;
  lProc: TmaxProc;
begin
  lProc := FProc;
  if not ProcAssigned(lProc) then
    Exit;
  if FDelayUs > 0 then
  begin
    lDelayMs := FDelayUs div 1000;
    if lDelayMs > 0 then
      TThread.Sleep(lDelayMs);
  end;
  lProc();
end;

procedure TMaxAsyncTask.AfterDone;
begin
  try
    FHandle := nil;
  finally
    Free;
  end;
end;

constructor TMainQueueAdapter.Create(const aProc: TmaxProc);
begin
  inherited Create;
  FProc := aProc;
end;

procedure TMainQueueAdapter.Invoke;
var
  lProc: TmaxProc;
begin
  lProc := FProc;
  try
    if ProcAssigned(lProc) then
      lProc();
  finally
    Free;
  end;
end;

procedure TmaxAsyncScheduler.ScheduleAsync(const aProc: TmaxProc; aDelayUs: Integer);
var
  lTask: TMaxAsyncTask;
  lHandle: iAsync;
begin
  if not ProcAssigned(aProc) then
    Exit;
  lTask := TMaxAsyncTask.Create(aProc, aDelayUs);
  try
    lHandle := SimpleAsyncCall(lTask.Execute, '', lTask.AfterDone);
  except
    // If async backend submission fails, degrade to inline execution so callers keep progressing.
    lTask.Execute;
    lTask.AfterDone;
    Exit;
  end;
  lTask.AttachHandle(lHandle);
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
var
  lAdapter: TMainQueueAdapter;
begin
  if not ProcAssigned(aProc) then
    Exit;
  if IsMainThread() then
    aProc()
  else
  begin
    lAdapter := TMainQueueAdapter.Create(aProc);
    try
      TThread.Queue(nil, lAdapter.Invoke);
    except
      lAdapter.Free;
      raise;
    end;
  end;
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
