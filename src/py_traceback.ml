open! Core

include Py.Traceback

module Unstable = struct
  type nonrec frame = frame =
    { filename : string
    ; function_name : string
    ; line_number : int
    }
  [@@deriving bin_io, sexp]

  type t = frame list [@@deriving bin_io, sexp]
end

let raise_py_err_with_backtrace ?(unwrap_more = fun _ -> None) ?backtrace exn =
  let rec loop acc_traceback = function
    | Exn.Reraised (reraised, exn) ->
      let frame =
        { Py.Traceback.filename = "exn.ml"
        ; function_name = Printf.sprintf "reraise<%s>" reraised
        ; line_number = 0
        }
      in
      loop ([ frame ] :: acc_traceback) exn
    | exn ->
      (match unwrap_more exn with
       | None -> List.concat (List.rev acc_traceback), exn
       | Some (backtraces, unwrapped_exn) ->
         if phys_equal unwrapped_exn exn
         then failwith "[unwrap_more exn] returns [exn] and causes an infinite loop"
         else
           loop (List.map ~f:of_ocaml_backtrace backtraces @ acc_traceback) unwrapped_exn)
  in
  let additional_traceback, exn = loop [] exn in
  (* The [additional_traceback] information is from function calls less recent than the
     ones from [Backtrace.Exn.most_recent] *)
  let traceback =
    Option.value_map backtrace ~f:of_ocaml_backtrace ~default:[] @ additional_traceback
  in
  let raise_py_err_with_traceback py_err msg =
    raise (Py.Err_with_traceback (py_err, msg, traceback))
  in
  match exn with
  | Py.E_with_traceback _ | Py.Err_with_traceback _ -> raise exn
  | Py.E (py_err_type, py_err, py_tb) ->
    let original_traceback = of_pyobject_traceback py_tb in
    raise (Py.E_with_traceback (py_err_type, py_err, original_traceback @ traceback))
  | Py.Err (py_err, msg) -> raise_py_err_with_traceback py_err msg
  | exn ->
    raise_py_err_with_traceback
      ValueError
      [%string "OCaml error: %{Exn.to_string_mach exn}"]
;;
