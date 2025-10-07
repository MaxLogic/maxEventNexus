program ConsoleSample;

{$I ../fpc_delphimode.inc}
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
    lBus: ImaxBus;
    lPolicy: TmaxQueuePolicy;
    lSub: ImaxSubscription;

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

function KeyOfInt(const aValue: Integer): TmaxString;
begin
  Result := IntToStr(aValue mod 10);
end;

  begin
    lBus := maxBus;

  lPolicy.MaxDepth := 1;
  lPolicy.Overflow := DropOldest;
  lPolicy.DeadlineUs := 0;
    (lBus as ImaxBusQueues).SetPolicyFor<Integer>(lPolicy);
    (lBus as ImaxBusAdvanced).EnableSticky<Integer>(True);
{$IFDEF FPC}
    (lBus as ImaxBusAdvanced).EnableCoalesceOf<Integer>(@KeyOfInt);
    lSub := lBus.Subscribe<Integer>(@OnInt);
    lBus.SubscribeNamed('tick', @OnNamed);
    lBus.SubscribeGuidOf<ITextMsg>(@OnGuid);
    lBus.Subscribe<string>(@OnAsync, TmaxDelivery.Async);
{$ELSE}
    (lBus as ImaxBusAdvanced).EnableCoalesceOf<Integer>(KeyOfInt);
    lSub := lBus.Subscribe<Integer>(OnInt);
    lBus.SubscribeNamed('tick', OnNamed);
    lBus.SubscribeGuidOf<ITextMsg>(OnGuid);
    lBus.Subscribe<string>(OnAsync, TmaxDelivery.Async);
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

