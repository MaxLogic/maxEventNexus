program ManualSubscribeSample;

{$APPTYPE CONSOLE}

uses
  SysUtils,
  maxLogic.EventNexus;

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
  lBus: TmaxBus;
  lWorker: TWorker;
  lSub: ImaxSubscription;
begin
  lBus := maxBusObj;
  lWorker := TWorker.Create;
  try
    lSub := lBus.Subscribe<Integer>(lWorker.OnPing);
    lBus.Post<Integer>(42);
    lSub.Unsubscribe;
  finally
    lWorker.Free;
  end;
end.
