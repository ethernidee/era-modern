unit EventLib;
(*
  List of all Era generated event structures.
*)


(***)  interface  (***)

uses
  UtilsB2, Legacy;


type
  POnBeforeFastQuitToGameMenuEvent = ^TOnBeforeFastQuitToGameMenuEvent;
  TOnBeforeFastQuitToGameMenuEvent = packed record
    TargetScreen: integer;
  end;

  POnBeforeLoadGameEvent = ^TOnBeforeLoadGameEvent;
  TOnBeforeLoadGameEvent = packed record
    FileName: myPChar;
  end;


(***)  implementation  (***)

end.