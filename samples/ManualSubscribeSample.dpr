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
  lWorker: TWorker;
  lSub: ImaxSubscription;
begin
  lWorker := TWorker.Create;
  try
    lSub := maxBus.Subscribe<Integer>(lWorker.OnPing);
    maxBus.Post<Integer>(42);
    lSub.Unsubscribe;
  finally
    lWorker.Free;
  end;
end.
