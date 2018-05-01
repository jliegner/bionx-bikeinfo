{ Copyright (C) 2013 Thorsten Schmidt (tschmidt@ts-soft.de)              }
{     www.ts-soft.de                                                     }
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
{                                                                        }
{ Portions of this software are taken and adapted from BigXionFlasher    }
{ published by Thomas König <info@bigxionflasher.org>                    }

unit TinyCANAdapter;

{$mode objfpc}{$H+}

interface

uses
  Classes,
  SyncObjs,
  CANAdapter,
  TinyCANDrv;

type
  THandleCANMessage = procedure ( aMsg : PCANMsg ) of object;

type
  TEventThread = class ( TThread )
  private
    FMsg      : TCanMsg;
    FEvent : TSimpleEvent;
    FHandleCANMessage : THandleCANMessage;
  protected
    procedure Execute; override;
    procedure QueueCanMsg ( aMsg : PCanMsg );
    function FetchCanMsg ( out aMsg : TCanMsg ) : boolean;
  public
    constructor Create ( aHandleCANMessage : THandleCANMessage );
    destructor Destroy; override;
  end;


  // implementation of a CAN bus driver wrapper using the TinyCAN with it's
  // library dll as adapter.
  // Write your own descandant, when using other hardware. Implement at least
  // the virtual abstract methods Connect, Disconnect, ReadByte and WriteByte
type
  TTinyCANAdapter = class ( TCANAdapter )
  private
    FLogMsg  : TLogMsg;
    FTinyCAN : TTinyCAN;
    FMsgHandler : TEventThread;
    procedure LogMsg ( aMsg : PCANMsg );
    procedure LogMsg ( const Msg : string );
    function SendCanMsg ( Msg : TCanMsg ) : boolean;
    function WaitForCanMsg ( var Msg : TCanMsg; Reg : byte ) : boolean;
    procedure TinyCanRxDEvent (Sender: TObject; index: DWORD; msg: PCanMsg; count: Integer);
  protected
  public
    constructor Create ( ALogMsg : TLogMsg );
    destructor Destroy; override;
    function Connect : boolean; override;
    procedure Disconnect; override;

    function ReadByte ( Id : byte; Reg : byte ) : byte; override;
    procedure WriteByte ( Id : byte; Reg : byte; Value : byte ); override;

//    property _TinyCAN : TTinyCAN read FTinyCAN;

    procedure StartMessageCapturing ( aHandleCANMessage : THandleCANMessage );
    procedure StopMessageCapturing;
  end;

implementation
uses
  SysUtils;

const
  MilliSecond = 1.0 / MSecsPerDay;

procedure InitMsg ( out Msg : TCanMsg; Id : byte; Reg : byte );
begin
  fillchar ( Msg, sizeof ( Msg ), 0 );
  Msg.Id := Id;
  Msg.Data.Bytes[1] := Reg;
end;

procedure InitSetMsg ( out Msg : TCanMsg; Id : byte; Reg : byte; Value : byte );
begin
  InitMsg ( Msg, Id, Reg );
  Msg.Flags := 4;
  Msg.Data.Bytes[3] := Value;
end;

procedure InitGetMsg ( out Msg : TCanMsg; Id : byte; Reg : byte );
begin
  InitMsg ( Msg, Id, Reg );
  Msg.Flags := 2;
end;

function MsgToStr ( Msg : TCanMsg ) : string;
begin
  Result := Format ( 'Id=%0.2x, Flags=%0.4x, Data=%0.2x %0.2x %0.2x %0.2x %0.2x %0.2x %0.2x %0.2x', [Msg.Id, Msg.Flags, Msg.Data.Bytes[0], Msg.Data.Bytes[1], Msg.Data.Bytes[2], Msg.Data.Bytes[3], Msg.Data.Bytes[4], Msg.Data.Bytes[5], Msg.Data.Bytes[6], Msg.Data.Bytes[7]] );
end;

