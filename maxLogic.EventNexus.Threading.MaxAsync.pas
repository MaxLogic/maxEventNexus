unit maxLogic.EventNexus.Threading.MaxAsync;

{$I fpc_delphimode.inc}

{$IFDEF FPC}
  {$DEFINE max_FPC}
{$ELSE}
  {$DEFINE max_DELPHI}
{$ENDIF}

interface

uses
  Classes, SysUtils, SyncObjs,
  {$IFDEF max_FPC} maxLogic_EventNexus_Threading_Adapter {$ELSE} maxLogic.EventNexus.Threading.Adapter {$ENDIF},
  maxAsync;

type
  TmaxAsyncScheduler = class(TInterfacedObject, IEventNexusScheduler)
  private
    class var fLock: TCriticalSection;
    class var fActive: TInterfaceList;
    class constructor Create;
    class destructor Destroy;
    class procedure Track(const aAsync: iAsync); static;
    class procedure Untrack(const aAsync: iAsync); static;
    procedure ScheduleAsync(const aProc: TmaxProc; aDelayUs: Integer);
  public
    procedure RunAsync(aProc: TmaxProc);
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

class constructor TmaxAsyncScheduler.Create;
begin
  inherited;
  fLock := TCriticalSection.Create;
  fActive := TInterfaceList.Create;
end;

class destructor TmaxAsyncScheduler.Destroy;
begin
  FreeAndNil(fActive);
  FreeAndNil(fLock);
end;

class procedure TmaxAsyncScheduler.Track(const aAsync: iAsync);
begin
  if aAsync = nil then
    Exit;
  fLock.Enter;
  try
    fActive.Add(aAsync);
  finally
    fLock.Leave;
  end;
end;

class procedure TmaxAsyncScheduler.Untrack(const aAsync: iAsync);
var
  lIndex: Integer;
begin
  if aAsync = nil then
    Exit;
  fLock.Enter;
  try
    lIndex := fActive.IndexOf(aAsync);
    if lIndex >= 0 then
      fActive.Delete(lIndex);
  finally
    fLock.Leave;
  end;
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
    TmaxAsyncScheduler.Untrack(FHandle);
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
  task: TMaxAsyncTask;
  handle: iAsync;
begin
  if not ProcAssigned(aProc) then
    Exit;
  task := TMaxAsyncTask.Create(aProc, aDelayUs);
  try
    handle := SimpleAsyncCall(task.Execute, '', task.AfterDone);
  except
    task.Free;
    raise;
  end;
  task.AttachHandle(handle);
  Track(handle);
end;

procedure TmaxAsyncScheduler.RunAsync(aProc: TmaxProc);
begin
  ScheduleAsync(aProc, 0);
end;

procedure TmaxAsyncScheduler.RunDelayed(const aProc: TmaxProc; aDelayUs: Integer);
begin
  ScheduleAsync(aProc, aDelayUs);
end;

procedure TmaxAsyncScheduler.RunOnMain(const aProc: TmaxProc);
var
  adapter: TMainQueueAdapter;
begin
  if not ProcAssigned(aProc) then
    Exit;
  if IsMainThread() then
    aProc()
  else
  begin
    adapter := TMainQueueAdapter.Create(aProc);
    try
      TThread.Queue(nil, adapter.Invoke);
    except
      adapter.Free;
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
