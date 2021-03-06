(***********************************************************************)
(*                                                                     *)
(*                              CamlIDL                                *)
(*                                                                     *)
(*            Xavier Leroy, projet Cristal, INRIA Rocquencourt         *)
(*                                                                     *)
(*  Copyright 1999 Institut National de Recherche en Informatique et   *)
(*  en Automatique.  All rights reserved.  This file is distributed    *)
(*  under the terms of the Q Public License version 1.0                *)
(*                                                                     *)
(***********************************************************************)

(* $Id: file.ml,v 1.18 2002-04-19 13:24:29 xleroy Exp $ *)

(* Handling of interfaces *)

open Printf
open Utils
open Idltypes
open Intf

type diversion_type = Div_c | Div_h | Div_ml | Div_mli | Div_ml_mli

type component =
    Comp_typedecl of Typedef.type_decl
  | Comp_structdecl of struct_decl
  | Comp_uniondecl of union_decl
  | Comp_enumdecl of enum_decl
  | Comp_fundecl of Funct.function_decl
  | Comp_constdecl of Constdecl.constant_decl
  | Comp_diversion of diversion_type * string
  | Comp_interface of Intf.interface
  | Comp_import of string * components

and components = component list

(* Evaluate all constant definitions *)

let rec eval_constants intf =
  List.iter
    (function Comp_constdecl cd -> Constdecl.record cd
            | Comp_import(file, comps) -> eval_constants comps
            | _ -> ())
    intf

(* Generate the ML interface *)

(* Generate the type definitions common to the .ml and the .mli *)

let gen_type_def oc intf =
  let first = ref true in
  let start_decl () =
    if !first then fprintf oc "type " else fprintf oc "and ";
    first := false in
  let emit_typedef = function
      Comp_typedecl td ->
        start_decl(); Typedef.ml_declaration oc td
    | Comp_structdecl s ->
        if s.sd_fields <> [] then begin
          start_decl(); Structdecl.ml_declaration oc s
        end
    | Comp_uniondecl u ->
        if u.ud_cases <> [] then begin
          start_decl(); Uniondecl.ml_declaration oc u
        end
    | Comp_enumdecl e ->
        start_decl(); Enumdecl.ml_declaration oc e
    | Comp_interface i ->
        if i.intf_methods <> [] then begin
          start_decl(); Intf.ml_declaration oc i
        end
    | _ -> () in
  List.iter emit_typedef intf;
  fprintf oc "\n"

(* Generate the .mli file *)

let gen_mli_file oc intf =
  fprintf oc "(* File generated from %s.idl *)\n\n" !module_name;
  gen_type_def oc intf;
  (* Generate the function declarations *)
  let emit_fundecl = function
      Comp_fundecl fd -> Funct.ml_declaration oc fd
    | Comp_constdecl cd -> Constdecl.ml_declaration oc cd
    | Comp_diversion((Div_mli | Div_ml_mli), txt) ->
        output_string oc txt; output_char oc '\n'
    | Comp_interface i ->
        if i.intf_methods <> [] then Intf.ml_class_declaration oc i
    | _ -> () in
  List.iter emit_fundecl intf

(* Generate the .ml file *)

let gen_ml_file oc intf =
  fprintf oc "(* File generated from %s.idl *)\n\n" !module_name;
  gen_type_def oc intf;
  (* Generate the function declarations and class definitions *)
  let emit_fundecl = function
      Comp_fundecl fd -> Funct.ml_declaration oc fd
    | Comp_constdecl cd -> Constdecl.ml_definition oc cd
    | Comp_diversion((Div_ml | Div_ml_mli), txt) ->
        output_string oc txt; output_char oc '\n'
    | Comp_interface i ->
        if i.intf_methods <> [] then Intf.ml_class_definition oc i
    | _ -> () in
  List.iter emit_fundecl intf

(* Process an import: declare the translation functions *)

let rec declare_comp oc = function
    Comp_typedecl td ->
      Typedef.declare_transl oc td
  | Comp_structdecl sd ->
      if sd.sd_name <> "" then Structdecl.declare_transl oc sd
  | Comp_uniondecl ud ->
      if ud.ud_name <> "" then Uniondecl.declare_transl oc ud
  | Comp_enumdecl en ->
      if en.en_name <> "" then Enumdecl.declare_transl oc en
  | Comp_fundecl fd ->
      ()
  | Comp_constdecl cd ->
      ()
  | Comp_diversion(kind, txt) ->
      ()
  | Comp_interface i ->
      Intf.declare_transl oc i
  | Comp_import(filename, comps) ->
      List.iter (declare_comp oc) comps

