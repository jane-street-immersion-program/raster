open! Core
open! Async

type t =
  { width : int
  ; height : int
  ; max_val : int
  ; image : Pixel.t array
  }
[@@deriving sexp_of, fields ~getters]

let load_ppm ~filename =
  let lines = In_channel.read_lines filename in
  (* Magic number for plain ppm format *)
  let lines =
    match lines with
    | "P3" :: rest -> rest
    | (_ : string list) ->
      raise_s [%message "Invalid magic number, plain PPM file should begin with P3"]
  in
  let parse_wh line =
    match String.split ~on:' ' line with
    | [ w; h ] -> Int.of_string w, Int.of_string h
    | (_ : string list) -> raise_s [%message "invalid dimensions line" (line : string)]
  in
  let (width, height), lines =
    match lines with
    | dimensions :: rest -> parse_wh dimensions, rest
    | (_ : string list) ->
      raise_s [%message "Reached the end of the file before dimensions line"]
  in
  let max_val, lines =
    match lines with
    | v :: rest -> Int.of_string v, rest
    | (_ : string list) ->
      raise_s [%message "Reached the end of the file before max value line"]
  in
  if max_val < 0 then raise_s [%message "max pixel value must be positive"];
  let flat_image = Array.create ~len:(width * height * 3) 0 in
  let idx = ref 0 in
  List.iter lines ~f:(fun line ->
    String.strip line
    |> String.split ~on:' '
    |> List.iter ~f:(fun channel ->
      let channel_val = Int.of_string channel in
      if channel_val > max_val || channel_val < 0
      then
        raise_s [%message "invalid pixel color value" (channel_val : int) (max_val : int)];
      flat_image.(!idx) <- channel_val;
      idx := !idx + 1));
  if !idx < Array.length flat_image
  then raise_s [%message "Reached end of file before reading all pixels"];
  let image =
    Array.filter_mapi flat_image ~f:(fun idx _ ->
      if idx % 3 = 0
      then Some (flat_image.(idx), flat_image.(idx + 1), flat_image.(idx + 2))
      else None)
  in
  { image; width; height; max_val }
;;

let save_ppm t ~filename =
  Out_channel.with_file filename ~f:(fun out ->
    let dimensions = sprintf "%d %d" t.width t.height in
    let lines = [ "P3"; dimensions; Int.to_string t.max_val ] in
    Out_channel.output_lines out lines;
    Array.iteri t.image ~f:(fun idx ((r, g, b) as pixel) ->
      if r < 0 || r > t.max_val || g < 0 || g > t.max_val || b < 0 || b > t.max_val
      then raise_s [%message "invalid pixel value in output image" (pixel : Pixel.t)];
      let sep =
        match idx with
        | 0 -> ""
        | _ when idx % t.width = 0 -> "\n"
        | _ -> " "
      in
      Out_channel.output_string out [%string "%{sep}%{pixel#Pixel}"]);
    Out_channel.output_string out "\n")
;;

let boundary_check ?(for_slice = false) t ~x ~y =
  if x < 0 || x > t.width || ((not for_slice) && x = t.width)
  then
    raise_s [%message "x-coordinate outside the image" (x : int) ~width:(t.width : int)];
  if y < 0 || y > t.height || ((not for_slice) && y = t.height)
  then
    raise_s [%message "y-coordinate outside the image" (y : int) ~height:(t.height : int)];
  ()
;;

let xy_to_idx t ~x ~y = (y * t.width) + x

let idx_to_xy t idx =
  let y = idx / t.width in
  let x = idx % t.width in
  x, y
;;

let get t ~x ~y =
  boundary_check t ~x ~y;
  let idx = xy_to_idx t ~x ~y in
  t.image.(idx)
;;

let set t ~x ~y pixel =
  boundary_check t ~x ~y;
  let idx = xy_to_idx t ~x ~y in
  t.image.(idx) <- pixel
;;

