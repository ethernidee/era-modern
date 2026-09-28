unit ProcessApi;
(*
  Process management.
*)

(***)  interface  (***)

uses
  SysUtils,
  Windows,

  CmdApp,
  Concur,
  DataLib,
  FastRand,
  StrLib,
  UtilsB2,
  WinUtils,

  EventMan,
  GameExt,
  Legacy;


(* Returns 32-character unique key for current game process. The ID will be unique between multiple game runs. *)
function GetCurrentProcessGuid: myAStr;

(* Starts current process clone with the same command line arguments and exits current process. Suitable for reloading after configuration change *)
function RestartCurrentProcess: bool;


(***) implementation (***)


const
  RESTART_EVENT_ARG_NAME = '--restart-event';
  PARENT_PID_ARG_NAME    = '--parent-pid';


var
  (* Global unique process GUID, generated on demand *)
  ProcessGuid: myAStr;

  StaticCritSection: Concur.TCritSection;


function GetCurrentProcessGuid: myAStr;
var
  ProcessGuidBuf: array [0..sizeof(GameExt.ProcessStartTime) - 1] of byte;

begin
  with StaticCritSection do begin
    Enter;

    if ProcessGuid = '' then begin
      Legacy.FillChar(ProcessGuidBuf, sizeof(ProcessGuidBuf), #0);

      if not WinUtils.RtlGenRandom(@ProcessGuidBuf, sizeof(ProcessGuidBuf)) then begin
        UtilsB2.CopyMem(sizeof(GameExt.ProcessStartTime), @GameExt.ProcessStartTime, @ProcessGuidBuf);
      end;

      ProcessGuid := StrLib.BinToHex(sizeof(ProcessGuidBuf), @ProcessGuidBuf);
    end;

    result := ProcessGuid;

    Leave;
  end;
end;

function RestartCurrentProcess: bool;
const
  MANUAL_RESET             = true;
  INITIAL_EVENT_STATE      = false;
  WAIT_END                 = true;
  RESTART_WAIT_TIME_MSEC   = 3000;
  RESTART_EVENT_ARG_PREFIX = RESTART_EVENT_ARG_NAME + '=';
  PARENT_PID_ARG_PREFIX    = PARENT_PID_ARG_NAME + '=';
  EXIT_CODE_OK             = 0;

var
{O} CmdArgs:   DataLib.TStrList;
    EventName: myAStr;
    hEvent:    Windows.THandle;
    Arg:       myAStr;
    MatchPos:  integer;
    i:         integer;


begin
  CmdArgs := DataLib.NewStrList(not UtilsB2.OWNS_ITEMS, DataLib.CASE_SENSITIVE);
  // * * * * * //
  with StaticCritSection do begin
    Enter;

    hEvent := 0;
    result := false;

    try
      EventName := 'EraRestart.Event.' + Legacy.IntToStr(WinUtils.GetUnixTime) + '.' + Legacy.IntToStr(FastRand.Rng.Random);
      hEvent    := Windows.CreateEventA(nil, MANUAL_RESET, INITIAL_EVENT_STATE, myPChar(EventName));

      if not WinUtils.IsValidHandle(hEvent) then begin
        exit;
      end;

      // Exclude existing restart related arguments
      for i := 1 to ParamCount do begin
        Arg := myAStr(ParamStr(i));

        if
          not (StrLib.FindSubstr(RESTART_EVENT_ARG_PREFIX, Arg, MatchPos) and (MatchPos = 1)) and
          not (StrLib.FindSubstr(PARENT_PID_ARG_PREFIX, Arg, MatchPos)    and (MatchPos = 1))
        then begin
          CmdArgs.Add('"' + Arg + '"');
        end;
      end;

      // Add restart related arguments
      CmdArgs.Add('"' + RESTART_EVENT_ARG_PREFIX + EventName + '"');
      CmdArgs.Add('"' + PARENT_PID_ARG_PREFIX + Legacy.IntToStr(Windows.GetCurrentProcessId) + '"');

      if not CmdApp.RunProcess(myAStr(WinUtils.GetExePath), CmdArgs.ToText(' '), '', not WAIT_END) then begin
        exit;
      end;

      if Windows.WaitForSingleObject(hEvent, RESTART_WAIT_TIME_MSEC) <> Windows.WAIT_OBJECT_0 then begin
        exit;
      end;

      try
        Windows.ExitProcess(EXIT_CODE_OK);
      except
        Windows.TerminateProcess(Windows.GetCurrentProcess, EXIT_CODE_OK);
      end;

      halt;
    finally
      if WinUtils.IsValidHandle(hEvent) then begin
        Windows.CloseHandle(hEvent);
      end;

      Legacy.FreeAndNil(CmdArgs);

      Leave;
    end;
  end; // .with
end; // .function RestartCurrentProcess

procedure OnBeforeInit (Event: GameExt.PEvent); stdcall;
const
  MANUAL_RESET                       = true;
  INITIAL_EVENT_STATE                = false;
  PARENT_PROCESS_TERMINATION_TIMEOUT = 5000;

var
  EventName:      myAStr;
  ParentPidArg:   myAStr;
  ParentPid:      integer;
  hEvent:         Windows.THandle;
  hParentProcess: Windows.THandle;

begin
  // Seems like current process was created in "restart process" function
  if CmdApp.ArgExists(RESTART_EVENT_ARG_NAME) and CmdApp.ArgExists(PARENT_PID_ARG_NAME) then begin
    EventName    := CmdApp.GetArg(RESTART_EVENT_ARG_NAME);
    ParentPidArg := CmdApp.GetArg(PARENT_PID_ARG_NAME);

    if not Legacy.TryStrToInt(ParentPidArg, ParentPid) then begin
      halt;
    end;

    hParentProcess := Windows.OpenProcess(Windows.SYNCHRONIZE, false, ParentPid);

    if not WinUtils.IsValidHandle(hParentProcess) then begin
      halt;
    end;

    hEvent := Windows.OpenEventA(Windows.EVENT_ALL_ACCESS, false, myPChar(EventName));

    if not WinUtils.IsValidHandle(hEvent) then begin
      halt;
    end;

    if not Windows.SetEvent(hEvent) then begin
      halt;
    end;

    if Windows.WaitForSingleObject(hParentProcess, PARENT_PROCESS_TERMINATION_TIMEOUT) <> Windows.WAIT_OBJECT_0 then begin
      halt;
    end;

    Windows.CloseHandle(hParentProcess);
    Windows.CloseHandle(hEvent);
  end; // .if
end; // .procedure OnBeforeInit

initialization
  StaticCritSection.Init;
  EventMan.GetInstance.On('$OnBeforeInit', OnBeforeInit);
finalization
  StaticCritSection.Delete;
end.
