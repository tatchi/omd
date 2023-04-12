let enabled =
  Lazy.from_fun (fun () ->
      Sys.getenv_opt "enable_log"
      |> Option.map bool_of_string_opt
      |> Option.join
      |> Option.value ~default:true)

let print fmt =
  if Lazy.force enabled then Printf.printf (fmt ^^ "\n%!")
  else Printf.ifprintf stdout fmt
