let sz = 8192
let bytes = Bytes.create sz

let copy src dest =
  let src = Unix.openfile src [ O_RDONLY ] 0
  and dest = Unix.openfile dest [ O_WRONLY; O_CREAT; O_TRUNC ] 0o777 in
  let rec loop () =
    match Unix.read src bytes 0 sz with
    | 0 -> ()
    | r ->
      ignore (Unix.write dest bytes 0 r);
      loop ()
  in
  loop ();
  Unix.close src;
  Unix.close dest

let mkdirs root dirs =
  let rec loop path = function
    | [] -> path
    | hd :: tl ->
      let path = Printf.sprintf "%s%s%s" path Filename.dir_sep hd in
      if Sys.file_exists path
      then loop path tl
      else begin
        Sys.mkdir path 0o777;
        loop path tl
      end
  in
  loop root dirs

let () =
  let dest = Sys.argv.(1) in
  if not @@ Sys.file_exists dest then Sys.mkdir dest 0o777;
  for i = 2 to Array.length Sys.argv - 1 do
    let name = Filename.basename Sys.argv.(i)
    and dirs = Filename.(String.(split_on_char (get dir_sep 0) (dirname Sys.argv.(i)))) in
    let path = Printf.sprintf "%s/%s" (mkdirs dest dirs) name in
    ignore @@ copy Sys.argv.(i) path
  done
