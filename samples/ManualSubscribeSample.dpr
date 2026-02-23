program ManualSubscribeSample;

{$APPTYPE CONSOLE}

uses
  SysUtils,
  maxLogic.EventNexus,
  maxLogic.EventNexus.Core;

type
  TWorker = class
  public
    procedure OnPing(const aValue: Integer);
  end;

procedure TWorker.OnPing(const aValue: Integer);
begin
  Writeln('ping ', aValue);
end;

var
  lBusObj: TmaxBus;
  lWorker: TWorker;
  lSub: ImaxSubscription;
begin
  lBusObj := maxBusObj(maxBus);
  lWorker := TWorker.Create;
  try
    lSub := lBusObj.Subscribe<Integer>(lWorker.OnPing);
    lBusObj.Post<Integer>(42);
    lSub.Unsubscribe;
  finally
    lWorker.Free;
  end;
end.
