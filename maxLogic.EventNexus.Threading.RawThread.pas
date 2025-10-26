unit {$IFDEF max_FPC}maxLogic_EventNexus_Threading_RawThread{$ELSE}maxLogic.EventNexus.Threading.RawThread{$ENDIF};

{$I fpc_delphimode.inc}

{$IFDEF FPC}
  {$DEFINE max_FPC}
{$ELSE}
  {$DEFINE max_DELPHI}
{$ENDIF}

interface

uses
  Classes, SysUtils,
  {$IFDEF max_FPC} maxLogic_EventNexus_Threading_Adapter {$ELSE} maxLogic.EventNexus.Threading.Adapter {$ENDIF};

type
  TmaxRawThreadScheduler = class(TInterfacedObject, IEventNexusScheduler)
  public
    procedure RunAsync(aProc: TmaxProc);
    procedure RunOnMain(const aProc: TmaxProc);
    procedure RunDelayed(const aProc: TmaxProc; aDelayUs: Integer);
    function IsMainThread: Boolean;
  end;

implementation

type
  TmaxProcAdapter = class
  private
    fProc: TmaxProc;
  public
    constructor Create(const aProc: TmaxProc);
    procedure Invoke;
  end;

  TmaxProcThread = class(TThread)
  private
    fProc: TmaxProc;
    fDelayUs: Integer;
  protected
    procedure Execute; override;
  public
    constructor Create(const aProc: TmaxProc; aDelayUs: Integer);
    class procedure Start(const aProc: TmaxProc; aDelayUs: Integer = 0); static;
  end;

{ TmaxProcAdapter }

constructor TmaxProcAdapter.Create(const aProc: TmaxProc);
begin
  inherited Create;
  fProc := aProc;
end;

procedure TmaxProcAdapter.Invoke;
var
  lProc: TmaxProc;
begin
  lProc := fProc;
  try
    if ProcAssigned(lProc) then
      lProc();
  finally
    Free;
  end;
end;

{ TmaxProcThread }

constructor TmaxProcThread.Create(const aProc: TmaxProc; aDelayUs: Integer);
begin
  inherited Create(True);
  FreeOnTerminate := True;
  fProc := aProc;
  if aDelayUs > 0 then
    fDelayUs := aDelayUs
  else
    fDelayUs := 0;
end;

procedure TmaxProcThread.Execute;
var
  lProc: TmaxProc;
  lDelayMs: Integer;
begin
  lProc := fProc;
  fProc := nil;
  if fDelayUs > 0 then
  begin
    lDelayMs := fDelayUs div 1000;
    if lDelayMs > 0 then
      TThread.Sleep(lDelayMs);
  end;
  if ProcAssigned(lProc) then
    lProc();
end;

class procedure TmaxProcThread.Start(const aProc: TmaxProc; aDelayUs: Integer);
var
  lThread: TmaxProcThread;
begin
  if not ProcAssigned(aProc) then
    Exit;
  lThread := TmaxProcThread.Create(aProc, aDelayUs);
  TThread(lThread).Start;
end;

{ TmaxRawThreadScheduler }

procedure TmaxRawThreadScheduler.RunAsync(aProc: TmaxProc);
begin
  TmaxProcThread.Start(aProc);
end;

procedure TmaxRawThreadScheduler.RunOnMain(const aProc: TmaxProc);
var
  lAdapter: TmaxProcAdapter;
begin
  if not ProcAssigned(aProc) then
    Exit;
  lAdapter := TmaxProcAdapter.Create(aProc);
  try
    TThread.Queue(nil, lAdapter.Invoke);
  except
    lAdapter.Free;
    raise;
  end;
end;

procedure TmaxRawThreadScheduler.RunDelayed(const aProc: TmaxProc; aDelayUs: Integer);
var
  lDelay: Integer;
begin
  if aDelayUs < 0 then
    lDelay := 0
  else
    lDelay := aDelayUs;
  TmaxProcThread.Start(aProc, lDelay);
end;

function TmaxRawThreadScheduler.IsMainThread: Boolean;
begin
  Result := TThread.CurrentThread.ThreadID = MainThreadID;
end;

end.