let slice t ~x_start ~x_end ~y_start ~y_end =
  boundary_check t ~x:x_start ~y:y_start ~for_slice:true;
  boundary_check t ~x:x_end ~y:y_end ~for_slice:true;
  if x_start > x_end
  then raise_s [%message "x_start must be <= x_end" (x_start : int) (x_end : int)];
  if y_start > y_end
  then raise_s [%message "y_start must be <= y_end" (y_start : int) (y_end : int)];
  let width = x_end - x_start in
  let height = y_end - y_start in
  let start_idx = xy_to_idx t ~x:x_start ~y:y_start in
  let i_to_slice_idx i = start_idx + (i / width * t.width) + (i % width) in
  let image = Array.init (width * height) ~f:(fun i -> t.image.(i_to_slice_idx i)) in
  { image; width; height; max_val = t.max_val }
;;

let mean_pixel t =
  if Array.length t.image = 0
  then raise_s [%message "Cannot take the mean of an empty image"];
  let r, g, b = Array.sum (module Pixel) t.image ~f:Fn.id in
  let length = Array.length t.image in
  r / length, g / length, b / length
;;

let copy t =
  { image = Array.copy t.image; width = t.width; height = t.height; max_val = t.max_val }
;;

let map t ~(f : Pixel.t -> Pixel.t) =
  let new_image = Array.map t.image ~f in
  { t with image = new_image }
;;

let mapi t ~f =
  let new_image =
    Array.mapi t.image ~f:(fun idx pixel ->
      let x, y = idx_to_xy t idx in
      f ~x ~y pixel)
  in
  { t with image = new_image }
;;

let fold t ~init ~f = Array.fold ~init t.image ~f

let foldi t ~init ~f =
  Array.foldi ~init t.image ~f:(fun idx acc pixel ->
    let x, y = idx_to_xy t idx in
    f ~x ~y acc pixel)
;;

let make ?(max_val = 255) ~width ~height pixel =
  if width <= 0 || height <= 0
  then
    raise_s
      [%message
        "Invalid image dimensions: width and height must be positive"
          (width : int)
          (height : int)];
  { image = Array.create ~len:(width * height) pixel; width; height; max_val }
;;

let to_graphics_image t =
  let colors_flat = Array.map t.image ~f:Pixel.to_color in
  let rows = Array.make_matrix ~dimx:t.height ~dimy:t.width Graphics.black in
  for row = 0 to t.height - 1 do
    for col = 0 to t.width - 1 do
      let idx = xy_to_idx t ~x:col ~y:row in
      rows.(row).(col) <- colors_flat.(idx)
    done
  done;
  Graphics.make_image rows
;;

let of_graphics_image image =
  let rows = Graphics.dump_image image in
  let height = Array.length rows in
  let width = Array.length rows.(0) in
  let image = make ~width ~height Pixel.zero in
  for row = 0 to height - 1 do
    for col = 0 to width - 1 do
      let pixel = rows.(row).(col) in
      set image ~x:col ~y:row (Pixel.of_color pixel)
    done
  done;
  image
;;

let simple_test data ~f =
  Expect_test_helpers_async.with_temp_dir (fun dirname ->
    let filename =
      File_path.append
        (File_path.of_string dirname)
        (File_path.Relative.of_string "image.ppm")
      |> File_path.to_string
    in
    Out_channel.write_all filename ~data;
    f filename)
;;

let%expect_test "round trip" =
  let data =
    {|P3
2 2
65535
50000 0 0 0 50000 0
0 0 50000 50000 0 0
|}
  in
  simple_test data ~f:(fun filename ->
    let image = load_ppm ~filename in
    save_ppm image ~filename:(filename ^ ".out");
    let output = In_channel.read_all (filename ^ ".out") in
    [%test_result: string] output ~expect:data;
    return ())
;;

