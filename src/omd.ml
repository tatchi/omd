(* The document model *)

include Ast.Impl

(* Helper functions for construction document AST *)

module Ctor = Ast_constructors.Impl

(* Table of contents *)

let headers = Toc.headers
let toc = Toc.toc

(* Conversion *)

let parse_inline defs s = Parser.inline defs (Parser.P.of_string s)

let print_list fmt data =
  Format.pp_print_list fmt Format.str_formatter data;
  Format.flush_str_formatter ()

let parse_inlines (md, defs) : doc =
  let show_blocks =
    print_list (Ast_block.Raw.pp_block Ast.Impl.pp_attributes)
  in
  Log.print "[parse_inlines] blocks = %s" (show_blocks md);
  let defs =
    let f (def : attributes Parser.link_def) =
      { def with label = Parser.normalize def.label }
    in
    List.map f defs
  in
  let res =
    List.map
      (fun blk -> Ast_block.Mapper.map (fun s -> parse_inline defs s) blk)
      md
  in
  let show_Impl_blocks =
    print_list (Ast.Impl.pp_block Ast.Impl.pp_attributes)
  in
  Log.print
    "[parse_inlines] result of mapping blocks = %s"
    (show_Impl_blocks res);
  res

let escape_html_entities = Html.htmlentities

let of_channel ic : doc =
  let (blk, defs)
        : attributes Ast_block.Raw.block list
          * Ast.Impl.attributes Parser.link_def list =
    Block_parser.Pre.of_channel ic
  in
  parse_inlines (blk, defs)

let of_string s = parse_inlines (Block_parser.Pre.of_string s)

let to_html ?auto_identifiers doc =
  Html.to_string (Html.of_doc ?auto_identifiers doc)

let to_sexp ast = Format.asprintf "@[%a@]@." Sexp.print (Sexp.create ast)

module Print = Print
