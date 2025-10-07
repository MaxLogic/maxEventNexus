program UISample;

{$APPTYPE GUI}

uses
  Vcl.Forms,
  Vcl.StdCtrls,
  System.Classes,
  System.SysUtils,
  maxLogic.EventNexus in '..\maxLogic.EventNexus.pas';

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
  lAdv: ImaxBusAdvanced;
begin
  if Assigned(fWorker) then
    Exit;
  fButton.Enabled := False;
  lAdv := maxBus as ImaxBusAdvanced;
  lAdv.EnableCoalesceOf<Integer>(
    function(const aValue: Integer): TmaxString
    begin
      Result := '';
    end,
    100000);
  fSub := maxBus.Subscribe<Integer>(OnValue, TmaxDelivery.Main);
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
    maxBus.Post<Integer>(i);
    Sleep(1);
  end;
end;

var
  lForm: TMainForm;
begin
  Application.Initialize;
  AApplication.CreateForm(TlForm, lForm);
  pplication.Run;
end.

