program AutoSubscribeSample;

{$APPTYPE CONSOLE}
{$RTTI EXPLICIT METHODS([vcPublic, vcProtected])}

uses
  SysUtils,
  maxLogic.EventNexus;

type
  TWorker = class
  public
    [maxSubscribe]
    procedure OnPing(const aValue: Integer);
  end;

procedure TWorker.OnPing(const aValue: Integer);
begin
  Writeln('ping ', aValue);
end;

var
  lBus: TmaxBus;
  lWorker: TWorker;
begin
  lBus := maxBusObj;
  lWorker := TWorker.Create;
  try
    AutoSubscribe(lWorker);
    lBus.Post<Integer>(42);
    AutoUnsubscribe(lWorker);
  finally
    lWorker.Free;
  end;
end.
