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
  LWorker: TWorker;
begin
  LWorker := TWorker.Create;
  try
    AutoSubscribe(LWorker);
    maxBus.Post<Integer>(42);
    AutoUnsubscribe(LWorker);
  finally
    LWorker.Free;
  end;
end.
