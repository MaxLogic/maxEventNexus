unit maxLogic.EventNexus.Threading.TTask;

{$I fpc_delphimode.inc}

{$IFDEF FPC}
  {$MESSAGE ERROR 'maxLogic.EventNexus.Threading.TTask requires Delphi with TTask support.'}
{$ENDIF}

interface

uses
  System.Classes, System.SysUtils, System.Threading,
  maxLogic.EventNexus.Threading.Adapter;

type
  TmaxTTaskScheduler = class(TInterfacedObject, IEventNexusScheduler)
  public
    procedure RunAsync(aProc: TmaxProc);
    procedure RunOnMain(const aProc: TmaxProc);
    procedure RunDelayed(const aProc: TmaxProc; aDelayUs: Integer);
    function IsMainThread: Boolean;
  end;

function CreateTTaskScheduler: IEventNexusScheduler;

implementation

procedure TmaxTTaskScheduler.RunAsync(aProc: TmaxProc);
begin
  if not ProcAssigned(aProc) then
    Exit;
  TTask.Run(
    procedure
    begin
      aProc();
    end);
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
    end);
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
