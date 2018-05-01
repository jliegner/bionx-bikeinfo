{ Copyright (C) 2018 Thorsten Schmidt (tschmidt@ts-soft.de)              }
{     www.ts-soft.de                                                     }
{ and Juergen Liegner (juergen@liegner.de)                               }
{                                                                        }
{ This program is free software; you can redistribute it and/or modify   }
{ it under the terms of the GNU General Public License as published by   }
{ the Free Software Foundation; either version 2 of the License, or      }
{ (at your option) any later version.                                    }
{                                                                        }
{ This program is distributed in the hope that it will be useful,        }
{ but WITHOUT ANY WARRANTY; without even the implied warranty of         }
{ MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the          }
{ GNU General Public License for more details.                           }
{                                                                        }
{ You should have received a copy of the GNU General Public License      }
{ along with this program; if not, write to the Free Software            }
{ Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.              }

unit SLCANAdapter;
interface
uses
  SynaSer,
  CANAdapter;

type
  TSLCANAdapter = class ( TCANAdapter )
  private
    FSerialPort : TBlockSerial;
    FFirmwareVersion : string;
  protected
  public
    constructor Create; override;
    destructor Destroy; override;

    function Connect : boolean; override;
    procedure Disconnect; override;
    procedure ClearCANRxBuffer; override;
    function SendCANMsg ( Id : DWORD; Len : byte; CANData : PCANData ) : boolean; override;
    function ReadCANMsg ( out Id : DWORD; out Len : byte; CANData : PCANData ) : boolean; override;
  end;

implementation
uses
  SysUtils,
  IniFiles,
  fmSerialPort;

const
  section_SLCAN            = 'SLCAN';
    entry_Port              = 'Port';
    default_Port            = 'COM1';

constructor TSLCANAdapter.Create;
begin
  inherited;
  FSerialPort := TBlockSerial.Create;
end;

destructor TSLCANAdapter.Destroy;
begin
  FSerialPort.Free;
  inherited;
end;

function TSLCANAdapter.Connect : boolean;
var
  IniFile : TIniFile;
  PortId : string;
  Baudrate : string;
  s : string;
begin
  Result := false;

{$IFDEF MSWINDOWS}
  IniFile := TIniFile.Create ( GetAppConfigFile(true) );
{$ELSE}
  IniFile := TIniFile.Create ( GetAppConfigFile(false) );
{$ENDIF}
  try
    PortId := IniFile.ReadString ( section_SLCAN, entry_Port, default_Port );
    Baudrate := IniFile.ReadString ( section_SLCAN, 'Baudrate', '115200' );

    // PortId := '/dev/tty.usbmodem621';
    if GetSerialPortnameAndBaudrate ( PortId, Baudrate ) then
    begin
      IniFile.WriteString ( section_SLCAN, entry_Port, PortId );
      IniFile.WriteString ( section_SLCAN, 'baudrate', Baudrate );
      FSerialPort.Connect ( PortId );
      if FSerialPort.LastError = 0 then
      begin
        // setup serial parameters
        FSerialPort.ConvertLineEnd := true;
        FSerialPort.Config ( StrToInt(Baudrate), 8, 'N', SB1, false, False);
        if FSerialPort.LastError = 0 then
        begin
          // Connect To SLCAN Adapter

          // close a open channal
          FSerialPort.SendString('C'#13);
          FSerialPort.RecvString(300);
          FSerialPort.Purge;

          FSerialPort.SendString('V'#13);
          s := FSerialPort.RecvString( 300 );

          FSerialPort.SendString('v'#13);
          s := FSerialPort.RecvString( 300 );
          FFirmwareVersion := s;

          // 125kbaud
          FSerialPort.SendString('S4'#13);
          s := FSerialPort.RecvString( 300 );
          if (s <> '') or (FSerialPort.LastError <> 0) then
            raise Exception.CreateFmt ( 'Adapter error 1', [] );

          // timestamp aus
          FSerialPort.SendString('Z0'#13);
          s := FSerialPort.RecvString( 300 );
          if (s <> '') or (FSerialPort.LastError <> 0) then
            raise Exception.CreateFmt ( 'Adapter error 2', [] );

          // Kanal oeffnen
          FSerialPort.SendString('O'#13);
          s := FSerialPort.RecvString( 300 );
          if (s <> '') or (FSerialPort.LastError <> 0) then
            raise Exception.CreateFmt ( 'Adapter error 3', [] );
          Result := true;
        end
        else
          raise Exception.CreateFmt ( 'configuration of port %s failed'#13'%s', [ PortId, FSerialPort.LastErrorDesc] );
      end
      else
        raise Exception.CreateFmt ( 'could not open serial port %s'#13'%s', [ PortId, FSerialPort.LastErrorDesc] );
    end;
  finally
     IniFile.Free;
  end;
end;

procedure TSLCANAdapter.Disconnect;
begin
  // terminate bridge mode
  if FSerialPort.InstanceActive then
  begin
    FSerialPort.SendString( 'C'#13 );
    FSerialPort.RecvString( 100 );
    FSerialPort.SendString( 'C'#13 );
    FSerialPort.RecvString( 100 );
    FSerialPort.SendString( 'C'#13 );
    FSerialPort.RecvString( 300 );
  end;
end;

procedure TSLCANAdapter.ClearCANRxBuffer;
begin
  // clean the serial buffer
  FSerialPort.Purge;
end;

function TSLCANAdapter.SendCANMsg ( Id : DWORD; Len : byte; CANData : PCANData ) : boolean;
var
  s : string;
  i : integer;
begin
  if Id < 1000 then
    begin
      s := 't';
      s := s + IntToHex(Id,3);
      s := s + IntToHex(Len,1);
    end
  else
    begin
      s := 'T';
      s := s + IntToHex(Id,8);
      s := s + IntToHex(Len,1);
    end;

  For i:=0 to (Len-1) do
  begin
    s := s + IntToHex(CANData^[i],2);
  end;

  s := s+#13;
  FSerialPort.SendString(s);

  for i:=0 to 100 do
  begin
    s:=FSerialPort.RecvString(100);

    if (s='') or (FSerialPort.LastError <> 0) then
      break;

    if (s='z') or (s='Z') then
      exit(true);
  end;
  Result := false;
end;

function TSLCANAdapter.ReadCANMsg ( out Id : DWORD; out Len : byte; CANData : PCANData ) : boolean;

var s : string;
    sh: string;
    i : integer;

begin
  while true do
  begin
    s:=FSerialPort.RecvString(100);
    if (s='') then
      exit(false);

//    if (s='z') then
//      continue;

    if (s[1]='t') and (length(s)>4) then
    begin
      sh:='0x'+copy(s,2,3);
      Id:=StrToInt(sh);

      sh:='0x'+copy(s,5,1);
      Len:=StrToInt(sh);

      For i:=0 to (Len-1) do
      begin
        sh:='0x'+copy(s,6+i*2,2);
        CANData^[i]:=StrToInt(sh);
      end;
      exit(true);
    end;
    exit(false);
  end;
end;


end.