constructor TTinyCANAdapter.Create ( ALogMsg : TLogMsg );
begin
  inherited Create;
  FLogMsg  := aLogMsg;
  FTinyCAN := TTinyCAN.Create ( nil );
end;

destructor TTinyCANAdapter.Destroy;
begin
  FTinyCAN.Free;
  inherited;
end;

function TTinyCANAdapter.Connect : boolean;
var
  errcode : integer;
  status : TDeviceStatus;
begin
  Result := false;
  errcode := FTinyCAN.LoadDriver;
  if errcode >= 0 then
  begin
    try
      errcode := FTinyCAN.CanSetMode( 0, OP_CAN_START, CAN_CMD_ALL_CLEAR );
      if errcode = 0 then
      begin
        errcode := FTinyCAN.CanGetDeviceStatus(0, @status);
        if errcode = 0 then
        begin
          if (Status.DrvStatus >= DRV_STATUS_CAN_OPEN) then
          begin
            if (Status.CanStatus = CAN_STATUS_BUS_OFF) then
              FTinyCAN.CanSetMode(0, OP_CAN_RESET, CAN_CMD_NONE);
            Result := true;
          end
          else
            raise ECANError.Create ( 'cannot not open device' );
        end
        else
          raise ECANError.CreateFmt ( 'cannot get device status', [errcode] );
      end
      else
        raise ECANError.CreateFmt ( 'cannot start CAN bus', [errcode] );
    except
      Disconnect;
      raise;
    end;
  end
  else
  begin
    if errcode = -2 then
      raise ECANError.Create ( 'cannot open port' )
    else
      if errcode = -1 then
        raise ECANError.Create ( 'cannot load driver dll' );
  end;
end;

procedure TTinyCANAdapter.Disconnect;
begin
  FTinyCAN.CanSetMode( 0, OP_CAN_STOP, CAN_CMD_ALL_CLEAR );
  FTinyCAN.DownDriver;
end;

procedure TTInyCANAdapter.LogMsg ( aMsg : PCANMsg );
begin
  ;
end;

procedure TTInyCANAdapter.LogMsg ( const Msg : string );
begin
  if assigned ( FLogMsg ) then
    FLogMsg ( Msg );
end;


function TTinyCANAdapter.SendCanMsg ( Msg : TCanMsg ) : boolean;
var
  TimeoutTime : TDateTime;
  errcode     : integer;
begin
  Result := false;
  LogMsg ( 'Tx: ' + MsgToStr ( Msg ) );
  TimeoutTime := Now + 500 * MilliSecond;
  // note:
  // previous dll versions returned 0 on CanTransmit success,
  // from 4.09 the function returns the number of messages sent,
  // 0, if the TX-FIFO is full or an errorcode < 0
  // Therefore, we wait for the FIFO emtpty and then may test the
  // CanTransmit success >= 0 on all dll versions
  // >0 will be true with new dll
  // =0 will be true woth old dll
  while ( FTinyCAN.CanTransmitGetCount(0) > 0 ) and
        ( TimeoutTime > Now )  do
    sleep ( 1 );

  errcode := FTinyCAN.CanTransmit ( 0, @Msg, 1 );
  if ( errcode >= 0 ) then
  begin
    repeat
      sleep ( 1 );
      Result := FTinyCAN.CanTransmitGetCount(0) = 0;
    until Result or ( TimeoutTime < Now );
  end
  else
    raise ECANError.CreateFmt ( 'cannot transmit message (%d)', [errcode] );
end;

function TTinyCANAdapter.WaitForCanMsg ( var Msg : TCanMsg; Reg : byte ) : boolean;
var
  TimeoutTime : TTime;
  errcode     : integer;
begin
  Result := false;
  TimeoutTime := Now + 1500 * MilliSecond;

  while ( TimeoutTime > Now ) and ( not Result ) do
  begin
    if (FTinyCAN.CanReceiveGetCount(0) > 0) then
    begin
      errcode := FTinyCAN.CanReceive(0, @Msg, 1);
      if errcode = 1 then
      begin
        LogMsg ( 'Rx: ' + MsgToStr ( Msg ) );
        Result := ( ((Msg.Flags and FlagsCanLength) = 4) and (Msg.Data.Bytes[1] = Reg) )
      end
      else
        raise ECANError.CreateFmt ( 'cannot receive message (%d)', [errcode] );
    end
    else
      Sleep ( 1 );
  end;
