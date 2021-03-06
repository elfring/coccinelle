(* Note: this module passes paths to other commands, but does not take
 * quoting into account. Thus, if these paths contain spaces, it's likely
 * that things go wrong.
 *)

module Ast = Ast_cocci

exception CompileFailure of string
exception LinkFailure of string

let ext = if Config.dynlink_is_native then ".cmxs" else ".cma"

let sysdir () =
  let sysdircmd = !Flag.ocamlfind ^ " printconf stdlib" in
  match Common.cmd_to_list sysdircmd with
    [sysdir] -> sysdir
  | _ -> raise (CompileFailure (sysdircmd ^" has failed"))

let check_cmd cmd =
  let (_,stat) = Common.cmd_to_list_and_status cmd in
  match stat with
      Unix.WEXITED 0 -> true
    | _ -> false

(* this function does not work when the executable has an extension like .exe *)
let to_opt cmd =
  let n = String.length cmd in
  if n > 4 && String.compare (String.sub cmd (n-4) 4) ".opt" == 0
  then cmd
  else cmd ^ ".opt"

let check_runtime () =
  let has_opt  = check_cmd (to_opt (!Flag.ocamlc) ^ " -version 2>&1 > /dev/null") in
  let has_c    = check_cmd (!Flag.ocamlc ^ " -version 2>&1 > /dev/null") in
    if has_opt then
      begin
	Flag.ocamlc   := to_opt (!Flag.ocamlc);
	Flag.ocamlopt := to_opt (!Flag.ocamlopt);
	Flag.ocamldep := to_opt (!Flag.ocamldep);
	Common.pr2 "Using native version of ocamlc/ocamlopt/ocamldep"
      end
    else
      if has_c then
	Common.pr2 "Using bytecode version of ocamlc/ocamlopt/ocamldep"
      else
	if Config.dynlink_is_native then
	  failwith
	    "No OCaml compiler found! Install either ocamlopt or ocamlopt.opt"
	else
	  failwith
	    "No OCaml compiler found! Install either ocamlc or ocamlc.opt"

let init_ocamlcocci _ =
  "open Coccilib\n"

let print_match ctr nm kind =
  let endlet = "| _ -> failwith \"bad value\" in\n" in
  let index = !ctr in
  ctr := !ctr + 1;
  Printf.sprintf
    "let %s = match List.nth __args__ %d with Coccilib.%s x -> x %s"
    nm index kind endlet

let string_rep_binding ctr = function
    (Some nm,Ast.MetaPosDecl _) -> print_match ctr nm "Pos"
  | (Some nm,Ast.MetaListlenDecl _) -> print_match ctr nm "Int"
  | (Some nm,_) (* strings for everything else *) ->
      print_match ctr nm "Str"
  | (None,_) -> ""

let ast_rep_binding ctr = function
    (Some nm,Ast.MetaPosDecl _) ->
      failwith
	(Printf.sprintf "%s: No AST representation for position variables" nm)
  | (Some nm,Ast.MetaAnalysisDecl _) ->
      failwith "Todo"

  | (Some nm,Ast.MetaMetaDecl _) ->
      failwith
	(Printf.sprintf
	   "%s: No AST representation for metavariables declared as \"%s\""
	   "metavariable" nm)
  | (Some nm,Ast.MetaIdDecl _) -> print_match ctr nm "Str"
  | (Some nm,Ast.MetaFreshIdDecl _) -> print_match ctr nm "Str"
  | (Some nm,Ast.MetaTypeDecl _) -> print_match ctr nm "Type"
  | (Some nm,Ast.MetaInitDecl _) -> print_match ctr nm "Init"
  | (Some nm,Ast.MetaInitListDecl _) -> print_match ctr nm "InitList"
  | (Some nm,Ast.MetaListlenDecl _) ->
      failwith
	(Printf.sprintf "%s: No AST representation for listlen variables" nm)
  | (Some nm,Ast.MetaParamDecl _) -> print_match ctr nm "Param"
  | (Some nm,Ast.MetaParamListDecl _) -> print_match ctr nm "ParamList"
  | (Some nm,Ast.MetaConstDecl _) -> print_match ctr nm "Expr"
  | (Some nm,Ast.MetaErrDecl _) -> failwith ("not supported: "^nm)
  | (Some nm,Ast.MetaExpDecl _) -> print_match ctr nm "Expr"
  | (Some nm,Ast.MetaIdExpDecl _) -> print_match ctr nm "Expr"
  | (Some nm,Ast.MetaLocalIdExpDecl _) -> print_match ctr nm "Expr"
  | (Some nm,Ast.MetaExpListDecl _) -> print_match ctr nm "ExprList"
  | (Some nm,Ast.MetaDeclDecl _) -> print_match ctr nm "Decl"
  | (Some nm,Ast.MetaFieldDecl _) -> print_match ctr nm "Field"
  | (Some nm,Ast.MetaFieldListDecl _) -> print_match ctr nm "FieldList"
  | (Some nm,Ast.MetaStmDecl _) -> print_match ctr nm "Stmt"
  | (Some nm,Ast.MetaStmListDecl _) -> failwith ("not supported: "^nm)
  | (Some nm,Ast.MetaFmtDecl _) -> print_match ctr nm "Fmt"
  | (Some nm,Ast.MetaFragListDecl _) -> print_match ctr nm "FragList"
  | (Some nm,Ast.MetaFuncDecl _) -> print_match ctr nm "Str"
  | (Some nm,Ast.MetaLocalFuncDecl _) -> print_match ctr nm "Str"
  | (Some nm,Ast.MetaDeclarerDecl _) -> print_match ctr nm "Str"
  | (Some nm,Ast.MetaIteratorDecl _) -> print_match ctr nm "Str"
  | (None,_) -> ""