(* Process a component *)

let rec process_comp oc = function
    Comp_typedecl td ->
      Typedef.emit_transl oc td
  | Comp_structdecl sd ->
      if sd.sd_name <> "" then
        if sd.sd_fields = []
        then Structdecl.declare_transl oc sd
        else  Structdecl.emit_transl oc sd
  | Comp_uniondecl ud ->
      if ud.ud_name <> "" then
        if ud.ud_cases = []
        then Uniondecl.declare_transl oc ud
        else Uniondecl.emit_transl oc ud
  | Comp_enumdecl en ->
      if en.en_name <> ""
      then Enumdecl.emit_transl oc en
      else Enumdecl.emit_transl_table oc en
  | Comp_fundecl fd ->
      Funct.emit_wrapper oc fd
  | Comp_constdecl cd ->
      ()
  | Comp_diversion(kind, txt) ->
      if kind = Div_c || (kind = Div_h && not !Clflags.include_header)
      then begin
        output_string oc txt; output_char oc '\n'
      end
  | Comp_interface i ->
      if i.intf_methods <> [] then Intf.emit_transl oc i
  | Comp_import(filename, comps) ->
      List.iter (declare_comp oc) comps

(* Generate the C stub file *)

let gen_c_stub oc intf =
  (* Output the header *)
  fprintf oc "/* File generated from %s.idl */\n\n" !module_name;
  output_string oc "\
    #include <stddef.h>\n\
    #include <string.h>\n\
    #include <caml/mlvalues.h>\n\
    #include <caml/memory.h>\n\
    #include <caml/alloc.h>\n\
    #include <caml/fail.h>\n\
    #include <caml/callback.h>\n\
    #ifdef Custom_tag\n\
    #include <caml/custom.h>\n\
    #include <caml/bigarray.h>\n\
    #endif\n\
    #include <caml/camlidlruntime.h>\n\n";
  if !Clflags.include_header then
    (* Include the .h for the module
       (as generated by us or by MIDL, or written by the user) *)
    fprintf oc "\n#include \"%s.h\"\n\n" !module_name;
  (* Process the interface *)
  List.iter (process_comp oc) intf

(* Generate the C header file *)

let process_definition oc = function
    Comp_typedecl td ->
      Typedef.c_declaration oc td
  | Comp_structdecl sd ->
      if sd.sd_name <> "" then Structdecl.c_declaration oc sd
  | Comp_uniondecl ud ->
      if ud.ud_name <> "" then Uniondecl.c_declaration oc ud
  | Comp_enumdecl en ->
      if en.en_name <> "" then Enumdecl.c_declaration oc en
  | Comp_fundecl fd ->
      Funct.c_declaration oc fd
  | Comp_constdecl cd ->
      Constdecl.c_declaration oc cd
  | Comp_diversion(kind, txt) ->
      if kind = Div_h then begin
        output_string oc txt; output_char oc '\n'
      end
  | Comp_interface i ->
      Intf.c_declaration oc i
  | Comp_import(basename, comps) ->
      fprintf oc "#include \"%s.h\"\n" basename

let gen_c_header oc intf =
  (* Output the header *)
  fprintf oc "/* File generated from %s.idl */\n\n" !module_name;
  (* TODO: emit relevant #include *)
  let symbname = "_CAMLIDL_" ^ String.uppercase_ascii !module_name ^ "_H" in
  fprintf oc "\
    #ifndef %s\n\
    #define %s\n\n" symbname symbname;
  fprintf oc "\
    #ifdef __cplusplus\n\
    #define _CAMLIDL_EXTERN_C extern \"C\"\n\
    #else\n\
    #define _CAMLIDL_EXTERN_C extern\n\
    #endif\n\n\
    #ifdef _WIN32\n\
    #pragma pack(push,8) /* necessary for COM interfaces */\n\
    #endif\n\n";
  (* Emit the definitions *)
  List.iter (process_definition oc) intf;
  fprintf oc "\
    #ifdef _WIN32\n\
    #pragma pack(pop)\n\
    #endif\n\n";
  fprintf oc "\n\
    #endif /* !%s */\n" symbname
