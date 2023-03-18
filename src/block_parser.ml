open Ast.Util
module Raw = Ast_block.Raw

module Pre = struct
  type container =
    | Rblockquote of t
    | Rlist of
        list_type
        * list_spacing
        * bool
        * int
        * attributes Raw.block list list
        * t
    | Rparagraph of string list
    | Rfenced_code of
        int
        * int
        * Parser.code_block_kind
        * (string * string)
        * string list
        * attributes
    | Rindented_code of string list
    | Rhtml of Parser.html_kind * string list
    | Rdef_list of string * string list
    | Rtable_header of StrSlice.t list * string
    | Rtable of (string * cell_alignment) list * string list list
    | Rempty

  and t =
    { blocks : attributes Raw.block list
    ; next : container
    }

  let concat l = String.concat "\n" (List.rev l) ^ "\n"

  let trim_left s =
    let rec loop i =
      if i >= String.length s then i
      else match s.[i] with ' ' | '\t' -> loop (succ i) | _ -> i
    in
    let i = loop 0 in
    if i > 0 then String.sub s i (String.length s - i) else s

  let link_reference_definitions s =
    let defs, off = Parser.link_reference_definitions (Parser.P.of_string s) in
    let s = String.sub s off (String.length s - off) |> String.trim in
    (defs, s)

  let rec close link_defs { blocks; next } =
    let finish = finish link_defs in
    match next with
    | Rblockquote state -> Raw.Blockquote ([], finish state) :: blocks
    | Rlist (ty, sp, _, _, closed_items, state) ->
        List ([], ty, sp, List.rev (finish state :: closed_items)) :: blocks
    | Rparagraph l ->
        let s = concat (List.map trim_left l) in
        let defs, off =
          Parser.link_reference_definitions (Parser.P.of_string s)
        in
        let s = String.sub s off (String.length s - off) |> String.trim in
        link_defs := defs @ !link_defs;
        if s = "" then blocks else Paragraph ([], s) :: blocks
    | Rfenced_code (_, _, _kind, (label, _other), [], attr) ->
        Code_block (attr, label, "") :: blocks
    | Rfenced_code (_, _, _kind, (label, _other), l, attr) ->
        Code_block (attr, label, concat l) :: blocks
    | Rdef_list (term, defs) ->
        let l, blocks =
          match blocks with
          | Definition_list (_, l) :: b -> (l, b)
          | b -> ([], b)
        in
        Definition_list ([], l @ [ { term; defs = List.rev defs } ]) :: blocks
    | Rindented_code l ->
        (* TODO: trim from the right *)
        let rec loop = function "" :: l -> loop l | _ as l -> l in
        Code_block ([], "", concat (loop l)) :: blocks
    | Rhtml (_, l) -> Html_block ([], concat l) :: blocks
    | Rtable_header (_header, line) ->
        (* FIXME: this will only ever get called on the very last
           line. Should it do the link definitions? *)
        close link_defs { blocks; next = Rparagraph [ line ] }
    | Rtable (header, rows) -> Table ([], header, List.rev rows) :: blocks
    | Rempty -> blocks

  and finish link_defs state = List.rev (close link_defs state)

  let empty = { blocks = []; next = Rempty }
  let classify_line s = Parser.parse s

  let classify_delimiter s =
    let left, s =
      match StrSlice.head s with
      | Some ':' -> (true, StrSlice.drop 1 s)
      | _ -> (false, s)
    in
    let right, s =
      match StrSlice.last s with
      | Some ':' -> (true, StrSlice.drop_last s)
      | _ -> (false, s)
    in
    if StrSlice.exists (fun c -> c <> '-') s then None
    else
      match (left, right) with
      | true, true -> Some Centre
      | true, false -> Some Left
      | false, true -> Some Right
      | false, false -> Some Default

  let match_table_headers headers delimiters =
    let rec loop processed = function
      | [], [] -> Some (List.rev processed)
      | header :: headers, line :: delimiters -> (
          match classify_delimiter line with
          | None -> None
          | Some alignment ->
              loop
                ((StrSlice.to_string header, alignment) :: processed)
                (headers, delimiters))
      | [], _ :: _ | _ :: _, [] -> None
    in
    loop [] (headers, delimiters)

  let rec match_row_length l1 l2 =
    match (l1, l2) with
    | [], _ -> []
    | l1, [] -> List.init (List.length l1) (fun _ -> "")
    | _ :: l1, x :: l2 -> StrSlice.to_string x :: match_row_length l1 l2

  let rec process link_defs { blocks; next } s =
    let process = process link_defs in
    let close = close link_defs in
    let finish = finish link_defs in
    match (next, classify_line s) with
    | Rempty, Parser.Lempty -> { blocks; next = Rempty }
    | Rempty, Lblockquote s -> { blocks; next = Rblockquote (process empty s) }
    | Rempty, Lthematic_break ->
        { blocks = Thematic_break [] :: blocks; next = Rempty }
    | Rempty, Lsetext_heading { level = 2; len } when len >= 3 ->
        { blocks = Thematic_break [] :: blocks; next = Rempty }
    | Rempty, Latx_heading (level, text, attr) ->
        { blocks =
            Heading (("heading_type", "latx") :: attr, level, text) :: blocks
        ; next = Rempty
        }
    | Rempty, Lfenced_code (ind, num, q, info, a) ->
        { blocks; next = Rfenced_code (ind, num, q, info, [], a) }
    | Rempty, Lhtml (_, kind) -> process { blocks; next = Rhtml (kind, []) } s
    | Rempty, Lindented_code s ->
        { blocks; next = Rindented_code [ StrSlice.to_string s ] }
    | Rempty, Llist_item (kind, indent, s) ->
        { blocks
        ; next = Rlist (kind, Tight, false, indent, [], process empty s)
        }
    | Rempty, (Lsetext_heading _ | Lparagraph | Ldef_list _ | Ltable_line []) ->
        { blocks; next = Rparagraph [ StrSlice.to_string s ] }
    | Rempty, Ltable_line items ->
        { blocks; next = Rtable_header (items, StrSlice.to_string s) }
    | Rparagraph [ h ], Ldef_list def ->
        { blocks; next = Rdef_list (h, [ def ]) }
    | Rdef_list (term, defs), Ldef_list def ->
        { blocks; next = Rdef_list (term, def :: defs) }
    | Rparagraph _, Llist_item ((Ordered (1, _) | Bullet _), _, s1)
      when not (Parser.is_empty (Parser.P.of_string (StrSlice.to_string s1))) ->
        process { blocks = close { blocks; next }; next = Rempty } s
    | ( Rparagraph _
      , ( Lempty | Lblockquote _ | Lthematic_break | Latx_heading _
        | Lfenced_code _
        | Lhtml (true, _) ) ) ->
        process { blocks = close { blocks; next }; next = Rempty } s
    | Rparagraph (_ :: _ as lines), Lsetext_heading { level; len } ->
        let text = concat (List.map trim_left lines) in
        let defs, text = link_reference_definitions text in
        link_defs := defs @ !link_defs;
        if text = "" then
          (* Happens when there's nothing between the [link reference definition] and the [setext heading].

               [foo]: /foo-url
               ===
               [foo]

             In that case, there's nothing to make as Heading. We can simply add `===` as Rparagraph
          *)
          { blocks; next = Rparagraph [ StrSlice.to_string s ] }
        else { blocks = Heading ([("heading_type", "lsetext"); ("len", string_of_int(len))], level, text) :: blocks; next = Rempty }
    | Rparagraph lines, _ ->
        { blocks; next = Rparagraph (StrSlice.to_string s :: lines) }
    | Rfenced_code (_, num, q, _, _, _), Lfenced_code (_, num', q1, ("", _), _)
      when num' >= num && q = q1 ->
        { blocks = close { blocks; next }; next = Rempty }
    | Rfenced_code (ind, num, q, info, lines, a), _ ->
        let s =
          let ind = min (Parser.indent s) ind in
          if ind > 0 then StrSlice.offset ind s else s
        in
        { blocks
        ; next =
            Rfenced_code (ind, num, q, info, StrSlice.to_string s :: lines, a)
        }
    | Rdef_list (term, d :: defs), Lparagraph ->
        { blocks
        ; next = Rdef_list (term, (d ^ "\n" ^ StrSlice.to_string s) :: defs)
        }
    | Rdef_list _, _ ->
        process { blocks = close { blocks; next }; next = Rempty } s
    | Rtable_header (headers, line), Ltable_line items -> (
        match match_table_headers headers items with
        | Some headers ->
            (* Makes sure that there are the same number of delimiters
               as headers. See
               https://github.github.com/gfm/#example-203 *)
            { blocks; next = Rtable (headers, []) }
        | None ->
            (* Reinterpret the previous line as the start of a
               paragraph. *)
            process { blocks; next = Rparagraph [ line ] } s)
    | Rtable_header (_, line), _ ->
        (* If we only have a potential header, and the current line
           doesn't look like a table delimiter, then reinterpret the
           previous line as the start of a paragraph. *)
        process { blocks; next = Rparagraph [ line ] } s
    | Rtable (header, rows), Ltable_line row ->
        (* Make sure the number of items in the row is consistent with
           the headers and the rest of the rows. See
           https://github.github.com/gfm/#example-204 *)
        let row = match_row_length header row in
        { blocks; next = Rtable (header, row :: rows) }
    | Rtable (header, rows), (Lparagraph | Lsetext_heading _) ->
        (* Treat a contiguous line after a table as a row, even if it
           doesn't contain any '|'
           characters. https://github.github.com/gfm/#example-202 *)
        let row = match_row_length header [ s ] in
        { blocks; next = Rtable (header, row :: rows) }
    | Rtable _, _ ->
        process { blocks = close { blocks; next }; next = Rempty } s
    | Rindented_code lines, Lindented_code s ->
        { blocks; next = Rindented_code (StrSlice.to_string s :: lines) }
    | Rindented_code lines, Lempty ->
        let n = min (Parser.indent s) 4 in
        let s = StrSlice.offset n s in
        { blocks; next = Rindented_code (StrSlice.to_string s :: lines) }
    | Rindented_code _, _ ->
        process { blocks = close { blocks; next }; next = Rempty } s
    | Rhtml ((Hcontains l as k), lines), _
      when List.exists (fun t -> StrSlice.contains t s) l ->
        { blocks =
            close { blocks; next = Rhtml (k, StrSlice.to_string s :: lines) }
        ; next = Rempty
        }
    | Rhtml (Hblank, _), Lempty ->
        { blocks = close { blocks; next }; next = Rempty }
    | Rhtml (k, lines), _ ->
        { blocks; next = Rhtml (k, StrSlice.to_string s :: lines) }
    | Rblockquote state, Lblockquote s ->
        { blocks; next = Rblockquote (process state s) }
    | Rlist (kind, style, _, ind, items, state), Lempty ->
        { blocks
        ; next = Rlist (kind, style, true, ind, items, process state s)
        }
    | Rlist (_, _, true, ind, _, { blocks = []; next = Rempty }), _
      when Parser.indent s >= ind ->
        process { blocks = close { blocks; next }; next = Rempty } s
    | Rlist (kind, style, prev_empty, ind, items, state), _
      when Parser.indent s >= ind ->
        let s = StrSlice.offset ind s in
        let state = process state s in
        let style =
          let rec new_block = function
            | Rblockquote { blocks = []; next }
            | Rlist (_, _, _, _, _, { blocks = []; next }) ->
                new_block next
            | Rparagraph [ _ ]
            | Rfenced_code (_, _, _, _, [], _)
            | Rindented_code [ _ ]
            | Rhtml (_, [ _ ]) ->
                true
            | _ -> false
          in
          if prev_empty && new_block state.next then Loose else style
        in
        { blocks; next = Rlist (kind, style, false, ind, items, state) }
    | ( Rlist (kind, style, prev_empty, _, items, state)
      , Llist_item (kind', ind, s) )
      when same_block_list_kind kind kind' ->
        let style = if prev_empty then Loose else style in
        { blocks
        ; next =
            Rlist
              (kind, style, false, ind, finish state :: items, process empty s)
        }
    | (Rlist _ | Rblockquote _), _ -> (
        let rec loop = function
          | Rlist (kind, style, prev_empty, ind, items, { blocks; next }) -> (
              match loop next with
              | Some next ->
                  Some
                    (Rlist
                       (kind, style, prev_empty, ind, items, { blocks; next }))
              | None -> None)
          | Rblockquote { blocks; next } -> (
              match loop next with
              | Some next -> Some (Rblockquote { blocks; next })
              | None -> None)
          | Rparagraph (_ :: _ as lines) -> (
              match classify_line s with
              | Parser.Lparagraph | Lindented_code _
              | Lsetext_heading { level = 1; _ }
              | Lhtml (false, _) ->
                  Some (Rparagraph (StrSlice.to_string s :: lines))
              | _ -> None)
          | _ -> None
        in
        match loop next with
        | Some next -> { blocks; next }
        | None -> process { blocks = close { blocks; next }; next = Rempty } s)

  let process link_defs state s = process link_defs state (StrSlice.of_string s)

  let of_channel ic =
    let link_defs = ref [] in
    let rec loop state =
      match input_line ic with
      | s -> loop (process link_defs state s)
      | exception End_of_file ->
          let blocks = finish link_defs state in
          (blocks, List.rev !link_defs)
    in
    loop empty

  let read_line s off =
    let buf = Buffer.create 128 in
    let rec loop cr_read off =
      if off >= String.length s then (Buffer.contents buf, None)
      else
        match s.[off] with
        | '\n' -> (Buffer.contents buf, Some (succ off))
        | '\r' ->
            if cr_read then Buffer.add_char buf '\r';
            loop true (succ off)
        | c ->
            if cr_read then Buffer.add_char buf '\r';
            Buffer.add_char buf c;
            loop false (succ off)
    in
    loop false off

  let of_string s =
    let link_defs = ref [] in
    let rec loop state = function
      | None ->
          let blocks = finish link_defs state in
          (blocks, List.rev !link_defs)
      | Some off ->
          let s, off = read_line s off in
          loop (process link_defs state s) off
    in
    loop empty (Some 0)
end
