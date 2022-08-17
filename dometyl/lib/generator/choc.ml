open! Base
open! Scad_ml

(* https://grabcad.com/library/kailh-1350-socket-2 *)
let kailh_socket =
  Scad.import_3d "../things/switches/choc_hotswap_socket.stl"
  |> Scad.translate (v3 7. 0. 0.)
  |> Scad.rotate (v3 (Float.pi /. 2.) 0. Float.pi)
  |> Scad.translate (v3 2.0 3.7 (-3.5))
  |> Scad.color ~alpha:0.4 Color.Silver

(* https://grabcad.com/library/kailh-low-profile-mechanical-keyboard-switch-1 *)
let switch =
  Scad.import_3d "../things/switches/kailh_choc.stl"
  |> Scad.rotate Float.(v3 (pi / 2.) 0. (pi / 2.))
  |> Scad.translate (v3 0. 0. 0.4)
  |> Scad.color ~alpha:0.5 Color.SkyBlue

module Hotswap = struct
  let make ~inner_w ~inner_h ~outer_w ~outer_h ~plate_thickness facing =
    let holder_thickness = 3.
    and hole_depth = 2.2 in
    let shallowness = hole_depth -. plate_thickness in
    (* hotswap socket cutout position *)
    let w = inner_w +. 3.
    and h = inner_h +. 3.
    and z = (holder_thickness +. hole_depth +. shallowness) /. -2.
    (* the bottom of the hole.  *)
    and socket_thickness = holder_thickness +. 0.5 (* plus printing error *)
    and pin_radius = 1.65
    and sign =
      match facing with
      | `North -> -1.
      | `South -> 1.
    in
    let socket_z = z -. 1.4 in
    let cutout =
      let edge_x = 0.2 +. (outer_w /. 2.)
      and edge_y = 0.2 +. (outer_h /. 2.) in
      let poly =
        Scad.polygon
        @@ List.map
             ~f:(fun (x, y) -> v2 (x *. sign) (y *. sign))
             [ -.edge_x, edge_y
             ; -5., 3.4
             ; 0.64, 3.4
             ; 1.19, 3.2
             ; 1.49, 3.
             ; 1.77, 2.7
             ; 2.29, 1.7
             ; 2.69, 1.3
             ; edge_x, 1.3
             ; edge_x, edge_y
             ; 7.2, edge_y
             ; 7.2, 6.12
             ; 4., 6.12
             ; 3.4, 6.12
             ; 3.15, 6.2
             ; 2.95, 6.3
             ; 2.65, 6.7
             ; 2.55, 7.0
             ; 2.55, 7.4
             ; 1.25, edge_y
             ; -5., edge_y
             ]
      and pin =
        Scad.translate
          (v3 0. (5.9 *. sign) 0.)
          (Scad.cylinder
             ~fn:30
             ~height:(z -. socket_z +. (holder_thickness /. 2.))
             pin_radius )
      in
      Scad.union
        [ poly |> Scad.linear_extrude ~center:true ~height:socket_thickness; pin ]
      |> Scad.translate (v3 0. 0. socket_z)
    in
    let hotswap =
      let led_cut = Scad.square ~center:true (v2 6. 6.) |> Scad.ytrans (-6. *. sign)
      and holes =
        let main = Scad.circle ~fn:30 1.75
        and pin = Scad.circle ~fn:30 pin_radius
        and friction = Scad.circle ~fn:30 1. in
        let plus = Scad.translate (v2 0. (5.9 *. sign)) pin
        and minus = Scad.translate (v2 (5. *. sign) (3.8 *. sign)) pin
        and fric_left = Scad.translate (v2 (-5.5) 0.) friction
        and fric_right = Scad.translate (v2 5.5 0.) friction in
        Scad.union [ main; plus; minus; fric_left; fric_right ]
      in
      Scad.difference (Scad.square ~center:true (v2 w h)) [ led_cut; holes ]
      |> Scad.linear_extrude ~center:true ~height:holder_thickness
      |> Scad.translate (v3 0. 0. z)
      |> Fn.flip Scad.difference [ cutout ]
    in
    ( ( if Float.(shallowness > 0.)
      then (
        let spacer =
          Scad.difference
            (Scad.square ~center:true (v2 w h))
            [ Scad.square ~center:true (v2 inner_w inner_h) ]
          |> Scad.linear_extrude ~height:shallowness
          |> Scad.translate (v3 0. 0. ((plate_thickness /. -2.) -. shallowness))
        in
        Scad.union [ hotswap; spacer ] )
      else hotswap )
    , cutout )
end

let teeth ~inner_w ~thickness hole =
  let depth = 0.9 in
  let block = Scad.cube ~center:true (v3 0.51 3.5 (thickness -. depth))
  and x = (inner_w /. 2.) +. 0.25
  and y = 3.5 in
  let nw = Scad.translate (v3 (-.x) y (-.depth)) block
  and sw = Scad.translate (v3 (-.x) (-.y) (-.depth)) block
  and ne = Scad.translate (v3 x y (-.depth)) block
  and se = Scad.translate (v3 x (-.y) (-.depth)) block in
  Scad.difference hole [ nw; sw; ne; se ]

let make_hole
    ?render
    ?cap
    ?hotswap
    ?(outer_w = 19.)
    ?(outer_h = 17.)
    ?(inner_w = 13.8)
    ?(inner_h = 13.8)
    ?(thickness = 4.)
    ?(cap_height = 5.)
    ?(cap_cutout_height = Some 0.8)
    ?(clearance = 2.)
    ?corner
    ?fn
    ()
  =
  let clearance, clip, cutout =
    match hotswap with
    | Some facing ->
      let swap, cutout =
        Hotswap.make ~inner_w ~inner_h ~outer_w ~outer_h ~plate_thickness:thickness facing
      in
      let clip hole = Scad.union [ teeth ~inner_w ~thickness hole; swap ] in
      clearance +. 1.5, clip, Some cutout
    | None        -> clearance, teeth ~inner_w ~thickness, None
  and cap_cutout =
    Option.map
      ~f:(fun h ->
        Scad.translate
          (v3 0. 0. (2. +. h +. (thickness /. 2.)))
          (Scad.cube ~center:true (v3 18.5 17.5 4.)) )
      cap_cutout_height
  in
  Key.(
    make
      ?render
      ?cap
      ?cutout:(Option.merge ~f:(fun a b -> Scad.union [ a; b ]) cutout cap_cutout)
      { outer_w
      ; outer_h
      ; inner_w
      ; inner_h
      ; thickness
      ; clip
      ; cap_height
      ; clearance
      ; corner
      ; fn
      })

let example_assembly
    ?(show_cutout = false)
    ?(show_switch = false)
    ?(show_socket = false)
    ?(show_cap = false)
    ()
  =
  let hole = make_hole ~hotswap:`South ~cap:Caps.MBK.mbk () in
  let cutout = Option.value_exn hole.cutout in
  let hole =
    Key.cutout_scad hole
    |> Scad.translate (v3 0. 0. (-2.))
    |> Scad.color ~alpha:0.5 Color.FireBrick
  and cutout =
    if show_cutout
    then Some (Scad.ztrans (-20.) cutout |> Scad.color Color.DarkGray ~alpha:0.5)
    else None
  and choc = Option.some_if show_switch switch
  and socket = Option.some_if show_socket kailh_socket
  and cap =
    Option.bind ~f:(fun c -> Option.some_if show_cap (Scad.ztrans (-2.) c)) hole.cap
  in
  Util.prepend_opt cutout [ hole ]
  |> Util.prepend_opt choc
  |> Util.prepend_opt socket
  |> Util.prepend_opt cap
  |> Scad.union