let%expect_test "invalid input images" =
  let%bind () =
    Expect_test_helpers_async.require_does_raise_async [%here] (fun () ->
      let data =
        {|P3
|}
      in
      simple_test data ~f:(fun filename ->
        let _image = load_ppm ~filename in
        return ()))
  in
  [%expect {| "Reached the end of the file before dimensions line" |}];
  let%bind () =
    Expect_test_helpers_async.require_does_raise_async [%here] (fun () ->
      let data =
        {|P3
abc
|}
      in
      simple_test data ~f:(fun filename ->
        let _image = load_ppm ~filename in
        return ()))
  in
  [%expect {| ("invalid dimensions line" (line abc)) |}];
  let%bind () =
    Expect_test_helpers_async.require_does_raise_async [%here] (fun () ->
      let data =
        {|P3
2 2
|}
      in
      simple_test data ~f:(fun filename ->
        let _image = load_ppm ~filename in
        return ()))
  in
  [%expect {| "Reached the end of the file before max value line" |}];
  let%bind () =
    Expect_test_helpers_async.require_does_raise_async [%here] (fun () ->
      let data =
        {|P3
2 2
-100
|}
      in
      simple_test data ~f:(fun filename ->
        let _image = load_ppm ~filename in
        return ()))
  in
  [%expect {| "max pixel value must be positive" |}];
  let%bind () =
    Expect_test_helpers_async.require_does_raise_async [%here] (fun () ->
      let data =
        {|XX
2 2
65535
50000 0 0 0 50000 0
0 0 50000 50000 0 0
|}
      in
      simple_test data ~f:(fun filename ->
        let _image = load_ppm ~filename in
        return ()))
  in
  [%expect {| "Invalid magic number, plain PPM file should begin with P3" |}];
  let%bind () =
    Expect_test_helpers_async.require_does_raise_async [%here] (fun () ->
      let data =
        {|P3
2 2
40000
50000 0 0 0 50000 0
0 0 50000 50000 0 0
|}
      in
      simple_test data ~f:(fun filename ->
        let _image = load_ppm ~filename in
        return ()))
  in
  [%expect
    {|
    ("invalid pixel color value"
      (channel_val 50000)
      (max_val     40000))
    |}];
  let%bind () =
    Expect_test_helpers_async.require_does_raise_async [%here] (fun () ->
      let data =
        {|P3
2 2
65535
50000 0 0 0 50000
0 0 50000 50000 0 0
|}
      in
      simple_test data ~f:(fun filename ->
        let _image = load_ppm ~filename in
        return ()))
  in
  [%expect {| "Reached end of file before reading all pixels" |}];
  return ()
;;

let%expect_test "get and set" =
  let data =
    {|P3
2 2
65535
50000 0 0 0 50000 0
0 0 50000 50000 0 0|}
  in
  simple_test data ~f:(fun filename ->
    let image = load_ppm ~filename in
    [%test_result: int * int * int] (get image ~x:0 ~y:0) ~expect:(50000, 0, 0);
    [%test_result: int * int * int] (get image ~x:1 ~y:0) ~expect:(0, 50000, 0);
    [%test_result: int * int * int] (get image ~x:0 ~y:1) ~expect:(0, 0, 50000);
    Expect_test_helpers_base.require_does_raise [%here] (fun () -> get image ~x:(-1) ~y:0);
    [%expect
      {|
      ("x-coordinate outside the image"
        (x     -1)
        (width 2))
      |}];
    set image ~x:0 ~y:0 (40000, 0, 0);
    set image ~x:1 ~y:0 (0, 40000, 0);
    set image ~x:0 ~y:1 (0, 0, 40000);
    [%test_result: int * int * int] (get image ~x:0 ~y:0) ~expect:(40000, 0, 0);
    [%test_result: int * int * int] (get image ~x:1 ~y:0) ~expect:(0, 40000, 0);
    [%test_result: int * int * int] (get image ~x:0 ~y:1) ~expect:(0, 0, 40000);
    Expect_test_helpers_base.require_does_raise [%here] (fun () ->
      set image ~y:100 ~x:0 (40000, 0, 0));
    [%expect
      {|
      ("y-coordinate outside the image"
        (y      100)
        (height 2))
      |}];
    return ())
;;