let manage_script_vars script_vars =
  let rec loop n = function
      [] -> ""
    | (_,x)::xs ->
	(Printf.sprintf "let %s = List.nth __script_args__ %d in\n" x n) ^
	(loop (n+1) xs) in
  loop 0 script_vars

(* ---------------------------------------------------------------------- *)
(* Iteration management *)

let print_iteration_code o =
  let translator l =
    String.concat "\n              | "
      (List.map
	 (function x -> Printf.sprintf "%s -> \"%s\""
	     (String.capitalize x) x)
	 l) in
  let add_virt_rules_method =
    match !Iteration.parsed_virtual_rules with
      [] -> ""
    | l ->
	Printf.sprintf "
    method add_virtual_rule r =
      let r = match r with %s in
      virtual_rules <- Common.union_set [r] virtual_rules\n"
	  (translator l) in
  let add_virt_ids_method =
    match !Iteration.parsed_virtual_identifiers with
      [] -> ""
    | l ->
	Printf.sprintf "
    method add_virtual_identifier i v =
      let i = match i with %s in
      try
	let v1 = List.assoc i virtual_identifiers in
	if not (v = v1)
	then failwith (\"multiple values specified for \"^i)
      with Not_found ->
	virtual_identifiers <- (i,v) :: virtual_identifiers"
					 (translator l) in
    Printf.fprintf o "
class iteration () =
  object
    val mutable files = None
    val mutable files_changed = false
    val mutable virtual_rules = ([] : string list)
    val mutable virtual_identifiers = ([] : (string * string) list)
    val mutable extend_virtual_ids = false
    method set_files f = files <- Some f
    method extend_virtual_identifiers (x : unit) = extend_virtual_ids <- true
    %s%s
    method register () =
      Iteration.add_pending_instance
	(files,virtual_rules,virtual_identifiers,extend_virtual_ids)
  end\n\n" add_virt_rules_method add_virt_ids_method

(* ---------------------------------------------------------------------- *)

let prepare_mvs o str = function
    [] -> true
  | metavars ->
      let fn _ =
	List.map
	  (function
	      ((Some nm,None),("virtual",vname),_) ->
		let vl =
		  try List.assoc vname !Flag.defined_virtual_env
		  with Not_found ->
		    begin
		      Common.pr2
			(str^": required variable "^nm^" not found, "^
			 str^" ignored");
		      raise Not_found
		    end in
		(nm,vl)
	    | _ -> failwith "invalid metavar in initialize or finalize")
	  metavars in
      try
	List.iter
	  (function (nm,vl) -> Printf.fprintf o "let %s = \"%s\"\n" nm vl)
	  (fn());
	Printf.fprintf o "\n";
	true
      with Not_found -> false

let prepare_rule (name, metavars, script_vars, code) =
  let fname = String.concat "_" (Str.split (Str.regexp " ") name) in
  (* function header *)
  let function_header body =
    Printf.sprintf "let %s __args__ __script_args__ =\n %s" fname body in
  (* parameter list *)
  let build_parameter_list body =
    let ctr = ref 0 in
    let lets =
      String.concat ""
	(List.rev
	   (List.fold_left
	      (function prev ->
		function ((str_nm,ast_nm),_,mv) ->
	          (* order important; ctr is incremented *)
		  let string_rep = string_rep_binding ctr (str_nm,mv) in
		  let ast_rep = ast_rep_binding ctr (ast_nm,mv) in
		  ast_rep :: string_rep :: prev)
	      [] metavars)) in
    lets ^ (manage_script_vars script_vars) ^ body in
  (* add to hash table *)
  let hash_add body =
    Printf.sprintf
      "%s\nlet _ = Hashtbl.add Coccilib.fcts \"%s\" %s\n" body name fname in
  hash_add (function_header (build_parameter_list code))

let prepare coccifile code =
  let (init_mvs,sub_final_mvs,all_final_mvs) =
    let (init,final) =
      List.fold_left
	(function ((init,final) as prev) ->
	  function
	      Ast_cocci.InitialScriptRule (name,"ocaml",deps,mvs,code) ->
		(Common.union_set mvs init,final)
	    | Ast_cocci.FinalScriptRule (name,"ocaml",deps,mvs,code) ->
		(init,Common.union_set mvs final)
	    | _ -> prev)
	([],[]) code in
    (* minus_set because actually init declarations are global... *)
    (init, Common.minus_set final init, final) in
  let init_rules =
    List.fold_left
      (function prev ->
	function
	    Ast_cocci.InitialScriptRule (name,"ocaml",deps,mvs,code) ->
	      code :: prev
	  | _ -> prev)
      [] code in
  let init_rules = List.rev init_rules in
  let final_rules =
    List.fold_left
      (function prev ->
	function
	    Ast_cocci.FinalScriptRule (name,"ocaml",deps,mvs,code) ->
	      (name,[],[],code) :: prev
	  | _ -> prev)
      [] code in
  let final_rules = List.rev final_rules in
  let other_rules =
    List.fold_left
      (function prev ->
	function
	    Ast_cocci.ScriptRule (name,"ocaml",deps,mv,script_vars,code) ->
	      (name,mv,script_vars,code) :: prev
	  | _ -> prev)
      [] code in
  let other_rules = List.rev other_rules in
  if init_rules = [] && other_rules = []
  then None
  else
    begin
      let basefile = Filename.basename (Filename.chop_extension coccifile) in
      let basefile =
	String.concat "_" (Str.split (Str.regexp "-") basefile) in
      let (file,o) = Filename.open_temp_file  basefile ".ml" in
      (* Global initialization *)
      Printf.fprintf o "%s\n" (init_ocamlcocci());
      (* virtual rules and identifiers *)
      (if !Iteration.parsed_virtual_rules != []
      then
	Printf.fprintf o "type __virtual_rules__ = %s\n\n"
	  (String.concat " | "
	     (List.map String.capitalize !Iteration.parsed_virtual_rules)));
      (if !Iteration.parsed_virtual_identifiers != []
      then
	Printf.fprintf o "type __virtual_identifiers__ = %s\n\n"
	  (String.concat " | "
	     (List.map
		(function x -> Printf.sprintf "%s" x)
		(List.map String.capitalize
		   !Iteration.parsed_virtual_identifiers))));
      print_iteration_code o;
      (* Virtual metavariables for initialize and finalize rules *)
      let generate_init = prepare_mvs o "initialize" init_mvs in
      let generate_final =
	prepare_mvs o "finalize"
	  (if generate_init then sub_final_mvs else all_final_mvs) in
      (* Semantic patch specific initialization *)
      (if generate_init
      then Printf.fprintf o "%s" (String.concat "\n\n" init_rules));
      (* Semantic patch rules *)
      let rule_code = List.map prepare_rule other_rules in
      Printf.fprintf o "%s" (String.concat "\n\n" rule_code);
      (* finalizer *)
      (if generate_final
      then
	let rule_code = List.map prepare_rule final_rules in
	Printf.fprintf o "%s" (String.concat "\n\n" rule_code));
      close_out o;
      check_runtime ();
      Some file
    end

(* give a path to the coccilib cmi file *)
let find_cmifile name =
  let path1 = Printf.sprintf "%s/ocaml/%s.cmi" Config.path name in
  if Sys.file_exists path1 then path1 else
  let path2 = Printf.sprintf "%s/ocaml/coccilib/%s.cmi" Config.path name in
  if Sys.file_exists path2 then path2 else
  raise (CompileFailure ("No coccilib.cmi in " ^ path1 ^ " or " ^ path2))

(* extract upper case identifiers from the cmi file. This will be an
 * approximation of the modules referenced by the coccilib, which are
 * thus present in the application and do not need to be loaded by
 * the dynamic linker.
 *)

module ModuleSet = Set.Make(String)

let approx_coccilib_deps cmi =
  let chan = open_in_bin cmi in
  let tbl = Hashtbl.create 1024 in
  let buf = Buffer.create 140 in
  begin
  try
    while true do
      let c = input_char chan in
      let has_ident = Buffer.length buf > 0 in
      if has_ident
      then begin
        if (c >= 'a' && c <= 'z') ||
           (c >= 'A' && c <= 'Z') ||
           (c >= '0' && c <= '9') ||
           c == '_' || c == '\''
        then Buffer.add_char buf c
        else begin
          if Buffer.length buf >= 3
          then begin
            let key = Buffer.contents buf in
            if Hashtbl.mem tbl key
            then ()
            else Hashtbl.add tbl (Buffer.contents buf) ()
          end;
          Buffer.clear buf
        end
      end
      else begin
        if c >= 'A' && c <= 'Z'
        then (* perhaps the begin of a capitalized identifier *)
          Buffer.add_char buf c
        else ()
      end
    done
  with End_of_file -> ()
  end;
  close_in chan;
  tbl

let filter_dep existing_deps (accld, accinc) dep =
  if Hashtbl.mem existing_deps dep
  then (accld, accinc)  (* skip an existing dep *)
  else match dep with
      (* Built-in and OCaml defaults are filtered out *)
      "Arg" | "Arith_status" | "Array" | "ArrayLabels" | "Big_int" | "Bigarray"
    | "Buffer" | "Callback" | "CamlinternalLazy" | "CamlinternalMod"
    | "CamlinternalOO"
    | "Char" | "Complex" | "Condition" | "Digest" | "Dynlink" | "Event"
    | "Filename"
    | "Format" | "Gc" | "Genlex" | "GraphicsX11" | "Hashtbl" | "Int32"
    | "Int64"
    | "Lazy" | "Lexing" | "List" | "ListLabels" | "Map" | "Marshal"
    | "MoreLabels" | "Mutex"
    | "Nativeint" | "Num" | "Obj" | "Oo" | "Parsing" | "Pervasives"
    | "Printexc" | "Printf"
    | "Queue" | "Random" | "Scanf" | "Set" | "Sort" | "Stack" | "StdLabels"
    | "Str" | "Stream"
    | "String" | "StringLabels" | "Sys" | "ThreadUnix" | "Unix" | "UnixLabels"
    | "Weak"     -> (accld, accinc)
    | "Dbm"      -> ("dbm"::accld, accinc)
    | "Graphics" -> ("graphics"::accld, accinc)
    | "Thread"   -> ("thread"::accld, accinc)
    | "Tk"       -> ("tk"::accld, accinc)

    | _ ->
	let l = Char.lowercase (String.get dep 0)in
	  String.set dep 0 l;
	  (accld, dep::accinc)

let get_dir p =
  let inclcmd = !Flag.ocamlfind ^" query "^p in
  let dir = List.hd (Common.cmd_to_list inclcmd) in
    (dir, p)

let parse_dep cmifile mlfile depout =
  let empty_deps = ([], "") in
  let existing_deps = approx_coccilib_deps cmifile in
  let re_colon = Str.regexp_string ":" in
  match Str.split re_colon depout with
    _::[dep] ->
      let deplist = Str.split (Str.regexp_string " ") dep in
      let (libs, orderdep) = List.fold_left (filter_dep existing_deps) ([],[]) deplist in
      if libs <> [] || orderdep <> [] then
	begin
	  if check_cmd (!Flag.ocamlfind ^ " printconf 2>&1 > /dev/null")
	  then
	    let packages = List.rev orderdep in
	    let inclflags = List.map get_dir packages in
	    let intlib = List.map get_dir libs in
	    let alllibs = List.rev_append intlib inclflags in
	    let plist =
	      List.fold_left (fun acc (_,p) -> acc ^" "^p) "" alllibs in
	    let flags =
	      String.concat " " (List.map (fun (d,_) -> "-I "^d) inclflags) in
	    if flags <> "" || libs <> []
	    then begin
	      Common.pr2
		("Extra OCaml packages used in the semantic patch:"^ plist);
		(alllibs, flags)
	    end
            else begin
  	      Common.pr2 ("Warning: ocamlfind did not find "^
		       (if (List.length libs + List.length orderdep) = 1
			then "this package:"
			else "one of these packages:")^ plist);
              empty_deps
            end
	  else begin
	    Common.pr2 ("Warning: ocamlfind not found but "^mlfile^" uses "^dep);
            empty_deps
          end
	end
      else
	empty_deps
  | _ ->
      raise
	(CompileFailure ("Wrong dependencies for "^mlfile^" (Got "^depout^")"))

let dep_flag cmifile mlfile =
  let depcmd  = !Flag.ocamldep ^" -modules "^mlfile in
  match Common.cmd_to_list depcmd with
    [dep] -> parse_dep cmifile mlfile dep
  | err ->
      List.iter (function x -> Common.pr2 (x^"\n")) err;
      raise (CompileFailure ("Failed ocamldep for "^mlfile))

let compile_bytecode_cmd flags mlfile =
  let obj = (Filename.chop_extension mlfile) ^ ".cmo" in
  (obj, Printf.sprintf "%s -c %s %s %s" !Flag.ocamlc obj flags mlfile)

let compile_native_cmd flags mlfile =
  let obj = (Filename.chop_extension mlfile) ^ ".cmxs" in
  (obj,
   Printf.sprintf "%s -shared -o %s %s %s" !Flag.ocamlopt obj flags mlfile)

let compile mlfile cmd =
  Common.pr2 cmd;
  match Sys.command cmd with
      0 -> ()
    | _ -> raise (CompileFailure mlfile)

let load_obj obj =
  Dynlink.allow_unsafe_modules true;
  try Dynlink.loadfile obj
  with Dynlink.Error e ->
    Common.pr2 (Dynlink.error_message e);
    raise (LinkFailure obj)

let load_lib (dir, name) =
  let obj = dir ^ "/" ^name ^ ext in
    Common.pr2 ("Loading "^ obj ^"...");
    load_obj obj

let load_libs libs =
  List.iter load_lib libs

let load_file mlfile =
  let cmifile = find_cmifile "coccilib" in
  let (ldlibs, inc) = dep_flag cmifile mlfile in
  (* add ocaml and ocaml/coccilib as search directories for the ocaml scripting *)
  let flags =
    Printf.sprintf
      "-g -I %s %s -I %s"
      (sysdir ()) inc (Filename.dirname cmifile) in
  let (obj, cmd) =
    if Config.dynlink_is_native
    then compile_native_cmd flags mlfile
    else compile_bytecode_cmd flags mlfile in
  compile mlfile cmd;
  Common.pr2 "Compilation OK!";
  load_libs ldlibs;
  Common.pr2 "Loading ML code of the SP...";
  load_obj obj

let clean_file mlfile =
  let basefile = Filename.chop_extension mlfile in
  let files =
    if Config.dynlink_is_native then
      [basefile ^ ".cmxs";
       basefile ^ ".cmx";
       basefile ^ ".o";
       basefile ^ ".annot"]
    else
      [basefile ^ ".cmo";
       basefile ^ ".annot"]
  in
    if not !Flag_parsing_cocci.keep_ml_script then Sys.remove mlfile;
    Sys.remove (basefile^".cmi");
    List.iter (fun f -> try Sys.remove f with _ -> ()) files

(*
  This function is used in testing.ml.
  Once the ML file is compiled and loaded,
  newly available functions are reported here.
*)
let test () =
  Hashtbl.iter
    (fun key fct ->
       Common.pr2 ("Fct registered: \""^key^"\"")
    ) Coccilib.fcts
