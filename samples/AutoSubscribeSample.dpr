program AutoSubscribeSample;

{$APPTYPE CONSOLE}
{$RTTI EXPLICIT METHODS([vcPublic, vcProtected])}

uses
  SysUtils,
  maxLogic.EventNexus,
  maxLogic.EventNexus.Core;

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
  lBusObj: TmaxBus;
  lWorker: TWorker;
begin
  lBusObj := maxBusObj(maxBus);
  lWorker := TWorker.Create;
  try
    AutoSubscribe(lWorker);
    lBusObj.Post<Integer>(42);
    AutoUnsubscribe(lWorker);
  finally
    lWorker.Free;
  end;
end.