let%expect_test "slice" =
  let data =
    {|P3
2 2
65535
50000 0 0 0 50000 0
0 0 50000 50000 0 0|}
  in
  simple_test data ~f:(fun filename ->
    let image = load_ppm ~filename in
    let sliced_image = slice image ~x_start:0 ~x_end:1 ~y_start:0 ~y_end:2 in
    print_s [%sexp (sliced_image : t)];
    (* We expect the first column of the image to have been sliced out *)
    [%expect
      {| ((width 1) (height 2) (max_val 65535) (image ((50000 0 0) (0 0 50000)))) |}];
    (* Check that invalid indexes raise *)
    (* Negative index *)
    Expect_test_helpers_base.require_does_raise [%here] (fun () ->
      slice image ~x_start:(-1) ~x_end:1 ~y_start:0 ~y_end:2);
    [%expect
      {|
      ("x-coordinate outside the image"
        (x     -1)
        (width 2))
      |}];
    Expect_test_helpers_base.require_does_raise [%here] (fun () ->
      slice image ~x_start:0 ~x_end:1 ~y_start:0 ~y_end:(-2));
    [%expect
      {|
      ("y-coordinate outside the image"
        (y      -2)
        (height 2))
      |}];
    (* Start before end *)
    Expect_test_helpers_base.require_does_raise [%here] (fun () ->
      slice image ~x_start:1 ~x_end:0 ~y_start:0 ~y_end:2);
    [%expect
      {|
      ("x_start must be <= x_end"
        (x_start 1)
        (x_end   0))
      |}];
    Expect_test_helpers_base.require_does_raise [%here] (fun () ->
      slice image ~x_start:0 ~x_end:1 ~y_start:2 ~y_end:0);
    [%expect
      {|
      ("y_start must be <= y_end"
        (y_start 2)
        (y_end   0))
      |}];
    (* End too large *)
    Expect_test_helpers_base.require_does_raise [%here] (fun () ->
      slice image ~x_start:0 ~x_end:100 ~y_start:0 ~y_end:2);
    [%expect
      {|
      ("x-coordinate outside the image"
        (x     100)
        (width 2))
      |}];
    Expect_test_helpers_base.require_does_raise [%here] (fun () ->
      slice image ~x_start:0 ~x_end:0 ~y_start:0 ~y_end:200);
    [%expect
      {|
      ("y-coordinate outside the image"
        (y      200)
        (height 2))
      |}];
    return ())
;;

let%expect_test "mean" =
  let data =
    {|P3
2 2
65535
50000 0 0 0 50000 0
0 0 50000 50000 0 0|}
  in
  simple_test data ~f:(fun filename ->
    let image = load_ppm ~filename in
    let mean = mean_pixel image in
    print_s [%sexp (mean : Pixel.t)];
    (* 2 red + 1 green + 1 blue means we expect 25000 12500 12500 *)
    [%expect {| (25000 12500 12500) |}];
    (* Check that taking the mean of an empty image raises *)
    Expect_test_helpers_base.require_does_raise [%here] (fun () ->
      mean_pixel (slice image ~x_start:0 ~x_end:0 ~y_start:0 ~y_end:0));
    [%expect {| "Cannot take the mean of an empty image" |}];
    return ())
;;

let%expect_test "map and mapi" =
  let data =
    {|P3
2 2
65535
50000 0 0 0 50000 0
0 0 50000 50000 0 0|}
  in
  simple_test data ~f:(fun filename ->
    let image = load_ppm ~filename in
    print_s [%sexp (map image ~f:(fun (r, g, b) -> r - 1, g / 2, b + 1) : t)];
    [%expect
      {|
      ((width 2) (height 2) (max_val 65535)
       (image ((49999 0 1) (-1 25000 1) (-1 0 50001) (49999 0 1))))
      |}];
    print_s [%sexp (mapi image ~f:(fun ~x ~y _ -> x, y, x + y) : t)];
    [%expect
      {|
      ((width 2) (height 2) (max_val 65535)
       (image ((0 0 0) (1 0 1) (0 1 1) (1 1 2))))
      |}];
    return ())
;;

let%expect_test "fold and foldi" =
  let data =
    {|P3
2 2
65535
50000 0 0 0 50000 0
0 0 50000 50000 0 0|}
  in
  simple_test data ~f:(fun filename ->
    let image = load_ppm ~filename in
    print_s
      [%sexp
        (fold ~init:Pixel.zero image ~f:(fun acc pixel -> Pixel.(acc + pixel)) : Pixel.t)];
    [%expect {| (100000 50000 50000) |}];
    print_s
      [%sexp
        (foldi ~init:(0, 0) image ~f:(fun ~x ~y (xsum, ysum) _ -> xsum + x, ysum + y)
         : int * int)];
    [%expect {| (2 2) |}];
    return ())
;;