end;

procedure TTinyCANAdapter.TinyCanRxDEvent (Sender: TObject; index: DWORD; msg: PCanMsg; count: Integer);
var
  i : integer;
begin
  if index = 0 then
  begin
    for i:=1 to count do
    begin
      FMsgHandler.QueueCanMsg( msg );
      inc(msg);
    end;
  end
//  else
//    FMsgs.Add ( 'Rx: Idx 0 '+MsgToStr ( Msg^ ) );
end;

function TTinyCANAdapter.ReadByte ( Id : byte; Reg : byte ) : byte;
var
  Msg : TCanMsg;
begin
  // empty the TinyCAN Rx buffers.
  FTinyCAN.CanSetMode( 0, OP_CAN_NONE, CAN_CMD_RXD_FIFOS_CLEAR );
  FTinyCAN.CanReceiveClear(0);

  Result := 0;
  InitGetMsg ( Msg, Id, Reg );

  try
    if SendCanMsg ( Msg ) then
    begin
      // we have cleaned the Rx buffer above. One of the next messages should be
      // the answer, we are waiting for
      if WaitForCanMsg ( Msg, Reg ) then
        Result := Msg.Data.Bytes[3]
      else
        raise ECANError.CreateFmt ( 'no response from node %0.2x', [Id] );
    end
    else
      raise ECANError.CreateFmt ( 'could not send request to node %0.2x', [Id] );
  except
    on E:Exception do
      raise ECANError.CreateFmt ( 'could not read register %0.2x from node %0.2x'#13+E.Message, [Reg, Id] );
  end;
end;

procedure TTinyCANAdapter.WriteByte ( Id : byte; Reg : byte; Value : byte );
var
  Msg : TCanMsg;
begin
  try
    InitSetMsg ( Msg, Id, Reg, Value );
    if not SendCanMsg ( Msg ) then
      raise ECANError.CreateFmt ( 'could not send value to node %0.2x', [Id]);
  except
    on E:Exception do
      raise ECANError.CreateFmt ( 'could not write register %0.2x to node %0.2x'#13+E.Message, [Reg, Id] );
  end;
end;

procedure TTinyCANAdapter.StartMessageCapturing ( aHandleCANMessage : THandleCANMessage );
begin
  FMsgHandler := TEventThread.Create ( aHandleCANMessage );

  FTinyCAN.OnCanRxDEvent:= @TinyCanRxDEvent;
  FTinyCAN.CanSetEvents( [RX_MESSAGES_EVENT] );
end;

procedure TTinyCANAdapter.StopMessageCapturing;
begin
  FTinyCAN.CanSetEvents( [] );
  FTinyCAN.OnCanRxDEvent:= nil;

  FMsgHandler.Terminate;
end;

constructor TEventThread.Create ( aHandleCANMessage : THandleCANMessage );
begin
  inherited Create ( false );
  FHandleCANMessage := aHandleCANMessage;
  FreeOnTerminate := true;
  FEvent := TSimpleEvent.Create;
end;

destructor TEventThread.Destroy;
begin
  FEvent.Free;
  inherited;
end;

procedure TEventThread.QueueCanMsg ( aMsg : PCanMsg );
begin
  FMsg := aMsg^;
  FEvent.SetEvent;
end;

function TEventThread.FetchCanMsg ( out aMsg : TCanMsg ) : boolean;
begin
  aMsg := FMsg;
end;

procedure TEventThread.Execute;
begin
  while not Terminated do
  begin
    if FEvent.WaitFor( 1 ) = wrSignaled then
    begin
      FHandleCANMessage ( @FMsg );
      FEvent.ResetEvent;
    end;
  end;
end;

end.

