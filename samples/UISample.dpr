program UISample;

{$APPTYPE GUI}

uses
  System.Classes,
  System.SysUtils,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  maxLogic.EventNexus in '..\maxLogic.EventNexus.pas',
  maxLogic.EventNexus.Core in '..\maxLogic.EventNexus.Core.pas';

type
  TMainForm = class(TForm)
  private
    fLabel: TLabel;
    fButton: TButton;
    fWorker: TThread;
    fSub: ImaxSubscription;
    procedure StartClicked(Sender: TObject);
    procedure OnValue(const aValue: Integer);
  public
    constructor Create(aOwner: TComponent); override;
    destructor Destroy; override;
  end;

  TProducer = class(TThread)
  protected
    procedure Execute; override;
  end;

constructor TMainForm.Create(aOwner: TComponent);
begin
  inherited Create(aOwner);
  Width := 200;
  Height := 100;
  Caption := 'EventNexus UI';
  fLabel := TLabel.Create(Self);
  fLabel.Parent := Self;
  fLabel.Align := alTop;
  fLabel.Caption := '0';
  fButton := TButton.Create(Self);
  fButton.Parent := Self;
  fButton.Align := alBottom;
  fButton.Caption := 'Start';
  fButton.OnClick := StartClicked;
end;

destructor TMainForm.Destroy;
begin
  if Assigned(fSub) then
    fSub.Unsubscribe;
  if Assigned(fWorker) then
    fWorker.WaitFor;
  fWorker.Free;
  inherited Destroy;
end;

procedure TMainForm.StartClicked(Sender: TObject);
var
  lBusObj: TmaxBus;
begin
  if Assigned(fWorker) then
    Exit;
  fButton.Enabled := False;
  lBusObj := maxBusObj(maxBus);
  lBusObj.EnableCoalesceOf<Integer>(
    function(const aValue: Integer): TmaxString
    begin
      Result := '';
    end,
    100000);
  fSub := lBusObj.Subscribe<Integer>(OnValue, TmaxDelivery.Main);
  fWorker := TProducer.Create(False);
end;

procedure TMainForm.OnValue(const aValue: Integer);
begin
  fLabel.Caption := IntToStr(aValue);
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
  lForm: TMainForm;
begin
  Application.Initialize;
  Application.CreateForm(TMainForm, lForm);
  Application.Run;
end.
