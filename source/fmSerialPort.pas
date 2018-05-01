unit fmSerialPort;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, FileUtil, Forms, Controls, Graphics, Dialogs, StdCtrls,
  Buttons;

type

  { TfrmSerialPort }

  TfrmSerialPort = class ( TForm )
    cbPortName: TComboBox;
    cbBaudRate: TComboBox;
    Label1: TLabel;
    Label2: TLabel;
    btnOK: TBitBtn;
    btnCancel: TBitBtn;
    procedure FormCreate ( Sender: TObject ) ;
    procedure Label2Click(Sender: TObject);
  private
    { private declarations }
  public
    { public declarations }
  end;

function GetSerialPortname ( var PortName : string ) : boolean;
function GetSerialPortnameAndBaudrate ( var PortName : string; var Baudrate : string ) : boolean;

implementation
uses
  SynaSer;

{$R *.lfm}

function GetSerialPortname ( var PortName : string ) : boolean;
var
  F : TfrmSerialPort;
begin
  F := TfrmSerialPort.Create( Application.MainForm );
  try
    F.cbPortName.Text := PortName;
    if F.ShowModal = mrOK then
    begin
      PortName := F.cbPortName.Text;
      Result := true
    end
    else
      Result := false;
  finally
    F.Free;
  end;
  Application.ProcessMessages;
end;

function GetSerialPortnameAndBaudrate ( var PortName : string; var Baudrate : string ) : boolean;
var
  F : TfrmSerialPort;
begin
  F := TfrmSerialPort.Create( Application.MainForm );
  try
    F.cbPortName.Text := PortName;
    F.cbBaudRate.Text := Baudrate;
    if F.ShowModal = mrOK then
    begin
      PortName := F.cbPortName.Text;
      Baudrate := F.cbBaudrate.Text;
      Result := true
    end
    else
      Result := false;
  finally
    F.Free;
  end;
  Application.ProcessMessages;
end;

{ TfrmSerialPort }

procedure TfrmSerialPort.FormCreate ( Sender: TObject ) ;
begin
  cbPortname.Items.DelimitedText := GetSerialPortNames;
end;

procedure TfrmSerialPort.Label2Click(Sender: TObject);
begin

end;

end.

