program UISampleConsole;

{$APPTYPE CONSOLE}

uses
  Classes,
  SysUtils,
  maxLogic.EventNexus,
  maxLogic.EventNexus.Core;

function KeyOf(const aValue: Integer): TmaxString;
begin
  Result := '';
end;

var
  gDone: Boolean;

procedure OnValue(const aValue: Integer);
begin
  Writeln('value ', aValue);
  if aValue >= 1000 then
    gDone := True;
end;

type
  TProducer = class(TThread)
  protected
    procedure Execute; override;
  end;

procedure TProducer.Execute;
var
  i: Integer;
begin
  for i := 1 to 1000 do
  begin
    maxBusObj(maxBus).Post<Integer>(i);
    Sleep(1);
  end;
end;

var
  lProd: TProducer;
  lBusObj: TmaxBus;
  lSub: ImaxSubscription;
begin
  lBusObj := maxBusObj(maxBus);
  lBusObj.EnableCoalesceOf<Integer>(KeyOf, 100000);
  lSub := lBusObj.Subscribe<Integer>(OnValue, TmaxDelivery.Main);
  lProd := TProducer.Create(False);
  while not gDone do
    CheckSynchronize(10);
  lProd.WaitFor;
  lProd.Free;
  lSub.Unsubscribe;
end.
