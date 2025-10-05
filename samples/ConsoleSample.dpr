program ConsoleSample;

{$I ..\..\MaxLogicFoundation\fpc_delphimode.inc}
{$APPTYPE CONSOLE}

uses
  SysUtils,
  maxLogic.EventNexus;

type
  ITextMsg = interface
    ['{E4D4C2A1-89D4-4F8C-8A25-5FA3086C35F0}']
    function Text: string;
  end;

  TTextMsg = class(TInterfacedObject, ITextMsg)
  private
    fText: string;
  public
    constructor Create(const aText: string);
    function Text: string;
  end;

constructor TTextMsg.Create(const aText: string);
begin
  inherited Create;
  fText := aText;
end;

function TTextMsg.Text: string;
begin
  Result := fText;
end;

  var
    lBus: IMLBus;
    lPolicy: TMLQueuePolicy;
    lSub: IMLSubscription;

procedure OnInt(const aValue: Integer);
begin
  Writeln('typed: ', aValue);
end;

procedure OnNamed;
begin
  Writeln('named');
end;

procedure OnGuid(const aValue: ITextMsg);
begin
  Writeln('guid: ', aValue.Text);
end;

procedure OnAsync(const aValue: string);
begin
  Writeln('async: ', aValue);
end;

function KeyOfInt(const aValue: Integer): TMLString;
begin
  Result := IntToStr(aValue mod 10);
end;

  begin
    lBus := MLBus;

  lPolicy.MaxDepth := 1;
  lPolicy.Overflow := DropOldest;
  lPolicy.DeadlineUs := 0;
    (lBus as IMLBusQueues).SetPolicyFor<Integer>(lPolicy);
    (lBus as IMLBusAdvanced).EnableSticky<Integer>(True);
{$IFDEF FPC}
    (lBus as IMLBusAdvanced).EnableCoalesceOf<Integer>(@KeyOfInt);
    lSub := lBus.Subscribe<Integer>(@OnInt);
    lBus.SubscribeNamed('tick', @OnNamed);
    lBus.SubscribeGuidOf<ITextMsg>(@OnGuid);
    lBus.Subscribe<string>(@OnAsync, TMLDelivery.Async);
{$ELSE}
    (lBus as IMLBusAdvanced).EnableCoalesceOf<Integer>(KeyOfInt);
    lSub := lBus.Subscribe<Integer>(OnInt);
    lBus.SubscribeNamed('tick', OnNamed);
    lBus.SubscribeGuidOf<ITextMsg>(OnGuid);
    lBus.Subscribe<string>(OnAsync, TMLDelivery.Async);
{$ENDIF}

  lBus.Post<Integer>(1);
  lBus.Post<Integer>(2);
  lBus.Post<Integer>(12);
  Sleep(50);

  lBus.PostNamed('tick');
  lBus.PostGuidOf<ITextMsg>(TTextMsg.Create('hello'));
  lBus.Post<string>('world');
  Sleep(50);
  lSub.Unsubscribe;
end.

